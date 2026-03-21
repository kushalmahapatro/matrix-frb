//! File upload dedup store in a dedicated SQLCipher DB (`app/app_db.sqlite3`).
//! Uses the same passphrase (or none) as [crate::matrix::client::ClientConfig] for Matrix sqlite stores.
//!
//! ## `file_upload_cache`
//! One row per **SHA-256 of plaintext file bytes** (same file from different temp paths shares a row).
//!
//! - **Plain rooms**: `file_mxc` + optional thumbnail MXC columns; server dedup reuses plain media.
//! - **Encrypted rooms**: after a successful send, `e2ee_msgtype_json` holds serialized
//!   [`ruma::events::room::message::RoomMessageEventContent`] (decrypted shape) so another send can
//!   reuse the same encrypted media payload without re-uploading ciphertext.
//!
//! Plain and E2EE payloads can both be present on one row (merge on write); each send path only
//! updates its half and preserves the other.
//!
//! Thumbnail matching uses `thumb_plaintext_sha256` (and legacy `thumb_content_sha256` on
//! `CachedThumbnail`) so a new JPEG thumb does not reuse old thumbnail metadata.
//!
//! **`e2ee_thumbnail_json`** stores the Matrix thumbnail payload for encrypted rooms: either
//! `thumbnail_url` (plain MXC) or `thumbnail_file` ([`ruma::events::room::EncryptedFile`]) plus
//! optional `thumbnail_info`, so clients can inspect MXC + encryption material without parsing the
//! full `e2ee_msgtype_json`.
//!
//! On iOS, the file is typically `Documents/app/app_db.sqlite3` under [ClientConfig::session_path].

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use rusqlite::{params, OptionalExtension};
use tracing;

/// Directory under the session path holding the app database file.
const APP_STORE_DIR: &str = "app";
/// Encrypted app database filename (separate from crypto/state/event_cache stores).
const APP_DB_FILE: &str = "app_db.sqlite3";

/// Stored thumbnail metadata (for event `info` when reusing a cached MXC).
#[derive(Debug, Clone)]
pub struct CachedThumbnail {
    pub mxc: String,
    pub width: u64,
    pub height: u64,
    pub size: u64,
    pub mimetype: String,
    /// SHA-256 hex of uploaded thumbnail bytes. Used with the main file hash so a new JPEG thumb
    /// does not reuse an old `thumbnail_url` MXC (wrong preview / encryption mismatch risk).
    pub content_sha256_hex: Option<String>,
}

#[derive(Debug, Clone)]
pub struct CachedEntry {
    pub sha256_hex: String,
    /// Plain MXC URI; empty string means no plain-room cache for this hash.
    pub file_mxc: String,
    pub thumbnail: Option<CachedThumbnail>,
    /// Serialized [`ruma::events::room::message::RoomMessageEventContent`] for E2EE reuse (`msgtype` only).
    pub e2ee_msgtype_json: Option<String>,
    /// JSON: `thumbnail_url` and/or `thumbnail_file` + optional `thumbnail_info` (E2EE thumbnail on the event).
    pub e2ee_thumbnail_json: Option<String>,
    /// SHA-256 hex of thumbnail **plaintext** JPEG bytes (matches incoming app-generated thumb).
    pub thumb_plaintext_sha256: Option<String>,
    pub room_id: String,
    pub event_id: Option<String>,
}

pub struct FileUploadCache {
    conn: Arc<Mutex<rusqlite::Connection>>,
}

impl FileUploadCache {
    /// Open or create the app SQLCipher database under `session_path/app/app_db.sqlite3`.
    /// `passphrase` must match the one used for Matrix `crypto` / `state` / `event_cache` stores.
    pub async fn open(
        session_path: impl AsRef<Path>,
        passphrase: Option<&str>,
    ) -> Result<Self, String> {
        let session_path = session_path.as_ref().to_path_buf();
        let app_dir = session_path.join(APP_STORE_DIR);
        tokio::fs::create_dir_all(&app_dir)
            .await
            .map_err(|e| e.to_string())?;
        let db_path = app_dir.join(APP_DB_FILE);
        let passphrase = passphrase.map(str::to_string);

        tokio::task::spawn_blocking(move || Self::open_sync(db_path, passphrase.as_deref()))
            .await
            .map_err(|e| e.to_string())?
    }

    fn create_table_v2(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        conn.execute_batch(
            r#"
            CREATE TABLE file_upload_cache (
                sha256_hex TEXT PRIMARY KEY NOT NULL,
                file_mxc TEXT NOT NULL,
                thumb_mxc TEXT,
                thumb_width INTEGER,
                thumb_height INTEGER,
                thumb_size INTEGER,
                thumb_mimetype TEXT,
                thumb_content_sha256 TEXT,
                room_id TEXT NOT NULL DEFAULT '',
                event_id TEXT,
                e2ee_msgtype_json TEXT,
                thumb_plaintext_sha256 TEXT,
                e2ee_thumbnail_json TEXT
            );
            "#,
        )
    }

    fn open_sync(db_path: PathBuf, passphrase: Option<&str>) -> Result<Self, String> {
        let conn = rusqlite::Connection::open(&db_path).map_err(|e| e.to_string())?;
        if let Some(p) = passphrase {
            conn.pragma_update(None, "key", p)
                .map_err(|e| e.to_string())?;
        }
        conn.query_row("SELECT 1", [], |_| Ok(()))
            .map_err(|e| format!("app_fb database key or open failed: {e}"))?;

        conn.execute_batch(
            r#"
            PRAGMA foreign_keys = ON;
            PRAGMA journal_mode = WAL;
            "#,
        )
        .map_err(|e| e.to_string())?;

        let table_exists: i64 = conn
            .query_row(
                "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='file_upload_cache'",
                [],
                |r| r.get(0),
            )
            .map_err(|e| e.to_string())?;

        if table_exists == 0 {
            Self::create_table_v2(&conn).map_err(|e| e.to_string())?;
        } else {
            let cols = Self::table_column_names(&conn).map_err(|e| e.to_string())?;
            if cols.iter().any(|c| c == "path") {
                Self::migrate_add_room_event_columns(&conn).map_err(|e| e.to_string())?;
                Self::migrate_path_pk_to_sha256(&conn).map_err(|e| e.to_string())?;
            }
            Self::migrate_add_thumb_content_sha256(&conn).map_err(|e| e.to_string())?;
            Self::migrate_add_e2ee_unified_columns(&conn).map_err(|e| e.to_string())?;
            Self::migrate_add_e2ee_thumbnail_json(&conn).map_err(|e| e.to_string())?;
        }

        Ok(Self {
            conn: Arc::new(Mutex::new(conn)),
        })
    }

    fn table_column_names(conn: &rusqlite::Connection) -> rusqlite::Result<Vec<String>> {
        let mut stmt = conn.prepare("PRAGMA table_info(file_upload_cache)")?;
        let cols: Vec<String> = stmt
            .query_map([], |r| r.get::<_, String>(1))?
            .filter_map(|x| x.ok())
            .collect();
        Ok(cols)
    }

    fn migrate_add_thumb_content_sha256(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        let cols = Self::table_column_names(conn)?;
        if !cols.iter().any(|c| c == "thumb_content_sha256") {
            conn.execute(
                "ALTER TABLE file_upload_cache ADD COLUMN thumb_content_sha256 TEXT",
                [],
            )?;
        }
        Ok(())
    }

    fn migrate_add_e2ee_unified_columns(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        let cols = Self::table_column_names(conn)?;
        if !cols.iter().any(|c| c == "e2ee_msgtype_json") {
            conn.execute(
                "ALTER TABLE file_upload_cache ADD COLUMN e2ee_msgtype_json TEXT",
                [],
            )?;
        }
        if !cols.iter().any(|c| c == "thumb_plaintext_sha256") {
            conn.execute(
                "ALTER TABLE file_upload_cache ADD COLUMN thumb_plaintext_sha256 TEXT",
                [],
            )?;
        }
        Ok(())
    }

    fn migrate_add_e2ee_thumbnail_json(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        let cols = Self::table_column_names(conn)?;
        if !cols.iter().any(|c| c == "e2ee_thumbnail_json") {
            conn.execute(
                "ALTER TABLE file_upload_cache ADD COLUMN e2ee_thumbnail_json TEXT",
                [],
            )?;
        }
        Ok(())
    }

    fn migrate_add_room_event_columns(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        let mut cols = Self::table_column_names(conn)?;
        if !cols.iter().any(|c| c == "room_id") {
            conn.execute(
                "ALTER TABLE file_upload_cache ADD COLUMN room_id TEXT NOT NULL DEFAULT ''",
                [],
            )?;
            cols = Self::table_column_names(conn)?;
        }
        if !cols.iter().any(|c| c == "event_id") {
            conn.execute("ALTER TABLE file_upload_cache ADD COLUMN event_id TEXT", [])?;
        }
        Ok(())
    }

    /// Legacy schema used `path` as PK; migrate to `sha256_hex` PK (one row per file content).
    fn migrate_path_pk_to_sha256(conn: &rusqlite::Connection) -> rusqlite::Result<()> {
        conn.execute_batch(
            r#"
            ALTER TABLE file_upload_cache RENAME TO file_upload_cache_legacy;
            CREATE TABLE file_upload_cache (
                sha256_hex TEXT PRIMARY KEY NOT NULL,
                file_mxc TEXT NOT NULL,
                thumb_mxc TEXT,
                thumb_width INTEGER,
                thumb_height INTEGER,
                thumb_size INTEGER,
                thumb_mimetype TEXT,
                thumb_content_sha256 TEXT,
                room_id TEXT NOT NULL DEFAULT '',
                event_id TEXT,
                e2ee_msgtype_json TEXT,
                thumb_plaintext_sha256 TEXT,
                e2ee_thumbnail_json TEXT
            );
            INSERT INTO file_upload_cache (
                sha256_hex, file_mxc,
                thumb_mxc, thumb_width, thumb_height, thumb_size, thumb_mimetype,
                thumb_content_sha256,
                room_id, event_id,
                e2ee_msgtype_json, thumb_plaintext_sha256, e2ee_thumbnail_json
            )
            SELECT o.sha256_hex, o.file_mxc,
                   o.thumb_mxc, o.thumb_width, o.thumb_height, o.thumb_size, o.thumb_mimetype,
                   NULL,
                   o.room_id, o.event_id,
                   NULL, NULL, NULL
            FROM file_upload_cache_legacy o
            INNER JOIN (
                SELECT sha256_hex, MAX(rowid) AS mx
                FROM file_upload_cache_legacy
                GROUP BY sha256_hex
            ) x ON o.sha256_hex = x.sha256_hex AND o.rowid = x.mx;
            DROP TABLE file_upload_cache_legacy;
            "#,
        )
    }

    fn upsert_in_tx(tx: &rusqlite::Transaction<'_>, entry: &CachedEntry) -> rusqlite::Result<()> {
        let (tm, tw, th, ts, tmt, tsha) = match &entry.thumbnail {
            Some(t) => (
                Some(t.mxc.as_str()),
                Some(t.width as i64),
                Some(t.height as i64),
                Some(t.size as i64),
                Some(t.mimetype.as_str()),
                t.content_sha256_hex.as_deref(),
            ),
            None => (None, None, None, None, None, None),
        };
        tx.execute(
            r#"
            INSERT INTO file_upload_cache (
                sha256_hex, file_mxc,
                thumb_mxc, thumb_width, thumb_height, thumb_size, thumb_mimetype,
                thumb_content_sha256,
                room_id, event_id,
                e2ee_msgtype_json, thumb_plaintext_sha256, e2ee_thumbnail_json
            ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13)
            ON CONFLICT(sha256_hex) DO UPDATE SET
                file_mxc = excluded.file_mxc,
                thumb_mxc = excluded.thumb_mxc,
                thumb_width = excluded.thumb_width,
                thumb_height = excluded.thumb_height,
                thumb_size = excluded.thumb_size,
                thumb_mimetype = excluded.thumb_mimetype,
                thumb_content_sha256 = excluded.thumb_content_sha256,
                room_id = excluded.room_id,
                event_id = excluded.event_id,
                e2ee_msgtype_json = excluded.e2ee_msgtype_json,
                thumb_plaintext_sha256 = excluded.thumb_plaintext_sha256,
                e2ee_thumbnail_json = excluded.e2ee_thumbnail_json
            "#,
            params![
                entry.sha256_hex,
                entry.file_mxc,
                tm,
                tw,
                th,
                ts,
                tmt,
                tsha,
                entry.room_id,
                entry.event_id,
                entry.e2ee_msgtype_json,
                entry.thumb_plaintext_sha256,
                entry.e2ee_thumbnail_json,
            ],
        )?;
        Ok(())
    }

    fn row_to_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<CachedEntry> {
        let thumb_mxc: Option<String> = row.get(2)?;
        let tw: Option<i64> = row.get(3)?;
        let th: Option<i64> = row.get(4)?;
        let ts: Option<i64> = row.get(5)?;
        let tmt: Option<String> = row.get(6)?;
        let tsha: Option<String> = row.get(7)?;
        let thumbnail = match (thumb_mxc, tw, th, ts, tmt) {
            (Some(mxc), Some(w), Some(h), Some(s), Some(mt)) => Some(CachedThumbnail {
                mxc,
                width: w as u64,
                height: h as u64,
                size: s as u64,
                mimetype: mt,
                content_sha256_hex: tsha,
            }),
            _ => None,
        };
        let room_id: String = row.get(8)?;
        let event_id: Option<String> = row.get(9)?;
        let e2ee_msgtype_json: Option<String> = row.get(10)?;
        let thumb_plaintext_sha256: Option<String> = row.get(11)?;
        let e2ee_thumbnail_json: Option<String> = row.get(12)?;
        Ok(CachedEntry {
            sha256_hex: row.get(0)?,
            file_mxc: row.get(1)?,
            thumbnail,
            e2ee_msgtype_json,
            e2ee_thumbnail_json,
            thumb_plaintext_sha256,
            room_id,
            event_id,
        })
    }

    pub async fn get_by_sha256(&self, sha256_hex: &str) -> Option<CachedEntry> {
        let conn = Arc::clone(&self.conn);
        let sha256_hex = sha256_hex.to_string();
        tokio::task::spawn_blocking(move || {
            let g = conn.lock().ok()?;
            match g.query_row(
                r#"SELECT sha256_hex, file_mxc,
                          thumb_mxc, thumb_width, thumb_height, thumb_size, thumb_mimetype,
                          thumb_content_sha256,
                          room_id, event_id,
                          e2ee_msgtype_json, thumb_plaintext_sha256, e2ee_thumbnail_json
                   FROM file_upload_cache WHERE sha256_hex = ?1"#,
                params![sha256_hex],
                Self::row_to_entry,
            )
            .optional()
            {
                Ok(v) => v,
                Err(e) => {
                    tracing::warn!(
                        target: "matrix.file_upload_cache",
                        error = %e,
                        "file_upload_cache SELECT failed (reopen DB after app update if schema is stale)"
                    );
                    None
                }
            }
        })
        .await
        .ok()?
    }

    /// Merge `incoming` with any existing row: preserves `e2ee_msgtype_json` when the incoming
    /// payload omits it, and preserves plain `file_mxc` / thumbnail when incoming `file_mxc` is empty.
    pub async fn put_merging_prior(&self, incoming: CachedEntry) -> Result<(), String> {
        let prior = self.get_by_sha256(&incoming.sha256_hex).await;
        let merged = merge_cached_entry(prior, incoming);
        self.put(merged).await
    }

    pub async fn put(&self, entry: CachedEntry) -> Result<(), String> {
        let conn = Arc::clone(&self.conn);
        tokio::task::spawn_blocking(move || {
            let mut g = conn
                .lock()
                .map_err(|_| "file_upload_cache db mutex poisoned")?;
            let tx = g.transaction().map_err(|e| e.to_string())?;
            Self::upsert_in_tx(&tx, &entry).map_err(|e| e.to_string())?;
            tx.commit().map_err(|e| e.to_string())?;
            Ok::<(), String>(())
        })
        .await
        .map_err(|e| e.to_string())?
    }

    pub async fn remove_by_sha256(&self, sha256_hex: &str) -> Result<(), String> {
        let conn = Arc::clone(&self.conn);
        let sha256_hex = sha256_hex.to_string();
        tokio::task::spawn_blocking(move || {
            let g = conn
                .lock()
                .map_err(|_| "file_upload_cache db mutex poisoned")?;
            g.execute(
                "DELETE FROM file_upload_cache WHERE sha256_hex = ?1",
                params![sha256_hex],
            )
            .map_err(|e| e.to_string())?;
            Ok::<(), String>(())
        })
        .await
        .map_err(|e| e.to_string())?
    }

    /// Drop any row whose last plain-send `event_id` matches (message was redacted).
    pub async fn remove_by_event_id(&self, event_id: &str) -> Result<(), String> {
        let conn = Arc::clone(&self.conn);
        let event_id = event_id.to_string();
        tokio::task::spawn_blocking(move || {
            let g = conn
                .lock()
                .map_err(|_| "file_upload_cache db mutex poisoned")?;
            g.execute(
                "DELETE FROM file_upload_cache WHERE event_id = ?1",
                params![event_id],
            )
            .map_err(|e| e.to_string())?;
            Ok::<(), String>(())
        })
        .await
        .map_err(|e| e.to_string())?
    }
}

fn merge_cached_entry(prior: Option<CachedEntry>, mut incoming: CachedEntry) -> CachedEntry {
    let Some(mut p) = prior else {
        return incoming;
    };
    if incoming.e2ee_msgtype_json.is_none() {
        incoming.e2ee_msgtype_json = p.e2ee_msgtype_json.take();
    }
    if incoming.file_mxc.is_empty() {
        incoming.file_mxc = std::mem::take(&mut p.file_mxc);
        if incoming.thumbnail.is_none() {
            incoming.thumbnail = p.thumbnail.take();
        }
    }
    if incoming.thumb_plaintext_sha256.is_none() {
        incoming.thumb_plaintext_sha256 = p.thumb_plaintext_sha256.take();
    }
    if incoming.e2ee_thumbnail_json.is_none() {
        incoming.e2ee_thumbnail_json = p.e2ee_thumbnail_json.take();
    }
    incoming
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn put_get_roundtrip_by_sha256() {
        let base = std::env::temp_dir().join(format!("matrix_fuc_{}", std::process::id()));
        let _ = tokio::fs::remove_dir_all(&base).await;
        let cache = FileUploadCache::open(&base, None).await.expect("open cache");

        let entry = CachedEntry {
            sha256_hex: "abc".to_string(),
            file_mxc: "mxc://example.org/foo".to_string(),
            thumbnail: None,
            e2ee_msgtype_json: None,
            e2ee_thumbnail_json: None,
            thumb_plaintext_sha256: None,
            room_id: "!r:example.org".to_string(),
            event_id: Some("$e:example.org".to_string()),
        };
        cache.put(entry.clone()).await.expect("put");
        let got = cache
            .get_by_sha256("abc")
            .await
            .expect("get");
        assert_eq!(got.file_mxc, entry.file_mxc);
        assert_eq!(got.room_id, entry.room_id);

        let _ = tokio::fs::remove_dir_all(&base).await;
    }
}

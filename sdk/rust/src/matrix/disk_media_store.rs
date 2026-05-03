//! Persistent decrypted media cache on disk (thumbnails + full files).
//!
//! Matrix SDK defaults to [`MemoryMediaStore`] (small in-memory LRU). This store writes
//! [`MediaRequestParameters::unique_key`]-addressed blobs under a user-provided root so previews
//! survive process restarts without putting media in the crypto/state SQLite DB.

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
    sync::{Arc, RwLock as StdRwLock},
};

use async_trait::async_trait;
use matrix_sdk::cross_process_lock::{
    memory_store_helper::{Lease, try_take_leased_lock},
    CrossProcessLockGeneration,
};
use matrix_sdk_base::media::{
    MediaFormat, MediaRequestParameters, UniqueKey as _,
    store::{
        IgnoreMediaRetentionPolicy, MediaRetentionPolicy, MediaService, MediaStore,
        MediaStoreError, MediaStoreInner,
    },
};
use ruma::{MxcUri, time::SystemTime};
use sha2::{Digest, Sha256};
use tokio::fs;
use tracing::warn;

fn sanitize_path_segment(s: &str) -> String {
    s.chars()
        .map(|c| match c {
            '/' | '\\' | ':' | '?' | '*' | '<' | '>' | '|' | '"' => '_',
            c if c.is_control() => '_',
            c => c,
        })
        .collect()
}

/// Stable file name for a cache entry; keeps MXC host + id readable when possible.
fn file_name_for_request(request: &MediaRequestParameters) -> String {
    let uri_part = sanitize_path_segment(request.uri().as_str());
    let fmt_part = request.format.unique_key();
    let combined = format!("{uri_part}_{fmt_part}");
    if combined.len() <= 220 {
        format!("{combined}.bin")
    } else {
        let mut hasher = Sha256::new();
        hasher.update(combined.as_bytes());
        let h = hex::encode(hasher.finalize());
        let up = uri_part.chars().take(100).collect::<String>();
        format!("{up}__{}.bin", &h[..32])
    }
}

fn uri_file_prefix(uri: &MxcUri) -> String {
    format!("{}_", sanitize_path_segment(uri.as_str()))
}

#[derive(Debug)]
struct DiskMediaStoreInner {
    leases: HashMap<String, Lease>,
    media_retention_policy: Option<MediaRetentionPolicy>,
    last_media_cleanup_time: SystemTime,
}

/// Filesystem-backed media cache under [Self::open]`(root)`.
#[derive(Debug, Clone)]
pub struct DiskMediaStore {
    thumbnails_dir: PathBuf,
    /// Full decrypted files (`MediaFormat::File`).
    media_full_dir: PathBuf,
    inner: Arc<StdRwLock<DiskMediaStoreInner>>,
    media_service: MediaService,
}

impl DiskMediaStore {
    /// Opens or creates the cache layout:
    /// - `{root}/thumbnails/`
    /// - `{root}/media/full/` — SDK cache for full files
    /// - `{root}/media/{images,videos,audios,docs,others}/` — empty dirs reserved for future typed prefetch
    pub async fn open(root: impl AsRef<Path>) -> Result<Self, String> {
        let root = root.as_ref().to_path_buf();
        let thumbnails_dir = root.join("thumbnails");
        let media = root.join("media");
        let media_full_dir = media.join("full");
        for d in [
            &thumbnails_dir,
            &media_full_dir,
            &media.join("images"),
            &media.join("videos"),
            &media.join("audios"),
            &media.join("docs"),
            &media.join("others"),
        ] {
            fs::create_dir_all(d)
                .await
                .map_err(|e| format!("create_dir_all {}: {e}", d.display()))?;
        }

        let last_media_cleanup_time = SystemTime::now();
        let media_service = MediaService::new();
        media_service.restore(None, Some(last_media_cleanup_time));

        Ok(Self {
            thumbnails_dir,
            media_full_dir,
            inner: Arc::new(StdRwLock::new(DiskMediaStoreInner {
                leases: HashMap::new(),
                media_retention_policy: None,
                last_media_cleanup_time,
            })),
            media_service,
        })
    }

    fn path_for(&self, request: &MediaRequestParameters) -> PathBuf {
        let name = file_name_for_request(request);
        match &request.format {
            MediaFormat::Thumbnail(_) => self.thumbnails_dir.join(&name),
            MediaFormat::File => self.media_full_dir.join(&name),
        }
    }

    async fn read_dir_pick_uri_match(
        dir: &Path,
        uri_prefix: &str,
    ) -> Result<Option<Vec<u8>>, MediaStoreError> {
        let mut rd = match fs::read_dir(dir).await {
            Ok(r) => r,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(e) => return Err(MediaStoreError::backend(e)),
        };

        while let Ok(Some(entry)) = rd.next_entry().await {
            let name = entry.file_name().to_string_lossy().into_owned();
            if !name.ends_with(".bin") {
                continue;
            }
            if !name.starts_with(uri_prefix) {
                continue;
            }
            let path = entry.path();
            match fs::read(&path).await {
                Ok(data) => {
                    return Ok(Some(data));
                }
                Err(e) => {
                    warn!(path = %path.display(), "disk media: read failed: {e}");
                }
            }
        }
        Ok(None)
    }
}

#[cfg_attr(not(target_family = "wasm"), async_trait)]
impl MediaStore for DiskMediaStore {
    type Error = MediaStoreError;

    async fn try_take_leased_lock(
        &self,
        lease_duration_ms: u32,
        key: &str,
        holder: &str,
    ) -> Result<Option<CrossProcessLockGeneration>, MediaStoreError>
    {
        let mut inner = self.inner.write().unwrap();
        Ok(try_take_leased_lock(&mut inner.leases, lease_duration_ms, key, holder))
    }

    async fn add_media_content(
        &self,
        request: &MediaRequestParameters,
        content: Vec<u8>,
        ignore_policy: IgnoreMediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        self.media_service
            .add_media_content(self, request, content, ignore_policy)
            .await
    }

    async fn replace_media_key(
        &self,
        from: &MediaRequestParameters,
        to: &MediaRequestParameters,
    ) -> Result<(), MediaStoreError> {
        let old_path = self.path_for(from);
        let new_path = self.path_for(to);
        if fs::metadata(&old_path).await.is_err() {
            return Ok(());
        }
        if let Some(parent) = new_path.parent() {
            fs::create_dir_all(parent)
                .await
                .map_err(MediaStoreError::backend)?;
        }
        fs::rename(&old_path, &new_path)
            .await
            .map_err(MediaStoreError::backend)?;
        Ok(())
    }

    async fn get_media_content(
        &self,
        request: &MediaRequestParameters,
    ) -> Result<Option<Vec<u8>>, MediaStoreError> {
        self.media_service.get_media_content(self, request).await
    }

    async fn remove_media_content(
        &self,
        request: &MediaRequestParameters,
    ) -> Result<(), MediaStoreError> {
        let path = self.path_for(request);
        let _ = fs::remove_file(path).await;
        Ok(())
    }

    async fn get_media_content_for_uri(
        &self,
        uri: &MxcUri,
    ) -> Result<Option<Vec<u8>>, MediaStoreError> {
        self.media_service.get_media_content_for_uri(self, uri).await
    }

    async fn remove_media_content_for_uri(&self, uri: &MxcUri) -> Result<(), MediaStoreError> {
        let prefix = uri_file_prefix(uri);
        for dir in [&self.thumbnails_dir, &self.media_full_dir] {
            let mut rd = match fs::read_dir(dir).await {
                Ok(r) => r,
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                Err(e) => return Err(MediaStoreError::backend(e)),
            };
            while let Ok(Some(entry)) = rd.next_entry().await {
                let name = entry.file_name().to_string_lossy().into_owned();
                if name.starts_with(&prefix) && name.ends_with(".bin") {
                    let _ = fs::remove_file(entry.path()).await;
                }
            }
        }
        Ok(())
    }

    async fn set_media_retention_policy(
        &self,
        policy: MediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        self.media_service.set_media_retention_policy(self, policy).await
    }

    fn media_retention_policy(&self) -> MediaRetentionPolicy {
        self.media_service.media_retention_policy()
    }

    async fn set_ignore_media_retention_policy(
        &self,
        _request: &MediaRequestParameters,
        _ignore_policy: IgnoreMediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        Ok(())
    }

    async fn clean(&self) -> Result<(), MediaStoreError> {
        self.media_service.clean(self).await
    }

    async fn optimize(&self) -> Result<(), MediaStoreError> {
        Ok(())
    }

    async fn get_size(&self) -> Result<Option<usize>, MediaStoreError> {
        let mut total: usize = 0;
        for dir in [&self.thumbnails_dir, &self.media_full_dir] {
            let mut stack = vec![dir.clone()];
            while let Some(d) = stack.pop() {
                let mut rd = match fs::read_dir(&d).await {
                    Ok(r) => r,
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(MediaStoreError::backend(e)),
                };
                while let Ok(Some(entry)) = rd.next_entry().await {
                    let p = entry.path();
                    let meta = match entry.metadata().await {
                        Ok(m) => m,
                        Err(_) => continue,
                    };
                    if meta.is_dir() {
                        stack.push(p);
                    } else if meta.is_file() {
                        total = total.saturating_add(meta.len() as usize);
                    }
                }
            }
        }
        Ok(Some(total))
    }
}

#[cfg_attr(not(target_family = "wasm"), async_trait)]
impl MediaStoreInner for DiskMediaStore {
    type Error = MediaStoreError;

    async fn media_retention_policy_inner(
        &self,
    ) -> Result<Option<MediaRetentionPolicy>, MediaStoreError> {
        Ok(self.inner.read().unwrap().media_retention_policy)
    }

    async fn set_media_retention_policy_inner(
        &self,
        policy: MediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        self.inner.write().unwrap().media_retention_policy = Some(policy);
        Ok(())
    }

    async fn add_media_content_inner(
        &self,
        request: &MediaRequestParameters,
        data: Vec<u8>,
        _current_time: SystemTime,
        policy: MediaRetentionPolicy,
        ignore_policy: IgnoreMediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        let ignore_policy = ignore_policy.is_yes();
        if !ignore_policy && policy.exceeds_max_file_size(data.len() as u64) {
            return Ok(());
        }

        self.remove_media_content(request).await?;

        let path = self.path_for(request);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .await
                .map_err(MediaStoreError::backend)?;
        }
        fs::write(&path, &data).await.map_err(MediaStoreError::backend)?;
        Ok(())
    }

    async fn set_ignore_media_retention_policy_inner(
        &self,
        _request: &MediaRequestParameters,
        _ignore_policy: IgnoreMediaRetentionPolicy,
    ) -> Result<(), MediaStoreError> {
        Ok(())
    }

    async fn get_media_content_inner(
        &self,
        request: &MediaRequestParameters,
        _current_time: SystemTime,
    ) -> Result<Option<Vec<u8>>, MediaStoreError> {
        let path = self.path_for(request);
        match fs::read(&path).await {
            Ok(data) => Ok(Some(data)),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(e) => Err(MediaStoreError::backend(e)),
        }
    }

    async fn get_media_content_for_uri_inner(
        &self,
        uri: &MxcUri,
        _current_time: SystemTime,
    ) -> Result<Option<Vec<u8>>, MediaStoreError> {
        let prefix = uri_file_prefix(uri);
        if let Some(b) = Self::read_dir_pick_uri_match(&self.thumbnails_dir, &prefix).await? {
            return Ok(Some(b));
        }
        Self::read_dir_pick_uri_match(&self.media_full_dir, &prefix).await
    }

    async fn clean_inner(
        &self,
        policy: MediaRetentionPolicy,
        current_time: SystemTime,
    ) -> Result<(), MediaStoreError> {
        if !policy.has_limitations() {
            return Ok(());
        }

        for dir in [&self.thumbnails_dir, &self.media_full_dir] {
            let mut stack = vec![dir.clone()];
            while let Some(d) = stack.pop() {
                let mut rd = match fs::read_dir(&d).await {
                    Ok(r) => r,
                    Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                    Err(e) => return Err(MediaStoreError::backend(e)),
                };
                while let Ok(Some(entry)) = rd.next_entry().await {
                    let path = entry.path();
                    let meta = match entry.metadata().await {
                        Ok(m) => m,
                        Err(_) => continue,
                    };
                    if meta.is_dir() {
                        stack.push(path);
                        continue;
                    }
                    if !meta.is_file() || !path.extension().is_some_and(|e| e == "bin") {
                        continue;
                    }

                    let len = meta.len();
                    let last = meta.modified().unwrap_or(current_time);

                    let mut remove = false;
                    if policy.computed_max_file_size().is_some()
                        && policy.exceeds_max_file_size(len)
                    {
                        remove = true;
                    }
                    if !remove
                        && policy.last_access_expiry.is_some()
                        && policy.has_content_expired(current_time, last)
                    {
                        remove = true;
                    }

                    if remove {
                        let _ = fs::remove_file(&path).await;
                    }
                }
            }
        }

        if let Some(max_cache_size) = policy.max_cache_size {
            let mut files: Vec<(PathBuf, u64, SystemTime)> = Vec::new();
            for dir in [&self.thumbnails_dir, &self.media_full_dir] {
                let mut stack = vec![dir.clone()];
                while let Some(d) = stack.pop() {
                    let mut rd = match fs::read_dir(&d).await {
                        Ok(r) => r,
                        Err(e) if e.kind() == std::io::ErrorKind::NotFound => continue,
                        Err(e) => return Err(MediaStoreError::backend(e)),
                    };
                    while let Ok(Some(entry)) = rd.next_entry().await {
                        let path = entry.path();
                        let meta = match entry.metadata().await {
                            Ok(m) => m,
                            Err(_) => continue,
                        };
                        if meta.is_dir() {
                            stack.push(path);
                        } else if meta.is_file() && path.extension().is_some_and(|e| e == "bin") {
                            let lm = meta.modified().unwrap_or(current_time);
                            files.push((path, meta.len(), lm));
                        }
                    }
                }
            }
            files.sort_by_key(|(_, _, t)| *t);
            let mut sum: u64 = files.iter().map(|(_, s, _)| *s).sum();
            for (path, size, _) in files {
                if sum <= max_cache_size {
                    break;
                }
                let _ = fs::remove_file(&path).await;
                sum = sum.saturating_sub(size);
            }
        }

        self.inner.write().unwrap().last_media_cleanup_time = current_time;
        Ok(())
    }

    async fn last_media_cleanup_time_inner(&self) -> Result<Option<SystemTime>, MediaStoreError> {
        Ok(Some(self.inner.read().unwrap().last_media_cleanup_time))
    }
}

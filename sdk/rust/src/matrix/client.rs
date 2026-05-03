use flutter_rust_bridge::frb;
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    reqwest::Certificate,
    ruma::{
        api::client::push::{PusherIds, PusherInit, PusherKind},
        push::HttpPusherData,
    },
    store::StoreConfig,
    AuthSession, Client, SessionChange, SqliteCryptoStore, SqliteEventCacheStore, SqliteStateStore,
};

use super::disk_media_store::DiskMediaStore;
use matrix_sdk::ruma::UserId;
use once_cell::sync::OnceCell;
use reqwest::ClientBuilder;
use std::{
    path::Path,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
};
use tokio::sync::Mutex;
use tracing::info;

#[frb(ignore)]
static GLOBAL_CLIENT: OnceCell<Arc<Mutex<Option<Client>>>> = OnceCell::new();
#[frb(ignore)]
pub static GLOBAL_CONFIG: OnceCell<ClientConfig> = OnceCell::new();

/// Latest `show_home_server_for_username` from every [configure_client] call (including when the
/// global client already exists). [GLOBAL_CONFIG] alone can stay stale on early-return configure.
#[frb(ignore)]
static SHOW_HOME_SERVER_FOR_USERNAME: AtomicBool = AtomicBool::new(true);

/// Whether UI should show full Matrix user ids (`@user:server`).
pub fn show_home_server_for_username() -> bool {
    SHOW_HOME_SERVER_FOR_USERNAME.load(Ordering::Relaxed)
}

/// Format a Matrix user id (or any `@localpart:server` label) for display.
/// When [show_home_server_for_username] is `false`, returns `@localpart` only (via [UserId] parse
/// when possible so IPv6 and unusual server parts are handled).
pub fn format_user_id_for_display(user_id: &str) -> String {
    let show_hs = show_home_server_for_username();
    if show_hs {
        return user_id.to_string();
    }
    if !user_id.starts_with('@') {
        return user_id.to_string();
    }
    if let Ok(uid) = UserId::parse(user_id) {
        return format!("@{}", uid.localpart());
    }
    match user_id.find(':') {
        Some(i) if i > 1 => user_id[..i].to_string(),
        _ => user_id.to_string(),
    }
}
#[frb(ignore)]
pub async fn get_global_client() -> Result<Option<Client>, String> {
    match GLOBAL_CLIENT.get() {
        Some(client) => {
            let client_guard = client.lock().await;
            Ok(client_guard.clone())
        }
        None => Ok(None),
    }
}
#[frb(ignore)]
pub async fn set_global_client(client: Option<Client>) -> Result<(), String> {
    let global_client = GLOBAL_CLIENT.get_or_init(|| Arc::new(Mutex::new(None)));
    let mut client_guard = global_client.lock().await;
    *client_guard = client;
    Ok(())
}

#[derive(Clone)]
pub struct ClientConfig {
    pub session_path: String,
    pub homeserver_url: String,
    pub root_certificates: Option<Vec<Certificate>>,
    pub proxy: Option<String>,
    pub passphrase: Option<String>,
    /// When `false`, UI may show Matrix user ids without the `:server` suffix (e.g. `@user` only).
    pub show_home_server_for_username: bool,
    /// Root directory for decrypted media cache (`thumbnails/`, `media/full/`, …). When `None` or
    /// empty, the SDK keeps the default in-memory media store (non-persistent, small LRU).
    pub media_cache_path: Option<String>,
}

/// Configure the client so it's ready for sync'ing.
///
/// Will log in or reuse a previous session.
pub(crate) async fn configure_client(config: &ClientConfig) -> Result<Client, String> {
    SHOW_HOME_SERVER_FOR_USERNAME.store(
        config.show_home_server_for_username,
        Ordering::Relaxed,
    );

    if let Some(client) = get_global_client().await? {
        return Ok(client);
    }

    // Store config before destructuring
    let config_clone = config.clone();

    let ClientConfig {
        session_path,
        homeserver_url,
        root_certificates,
        proxy,
        passphrase,
        show_home_server_for_username: _,
        media_cache_path,
    } = config;

    info!("Storage path: {}", session_path);
    let path = Path::new(&session_path);

    let crypto_store = SqliteCryptoStore::open(path.join("crypto"), passphrase.as_deref())
        .await
        .map_err(|e| format!("Error creating crypto_store: {}", e))?;
    let state_store = SqliteStateStore::open(path.join("state"), passphrase.as_deref())
        .await
        .map_err(|e| format!("Error creating state_store: {}", e))?;
    let event_cache_store =
        SqliteEventCacheStore::open(path.join("event_cache"), passphrase.as_deref())
            .await
            .map_err(|e| format!("Error creating event_cache_store: {}", e))?;

    let mut store_config = StoreConfig::new(
        matrix_sdk::cross_process_lock::CrossProcessLockConfig::MultiProcess {
            holder_name: "matrix".to_owned(),
        },
    )
    .crypto_store(crypto_store)
    .state_store(state_store)
    .event_cache_store(event_cache_store);

    if let Some(ref media_root) = media_cache_path {
        if !media_root.trim().is_empty() {
            let disk = DiskMediaStore::open(Path::new(media_root))
                .await
                .map_err(|e| format!("Disk media cache: {e}"))?;
            store_config = store_config.media_store(disk);
            info!("Media cache (filesystem): {}", media_root);
        }
    }

    let mut client_builder = Client::builder()
        .store_config(store_config)
        .homeserver_url(&homeserver_url)
        .with_encryption_settings(EncryptionSettings {
            auto_enable_cross_signing: true,
            backup_download_strategy: BackupDownloadStrategy::AfterDecryptionFailure,
            auto_enable_backups: true,
        })
        .with_enable_share_history_on_invite(true)
        .handle_refresh_tokens();

    let reqwest_client = ClientBuilder::new()
        .use_native_tls()
        .build()
        .map_err(|e| e.to_string())?;

    client_builder = client_builder.http_client(reqwest_client);

    if let Some(proxy_url) = proxy {
        client_builder = client_builder.proxy(proxy_url).disable_ssl_verification();
    }

    if let Some(root_certificates) = root_certificates {
        client_builder = client_builder.add_root_certificates(root_certificates.clone());
    }

    let client = client_builder.build().await.map_err(|e| e.to_string())?;

    GLOBAL_CONFIG.get_or_init(|| config_clone);

    // Try reading a session, otherwise create a new one.
    let _ = restore_session_if_available(&client, &path).await;

    set_global_client(Some(client.clone())).await?;

    // When the server reports invalid/unknown token (e.g. "refresh token does not exist"),
    // clear session so the app can show login again.
    spawn_session_invalid_listener(client.clone());

    Ok(client)
}

const SESSION_JSON: &str = "session.json";

fn spawn_session_invalid_listener(client: Client) {
    tokio::spawn(async move {
        let mut rx = client.subscribe_to_session_changes();
        while let Ok(change) = rx.recv().await {
            match change {
                SessionChange::UnknownToken(_) => {
                    info!(
                        "Session invalid (UnknownToken / refresh token rejected), clearing session file"
                    );
                    if let Some(config) = GLOBAL_CONFIG.get() {
                        let path = Path::new(&config.session_path).join(SESSION_JSON);
                        let _ = std::fs::remove_file(&path);
                    }
                    break;
                }
                SessionChange::TokensRefreshed => {
                    // Persist updated access/refresh tokens so we don't restore stale session on next launch
                    if let Some(config) = GLOBAL_CONFIG.get() {
                        if let Some(session) = client.session() {
                            if let AuthSession::Matrix(matrix_session) = session {
                                let path = Path::new(&config.session_path).join(SESSION_JSON);
                                if let Ok(serialized) = serde_json::to_string(&matrix_session) {
                                    let _ = std::fs::write(&path, serialized);
                                    info!("Session updated in session.json after token refresh");
                                }
                            }
                        }
                    }
                }
            }
        }
    });
}

async fn restore_session_if_available(client: &Client, session_path: &Path) -> Result<(), String> {
    let session_path = session_path.join("session.json");

    if let Ok(serialized) = std::fs::read_to_string(&session_path) {
        let session: MatrixSession =
            serde_json::from_str(&serialized).map_err(|e| e.to_string())?;
        client
            .restore_session(session)
            .await
            .map_err(|e| e.to_string())?;
        info!("Session restored successfully");
    } else {
        info!("No existing session found");
    }

    Ok(())
}

pub(crate) async fn register_pusher(
    client: &Client,
    push_key: String,
    app_id: String,
    url: String,
    display_name: String,
    profile_tag: String,
    lang: String,
    app_display_name: String,
) -> Result<(), String> {
    return client
        .pusher()
        .set(
            PusherInit {
                ids: PusherIds::new(push_key, app_id),
                kind: PusherKind::Http(HttpPusherData::new(url)),
                app_display_name: app_display_name,
                device_display_name: display_name,
                profile_tag: Some(profile_tag),
                lang: lang,
            }
            .into(),
        )
        .await
        .map_err(|e| e.to_string());
}

pub(crate) async fn unregister_pusher(
    client: &Client,
    push_key: String,
    app_id: String,
) -> Result<(), String> {
    return client
        .pusher()
        .delete(PusherIds::new(push_key, app_id))
        .await
        .map_err(|e| e.to_string());
}

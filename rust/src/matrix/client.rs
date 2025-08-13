use std::{path::Path, sync::Arc};

use flutter_rust_bridge::frb;
use matrix_sdk::{
    authentication::matrix::MatrixSession,
    encryption::{BackupDownloadStrategy, EncryptionSettings},
    reqwest::Certificate,
    store::StoreConfig,
    Client, SqliteCryptoStore, SqliteEventCacheStore, SqliteStateStore,
};
use once_cell::sync::OnceCell;

use tokio::sync::Mutex;

use crate::api::logger::{log_debug, log_info};
#[frb(ignore)]
static GLOBAL_CLIENT: OnceCell<Arc<Mutex<Option<Client>>>> = OnceCell::new();
#[frb(ignore)]
pub static GLOBAL_CONFIG: OnceCell<ClientConfig> = OnceCell::new();
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
}

/// Configure the client so it's ready for sync'ing.
///
/// Will log in or reuse a previous session.
pub async fn configure_client(config: ClientConfig) -> Result<bool, String> {
    if let Some(_) = get_global_client().await? {
        log_info(format!("Client already initialized"));
        return Ok(true);
    }

    // Store config before destructuring
    let config_clone = config.clone();

    let ClientConfig {
        session_path,
        homeserver_url,
        root_certificates,
        proxy,
    } = config;

    log_debug(format!("Storage path: {}", session_path));
    let path = Path::new(&session_path);

    let mut client_builder = Client::builder()
        .store_config(
            StoreConfig::new("matrix".to_owned())
                .crypto_store(
                    SqliteCryptoStore::open(path.join("crypto"), None)
                        .await
                        .map_err(|e| e.to_string())?,
                )
                .state_store(
                    SqliteStateStore::open(path.join("state"), None)
                        .await
                        .map_err(|e| e.to_string())?,
                )
                .event_cache_store(
                    SqliteEventCacheStore::open(path.join("cache"), None)
                        .await
                        .map_err(|e| e.to_string())?,
                ),
        )
        .homeserver_url(&homeserver_url)
        .with_encryption_settings(EncryptionSettings {
            auto_enable_cross_signing: true,
            backup_download_strategy: BackupDownloadStrategy::AfterDecryptionFailure,
            auto_enable_backups: true,
        })
        .with_enable_share_history_on_invite(true);

    if let Some(proxy_url) = proxy {
        client_builder = client_builder.proxy(proxy_url).disable_ssl_verification();
    }

    if let Some(root_certificates) = root_certificates {
        client_builder = client_builder.add_root_certificates(root_certificates);
    }

    let client = client_builder.build().await.map_err(|e| e.to_string())?;

    set_global_client(Some(client.clone())).await?;
    GLOBAL_CONFIG.get_or_init(|| config_clone);

    // Try reading a session, otherwise create a new one.
    restore_session_if_available(&client, &path).await?;

    Ok(true)
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
        log_info("Session restored successfully".to_string());
    } else {
        log_info("No existing session found".to_string());
    }

    Ok(())
}

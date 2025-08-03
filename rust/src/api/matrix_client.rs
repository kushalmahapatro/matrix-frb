use log::{debug, error, info};
use matrix_sdk::{config::SyncSettings, ruma::RoomId, Client};
use matrix_sdk::{AuthSession, SqliteStoreConfig};
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use std::sync::OnceLock;
use tokio::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixClientConfig {
    pub homeserver_url: String,
    pub storage_path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixRoomInfo {
    pub room_id: String,
    pub name: Option<String>,
    pub topic: Option<String>,
    pub member_count: u64,
    pub is_encrypted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MatrixMessage {
    pub event_id: String,
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncStatus {
    pub is_syncing: bool,
    pub rooms_count: u64,
    pub messages_count: u64,
    pub last_sync_time: Option<u64>,
}

// Global static variables for the Matrix client
static GLOBAL_CLIENT: OnceLock<Arc<Mutex<Option<Client>>>> = OnceLock::new();
static GLOBAL_SYNC_STATUS: OnceLock<Arc<Mutex<SyncStatus>>> = OnceLock::new();
static GLOBAL_CONFIG: OnceLock<Arc<Mutex<Option<MatrixClientConfig>>>> = OnceLock::new();

// Initialize global variables
fn init_globals() {
    GLOBAL_CLIENT.get_or_init(|| Arc::new(Mutex::new(None)));
    GLOBAL_SYNC_STATUS.get_or_init(|| {
        Arc::new(Mutex::new(SyncStatus {
            is_syncing: false,
            rooms_count: 0,
            messages_count: 0,
            last_sync_time: None,
        }))
    });
    GLOBAL_CONFIG.get_or_init(|| Arc::new(Mutex::new(None)));
}

// Helper function to get and set the global client
async fn get_global_client() -> Result<Arc<Mutex<Option<Client>>>, String> {
    Ok(GLOBAL_CLIENT.get().unwrap().clone())
}
async fn set_global_client(client: Client) -> Result<(), String> {
    let _ = GLOBAL_CLIENT.set(Arc::new(Mutex::new(Some(client))));
    Ok(())
}

// Helper function to get and set the global sync status
async fn get_global_sync_status() -> Result<Arc<Mutex<SyncStatus>>, String> {
    Ok(GLOBAL_SYNC_STATUS.get().unwrap().clone())
}

async fn set_global_sync_status(sync_status: SyncStatus) -> Result<(), String> {
    let _ = GLOBAL_SYNC_STATUS.set(Arc::new(Mutex::new(sync_status)));
    Ok(())
}

// Helper function to get and set the global config
async fn get_global_config() -> Result<Arc<Mutex<Option<MatrixClientConfig>>>, String> {
    Ok(GLOBAL_CONFIG.get().unwrap().clone())
}

async fn set_global_config(config: MatrixClientConfig) -> Result<(), String> {
    let _ = GLOBAL_CONFIG.set(Arc::new(Mutex::new(Some(config))));
    Ok(())
}

// Public API functions that work with the global client
pub fn init_client(config: MatrixClientConfig) -> Result<bool, String> {
    info!(
        "Initializing Matrix client with homeserver: {}",
        config.homeserver_url
    );
    debug!("Storage path: {}", config.storage_path);

    let rt = tokio::runtime::Runtime::new().map_err(|e| {
        error!("Failed to create tokio runtime: {}", e);
        e.to_string()
    })?;

    let path = Path::new(&config.storage_path);

    rt.block_on(async {
        init_globals();
        info!("Building Matrix client...");

        let client = Client::builder()
            .sqlite_store_with_config_and_cache_path(
                SqliteStoreConfig::new(path).passphrase(Some("password")),
                Some(path.join("cache")),
            )
            .homeserver_url(&config.homeserver_url)
            .build()
            .await
            .map_err(|e| {
                error!("Failed to build Matrix client: {}", e);
                e.to_string()
            })?;

        info!("Matrix client built successfully");

        // Store the config and client globally
        set_global_config(config.clone()).await?;
        set_global_client(client).await?;

        info!("Matrix client initialized and stored globally");
        Ok(true)
    })
}
pub fn login(username: String, password: String) -> Result<bool, String> {
    info!("Attempting to login user: {}", username);

    let rt = tokio::runtime::Runtime::new().map_err(|e| {
        error!("Failed to create tokio runtime for login: {}", e);
        e.to_string()
    })?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;
        if let Some(client) = &*client_guard {
            info!("Attempting Matrix authentication...");

            client
                .matrix_auth()
                .login_username(&username, &password)
                .initial_device_display_name("Matrix Flutter App ")
                .await
                .map_err(|e| {
                    error!("Login failed: {}", e);
                    e.to_string()
                })?;

            info!("Login successful, retrieving session...");

            let Some(session) = client.session() else {
                error!("Session not found after login");
                return Err("Session not found".to_string());
            };

            let AuthSession::Matrix(session) = session else {
                error!("Unexpected OAuth 2.0 session");
                panic!("Unexpected OAuth 2.0 session")
            };

            let global_config = get_global_config().await?;
            let config_guard = global_config.lock().await;

            let Some(config) = &*config_guard else {
                error!("Config not found during login");
                return Err("Config not found".to_string());
            };

            let path = Path::new(&config.storage_path);
            let session_path = path.join("session.json");
            let serialized_session = serde_json::to_string(&session).unwrap();
            let _ = std::fs::write(session_path, serialized_session);

            info!("Login completed successfully for user: {}", username);
            Ok(true)
        } else {
            error!("Client not initialized for login");
            Err("Client not initialized".to_string())
        }
    })
}

pub fn logout() -> Result<bool, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;
        if let Some(client) = &*client_guard {
            client
                .matrix_auth()
                .logout()
                .await
                .map_err(|e| e.to_string())?;

            // Clear the global client
            *global_client.lock().await = None;

            let gloabl_config = get_global_config().await?;
            *gloabl_config.lock().await = None;

            // Reset sync status
            {
                let sync_status = SyncStatus {
                    is_syncing: false,
                    rooms_count: 0,
                    messages_count: 0,
                    last_sync_time: None,
                };

                set_global_sync_status(sync_status).await?;
            }

            Ok(true)
        } else {
            Err("Client not initialized".to_string())
        }
    })
}

pub fn perform_initial_sync() -> Result<bool, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;

        if let Some(client) = &*client_guard {
            let sync_settings = SyncSettings::default().timeout(std::time::Duration::from_secs(30));
            let _response = client
                .sync_once(sync_settings)
                .await
                .map_err(|e| e.to_string())?;

            // Update sync status
            let sync_status = get_global_sync_status().await?;
            *sync_status.lock().await = SyncStatus {
                is_syncing: false,
                rooms_count: 0, // Will be updated when getting rooms
                messages_count: 0,
                last_sync_time: Some(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs(),
                ),
            };

            Ok(true)
        } else {
            Err("Client not logged in".to_string())
        }
    })
}

pub fn get_rooms() -> Result<Vec<MatrixRoomInfo>, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;

        if let Some(client) = &*client_guard {
            let mut rooms = Vec::new();

            for room in client.rooms() {
                let room_id = room.room_id().to_string();
                let name = room.name().map(|n| n.to_string());
                let topic = room.topic().map(|t| t.to_string());
                let member_count = room.active_members_count();

                rooms.push(MatrixRoomInfo {
                    room_id,
                    name,
                    topic,
                    member_count,
                    is_encrypted: false, // Simplified for now
                });
            }

            // Update sync status with room count
            let sync_status = get_global_sync_status().await?;
            let mut current_status = sync_status.lock().await;
            current_status.rooms_count = rooms.len() as u64;

            Ok(rooms)
        } else {
            Err("Client not logged in".to_string())
        }
    })
}

pub fn create_room(name: String, _topic: Option<String>) -> Result<String, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let _client_guard = global_client.lock().await;

        // Simplified room creation - just return a placeholder for now
        // This would need to be implemented with the actual room creation API
        Ok(format!("!placeholder:{}", name))
    })
}

pub fn join_room(room_id: String) -> Result<bool, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;

        if let Some(client) = &*client_guard {
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            client
                .join_room_by_id(&room_id)
                .await
                .map_err(|e| e.to_string())?;
            Ok(true)
        } else {
            Err("Client not logged in".to_string())
        }
    })
}

pub fn send_message(room_id: String, content: String) -> Result<String, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let global_client = get_global_client().await?;
        let client_guard = global_client.lock().await;

        if let Some(client) = &*client_guard {
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = client.get_room(&room_id).ok_or("Room not found")?;

            let event_id = room
                .send(
                    matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(
                        &content,
                    ),
                )
                .await
                .map_err(|e| e.to_string())?;

            Ok(event_id.event_id.to_string())
        } else {
            Err("Client not logged in".to_string())
        }
    })
}

pub fn get_messages(_room_id: String, _limit: u32) -> Result<Vec<MatrixMessage>, String> {
    // For now, return empty messages since timeline API is complex
    // This would need to be implemented with the actual timeline API
    let messages = Vec::new();

    // Update sync status with message count
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;
    rt.block_on(async {
        let sync_status = get_global_sync_status().await?;
        let mut current_status = sync_status.lock().await;
        current_status.messages_count = messages.len() as u64;
        Ok::<(), String>(())
    })?;

    Ok(messages)
}

pub fn get_sync_status() -> Result<SyncStatus, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let sync_status = get_global_sync_status().await?;
        let status_guard = sync_status.lock().await;
        Ok(status_guard.clone())
    })
}

pub fn is_logged_in() -> Result<bool, String> {
    let rt = tokio::runtime::Runtime::new().map_err(|e| e.to_string())?;

    rt.block_on(async {
        let matrix_config = get_global_config().await.unwrap();
        let config_guard = matrix_config.lock().await;
        let Some(config) = &*config_guard else {
            return Ok(false);
        };
        let path = Path::new(&config.storage_path);
        let session_path = path.join("session");
        Ok::<bool, String>(session_path.exists())
    })
}

use crate::api::logger::{log_error, log_info};
use crate::frb_generated::StreamSink;
use matrix_sdk::authentication::matrix::MatrixSession;
use matrix_sdk::{config::SyncSettings, ruma::RoomId, Client, LoopCtrl};
use matrix_sdk::{AuthSession, SqliteStoreConfig};
use matrix_sdk_ui::timeline::RoomExt;
use once_cell::sync::OnceCell;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::sync::Arc;
use std::time::UNIX_EPOCH;
use tokio::sync::Mutex;
use tokio::task::JoinHandle;

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
    pub latest_event: Option<MatrixMessage>,
    pub latest_event_timestamp: Option<u64>,
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncEvent {
    pub event_type: String,
    pub room_id: Option<String>,
    pub event_id: Option<String>,
    pub sender: Option<String>,
    pub content: Option<String>,
    pub timestamp: Option<u64>,
    pub sync_time: u64,
}

// Global static variables for the Matrix client
static GLOBAL_CLIENT: OnceCell<Arc<Mutex<Option<Client>>>> = OnceCell::new();
static GLOBAL_SYNC_STATUS: OnceCell<Arc<Mutex<SyncStatus>>> = OnceCell::new();
static GLOBAL_CONFIG: OnceCell<Arc<Mutex<Option<MatrixClientConfig>>>> = OnceCell::new();
static SYNC_TASK: OnceCell<Arc<Mutex<Option<JoinHandle<()>>>>> = OnceCell::new();
static SYNC_EVENTS: OnceCell<Arc<Mutex<Vec<SyncEvent>>>> = OnceCell::new();
static SYNC_STREAM_SINK: OnceCell<StreamSink<SyncEvent>> = OnceCell::new();
static GLOBAL_RUNTIME: OnceCell<tokio::runtime::Runtime> = OnceCell::new();

static SESSION_JSON: &str = "session.json";

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
    SYNC_TASK.get_or_init(|| Arc::new(Mutex::new(None)));
    SYNC_EVENTS.get_or_init(|| Arc::new(Mutex::new(Vec::new())));
    GLOBAL_RUNTIME
        .get_or_init(|| tokio::runtime::Runtime::new().expect("Failed to create global runtime"));
    log_info("Global variables initialized".to_string());
}

// Initialize sync event stream for Flutter
pub fn init_sync_stream(sync_stream: StreamSink<SyncEvent>) {
    create_sync_stream(sync_stream);
}

fn create_sync_stream(s: StreamSink<SyncEvent>) {
    match SYNC_STREAM_SINK.set(s) {
        Ok(_) => {
            log_info("Sync stream sink initialized successfully".to_string());
        }
        Err(_) => {
            log_error("Failed to set sync stream sink".to_string());
        }
    }
}

// Helper function to get and set the global client
async fn get_global_client() -> Result<Option<Client>, String> {
    match GLOBAL_CLIENT.get() {
        Some(client) => {
            let client_guard = client.lock().await;
            Ok(client_guard.clone())
        }
        None => Err("Global client not initialized".to_string()),
    }
}
async fn set_global_client(client: Option<Client>) -> Result<(), String> {
    let mut client_guard = GLOBAL_CLIENT.get().unwrap().lock().await;
    *client_guard = client;
    Ok(())
}

// Helper function to get and set the global sync status
async fn get_global_sync_status() -> Result<Arc<Mutex<SyncStatus>>, String> {
    Ok(GLOBAL_SYNC_STATUS.get().unwrap().clone())
}

async fn set_global_sync_status(sync_status: SyncStatus) -> Result<(), String> {
    let mut sync_status_guard = GLOBAL_SYNC_STATUS.get().unwrap().lock().await;
    *sync_status_guard = sync_status;
    Ok(())
}

// Helper function to get and set the global config
async fn get_global_config() -> Result<Option<MatrixClientConfig>, String> {
    match GLOBAL_CONFIG.get() {
        Some(config) => {
            let config_guard = config.lock().await;
            Ok(config_guard.clone())
        }
        None => Err("Global config not initialized".to_string()),
    }
}

async fn set_global_config(config: Option<MatrixClientConfig>) -> Result<(), String> {
    match GLOBAL_CONFIG.get() {
        Some(existing_config) => {
            let mut config_guard = existing_config.lock().await;
            *config_guard = config;
            Ok(())
        }
        None => {
            let _ = GLOBAL_CONFIG.set(Arc::new(Mutex::new(config)));
            Ok(())
        }
    }
}

// Helper functions to manage the sync task
async fn get_sync_task() -> Result<Arc<Mutex<Option<JoinHandle<()>>>>, String> {
    match SYNC_TASK.get() {
        Some(task) => {
            let _ = task.lock().await;
            Ok(task.clone())
        }
        None => Err("Sync task not initialized".to_string()),
    }
}

async fn set_sync_task(task: Option<JoinHandle<()>>) -> Result<(), String> {
    let mut task_guard = SYNC_TASK.get().unwrap().lock().await;
    *task_guard = task;
    Ok(())
}

// Helper functions to manage sync events
async fn store_sync_event(event: SyncEvent) {
    // Store in the events vector for batch retrieval
    if let Some(events) = SYNC_EVENTS.get() {
        let mut events_guard = events.lock().await;
        events_guard.push(event.clone());
        // Keep only the last 1000 events to prevent memory issues
        if events_guard.len() > 1000 {
            events_guard.remove(0);
        }
    }

    // Send to stream sink for real-time Flutter updates
    if let Some(sink) = SYNC_STREAM_SINK.get() {
        if let Err(e) = sink.add(event) {
            log_error(format!("Failed to send sync event to stream: {}", e));
        }
    }
}

async fn get_sync_events() -> Result<Vec<SyncEvent>, String> {
    let events = SYNC_EVENTS.get().ok_or("Sync events not initialized")?;
    let events_guard = events.lock().await;
    Ok(events_guard.clone())
}

async fn clear_sync_events() -> Result<(), String> {
    let events = SYNC_EVENTS.get().ok_or("Sync events not initialized")?;
    let mut events_guard = events.lock().await;
    events_guard.clear();
    Ok(())
}

// Public API functions that work with the global client
pub async fn init_client(config: MatrixClientConfig) -> Result<bool, String> {
    if get_global_config().await.is_ok() {
        log_info("Config already initialized".to_string());
    } else {
        log_info("Config not initialized".to_string());
        let _ = set_global_config(Some(config.clone())).await;
    }

    if get_global_client().await.is_ok() {
        log_info("Client already initialized".to_string());
        return Ok(true);
    }
    log_info(format!(
        "Initializing Matrix client with homeserver: {}",
        config.homeserver_url
    ));
    log_info(format!("Storage path: {}", config.storage_path));

    // Initialize globals first
    init_globals();

    let path = Path::new(&config.storage_path);

    log_info("Building Matrix client...".to_string());

    let client = Client::builder()
        .sqlite_store_with_config_and_cache_path(
            SqliteStoreConfig::new(path).passphrase(Some("password")),
            Some(path.join("cache")),
        )
        .homeserver_url(&config.homeserver_url)
        .build()
        .await
        .map_err(|e| {
            log_error(format!("Failed to build Matrix client: {}", e));
            e.to_string()
        })?;

    log_info("Matrix client built successfully".to_string());

    // Store the config and client globally
    let _ = set_global_config(Some(config.clone())).await;
    let _ = set_global_client(Some(client)).await;

    log_info("Matrix client initialized and stored globally".to_string());
    Ok(true)
}

pub fn login(username: String, password: String) -> Result<bool, String> {
    log_info(format!("Attempting to login user: {}", username));

    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                log_info("Attempting Matrix authentication...".to_string());

                client
                    .matrix_auth()
                    .login_username(&username, &password)
                    .initial_device_display_name("Matrix Flutter App ")
                    .await
                    .map_err(|e| {
                        log_error(format!("Login failed: {}", e));
                        e.to_string()
                    })?;

                log_info("Login successful, retrieving session...".to_string());

                let Some(session) = client.session() else {
                    log_error("Session not found after login".to_string());
                    return Err("Session not found".to_string());
                };

                let AuthSession::Matrix(session) = session else {
                    log_error("Unexpected OAuth 2.0 session".to_string());
                    panic!("Unexpected OAuth 2.0 session")
                };

                let global_config = get_global_config().await?;
                let Some(config) = global_config else {
                    log_error("Config not found during login".to_string());
                    return Err("Config not found".to_string());
                };

                let path = Path::new(&config.storage_path);
                let session_path = path.join(SESSION_JSON);
                let serialized_session = serde_json::to_string(&session).unwrap();
                let _ = std::fs::write(session_path, serialized_session);

                log_info(format!(
                    "Login completed successfully for user: {}",
                    username
                ));
                Ok(true)
            } else {
                log_error("Client not initialized for login".to_string());
                Err("Client not initialized".to_string())
            }
        })
    })
}

pub fn logout() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                client
                    .matrix_auth()
                    .logout()
                    .await
                    .map_err(|e| e.to_string())?;

                // Stop polling sync
                stop_polling_sync_internal().await?;

                // Clear the global client
                set_global_client(None).await?;
                set_global_config(None).await?;

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
    })
}

// Async version for internal use
async fn perform_initial_sync_async() -> Result<bool, String> {
    log_info("Performing initial sync".to_string());

    // First check if user is logged in
    let is_logged_in =
        is_logged_in().map_err(|e| format!("Failed to check login status: {}", e))?;
    if !is_logged_in {
        log_error("Cannot perform sync: user not logged in".to_string());
        return Err("User not logged in. Please login first.".to_string());
    }

    let global_client = get_global_client().await?;

    if let Some(client) = global_client {
        // Check if client has a valid session
        if client.session().is_none() {
            log_error("Client has no valid session".to_string());
            return Err("No valid session found. Please login again.".to_string());
        }

        let sync_settings = SyncSettings::default()
            .full_state(true)
            .timeout(std::time::Duration::from_secs(30));
        let _response = client.sync_once(sync_settings).await.map_err(|e| {
            log_error(format!("Sync failed: {}", e));
            if e.to_string().contains("no access token") {
                "Authentication required. Please login first.".to_string()
            } else {
                format!("Sync failed: {}", e)
            }
        })?;

        let rooms = client.rooms();
        for room in rooms {
            log_info(format!("Room: {:?}", room));
            let timeline = room.timeline_builder().build().await.map_err(|e| {
                log_error(format!("Failed to get timeline: {}", e));
                e.to_string()
            })?;
            log_info(format!("Timeline: {:?}", timeline));
            let _ = timeline.subscribe();
        }

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

        log_info("Initial sync completed successfully".to_string());
        Ok(true)
    } else {
        log_error("Client not initialized".to_string());
        Err("Client not initialized. Please initialize the client first.".to_string())
    }
}

// Public sync function that uses block_in_place to avoid runtime conflicts
// pub fn perform_initial_sync() -> Result<bool, String> {
//     let _ = perform_initial_sync_async();
//     Ok(true)
// }

// Perform initial sync and optionally start polling sync
pub async fn perform_initial_sync_with_polling(start_polling: bool) -> Result<bool, String> {
    log_info("Performing initial sync with polling option".to_string());

    // First perform the initial sync
    let initial_sync_result = perform_initial_sync_async().await;
    if initial_sync_result.is_err() {
        return initial_sync_result;
    }

    // If requested, start polling sync
    if start_polling {
        log_info("Starting polling sync after initial sync".to_string());
        let _ = start_polling_sync().await;
    }

    Ok(true)
}

pub fn get_rooms() -> Result<Vec<MatrixRoomInfo>, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;

            if let Some(client) = global_client {
                let mut rooms = Vec::new();

                for room in client.rooms() {
                    log_info(format!("Room: {:?}", room));
                    let room_id = room.room_id().to_string();
                    let name = room.name().map(|n| n.to_string());
                    let topic = room.topic().map(|t| t.to_string());
                    let member_count = room.joined_members_count();
                    let latest_event_item = room.latest_event_item().await;
                    let mut matrix_message = MatrixMessage {
                        event_id: "".to_string(),
                        sender: "".to_string(),
                        content: "".to_string(),
                        timestamp: 0,
                    };
                    let mut timestamp = 0;

                    if latest_event_item.is_none() {
                        log_error("No latest event found".to_string());
                    } else {
                        let event_item = latest_event_item.unwrap();
                        let latest_event_content = event_item
                            .content()
                            .as_message()
                            .map(|m| m.body().to_string());
                        log_info(format!("Latest event: {:?}", latest_event_content));

                        // Extract event ID
                        let event_id = if let Some(id) = event_item.event_id() {
                            id.to_string()
                        } else {
                            "unknown_event_id".to_string()
                        };

                        // Extract timestamp from the raw event
                        timestamp = event_item
                            .timestamp()
                            .to_system_time()
                            .unwrap()
                            .duration_since(UNIX_EPOCH)
                            .unwrap()
                            .as_secs();

                        // Extract sender from the raw event
                        let sender = event_item.sender().to_string();

                        // Extract content from the raw event
                        let content = latest_event_content.unwrap_or("".to_string());

                        matrix_message = MatrixMessage {
                            event_id,
                            sender,
                            content,
                            timestamp,
                        };

                        log_info(format!("Matrix message: {:?}", matrix_message));
                        log_info(format!("Timestamp: {:?}", timestamp));
                    }
                    rooms.push(MatrixRoomInfo {
                        room_id,
                        name,
                        topic,
                        member_count,
                        latest_event: Some(matrix_message),
                        latest_event_timestamp: Some(timestamp),
                    });
                }

                // Sort rooms by latest event timestamp (most recent first)
                rooms.sort_by(|a, b| {
                    let timestamp_a = a.latest_event_timestamp.unwrap_or(0);
                    let timestamp_b = b.latest_event_timestamp.unwrap_or(0);
                    timestamp_b.cmp(&timestamp_a) // Reverse order for most recent first
                });

                // Update sync status with room count
                let sync_status = get_global_sync_status().await?;
                let mut current_status = sync_status.lock().await;
                current_status.rooms_count = rooms.len() as u64;

                Ok(rooms)
            } else {
                Err("Client not logged in".to_string())
            }
        })
    })
}

pub fn create_room(name: String, _topic: Option<String>) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let _global_client = get_global_client().await?;

            // Simplified room creation - just return a placeholder for now
            // This would need to be implemented with the actual room creation API
            Ok(format!("!placeholder:{}", name))
        })
    })
}

pub fn join_room(room_id: String) -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;

            if let Some(client) = global_client {
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
    })
}

pub fn send_message(room_id: String, content: String) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;

            if let Some(client) = global_client {
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
    })
}

pub fn get_messages(_room_id: String, _limit: u32) -> Result<Vec<MatrixMessage>, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            // For now, return empty messages since timeline API is complex
            // This would need to be implemented with the actual timeline API
            let messages = Vec::new();

            // Update sync status with message count
            let sync_status = get_global_sync_status().await?;
            let mut current_status = sync_status.lock().await;
            current_status.messages_count = messages.len() as u64;

            Ok(messages)
        })
    })
}

pub fn get_sync_status() -> Result<SyncStatus, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let sync_status = get_global_sync_status().await?;
            let status_guard = sync_status.lock().await;
            Ok(status_guard.clone())
        })
    })
}

pub fn is_logged_in() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let matrix_config = get_global_config().await.unwrap();
            let Some(config) = matrix_config else {
                return Ok(false);
            };
            let path = Path::new(&config.storage_path);
            let session_path = path.join(SESSION_JSON);
            let session_json_exists = session_path.exists();

            let client = get_global_client().await?;
            let Some(client) = client else {
                return Err("Client not initialized".to_string());
            };
            if session_json_exists && client.session().is_none() {
                let session_json =
                    std::fs::read_to_string(session_path).map_err(|e| e.to_string())?;
                let matrix_session = serde_json::from_str::<MatrixSession>(&session_json)
                    .map_err(|e| e.to_string())?;
                client
                    .restore_session(matrix_session)
                    .await
                    .map_err(|e| e.to_string())?;
                return Ok(true);
            }

            Ok(session_json_exists)
        })
    })
}

// Start polling sync - continuously syncs with the server
pub async fn start_polling_sync() -> Result<bool, String> {
    log_info("Starting polling sync".to_string());

    // First check if user is logged in
    let is_logged_in =
        is_logged_in().map_err(|e| format!("Failed to check login status: {}", e))?;
    if !is_logged_in {
        log_error("Cannot start polling sync: user not logged in".to_string());
        return Err("User not logged in. Please login first.".to_string());
    }

    // Stop any existing sync task
    stop_polling_sync_internal().await?;

    let client = get_global_client().await?;
    let Some(client) = client else {
        return Err("Client not initialized".to_string());
    };

    // Check if client has a valid session
    if client.session().is_none() {
        log_error("Client has no valid session".to_string());
        return Err("No valid session found. Please login again.".to_string());
    }

    // Update sync status
    set_global_sync_status(SyncStatus {
        is_syncing: true,
        rooms_count: 0,
        messages_count: 0,
        last_sync_time: None,
    })
    .await?;

    // Spawn the polling sync task
    let handle = tokio::spawn(polling_sync_loop(client));
    set_sync_task(Some(handle)).await?;

    log_info("Polling sync started successfully".to_string());
    Ok(true)
}

// Stop polling sync
pub fn stop_polling_sync() -> Result<bool, String> {
    log_info("Stopping polling sync".to_string());

    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            stop_polling_sync_internal().await?;
            log_info("Polling sync stopped successfully".to_string());
            Ok(true)
        })
    })
}

// Internal function to stop polling sync
async fn stop_polling_sync_internal() -> Result<(), String> {
    let sync_task = get_sync_task().await?;
    let mut task_guard = sync_task.lock().await;

    if let Some(handle) = task_guard.take() {
        handle.abort();
        // Wait for the task to finish
        let _ = handle.await;
    }

    // Update sync status
    set_global_sync_status(SyncStatus {
        is_syncing: false,
        rooms_count: 0,
        messages_count: 0,
        last_sync_time: None,
    })
    .await?;

    Ok(())
}

// Get sync events for Flutter
pub fn get_sync_events_for_flutter() -> Result<Vec<SyncEvent>, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async { get_sync_events().await })
    })
}

// Clear sync events
pub fn clear_sync_events_for_flutter() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            clear_sync_events().await?;
            Ok(true)
        })
    })
}

// Check if sync stream is initialized
pub fn is_sync_stream_initialized() -> bool {
    SYNC_STREAM_SINK.get().is_some()
}

// Send a test sync event (for debugging)
pub fn send_test_sync_event() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let test_event = SyncEvent {
                event_type: "test_event".to_string(),
                room_id: Some("!test:example.com".to_string()),
                event_id: Some("$test123".to_string()),
                sender: Some("@test:example.com".to_string()),
                content: Some("This is a test sync event".to_string()),
                timestamp: Some(
                    std::time::SystemTime::now()
                        .duration_since(std::time::UNIX_EPOCH)
                        .unwrap()
                        .as_secs(),
                ),
                sync_time: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_secs(),
            };

            store_sync_event(test_event).await;
            Ok(true)
        })
    })
}

// Check if polling sync is active
pub fn is_polling_sync_active() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let sync_task = get_sync_task().await?;
            let task_guard = sync_task.lock().await;
            Ok(task_guard.is_some())
        })
    })
}

// Check if client is properly authenticated
pub fn is_client_authenticated() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                // Check if client has a valid session
                Ok(client.session().is_some())
            } else {
                Ok(false)
            }
        })
    })
}

// The main polling sync loop
async fn polling_sync_loop(client: Client) {
    log_info("Polling sync loop started".to_string());

    let mut interval = tokio::time::interval(std::time::Duration::from_secs(30)); // Sync every 30 seconds

    loop {
        interval.tick().await;

        match perform_sync_cycle(&client).await {
            Ok(_) => {
                log_info("Sync cycle completed successfully".to_string());
            }
            Err(e) => {
                log_error(format!("Sync cycle failed: {}", e));
                // Continue the loop even if sync fails
            }
        }
    }
}

// Perform a single sync cycle
async fn perform_sync_cycle(client: &Client) -> Result<(), String> {
    // Check if client has a valid session before attempting sync
    if client.session().is_none() {
        log_error("Cannot perform sync cycle: no valid session".to_string());
        return Err("No valid session found. Please login again.".to_string());
    }

    let sync_settings = SyncSettings::default().timeout(std::time::Duration::from_secs(30));

    let current_time = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs();

    client
        .sync_with_result_callback(sync_settings, |sync_result| async move {
            match sync_result {
                Ok(response) => {
                    log_info(format!("Processing sync response {:?}", response));

                    // Process joined rooms
                    for (room_id, room) in response.rooms.joined {
                        log_info(format!("Processing room: {}", room_id));

                        // Process timeline events
                        for event in room.timeline.events {
                            let sync_event = SyncEvent {
                                event_type: "timeline_event".to_string(),
                                room_id: Some(room_id.to_string()),
                                event_id: None, // Will be extracted if needed
                                sender: None,   // Will be extracted if needed
                                content: Some(format!("{:?}", event)),
                                timestamp: None, // Will be extracted if needed
                                sync_time: current_time,
                            };

                            // Store the event for Flutter to retrieve
                            store_sync_event(sync_event).await;
                        }
                    }

                    // Process left rooms
                    for (room_id, _room) in response.rooms.left {
                        let sync_event = SyncEvent {
                            event_type: "room_left".to_string(),
                            room_id: Some(room_id.to_string()),
                            event_id: None,
                            sender: None,
                            content: None,
                            timestamp: None,
                            sync_time: current_time,
                        };

                        log_info(format!("Left room event: {:?}", sync_event));
                    }

                    // Process invited rooms
                    for (room_id, _room) in response.rooms.invited {
                        let sync_event = SyncEvent {
                            event_type: "room_invited".to_string(),
                            room_id: Some(room_id.to_string()),
                            event_id: None,
                            sender: None,
                            content: None,
                            timestamp: None,
                            sync_time: current_time,
                        };

                        log_info(format!("Invited room event: {:?}", sync_event));
                    }
                }
                Err(e) => {
                    log_error(format!("Sync response error: {}", e));
                }
            }

            Ok(LoopCtrl::Continue)
        })
        .await
        .map_err(|e| {
            log_error(format!("Sync cycle failed: {}", e));
            if e.to_string().contains("no access token") {
                "Authentication required. Please login first.".to_string()
            } else {
                format!("Sync failed: {}", e)
            }
        })?;

    // Update sync status with current time
    let rooms_count = client.rooms().len() as u64;
    let messages_count = 0; // This would need to be calculated from actual messages

    set_global_sync_status(SyncStatus {
        is_syncing: true,
        rooms_count,
        messages_count,
        last_sync_time: Some(current_time),
    })
    .await?;

    log_info(format!(
        "Sync completed - Rooms: {}, Messages: {}, Time: {}",
        rooms_count, messages_count, current_time
    ));

    Ok(())
}

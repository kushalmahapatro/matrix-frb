use crate::api::logger::{log_error, log_info};
use crate::frb_generated::StreamSink;
use futures::{pin_mut, StreamExt};
use matrix_sdk::authentication::matrix::MatrixSession;
use matrix_sdk::ruma::api::client::uiaa::{AuthData, Dummy};
use matrix_sdk::ruma::{self, assign};
use matrix_sdk::{config::SyncSettings, ruma::RoomId, Client};
use matrix_sdk::{AuthSession, RoomDisplayName, SqliteStoreConfig};

use ruma::api::client::account::register;

use matrix_sdk_ui::timeline::{RoomExt, TimelineItemKind};
use once_cell::sync::OnceCell;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::path::Path;
use std::sync::Arc;
use std::time::{Duration, UNIX_EPOCH};

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
// Global timeline stream map: room_id -> StreamSink<RoomTimeline>
static GLOBAL_TIMELINE_STREAMS: OnceCell<Mutex<HashMap<String, StreamSink<RoomTimeline>>>> =
    OnceCell::new();

/// Initialize the global timeline streams map
fn init_timeline_streams() {
    GLOBAL_TIMELINE_STREAMS.get_or_init(|| Mutex::new(HashMap::new()));
}

/// Add or update a timeline stream for a room
pub async fn set_timeline_stream(room_id: String, stream: StreamSink<RoomTimeline>) {
    if let Some(map) = GLOBAL_TIMELINE_STREAMS.get() {
        let mut guard = map.lock().await;
        guard.insert(room_id, stream);
    }
}

/// Send a timeline event to a room's stream
pub async fn send_to_timeline_stream(
    room_id: &str,
    timeline_event: RoomTimeline,
) -> Result<(), String> {
    if let Some(map) = GLOBAL_TIMELINE_STREAMS.get() {
        let guard = map.lock().await;
        if let Some(stream) = guard.get(room_id) {
            if let Err(e) = stream.add(timeline_event) {
                return Err(format!("Failed to send timeline event to stream: {}", e));
            }
        } else {
            return Err(format!("No timeline stream found for room: {}", room_id));
        }
    } else {
        return Err("Timeline streams not initialized".to_string());
    }
    Ok(())
}

/// Remove a timeline stream for a room
pub async fn remove_timeline_stream(room_id: &str) {
    if let Some(map) = GLOBAL_TIMELINE_STREAMS.get() {
        let mut guard = map.lock().await;
        guard.remove(room_id);
    }
}

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
    init_timeline_streams();
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

// Public API functions that work with the global client
pub async fn init_client(config: MatrixClientConfig) -> Result<bool, String> {
    let _ = set_global_config(Some(config.clone())).await;

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
        .sliding_sync_version_builder(matrix_sdk::sliding_sync::VersionBuilder::DiscoverNative)
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

pub fn register(username: String, password: String) -> Result<bool, String> {
    log_info(format!("Attempting to register user: {}", username));
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                log_info("Attempting Matrix authentication...".to_string());

                let req = assign!(register::v3::Request::new(), {
                    username: Some(username.to_owned()),
                    password: Some(password.to_owned()),
                    auth: Some(AuthData::Dummy(Dummy::new())),
                    refresh_token: true,
                });

                client.matrix_auth().register(req).await.map_err(|e| {
                    log_error(format!("Login failed: {}", e));
                    e.to_string()
                })?;

                log_info("Registration successful, retrieving session...".to_string());

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
                    "Registration completed successfully for user: {}",
                    username
                ));
                Ok(true)
            } else {
                log_error("Client not initialized for registration".to_string());
                Err("Client not initialized".to_string())
            }
        })
    })
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

                // Stop sync

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

pub fn listen_room_updates(stream: StreamSink<MatrixRoomInfo>) {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await.unwrap();

            if let Some(client) = global_client {
                let mut room_stream = client.subscribe_to_all_room_updates();
                loop {
                    match room_stream.recv().await {
                        Ok(updates) => {
                            log_info(format!("Received room update: {:?}", updates));
                            match get_rooms() {
                                Ok(rooms) => {
                                    for room in rooms {
                                        let _ = stream.add(room);
                                    }
                                }
                                Err(e) => {
                                    log_error(format!("Error getting rooms: {}", e));
                                }
                            }
                        }
                        Err(e) => {
                            log_error(format!("Error receiving room updates: {}", e));
                        }
                    }
                }
            }
        })
    })
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
                    let display_name = room
                        .cached_display_name()
                        .unwrap_or_else(|| RoomDisplayName::Empty);
                    let name = display_name.to_string();
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
                    log_info(format!("latest event: {:?}", latest_event_item));

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
                        topic,
                        member_count,
                        name: Some(name),
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

#[derive(Debug, Clone)]
pub struct RoomTimeline {
    pub event_id: String,
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
}

async fn update_timeline(timeline: &matrix_sdk_ui::Timeline, room_id: &str) {
    let events = timeline.items().await;

    for event in events.iter() {
        match event.kind() {
            TimelineItemKind::Event(e) => {
                let event_id = e
                    .event_id()
                    .map_or("unknown_event_id".to_string(), |id| id.to_string());
                let sender = e.sender().as_str().to_string();
                let content = e
                    .content()
                    .as_message()
                    .map_or("No content".to_string(), |m| m.body().to_string());
                let timestamp = e
                    .timestamp()
                    .to_system_time()
                    .map_or(0, |f| f.duration_since(UNIX_EPOCH).unwrap().as_secs());

                let timeline_event = RoomTimeline {
                    event_id,
                    sender,
                    content,
                    timestamp,
                };

                log_info(format!("Sending timeline event: {:?}", timeline_event));
                let _ = send_to_timeline_stream(&room_id, timeline_event).await;
            }
            TimelineItemKind::Virtual(virtual_timeline_item) => {
                // Handle virtual timeline items if needed
                log_info(format!(
                    "Virtual timeline item: {:?}",
                    virtual_timeline_item
                ));
                // For now, we just log it, but you can handle it as needed
            }
        }
    }
}
pub fn load_timeline(stream: StreamSink<RoomTimeline>, room_id: String) -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;

            if let Some(client) = global_client {
                let room_id_string = room_id.clone();
                let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
                let room = client.get_room(&room_id).ok_or("Room not found")?;

                // Load the timeline for the room
                let timeline: matrix_sdk_ui::Timeline =
                    room.timeline().await.map_err(|e| e.to_string())?;
                let events = timeline.items().await;
                log_info(format!(
                    "Loaded {} events for room {}",
                    events.len(),
                    room_id
                ));

                set_timeline_stream(room_id_string.clone(), stream).await;

                // Subscribe to the timeline to get the initial events and the stream of diffs
                let (events, mut diff_stream) = timeline.subscribe().await;

                update_timeline(&timeline, &room_id_string).await;

                while let Some(diffs) = diff_stream.next().await {
                    for diff in diffs {
                        log_info(format!("Received timeline diff: {:?}", diff));
                        // Each diff can be an addition, removal, update, etc.
                        // We'll try to extract RoomTimeline from added/updated events.
                        update_timeline(&timeline, &room_id_string).await;
                        // match diff {
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Append { values } => {
                        //         update_timeline(&timeline, &room_id_string).await;
                        //     }
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Clear => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::PushFront { value } => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::PushBack { value } => {
                        //         update_timeline(&timeline, &room_id_string).await;
                        //     }
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::PopFront => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::PopBack => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Insert { index, value } => {
                        //         todo!()
                        //     }
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Set { index, value } => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Remove { index } => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Truncate { length } => todo!(),
                        //     matrix_sdk_ui::eyeball_im::VectorDiff::Reset { values } => todo!(),
                        // }
                    }
                }

                Ok(true)
            } else {
                Err("Client not logged in".to_string())
            }
        })
    })
}

pub fn timeline_paginate_forward(room_id: String) -> Result<(), String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            // For now, this function does nothing
            // It can be implemented to fetch more messages from the timeline
            log_info(format!("Paginating up for room: {}", room_id));
            let client = get_global_client().await?;
            if client.is_none() {
                return Err("Client not logged in".to_string());
            }
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = client.unwrap().get_room(&room_id).ok_or("Room not found")?;

            // Load the timeline for the room
            let timeline = room.timeline().await.map_err(|e| e.to_string())?;
            let _ = timeline.paginate_forwards(10);
            Ok(())
        })
    })
}

pub fn timeline_paginate_backwards(room_id: String) -> Result<(), String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            // For now, this function does nothing
            // It can be implemented to fetch more messages from the timeline
            log_info(format!("Paginating down for room: {}", room_id));
            let client = get_global_client().await?;
            if client.is_none() {
                return Err("Client not logged in".to_string());
            }
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = client.unwrap().get_room(&room_id).ok_or("Room not found")?;

            // Load the timeline for the room
            let timeline = room.timeline().await.map_err(|e| e.to_string())?;
            let _ = timeline.paginate_backwards(10);
            Ok(())
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

pub fn sync_once() -> Result<(), String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            log_info("Syncing once".to_string());

            let global_client = get_global_client().await.unwrap();
            if let Some(client) = global_client {
                // Check if client has a valid session
                if client.session().is_none() {
                    log_error("Client has no valid session".to_string());
                    return Err("No valid session found. Please login again.".to_string());
                }

                let sync_settings = SyncSettings::default();
                let sync_response = client
                    .sync_once(sync_settings)
                    .await
                    .map_err(|e| e.to_string())?;

                log_info(format!("Sync once response: {:?}", sync_response));

                Ok(())
            } else {
                log_error("Client not initialized".to_string());
                Err("Client not initialized. Please initialize the client first.".to_string())
            }
        })
    })
}

pub async fn start_sliding_sync() -> Result<(), String> {
    log_info("Starting sliding sync".to_string());

    // First check if user is logged in
    let is_logged_in =
        is_logged_in().map_err(|e| format!("Failed to check login status: {}", e))?;
    if !is_logged_in {
        log_error("Cannot start sliding sync: user not logged in".to_string());
        return Err("User not logged in. Please login first.".to_string());
    }

    let global_client = get_global_client().await?;
    if let Some(client) = global_client {
        // Check if client has a valid session
        if client.session().is_none() {
            log_error("Client has no valid session".to_string());
            return Err("No valid session found. Please login again.".to_string());
        }

        // Start sliding sync
        let builder = client.sliding_sync("main").map_err(|e| {
            log_error(format!("Sliding sync failed: {}", e));
            e.to_string()
        })?;

        let service = builder
            .network_timeout(Duration::from_secs(5))
            .poll_timeout(Duration::from_secs(5))
            .share_pos()
            .version(matrix_sdk::sliding_sync::Version::Native)
            .with_all_extensions()
            .build()
            .await
            .map_err(|e| {
                log_error(format!("Failed to build sliding sync: {}", e));
                e.to_string()
            })?;

        let sliding_sync_version = client.sliding_sync_version();
        log_info(format!("Sliding sync version: {:?}", sliding_sync_version));

        let sync_stream = service.sync();
        pin_mut!(sync_stream);
        while let Some(sync_response) = sync_stream.next().await {
            log_info(format!("Sync response: {:?}", sync_response));
        }

        log_info("Sliding sync started successfully".to_string());

        let mut sync_stream = Box::pin(client.sync_stream(SyncSettings::default()).await);

        while let Some(Ok(response)) = sync_stream.next().await {
            log_info(format!("Normal Sync response: {:?}", response));
        }

        Ok(())
    } else {
        log_error("Client not initialized".to_string());
        Err("Client not initialized. Please initialize the client first.".to_string())
    }
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

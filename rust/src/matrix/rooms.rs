use std::{collections::HashMap, sync::Arc};

use flutter_rust_bridge::frb;

use imbl::Vector;
use matrix_sdk::{
    ruma::{OwnedRoomId, RoomId},
    Client, Room, RoomState,
};
use matrix_sdk_ui::{sync_service::SyncService, timeline::RoomExt};
use std::sync::Mutex;

use crate::{
    api::{
        logger::{log_error, log_info, log_warn},
        platform::GLOBAL_RUNTIME,
    },
    frb_generated::StreamSink,
    matrix::{
        status::StatusHandle,
        sync_service::GLOBAL_APP,
        timelines::{get_message_from_timeline_item, Message, MessageType},
    },
};

// RoomUpdate moved to api module

pub type Rooms = Arc<Mutex<Vector<Room>>>;

#[derive(Clone)]
#[frb(ignore)]
pub struct RoomList {
    pub status_handle: StatusHandle,

    pub rooms: Rooms,

    client: Client,

    /// Extra information about rooms.
    room_infos: RoomInfos,

    /// The current room that's subscribed to in the room list's sliding sync.
    current_room_subscription: Option<Room>,

    /// The sync service used for synchronizing events.
    sync_service: Arc<SyncService>,
}

impl RoomList {
    pub fn new(
        client: Client,
        rooms: Rooms,
        room_infos: RoomInfos,
        sync_service: Arc<SyncService>,
        status_handle: StatusHandle,
    ) -> Self {
        Self {
            client,
            rooms,
            status_handle,
            room_infos,
            current_room_subscription: None,
            sync_service,
        }
    }

    pub fn get_room_by_id(&self, room_id: &str) -> Option<Room> {
        let rooms = self.rooms.lock().unwrap();
        rooms
            .iter()
            .find(|room| room.room_id().to_string() == room_id)
            .cloned()
    }
}

#[frb(ignore)]
pub type RoomInfos = Arc<Mutex<HashMap<OwnedRoomId, ExtraRoomInfo>>>;
#[derive(Clone)]
#[frb(ignore)]
pub struct ExtraRoomInfo {
    /// Content of the raw m.room.name event, if available.
    pub raw_name: Option<String>,

    /// Calculated display name for the room.
    pub display_name: Option<String>,

    /// Is the room a DM?
    pub is_dm: Option<bool>,
}

pub enum UpdateType {
    Joined,
    Left,
    Invited,
    Knocked,
    Banned,
}

pub struct RoomUpdate {
    pub room_id: String,
    pub raw_name: Option<String>,
    pub display_name: Option<String>,
    pub is_dm: Option<bool>,
    pub update_type: UpdateType,
    pub unread_notifications: Option<u64>,
    pub unread_highlight: Option<u64>,
    pub unread_mentions: Option<u64>,
    pub unread_messages: Option<u64>,
    pub message: Option<Message>,
}

async fn get_room_update_data(room: &Room) -> RoomUpdate {
    let room_id = room.room_id().to_string();
    let raw_name = room.name().map(|name| name.to_string());
    let display_name = room.cached_display_name().map(|name| name.to_string());
    let is_dm = room.is_direct().await.map_err(|e| false).unwrap();
    let unread_notification_count = room.unread_notification_counts().notification_count;
    let unread_highlight_count = room.unread_notification_counts().highlight_count;
    let unread_mentions_count = room.num_unread_mentions();
    let unread_messages = room.num_unread_messages();
    let update_type = match room.state() {
        RoomState::Joined => UpdateType::Joined,
        RoomState::Invited => UpdateType::Invited,
        RoomState::Knocked => UpdateType::Knocked,
        RoomState::Banned => UpdateType::Banned,
        RoomState::Left => UpdateType::Left,
    };

    let last_event = room.latest_event_item().await;
    let mut message = Message {
        event_id: "".to_string(),
        sender: "".to_string(),
        content: "".to_string(),
        timestamp: 0,
        message_type: MessageType::Message,
    };
    if last_event.is_some() {
        let last_event = last_event.unwrap();
        let id = &last_event.event_id().expect("").to_string();
        let mut message_content = "".to_string();
        let content = &last_event.content();
        if content.is_message() {
            let m_c = content.as_message().unwrap().body();
            message_content = m_c.to_string();
        }
        let sender = &last_event.sender().to_string();
        let timestamp = u64::from(last_event.timestamp().0);
        message = Message {
            event_id: id.clone(),
            content: message_content,
            message_type: MessageType::Message,
            sender: sender.clone(),
            timestamp: timestamp,
        };
    } else {
        log_error(format!("No last event found for room {:?}", room_id));
    }

    return RoomUpdate {
        room_id,
        raw_name,
        display_name,
        is_dm: Some(is_dm),
        update_type: update_type,
        unread_notifications: Some(unread_notification_count),
        unread_highlight: Some(unread_highlight_count),
        unread_mentions: Some(unread_mentions_count),
        unread_messages: Some(unread_messages),
        message: Some(message),
    };
}

pub fn get_all_rooms() -> Vec<RoomUpdate> {
    let runtime = GLOBAL_RUNTIME
        .get() // get the runtime
        .expect("No global runtime found");

    runtime.block_on(async {
        match GLOBAL_APP.get() {
            Some(app) => {
                let mut room_updates = Vec::new();
                let rooms_lock = app.room_list.rooms.lock().unwrap();

                for room in rooms_lock.iter() {
                    let update = get_room_update_data(room).await;
                    room_updates.push(update);
                }

                room_updates
            }
            None => {
                log_error(format!("No global app found"));
                Vec::new()
            }
        }
    })
}

pub fn subscribe_to_all_room_updates(stream: StreamSink<RoomUpdate>) {
    let runtime = GLOBAL_RUNTIME
        .get() // get the runtime
        .expect("No global runtime found");

    runtime.block_on(async {
        match GLOBAL_APP.get() {
            Some(app) => loop {
                match &app.client.subscribe_to_all_room_updates().recv().await {
                    Ok(updates) => {
                        log_info(format!("Received room update: {:?}", updates));
                        for room_id in &updates.joined {
                            match &app.client.get_room(&room_id.0) {
                                Some(room) => {
                                    let mut update = get_room_update_data(room).await;
                                    update.update_type = UpdateType::Joined;
                                    let _ = stream.add(update);
                                }

                                None => {
                                    log_warn(format!("Room not found: {}", room_id.0));
                                }
                            }
                        }

                        for room_id in &updates.invited {
                            match &app.client.get_room(&room_id.0) {
                                Some(room) => {
                                    let mut update = get_room_update_data(room).await;
                                    update.update_type = UpdateType::Invited;
                                    let _ = stream.add(update);
                                }

                                None => {
                                    log_warn(format!("Room not found: {}", room_id.0));
                                }
                            }
                        }

                        for room_id in &updates.left {
                            match &app.client.get_room(&room_id.0) {
                                Some(room) => {
                                    let mut update = get_room_update_data(room).await;
                                    update.update_type = UpdateType::Left;
                                    let _ = stream.add(update);
                                }

                                None => {
                                    log_warn(format!("Room not found: {}", room_id.0));
                                }
                            }
                        }
                        
                    }
                    Err(e) => {
                        log_error(format!("Error receiving room updates: {}", e));
                    }
                }
            },
            None => {
                log_error(format!("No global app found"));
                return;
            }
        }
    });
}

pub fn send_message(room_id: String, content: String) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");

            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = &app.client.get_room(&room_id).ok_or("Room not found")?;

            let event_id = room
                .send(
                    matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(
                        &content,
                    ),
                )
                .await
                .map_err(|e| e.to_string())?;

            Ok(event_id.event_id.to_string())
        })
    })
}


pub fn create_direct_room(user_id: String) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");

            use matrix_sdk::ruma::UserId;
            use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;

            let user_id = UserId::parse(&user_id).map_err(|e| e.to_string())?;
            
            let mut request = CreateRoomRequest::new();
            request.is_direct = true;
            request.invite = vec![user_id.to_owned()];
            request.preset = Some(matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::TrustedPrivateChat);

            let response = app.client
                .create_room(request)
                .await
                .map_err(|e| e.to_string())?;

            Ok(response.room_id().to_string())
        })
    })
}

pub fn create_group_room(name: String, user_ids: Vec<String>) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");

            use matrix_sdk::ruma::UserId;
            use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;

            let mut request = CreateRoomRequest::new();
            request.name = Some(name);
            request.is_direct = false;
            request.preset = Some(matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::PrivateChat);

            // Parse and add invited users
            let mut invites = Vec::new();
            for user_id_str in user_ids {
                let user_id = UserId::parse(&user_id_str).map_err(|e| e.to_string())?;
                invites.push(user_id);
            }
            request.invite = invites;

            let response = app.client
                .create_room(request)
                .await
                .map_err(|e| e.to_string())?;

            Ok(response.room_id().to_string())
        })
    })
}


pub fn join_room(room_id: String) -> Result<String, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = &app.client.get_room(&room_id).ok_or("Room not found")?;
            let _ = room.join().await.map_err(|e| e.to_string())?;
            Ok(room_id.to_string())
        })
    })
}

pub fn leave_room(room_id: String) -> Result<String, String> {  
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");
            let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
            let room = &app.client.get_room(&room_id).ok_or("Room not found")?;
            let _ = room.leave().await.map_err(|e| e.to_string())?; 
            Ok(room_id.to_string())
        })
    })
}
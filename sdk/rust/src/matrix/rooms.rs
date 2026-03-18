use std::{collections::HashMap, sync::Arc};

use flutter_rust_bridge::frb;

use eyeball_im::Vector;
use matrix_sdk::{
    ruma::{OwnedRoomId, RoomId},
    Client, Room, RoomState,
};
use matrix_sdk_ui::timeline::{LatestEventValue, RoomExt};
use std::sync::Mutex;
use tokio::sync::Mutex as AsyncMutex;

use crate::{
    frb_generated::StreamSink,
    matrix::{
        status::StatusHandle,
        sync_service::App,
        timelines::{Message, MessageType},
    },
};
use tracing::{debug, error, warn};

// RoomUpdate moved to api module

pub type Rooms = Arc<Mutex<Vector<Room>>>;

#[derive(Clone)]
#[frb(ignore)]
pub struct RoomList {
    pub status_handle: StatusHandle,
    pub rooms: Rooms,
    /// Extra information about rooms (written by sync listen_task).
    pub room_infos: RoomInfos,
}

impl RoomList {
    pub fn new(rooms: Rooms, room_infos: RoomInfos, status_handle: StatusHandle) -> Self {
        Self {
            rooms,
            status_handle,
            room_infos,
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

#[derive(Clone)]
pub enum UpdateType {
    Joined,
    Left,
    Invited,
    Knocked,
    Banned,
}

#[derive(Clone)]
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

/// Result of sending a message: event_id and a room update with the sent message as last.
/// Use the room_update to refresh the room list so the UI shows the correct last message
/// immediately (the SDK's latest_event is updated asynchronously and may be one step behind).
pub struct SendMessageResult {
    pub event_id: String,
    pub room_update: RoomUpdate,
}

pub(crate) async fn get_room_update_data(room: &Room) -> RoomUpdate {
    let room_id = room.room_id().to_string();
    let raw_name = room.name().map(|name| name.to_string());
    let display_name = room.cached_display_name().map(|name| name.to_string());
    let is_dm = room.is_direct().await.unwrap_or(false);
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

    let last_event = room.latest_event().await;
    let mut message = Message {
        event_id: "".to_string(),
        sender: "".to_string(),
        content: "".to_string(),
        timestamp: 0,
        message_type: MessageType::Message,
    };
    match &last_event {
        LatestEventValue::Remote {
            timestamp,
            sender,
            content,
            ..
        }
        | LatestEventValue::Local {
            timestamp,
            sender,
            content,
            ..
        } => {
            let message_content = content
                .as_message()
                .map(|m| m.body().to_string())
                .unwrap_or_else(|| "".to_string());
            message = Message {
                event_id: "".to_string(), // LatestEventValue does not expose event_id
                sender: sender.to_string(),
                content: message_content,
                timestamp: u64::from(timestamp.0),
                message_type: MessageType::Message,
            };
        }
        LatestEventValue::None | LatestEventValue::RemoteInvite { .. } => {
            error!("No last event found for room {:?}", room_id);
        }
    }

    RoomUpdate {
        room_id,
        raw_name,
        display_name,
        is_dm: Some(is_dm),
        update_type,
        unread_notifications: Some(unread_notification_count),
        unread_highlight: Some(unread_highlight_count),
        unread_mentions: Some(unread_mentions_count),
        unread_messages: Some(unread_messages),
        message: Some(message),
    }
}

/// Merge one room update into the list (by room_id). Left = remove; else replace or insert.
pub(crate) fn merge_room_update_into_list(list: &mut Vec<RoomUpdate>, update: RoomUpdate) {
    use UpdateType::Left;
    if matches!(update.update_type, Left) {
        list.retain(|r| r.room_id != update.room_id);
        return;
    }
    if let Some(pos) = list.iter().position(|r| r.room_id == update.room_id) {
        list[pos] = update;
    } else {
        list.push(update);
    }
}

/// Sort room list by last activity descending (most recent first).
pub(crate) fn sort_room_list_by_activity(list: &mut [RoomUpdate]) {
    list.sort_by(|a, b| {
        let ts_a = a.message.as_ref().map(|m| m.timestamp).unwrap_or(0);
        let ts_b = b.message.as_ref().map(|m| m.timestamp).unwrap_or(0);
        ts_b.cmp(&ts_a)
    });
}

/// Room list for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub(crate) async fn get_all_rooms(app: &App) -> Vec<RoomUpdate> {
    let rooms_snapshot: Vec<matrix_sdk::Room> = {
        let rooms_lock = app.room_list.rooms.lock().unwrap();
        rooms_lock.iter().cloned().collect()
    };

    let mut room_updates = Vec::new();
    for room in &rooms_snapshot {
        let update = get_room_update_data(room).await;
        room_updates.push(update);
    }

    room_updates
}

/// Subscribe to room updates for the given app (used by [crate::api::matrix_client::MatrixClient]). Runs until stream is dropped.
pub(crate) async fn subscribe_to_all_room_updates(client: &Client, stream: StreamSink<RoomUpdate>) {
    loop {
        match client.subscribe_to_all_room_updates().recv().await {
            Ok(updates) => {
                debug!("Received room update: {} joined, {} invited, {} left, {} knocked",
                    updates.joined.len(), updates.invited.len(), updates.left.len(), updates.knocked.len());
                for room_id in &updates.joined {
                    match client.get_room(&room_id.0) {
                        Some(room) => {
                            let mut update = get_room_update_data(&room).await;
                            update.update_type = UpdateType::Joined;
                            let _ = stream.add(update);
                        }
                        None => {
                            warn!("Room not found: {}", room_id.0);
                        }
                    }
                }
                for room_id in &updates.invited {
                    match client.get_room(&room_id.0) {
                        Some(room) => {
                            let mut update = get_room_update_data(&room).await;
                            update.update_type = UpdateType::Invited;
                            let _ = stream.add(update);
                        }
                        None => {
                            warn!("Room not found: {}", room_id.0);
                        }
                    }
                }
                for room_id in &updates.left {
                    match client.get_room(&room_id.0) {
                        Some(room) => {
                            let mut update = get_room_update_data(&room).await;
                            update.update_type = UpdateType::Left;
                            let _ = stream.add(update);
                        }
                        None => {
                            warn!("Room not found: {}", room_id.0);
                        }
                    }
                }
                for room_id in &updates.knocked {
                    match client.get_room(&room_id.0) {
                        Some(room) => {
                            let mut update = get_room_update_data(&room).await;
                            update.update_type = UpdateType::Knocked;
                            let _ = stream.add(update);
                        }
                        None => {
                            warn!("Room not found: {}", room_id.0);
                        }
                    }
                }
            }
            Err(e) => {
                error!("Room updates stream closed or lagged: {}", e);
                break;
            }
        }
    }
}

/// Runs until stream is dropped. Receives sync room updates, merges into cache, and sends full list each time.
pub(crate) async fn subscribe_to_room_list_loop(
    client: Client,
    cache: Arc<AsyncMutex<Vec<RoomUpdate>>>,
    stream: std::sync::Arc<StreamSink<Vec<RoomUpdate>>>,
) {
    loop {
        match client.subscribe_to_all_room_updates().recv().await {
            Ok(updates) => {
                debug!(
                    "Room list: {} joined, {} invited, {} left, {} knocked",
                    updates.joined.len(),
                    updates.invited.len(),
                    updates.left.len(),
                    updates.knocked.len()
                );
                let mut list = cache.lock().await;
                for room_id in &updates.joined {
                    if let Some(room) = client.get_room(&room_id.0) {
                        let mut update = get_room_update_data(&room).await;
                        update.update_type = UpdateType::Joined;
                        merge_room_update_into_list(&mut list, update);
                    }
                }
                for room_id in &updates.invited {
                    if let Some(room) = client.get_room(&room_id.0) {
                        let mut update = get_room_update_data(&room).await;
                        update.update_type = UpdateType::Invited;
                        merge_room_update_into_list(&mut list, update);
                    }
                }
                for room_id in &updates.left {
                    if let Some(room) = client.get_room(&room_id.0) {
                        let mut update = get_room_update_data(&room).await;
                        update.update_type = UpdateType::Left;
                        merge_room_update_into_list(&mut list, update);
                    }
                }
                for room_id in &updates.knocked {
                    if let Some(room) = client.get_room(&room_id.0) {
                        let mut update = get_room_update_data(&room).await;
                        update.update_type = UpdateType::Knocked;
                        merge_room_update_into_list(&mut list, update);
                    }
                }
                sort_room_list_by_activity(&mut list);
                let _ = stream.add(list.clone());
            }
            Err(e) => {
                error!("Room list stream closed or lagged: {}", e);
                break;
            }
        }
    }
}

/// Send a message in the given app (used by [crate::api::matrix_client::MatrixClient]).
/// Returns the event_id and a room update with the sent message as the last message,
/// so the UI can refresh the room list immediately without waiting for the SDK's
/// latest_event cache to update (which can be one step behind after send).
pub(crate) async fn send_message(
    client: &Client,
    room_id: String,
    content: String,
) -> Result<SendMessageResult, String> {
    let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&room_id_parsed).ok_or("Room not found")?;
    let sender = client.user_id().ok_or("Not logged in")?.to_string();

    let result = room
        .send(
            matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(&content),
        )
        .await
        .map_err(|e| e.to_string())?;

    let event_id = result.response.event_id.to_string();
    let timestamp_ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0);

    let mut room_update = get_room_update_data(&room).await;
    room_update.message = Some(Message {
        event_id: event_id.clone(),
        sender,
        content: content.clone(),
        timestamp: timestamp_ms,
        message_type: MessageType::Message,
    });

    Ok(SendMessageResult {
        event_id,
        room_update,
    })
}

pub(crate) async fn create_direct_room(client: &Client, user_id: String) -> Result<String, String> {
    use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;
    use matrix_sdk::ruma::UserId;

    let user_id = UserId::parse(&user_id).map_err(|e| e.to_string())?;

    let mut request = CreateRoomRequest::new();
    request.is_direct = true;
    request.invite = vec![user_id.to_owned()];
    request.preset =
        Some(matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::TrustedPrivateChat);

    let room = client
        .create_room(request)
        .await
        .map_err(|e| e.to_string())?;

    room.enable_encryption().await.map_err(|e| e.to_string())?;

    Ok(room.room_id().to_string())
}

pub(crate) async fn create_group_room(
    client: &Client,
    name: String,
    user_ids: Vec<String>,
) -> Result<String, String> {
    use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;
    use matrix_sdk::ruma::UserId;

    let mut request = CreateRoomRequest::new();
    request.name = Some(name);
    request.is_direct = false;
    request.preset =
        Some(matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::PrivateChat);

    let mut invites = Vec::new();
    for user_id_str in user_ids {
        let user_id = UserId::parse(&user_id_str).map_err(|e| e.to_string())?;
        invites.push(user_id);
    }
    request.invite = invites;

    let room = client
        .create_room(request)
        .await
        .map_err(|e| e.to_string())?;

    room.enable_encryption().await.map_err(|e| e.to_string())?;

    Ok(room.room_id().to_string())
}

pub(crate) async fn join_room(client: &Client, room_id: String) -> Result<String, String> {
    let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&room_id_parsed).ok_or("Room not found")?;
    let _ = room.join().await.map_err(|e| e.to_string())?;
    Ok(room_id_parsed.to_string())
}

pub(crate) async fn leave_room(client: &Client, room_id: String) -> Result<String, String> {
    let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&room_id_parsed).ok_or("Room not found")?;
    let _ = room.leave().await.map_err(|e| e.to_string())?;
    Ok(room_id_parsed.to_string())
}

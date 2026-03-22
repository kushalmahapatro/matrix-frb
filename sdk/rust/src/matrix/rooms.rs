use std::{collections::HashMap, ops::Deref, sync::Arc};

use flutter_rust_bridge::frb;

use eyeball_im::Vector;
use futures::future::join_all;
use matrix_sdk::{
    ruma::{
        events::{
            room::encryption::RoomEncryptionEventContent,
            InitialStateEvent,
        },
        OwnedRoomId, RoomId,
    },
    Client, Room, RoomState,
};
use matrix_sdk_ui::room_list_service::RoomListItem;
use matrix_sdk_ui::timeline::{LatestEventValue, RoomExt};
use std::sync::Mutex;
use tokio::sync::Mutex as AsyncMutex;

use crate::{
    frb_generated::StreamSink,
    matrix::{
        client::format_user_id_for_display,
        sync_service::App,
        timelines::{
            self, EventSendStateKind, Message, MessageType, RoomMessageKind,
        },
    },
};
use tracing::{debug, error, warn};

// RoomUpdate moved to api module

/// Rooms as ordered by sliding sync + room list service (matches multiverse / Element).
pub type Rooms = Arc<Mutex<Vector<RoomListItem>>>;

#[derive(Clone)]
#[frb(ignore)]
pub struct RoomList {
    pub rooms: Rooms,
    /// Extra information about rooms (written by sync listen_task).
    pub room_infos: RoomInfos,
}

impl RoomList {
    pub fn new(rooms: Rooms, room_infos: RoomInfos) -> Self {
        Self { rooms, room_infos }
    }

    pub fn get_room_by_id(&self, room_id: &str) -> Option<Room> {
        let rooms = self.rooms.lock().unwrap();
        rooms
            .iter()
            .find(|item| item.room_id().as_str() == room_id)
            .map(|item| item.clone().into_inner())
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

pub(crate) async fn get_room_update_data(room: &Room, own_user_id: Option<&str>) -> RoomUpdate {
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
        transaction_id: "".to_string(),
        sender: "".to_string(),
        content: "".to_string(),
        timestamp: 0,
        message_type: MessageType::Message,
        room_msg_kind: crate::matrix::timelines::RoomMessageKind::Other,
        send_state: EventSendStateKind::Delivered,
        send_error: "".to_string(),
        send_recoverable: false,
        is_own: false,
        media_mimetype: String::new(),
        media_size_bytes: 0,
        media_blurhash: String::new(),
        media_preview_width: 0,
        media_preview_height: 0,
        in_reply_to_event_id: String::new(),
        in_reply_to_sender: String::new(),
        in_reply_to_preview: String::new(),
        in_reply_to_room_msg_kind: crate::matrix::timelines::RoomMessageKind::Other,
        in_reply_to_media_mimetype: String::new(),
        in_reply_to_media_size_bytes: 0,
        in_reply_to_media_blurhash: String::new(),
        in_reply_to_media_preview_width: 0,
        in_reply_to_media_preview_height: 0,
        in_reply_to_parent_redacted: false,
        reactions: vec![],
        poll_options_json: String::new(),
        poll_state_json: String::new(),
        link_previews_json: "[]".to_string(),
        is_redacted: false,
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
            let base_latest = room.deref().latest_event();
            let event_id_str = base_latest
                .event_id()
                .map(|id| id.to_string())
                .unwrap_or_default();
            let poll_options_json = content
                .as_poll()
                .map(|p| timelines::poll_options_json_from_state(p))
                .unwrap_or_default();
            let poll_state_json = content
                .as_poll()
                .map(|p| timelines::poll_state_json_from_state(p))
                .unwrap_or_default();
            let message_content = content
                .as_poll()
                .map(|p| timelines::poll_body_from_state(p))
                .or_else(|| content.as_message().map(|m| m.body().to_string()))
                .unwrap_or_default();
            let room_msg_kind = if content.is_poll() {
                RoomMessageKind::Poll
            } else {
                content
                    .as_message()
                    .map(timelines::room_msg_kind_from_sdk_ui_message)
                    .unwrap_or(RoomMessageKind::Other)
            };
            let (media_mimetype, media_size_bytes) = content
                .as_message()
                .map(|m| crate::matrix::timelines::sdk_ui_message_media_info(m))
                .unwrap_or((String::new(), 0));
            let (media_blurhash, media_preview_width, media_preview_height) = content
                .as_message()
                .map(|m| crate::matrix::timelines::sdk_ui_message_media_preview(m))
                .unwrap_or((String::new(), 0, 0));
            let link_previews_json = content
                .as_message()
                .map(|m| crate::matrix::timelines::link_previews_json_for_sdk_message(m))
                .unwrap_or_else(|| "[]".to_string());
            let sender_str = sender.to_string();
            let is_own = own_user_id.is_some_and(|o| o == sender_str.as_str());
            message = Message {
                event_id: event_id_str,
                transaction_id: "".to_string(),
                sender: format_user_id_for_display(&sender_str),
                content: message_content,
                timestamp: u64::from(timestamp.0),
                message_type: MessageType::Message,
                room_msg_kind,
                send_state: EventSendStateKind::Delivered,
                send_error: "".to_string(),
                send_recoverable: false,
                is_own,
                media_mimetype,
                media_size_bytes,
                media_blurhash,
                media_preview_width,
                media_preview_height,
                in_reply_to_event_id: String::new(),
                in_reply_to_sender: String::new(),
                in_reply_to_preview: String::new(),
                in_reply_to_room_msg_kind: crate::matrix::timelines::RoomMessageKind::Other,
                in_reply_to_media_mimetype: String::new(),
                in_reply_to_media_size_bytes: 0,
                in_reply_to_media_blurhash: String::new(),
                in_reply_to_media_preview_width: 0,
                in_reply_to_media_preview_height: 0,
                in_reply_to_parent_redacted: false,
                reactions: vec![],
                poll_options_json,
                poll_state_json,
                link_previews_json,
                is_redacted: content.is_redacted(),
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
///
/// `timeline_list_subscriber_cache`: optional per-room full lists from [subscribe_to_timeline_list];
/// when set, overrides preview for that room (can be ahead of the sync timeline vector).
pub(crate) async fn get_all_rooms(
    app: &App,
    own_user_id: Option<String>,
    timeline_list_subscriber_cache: Option<&HashMap<String, Vec<Message>>>,
) -> Vec<RoomUpdate> {
    let rooms_snapshot: Vec<RoomListItem> = {
        let rooms_lock = app.room_list.rooms.lock().unwrap();
        rooms_lock.iter().cloned().collect()
    };

    let own = own_user_id.as_deref();
    let mut list = join_all(
        rooms_snapshot
            .iter()
            .map(|item| get_room_update_data(&**item, own)),
    )
    .await;

    // `Room::latest_event()` can skip redacted tails and show the previous message. The
    // sliding-sync UI timeline (`app.timelines`) matches conversation order — use its last
    // real message row for listing preview so reload keeps "Message deleted" etc.
    for update in list.iter_mut() {
        if let Some(msgs) = timelines::get_timeline_items_from_timelines_map(
            &app.timelines,
            &update.room_id,
            own,
        ) {
            if let Some(last) = timelines::last_message_row_for_room_preview(&msgs) {
                update.message = Some(last);
            }
        }
    }

    if let Some(sub_cache) = timeline_list_subscriber_cache {
        for update in list.iter_mut() {
            if let Some(msgs) = sub_cache.get(&update.room_id) {
                if let Some(last) = timelines::last_message_row_for_room_preview(msgs) {
                    update.message = Some(last);
                }
            }
        }
    }

    sort_room_list_by_activity(&mut list);
    list
}

/// Full snapshot for subscribers (sorted like the merged room-list cache).
pub(crate) async fn push_full_room_list_to_subscribers(
    app: &App,
    cache: &Arc<AsyncMutex<Vec<RoomUpdate>>>,
    sink: &Arc<StreamSink<Vec<RoomUpdate>>>,
    own_user_id: Option<String>,
    timeline_list_subscriber_cache: Option<&HashMap<String, Vec<Message>>>,
) {
    let list = get_all_rooms(app, own_user_id, timeline_list_subscriber_cache).await;
    {
        let mut c = cache.lock().await;
        *c = list.clone();
    }
    let _ = sink.add(list);
}

/// Subscribe to room updates for the given app (used by [crate::api::matrix_client::MatrixClient]). Runs until stream is dropped.
pub(crate) async fn subscribe_to_all_room_updates(client: &Client, stream: StreamSink<RoomUpdate>) {
    loop {
        match client.subscribe_to_all_room_updates().recv().await {
            Ok(updates) => {
                let own = client.user_id().map(|u| u.to_string());
                let own_ref = own.as_deref();
                debug!(
                    "Received room update: {} joined, {} invited, {} left, {} knocked",
                    updates.joined.len(),
                    updates.invited.len(),
                    updates.left.len(),
                    updates.knocked.len()
                );
                for room_id in &updates.joined {
                    match client.get_room(&room_id.0) {
                        Some(room) => {
                            let mut update = get_room_update_data(&room, own_ref).await;
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
                            let mut update = get_room_update_data(&room, own_ref).await;
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
                            let mut update = get_room_update_data(&room, own_ref).await;
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
                            let mut update = get_room_update_data(&room, own_ref).await;
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

/// `m.room.encryption` at creation so the room is E2EE from the first event (no plaintext window).
fn new_room_encryption_initial_state(
) -> Vec<matrix_sdk::ruma::serde::Raw<matrix_sdk::ruma::events::AnyInitialStateEvent>> {
    vec![InitialStateEvent::with_empty_state_key(
        RoomEncryptionEventContent::with_recommended_defaults(),
    )
    .to_raw_any()]
}

/// Turn on Megolm if needed, wait for sync, then fail if the room is still not encrypted.
async fn ensure_created_room_is_e2ee(room: &Room) -> Result<(), String> {
    room.enable_encryption()
        .await
        .map_err(|e| format!("Failed to enable end-to-end encryption: {e}"))?;
    let encrypted = room
        .latest_encryption_state()
        .await
        .map_err(|e| format!("Failed to read room encryption state: {e}"))?
        .is_encrypted();
    if !encrypted {
        return Err(
            "Room was created but is not end-to-end encrypted (check server support and your power level)"
                .to_string(),
        );
    }
    Ok(())
}

pub(crate) async fn create_direct_room(client: &Client, user_id: String) -> Result<String, String> {
    use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;
    use matrix_sdk::ruma::UserId;

    let user_id = UserId::parse(&user_id).map_err(|e| e.to_string())?;

    let mut request = CreateRoomRequest::new();
    request.initial_state = new_room_encryption_initial_state();
    request.is_direct = true;
    request.invite = vec![user_id.to_owned()];
    request.preset =
        Some(matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset::TrustedPrivateChat);

    let room = client
        .create_room(request)
        .await
        .map_err(|e| e.to_string())?;

    ensure_created_room_is_e2ee(&room).await?;

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
    request.initial_state = new_room_encryption_initial_state();
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

    ensure_created_room_is_e2ee(&room).await?;

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

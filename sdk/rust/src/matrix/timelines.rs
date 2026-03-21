use eyeball_im::Vector;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use matrix_sdk::ruma::events::room::message::{
    FileMessageEventContent, MessageType as RumaMessageType,
};
use matrix_sdk::ruma::UInt;
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::Client;
use matrix_sdk_ui::timeline::{
    EventSendState, EventTimelineItem, Message as SdkUiRoomMessage, RoomExt, TimelineFocus,
    TimelineItem, TimelineItemKind,
};
use matrix_sdk_ui::Timeline as SdkTimeline;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use tokio::sync::Mutex as AsyncMutex;
use tokio::sync::OnceCell;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::frb_generated::StreamSink;
use crate::matrix::rooms;
use tracing::{debug, error};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[frb]
pub enum EventSendStateKind {
    /// Remote event, or local echo already confirmed / sent.
    Delivered,
    /// Local echo: sending or waiting for network.
    Pending,
    /// Local echo: send failed (see [Message::send_error]; retry if [Message::send_recoverable]).
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    Message,
    DateDivider,
    ReadMarker,
    TimelineStart,
}

/// Classification of an `m.room.message` (for media previews). Non-message timeline rows use [RoomMessageKind::Other].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum RoomMessageKind {
    Text,
    Image,
    File,
    Video,
    Audio,
    Other,
}

/// `m.file` is still a file message in Matrix, but we classify by filename / mimetype so the UI
/// uses image / video / audio viewers (e.g. media_kit) instead of a generic file row.
fn room_kind_for_file_content(f: &FileMessageEventContent) -> RoomMessageKind {
    let name = f.filename();
    let mime = f.info.as_ref().and_then(|i| i.mimetype.as_deref());
    if file_suggests_video(name, mime) {
        return RoomMessageKind::Video;
    }
    if file_suggests_image(name, mime) {
        return RoomMessageKind::Image;
    }
    if file_suggests_audio(name, mime) {
        return RoomMessageKind::Audio;
    }
    RoomMessageKind::File
}

fn file_suggests_video(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| {
        m.starts_with("video/")
            || m == "application/mp4"
            || m == "application/x-matroska"
    }) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "mp4" | "mov" | "webm" | "mkv" | "m4v" | "avi" | "mpeg" | "mpg"
    )
}

fn file_suggests_image(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| m.starts_with("image/")) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "heic" | "heif"
    )
}

fn file_suggests_audio(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| m.starts_with("audio/")) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "mp3" | "m4a" | "aac" | "ogg" | "opus" | "flac" | "wav" | "aiff"
    )
}

pub(crate) fn room_msg_kind_from_sdk_ui_message(msg: &SdkUiRoomMessage) -> RoomMessageKind {
    match msg.msgtype() {
        RumaMessageType::Text(_) | RumaMessageType::Notice(_) | RumaMessageType::Emote(_) => {
            RoomMessageKind::Text
        }
        RumaMessageType::Image(_) => RoomMessageKind::Image,
        RumaMessageType::File(f) => room_kind_for_file_content(f),
        RumaMessageType::Video(_) => RoomMessageKind::Video,
        RumaMessageType::Audio(_) => RoomMessageKind::Audio,
        _ => RoomMessageKind::Other,
    }
}

#[cfg(test)]
mod file_kind_tests {
    use super::*;
    use matrix_sdk::ruma::events::room::message::FileMessageEventContent;
    use matrix_sdk::ruma::owned_mxc_uri;

    fn file_msg(filename: Option<&str>, body: &str, mime: Option<&str>) -> FileMessageEventContent {
        let url = owned_mxc_uri!("mxc://example.org/123");
        let mut c = FileMessageEventContent::plain(body.to_owned(), url);
        c.filename = filename.map(String::from);
        if mime.is_some() {
            let mut info = matrix_sdk::ruma::events::room::message::FileInfo::new();
            info.mimetype = mime.map(String::from);
            c.info = Some(Box::new(info));
        }
        c
    }

    #[test]
    fn file_mp4_by_extension_is_video_kind() {
        let f = file_msg(Some("clip.mp4"), "clip.mp4", None);
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::Video);
    }

    #[test]
    fn file_no_ext_video_mime_is_video() {
        let f = file_msg(None, "binary", Some("video/mp4"));
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::Video);
    }

    #[test]
    fn file_pdf_stays_file() {
        let f = file_msg(Some("a.pdf"), "a.pdf", Some("application/pdf"));
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::File);
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageUpdateType {
    Reset,
    Truncate,
    Remove,
    Set,
    Insert,
    PopBack,
    PopFront,
    PushBack,
    PushFront,
    Clear,
    Append,
    TimelineStart,
    ReadMarker,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub event_id: String,
    /// Matrix transaction id for local echoes (empty for remote-only items).
    pub transaction_id: String,
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
    pub message_type: MessageType,
    /// `m.room.message` kind for rendering (image/file/video…).
    pub room_msg_kind: RoomMessageKind,
    /// Send state for timeline events (local echo progress / failures).
    pub send_state: EventSendStateKind,
    /// Human-readable error when [EventSendStateKind::Failed].
    pub send_error: String,
    /// Whether the SDK considers the failure recoverable (e.g. retry via [crate::api::matrix_client::MatrixClient::retry_failed_send]).
    pub send_recoverable: bool,
    /// `true` when the event sender is the logged-in user (outgoing); virtual rows are `false`.
    pub is_own: bool,
    /// From `m.room.message` attachment `info.mimetype` when present.
    pub media_mimetype: String,
    /// From `m.room.message` attachment `info.size` when present (bytes).
    pub media_size_bytes: u64,
}

/// Sentinel for missing index/length in MessageUpdate (codegen uses usize, not Option<usize>).
pub const MESSAGE_UPDATE_NONE_INDEX: usize = usize::MAX;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageUpdate {
    pub message_update_type: MessageUpdateType,
    pub messages: Option<Vec<Message>>,
    /// Index for Insert/Set/Remove; use MESSAGE_UPDATE_NONE_INDEX when not applicable.
    pub index: usize,
    /// Length for Truncate; use MESSAGE_UPDATE_NONE_INDEX when not applicable.
    pub length: usize,
}

#[frb(ignore)]
pub struct Timeline {
    pub timeline: Arc<SdkTimeline>,
    pub items: Arc<StdMutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
    pub task: JoinHandle<()>,
}

#[frb(ignore)]
pub type Timelines = Arc<StdMutex<HashMap<OwnedRoomId, Timeline>>>;

#[frb(ignore)]
pub enum TimelineKind {
    Room {
        room: Option<OwnedRoomId>,
    },

    Thread {
        room: OwnedRoomId,
        thread_root: OwnedEventId,
        /// The threaded-focused timeline for this thread.
        timeline: Arc<OnceCell<Arc<Timeline>>>,
        /// Items in the thread timeline (to avoid recomputing them every single
        /// time).
        items: Arc<StdMutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
        /// Task listening to updates from the threaded timeline, to maintain
        /// the `items` field over time.
        task: JoinHandle<()>,
    },
}

#[frb(ignore)]
impl Clone for TimelineKind {
    fn clone(&self) -> Self {
        match self {
            TimelineKind::Room { room } => TimelineKind::Room { room: room.clone() },
            TimelineKind::Thread {
                room, thread_root, ..
            } => {
                // For thread timeline, create a new instance with default values
                // since JoinHandle and OnceCell can't be cloned
                TimelineKind::Thread {
                    room: room.clone(),
                    thread_root: thread_root.clone(),
                    timeline: Arc::new(OnceCell::new()),
                    items: Arc::new(StdMutex::new(Vector::new())),
                    task: tokio::spawn(async {}), // Empty task as placeholder
                }
            }
        }
    }
}

fn event_message_body(ev: &EventTimelineItem) -> String {
    ev.content()
        .as_message()
        .map(|msg| msg.body().to_string())
        .unwrap_or_default()
}

fn event_room_msg_kind(ev: &EventTimelineItem) -> RoomMessageKind {
    ev.content()
        .as_message()
        .map(room_msg_kind_from_sdk_ui_message)
        .unwrap_or(RoomMessageKind::Other)
}

fn optional_uint_to_u64(opt: Option<UInt>) -> u64 {
    opt.map(Into::into).unwrap_or(0)
}

/// Attachment `info.mimetype` / `info.size` for a UI timeline message (room list latest event, etc.).
pub(crate) fn sdk_ui_message_media_info(msg: &SdkUiRoomMessage) -> (String, u64) {
    match msg.msgtype() {
        RumaMessageType::Image(i) => {
            let mime = i
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(i.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::File(f) => {
            let mime = f
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(f.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::Video(v) => {
            let mime = v
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(v.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::Audio(a) => {
            let mime = a
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(a.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        _ => (String::new(), 0),
    }
}

fn event_media_attachment_info(ev: &EventTimelineItem) -> (String, u64) {
    let Some(msg) = ev.content().as_message() else {
        return (String::new(), 0);
    };
    sdk_ui_message_media_info(msg)
}

fn send_state_fields(ev: &EventTimelineItem) -> (EventSendStateKind, String, bool) {
    match ev.send_state() {
        None => (EventSendStateKind::Delivered, String::new(), false),
        Some(EventSendState::NotSentYet { .. }) => {
            (EventSendStateKind::Pending, String::new(), false)
        }
        Some(EventSendState::SendingFailed {
            error,
            is_recoverable,
        }) => (
            EventSendStateKind::Failed,
            error.to_string(),
            *is_recoverable,
        ),
        Some(EventSendState::Sent { .. }) => (EventSendStateKind::Delivered, String::new(), false),
    }
}

#[frb(ignore)]
pub fn get_message_from_timeline_item(item: &TimelineItem, own_user_id: Option<&str>) -> Message {
    match item.kind() {
        TimelineItemKind::Event(ev) => {
            let (send_state, send_error, send_recoverable) = send_state_fields(ev);
            let event_id = ev.event_id().map(|id| id.to_string()).unwrap_or_default();
            let transaction_id = ev
                .transaction_id()
                .map(|t| t.to_string())
                .unwrap_or_default();
            let sender = ev.sender().to_string();
            let is_own = own_user_id.is_some_and(|o| o == sender.as_str());
            let content = event_message_body(ev);
            let timestamp = u64::from(ev.timestamp().0);
            let (media_mimetype, media_size_bytes) = event_media_attachment_info(ev);
            Message {
                event_id,
                transaction_id,
                sender,
                content,
                timestamp,
                message_type: MessageType::Message,
                room_msg_kind: event_room_msg_kind(ev),
                send_state,
                send_error,
                send_recoverable,
                is_own,
                media_mimetype,
                media_size_bytes,
            }
        }
        TimelineItemKind::Virtual(virtual_timeline_item) => {
            match virtual_timeline_item {
                matrix_sdk_ui::timeline::VirtualTimelineItem::DateDivider(
                    milli_seconds_since_unix_epoch,
                ) => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    content: format!("Date: {}", u64::from(milli_seconds_since_unix_epoch.0)),
                    timestamp: u64::from(milli_seconds_since_unix_epoch.0),
                    message_type: MessageType::DateDivider,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::ReadMarker => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::ReadMarker,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::TimelineStart => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::TimelineStart,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                },
            }
        }
    }
}

/// Retry a failed local send (same as send-queue [SendHandle::unwedge]).
pub(crate) async fn retry_send_by_transaction_id(
    timeline: &SdkTimeline,
    transaction_id: &str,
) -> Result<(), String> {
    let items = timeline.items().await;
    for item in items.iter() {
        let Some(ev) = item.as_event() else {
            continue;
        };
        let Some(tid) = ev.transaction_id() else {
            continue;
        };
        if tid.as_str() != transaction_id {
            continue;
        }
        let Some(handle) = ev.local_echo_send_handle() else {
            return Err("No send handle for this local echo".to_string());
        };
        return handle.unwedge().await.map_err(|e| e.to_string());
    }
    Err("No failed local message with that transaction id".to_string())
}

/// Runs the timeline diff stream for the room; applies each diff to the room's cache and pushes full list.
/// When timeline list updates, also updates the room list with the last message so the listing shows it.
/// Stops when [cancel] is triggered (e.g. when the client re-subscribes for this room).
/// Caller must ensure cache_map and sinks_map contain an entry for room_id before spawning.
///
/// If [shared_timeline] is set, uses that [`SdkTimeline`] (same as [crate::matrix::sync_service] listen_task);
/// otherwise builds a separate live timeline (e.g. sync not started or room not yet in the sliding list).
pub(crate) async fn subscribe_to_timeline_list_loop(
    client: Client,
    room_id: String,
    shared_timeline: Option<Arc<SdkTimeline>>,
    own_user_id: Option<String>,
    cache_map: Arc<AsyncMutex<HashMap<String, Vec<Message>>>>,
    sinks_map: Arc<AsyncMutex<HashMap<String, Arc<StreamSink<Vec<Message>>>>>>,
    room_list_cache: Arc<AsyncMutex<Vec<rooms::RoomUpdate>>>,
    room_list_sink: Arc<AsyncMutex<Option<Arc<StreamSink<Vec<rooms::RoomUpdate>>>>>>,
    cancel: CancellationToken,
) {
    let room_id_parsed: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID for timeline list");
            return;
        }
    };

    let room = match client.get_room(room_id_parsed.as_ref()) {
        Some(room) => room,
        None => {
            error!("Room not found for timeline list");
            return;
        }
    };

    let timeline: Arc<SdkTimeline> = if let Some(t) = shared_timeline {
        t
    } else {
        let timeline = match room
            .timeline_builder()
            .with_focus(TimelineFocus::Live {
                hide_threaded_events: true,
            })
            .build()
            .await
        {
            Ok(t) => t,
            Err(e) => {
                error!("Failed to build timeline: {}", e);
                return;
            }
        };
        Arc::new(timeline)
    };

    // Load up to 50 messages initially so the list fills the screen and is scrollable;
    // if the room has fewer, we get all of them.
    const INITIAL_TIMELINE_PAGE_SIZE: u16 = 50;
    if let Err(e) = timeline
        .paginate_backwards(INITIAL_TIMELINE_PAGE_SIZE)
        .await
    {
        debug!(
            "Initial timeline paginate_backwards failed (non-fatal): {}",
            e
        );
    }

    let (_events, mut diff_stream) = timeline.subscribe().await;
    let own = own_user_id.as_deref();

    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                debug!("Timeline list loop cancelled for room {}", room_id);
                break;
            }
            next = diff_stream.next() => match next {
            Some(diffs) => {
                for diff in diffs {
                    let list = {
                        let mut cache_guard = cache_map.lock().await;
                        let vec = cache_guard.entry(room_id.clone()).or_insert_with(Vec::new);
                        apply_vector_diff_to_messages(vec, diff, own);
                        vec.clone()
                    };
                    let sinks_guard = sinks_map.lock().await;
                    if let Some(sink) = sinks_guard.get(&room_id) {
                        let _ = sink.add(list.clone());
                    }
                    drop(sinks_guard);
                    // Refresh room list with last message from timeline so listing shows it
                    if let Some(last_msg) = list.last().cloned() {
                        let mut update = rooms::get_room_update_data(&room, own).await;
                        update.message = Some(last_msg);
                        let mut cache = room_list_cache.lock().await;
                        rooms::merge_room_update_into_list(&mut cache, update);
                        rooms::sort_room_list_by_activity(&mut cache);
                        let list_to_push = cache.clone();
                        drop(cache);
                        let sink_guard = room_list_sink.lock().await;
                        if let Some(ref s) = *sink_guard {
                            let _ = s.add(list_to_push);
                        }
                    }
                }
            }
            None => {
                debug!("Timeline list stream ended for room {}", room_id);
                break;
            }
            }
        }
    }
}

fn messages_same_identity(a: &Message, b: &Message) -> bool {
    if !a.event_id.is_empty() && !b.event_id.is_empty() && a.event_id == b.event_id {
        return true;
    }
    if !a.transaction_id.is_empty()
        && !b.transaction_id.is_empty()
        && a.transaction_id == b.transaction_id
    {
        return true;
    }
    false
}

/// Push message only if no message with the same event_id / transaction_id is already in the list.
/// Avoids duplicates when send_message has already appended and the timeline diff also emits it.
fn push_if_not_duplicate(vec: &mut Vec<Message>, msg: Message) {
    let has = vec.iter().any(|m| messages_same_identity(m, &msg));
    if !has {
        vec.push(msg);
    }
}

/// Insert at front only if not duplicate by identity.
fn push_front_if_not_duplicate(vec: &mut Vec<Message>, msg: Message) {
    let has = vec.iter().any(|m| messages_same_identity(m, &msg));
    if !has {
        vec.insert(0, msg);
    }
}

/// Insert at index only if not duplicate by identity.
fn insert_if_not_duplicate(vec: &mut Vec<Message>, index: usize, msg: Message) {
    let has = vec.iter().any(|m| messages_same_identity(m, &msg));
    if !has && index <= vec.len() {
        vec.insert(index, msg);
    }
}

/// Clone the shared UI timeline for a room (same instance as the sync listen_task).
pub(crate) fn clone_timeline_arc(
    timelines: &Timelines,
    room_id: &OwnedRoomId,
) -> Option<Arc<SdkTimeline>> {
    let guard = timelines.lock().ok()?;
    guard.get(room_id).map(|t| t.timeline.clone())
}

/// Current messages from the sync-owned item vector (no extra SDK timeline).
pub(crate) fn get_timeline_items_from_timelines_map(
    timelines: &Timelines,
    room_id: &str,
    own_user_id: Option<&str>,
) -> Option<Vec<Message>> {
    let room_id: OwnedRoomId = room_id.parse().ok()?;
    let guard = timelines.lock().ok()?;
    let t = guard.get(&room_id)?;
    let items = t.items.lock().ok()?;
    Some(
        items
            .iter()
            .map(|v| get_message_from_timeline_item(v.as_ref(), own_user_id))
            .collect(),
    )
}

/// Snapshot from the shared UI timeline (same underlying object as sync).
pub(crate) async fn messages_from_sdk_timeline(
    timeline: &SdkTimeline,
    own_user_id: Option<&str>,
) -> Vec<Message> {
    let items = timeline.items().await;
    items
        .iter()
        .map(|item| get_message_from_timeline_item(item.as_ref(), own_user_id))
        .collect()
}

fn apply_vector_diff_to_messages(
    vec: &mut Vec<Message>,
    diff: matrix_sdk_ui::eyeball_im::VectorDiff<Arc<matrix_sdk_ui::timeline::TimelineItem>>,
    own_user_id: Option<&str>,
) {
    use matrix_sdk_ui::eyeball_im::VectorDiff;
    match diff {
        VectorDiff::Reset { values } => {
            *vec = values
                .iter()
                .map(|v| get_message_from_timeline_item(v.as_ref(), own_user_id))
                .collect();
        }
        VectorDiff::Append { values } => {
            for value in values {
                push_if_not_duplicate(
                    vec,
                    get_message_from_timeline_item(value.as_ref(), own_user_id),
                );
            }
        }
        VectorDiff::Clear => vec.clear(),
        VectorDiff::PushFront { value } => {
            push_front_if_not_duplicate(
                vec,
                get_message_from_timeline_item(value.as_ref(), own_user_id),
            );
        }
        VectorDiff::PushBack { value } => {
            push_if_not_duplicate(
                vec,
                get_message_from_timeline_item(value.as_ref(), own_user_id),
            );
        }
        VectorDiff::PopFront => {
            if !vec.is_empty() {
                vec.remove(0);
            }
        }
        VectorDiff::PopBack => {
            vec.pop();
        }
        VectorDiff::Insert { index, value } => {
            let msg = get_message_from_timeline_item(value.as_ref(), own_user_id);
            insert_if_not_duplicate(vec, index, msg);
        }
        VectorDiff::Set { index, value } => {
            let msg = get_message_from_timeline_item(value.as_ref(), own_user_id);
            if index < vec.len() {
                vec[index] = msg;
            }
        }
        VectorDiff::Remove { index } => {
            if index < vec.len() {
                vec.remove(index);
            }
        }
        VectorDiff::Truncate { length } => {
            vec.truncate(length);
        }
    }
}

/// Timeline items for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub(crate) async fn get_timeline_items_by_room_id(
    client: &Client,
    room_id: String,
) -> Vec<Message> {
    let mut messages = Vec::new();
    let room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return messages;
        }
    };

    let room_id_ref = room_id.as_ref();
    let room = match client.get_room(room_id_ref) {
        Some(room) => room,
        None => {
            error!("Room not found");
            return messages;
        }
    };

    let timeline = match room.timeline().await {
        Ok(timeline) => timeline,
        Err(e) => {
            error!("Failed to get timeline: {}", e);
            return messages;
        }
    };

    let own = client.user_id().map(|u| u.to_string());
    let own_ref = own.as_deref();
    let items = timeline.items().await;

    for item in items.iter() {
        messages.push(get_message_from_timeline_item(item, own_ref));
    }
    messages
}

/// Subscribe to timeline updates for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub async fn subscribe_to_timeline_updates(
    client: &Client,
    stream: StreamSink<MessageUpdate>,
    room_id: String,
    shared_timeline: Option<Arc<SdkTimeline>>,
) {
    let room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return;
        }
    };

    let room_id_ref = room_id.as_ref();
    let room = match client.get_room(room_id_ref) {
        Some(room) => room,
        None => {
            error!("Room not found");
            return;
        }
    };

    let timeline: Arc<SdkTimeline> = if let Some(t) = shared_timeline {
        t
    } else {
        let timeline = room
            .timeline_builder()
            .with_focus(TimelineFocus::Live {
                hide_threaded_events: true,
            })
            .build()
            .await;

        let timeline = match timeline {
            Ok(timeline) => timeline,
            Err(e) => {
                error!("Failed to build timeline: {}", e);
                return;
            }
        };
        Arc::new(timeline)
    };

    let (_events, mut diff_stream) = timeline.subscribe().await;
    let own = client.user_id().map(|u| u.to_string());
    let own_ref = own.as_deref();

    // Send initial heartbeat to confirm connection
    let _ = stream.add(MessageUpdate {
        message_update_type: MessageUpdateType::TimelineStart,
        messages: None,
        index: MESSAGE_UPDATE_NONE_INDEX,
        length: MESSAGE_UPDATE_NONE_INDEX,
    });

    // Create a heartbeat timer
    let mut heartbeat_interval = tokio::time::interval(tokio::time::Duration::from_secs(30));

    loop {
        tokio::select! {
            // Handle timeline updates
            diffs = diff_stream.next() => {
                match diffs {
                    Some(diffs) => {
                        for diff in diffs {
                            debug!("Timeline diff: {:?}", diff);
                            match diff {
                                matrix_sdk_ui::eyeball_im::VectorDiff::Append { values } => {
                                    let mut messages = Vec::new();
                                    for value in values {
                                        let message =
                                            get_message_from_timeline_item(&value, own_ref);
                                        messages.push(message);
                                    }
                                    let _ = stream.add(MessageUpdate {
                                        messages: Some(messages),
                                        message_update_type: MessageUpdateType::Append,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Clear => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Clear,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PushFront { value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PushFront,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PushBack { value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PushBack,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PopFront => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PopFront,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PopBack => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PopBack,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Insert { index, value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);

                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Insert,
                                        messages: Some(messages),
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Set { index, value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);

                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Set,
                                        messages: Some(messages),
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Remove { index } => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Remove,
                                        messages: None,
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Truncate { length } => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Truncate,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Reset { values } => {
                                    let mut messages = Vec::new();
                                    for value in values {
                                        let message =
                                            get_message_from_timeline_item(&value, own_ref);
                                        messages.push(message);
                                    }
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Reset,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                            }
                        }
                    }
                    None => {
                        debug!("Timeline stream ended, exiting subscription loop");
                        break;
                    }
                }
            }

            // Handle heartbeat
            _ = heartbeat_interval.tick() => {
                // Send a heartbeat to keep the connection alive
                let _ = stream.add(MessageUpdate {
                    message_update_type: MessageUpdateType::ReadMarker, // Use ReadMarker as heartbeat
                    messages: None,
                    index: MESSAGE_UPDATE_NONE_INDEX,
                    length: MESSAGE_UPDATE_NONE_INDEX,
                });
                debug!("Timeline heartbeat sent");
            }
        }
    }

    debug!("Timeline subscription ended for room {}", room_id);
}

/// Paginate and read items from a UI timeline (shared or ad hoc).
pub(crate) async fn get_older_messages_for_timeline(
    timeline: &SdkTimeline,
    count: u16,
    own_user_id: Option<&str>,
) -> Result<Vec<Message>, String> {
    timeline
        .paginate_backwards(count)
        .await
        .map_err(|e| format!("Failed to paginate backwards: {}", e))?;

    let items = timeline.items().await;
    Ok(items
        .iter()
        .map(|item| get_message_from_timeline_item(item.as_ref(), own_user_id))
        .collect())
}

/// Older messages for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub async fn get_older_messages(
    client: &Client,
    room_id: String,
    count: u16,
) -> Result<Vec<Message>, String> {
    let owned_room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return Err("Failed to parse room ID".to_string());
        }
    };

    let room_id_ref = owned_room_id.as_ref();
    let room = client
        .get_room(room_id_ref)
        .ok_or_else(|| "Room not found".to_string())?;
    let timeline = room
        .timeline()
        .await
        .map_err(|e| format!("Failed to get timeline: {}", e))?;

    let own = client.user_id().map(|u| u.to_string());
    get_older_messages_for_timeline(&timeline, count, own.as_deref()).await
}

// pub(crate) async fn send_message(
//     client: &Client,
//     room_id: String,
//     content: String,
// ) -> Result<SendMessageResult, String> {
//     let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
//     let room = client.get_room(&room_id_parsed).ok_or("Room not found")?;
//     let sender = client.user_id().ok_or("Not logged in")?.to_string();

//     let result = room
//         .send(
//             matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(&content),
//         )
//         .await
//         .map_err(|e| e.to_string())?;

//     let event_id = result.response.event_id.to_string();
//     let timestamp_ms = std::time::SystemTime::now()
//         .duration_since(std::time::UNIX_EPOCH)
//         .map(|d| d.as_millis() as u64)
//         .unwrap_or(0);

//     let mut room_update = get_room_update_data(&room).await;
//     room_update.message = Some(Message {
//         event_id: event_id.clone(),
//         sender,
//         content: content.clone(),
//         timestamp: timestamp_ms,
//         message_type: MessageType::Message,
//     });

//     Ok(SendMessageResult {
//         event_id,
//         room_update,
//     })
// }

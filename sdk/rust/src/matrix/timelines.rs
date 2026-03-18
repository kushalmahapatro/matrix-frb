use eyeball_im::Vector;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::Client;
use matrix_sdk_ui::timeline::{RoomExt, TimelineFocus, TimelineItem};
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
use crate::matrix::status::StatusHandle;
use tracing::{debug, error};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    Message,
    DateDivider,
    ReadMarker,
    TimelineStart,
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
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
    pub message_type: MessageType,
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

#[derive(Clone)]
#[frb(ignore)]
pub struct RoomView {
    client: Client,

    /// Timelines data structures for each room.
    timelines: Timelines,

    status_handle: StatusHandle,

    current_pagination: Arc<StdMutex<Option<JoinHandle<()>>>>,

    kind: TimelineKind,
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

#[frb(ignore)]
impl RoomView {
    pub fn new(client: Client, timelines: Timelines, status_handle: StatusHandle) -> Self {
        Self {
            client,
            timelines,
            status_handle,
            current_pagination: Default::default(),
            kind: TimelineKind::Room { room: None },
        }
    }
}

#[frb(ignore)]
pub fn get_message_from_timeline_item(item: &TimelineItem) -> Message {
    match item.kind() {
        matrix_sdk_ui::timeline::TimelineItemKind::Event(event_timeline_item) => {
            let event_id = event_timeline_item
                .event_id()
                .map(|id| id.to_string())
                .unwrap_or_else(|| "unknown".to_string());
            let sender = event_timeline_item.sender().to_string();
            let content = event_timeline_item
                .content()
                .as_message()
                .map(|msg| msg.body().to_string())
                .unwrap_or_else(|| "".to_string());
            let timestamp = u64::from(event_timeline_item.timestamp().0);
            Message {
                event_id,
                sender,
                content,
                timestamp,
                message_type: MessageType::Message,
            }
        }
        matrix_sdk_ui::timeline::TimelineItemKind::Virtual(virtual_timeline_item) => {
            match virtual_timeline_item {
                matrix_sdk_ui::timeline::VirtualTimelineItem::DateDivider(
                    milli_seconds_since_unix_epoch,
                ) => Message {
                    event_id: "".to_string(),
                    sender: "".to_string(),
                    content: format!("Date: {}", u64::from(milli_seconds_since_unix_epoch.0)),
                    timestamp: u64::from(milli_seconds_since_unix_epoch.0),
                    message_type: MessageType::DateDivider,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::ReadMarker => Message {
                    event_id: "".to_string(),
                    sender: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::ReadMarker,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::TimelineStart => Message {
                    event_id: "".to_string(),
                    sender: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::TimelineStart,
                },
            }
        }
    }
}

/// Runs the timeline diff stream for the room; applies each diff to the room's cache and pushes full list.
/// When timeline list updates, also updates the room list with the last message so the listing shows it.
/// Stops when [cancel] is triggered (e.g. when the client re-subscribes for this room).
/// Caller must ensure cache_map and sinks_map contain an entry for room_id before spawning.
pub(crate) async fn subscribe_to_timeline_list_loop(
    client: Client,
    room_id: String,
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

    // Load up to 50 messages initially so the list fills the screen and is scrollable;
    // if the room has fewer, we get all of them.
    const INITIAL_TIMELINE_PAGE_SIZE: u16 = 50;
    if let Err(e) = timeline.paginate_backwards(INITIAL_TIMELINE_PAGE_SIZE).await {
        debug!("Initial timeline paginate_backwards failed (non-fatal): {}", e);
    }

    let (_events, mut diff_stream) = timeline.subscribe().await;

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
                        apply_vector_diff_to_messages(vec, diff);
                        vec.clone()
                    };
                    let sinks_guard = sinks_map.lock().await;
                    if let Some(sink) = sinks_guard.get(&room_id) {
                        let _ = sink.add(list.clone());
                    }
                    drop(sinks_guard);
                    // Refresh room list with last message from timeline so listing shows it
                    if let Some(last_msg) = list.last().cloned() {
                        let mut update = rooms::get_room_update_data(&room).await;
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

/// Push message only if no message with the same event_id is already in the list.
/// Avoids duplicates when send_message has already appended and the timeline diff also emits it.
fn push_if_not_duplicate(vec: &mut Vec<Message>, msg: Message) {
    let has = !msg.event_id.is_empty() && vec.iter().any(|m| m.event_id == msg.event_id);
    if !has {
        vec.push(msg);
    }
}

/// Insert at front only if not duplicate by event_id.
fn push_front_if_not_duplicate(vec: &mut Vec<Message>, msg: Message) {
    let has = !msg.event_id.is_empty() && vec.iter().any(|m| m.event_id == msg.event_id);
    if !has {
        vec.insert(0, msg);
    }
}

/// Insert at index only if not duplicate by event_id.
fn insert_if_not_duplicate(vec: &mut Vec<Message>, index: usize, msg: Message) {
    let has = !msg.event_id.is_empty() && vec.iter().any(|m| m.event_id == msg.event_id);
    if !has && index <= vec.len() {
        vec.insert(index, msg);
    }
}

fn apply_vector_diff_to_messages(
    vec: &mut Vec<Message>,
    diff: matrix_sdk_ui::eyeball_im::VectorDiff<Arc<matrix_sdk_ui::timeline::TimelineItem>>,
) {
    use matrix_sdk_ui::eyeball_im::VectorDiff;
    match diff {
        VectorDiff::Reset { values } => {
            *vec = values
                .iter()
                .map(|v| get_message_from_timeline_item(v.as_ref()))
                .collect();
        }
        VectorDiff::Append { values } => {
            for value in values {
                push_if_not_duplicate(vec, get_message_from_timeline_item(value.as_ref()));
            }
        }
        VectorDiff::Clear => vec.clear(),
        VectorDiff::PushFront { value } => {
            push_front_if_not_duplicate(
                vec,
                get_message_from_timeline_item(value.as_ref()),
            );
        }
        VectorDiff::PushBack { value } => {
            push_if_not_duplicate(vec, get_message_from_timeline_item(value.as_ref()));
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
            let msg = get_message_from_timeline_item(value.as_ref());
            insert_if_not_duplicate(vec, index, msg);
        }
        VectorDiff::Set { index, value } => {
            let msg = get_message_from_timeline_item(value.as_ref());
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

    let items = timeline.items().await;

    for item in items.iter() {
        messages.push(get_message_from_timeline_item(item));
    }
    messages
}

/// Subscribe to timeline updates for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub async fn subscribe_to_timeline_updates(
    client: &Client,
    stream: StreamSink<MessageUpdate>,
    room_id: String,
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

    let (_events, mut diff_stream) = timeline.subscribe().await;

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
                                        let message = get_message_from_timeline_item(&value);
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
                                    let message = get_message_from_timeline_item(&value);
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
                                    let message = get_message_from_timeline_item(&value);
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
                                    let message = get_message_from_timeline_item(&value);
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
                                    let message = get_message_from_timeline_item(&value);
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
                                        let message = get_message_from_timeline_item(&value);
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

    timeline
        .paginate_backwards(count)
        .await
        .map_err(|e| format!("Failed to paginate backwards: {}", e))?;

    let items = timeline.items().await;
    Ok(items
        .iter()
        .map(|item| get_message_from_timeline_item(item.as_ref()))
        .collect())
}

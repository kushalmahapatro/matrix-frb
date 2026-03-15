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
use std::sync::Mutex;
use tokio::sync::OnceCell;
use tokio::task::JoinHandle;

use crate::frb_generated::StreamSink;
use crate::matrix::status::StatusHandle;
use tracing::{error, info};

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
    pub items: Arc<Mutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
    pub task: JoinHandle<()>,
}

#[frb(ignore)]
pub type Timelines = Arc<Mutex<HashMap<OwnedRoomId, Timeline>>>;

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
        items: Arc<Mutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
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

    current_pagination: Arc<Mutex<Option<JoinHandle<()>>>>,

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
                    items: Arc::new(Mutex::new(Vector::new())),
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
                            info!("Received timeline diff: {:?}", diff);
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
                        info!("Timeline stream ended, exiting subscription loop");
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
                info!("Sent heartbeat to keep connection alive");
            }
        }
    }

    info!("Timeline subscription ended");
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
    let room = client.get_room(room_id_ref).unwrap();
    let timeline = room.timeline().await.unwrap();

    let result = timeline.paginate_backwards(count).await;
    match result {
        Ok(_) => {
            // Build messages from current timeline items without block_on (we're already on the runtime).
            let items = timeline.items().await;
            Ok(items
                .iter()
                .map(|item| get_message_from_timeline_item(item.as_ref()))
                .collect())
        }
        Err(_) => {
            error!("Failed to paginate backwards");
            Err("Failed to paginate backwards".to_string())
        }
    }
}

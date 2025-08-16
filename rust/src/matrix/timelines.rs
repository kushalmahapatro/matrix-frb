use flutter_rust_bridge::frb;
use futures::StreamExt;
use imbl::Vector;
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::Client;
use matrix_sdk_ui::timeline::{RoomExt, TimelineItem};
use matrix_sdk_ui::Timeline as SdkTimeline;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::Mutex;
use tokio::sync::OnceCell;
use tokio::task::JoinHandle;

use crate::api::logger::log_info;
use crate::api::platform::GLOBAL_RUNTIME;
use crate::frb_generated::StreamSink;
use crate::matrix::status::StatusHandle;
use crate::matrix::sync_service::GLOBAL_APP;

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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub event_id: String,
    pub sender: String,
    pub content: String,
    pub timestamp: u64,
    pub message_type: MessageType,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageUpdate {
    pub message_update_type: MessageUpdateType,
    pub messages: Option<Vec<Message>>,
    pub index: Option<usize>,
    pub length: Option<usize>,
}

#[frb(ignore)]
pub struct Timeline {
    pub timeline: Arc<SdkTimeline>,
    pub items: Arc<Mutex<Vector<Arc<TimelineItem>>>>,
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
        items: Arc<Mutex<Vector<Arc<TimelineItem>>>>,
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

fn get_timeline_sdk_by_room_id(room_id: String) -> Option<Arc<SdkTimeline>> {
    match GLOBAL_APP.get() {
        Some(app) => {
            let room_id: OwnedRoomId = room_id.parse().ok()?;
            let timelines = app.timelines.lock().ok()?;
            let room_id_ref: &matrix_sdk::ruma::RoomId = room_id.as_ref();
            timelines
                .get(room_id_ref)
                .map(|timeline| timeline.timeline.clone())
        }
        None => {
            println!("No global app found");
            None
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

pub fn get_timeline_items_by_room_id(room_id: String) -> Vec<Message> {
    let rt = GLOBAL_RUNTIME.get().unwrap();
    rt.block_on(async {
        let mut messages = Vec::new();
        match GLOBAL_APP.get() {
            Some(app) => {
                let room_id: OwnedRoomId = match room_id.parse() {
                    Ok(id) => id,
                    Err(_) => {
                        println!("Failed to parse room ID");
                        return messages;
                    }
                };

                let room_id_ref = room_id.as_ref();
                let room = match app.client.get_room(room_id_ref) {
                    Some(room) => room,
                    None => {
                        println!("Room not found");
                        return messages;
                    }
                };

                let timeline = match room.timeline().await {
                    Ok(timeline) => timeline,
                    Err(e) => {
                        println!("Failed to get timeline: {}", e);
                        return messages;
                    }
                };

                let items = timeline.items().await;

                for item in items.iter() {
                    messages.push(get_message_from_timeline_item(item));
                }
            }
            None => {
                println!("No global app found");
            }
        }
        messages
    })
}

pub fn subscribe_to_timeline_updates(stream: StreamSink<MessageUpdate>, room_id: String) {
    let rt = GLOBAL_RUNTIME.get().unwrap();
    rt.block_on(async {
        let room_id: OwnedRoomId = match room_id.parse() {
            Ok(id) => id,
            Err(_) => {
                println!("Failed to parse room ID");
                return;
            }
        };

        let room_id_ref = room_id.as_ref();
        let room = match GLOBAL_APP.get().unwrap().client.get_room(room_id_ref) {
            Some(room) => room,
            None => {
                println!("Room not found");
                return;
            }
        };
        let timeline = room.timeline().await.unwrap();
        let (_events, mut diff_stream) = timeline.subscribe().await;

        while let Some(diffs) = diff_stream.next().await {
            for diff in diffs {
                log_info(format!("Received timeline diff: {:?}", diff));
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
                            index: None,
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::Clear => {
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::Clear,
                            messages: None,
                            index: None,
                            length: None,
                        });
                    }

                    matrix_sdk_ui::eyeball_im::VectorDiff::PushFront { value } => {
                        let mut messages = Vec::new();
                        let message = get_message_from_timeline_item(&value);
                        messages.push(message);
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::PushFront,
                            messages: Some(messages),
                            index: None,
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::PushBack { value } => {
                        let mut messages = Vec::new();
                        let message = get_message_from_timeline_item(&value);
                        messages.push(message);
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::PushBack,
                            messages: Some(messages),
                            index: None,
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::PopFront => {
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::PopFront,
                            messages: None,
                            index: None,
                            length: None,
                        });
                    }

                    matrix_sdk_ui::eyeball_im::VectorDiff::PopBack => {
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::PopBack,
                            messages: None,
                            index: None,
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::Insert { index, value } => {
                        let mut messages = Vec::new();
                        let message = get_message_from_timeline_item(&value);
                        messages.push(message);

                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::Insert,
                            messages: Some(messages),
                            index: Some(index),
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::Set { index, value } => {
                        let mut messages = Vec::new();
                        let message = get_message_from_timeline_item(&value);
                        messages.push(message);

                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::Set,
                            messages: Some(messages),
                            index: Some(index),
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::Remove { index } => {
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::Remove,
                            messages: None,
                            index: Some(index),
                            length: None,
                        });
                    }
                    matrix_sdk_ui::eyeball_im::VectorDiff::Truncate { length } => {
                        let _ = stream.add(MessageUpdate {
                            message_update_type: MessageUpdateType::Truncate,
                            messages: None,
                            index: None,
                            length: Some(length),
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
                            index: None,
                            length: None,
                        });
                    }
                }
            }
        }
    });
}

use tracing::{error, warn};

use crate::frb_generated::StreamSink;
use crate::matrix::rooms::{ExtraRoomInfo, RoomInfos, RoomList};
use crate::matrix::status::Status;
use crate::matrix::timelines::{RoomView, Timeline, Timelines};
use eyeball_im::Vector;
use flutter_rust_bridge::frb;
use futures::{pin_mut, StreamExt};
use matrix_sdk::Client;
use matrix_sdk::Room;
use matrix_sdk_ui::sync_service::{State as MatrixSyncState, SyncService};
use matrix_sdk_ui::timeline::{EventTimelineItem, RoomExt, TimelineFocus, VirtualTimelineItem};
use once_cell::sync::OnceCell;
pub use std::collections::HashMap;
use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use std::time::Instant;
use tokio::spawn;

/// Sync service state, mirroring the matrix-sdk-ffi SyncServiceState.
/// Notify the client when this changes so it can refresh rooms/timeline or show sync status.
#[derive(Clone, Debug)]
pub enum SyncState {
    Idle,
    Running,
    Terminated,
    Error,
    Offline,
}

impl From<MatrixSyncState> for SyncState {
    fn from(s: MatrixSyncState) -> Self {
        match s {
            MatrixSyncState::Idle => SyncState::Idle,
            MatrixSyncState::Running => SyncState::Running,
            MatrixSyncState::Terminated => SyncState::Terminated,
            MatrixSyncState::Error(_) => SyncState::Error,
            MatrixSyncState::Offline => SyncState::Offline,
        }
    }
}

#[frb(ignore)]
pub static GLOBAL_SYNC_SERVICE: OnceCell<Option<Arc<SyncService>>> = OnceCell::new();

#[frb(ignore)]
pub type Rooms = Arc<StdMutex<Vector<Room>>>;

pub struct RoomUpdate {
    pub room_id: String,
    pub raw_name: Option<String>,
    pub display_name: Option<String>,
    pub is_dm: Option<bool>,
}
#[frb(ignore)]
pub struct TimelineUpdate {
    pub room_id: String,
    // pub room_event_cache: RoomEventCache,
    pub items: Vec<TimelineItems>, // Changed from Vector<Arc<TimelineItems>> to Vec<TimelineItems> for serialization
}

#[derive(Clone, Debug)]
#[allow(clippy::large_enum_variant)]
#[frb(ignore)]
pub enum TimelineItemType {
    /// An event or aggregation of multiple events.
    Event(EventTimelineItem),
    /// An item that doesn't correspond to an event, for example the user's
    /// own read marker, or a date divider.
    Virtual(VirtualTimelineItem),
}

/// A single entry in timeline.
#[derive(Clone, Debug)]
#[frb(ignore)]
pub struct TimelineItems {
    pub kind: TimelineItemType,
    pub internal_id: String, // Changed from TimelineUniqueId to String for serialization
}

#[frb(ignore)]
#[derive(Clone)]
pub struct App {
    /// The sync service used for synchronizing events.
    pub sync_service: Arc<SyncService>,

    /// Timelines data structures for each room.
    pub timelines: Timelines,

    /// The room list widget on the left-hand side of the screen.
    pub room_list: RoomList,

    /// A view displaying the contents of the selected room, the widget on the
    /// right-hand side of the screen.
    pub room_view: RoomView,

    /// The status widget at the bottom of the screen.
    pub status: Status,

    pub last_tick: Instant,
}

#[frb(ignore)]
impl App {
    /// Build the App (rooms, room_list, room_view, listen_task). Caller must spawn
    /// `app.sync_service.start()` so the sync loop runs without blocking.
    async fn new(client: Client, sync_service: Arc<SyncService>) -> Result<Self, ()> {
        let rooms = Rooms::default();
        let room_infos = RoomInfos::default();
        let timelines = Timelines::default();

        // Spawn the listen task; it will get the room stream from the client it owns.
        let _listen_task = spawn(Self::listen_task(
            rooms.clone(),
            room_infos.clone(),
            timelines.clone(),
            client.clone(),
        ));

        let status = Status::new();
        let room_list = RoomList::new(rooms, room_infos, sync_service.clone(), status.handle());

        let room_view = RoomView::new(client.clone(), timelines.clone(), status.handle());

        Ok(Self {
            sync_service,
            timelines,
            room_list,
            room_view,
            status,
            last_tick: Instant::now(),
        })
    }

    async fn listen_task(
        rooms: Rooms,
        room_infos: RoomInfos,
        timelines: Timelines,
        client: Client,
    ) {
        let (initial_rooms, mut rooms_stream) = client.rooms_stream();
        *rooms.lock().unwrap() = initial_rooms;

        let mut previous_rooms = HashSet::new();

        while let Some(diffs) = rooms_stream.next().await {
            let all_rooms = {
                // Apply the diffs to the list of room entries.
                let mut rooms = rooms.lock().unwrap();

                for diff in diffs {
                    diff.apply(&mut *rooms);
                }

                // Collect rooms early to release the room entries list lock.
                (*rooms).clone()
            };

            let mut new_rooms = HashMap::new();
            let mut new_timelines = Vec::new();

            // Update all the room info for all rooms.
            for room in all_rooms.iter() {
                let raw_name = room.name();
                let display_name = room
                    .cached_display_name()
                    .map(|display_name| display_name.to_string());
                let is_dm = room
                    .is_direct()
                    .await
                    .map_err(|err| {
                        warn!("couldn't figure whether a room is a DM or not: {err}");
                    })
                    .ok();
                room_infos.lock().unwrap().insert(
                    room.room_id().to_owned(),
                    ExtraRoomInfo {
                        raw_name,
                        display_name,
                        is_dm,
                    },
                );
            }

            // Initialize all the new rooms.
            for room in all_rooms
                .into_iter()
                .filter(|room| !previous_rooms.contains(room.room_id()))
            {
                // Initialize the timeline.
                let Ok(timeline) = room
                    .timeline_builder()
                    .with_focus(TimelineFocus::Live {
                        hide_threaded_events: true,
                    })
                    .build()
                    .await
                else {
                    error!("error when creating default timeline");
                    continue;
                };

                // Save the timeline in the cache.
                let (items, stream): (Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>, _) =
                    timeline.subscribe().await;
                let items = Arc::new(StdMutex::new(items));

                // Spawn a timeline task that will listen to all the timeline item changes.
                let i = items.clone();
                let timeline_task = spawn(async move {
                    pin_mut!(stream);
                    let items = i;
                    while let Some(diffs) = stream.next().await {
                        let mut items = items.lock().unwrap();

                        for diff in diffs {
                            diff.apply(&mut *items);
                        }
                    }
                });

                new_timelines.push((
                    room.room_id().to_owned(),
                    Timeline {
                        timeline: Arc::new(timeline),
                        items,
                        task: timeline_task,
                    },
                ));

                // Save the room list service room in the cache.
                new_rooms.insert(room.room_id().to_owned(), room);
            }

            previous_rooms.extend(new_rooms.into_keys());

            timelines.lock().unwrap().extend(new_timelines);
        }
    }
}

pub(crate) async fn start_sync_service(client: Client) -> Result<Arc<App>, String> {
    match SyncService::builder(client.clone()).build().await {
        Ok(sync) => {
            let sync = Arc::new(sync);
            let app = App::new(client.clone(), sync.clone()).await.map_err(|_| ());
            let app = match app {
                Ok(a) => Arc::new(a),
                Err(_) => return Err("Failed to create App".to_string()),
            };

            // Run sync loop in background so this future can return.

            sync.start().await;

            Ok(app.clone())
        }
        Err(e) => Err(e.to_string()),
    }
}

/// Restart sync using the app stored in the client. Call from [crate::api::matrix_client::MatrixClient].
pub(crate) async fn restart_sync_service(app: Arc<App>) -> Result<bool, String> {
    let sync = app.sync_service.clone();
    sync.start().await;
    Ok(true)
}

/// Subscribe to sync state using the app stored in the client.
pub(crate) async fn subscribe_sync_state(app: Arc<App>, stream: StreamSink<SyncState>) {
    let sync_service = app.sync_service.clone();
    let state_stream = sync_service.state();
    pin_mut!(state_stream);
    while let Some(state) = state_stream.next().await {
        let _ = stream.add(state.into());
    }
}

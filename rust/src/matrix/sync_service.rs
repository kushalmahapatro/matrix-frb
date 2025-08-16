use crate::api::logger::{log_error, log_warn};
use crate::matrix::rooms::{ExtraRoomInfo, RoomInfos, RoomList};
use crate::matrix::status::Status;
use crate::matrix::timelines::{RoomView, Timeline, Timelines};
use crate::{api::platform::GLOBAL_RUNTIME, matrix::client::get_global_client};
use flutter_rust_bridge::frb;
use futures::{pin_mut, StreamExt};
use imbl::Vector;
use matrix_sdk::Client;
use matrix_sdk::Room;
use matrix_sdk_ui::room_list_service::filters::new_filter_non_left;
use matrix_sdk_ui::room_list_service::{self};
use matrix_sdk_ui::sync_service::SyncService;
use matrix_sdk_ui::timeline::{EventTimelineItem, RoomExt, TimelineFocus, VirtualTimelineItem};
use once_cell::sync::OnceCell;
pub use std::collections::HashMap;
use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex;
use std::time::Instant;
use tokio::spawn;

#[frb(ignore)]
pub static GLOBAL_SYNC_SERVICE: OnceCell<Option<Arc<SyncService>>> = OnceCell::new();

#[frb(ignore)]
pub static GLOBAL_APP: OnceCell<Arc<App>> = OnceCell::new();

#[frb(ignore)]
pub type Rooms = Arc<Mutex<Vector<Room>>>;

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
    /// Reference to the main SDK client.
    pub client: Client,

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
    async fn new(client: Client, sync_service: Arc<SyncService>) -> Result<Self, ()> {
        let rooms = Rooms::default();
        let room_infos = RoomInfos::default();
        let timelines = Timelines::default();

        let room_list_service = sync_service.room_list_service();
        let all_rooms = room_list_service
            .all_rooms()
            .await
            .map_err(|e| e.to_string());

        // Spawn the listen task but don't store it in the struct since JoinHandle can't be cloned
        let _listen_task = spawn(Self::listen_task(
            rooms.clone(),
            room_infos.clone(),
            timelines.clone(),
            all_rooms.unwrap(),
        ));

        // This will sync (with encryption) until an error happens or the program is
        // stopped.
        sync_service.start().await;

        let status = Status::new();
        let room_list = RoomList::new(
            client.clone(),
            rooms,
            room_infos,
            sync_service.clone(),
            status.handle(),
        );

        let room_view = RoomView::new(client.clone(), timelines.clone(), status.handle());

        Ok(Self {
            sync_service,
            timelines,
            room_list,
            room_view,
            client,
            status,
            last_tick: Instant::now(),
        })
    }

    async fn listen_task(
        rooms: Rooms,
        room_infos: RoomInfos,
        timelines: Timelines,
        all_rooms: room_list_service::RoomList,
    ) {
        let (stream, entries_controller) = all_rooms.entries_with_dynamic_adapters(50_000);
        entries_controller.set_filter(Box::new(new_filter_non_left()));

        pin_mut!(stream);

        let mut previous_rooms = HashSet::new();

        while let Some(diffs) = stream.next().await {
            let all_rooms = {
                // Apply the diffs to the list of room entries.
                let mut rooms = rooms.lock().unwrap();

                for diff in diffs {
                    diff.apply(&mut rooms);
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
                        log_warn(format!(
                            "couldn't figure whether a room is a DM or not: {err}"
                        ));
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
                    log_error(format!("error when creating default timeline"));
                    continue;
                };

                // Save the timeline in the cache.
                let (items, stream): (Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>, _) =
                    timeline.subscribe().await;
                let items = Arc::new(Mutex::new(items));

                // Spawn a timeline task that will listen to all the timeline item changes.
                let i = items.clone();
                let timeline_task = spawn(async move {
                    pin_mut!(stream);
                    let items = i;
                    while let Some(diffs) = stream.next().await {
                        let mut items = items.lock().unwrap();

                        for diff in diffs {
                            diff.apply(&mut items);
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

pub fn start_sync_service() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client: Option<Client> = get_global_client().await?;
            if let Some(client) = global_client {
                match SyncService::builder(client.clone()).build().await {
                    Ok(sync) => {
                        // GLOBAL_SYNC_SERVICE.get_or_init(|| Some(sync));
                        let app = App::new(client, Arc::new(sync)).await.map_err(|e| e);
                        GLOBAL_APP.get_or_init(|| Arc::new(app.unwrap()));
                        return Ok(true);
                    }
                    Err(e) => Err(e.to_string()),
                }
            } else {
                Err("No client available".to_string())
            }
        })
    })
}

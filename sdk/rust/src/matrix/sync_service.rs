use std::time::{SystemTime, UNIX_EPOCH};

use tracing::{error, warn};

use crate::frb_generated::StreamSink;
use crate::matrix::client::format_user_id_for_display;
use crate::matrix::rooms::{ExtraRoomInfo, RoomInfos, RoomList, Rooms};
use crate::matrix::sync_notifications::{
    SyncNotificationSummary, RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS,
};
use crate::matrix::timelines::{self, Timeline, Timelines};
use eyeball_im::Vector;
use flutter_rust_bridge::frb;
use futures::{pin_mut, StreamExt};
use matrix_sdk::Client;
use matrix_sdk_ui::room_list_service::filters::new_filter_non_left;
use matrix_sdk_ui::room_list_service::RoomList as SlidingSyncRoomList;
use matrix_sdk_ui::sync_service::{State as MatrixSyncState, SyncService};
use matrix_sdk_ui::timeline::{RoomExt, TimelineFocus, TimelineReadReceiptTracking};
use std::collections::HashSet;
use std::sync::Arc;
use std::sync::Mutex as StdMutex;
use tokio::spawn;
use tokio::sync::broadcast;

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
#[derive(Clone)]
pub struct App {
    /// The sync service used for synchronizing events.
    pub sync_service: Arc<SyncService>,

    /// Timelines data structures for each room.
    pub timelines: Timelines,

    /// The room list widget on the left-hand side of the screen.
    pub room_list: RoomList,

    /// Notify UI room-list subscribers when sliding-sync room list changes (multiverse-style).
    pub room_list_refresh: broadcast::Sender<()>,
}

#[frb(ignore)]
impl App {
    /// Build the App (rooms, room_list, listen_task). Caller must call
    /// `app.sync_service.start().await` so the sync loop runs without blocking.
    async fn new(
        client: Client,
        sync_service: Arc<SyncService>,
        all_rooms: SlidingSyncRoomList,
        rtc_notify_tx: Option<broadcast::Sender<SyncNotificationSummary>>,
    ) -> Result<Self, ()> {
        let rooms = Rooms::default();
        let room_infos = RoomInfos::default();
        let timelines = Timelines::default();

        let (room_list_refresh, _) = broadcast::channel::<()>(256);
        let refresh_tx = room_list_refresh.clone();

        let _listen_task = spawn(Self::listen_task(
            client,
            rooms.clone(),
            room_infos.clone(),
            timelines.clone(),
            all_rooms,
            refresh_tx,
            rtc_notify_tx,
        ));

        let room_list = RoomList::new(rooms, room_infos);

        Ok(Self {
            sync_service,
            timelines,
            room_list,
            room_list_refresh,
        })
    }

    /// Sliding Sync room list + timelines (same pipeline as matrix-rust-sdk multiverse).
    async fn listen_task(
        client: Client,
        rooms: Rooms,
        room_infos: RoomInfos,
        timelines: Timelines,
        all_rooms: SlidingSyncRoomList,
        room_list_refresh: broadcast::Sender<()>,
        rtc_notify_tx: Option<broadcast::Sender<SyncNotificationSummary>>,
    ) {
        let (stream, entries_controller) = all_rooms.entries_with_dynamic_adapters(50_000);
        entries_controller.set_filter(Box::new(new_filter_non_left()));

        pin_mut!(stream);

        let mut previous_rooms = HashSet::new();

        while let Some(diffs) = stream.next().await {
            let all_room_items = {
                let mut rooms_guard = rooms.lock().unwrap();

                for diff in diffs {
                    diff.apply(&mut *rooms_guard);
                }

                (*rooms_guard).clone()
            };

            let mut new_room_ids = HashSet::new();
            let mut new_timelines = Vec::new();

            for room in all_room_items.iter() {
                let raw_name = room
                    .name()
                    .map(|n| format_user_id_for_display(n.as_ref()));
                let display_name = room.cached_display_name().map(|display_name| {
                    format_user_id_for_display(&display_name.to_string())
                });
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

            for room in all_room_items
                .into_iter()
                .filter(|room| !previous_rooms.contains(room.room_id()))
            {
                let Ok(timeline) = room
                    .timeline_builder()
                    .track_read_marker_and_receipts(TimelineReadReceiptTracking::MessageLikeEvents)
                    .with_focus(TimelineFocus::Live {
                        hide_threaded_events: true,
                    })
                    .build()
                    .await
                else {
                    error!("error when creating default timeline");
                    continue;
                };

                let (items, stream): (Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>, _) =
                    timeline.subscribe().await;
                let items = Arc::new(StdMutex::new(items));

                let i = items.clone();
                let client_for_timeline = client.clone();
                let room_id_owned = room.room_id().to_owned();
                let rtc_tx = rtc_notify_tx.clone();
                let own_user_id = client.user_id().map(|u| u.to_string());
                let timeline_task = spawn(async move {
                    fn now_ms() -> u64 {
                        SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .map(|d| d.as_millis() as u64)
                            .unwrap_or(0)
                    }

                    pin_mut!(stream);
                    let items = i;
                    let mut seen_ring_event_ids: HashSet<String> = HashSet::new();

                    while let Some(diffs) = stream.next().await {
                        {
                            let mut items = items.lock().unwrap();
                            for diff in diffs {
                                diff.apply(&mut *items);
                            }
                        }

                        let Some(ref tx) = rtc_tx else {
                            continue;
                        };
                        let Some(room) = client_for_timeline.get_room(room_id_owned.as_ref()) else {
                            continue;
                        };
                        let own = own_user_id.as_deref();
                        let now = now_ms();

                        let ring_messages: Vec<_> = {
                            let guard = items.lock().unwrap();
                            guard
                                .iter()
                                .map(|v| {
                                    timelines::get_message_from_timeline_item(v.as_ref(), own)
                                })
                                .filter(|m| {
                                    timelines::timeline_message_is_peer_incoming_call_ring(m)
                                })
                                .collect()
                        };

                        for m in ring_messages {
                            let eid = m.event_id.trim().to_string();
                            if eid.is_empty() {
                                continue;
                            }
                            if seen_ring_event_ids.contains(&eid) {
                                continue;
                            }

                            let stale = m.timestamp == 0
                                || now.saturating_sub(m.timestamp)
                                    > RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS;
                            if stale {
                                seen_ring_event_ids.insert(eid);
                                continue;
                            }

                            if let Some(summary) =
                                timelines::summary_from_timeline_incoming_call_ring(&room, &m)
                            {
                                let _ = tx.send(summary);
                            }
                            seen_ring_event_ids.insert(eid);
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

                new_room_ids.insert(room.room_id().to_owned());
            }

            previous_rooms.extend(new_room_ids);

            timelines.lock().unwrap().extend(new_timelines);

            let _ = room_list_refresh.send(());
        }
    }
}

pub(crate) async fn start_sync_service(
    client: Client,
    rtc_notify_tx: Option<broadcast::Sender<SyncNotificationSummary>>,
) -> Result<Arc<App>, String> {
    match SyncService::builder(client.clone()).build().await {
        Ok(sync) => {
            let sync = Arc::new(sync);

            let all_rooms = sync
                .room_list_service()
                .all_rooms()
                .await
                .map_err(|e| e.to_string())?;

            client
                .event_cache()
                .subscribe()
                .map_err(|e| format!("event_cache.subscribe: {e}"))?;

            let app = App::new(client.clone(), sync.clone(), all_rooms, rtc_notify_tx)
                .await
                .map_err(|_| "Failed to create App".to_string())?;
            let app = Arc::new(app);

            // Run sync in the background so Flutter can leave the splash screen immediately.
            // Room list updates still arrive via `room_list_refresh` as sliding sync applies diffs.
            let sync_runner = sync.clone();
            spawn(async move {
                sync_runner.start().await;
            });

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

/// Stop sliding sync (e.g. app backgrounded). Pair with [restart_sync_service] on resume.
pub(crate) async fn pause_sync_service(app: Arc<App>) -> Result<bool, String> {
    let sync = app.sync_service.clone();
    sync.stop().await;
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

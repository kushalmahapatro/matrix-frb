use std::collections::HashSet;
use std::sync::Arc;

use futures::{future::join_all, pin_mut, StreamExt};
use matrix_sdk::Client;
use matrix_sdk_ui::eyeball_im::VectorDiff;
use matrix_sdk_ui::room_list_service::filters::new_filter_non_left;
use matrix_sdk_ui::room_list_service::RoomList as SlidingSyncRoomList;
use matrix_sdk_ui::room_list_service::RoomListItem;
use matrix_sdk_ui::sync_service::{State as MatrixSyncState, SyncService};
use ruma::OwnedRoomId;
use tokio::spawn;
use tokio::sync::broadcast;
use tracing::warn;

use crate::frb_generated::StreamSink;
use crate::matrix::client::format_user_id_for_display;
use crate::matrix::rooms::{ExtraRoomInfo, RoomInfos, RoomList, Rooms};
use crate::matrix::timelines::Timelines;
use eyeball_im::Vector;
use flutter_rust_bridge::frb;

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

/// Room list entries that need [ExtraRoomInfo] refreshed after this batch of diffs.
///
/// Call with the sliding-sync room vector **before** applying the diffs. This avoids cloning
/// the full list each tick (important for large accounts — Telegram/Signal-style lazy work).
fn room_list_items_touched_by_diffs(
    before: &Vector<RoomListItem>,
    diffs: &[VectorDiff<RoomListItem>],
) -> HashSet<OwnedRoomId> {
    let mut touched = HashSet::new();

    for d in diffs {
        match d {
            VectorDiff::Append { values } => {
                touched.extend(values.iter().map(|v| v.room_id().to_owned()));
            }
            VectorDiff::PushFront { value } | VectorDiff::PushBack { value } => {
                touched.insert(value.room_id().to_owned());
            }
            VectorDiff::Insert { value, .. } | VectorDiff::Set { value, .. } => {
                touched.insert(value.room_id().to_owned());
            }
            VectorDiff::Remove { index } => {
                if let Some(v) = before.get(*index) {
                    touched.insert(v.room_id().to_owned());
                }
            }
            VectorDiff::Truncate { length } => {
                touched.extend(before.iter().skip(*length).map(|v| v.room_id().to_owned()));
            }
            VectorDiff::Clear => {
                touched.extend(before.iter().map(|v| v.room_id().to_owned()));
            }
            VectorDiff::Reset { values } => {
                touched.extend(before.iter().map(|v| v.room_id().to_owned()));
                touched.extend(values.iter().map(|v| v.room_id().to_owned()));
            }
            VectorDiff::PopFront => {
                if let Some(v) = before.get(0) {
                    touched.insert(v.room_id().to_owned());
                }
            }
            VectorDiff::PopBack => {
                let len = before.len();
                if let Some(v) = len.checked_sub(1).and_then(|i| before.get(i)) {
                    touched.insert(v.room_id().to_owned());
                }
            }
        }
    }

    touched
}

#[frb(ignore)]
#[derive(Clone)]
pub struct App {
    /// The sync service used for synchronizing events.
    pub sync_service: Arc<SyncService>,

    /// Optional shared UI timelines keyed by room (populated only when code explicitly caches one).
    ///
    /// Chat timelines are built lazily when the user opens a room — see
    /// [crate::matrix::timelines::get_timeline_items_by_room_id] and
    /// [crate::matrix::timelines::subscribe_to_timeline_updates].
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
        sync_service: Arc<SyncService>,
        all_rooms: SlidingSyncRoomList,
    ) -> Result<Self, ()> {
        let rooms = Rooms::default();
        let room_infos = RoomInfos::default();
        let timelines = Timelines::default();

        let (room_list_refresh, _) = broadcast::channel::<()>(256);
        let refresh_tx = room_list_refresh.clone();

        let _listen_task = spawn(Self::listen_task(
            rooms.clone(),
            room_infos.clone(),
            all_rooms,
            refresh_tx,
        ));

        let room_list = RoomList::new(rooms, room_infos);

        Ok(Self {
            sync_service,
            timelines,
            room_list,
            room_list_refresh,
        })
    }

    /// Sliding Sync room list updates only (no per-room live timelines — those are lazy).
    async fn listen_task(
        rooms: Rooms,
        room_infos: RoomInfos,
        all_rooms: SlidingSyncRoomList,
        room_list_refresh: broadcast::Sender<()>,
    ) {
        let (stream, entries_controller) = all_rooms.entries_with_dynamic_adapters(50_000);
        entries_controller.set_filter(Box::new(new_filter_non_left()));

        pin_mut!(stream);

        while let Some(diffs) = stream.next().await {
            let touched_ids = {
                let mut rooms_guard = rooms.lock().unwrap();
                let touched = room_list_items_touched_by_diffs(&rooms_guard, &diffs);
                for diff in diffs {
                    diff.apply(&mut *rooms_guard);
                }
                let valid: HashSet<OwnedRoomId> =
                    rooms_guard.iter().map(|r| r.room_id().to_owned()).collect();
                drop(rooms_guard);
                (touched, valid)
            };

            let (touched, valid) = touched_ids;
            {
                let mut infos = room_infos.lock().unwrap();
                infos.retain(|k, _| valid.contains(k));
            }

            let items_to_refresh: Vec<RoomListItem> = {
                let rooms_guard = rooms.lock().unwrap();
                if touched.is_empty() {
                    Vec::new()
                } else {
                    rooms_guard
                        .iter()
                        .filter(|r| touched.contains(r.room_id()))
                        .cloned()
                        .collect()
                }
            };

            let updates = join_all(items_to_refresh.iter().map(|room| async {
                let raw_name = room.name().map(|n| format_user_id_for_display(n.as_ref()));
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
                (
                    room.room_id().to_owned(),
                    ExtraRoomInfo {
                        raw_name,
                        display_name,
                        is_dm,
                    },
                )
            }))
            .await;

            {
                let mut infos = room_infos.lock().unwrap();
                for (id, info) in updates {
                    infos.insert(id, info);
                }
            }

            let _ = room_list_refresh.send(());
        }
    }
}

pub(crate) async fn start_sync_service(client: Client) -> Result<Arc<App>, String> {
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

            let app = App::new(sync.clone(), all_rooms)
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

use matrix_sdk::Client;
use std::sync::Arc;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::{
    frb_generated::StreamSink,
    matrix::{
        client::ClientConfig,
        rooms::{self, RoomUpdate},
        sync_service::{self, App},
        timelines::{self, Message},
        user_serach,
    },
};

/// Single entry point for the Matrix client. Create via [MatrixClient::configure], then use
/// [MatrixClient::login], [MatrixClient::register], [MatrixClient::get_all_rooms], etc.
/// Holds the SDK client and the App (sync service + room list + timelines) when sync is started.

pub struct MatrixClient {
    client: Client,
    /// Set when [MatrixClient::start_sync_service] is called; used for rooms/timeline/sync state.
    app: Arc<Mutex<Option<Arc<App>>>>,
    session_path: String,
    /// Room update for the last sent message (so UI can show correct last message without waiting for SDK cache).
    last_sent_room_update: Arc<Mutex<Option<RoomUpdate>>>,
    /// Canonical room list (Rust-owned). Updated by sync and by send_message; pushed to [room_list_sink].
    room_list_cache: Arc<Mutex<Vec<RoomUpdate>>>,
    /// When set, [subscribe_to_room_list] is active; we push full list here on every change.
    room_list_sink: Arc<Mutex<Option<Arc<StreamSink<Vec<RoomUpdate>>>>>>,
    /// Per-room timeline list cache (for [subscribe_to_timeline_list]).
    timeline_list_cache: Arc<Mutex<std::collections::HashMap<String, Vec<Message>>>>,
    /// Per-room sinks for timeline list stream.
    timeline_list_sinks:
        Arc<Mutex<std::collections::HashMap<String, Arc<StreamSink<Vec<Message>>>>>>,
    /// Cancel token per room so we abort the previous timeline loop when re-subscribing.
    timeline_list_cancel: Arc<Mutex<std::collections::HashMap<String, CancellationToken>>>,
}

impl MatrixClient {
    /// Initialize the client with the given config. Returns a [MatrixClient] instance to use for
    /// all further operations (login, register, get_all_rooms, etc.).
    pub async fn configure(config: ClientConfig) -> Result<MatrixClient, String> {
        let client = crate::matrix::client::configure_client(&config).await?;
        let session_path = config.session_path.clone();
        Ok(MatrixClient {
            client,
            app: Arc::new(Mutex::new(None)),
            session_path,
            last_sent_room_update: Arc::new(Mutex::new(None)),
            room_list_cache: Arc::new(Mutex::new(Vec::new())),
            room_list_sink: Arc::new(Mutex::new(None)),
            timeline_list_cache: Arc::new(Mutex::new(std::collections::HashMap::new())),
            timeline_list_sinks: Arc::new(Mutex::new(std::collections::HashMap::new())),
            timeline_list_cancel: Arc::new(Mutex::new(std::collections::HashMap::new())),
        })
    }

    /// Log in with username and password.
    pub async fn login(&self, username: String, password: String) -> Result<bool, String> {
        crate::matrix::authentication::login(&self.client, &self.session_path, username, password)
            .await
    }

    /// Register a new account.
    pub async fn register(
        &self,
        username: String,
        password: String,
        display_name: String,
        token: Option<String>,
    ) -> Result<bool, String> {
        return crate::matrix::authentication::register(
            &self.client,
            &self.session_path,
            username,
            password,
            display_name,
            token,
        )
        .await;
    }

    /// Log out and clear the session.
    pub async fn logout(&self) -> Result<bool, String> {
        let client = self.client.clone();
        let session_path = self.session_path.clone();
        return crate::matrix::authentication::logout(&client, &session_path).await;
    }

    /// Whether the client has an active session.
    pub fn is_client_authenticated(&self) -> Result<bool, String> {
        crate::matrix::authentication::is_client_authenticated(&self.client)
    }

    /// Get the current user's display name (profile).
    pub async fn get_display_name(&self) -> Result<Option<String>, String> {
        self.client
            .account()
            .get_display_name()
            .await
            .map_err(|e| e.to_string())
    }

    /// Set the current user's display name (profile).
    pub async fn set_display_name(&self, display_name: String) -> Result<(), String> {
        let name = if display_name.trim().is_empty() {
            None
        } else {
            Some(display_name.trim().to_string())
        };
        self.client
            .account()
            .set_display_name(name.as_deref())
            .await
            .map_err(|e| e.to_string())
    }

    pub async fn register_pusher(
        &self,
        push_key: String,
        app_id: String,
        url: String,
        display_name: String,
        profile_tag: String,
        lang: String,
        app_display_name: String,
    ) -> Result<(), String> {
        crate::matrix::client::register_pusher(
            &self.client,
            push_key,
            app_id,
            url,
            display_name,
            profile_tag,
            lang,
            app_display_name,
        )
        .await
    }

    pub async fn unregister_pusher(&self, push_key: String, app_id: String) -> Result<(), String> {
        crate::matrix::client::unregister_pusher(&self.client, push_key, app_id).await
    }

    /// Fetch all rooms the user is in. Uses the app stored in this client (from [MatrixClient::start_sync_service]).
    pub async fn get_all_rooms(&self) -> Vec<crate::matrix::rooms::RoomUpdate> {
        let guard = self.app.lock().await;
        let app = guard.clone();
        drop(guard);
        match app {
            Some(a) => rooms::get_all_rooms(&a).await,
            None => Vec::new(),
        }
    }

    /// Subscribe to room list updates (joined / invited / left). Uses the app stored in this client.
    pub async fn subscribe_to_all_room_updates(
        &self,
        stream: StreamSink<crate::matrix::rooms::RoomUpdate>,
    ) {
        rooms::subscribe_to_all_room_updates(&self.client, stream).await;
    }

    /// Subscribe to the canonical room list. Emits the full list whenever it changes (sync or send_message).
    /// Call after [MatrixClient::start_sync_service]. Initial snapshot is sent immediately.
    pub async fn subscribe_to_room_list(&self, stream: StreamSink<Vec<RoomUpdate>>) {
        let app_guard = self.app.lock().await;
        let app = match app_guard.as_ref() {
            Some(a) => a.clone(),
            None => {
                tracing::warn!("subscribe_to_room_list: sync not started");
                return;
            }
        };
        drop(app_guard);

        let initial = rooms::get_all_rooms(&app).await;
        {
            let mut cache = self.room_list_cache.lock().await;
            *cache = initial.clone();
        }
        let _ = stream.add(initial);

        let stream_ref = Arc::new(stream);
        *self.room_list_sink.lock().await = Some(Arc::clone(&stream_ref));
        let client = self.client.clone();
        let cache = self.room_list_cache.clone();
        let sink_guard = self.room_list_sink.clone();
        tokio::spawn(async move {
            rooms::subscribe_to_room_list_loop(client, cache, stream_ref).await;
            *sink_guard.lock().await = None;
        });
    }

    /// Start the sync service (required for rooms and timeline to work).
    /// Stores the App in this client; rooms/timeline/sync state use it instead of global state.
    pub async fn start_sync_service(&self) -> Result<bool, String> {
        let client = self.client.clone();
        let app_mutex = self.app.clone(); // same Arc as self.app
        let app = sync_service::start_sync_service(client).await?;
        *app_mutex.lock().await = Some(app); // updates self.app (shared Arc)
        Ok(true)
    }

    /// Restart the sync service after it has stopped (e.g. after long background). Safe to call repeatedly.
    pub async fn restart_sync_service(&self) -> Result<bool, String> {
        let app_mutex = self.app.clone();
        let guard = app_mutex.lock().await;
        let app = guard
            .as_ref()
            .ok_or("Sync not started; call start_sync_service first")?
            .clone();
        drop(guard);
        sync_service::restart_sync_service(app).await
    }

    /// Send a message. Returns the event_id. Room list and timeline list caches are updated immediately.
    pub async fn send_message(&self, room_id: String, content: String) -> Result<String, String> {
        let result = rooms::send_message(&self.client, room_id.clone(), content).await?;
        let update = result.room_update.clone();
        *self.last_sent_room_update.lock().await = Some(result.room_update.clone());
        // Update canonical room list.
        let mut cache = self.room_list_cache.lock().await;
        rooms::merge_room_update_into_list(&mut cache, update.clone());
        rooms::sort_room_list_by_activity(&mut cache);
        if let Some(ref sink) = *self.room_list_sink.lock().await {
            let _ = sink.add(cache.clone());
        }
        drop(cache);
        // Append sent message to timeline list for this room so subscribers see it immediately.
        if let Some(ref msg) = result.room_update.message {
            let mut cache = self.timeline_list_cache.lock().await;
            cache.entry(room_id.clone()).or_default().push(msg.clone());
            let list = cache.get(&room_id).cloned().unwrap_or_default();
            drop(cache);
            let sinks = self.timeline_list_sinks.lock().await;
            if let Some(sink) = sinks.get(&room_id) {
                let _ = sink.add(list);
            }
        }
        Ok(result.event_id)
    }

    /// Takes the room update stored by the last successful [MatrixClient::send_message].
    /// Call this after send_message succeeds to update the room list with the correct last message.
    pub async fn take_last_sent_room_update(&self) -> Option<RoomUpdate> {
        self.last_sent_room_update.lock().await.take()
    }

    pub async fn create_direct_room(&self, user_id: String) -> Result<String, String> {
        rooms::create_direct_room(&self.client, user_id).await
    }

    pub async fn create_group_room(
        &self,
        name: String,
        user_ids: Vec<String>,
    ) -> Result<String, String> {
        rooms::create_group_room(&self.client, name, user_ids).await
    }

    pub async fn join_room(&self, room_id: String) -> Result<String, String> {
        rooms::join_room(&self.client, room_id).await
    }

    pub async fn leave_room(&self, room_id: String) -> Result<String, String> {
        rooms::leave_room(&self.client, room_id).await
    }

    pub async fn get_timeline_items_by_room_id(
        &self,
        room_id: String,
    ) -> Vec<crate::matrix::timelines::Message> {
        timelines::get_timeline_items_by_room_id(&self.client, room_id).await
    }

    pub async fn subscribe_to_timeline_updates(
        &self,
        stream: StreamSink<crate::matrix::timelines::MessageUpdate>,
        room_id: String,
    ) {
        timelines::subscribe_to_timeline_updates(&self.client, stream, room_id).await;
    }

    /// Subscribe to the canonical message list for a room. Emits the full list whenever it changes (timeline updates or send_message).
    /// Sends initial list immediately, then runs the timeline diff loop. Call after [MatrixClient::start_sync_service].
    pub async fn subscribe_to_timeline_list(
        &self,
        room_id: String,
        stream: StreamSink<Vec<Message>>,
    ) {
        let initial = timelines::get_timeline_items_by_room_id(&self.client, room_id.clone()).await;
        {
            let mut cache = self.timeline_list_cache.lock().await;
            cache.insert(room_id.clone(), initial.clone());
        }
        let _ = stream.add(initial.clone());
        // Refresh room list with last message so listing shows it (SDK latest_event can be empty)
        if let Some(last_msg) = initial.last().cloned() {
            if let Ok(room_id_parsed) = room_id.parse::<matrix_sdk::ruma::OwnedRoomId>() {
                if let Some(room) = self.client.get_room(&room_id_parsed) {
                    let mut update = rooms::get_room_update_data(&room).await;
                    update.message = Some(last_msg);
                    let mut cache = self.room_list_cache.lock().await;
                    rooms::merge_room_update_into_list(&mut cache, update);
                    rooms::sort_room_list_by_activity(&mut cache);
                    let list = cache.clone();
                    drop(cache);
                    if let Some(ref sink) = *self.room_list_sink.lock().await {
                        let _ = sink.add(list);
                    }
                }
            }
        }

        let mut sinks = self.timeline_list_sinks.lock().await;
        sinks.insert(room_id.clone(), Arc::new(stream));
        drop(sinks);

        // Cancel any existing timeline loop for this room to avoid duplicate diffs.
        let mut cancel_map = self.timeline_list_cancel.lock().await;
        if let Some(prev) = cancel_map.remove(&room_id) {
            prev.cancel();
        }
        let cancel_token = CancellationToken::new();
        let cancel_child = cancel_token.child_token();
        cancel_map.insert(room_id.clone(), cancel_token);
        drop(cancel_map);

        let client = self.client.clone();
        let cache_map = self.timeline_list_cache.clone();
        let sinks_map = self.timeline_list_sinks.clone();
        let sinks_for_cleanup = self.timeline_list_sinks.clone();
        let cancel_for_cleanup = self.timeline_list_cancel.clone();
        let room_list_cache = self.room_list_cache.clone();
        let room_list_sink = self.room_list_sink.clone();
        let room_id_owned = room_id.clone();
        tokio::spawn(async move {
            timelines::subscribe_to_timeline_list_loop(
                client,
                room_id_owned.clone(),
                cache_map,
                sinks_map,
                room_list_cache,
                room_list_sink,
                cancel_child,
            )
            .await;
            let mut s = sinks_for_cleanup.lock().await;
            s.remove(&room_id_owned);
            let mut c = cancel_for_cleanup.lock().await;
            c.remove(&room_id_owned);
        });
    }

    /// Load older messages (paginate backwards). Updates the timeline list cache and pushes to
    /// subscribers so the UI receives the full list including newly loaded messages.
    pub async fn get_older_messages(
        &self,
        room_id: String,
        count: u16,
    ) -> Result<Vec<Message>, String> {
        let list = timelines::get_older_messages(&self.client, room_id.clone(), count).await?;
        {
            let mut cache = self.timeline_list_cache.lock().await;
            cache.insert(room_id.clone(), list.clone());
        }
        let sinks = self.timeline_list_sinks.lock().await;
        if let Some(sink) = sinks.get(&room_id) {
            let _ = sink.add(list.clone());
        }
        Ok(list)
    }

    pub async fn search_users(
        &self,
        query: String,
    ) -> Result<crate::matrix::user_serach::UserSearchResult, String> {
        user_serach::search_users(&self.client, query).await
    }

    /// Subscribe to sync service state (Idle, Running, Terminated, Error, Offline).
    /// Call after [MatrixClient::start_sync_service]. When state changes, refresh rooms/timeline
    /// or show sync status; mirrors matrix-sdk-ffi SyncServiceStateObserver.
    /// No-ops if sync was not started (no panic).
    pub async fn subscribe_sync_state(
        &self,
        stream: StreamSink<crate::matrix::sync_service::SyncState>,
    ) {
        let app_mutex = self.app.clone();
        let guard = app_mutex.lock().await;
        let app = match guard.as_ref() {
            Some(a) => a.clone(),
            None => {
                tracing::warn!(
                    "subscribe_sync_state: sync not started, call start_sync_service first"
                );
                return;
            }
        };
        drop(guard);
        sync_service::subscribe_sync_state(app, stream).await;
    }
}

use matrix_sdk::{
    ruma::events::room::message::RoomMessageEventContent,
    ruma::{OwnedRoomId, RoomId},
    Client,
};
use std::sync::atomic::AtomicBool;
use std::sync::Arc;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::{
    frb_generated::StreamSink,
    matrix::{
        client::ClientConfig,
        file_send_progress::{FileSendPhase, FileSendProgress},
        file_upload_cache::FileUploadCache,
        file_upload_cache_redaction,
        rooms::{self, RoomUpdate},
        send_timeline_file,
        sync_service::{self, App},
        timeline_media,
        timelines::{self, Message},
        room_info::{
            self, RoomDetails, RoomFileFilter, RoomFileItem,
        },
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
    /// Plain-room file MXC dedup (path + SHA-256 → MXC + optional thumbnail MXC); persisted under session path.
    file_upload_cache: Arc<FileUploadCache>,
    /// Ensures [file_upload_cache_redaction::register_redaction_cleanup] runs only once per client.
    file_upload_redaction_handler_registered: Arc<AtomicBool>,
    /// Active [CancellationToken] for [MatrixClient::send_timeline_file_with_progress] (cancel via [MatrixClient::cancel_timeline_file_send]).
    file_send_cancel: Arc<Mutex<Option<CancellationToken>>>,
}

impl MatrixClient {
    /// Initialize the client with the given config. Returns a [MatrixClient] instance to use for
    /// all further operations (login, register, get_all_rooms, etc.).
    pub async fn configure(config: ClientConfig) -> Result<MatrixClient, String> {
        let session_path = config.session_path.clone();
        let store_passphrase = config.passphrase.clone();
        let client = crate::matrix::client::configure_client(&config).await?;
        let file_upload_cache =
            Arc::new(FileUploadCache::open(&session_path, store_passphrase.as_deref()).await?);
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
            file_upload_cache,
            file_upload_redaction_handler_registered: Arc::new(AtomicBool::new(false)),
            file_send_cancel: Arc::new(Mutex::new(None)),
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
        let own_user_id = self.client.user_id().map(|u| u.to_string());
        let guard = self.app.lock().await;
        let app = guard.clone();
        drop(guard);
        match app {
            Some(a) => rooms::get_all_rooms(&a, own_user_id).await,
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

        let own_user_id = self.client.user_id().map(|u| u.to_string());
        let initial = rooms::get_all_rooms(&app, own_user_id.clone()).await;
        {
            let mut cache = self.room_list_cache.lock().await;
            *cache = initial.clone();
        }
        let _ = stream.add(initial);

        let stream_ref = Arc::new(stream);
        *self.room_list_sink.lock().await = Some(Arc::clone(&stream_ref));

        let mut refresh_rx = app.room_list_refresh.subscribe();
        let app_for_refresh = app.clone();
        let own_for_refresh = self.client.user_id().map(|u| u.to_string());
        let cache = self.room_list_cache.clone();
        let stream_for_refresh = Arc::clone(&stream_ref);
        let sink_guard = self.room_list_sink.clone();
        tokio::spawn(async move {
            loop {
                match refresh_rx.recv().await {
                    Ok(()) | Err(RecvError::Lagged(_)) => {
                        rooms::push_full_room_list_to_subscribers(
                            &app_for_refresh,
                            &cache,
                            &stream_for_refresh,
                            own_for_refresh.clone(),
                        )
                        .await;
                    }
                    Err(RecvError::Closed) => break,
                }
            }
            *sink_guard.lock().await = None;
        });
    }

    /// Subscribe the sliding-sync room list to one room (latest events, required state).
    /// Call when the user opens a conversation (same as multiverse `subscribe_to_rooms` on focus).
    pub async fn room_list_subscribe_to_rooms(&self, room_id: String) -> Result<(), String> {
        let room_id = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let app = {
            let guard = self.app.lock().await;
            guard
                .clone()
                .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?
        };
        let rid = room_id.as_ref();
        app.sync_service
            .room_list_service()
            .subscribe_to_rooms(&[rid])
            .await;
        Ok(())
    }

    /// Start the sync service (required for rooms and timeline to work).
    /// Stores the App in this client; rooms/timeline/sync state use it instead of global state.
    pub async fn start_sync_service(&self) -> Result<bool, String> {
        let client = self.client.clone();
        let app_mutex = self.app.clone(); // same Arc as self.app
        let app = sync_service::start_sync_service(client).await?;
        *app_mutex.lock().await = Some(app); // updates self.app (shared Arc)
        file_upload_cache_redaction::register_redaction_cleanup(
            &self.client,
            Arc::clone(&self.file_upload_cache),
            self.file_upload_redaction_handler_registered.as_ref(),
        );
        Ok(true)
    }

    /// Restart the sync service after it has stopped (e.g. after long background). Safe to call repeatedly.
    pub async fn restart_sync_service(&self) -> Result<bool, String> {
        let is_logged_in = crate::matrix::authentication::is_client_authenticated(&self.client)?;
        if !is_logged_in {
            return Err("Client is not logged in".to_string());
        }
        let app_mutex = self.app.clone();
        let guard = app_mutex.lock().await;
        let app = guard
            .as_ref()
            .ok_or("Sync not started; call start_sync_service first")?
            .clone();
        drop(guard);
        sync_service::restart_sync_service(app).await
    }

    /// Send a message through the UI timeline (local echo, offline errors, retry via [Self::retry_failed_send]).
    /// Returns the server event id once echoed; often empty immediately—UI should follow the timeline stream.
    pub async fn send_message(&self, room_id: String, content: String) -> Result<String, String> {
        let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let app = self
            .app
            .lock()
            .await
            .clone()
            .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?;

        let timeline_arc = {
            let tg = app.timelines.lock().unwrap();
            tg.get(&room_id_parsed)
                .map(|t| t.timeline.clone())
                .ok_or_else(|| {
                    "No timeline for this room yet; wait until it appears in the room list after sync."
                        .to_string()
                })?
        };

        let _send_handle = timeline_arc
            .send(RoomMessageEventContent::text_plain(&content).into())
            .await
            .map_err(|e| e.to_string())?;

        // Local echo + send state come through subscribe_to_timeline_list; room list updates from last timeline item.
        Ok(String::new())
    }

    /// Send a file from a local path on the UI timeline.
    ///
    /// Sidecar DB: **`{session_path}/app/app_db.sqlite3`** (SQLCipher; same passphrase as Matrix stores).
    /// Table **`file_upload_cache`**: keyed by **SHA-256 of plaintext file bytes**. Plain rooms store
    /// reusable plain MXC URIs; encrypted rooms store a serialized `m.room.message` template after send
    /// so the same ciphertext/media can be resent with an updated caption without re-uploading.
    ///
    /// Plain reuse probes both MXCs on the server; E2EE reuse matches thumbnail JPEG bytes (when present)
    /// the same way. Timeline thumbnails for **images** and **videos** must come from the app: pass a JPEG
    /// path from the Dart `media` package as [`app_thumbnail_jpeg_path`]. PDF / office embedded thumbnails
    /// are still extracted in Rust when Pdfium / zip paths apply. Video compression is done in the app
    /// before send. **Encrypted** uploads use the SDK **send queue**; a fixed transaction id correlates
    /// queue updates, and the server `event_id` from `RoomSendQueueUpdate::SentEvent` loads the message
    /// into the cache when possible.
    pub async fn send_timeline_file(
        &self,
        room_id: String,
        file_path: String,
        caption: Option<String>,
        app_thumbnail_jpeg_path: Option<String>,
    ) -> Result<String, String> {
        let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let app = self
            .app
            .lock()
            .await
            .clone()
            .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?;

        let timeline_arc = {
            let tg = app.timelines.lock().unwrap();
            tg.get(&room_id_parsed)
                .map(|t| t.timeline.clone())
                .ok_or_else(|| {
                    "No timeline for this room yet; wait until it appears in the room list after sync."
                        .to_string()
                })?
        };

        let cancel = CancellationToken::new();
        let mut noop = |_p: FileSendProgress| {};
        send_timeline_file::send_timeline_file_from_path(
            timeline_arc.as_ref(),
            &self.client,
            self.file_upload_cache.as_ref(),
            room_id,
            file_path,
            caption,
            app_thumbnail_jpeg_path,
            &mut noop,
            &cancel,
        )
        .await?;

        Ok(String::new())
    }

    /// Like [MatrixClient::send_timeline_file] but reports byte progress on `progress` and honours [MatrixClient::cancel_timeline_file_send].
    pub async fn send_timeline_file_with_progress(
        &self,
        room_id: String,
        file_path: String,
        caption: Option<String>,
        app_thumbnail_jpeg_path: Option<String>,
        progress: StreamSink<FileSendProgress>,
    ) -> Result<String, String> {
        let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let app = self
            .app
            .lock()
            .await
            .clone()
            .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?;

        let timeline_arc = {
            let tg = app.timelines.lock().unwrap();
            tg.get(&room_id_parsed)
                .map(|t| t.timeline.clone())
                .ok_or_else(|| {
                    "No timeline for this room yet; wait until it appears in the room list after sync."
                        .to_string()
                })?
        };

        let cancel = CancellationToken::new();
        {
            let mut g = self.file_send_cancel.lock().await;
            if let Some(prev) = g.take() {
                prev.cancel();
            }
            *g = Some(cancel.clone());
        }

        let progress_for_items = progress.clone();
        let mut emit = move |p: FileSendProgress| {
            let _ = progress_for_items.add(p);
        };
        let result = send_timeline_file::send_timeline_file_from_path(
            timeline_arc.as_ref(),
            &self.client,
            self.file_upload_cache.as_ref(),
            room_id,
            file_path,
            caption,
            app_thumbnail_jpeg_path,
            &mut emit,
            &cancel,
        )
        .await;

        *self.file_send_cancel.lock().await = None;
        match &result {
            Ok(()) => {
                let _ = progress.add(FileSendProgress {
                    phase: FileSendPhase::Done,
                    current: 0,
                    total: 0,
                    message: String::new(),
                });
            }
            Err(e) if e == "Cancelled" => {}
            Err(e) => {
                let _ = progress.add(FileSendProgress {
                    phase: FileSendPhase::Failed,
                    current: 0,
                    total: 0,
                    message: e.clone(),
                });
            }
        }
        Ok(String::new())
    }

    /// Cancels an in-progress [MatrixClient::send_timeline_file_with_progress] (upload / send).
    pub async fn cancel_timeline_file_send(&self) {
        let g = self.file_send_cancel.lock().await;
        if let Some(t) = g.as_ref() {
            t.cancel();
        }
    }

    /// Retry sending after a recoverable failure ([Message::send_recoverable]).
    pub async fn retry_failed_send(
        &self,
        room_id: String,
        transaction_id: String,
    ) -> Result<(), String> {
        let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let app = self
            .app
            .lock()
            .await
            .clone()
            .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?;

        let timeline_arc = {
            let tg = app.timelines.lock().unwrap();
            tg.get(&room_id_parsed)
                .map(|t| t.timeline.clone())
                .ok_or_else(|| "No timeline for this room".to_string())?
        };

        timelines::retry_send_by_transaction_id(timeline_arc.as_ref(), &transaction_id).await
    }

    /// Fetches decrypted media bytes for a timeline message (image/video/file/audio).
    /// `event_id` may be a server event id or a **local transaction id** for pending echoes.
    /// Set [thumbnail] to request a server-generated thumbnail when available (smaller for grid UI).
    pub async fn fetch_room_message_media(
        &self,
        room_id: String,
        event_id: String,
        thumbnail: bool,
    ) -> Result<Vec<u8>, String> {
        let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
        let room_owned: OwnedRoomId = room_id_parsed.to_owned();
        let app = self
            .app
            .lock()
            .await
            .clone()
            .ok_or_else(|| "Sync not started; call start_sync_service first".to_string())?;

        let timeline_arc = {
            let tg = app.timelines.lock().unwrap();
            tg.get(&room_owned)
                .map(|t| t.timeline.clone())
                .ok_or_else(|| {
                    "No timeline for this room; open the conversation and wait for sync.".to_string()
                })?
        };

        timeline_media::fetch_media_for_timeline_event(
            &self.client,
            timeline_arc.as_ref(),
            &event_id,
            thumbnail,
        )
        .await
    }

    /// Takes the room update stored by the last successful [MatrixClient::send_message].
    /// Call this after send_message succeeds to update the room list with the correct last message.
    pub async fn take_last_sent_room_update(&self) -> Option<RoomUpdate> {
        self.last_sent_room_update.lock().await.take()
    }

    /// Returns the joined DM room id if a 1:1 direct room with this user already exists
    /// ([`matrix_sdk::Client::get_dm_room`]).
    pub fn get_existing_dm_room_id(&self, user_id: String) -> Option<String> {
        matrix_sdk::ruma::UserId::parse(&user_id)
            .ok()
            .and_then(|uid| {
                self.client
                    .get_dm_room(&uid)
                    .map(|room| room.room_id().to_string())
            })
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

    /// Leave the room and call `/forget` so it disappears from the client room list.
    pub async fn leave_and_forget_room(&self, room_id: String) -> Result<String, String> {
        room_info::leave_and_forget_room(&self.client, room_id).await
    }

    /// Room summary, joined members (empty for DMs), and moderation flags for the current user.
    pub async fn get_room_details(&self, room_id: String) -> Result<RoomDetails, String> {
        room_info::fetch_room_details(&self.client, room_id).await
    }

    /// `m.room.message` events with `msgtype` **m.file** from the **event cache SQLite DB**
    /// (`get_room_events` / timeline persistence). Sent vs received uses sender vs logged-in user.
    pub async fn list_room_files(
        &self,
        room_id: String,
        filter: RoomFileFilter,
    ) -> Result<Vec<RoomFileItem>, String> {
        room_info::list_room_files_from_event_cache(&self.client, room_id, filter).await
    }

    /// Remove a member from the room (kick). Requires sufficient power level.
    pub async fn kick_room_member(
        &self,
        room_id: String,
        user_id: String,
    ) -> Result<(), String> {
        room_info::kick_room_member(&self.client, room_id, user_id).await
    }

    /// Change a member's power level (e.g. 50 = moderator, 100 = admin).
    pub async fn set_room_member_power_level(
        &self,
        room_id: String,
        user_id: String,
        power_level: i64,
    ) -> Result<(), String> {
        room_info::set_room_member_power_level(&self.client, room_id, user_id, power_level).await
    }

    pub async fn get_timeline_items_by_room_id(
        &self,
        room_id: String,
    ) -> Vec<crate::matrix::timelines::Message> {
        let own_user_id = self.client.user_id().map(|u| u.to_string());
        let own = own_user_id.as_deref();
        let app = self.app.lock().await.clone();
        if let Some(app) = app {
            if let Some(messages) =
                timelines::get_timeline_items_from_timelines_map(&app.timelines, &room_id, own)
            {
                return messages;
            }
            if let Ok(rid) = room_id.parse::<OwnedRoomId>() {
                if let Some(tl) = timelines::clone_timeline_arc(&app.timelines, &rid) {
                    return timelines::messages_from_sdk_timeline(tl.as_ref(), own).await;
                }
            }
        }
        timelines::get_timeline_items_by_room_id(&self.client, room_id).await
    }

    pub async fn subscribe_to_timeline_updates(
        &self,
        stream: StreamSink<crate::matrix::timelines::MessageUpdate>,
        room_id: String,
    ) {
        let shared_timeline = {
            let guard = self.app.lock().await;
            if let Some(app) = guard.as_ref() {
                room_id
                    .parse::<OwnedRoomId>()
                    .ok()
                    .and_then(|rid| timelines::clone_timeline_arc(&app.timelines, &rid))
            } else {
                None
            }
        };
        timelines::subscribe_to_timeline_updates(&self.client, stream, room_id, shared_timeline)
            .await;
    }

    /// Subscribe to the canonical message list for a room. Emits the full list whenever it changes (timeline updates or send_message).
    /// Sends initial list immediately, then runs the timeline diff loop. Call after [MatrixClient::start_sync_service].
    pub async fn subscribe_to_timeline_list(
        &self,
        room_id: String,
        stream: StreamSink<Vec<Message>>,
    ) {
        let shared_timeline = {
            let guard = self.app.lock().await;
            if let Some(app) = guard.as_ref() {
                room_id
                    .parse::<OwnedRoomId>()
                    .ok()
                    .and_then(|rid| timelines::clone_timeline_arc(&app.timelines, &rid))
            } else {
                None
            }
        };

        let own_user_id = self.client.user_id().map(|u| u.to_string());
        let own = own_user_id.as_deref();
        let initial = if let Some(app) = self.app.lock().await.clone() {
            if let Some(m) =
                timelines::get_timeline_items_from_timelines_map(&app.timelines, &room_id, own)
            {
                m
            } else if let Some(ref tl) = shared_timeline {
                timelines::messages_from_sdk_timeline(tl.as_ref(), own).await
            } else {
                timelines::get_timeline_items_by_room_id(&self.client, room_id.clone()).await
            }
        } else {
            timelines::get_timeline_items_by_room_id(&self.client, room_id.clone()).await
        };
        {
            let mut cache = self.timeline_list_cache.lock().await;
            cache.insert(room_id.clone(), initial.clone());
        }
        let _ = stream.add(initial.clone());
        // Refresh room list with last message so listing shows it (SDK latest_event can be empty)
        if let Some(last_msg) = initial.last().cloned() {
            if let Ok(room_id_parsed) = room_id.parse::<matrix_sdk::ruma::OwnedRoomId>() {
                if let Some(room) = self.client.get_room(&room_id_parsed) {
                    let mut update = rooms::get_room_update_data(&room, own).await;
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
        let shared_for_loop = shared_timeline.clone();
        let own_for_loop = own_user_id.clone();
        tokio::spawn(async move {
            timelines::subscribe_to_timeline_list_loop(
                client,
                room_id_owned.clone(),
                shared_for_loop,
                own_for_loop,
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
        let shared_timeline = {
            let guard = self.app.lock().await;
            if let Some(app) = guard.as_ref() {
                room_id
                    .parse::<OwnedRoomId>()
                    .ok()
                    .and_then(|rid| timelines::clone_timeline_arc(&app.timelines, &rid))
            } else {
                None
            }
        };

        let own_user_id = self.client.user_id().map(|u| u.to_string());
        let own = own_user_id.as_deref();
        let list = if let Some(tl) = shared_timeline {
            timelines::get_older_messages_for_timeline(tl.as_ref(), count, own).await?
        } else {
            timelines::get_older_messages(&self.client, room_id.clone(), count).await?
        };
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

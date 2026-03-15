use matrix_sdk::Client;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::{
    frb_generated::StreamSink,
    matrix::{
        client::ClientConfig,
        rooms::{self, RoomUpdate},
        sync_service::{self, App},
        timelines, user_serach,
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
        })
    }

    /// Log in with username and password.
    pub async fn login(&self, username: String, password: String) -> Result<bool, String> {
        crate::matrix::authentication::login(&self.client, &self.session_path, username, password)
            .await
    }

    /// Register a new account.
    pub async fn register(&self, username: String, password: String) -> Result<bool, String> {
        return crate::matrix::authentication::register(
            &self.client,
            &self.session_path,
            username,
            password,
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

    /// Send a message. Returns the event_id. After success, call [MatrixClient::take_last_sent_room_update]
    /// to get the room update with the sent message as last (for updating the room list immediately).
    pub async fn send_message(&self, room_id: String, content: String) -> Result<String, String> {
        let result = rooms::send_message(&self.client, room_id, content).await?;
        *self.last_sent_room_update.lock().await = Some(result.room_update);
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

    pub async fn get_older_messages(
        &self,
        room_id: String,
        count: u16,
    ) -> Result<Vec<crate::matrix::timelines::Message>, String> {
        timelines::get_older_messages(&self.client, room_id, count).await
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
    pub async fn subscribe_sync_state(
        &self,
        stream: StreamSink<crate::matrix::sync_service::SyncState>,
    ) {
        let app_mutex = self.app.clone();
        let guard = app_mutex.lock().await;
        let app = guard
            .as_ref()
            .ok_or("Sync not started; call start_sync_service first")
            .unwrap()
            .clone();
        drop(guard);
        sync_service::subscribe_sync_state(app, stream).await;
    }
}

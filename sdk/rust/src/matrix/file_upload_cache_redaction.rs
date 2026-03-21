//! Drop [super::file_upload_cache::FileUploadCache] rows when a synced redaction targets the cached plain-send event.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use matrix_sdk::ruma::events::room::redaction::SyncRoomRedactionEvent;
use matrix_sdk::{Client, Room};

use super::file_upload_cache::FileUploadCache;

pub(crate) fn register_redaction_cleanup(
    client: &Client,
    cache: Arc<FileUploadCache>,
    already_registered: &AtomicBool,
) {
    if already_registered.swap(true, Ordering::SeqCst) {
        return;
    }
    let cache = Arc::clone(&cache);
    client.add_event_handler(move |ev: SyncRoomRedactionEvent, room: Room| {
        let cache = Arc::clone(&cache);
        async move {
            let redaction_rules = room.clone_info().room_version_rules_or_default().redaction;
            if let Some(eid) = ev.redacts(&redaction_rules) {
                let _ = cache.remove_by_event_id(eid.as_ref()).await;
            }
        }
    });
}

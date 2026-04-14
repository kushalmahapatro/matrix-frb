//! Holds [EventHandlerDropGuard] for MatrixRTC decline subscriptions so hang-up can release them.

use std::collections::HashMap;
use std::sync::{Mutex, OnceLock};

use matrix_sdk::event_handler::EventHandlerDropGuard;

fn guards() -> &'static Mutex<HashMap<String, EventHandlerDropGuard>> {
    static GUARDS: OnceLock<Mutex<HashMap<String, EventHandlerDropGuard>>> = OnceLock::new();
    GUARDS.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn watch_key(room_id: &str, rtc_notification_event_id: &str) -> String {
    format!("{room_id}|{rtc_notification_event_id}")
}

pub fn register(key: String, guard: EventHandlerDropGuard) {
    let _ = guards()
        .lock()
        .expect("call_decline_watch mutex poisoned")
        .insert(key, guard);
}

/// Drops the SDK event handler for this outgoing ring notification.
pub fn unregister_key(key: &str) {
    let _ = guards()
        .lock()
        .expect("call_decline_watch mutex poisoned")
        .remove(key);
}

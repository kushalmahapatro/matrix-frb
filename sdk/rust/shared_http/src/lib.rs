//! Shared reqwest client so rhttp (Dart HTTP) and matrix-sdk can use the same HTTP client.
//! - rhttp calls [set_shared_reqwest_client] when its client is created (register_client).
//! - matrix crate calls [get_shared_reqwest_client] when building the Matrix client (if rhttp-client feature is on).

use std::sync::OnceLock;

static SHARED: OnceLock<reqwest::Client> = OnceLock::new();

/// Set the shared reqwest client (e.g. from rhttp when register_client is called).
pub fn set_shared_reqwest_client(client: reqwest::Client) {
    let _ = SHARED.set(client);
}

/// Get a clone of the shared reqwest client, if one was set.
pub fn get_shared_reqwest_client() -> Option<reqwest::Client> {
    SHARED.get().cloned()
}

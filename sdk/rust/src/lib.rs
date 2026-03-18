mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge. This line may not be accurate, and you can change it according to your needs. */
// Matrix Flutter/Rust bridge library.
// Entry points for codegen: `crate::api`, `crate::matrix` (see flutter_rust_bridge.yaml).

#[cfg(target_os = "android")]
mod android;

pub mod api;
pub mod logger;
pub mod matrix;
pub mod rhttp;

// Re-exports so frb_generated.rs can resolve types used by the bridge.
pub use matrix_sdk::reqwest::Certificate;
/// Re-exported so generated code can decode the opaque `Client` argument for `matrix::authentication::is_client_authenticated`.
pub use matrix_sdk::Client;
/// Type alias so frb_generated can resolve `TokioMutex` (used by MatrixClient::app).
pub use tokio::sync::Mutex as TokioMutex;

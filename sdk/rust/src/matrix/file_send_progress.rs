use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// Which part of sending a timeline attachment is in progress (for UI).
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[frb]
pub enum FileSendPhase {
    /// Reserved; video compression runs in the app before the Matrix send.
    VideoCompress,
    /// Uploading the main file to the media repo (plain rooms).
    MainUpload,
    /// Uploading a generated thumbnail (plain rooms).
    ThumbnailUpload,
    /// Sending the `m.room.message` after MXC is known.
    SendingMessage,
    /// Encrypted room: attachment is handed to the send queue (upload may continue in background).
    EncryptedQueued,
    /// Send finished successfully.
    Done,
    /// User cancelled or the operation was aborted.
    Cancelled,
    /// Terminal failure (see [FileSendProgress::message]).
    Failed,
}

/// Byte progress for the current [FileSendPhase] (`current` / `total`), plus phase for labels.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct FileSendProgress {
    pub phase: FileSendPhase,
    pub current: u64,
    pub total: u64,
    /// Error details when [FileSendPhase::Failed]; otherwise empty.
    pub message: String,
}

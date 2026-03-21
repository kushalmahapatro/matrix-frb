//! Bridge: set Pdfium / FFmpeg lookup paths from Flutter ([`crate::matrix::native_media_env`]).

use crate::matrix::native_media_env::{
    ENV_MATRIX_FFMPEG_PATH, ENV_MATRIX_PDFIUM_DIR, ENV_PDFIUM_DYNAMIC_LIB_PATH,
};

/// Sets process environment variables used for PDF thumbnails, video frame extraction, and transcode.
///
/// Call after process start and before sending timeline files if the host OS does not provide
/// Pdfium / `ffmpeg` on `PATH` (mobile). Pass [`None`] or an empty string to skip that key
/// (existing OS environment values are kept).
pub fn set_native_media_env(
    pdfium_dynamic_lib_path: Option<String>,
    matrix_pdfium_dir: Option<String>,
    matrix_ffmpeg_path: Option<String>,
) {
    if let Some(v) = pdfium_dynamic_lib_path {
        if !v.is_empty() {
            std::env::set_var(ENV_PDFIUM_DYNAMIC_LIB_PATH, v);
        }
    }
    if let Some(v) = matrix_pdfium_dir {
        if !v.is_empty() {
            std::env::set_var(ENV_MATRIX_PDFIUM_DIR, v);
        }
    }
    if let Some(v) = matrix_ffmpeg_path {
        if !v.is_empty() {
            std::env::set_var(ENV_MATRIX_FFMPEG_PATH, v);
        }
    }
}

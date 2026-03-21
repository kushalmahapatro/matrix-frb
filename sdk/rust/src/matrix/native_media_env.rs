//! Environment keys for Pdfium and FFmpeg resolution (PDF thumbnails, office previews, video).
//!
//! | Variable | Role |
//! |----------|------|
//! | [`ENV_PDFIUM_DYNAMIC_LIB_PATH`] | Directory searched first for the Pdfium dynamic library (`pdfium_render` naming). |
//! | [`ENV_MATRIX_PDFIUM_DIR`] | Same as above: extra directory to try before cwd / exe dir / system. |
//! | [`ENV_MATRIX_FFMPEG_PATH`] | Full path to the `ffmpeg` executable when it is not on `PATH` (typical on iOS/Android). |
//!
//! Set these in the process environment before sending attachments, or call
//! [`crate::api::native_media_env::set_native_media_env`] from Flutter at startup.
//!
//! Typical Flutter layout (application support, writable): `native_media/pdfium/`
//! containing the Pdfium shared library, and `native_media/bin/ffmpeg` (plus `.exe` on Windows).

/// First directory tried when binding Pdfium (see `pdfium_render::Pdfium::pdfium_platform_library_name_at_path`).
pub const ENV_PDFIUM_DYNAMIC_LIB_PATH: &str = "PDFIUM_DYNAMIC_LIB_PATH";

/// Additional directory containing the Pdfium shared library.
pub const ENV_MATRIX_PDFIUM_DIR: &str = "MATRIX_PDFIUM_DIR";

/// Full path to `ffmpeg` when not discoverable via `PATH`.
pub const ENV_MATRIX_FFMPEG_PATH: &str = "MATRIX_FFMPEG_PATH";

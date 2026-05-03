//! Fetch decrypted media bytes for timeline `m.room.message` events (images, video thumbs, files).
//!
//! When `fetch_media_for_timeline_event` is called with `thumbnail: true`, we fetch the event’s
//! thumbnail MXC. For `m.file`, the SDK uses [`MediaFormat::Thumbnail`] on that MXC; client‑uploaded
//! JPEG thumbs are full images, so we **fall back** to [`MediaFormat::File`] on the same MXC when
//! the thumbnail request does not return a raster (common for PDF / Office attachments).
//!
//! We still avoid downloading the **main** file for timeline previews.
//!
//! Some servers return a **video container** (e.g. MP4) for `GET /thumbnail` when the thumbnail
//! source is the main video MXC. Those bytes are rejected for `Image.memory`. When the event has a
//! **separate** `info.thumbnail_source` (e.g. client-uploaded JPEG), we fall back to
//! [`MediaFormat::File`] on that MXC—same idea as [`fetch_file_thumbnail_as_raster`].

use matrix_sdk::media::{
    MediaEventContent, MediaFormat, MediaRequestParameters, MediaThumbnailSettings,
};
use matrix_sdk::ruma::{
    events::room::message::{FileMessageEventContent, MessageType, VideoMessageEventContent},
    events::room::MediaSource,
    uint, OwnedEventId, OwnedMxcUri,
};
use matrix_sdk::Client;
use matrix_sdk_ui::timeline::{Message as SdkUiMessage, TimelineItemKind};
use matrix_sdk_ui::Timeline as SdkTimeline;

/// Timeline thumbnails are requested at 480×480 max (lighter than the previous 800×800 cap).

fn is_probably_raster_image(data: &[u8]) -> bool {
    if data.len() < 12 {
        return false;
    }
    if data.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return true;
    }
    if data.starts_with(&[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
        return true;
    }
    if data.starts_with(b"GIF87a") || data.starts_with(b"GIF89a") {
        return true;
    }
    if data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP") {
        return true;
    }
    if data.starts_with(b"BM") {
        return true;
    }
    false
}

/// ISO BMFF (`ftyp` at offset 4) — MP4/MOV/etc., not a static raster image.
fn is_probably_isobmff_video(data: &[u8]) -> bool {
    data.len() >= 12 && data.get(4..8) == Some(b"ftyp")
}

fn media_sources_same(main: Option<&MediaSource>, thumb: &MediaSource) -> bool {
    match (main, thumb) {
        (Some(MediaSource::Plain(a)), MediaSource::Plain(b)) => a == b,
        (Some(MediaSource::Encrypted(ea)), MediaSource::Encrypted(eb)) => ea.url == eb.url,
        _ => false,
    }
}

async fn fetch_thumbnail_as_raster(
    media: &matrix_sdk::media::Media,
    content: &impl matrix_sdk::media::MediaEventContent,
    thumb_settings: MediaThumbnailSettings,
) -> Result<Vec<u8>, String> {
    let bytes = media
        .get_thumbnail(content, thumb_settings, true)
        .await
        .map_err(|e| e.to_string())?
        .ok_or_else(|| "Thumbnail not available".to_string())?;
    if is_probably_isobmff_video(&bytes) || !is_probably_raster_image(&bytes) {
        return Err(
            "Thumbnail is not a raster image (server may have returned video or unknown format)"
                .to_string(),
        );
    }
    Ok(bytes)
}

async fn fetch_video_thumbnail_as_raster(
    media: &matrix_sdk::media::Media,
    content: &VideoMessageEventContent,
    thumb_settings: MediaThumbnailSettings,
) -> Result<Vec<u8>, String> {
    match fetch_thumbnail_as_raster(media, content, thumb_settings).await {
        Ok(b) => Ok(b),
        Err(e_first) => {
            let Some(thumb_src) = content
                .info
                .as_ref()
                .and_then(|i| i.thumbnail_source.clone())
            else {
                return Err(e_first);
            };
            if media_sources_same(content.source().as_ref(), &thumb_src) {
                return Err(e_first);
            }
            let bytes = media
                .get_media_content(
                    &MediaRequestParameters {
                        source: thumb_src,
                        format: MediaFormat::File,
                    },
                    true,
                )
                .await
                .map_err(|e| format!("{e_first} (video thumb as file: {e})"))?;
            if is_probably_isobmff_video(&bytes) || !is_probably_raster_image(&bytes) {
                return Err(e_first);
            }
            Ok(bytes)
        }
    }
}

/// `m.file` thumbnails are often a **separate** MXC pointing at a JPEG. `get_thumbnail` uses the
/// `/thumbnail` API, which can fail or return non‑raster data for those URIs; fetching as **file**
/// returns the uploaded JPEG bytes.
async fn fetch_file_thumbnail_as_raster(
    media: &matrix_sdk::media::Media,
    content: &FileMessageEventContent,
    thumb_settings: MediaThumbnailSettings,
) -> Result<Vec<u8>, String> {
    match fetch_thumbnail_as_raster(media, content, thumb_settings).await {
        Ok(b) => Ok(b),
        Err(e_first) => {
            let Some(source) = content.thumbnail_source() else {
                return Err(e_first);
            };
            let bytes = media
                .get_media_content(
                    &MediaRequestParameters {
                        source,
                        format: MediaFormat::File,
                    },
                    true,
                )
                .await
                .map_err(|e| format!("{e_first} (also: MXC as file: {e})"))?;
            if is_probably_isobmff_video(&bytes) || !is_probably_raster_image(&bytes) {
                return Err(e_first);
            }
            Ok(bytes)
        }
    }
}

/// Download thumbnail (if [thumbnail]) or full file; decrypts when the room/event uses encrypted media.
///
/// `event_or_transaction_id` is a server event id **or** a local-echo transaction id (same values the UI
/// exposes as `Message.event_id` / `Message.transaction_id`).
pub async fn fetch_media_for_timeline_event(
    client: &Client,
    timeline: &SdkTimeline,
    event_or_transaction_id: &str,
    thumbnail: bool,
) -> Result<Vec<u8>, String> {
    let parsed_eid: Option<OwnedEventId> = event_or_transaction_id.parse().ok();
    let items = timeline.items().await;
    for item in items {
        let item = item.as_ref();
        let TimelineItemKind::Event(ev) = item.kind() else {
            continue;
        };
        let Some(msg) = ev.content().as_message() else {
            continue;
        };
        let matches_event = if let Some(ref eid) = parsed_eid {
            ev.event_id()
                .map(|id| id.as_str() == eid.as_str())
                .unwrap_or(false)
        } else {
            false
        };
        let matches_txn = ev
            .transaction_id()
            .map(|t| t.as_str() == event_or_transaction_id)
            .unwrap_or(false);
        if !matches_event && !matches_txn {
            continue;
        }
        return fetch_media_for_sdk_message(client, msg, thumbnail).await;
    }

    Err("Message not found on this timeline (wait for sync or scroll)".to_string())
}

/// Small raster for a user avatar (`mxc://` on the media repository). Thumbnail first, then full file.
pub async fn fetch_avatar_mxc_thumbnail(client: &Client, mxc_uri: &str) -> Result<Vec<u8>, String> {
    let uri: OwnedMxcUri = mxc_uri
        .try_into()
        .map_err(|_| format!("Invalid MXC URI: {mxc_uri}"))?;
    // Slightly larger than on-screen bubble (~30px) so thumbnails stay sharp on high DPR.
    let thumb_settings = MediaThumbnailSettings::new(uint!(128), uint!(128));
    let thumb_req = MediaRequestParameters {
        source: MediaSource::Plain(uri.clone()),
        format: MediaFormat::Thumbnail(thumb_settings),
    };
    match client.media().get_media_content(&thumb_req, true).await {
        Ok(bytes) if !bytes.is_empty() => Ok(bytes),
        Ok(_) => Err("Empty avatar thumbnail".to_string()),
        Err(e_thumb) => {
            let file_req = MediaRequestParameters {
                source: MediaSource::Plain(uri),
                format: MediaFormat::File,
            };
            client
                .media()
                .get_media_content(&file_req, true)
                .await
                .map_err(|e_file| format!("Avatar: thumbnail ({e_thumb}); file ({e_file})"))
        }
    }
}

async fn fetch_media_for_sdk_message(
    client: &Client,
    msg: &SdkUiMessage,
    thumbnail: bool,
) -> Result<Vec<u8>, String> {
    let media = client.media();
    let thumb_settings = MediaThumbnailSettings::new(uint!(480), uint!(480));

    match msg.msgtype() {
        MessageType::Image(content) => {
            if thumbnail {
                return fetch_thumbnail_as_raster(&media, content, thumb_settings).await;
            }
            media
                .get_file(content, true)
                .await
                .map_err(|e| e.to_string())?
                .ok_or_else(|| "No image data".to_string())
        }
        MessageType::Video(content) => {
            if thumbnail {
                return fetch_video_thumbnail_as_raster(&media, content, thumb_settings).await;
            }
            media
                .get_file(content, true)
                .await
                .map_err(|e| e.to_string())?
                .ok_or_else(|| "No video data".to_string())
        }
        MessageType::File(content) => {
            if thumbnail {
                return fetch_file_thumbnail_as_raster(&media, content, thumb_settings).await;
            }
            media
                .get_file(content, true)
                .await
                .map_err(|e| e.to_string())?
                .ok_or_else(|| "No file data".to_string())
        }
        MessageType::Audio(content) => media
            .get_file(content, true)
            .await
            .map_err(|e| e.to_string())?
            .ok_or_else(|| "No audio data".to_string()),
        _ => Err("This message type has no downloadable media".to_string()),
    }
}

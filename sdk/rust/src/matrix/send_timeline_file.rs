//! Send a file on the Matrix UI timeline with optional thumbnails and **SHA-256 (plaintext file)
//! dedup** in `file_upload_cache` for **both** plain and encrypted rooms.
//!
//! - **Plain rooms**: reuse plain `mxc://` media after server probe.
//! - **Encrypted rooms**: new uploads go through the SDK **send queue** (`RoomSendQueue::send_attachment`).
//!   A fixed [`TransactionId`] is set on the attachment so we can match
//!   [`RoomSendQueueUpdate::SentEvent`] / [`RoomSendQueueUpdate::MediaUpload`] and then load the
//!   decrypted `m.room.message` into the cache (by server [`EventId`] from the send response).
//!
//! **Image / video timeline thumbnails** are **only** taken from the app: pass a JPEG path from the
//! Flutter `media` package via [`send_timeline_file_from_path`]'s `app_thumbnail_jpeg_path`.
//! Rust / Matrix SDK does not synthesize raster thumbnails for those types on send.
//!
//! Other thumbnails when no app path is supplied:
//! - **PDF**: first page via **Pdfium** ([`crate::matrix::attachment_thumbnails`]) when loadable.
//! - **Office zips** (docx, pptx, xlsx, ODF): first embedded / standard thumbnail image when present.
//! - **Other files**: no synthetic placeholder thumbnail is uploaded.
//!
//! **Video transcode** before upload is handled in the app (Dart `media`); Rust uploads the file at
//! `file_path` as-is.

use std::future::IntoFuture;
use std::path::Path;
use std::pin::Pin;
use std::time::Duration;

use matrix_sdk::attachment::{
    AttachmentConfig as SdkAttachmentConfig, AttachmentInfo, BaseAudioInfo, BaseFileInfo,
    BaseImageInfo, BaseVideoInfo, Thumbnail,
};
use eyeball::SharedObservable;
use matrix_sdk::deserialized_responses::TimelineEvent;
use matrix_sdk::ruma::{
    MxcUri, OwnedEventId, OwnedMxcUri, RoomId, TransactionId, UInt, assign,
    events::{
        AnySyncMessageLikeEvent, AnySyncTimelineEvent,
        room::{
            EncryptedFile, ImageInfo, MediaSource, ThumbnailInfo,
            message::{
                AudioInfo, AudioMessageEventContent, FileInfo, FileMessageEventContent,
                ImageMessageEventContent, MessageType, RoomMessageEventContent,
                TextMessageEventContent, UnstableAmplitude, UnstableAudioDetailsContentBlock,
                UnstableVoiceContentBlock, VideoInfo, VideoMessageEventContent,
            },
        },
    },
};
use matrix_sdk::send_queue::RoomSendQueueUpdate;
use matrix_sdk::TransmissionProgress;
use matrix_sdk_ui::timeline::Timeline;
use tokio::sync::broadcast::error::RecvError;
use mime::Mime;
use sha2::{Digest, Sha256};
use tokio::sync::mpsc;
use tokio_util::sync::CancellationToken;
use tracing;

use super::file_send_progress::{FileSendPhase, FileSendProgress};
use super::file_upload_cache::{CachedEntry, CachedThumbnail, FileUploadCache};
use super::media_mxc_validate::{
    probe_cached_plain_media, CachedPlainMediaProbe,
};

fn parse_mxc(s: &str) -> Result<OwnedMxcUri, String> {
    let m: &MxcUri = s.into();
    m.validate().map_err(|e| e.to_string())?;
    Ok(s.to_owned().into())
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut h = Sha256::new();
    h.update(bytes);
    hex::encode(h.finalize())
}

fn blurhash_from_jpeg_bytes(data: &[u8]) -> Option<String> {
    let img = image::load_from_memory(data).ok()?;
    let rgba = img.to_rgba8();
    let (w, h) = rgba.dimensions();
    if w == 0 || h == 0 {
        return None;
    }
    blurhash::encode(4, 3, w, h, rgba.as_raw()).ok()
}

fn merge_thumb_blurhash_into_info(info: &mut Option<AttachmentInfo>, thumb_jpeg: &[u8]) {
    let Some(hash) = blurhash_from_jpeg_bytes(thumb_jpeg) else {
        return;
    };
    match info {
        Some(AttachmentInfo::Image(ref mut i)) => {
            i.blurhash = Some(hash);
        }
        Some(AttachmentInfo::Video(ref mut i)) => {
            i.blurhash = Some(hash);
        }
        _ => {}
    }
}

/// JPEG from the app (`media` package); validates magic + decodes dimensions for Matrix `ThumbnailInfo`.
fn load_app_jpeg_thumbnail(path: &Path) -> Option<(Vec<u8>, u32, u32, usize)> {
    let data = std::fs::read(path).ok()?;
    if data.len() < 3 || !data.starts_with(&[0xff, 0xd8, 0xff]) {
        return None;
    }
    let img = image::load_from_memory_with_format(&data, image::ImageFormat::Jpeg).ok()?;
    let len = data.len();
    Some((data, img.width(), img.height(), len))
}

async fn thumbnail_from_app_path(app_thumbnail_path: Option<&Path>) -> Option<(Vec<u8>, u32, u32, usize)> {
    let tp = app_thumbnail_path?.to_path_buf();
    tokio::task::spawn_blocking(move || load_app_jpeg_thumbnail(&tp))
        .await
        .ok()
        .flatten()
}

/// Thumbnail bytes for SDK [`SdkAttachmentConfig::thumbnail`] / plain-room MXC upload.
/// `image/*` and `video/*` use **only** [`thumbnail_from_app_path`] (Dart `media`); no SDK thumbnail.
async fn generate_attachment_thumbnail(
    path: &Path,
    mime_type: &Mime,
    data: &[u8],
    app_thumbnail_path: Option<&Path>,
) -> Option<(Vec<u8>, u32, u32, usize)> {
    match mime_type.type_() {
        mime::IMAGE | mime::VIDEO => thumbnail_from_app_path(app_thumbnail_path).await,
        mime::AUDIO => None,
        _ => super::attachment_thumbnails::try_document_thumbnail(path, mime_type, data),
    }
}

fn attachment_info_for(mime_type: &Mime, data: &[u8]) -> Option<AttachmentInfo> {
    match mime_type.type_() {
        mime::IMAGE => {
            let img = image::load_from_memory(data).ok()?;
            Some(AttachmentInfo::Image(BaseImageInfo {
                height: UInt::try_from(img.height()).ok(),
                width: UInt::try_from(img.width()).ok(),
                size: UInt::try_from(data.len()).ok(),
                ..Default::default()
            }))
        }
        mime::VIDEO => Some(AttachmentInfo::Video(BaseVideoInfo {
            size: UInt::try_from(data.len()).ok(),
            ..Default::default()
        })),
        mime::AUDIO => Some(AttachmentInfo::Audio(BaseAudioInfo {
            size: UInt::try_from(data.len()).ok(),
            ..Default::default()
        })),
        _ => Some(AttachmentInfo::File(BaseFileInfo {
            size: UInt::try_from(data.len()).ok(),
        })),
    }
}

fn sdk_thumbnail_from_generated(data: Vec<u8>, width: u32, height: u32, size: usize) -> Option<Thumbnail> {
    Some(Thumbnail {
        data,
        content_type: mime::IMAGE_JPEG,
        height: UInt::try_from(height).ok()?,
        width: UInt::try_from(width).ok()?,
        size: UInt::try_from(size).ok()?,
    })
}

/// Cache reuse requires the same thumbnail **presence** and JPEG **plaintext** hash as this send.
/// Uses `thumb_plaintext_sha256` when set, else legacy `CachedThumbnail::content_sha256_hex`.
fn cache_thumb_matches_entry(
    cached: &CachedEntry,
    incoming_has_thumb: bool,
    incoming_thumb_sha256: Option<&str>,
) -> bool {
    let cached_sha = cached
        .thumb_plaintext_sha256
        .as_deref()
        .or(cached.thumbnail.as_ref().and_then(|t| t.content_sha256_hex.as_deref()));
    let cached_has = cached_sha.is_some();
    if cached_has != incoming_has_thumb {
        return false;
    }
    if !cached_has {
        return true;
    }
    match (cached_sha, incoming_thumb_sha256) {
        (Some(a), Some(b)) => a == b,
        _ => false,
    }
}

fn message_type_from_timeline_event(ev: &TimelineEvent) -> Result<MessageType, String> {
    if ev.kind.is_utd() {
        return Err("event could not be decrypted".to_string());
    }
    let raw = ev.kind.raw();
    let any = raw.deserialize().map_err(|e| e.to_string())?;
    match any {
        AnySyncTimelineEvent::MessageLike(AnySyncMessageLikeEvent::RoomMessage(rm)) => {
            let orig = rm.as_original().ok_or("redacted or non-original room message")?;
            Ok(orig.content.msgtype.clone())
        }
        _ => Err("not an m.room.message".to_string()),
    }
}

fn patch_message_type_caption(
    msg_type: MessageType,
    filename: String,
    caption: Option<TextMessageEventContent>,
) -> MessageType {
    let (body, formatted, filename_field) = match &caption {
        Some(c) => (c.body.clone(), c.formatted.clone(), Some(filename)),
        None => (filename.clone(), None, None),
    };
    match msg_type {
        MessageType::Image(mut c) => {
            c.body = body;
            c.formatted = formatted;
            c.filename = filename_field;
            MessageType::Image(c)
        }
        MessageType::Video(mut c) => {
            c.body = body;
            c.formatted = formatted;
            c.filename = filename_field;
            MessageType::Video(c)
        }
        MessageType::File(mut c) => {
            c.body = body;
            c.formatted = formatted;
            c.filename = filename_field;
            MessageType::File(c)
        }
        MessageType::Audio(mut c) => {
            c.body = body;
            c.formatted = formatted;
            c.filename = filename_field;
            MessageType::Audio(c)
        }
        other => other,
    }
}

/// Matrix-shaped JSON: `thumbnail_url` XOR `thumbnail_file` plus optional `thumbnail_info`.
#[derive(serde::Serialize, serde::Deserialize)]
struct E2eeThumbnailPersist {
    #[serde(skip_serializing_if = "Option::is_none")]
    thumbnail_url: Option<OwnedMxcUri>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thumbnail_file: Option<Box<EncryptedFile>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thumbnail_info: Option<Box<ThumbnailInfo>>,
}

fn e2ee_thumbnail_json_from_message_type(mt: &MessageType) -> Option<String> {
    let (thumb_src, thumb_info): (MediaSource, Option<Box<ThumbnailInfo>>) = match mt {
        MessageType::Image(c) => {
            let info = c.info.as_ref()?;
            let ts = info.thumbnail_source.clone()?;
            (ts, info.thumbnail_info.clone())
        }
        MessageType::Video(c) => {
            let info = c.info.as_ref()?;
            let ts = info.thumbnail_source.clone()?;
            (ts, info.thumbnail_info.clone())
        }
        MessageType::File(c) => {
            let info = c.info.as_ref()?;
            let ts = info.thumbnail_source.clone()?;
            (ts, info.thumbnail_info.clone())
        }
        _ => return None,
    };
    let (thumbnail_url, thumbnail_file) = match thumb_src {
        MediaSource::Plain(url) => (Some(url), None),
        MediaSource::Encrypted(f) => (None, Some(f)),
    };
    let payload = E2eeThumbnailPersist {
        thumbnail_url,
        thumbnail_file,
        thumbnail_info: thumb_info,
    };
    serde_json::to_string(&payload).ok()
}

/// Loads decrypted `m.room.message` JSON for cache reuse and a separate E2EE thumbnail payload.
async fn try_fetch_e2ee_cache_payloads(
    room: &matrix_sdk::room::Room,
    event_id: &OwnedEventId,
) -> (Option<String>, Option<String>) {
    for _ in 0..10u32 {
        tokio::time::sleep(Duration::from_millis(150)).await;
        let Ok(ev) = room.load_or_fetch_event(event_id.as_ref(), None).await else {
            continue;
        };
        let Ok(mt) = message_type_from_timeline_event(&ev) else {
            continue;
        };
        let thumb_json = e2ee_thumbnail_json_from_message_type(&mt);
        let store = RoomMessageEventContent::new(mt);
        let tpl = serde_json::to_string(&store).ok();
        return (tpl, thumb_json);
    }
    (None, None)
}

/// Queue an encrypted attachment on [`matrix_sdk::room::Room::send_queue`], forward
/// [`RoomSendQueueUpdate::MediaUpload`] as progress, and return the server event id from
/// [`RoomSendQueueUpdate::SentEvent`].
///
/// `sdk_config.txn_id` is set to a fresh id so updates can be correlated without relying on
/// [`SendHandle`] internals.
async fn send_encrypted_attachment_via_queue_cancel(
    room: &matrix_sdk::room::Room,
    filename: String,
    mime_type: Mime,
    data: Vec<u8>,
    mut sdk_config: SdkAttachmentConfig,
    cancel: &CancellationToken,
    progress: &mut impl FnMut(FileSendProgress),
) -> Result<OwnedEventId, String> {
    let file_sz = data.len() as u64;
    let our_txn = TransactionId::new();
    sdk_config.txn_id = Some(our_txn.clone());

    let (_echoes, mut rx) = room.send_queue().subscribe().await.map_err(|e| e.to_string())?;

    let handle = room
        .send_queue()
        .send_attachment(filename, mime_type, data, sdk_config)
        .await
        .map_err(|e| e.to_string())?;

    emit(progress, FileSendPhase::EncryptedQueued, 0, file_sz);

    loop {
        tokio::select! {
            biased;
            _ = cancel.cancelled() => {
                let _ = handle.abort().await;
                emit(progress, FileSendPhase::Cancelled, 0, 0);
                return Err("Cancelled".to_string());
            }
            recv = rx.recv() => {
                let update = match recv {
                    Ok(u) => u,
                    Err(RecvError::Lagged(_)) => continue,
                    Err(RecvError::Closed) => {
                        let msg = "send queue update channel closed".to_string();
                        emit_failed(progress, msg.clone());
                        return Err(msg);
                    }
                };

                match update {
                    RoomSendQueueUpdate::SentEvent { transaction_id, event_id }
                        if transaction_id == our_txn =>
                    {
                        emit(progress, FileSendPhase::MainUpload, file_sz, file_sz);
                        return Ok(event_id);
                    }
                    RoomSendQueueUpdate::MediaUpload { related_to, progress: ap, .. }
                        if related_to == our_txn =>
                    {
                        let total = ap.total.max(1) as u64;
                        let cur = ap.current.min(ap.total) as u64;
                        emit(progress, FileSendPhase::MainUpload, cur, total);
                    }
                    RoomSendQueueUpdate::SendError { transaction_id, error, .. }
                        if transaction_id == our_txn =>
                    {
                        let msg = error.to_string();
                        emit_failed(progress, msg.clone());
                        return Err(msg);
                    }
                    RoomSendQueueUpdate::CancelledLocalEvent { transaction_id }
                        if transaction_id == our_txn =>
                    {
                        emit(progress, FileSendPhase::Cancelled, 0, 0);
                        return Err("Cancelled".to_string());
                    }
                    _ => {}
                }
            }
        }
    }
}

fn thumbnail_fields_from_cache(thumb: Option<&CachedThumbnail>) -> Result<(Option<MediaSource>, Option<Box<ThumbnailInfo>>), String> {
    let Some(t) = thumb else {
        return Ok((None, None));
    };
    let source = Some(MediaSource::Plain(parse_mxc(&t.mxc)?));
    let ti = assign!(ThumbnailInfo::new(), {
        width: Some(UInt::try_from(t.width).map_err(|_| "thumb width")?),
        height: Some(UInt::try_from(t.height).map_err(|_| "thumb height")?),
        size: Some(UInt::try_from(t.size).map_err(|_| "thumb size")?),
        mimetype: Some(t.mimetype.clone()),
    });
    Ok((source, Some(Box::new(ti))))
}

fn make_message_type(
    mime_type: &Mime,
    filename: String,
    file_mxc: OwnedMxcUri,
    caption: Option<TextMessageEventContent>,
    info: &Option<AttachmentInfo>,
    thumb: Option<&CachedThumbnail>,
) -> Result<MessageType, String> {
    let (thumb_source, thumb_info) = thumbnail_fields_from_cache(thumb)?;

    let (body, formatted, filename_field) = match caption {
        Some(TextMessageEventContent { body, formatted, .. }) => (body, formatted, Some(filename)),
        None => (filename, None, None),
    };

    Ok(match mime_type.type_() {
        mime::IMAGE => {
            let mut image_info = match info {
                Some(AttachmentInfo::Image(i)) => assign!(ImageInfo::new(), {
                    height: i.height,
                    width: i.width,
                    size: i.size,
                    blurhash: i.blurhash.clone(),
                    is_animated: i.is_animated,
                }),
                _ => ImageInfo::new(),
            };
            image_info.mimetype = Some(mime_type.as_ref().to_owned());
            image_info.thumbnail_source = thumb_source;
            image_info.thumbnail_info = thumb_info;
            MessageType::Image(assign!(ImageMessageEventContent::plain(body, file_mxc), {
                formatted,
                filename: filename_field,
                info: Some(Box::new(image_info)),
            }))
        }
        mime::AUDIO => {
            let mut audio_info = match info {
                Some(AttachmentInfo::Audio(i)) => assign!(AudioInfo::new(), {
                    duration: i.duration,
                    size: i.size,
                }),
                Some(AttachmentInfo::Voice(i)) => assign!(AudioInfo::new(), {
                    duration: i.duration,
                    size: i.size,
                }),
                _ => AudioInfo::new(),
            };
            audio_info.mimetype = Some(mime_type.as_ref().to_owned());
            let mut audio_content = assign!(AudioMessageEventContent::plain(body, file_mxc), {
                formatted,
                filename: filename_field,
                info: Some(Box::new(audio_info)),
            });
            let (dur_opt, wf_opt) = match info {
                Some(AttachmentInfo::Audio(i)) | Some(AttachmentInfo::Voice(i)) => {
                    (i.duration, i.waveform.as_deref())
                }
                _ => (None, None),
            };
            if let (Some(dur), Some(wf)) = (dur_opt, wf_opt) {
                if !wf.is_empty() {
                    let waveform: Vec<UnstableAmplitude> = wf
                        .iter()
                        .copied()
                        .map(|v| {
                            let scaled =
                                (v.clamp(0.0, 1.0) * f32::from(UnstableAmplitude::MAX)) as u16;
                            UnstableAmplitude::new(scaled)
                        })
                        .collect();
                    audio_content.audio =
                        Some(UnstableAudioDetailsContentBlock::new(dur, waveform));
                }
            }
            if matches!(info, Some(AttachmentInfo::Voice(_))) {
                audio_content.voice = Some(UnstableVoiceContentBlock::new());
            }
            MessageType::Audio(audio_content)
        }
        mime::VIDEO => {
            let mut video_info = match info {
                Some(AttachmentInfo::Video(i)) => assign!(VideoInfo::new(), {
                    duration: i.duration,
                    height: i.height,
                    width: i.width,
                    size: i.size,
                    blurhash: i.blurhash.clone(),
                }),
                _ => VideoInfo::new(),
            };
            video_info.mimetype = Some(mime_type.as_ref().to_owned());
            video_info.thumbnail_source = thumb_source;
            video_info.thumbnail_info = thumb_info;
            MessageType::Video(assign!(VideoMessageEventContent::plain(body, file_mxc), {
                formatted,
                filename: filename_field,
                info: Some(Box::new(video_info)),
            }))
        }
        _ => {
            let mut file_info = match info {
                Some(AttachmentInfo::File(i)) => assign!(FileInfo::new(), {
                    size: i.size,
                }),
                _ => FileInfo::new(),
            };
            file_info.mimetype = Some(mime_type.as_ref().to_owned());
            file_info.thumbnail_source = thumb_source;
            file_info.thumbnail_info = thumb_info;
            MessageType::File(assign!(FileMessageEventContent::plain(body, file_mxc), {
                formatted,
                filename: filename_field,
                info: Some(Box::new(file_info)),
            }))
        }
    })
}

fn emit<P: FnMut(FileSendProgress)>(progress: &mut P, phase: FileSendPhase, current: u64, total: u64) {
    progress(FileSendProgress {
        phase,
        current,
        total,
        message: String::new(),
    });
}

fn emit_failed<P: FnMut(FileSendProgress)>(progress: &mut P, message: String) {
    progress(FileSendProgress {
        phase: FileSendPhase::Failed,
        current: 0,
        total: 0,
        message,
    });
}

async fn media_upload_with_progress_cancel(
    client: &matrix_sdk::Client,
    content_type: &Mime,
    data: Vec<u8>,
    cancel: &CancellationToken,
    progress: &mut impl FnMut(FileSendProgress),
    phase: FileSendPhase,
) -> Result<OwnedMxcUri, String> {
    let total_bytes = data.len() as u64;
    let send_progress = SharedObservable::<TransmissionProgress>::default();
    let mut subscriber = send_progress.subscribe();
    let (prog_tx, mut prog_rx) = mpsc::unbounded_channel::<TransmissionProgress>();
    let forward = tokio::spawn(async move {
        while let Some(p) = futures_util::StreamExt::next(&mut subscriber).await {
            let _ = prog_tx.send(p);
        }
    });

    // `std::pin::pin!` expands to tokens `syn` cannot parse (breaks flutter_rust_bridge_codegen's
    // `cargo expand` + `syn::parse_file`). `Box::pin` stays valid in expanded output.
    let mut upload: Pin<Box<_>> = Box::pin(IntoFuture::into_future(
        client
            .media()
            .upload(content_type, data, None)
            .with_send_progress_observable(send_progress),
    ));

    let mut prog_open = true;
    loop {
        tokio::select! {
            biased;
            _ = cancel.cancelled() => {
                forward.abort();
                return Err("Cancelled".to_string());
            }
            p = prog_rx.recv(), if prog_open => {
                match p {
                    Some(tp) => {
                        let tot = if tp.total > 0 {
                            tp.total as u64
                        } else {
                            total_bytes
                        };
                        emit(progress, phase, tp.current as u64, tot);
                    }
                    None => prog_open = false,
                }
            }
            res = upload.as_mut() => {
                forward.abort();
                let response = res.map_err(|e: matrix_sdk::Error| e.to_string())?;
                emit(progress, phase, total_bytes, total_bytes);
                return Ok(response.content_uri);
            }
        }
    }
}

async fn send_plain_with_mxcs<P>(
    timeline: &Timeline,
    mime_type: &Mime,
    filename: String,
    file_mxc: OwnedMxcUri,
    caption_content: Option<TextMessageEventContent>,
    info: Option<AttachmentInfo>,
    thumb: Option<&CachedThumbnail>,
    progress: &mut P,
    cancel: &CancellationToken,
) -> Result<String, String>
where
    P: FnMut(FileSendProgress) + Send,
{
    let msg_type = make_message_type(
        mime_type,
        filename,
        file_mxc,
        caption_content,
        &info,
        thumb,
    )?;
    let content = RoomMessageEventContent::new(msg_type);
    let room = timeline.room();
    emit(progress, FileSendPhase::SendingMessage, 0, 1);
    tokio::select! {
        biased;
        _ = cancel.cancelled() => {
            emit(progress, FileSendPhase::Cancelled, 0, 0);
            Err("Cancelled".to_string())
        }
        res = room.send(content) => {
            let res = res.map_err(|e| e.to_string())?;
            emit(progress, FileSendPhase::SendingMessage, 1, 1);
            Ok(res.response.event_id.to_string())
        }
    }
}

/// Optional MSC3245 / MSC1767 voice metadata for `m.audio` (waveform + duration).
///
/// When set with a non-empty waveform, encrypted-room **template reuse** from `file_upload_cache`
/// is skipped so the event JSON matches this send.
pub type AudioTimelineSendExtras = (Duration, Vec<f32>, bool);

async fn send_timeline_file_inner<P>(
    timeline: &Timeline,
    client: &matrix_sdk::Client,
    upload_cache: &FileUploadCache,
    room_id: String,
    file_path: String,
    caption: Option<String>,
    app_thumbnail_jpeg_path: Option<String>,
    audio_extras: Option<AudioTimelineSendExtras>,
    progress: &mut P,
    cancel: &CancellationToken,
) -> Result<(), String>
where
    P: FnMut(FileSendProgress) + Send,
{
    let path = Path::new(&file_path);
    let app_thumb_path = app_thumbnail_jpeg_path
        .as_deref()
        .map(Path::new)
        .filter(|p| p.is_file());
    let data = tokio::fs::read(path).await.map_err(|e| e.to_string())?;
    let filename = path
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("file")
        .to_owned();
    let mime_type: Mime = mime_guess::from_path(path)
        .first_or_octet_stream()
        .to_string()
        .parse()
        .unwrap_or(mime::APPLICATION_OCTET_STREAM);

    if mime_type.type_() == mime::VIDEO && app_thumb_path.is_none() {
        return Err(
            "Timeline video send requires an app-generated JPEG thumbnail (app_thumbnail_jpeg_path)"
                .to_string(),
        );
    }

    let room = timeline.room();
    let encrypted = room
        .latest_encryption_state()
        .await
        .map_err(|e| e.to_string())?
        .is_encrypted();

    let hash = sha256_hex(&data);
    let caption_content = caption.map(TextMessageEventContent::plain);
    let mut info = attachment_info_for(&mime_type, &data);
    if mime_type.type_() == mime::AUDIO {
        if let Some((dur, wf, is_voice)) = audio_extras.as_ref() {
            if !wf.is_empty() {
                let size = match &info {
                    Some(AttachmentInfo::Audio(i)) | Some(AttachmentInfo::Voice(i)) => i.size,
                    _ => UInt::try_from(data.len()).ok(),
                };
                let base = BaseAudioInfo {
                    duration: Some(*dur),
                    waveform: Some(wf.clone()),
                    size: size.or_else(|| UInt::try_from(data.len()).ok()),
                };
                info = Some(if *is_voice {
                    AttachmentInfo::Voice(base)
                } else {
                    AttachmentInfo::Audio(base)
                });
            }
        }
    }
    let skip_e2ee_template_reuse = audio_extras
        .as_ref()
        .is_some_and(|(_, wf, _)| !wf.is_empty());

    let generated_thumb =
        generate_attachment_thumbnail(path, &mime_type, &data, app_thumb_path).await;
    if let Some((ref thumb_data, _, _, _)) = generated_thumb {
        merge_thumb_blurhash_into_info(&mut info, thumb_data);
    }
    let incoming_has_thumb = generated_thumb.is_some();
    let incoming_thumb_sha256 =
        generated_thumb.as_ref().map(|(d, _, _, _)| sha256_hex(d));

    if encrypted {
        if !skip_e2ee_template_reuse {
            if let Some(mut cached) = upload_cache.get_by_sha256(&hash).await {
            if let Some(ref ej) = cached.e2ee_msgtype_json {
                if cache_thumb_matches_entry(
                    &cached,
                    incoming_has_thumb,
                    incoming_thumb_sha256.as_deref(),
                ) {
                    let parsed: RoomMessageEventContent =
                        serde_json::from_str(ej).map_err(|e| e.to_string())?;
                    let patched =
                        patch_message_type_caption(parsed.msgtype, filename.clone(), caption_content.clone());
                    let to_send = RoomMessageEventContent::new(patched);
                    emit(progress, FileSendPhase::SendingMessage, 0, 1);
                    let event_id = tokio::select! {
                        biased;
                        _ = cancel.cancelled() => {
                            emit(progress, FileSendPhase::Cancelled, 0, 0);
                            return Err("Cancelled".to_string());
                        }
                        res = room.send(to_send) => {
                            let res = res.map_err(|e| e.to_string())?;
                            emit(progress, FileSendPhase::SendingMessage, 1, 1);
                            res.response.event_id
                        }
                    };
                    cached.room_id = room_id.clone();
                    cached.event_id = Some(event_id.to_string());
                    cached.thumb_plaintext_sha256 = incoming_thumb_sha256.clone();
                    upload_cache.put_merging_prior(cached).await?;
                    tracing::debug!(
                        target: "matrix.file_upload_cache",
                        sha256 = %hash,
                        "file_upload_cache E2EE template reuse (no re-upload)"
                    );
                    return Ok(());
                }
            }
            }
        }

        let sdk_thumb = generated_thumb
            .as_ref()
            .and_then(|(d, w, h, s)| sdk_thumbnail_from_generated(d.clone(), *w, *h, *s));
        let mut sdk_cfg = SdkAttachmentConfig::new();
        sdk_cfg.info = info;
        sdk_cfg.thumbnail = sdk_thumb;
        sdk_cfg.caption = caption_content;

        let event_id = send_encrypted_attachment_via_queue_cancel(
            &room,
            filename.clone(),
            mime_type.clone(),
            data.clone(),
            sdk_cfg,
            cancel,
            progress,
        )
        .await?;

        let (tpl, tthumb) = try_fetch_e2ee_cache_payloads(&room, &event_id).await;
        if tpl.is_none() {
            tracing::warn!(
                target: "matrix.file_upload_cache",
                event_id = %event_id,
                "could not load m.room.message template after E2EE send; cache row will miss e2ee_msgtype_json until next successful fetch"
            );
        }
        if tthumb.is_none() && incoming_has_thumb {
            tracing::warn!(
                target: "matrix.file_upload_cache",
                event_id = %event_id,
                "E2EE send had a thumbnail but cache could not extract thumbnail_url/thumbnail_file JSON yet"
            );
        }

        upload_cache
            .put_merging_prior(CachedEntry {
                sha256_hex: hash.clone(),
                file_mxc: String::new(),
                thumbnail: None,
                e2ee_msgtype_json: tpl,
                e2ee_thumbnail_json: tthumb,
                thumb_plaintext_sha256: incoming_thumb_sha256.clone(),
                room_id: room_id.clone(),
                event_id: Some(event_id.to_string()),
            })
            .await?;
        tracing::debug!(
            target: "matrix.file_upload_cache",
            sha256 = %hash,
            event_id = %event_id,
            "file_upload_cache row updated (E2EE send, template cached when available)"
        );
        return Ok(());
    }

    if let Some(mut cached) = upload_cache.get_by_sha256(&hash).await {
        let thumb_ok = cache_thumb_matches_entry(
            &cached,
            incoming_has_thumb,
            incoming_thumb_sha256.as_deref(),
        );
        if thumb_ok && !cached.file_mxc.is_empty() {
            match probe_cached_plain_media(
                client,
                &cached.file_mxc,
                cached.thumbnail.as_ref().map(|t| t.mxc.as_str()),
            )
            .await
            {
                CachedPlainMediaProbe::Reusable => {
                    let file_mxc = parse_mxc(&cached.file_mxc)?;
                    let sz = data.len() as u64;
                    emit(progress, FileSendPhase::MainUpload, sz, sz);
                    let event_id = send_plain_with_mxcs(
                        timeline,
                        &mime_type,
                        filename,
                        file_mxc,
                        caption_content,
                        info,
                        cached.thumbnail.as_ref(),
                        progress,
                        cancel,
                    )
                    .await?;
                    cached.room_id = room_id.clone();
                    cached.event_id = Some(event_id);
                    cached.thumb_plaintext_sha256 = incoming_thumb_sha256.clone();
                    upload_cache.put_merging_prior(cached).await?;
                    tracing::debug!(
                        target: "matrix.file_upload_cache",
                        sha256 = %hash,
                        "file_upload_cache updated (plain MXC reuse)"
                    );
                    return Ok(());
                }
                CachedPlainMediaProbe::FileGone | CachedPlainMediaProbe::ThumbGone => {
                    let _ = upload_cache.remove_by_sha256(&hash).await;
                }
            }
        }
    }

    let file_mxc = media_upload_with_progress_cancel(
        client,
        &mime_type,
        data.clone(),
        cancel,
        progress,
        FileSendPhase::MainUpload,
    )
    .await?;

    let thumb_cached = if let Some((thumb_data, w, h, s)) = generated_thumb.as_ref() {
        let uri = media_upload_with_progress_cancel(
            client,
            &mime::IMAGE_JPEG,
            thumb_data.clone(),
            cancel,
            progress,
            FileSendPhase::ThumbnailUpload,
        )
        .await?;
        Some(CachedThumbnail {
            mxc: uri.to_string(),
            width: u64::from(*w),
            height: u64::from(*h),
            size: *s as u64,
            mimetype: "image/jpeg".to_owned(),
            content_sha256_hex: Some(sha256_hex(thumb_data)),
        })
    } else {
        None
    };

    let event_id = send_plain_with_mxcs(
        timeline,
        &mime_type,
        filename,
        file_mxc.clone(),
        caption_content,
        info,
        thumb_cached.as_ref(),
        progress,
        cancel,
    )
    .await?;

    let sha_for_log = hash.clone();
    upload_cache
        .put_merging_prior(CachedEntry {
            sha256_hex: hash,
            file_mxc: file_mxc.to_string(),
            thumbnail: thumb_cached,
            e2ee_msgtype_json: None,
            e2ee_thumbnail_json: None,
            thumb_plaintext_sha256: incoming_thumb_sha256.clone(),
            room_id,
            event_id: Some(event_id),
        })
        .await?;
    tracing::debug!(
        target: "matrix.file_upload_cache",
        sha256 = %sha_for_log,
        file_mxc = %file_mxc,
        "file_upload_cache row written (plain room, new upload)"
    );

    Ok(())
}

/// Send a file from disk on the timeline. **Plain and encrypted** rooms use `file_upload_cache`
/// keyed by SHA-256 of **plaintext file bytes** (see module docs).
///
/// `app_thumbnail_jpeg_path`: optional JPEG on disk from the Flutter `media` package (image + video timeline thumbnails).
/// `audio_duration_ms` + `audio_waveform_normalized` (values in **0..=1**) populate `org.matrix.msc1767.audio` for `m.audio`.
/// When `audio_as_voice_message` is `true`, also sets `org.matrix.msc3245.voice` (MSC3245 voice message).
/// `progress` is invoked on the async runtime thread; `cancel` aborts in-flight uploads and queued encrypted sends cooperatively.
pub async fn send_timeline_file_from_path<P>(
    timeline: &Timeline,
    client: &matrix_sdk::Client,
    upload_cache: &FileUploadCache,
    room_id: String,
    file_path: String,
    caption: Option<String>,
    app_thumbnail_jpeg_path: Option<String>,
    audio_duration_ms: Option<u64>,
    audio_waveform_normalized: Option<Vec<f32>>,
    audio_as_voice_message: bool,
    progress: &mut P,
    cancel: &CancellationToken,
) -> Result<(), String>
where
    P: FnMut(FileSendProgress) + Send,
{
    let audio_extras = match (audio_duration_ms, audio_waveform_normalized) {
        (Some(ms), Some(wf)) if !wf.is_empty() => {
            Some((Duration::from_millis(ms), wf, audio_as_voice_message))
        }
        _ => None,
    };
    let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    if timeline.room().room_id() != std::convert::AsRef::<RoomId>::as_ref(&room_id_parsed) {
        return Err("send_timeline_file: room_id does not match this timeline's room".to_string());
    }

    tokio::select! {
        biased;
        _ = cancel.cancelled() => {
            emit(progress, FileSendPhase::Cancelled, 0, 0);
            Err("Cancelled".to_string())
        }
        r = send_timeline_file_inner(
            timeline,
            client,
            upload_cache,
            room_id,
            file_path,
            caption,
            app_thumbnail_jpeg_path,
            audio_extras,
            progress,
            cancel,
        ) => r,
    }
}

use eyeball_im::Vector;
use flutter_rust_bridge::frb;
use futures::StreamExt;
use matrix_sdk::ruma::events::poll::start::PollKind;
use matrix_sdk::ruma::events::receipt::Receipt as RumaReadReceipt;
use matrix_sdk::ruma::events::room::member::Change as MemberProfileFieldChange;
use matrix_sdk::ruma::events::room::message::{
    FileMessageEventContent, MessageType as RumaMessageType,
};
use matrix_sdk::ruma::events::room::ThumbnailInfo;
use matrix_sdk::ruma::UInt;
use matrix_sdk::ruma::{OwnedEventId, OwnedRoomId};
use matrix_sdk::{Client, Room};
use matrix_sdk_ui::timeline::{
    EmbeddedEvent, EventSendState, EventTimelineItem, MemberProfileChange, Message as SdkUiRoomMessage,
    MembershipChange as UiMembershipChange, PollState, Profile, RoomExt, RoomMembershipChange,
    TimelineDetails, TimelineFocus, TimelineItem, TimelineItemContent, TimelineItemKind,
    TimelineReadReceiptTracking,
};
use matrix_sdk_ui::Timeline as SdkTimeline;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use std::sync::Mutex as StdMutex;
use tokio::sync::broadcast;
use tokio::sync::Mutex as AsyncMutex;
use tokio::sync::OnceCell;
use tokio::task::JoinHandle;
use tokio_util::sync::CancellationToken;

use crate::frb_generated::StreamSink;
use crate::matrix::client::format_user_id_for_display;
use crate::matrix::rooms;
use crate::matrix::sync_notifications::{
    SyncNotificationKind, SyncNotificationSummary, RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS,
};
use tracing::{debug, error};

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[frb]
pub enum EventSendStateKind {
    /// Remote event, or local echo already confirmed / sent.
    Delivered,
    /// Local echo: sending or waiting for network.
    Pending,
    /// Local echo: send failed (see [Message::send_error]; retry if [Message::send_recoverable]).
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageType {
    Message,
    DateDivider,
    ReadMarker,
    TimelineStart,
    /// `m.room.member` join/leave/invite/etc. (human-readable [Message::content]).
    MembershipChange,
    /// Display name / avatar change for a joined member.
    ProfileChange,
}

/// Classification of an `m.room.message` (for media previews). Non-message timeline rows use [RoomMessageKind::Other].
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum RoomMessageKind {
    Text,
    Image,
    File,
    Video,
    Audio,
    /// MSC3381 unstable poll (`org.matrix.msc3381.poll.start`).
    Poll,
    /// MatrixRTC `m.rtc.notification` or legacy `m.call.invite` in the timeline.
    Call,
    Other,
}

/// `m.file` is still a file message in Matrix, but we classify by filename / mimetype so the UI
/// uses image / video / audio viewers (e.g. media_kit) instead of a generic file row.
fn room_kind_for_file_content(f: &FileMessageEventContent) -> RoomMessageKind {
    let name = f.filename();
    let mime = f.info.as_ref().and_then(|i| i.mimetype.as_deref());
    if file_suggests_video(name, mime) {
        return RoomMessageKind::Video;
    }
    if file_suggests_image(name, mime) {
        return RoomMessageKind::Image;
    }
    if file_suggests_audio(name, mime) {
        return RoomMessageKind::Audio;
    }
    RoomMessageKind::File
}

fn file_suggests_video(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| {
        m.starts_with("video/")
            || m == "application/mp4"
            || m == "application/x-matroska"
    }) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "mp4" | "mov" | "webm" | "mkv" | "m4v" | "avi" | "mpeg" | "mpg"
    )
}

fn file_suggests_image(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| m.starts_with("image/")) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "jpg" | "jpeg" | "png" | "gif" | "webp" | "bmp" | "heic" | "heif"
    )
}

fn file_suggests_audio(filename: &str, mimetype: Option<&str>) -> bool {
    if mimetype.is_some_and(|m| m.starts_with("audio/")) {
        return true;
    }
    let Some(ext) = std::path::Path::new(filename)
        .extension()
        .and_then(|e| e.to_str())
    else {
        return false;
    };
    matches!(
        ext.to_ascii_lowercase().as_str(),
        "mp3" | "m4a" | "aac" | "ogg" | "opus" | "flac" | "wav" | "aiff"
    )
}

pub(crate) fn room_msg_kind_from_sdk_ui_message(msg: &SdkUiRoomMessage) -> RoomMessageKind {
    match msg.msgtype() {
        RumaMessageType::Text(_) | RumaMessageType::Notice(_) | RumaMessageType::Emote(_) => {
            RoomMessageKind::Text
        }
        RumaMessageType::Image(_) => RoomMessageKind::Image,
        RumaMessageType::File(f) => room_kind_for_file_content(f),
        RumaMessageType::Video(_) => RoomMessageKind::Video,
        RumaMessageType::Audio(_) => RoomMessageKind::Audio,
        _ => RoomMessageKind::Other,
    }
}

#[cfg(test)]
mod file_kind_tests {
    use super::*;
    use matrix_sdk::ruma::events::room::message::FileMessageEventContent;
    use matrix_sdk::ruma::owned_mxc_uri;

    fn file_msg(filename: Option<&str>, body: &str, mime: Option<&str>) -> FileMessageEventContent {
        let url = owned_mxc_uri!("mxc://example.org/123");
        let mut c = FileMessageEventContent::plain(body.to_owned(), url);
        c.filename = filename.map(String::from);
        if mime.is_some() {
            let mut info = matrix_sdk::ruma::events::room::message::FileInfo::new();
            info.mimetype = mime.map(String::from);
            c.info = Some(Box::new(info));
        }
        c
    }

    #[test]
    fn file_mp4_by_extension_is_video_kind() {
        let f = file_msg(Some("clip.mp4"), "clip.mp4", None);
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::Video);
    }

    #[test]
    fn file_no_ext_video_mime_is_video() {
        let f = file_msg(None, "binary", Some("video/mp4"));
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::Video);
    }

    #[test]
    fn file_pdf_stays_file() {
        let f = file_msg(Some("a.pdf"), "a.pdf", Some("application/pdf"));
        assert_eq!(room_kind_for_file_content(&f), RoomMessageKind::File);
    }
}

/// One reaction key on a timeline message (aggregated senders from matrix-sdk-ui).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct MessageReactionEntry {
    pub key: String,
    pub count: u32,
    /// Whether the logged-in user has sent this reaction key for this event.
    pub contains_own: bool,
    /// Matrix user ids who reacted with this key (sorted for stable UI).
    pub senders: Vec<String>,
}

fn reaction_entries_from_event(ev: &EventTimelineItem, own_user_id: Option<&str>) -> Vec<MessageReactionEntry> {
    let Some(reactions_map) = ev.content().reactions() else {
        return Vec::new();
    };
    let mut keys: Vec<String> = reactions_map.keys().cloned().collect();
    keys.sort();
    let mut out = Vec::new();
    for key in keys {
        let Some(by_user) = reactions_map.get(&key) else {
            continue;
        };
        let senders_raw: Vec<String> = by_user.keys().map(|u| u.to_string()).collect();
        let mut senders_raw_sorted = senders_raw;
        senders_raw_sorted.sort();
        let count = senders_raw_sorted.len() as u32;
        let contains_own =
            own_user_id.is_some_and(|o| senders_raw_sorted.iter().any(|s| s == o));
        let senders: Vec<String> = senders_raw_sorted
            .into_iter()
            .map(|s| format_user_id_for_display(&s))
            .collect();
        out.push(MessageReactionEntry {
            key,
            count,
            contains_own,
            senders,
        });
    }
    out
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum MessageUpdateType {
    Reset,
    Truncate,
    Remove,
    Set,
    Insert,
    PopBack,
    PopFront,
    PushBack,
    PushFront,
    Clear,
    Append,
    TimelineStart,
    ReadMarker,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Message {
    pub event_id: String,
    /// Matrix transaction id for local echoes (empty for remote-only items).
    pub transaction_id: String,
    /// Best-effort display name: room member / profile display name, else formatted user id.
    pub sender: String,
    /// Raw Matrix user id of the sender (`@local:server`); empty for virtual rows.
    pub sender_user_id: String,
    /// Profile avatar MXC when known (`mxc://…`); empty if unset or not loaded yet.
    pub sender_avatar_mxc: String,
    pub content: String,
    pub timestamp: u64,
    pub message_type: MessageType,
    /// `m.room.message` kind for rendering (image/file/video…).
    pub room_msg_kind: RoomMessageKind,
    /// Send state for timeline events (local echo progress / failures).
    pub send_state: EventSendStateKind,
    /// Human-readable error when [EventSendStateKind::Failed].
    pub send_error: String,
    /// Whether the SDK considers the failure recoverable (e.g. retry via [crate::api::matrix_client::MatrixClient::retry_failed_send]).
    pub send_recoverable: bool,
    /// `true` when the event sender is the logged-in user (outgoing); virtual rows are `false`.
    pub is_own: bool,
    /// From `m.room.message` attachment `info.mimetype` when present.
    pub media_mimetype: String,
    /// From `m.room.message` attachment `info.size` when present (bytes).
    pub media_size_bytes: u64,
    /// BlurHash string from image/video `info` when present ([MSC2448]).
    pub media_blurhash: String,
    /// Pixel width for timeline thumb aspect (thumbnail `w` when set, else main media `w`).
    pub media_preview_width: u32,
    /// Pixel height for timeline thumb aspect (thumbnail `h` when set, else main media `h`).
    pub media_preview_height: u32,
    /// Voice/audio: `org.matrix.msc1767.audio` duration in ms, or `info.duration`, else 0.
    pub audio_duration_ms: u64,
    /// Voice/audio: MSC waveform normalized to 0..=1 (empty when not present).
    pub audio_waveform: Vec<f32>,
    /// Event id this message replies to (`m.in_reply_to`), empty when not a reply.
    pub in_reply_to_event_id: String,
    /// Sender of the replied-to event when known.
    pub in_reply_to_sender: String,
    /// Short preview of the quoted message (body or `[image]` / loading hint).
    pub in_reply_to_preview: String,
    /// Kind of the quoted message when known (`Other` if not a reply or not loaded).
    pub in_reply_to_room_msg_kind: RoomMessageKind,
    /// Quoted attachment `info.mimetype` when present.
    pub in_reply_to_media_mimetype: String,
    pub in_reply_to_media_size_bytes: u64,
    pub in_reply_to_media_blurhash: String,
    pub in_reply_to_media_preview_width: u32,
    pub in_reply_to_media_preview_height: u32,
    /// `true` when the replied-to event is redacted (parent bubble is a deleted message).
    pub in_reply_to_parent_redacted: bool,
    /// Aggregated reactions for msg-like events; empty for virtual rows and non-message content.
    pub reactions: Vec<MessageReactionEntry>,
    /// JSON `{"answers":[{"id","text"},...]}` for [RoomMessageKind::Poll]; empty otherwise.
    pub poll_options_json: String,
    /// JSON snapshot for poll UI: kind, max_selections, ended, tallies, voters (disclosed), etc.
    pub poll_state_json: String,
    /// MSC4095 `com.beeper.linkpreviews` JSON array for `m.text` / `m.notice`; `"[]"` when none.
    pub link_previews_json: String,
    /// `true` after an `m.room.redaction` removed content for everyone in the room.
    pub is_redacted: bool,
    /// Other room members with a read receipt on this event (`m.read` / main-thread compatible). Always 0 for virtual rows and local echoes.
    pub read_receipt_count: u32,
    /// Latest `origin_server_ts` among those read receipts (ms since Unix epoch), or 0 if unknown / none.
    pub read_receipt_latest_timestamp_ms: u64,
}

/// Sentinel for missing index/length in MessageUpdate (codegen uses usize, not Option<usize>).
pub const MESSAGE_UPDATE_NONE_INDEX: usize = usize::MAX;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MessageUpdate {
    pub message_update_type: MessageUpdateType,
    pub messages: Option<Vec<Message>>,
    /// Index for Insert/Set/Remove; use MESSAGE_UPDATE_NONE_INDEX when not applicable.
    pub index: usize,
    /// Length for Truncate; use MESSAGE_UPDATE_NONE_INDEX when not applicable.
    pub length: usize,
}

#[frb(ignore)]
pub struct Timeline {
    pub timeline: Arc<SdkTimeline>,
    pub items: Arc<StdMutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
    pub task: JoinHandle<()>,
}

#[frb(ignore)]
pub type Timelines = Arc<StdMutex<HashMap<OwnedRoomId, Timeline>>>;

#[frb(ignore)]
pub enum TimelineKind {
    Room {
        room: Option<OwnedRoomId>,
    },

    Thread {
        room: OwnedRoomId,
        thread_root: OwnedEventId,
        /// The threaded-focused timeline for this thread.
        timeline: Arc<OnceCell<Arc<Timeline>>>,
        /// Items in the thread timeline (to avoid recomputing them every single
        /// time).
        items: Arc<StdMutex<Vector<Arc<matrix_sdk_ui::timeline::TimelineItem>>>>,
        /// Task listening to updates from the threaded timeline, to maintain
        /// the `items` field over time.
        task: JoinHandle<()>,
    },
}

#[frb(ignore)]
impl Clone for TimelineKind {
    fn clone(&self) -> Self {
        match self {
            TimelineKind::Room { room } => TimelineKind::Room { room: room.clone() },
            TimelineKind::Thread {
                room, thread_root, ..
            } => {
                // For thread timeline, create a new instance with default values
                // since JoinHandle and OnceCell can't be cloned
                TimelineKind::Thread {
                    room: room.clone(),
                    thread_root: thread_root.clone(),
                    timeline: Arc::new(OnceCell::new()),
                    items: Arc::new(StdMutex::new(Vector::new())),
                    task: tokio::spawn(async {}), // Empty task as placeholder
                }
            }
        }
    }
}

pub(crate) fn poll_body_from_state(poll: &PollState) -> String {
    let q = poll.results().question;
    let t = q.trim();
    if !t.is_empty() {
        return truncate_timeline_preview(t, 500);
    }
    poll.fallback_text()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .map(|s| truncate_timeline_preview(&s, 500))
        .unwrap_or_else(|| "[poll]".to_string())
}

/// JSON answer ids/text for the Flutter poll vote UI.
pub(crate) fn poll_options_json_from_state(poll: &PollState) -> String {
    let r = poll.results();
    let answers: Vec<serde_json::Value> = r
        .answers
        .iter()
        .map(|a| serde_json::json!({"id": a.id, "text": a.text}))
        .collect();
    serde_json::json!({ "answers": answers }).to_string()
}

/// Rich poll snapshot for Flutter (vote counts, voters when disclosed, poll kind).
pub(crate) fn poll_state_json_from_state(poll: &PollState) -> String {
    let r = poll.results();
    let kind_str: &'static str = match &r.kind {
        PollKind::Undisclosed => "undisclosed",
        PollKind::Disclosed => "disclosed",
        PollKind::_Custom(_) => "custom",
        _ => "custom",
    };
    let tallies: Vec<serde_json::Value> = r
        .answers
        .iter()
        .map(|a| {
            let voters: Vec<String> = r.votes.get(&a.id).cloned().unwrap_or_default();
            serde_json::json!({
                "id": a.id,
                "text": a.text,
                "count": voters.len(),
                "voters": voters,
            })
        })
        .collect();
    let total_selections: usize = r.votes.values().map(|v| v.len()).sum();
    serde_json::json!({
        "kind": kind_str,
        "maxSelections": r.max_selections,
        "ended": r.end_time.is_some(),
        "edited": r.has_been_edited,
        "tallies": tallies,
        "totalSelections": total_selections,
    })
    .to_string()
}

fn event_message_body(ev: &EventTimelineItem) -> String {
    if ev.content().is_unable_to_decrypt() {
        // Non-empty body so Flutter does not drop the row (see paginated_message_list:
        // empty content + no media => SizedBox.shrink). UTD events have no `as_message()` body.
        return "Unable to decrypt message".to_string();
    }
    if let Some(poll) = ev.content().as_poll() {
        return poll_body_from_state(poll);
    }
    ev.content()
        .as_message()
        .map(|msg| msg.body().to_string())
        .unwrap_or_default()
}

/// Serialize bundled URL previews from a timeline SDK message (`m.text` / `m.notice`).
pub(crate) fn link_previews_json_for_sdk_message(msg: &SdkUiRoomMessage) -> String {
    match msg.msgtype() {
        RumaMessageType::Text(t) => {
            if let Some(pv) = &t.url_previews {
                serde_json::to_string(pv).unwrap_or_else(|_| "[]".to_string())
            } else {
                "[]".to_string()
            }
        }
        _ => "[]".to_string(),
    }
}

fn event_link_previews_json(ev: &EventTimelineItem) -> String {
    if let Some(msg) = ev.content().as_message() {
        let s = link_previews_json_for_sdk_message(msg);
        if s != "[]" {
            return s;
        }
    }
    if let Some(raw) = ev.latest_json() {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(raw.json().get()) {
            if let Some(content) = v.get("content") {
                for key in ["com.beeper.linkpreviews", "m.url_previews"] {
                    if let Some(arr) = content.get(key) {
                        return serde_json::to_string(arr).unwrap_or_else(|_| "[]".to_string());
                    }
                }
            }
        }
    }
    "[]".to_string()
}

fn event_room_msg_kind(ev: &EventTimelineItem) -> RoomMessageKind {
    if ev.content().is_poll() {
        return RoomMessageKind::Poll;
    }
    ev.content()
        .as_message()
        .map(room_msg_kind_from_sdk_ui_message)
        .unwrap_or(RoomMessageKind::Other)
}

fn optional_uint_to_u64(opt: Option<UInt>) -> u64 {
    opt.map(Into::into).unwrap_or(0)
}

/// Attachment `info.mimetype` / `info.size` for a UI timeline message (room list latest event, etc.).
pub(crate) fn sdk_ui_message_media_info(msg: &SdkUiRoomMessage) -> (String, u64) {
    match msg.msgtype() {
        RumaMessageType::Image(i) => {
            let mime = i
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(i.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::File(f) => {
            let mime = f
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(f.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::Video(v) => {
            let mime = v
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(v.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        RumaMessageType::Audio(a) => {
            let mime = a
                .info
                .as_ref()
                .and_then(|info| info.mimetype.as_ref())
                .map(ToString::to_string)
                .unwrap_or_default();
            let sz = optional_uint_to_u64(a.info.as_ref().and_then(|info| info.size));
            (mime, sz)
        }
        _ => (String::new(), 0),
    }
}

fn uint_opt_to_u32(u: Option<UInt>) -> u32 {
    let n = optional_uint_to_u64(u);
    u32::try_from(n).unwrap_or(0)
}

fn preview_dims_from_infos(
    thumb: Option<&ThumbnailInfo>,
    main_w: Option<UInt>,
    main_h: Option<UInt>,
) -> (u32, u32) {
    if let Some(t) = thumb {
        let tw = uint_opt_to_u32(t.width);
        let th = uint_opt_to_u32(t.height);
        if tw > 0 && th > 0 {
            return (tw, th);
        }
    }
    (uint_opt_to_u32(main_w), uint_opt_to_u32(main_h))
}

/// BlurHash plus width/height for timeline thumb layout (prefers `thumbnail_info` when set).
pub(crate) fn sdk_ui_message_media_preview(msg: &SdkUiRoomMessage) -> (String, u32, u32) {
    match msg.msgtype() {
        RumaMessageType::Image(i) => {
            let info = i.info.as_deref();
            let blurhash = info
                .and_then(|inf| inf.blurhash.clone())
                .unwrap_or_default();
            let (w, h) = info
                .map(|inf| {
                    preview_dims_from_infos(
                        inf.thumbnail_info.as_deref(),
                        inf.width,
                        inf.height,
                    )
                })
                .unwrap_or((0, 0));
            (blurhash, w, h)
        }
        RumaMessageType::Video(v) => {
            let info = v.info.as_deref();
            let blurhash = info
                .and_then(|inf| inf.blurhash.clone())
                .unwrap_or_default();
            let (w, h) = info
                .map(|inf| {
                    preview_dims_from_infos(
                        inf.thumbnail_info.as_deref(),
                        inf.width,
                        inf.height,
                    )
                })
                .unwrap_or((0, 0));
            (blurhash, w, h)
        }
        RumaMessageType::File(f) => {
            let (w, h) = f
                .info
                .as_deref()
                .and_then(|inf| inf.thumbnail_info.as_deref())
                .map(|t| (uint_opt_to_u32(t.width), uint_opt_to_u32(t.height)))
                .unwrap_or((0, 0));
            (String::new(), w, h)
        }
        _ => (String::new(), 0, 0),
    }
}

/// Fallback: read `org.matrix.msc1767.audio` from the raw timeline JSON when the typed
/// [`SdkUiRoomMessage`] payload does not surface it (e.g. sanitization / version skew).
fn msc1767_audio_from_latest_json(ev: &EventTimelineItem) -> Option<(u64, Vec<f32>)> {
    const AMP_MAX: f32 = 1024.0;
    let raw = ev.latest_json()?;
    let root: serde_json::Value = serde_json::from_str(raw.json().get()).ok()?;
    let content = root.get("content")?.as_object()?;
    let audio = content.get("org.matrix.msc1767.audio")?.as_object()?;
    let dur_val = audio.get("duration")?;
    let dur_ms = dur_val
        .as_u64()
        .or_else(|| dur_val.as_f64().map(|f| f.round().max(0.0) as u64))?;
    let wf_json = audio.get("waveform")?.as_array()?;
    if wf_json.is_empty() {
        return Some((dur_ms, Vec::new()));
    }
    let wf: Vec<f32> = wf_json
        .iter()
        .filter_map(|x| {
            x.as_u64()
                .map(|u| (u as f32 / AMP_MAX).clamp(0.0, 1.0))
                .or_else(|| {
                    x.as_f64()
                        .map(|f| (f as f32 / AMP_MAX).clamp(0.0, 1.0))
                })
        })
        .collect();
    Some((dur_ms, wf))
}

/// MSC1767 / MSC3245 `org.matrix.msc1767.audio`: duration (ms) and waveform samples in 0..=1.
pub(crate) fn sdk_ui_message_audio_details(msg: &SdkUiRoomMessage) -> (u64, Vec<f32>) {
    const AMP_MAX: f32 = 1024.0;
    match msg.msgtype() {
        RumaMessageType::Audio(a) => {
            if let Some(details) = &a.audio {
                let ms = details.duration.as_millis().min(u128::from(u64::MAX)) as u64;
                let wf: Vec<f32> = details
                    .waveform
                    .iter()
                    .map(|amp| {
                        let u = optional_uint_to_u64(Some(amp.get())) as f32;
                        (u / AMP_MAX).clamp(0.0, 1.0)
                    })
                    .collect();
                return (ms, wf);
            }
            let dur_ms = a
                .info
                .as_deref()
                .and_then(|i| i.duration)
                .map(|d| d.as_millis().min(u128::from(u64::MAX)) as u64)
                .unwrap_or(0);
            (dur_ms, Vec::new())
        }
        _ => (0, Vec::new()),
    }
}

fn event_media_attachment_info(ev: &EventTimelineItem) -> (String, u64) {
    let Some(msg) = ev.content().as_message() else {
        return (String::new(), 0);
    };
    sdk_ui_message_media_info(msg)
}

fn event_media_attachment_preview(ev: &EventTimelineItem) -> (String, u32, u32) {
    let Some(msg) = ev.content().as_message() else {
        return (String::new(), 0, 0);
    };
    sdk_ui_message_media_preview(msg)
}

fn truncate_timeline_preview(s: &str, max_chars: usize) -> String {
    let t = s.trim();
    let n = t.chars().count();
    if n <= max_chars {
        return t.to_string();
    }
    let take = max_chars.saturating_sub(1);
    t.chars().take(take).collect::<String>() + "…"
}

fn embedded_reply_body_preview(embedded: &EmbeddedEvent) -> String {
    if embedded.content.is_poll() {
        return "[poll]".to_string();
    }
    if let Some(msg) = embedded.content.as_message() {
        // Prefer stable media labels over filename-like bodies (pickers use long names).
        return match msg.msgtype() {
            RumaMessageType::Image(_) => "[image]".to_string(),
            RumaMessageType::Video(_) => "[video]".to_string(),
            RumaMessageType::Audio(_) => "[audio]".to_string(),
            RumaMessageType::File(_) => "[file]".to_string(),
            _ => {
                let b = msg.body().trim();
                if !b.is_empty() {
                    truncate_timeline_preview(b, 220)
                } else {
                    "[message]".to_string()
                }
            }
        };
    }
    "[message]".to_string()
}

fn in_reply_target_media_from_embedded(
    embedded: &EmbeddedEvent,
) -> (RoomMessageKind, String, u64, String, u32, u32) {
    if embedded.content.is_poll() {
        return (
            RoomMessageKind::Poll,
            String::new(),
            0,
            String::new(),
            0,
            0,
        );
    }
    let Some(msg) = embedded.content.as_message() else {
        return (
            RoomMessageKind::Other,
            String::new(),
            0,
            String::new(),
            0,
            0,
        );
    };
    let kind = room_msg_kind_from_sdk_ui_message(msg);
    let (mime, sz) = sdk_ui_message_media_info(msg);
    let (bh, w, h) = sdk_ui_message_media_preview(msg);
    (kind, mime, sz, bh, w, h)
}

struct InReplySnapshot {
    event_id: String,
    sender: String,
    preview: String,
    room_msg_kind: RoomMessageKind,
    media_mimetype: String,
    media_size_bytes: u64,
    media_blurhash: String,
    media_preview_width: u32,
    media_preview_height: u32,
    parent_redacted: bool,
}

/// Matrix reply metadata for inline quote UI (preview + quoted message media hints).
fn event_in_reply_snapshot(ev: &EventTimelineItem) -> InReplySnapshot {
    let empty = InReplySnapshot {
        event_id: String::new(),
        sender: String::new(),
        preview: String::new(),
        room_msg_kind: RoomMessageKind::Other,
        media_mimetype: String::new(),
        media_size_bytes: 0,
        media_blurhash: String::new(),
        media_preview_width: 0,
        media_preview_height: 0,
        parent_redacted: false,
    };
    let Some(details) = ev.content().in_reply_to() else {
        return empty;
    };
    let id = details.event_id.to_string();
    match &details.event {
        TimelineDetails::Ready(embedded) => {
            let parent_redacted = embedded.content.is_redacted();
            let sender = embedded.sender.to_string();
            let (preview, k, m, s, bh, w, h) = if parent_redacted {
                (
                    String::new(),
                    RoomMessageKind::Other,
                    String::new(),
                    0_u64,
                    String::new(),
                    0_u32,
                    0_u32,
                )
            } else {
                let preview = embedded_reply_body_preview(embedded);
                let (k, m, s, bh, w, h) = in_reply_target_media_from_embedded(embedded);
                (preview, k, m, s, bh, w, h)
            };
            InReplySnapshot {
                event_id: id,
                sender,
                preview,
                room_msg_kind: k,
                media_mimetype: m,
                media_size_bytes: s,
                media_blurhash: bh,
                media_preview_width: w,
                media_preview_height: h,
                parent_redacted,
            }
        }
        TimelineDetails::Pending => InReplySnapshot {
            event_id: id,
            preview: "loading…".to_string(),
            ..empty
        },
        TimelineDetails::Unavailable => InReplySnapshot {
            event_id: id,
            preview: "original message".to_string(),
            ..empty
        },
        TimelineDetails::Error(_) => InReplySnapshot {
            event_id: id,
            preview: "[unavailable]".to_string(),
            ..empty
        },
    }
}

/// Display label and avatar MXC from the timeline sender profile when ready.
pub(crate) fn sender_display_and_avatar_from_profile(
    sender_user_id: &str,
    profile: &TimelineDetails<Profile>,
) -> (String, String) {
    let fallback = format_user_id_for_display(sender_user_id);
    match profile {
        TimelineDetails::Ready(p) => {
            let label = p
                .display_name
                .as_ref()
                .map(|n| n.trim())
                .filter(|n| !n.is_empty())
                .map(|n| n.to_string())
                .unwrap_or_else(|| fallback.clone());
            let avatar = p
                .avatar_url
                .as_ref()
                .map(|u| u.to_string())
                .unwrap_or_default();
            (label, avatar)
        }
        _ => (fallback, String::new()),
    }
}

fn receipt_timestamp_ms(r: &RumaReadReceipt) -> u64 {
    r.ts.map(|t| u64::from(t.0)).unwrap_or(0)
}

/// Read receipts from other members on this timeline item: count and latest receipt timestamp.
fn other_read_receipt_stats(ev: &EventTimelineItem, own_user_id: Option<&str>) -> (u32, u64) {
    let mut count: u32 = 0;
    let mut latest_ms: u64 = 0;
    for (uid, receipt) in ev.read_receipts() {
        if own_user_id.is_some_and(|o| o == uid.as_str()) {
            continue;
        }
        count = count.saturating_add(1);
        latest_ms = latest_ms.max(receipt_timestamp_ms(receipt));
    }
    (count, latest_ms)
}

fn send_state_fields(ev: &EventTimelineItem) -> (EventSendStateKind, String, bool) {
    match ev.send_state() {
        None => (EventSendStateKind::Delivered, String::new(), false),
        Some(EventSendState::NotSentYet { .. }) => {
            (EventSendStateKind::Pending, String::new(), false)
        }
        Some(EventSendState::SendingFailed {
            error,
            is_recoverable,
        }) => (
            EventSendStateKind::Failed,
            error.to_string(),
            *is_recoverable,
        ),
        Some(EventSendState::Sent { .. }) => (EventSendStateKind::Delivered, String::new(), false),
    }
}

fn member_subject_label(mc: &RoomMembershipChange) -> String {
    mc.display_name()
        .filter(|s| !s.trim().is_empty())
        .unwrap_or_else(|| format_user_id_for_display(mc.user_id().as_str()))
}

fn actor_label(ev: &EventTimelineItem) -> String {
    let sender_user_id = ev.sender().to_string();
    sender_display_and_avatar_from_profile(&sender_user_id, ev.sender_profile()).0
}

fn format_membership_change_notice(mc: &RoomMembershipChange, ev: &EventTimelineItem) -> String {
    let subject = member_subject_label(mc);
    let actor = actor_label(ev);
    let sender = ev.sender().as_str();
    let affected = mc.user_id().as_str();

    match mc.change() {
        None => format!("{subject} membership was updated"),
        Some(UiMembershipChange::None) | Some(UiMembershipChange::Error) => {
            format!("{subject} membership was updated")
        }
        Some(UiMembershipChange::Joined) => format!("{subject} joined the room"),
        Some(UiMembershipChange::Left) => format!("{subject} left the room"),
        Some(UiMembershipChange::Banned) => {
            if sender != affected {
                format!("{actor} banned {subject}")
            } else {
                format!("{subject} was banned")
            }
        },
        Some(UiMembershipChange::Unbanned) => {
            if sender != affected {
                format!("{actor} unbanned {subject}")
            } else {
                format!("{subject} was unbanned")
            }
        },
        Some(UiMembershipChange::Kicked) => {
            if sender != affected {
                format!("{actor} removed {subject} from the room")
            } else {
                format!("{subject} left the room")
            }
        },
        Some(UiMembershipChange::Invited) => {
            if sender != affected {
                format!("{actor} invited {subject}")
            } else {
                format!("{subject} was invited")
            }
        },
        Some(UiMembershipChange::KickedAndBanned) => {
            if sender != affected {
                format!("{actor} removed and banned {subject}")
            } else {
                format!("{subject} was removed and banned")
            }
        },
        Some(UiMembershipChange::InvitationAccepted) => format!("{subject} accepted the invite"),
        Some(UiMembershipChange::InvitationRejected) => format!("{subject} declined the invite"),
        Some(UiMembershipChange::InvitationRevoked) => format!("{subject}'s invite was revoked"),
        Some(UiMembershipChange::Knocked) => format!("{subject} asked to join"),
        Some(UiMembershipChange::KnockAccepted) => format!("{subject} was allowed to join"),
        Some(UiMembershipChange::KnockRetracted) => format!("{subject} withdrew their join request"),
        Some(UiMembershipChange::KnockDenied) => format!("{subject}'s join request was denied"),
        Some(UiMembershipChange::NotImplemented) => format!("{subject} membership was updated"),
    }
}

fn describe_displayname_change(
    ch: &MemberProfileFieldChange<Option<String>>,
    user: &str,
) -> Option<String> {
    match (&ch.old, &ch.new) {
        (_, Some(new)) if new.is_empty() => None,
        (None, Some(new)) => Some(format!("{user} set their display name to {new}")),
        (Some(old), Some(new)) if old != new => {
            if new.is_empty() {
                Some(format!("{user} removed their display name (was {old})"))
            } else {
                Some(format!(
                    "{user} changed their display name from {old} to {new}"
                ))
            }
        }
        (Some(old), None) => Some(format!("{user} removed their display name (was {old})")),
        _ => None,
    }
}

fn format_profile_change_notice(pc: &MemberProfileChange) -> String {
    let user = format_user_id_for_display(pc.user_id().as_str());
    let mut parts: Vec<String> = Vec::new();
    if let Some(ch) = pc.displayname_change() {
        if let Some(line) = describe_displayname_change(ch, &user) {
            parts.push(line);
        }
    }
    if pc.avatar_url_change().is_some() {
        parts.push(format!("{user} updated their profile picture"));
    }
    if parts.is_empty() {
        format!("{user} updated their profile")
    } else {
        parts.join(" • ")
    }
}

fn parse_rtc_notification_ring(ev: &EventTimelineItem) -> Option<bool> {
    let raw = ev.latest_json()?;
    let v: serde_json::Value = serde_json::from_str(raw.json().get()).ok()?;
    let content = v.get("content")?;
    let nt = content.get("notification_type")?.as_str()?;
    if nt.eq_ignore_ascii_case("ring") {
        Some(true)
    } else if nt.eq_ignore_ascii_case("notification") {
        Some(false)
    } else {
        None
    }
}

fn matrix_rtc_call_display_body(ev: &EventTimelineItem, own_user_id: Option<&str>) -> String {
    let is_own = own_user_id.is_some_and(|o| o == ev.sender().as_str());
    let is_ring = parse_rtc_notification_ring(ev).unwrap_or(true);
    match (is_own, is_ring) {
        (true, true) => "Outgoing call".to_string(),
        (true, false) => "Call".to_string(),
        (false, true) => "Incoming call".to_string(),
        (false, false) => "Call".to_string(),
    }
}

fn matrix_call_invite_display_body(ev: &EventTimelineItem, own_user_id: Option<&str>) -> String {
    let is_own = own_user_id.is_some_and(|o| o == ev.sender().as_str());
    if is_own {
        "Outgoing call".to_string()
    } else {
        "Incoming call".to_string()
    }
}

/// Timeline row for `m.rtc.notification` / `m.call.invite` (non-empty body, [RoomMessageKind::Call] for UI).
fn event_as_matrix_call_row(
    ev: &EventTimelineItem,
    own_user_id: Option<&str>,
    body: String,
) -> Message {
    let (send_state, send_error, send_recoverable) = send_state_fields(ev);
    let is_redacted = ev.content().is_redacted();
    let event_id = ev.event_id().map(|id| id.to_string()).unwrap_or_default();
    let transaction_id = ev
        .transaction_id()
        .map(|t| t.to_string())
        .unwrap_or_default();
    let sender_user_id = ev.sender().to_string();
    let (sender, sender_avatar_mxc) =
        sender_display_and_avatar_from_profile(&sender_user_id, ev.sender_profile());
    let is_own = own_user_id.is_some_and(|o| o == sender_user_id.as_str());
    let timestamp = u64::from(ev.timestamp().0);
    let (read_receipt_count, read_receipt_latest_timestamp_ms) =
        other_read_receipt_stats(ev, own_user_id);
    Message {
        event_id,
        transaction_id,
        sender,
        sender_user_id,
        sender_avatar_mxc,
        content: body,
        timestamp,
        message_type: MessageType::Message,
        room_msg_kind: RoomMessageKind::Call,
        send_state,
        send_error,
        send_recoverable,
        is_own,
        media_mimetype: String::new(),
        media_size_bytes: 0,
        media_blurhash: String::new(),
        media_preview_width: 0,
        media_preview_height: 0,
        audio_duration_ms: 0,
        audio_waveform: vec![],
        in_reply_to_event_id: String::new(),
        in_reply_to_sender: String::new(),
        in_reply_to_preview: String::new(),
        in_reply_to_room_msg_kind: RoomMessageKind::Other,
        in_reply_to_media_mimetype: String::new(),
        in_reply_to_media_size_bytes: 0,
        in_reply_to_media_blurhash: String::new(),
        in_reply_to_media_preview_width: 0,
        in_reply_to_media_preview_height: 0,
        in_reply_to_parent_redacted: false,
        reactions: vec![],
        poll_options_json: String::new(),
        poll_state_json: String::new(),
        link_previews_json: "[]".to_string(),
        is_redacted,
        read_receipt_count,
        read_receipt_latest_timestamp_ms,
    }
}

fn event_as_system_row(
    ev: &EventTimelineItem,
    own_user_id: Option<&str>,
    content: String,
    message_type: MessageType,
) -> Message {
    let (send_state, send_error, send_recoverable) = send_state_fields(ev);
    let is_redacted = ev.content().is_redacted();
    let event_id = ev.event_id().map(|id| id.to_string()).unwrap_or_default();
    let transaction_id = ev
        .transaction_id()
        .map(|t| t.to_string())
        .unwrap_or_default();
    let sender_user_id = ev.sender().to_string();
    let (sender, sender_avatar_mxc) =
        sender_display_and_avatar_from_profile(&sender_user_id, ev.sender_profile());
    let is_own = own_user_id.is_some_and(|o| o == sender_user_id.as_str());
    let timestamp = u64::from(ev.timestamp().0);
    let (read_receipt_count, read_receipt_latest_timestamp_ms) =
        other_read_receipt_stats(ev, own_user_id);
    Message {
        event_id,
        transaction_id,
        sender,
        sender_user_id,
        sender_avatar_mxc,
        content,
        timestamp,
        message_type,
        room_msg_kind: RoomMessageKind::Other,
        send_state,
        send_error,
        send_recoverable,
        is_own,
        media_mimetype: String::new(),
        media_size_bytes: 0,
        media_blurhash: String::new(),
        media_preview_width: 0,
        media_preview_height: 0,
        audio_duration_ms: 0,
        audio_waveform: vec![],
        in_reply_to_event_id: String::new(),
        in_reply_to_sender: String::new(),
        in_reply_to_preview: String::new(),
        in_reply_to_room_msg_kind: RoomMessageKind::Other,
        in_reply_to_media_mimetype: String::new(),
        in_reply_to_media_size_bytes: 0,
        in_reply_to_media_blurhash: String::new(),
        in_reply_to_media_preview_width: 0,
        in_reply_to_media_preview_height: 0,
        in_reply_to_parent_redacted: false,
        reactions: vec![],
        poll_options_json: String::new(),
        poll_state_json: String::new(),
        link_previews_json: "[]".to_string(),
        is_redacted,
        read_receipt_count,
        read_receipt_latest_timestamp_ms,
    }
}

#[frb(ignore)]
pub fn get_message_from_timeline_item(item: &TimelineItem, own_user_id: Option<&str>) -> Message {
    match item.kind() {
        TimelineItemKind::Event(ev) => {
            match ev.content() {
                TimelineItemContent::MembershipChange(mc) => {
                    return event_as_system_row(
                        ev,
                        own_user_id,
                        format_membership_change_notice(mc, ev),
                        MessageType::MembershipChange,
                    );
                }
                TimelineItemContent::ProfileChange(pc) => {
                    return event_as_system_row(
                        ev,
                        own_user_id,
                        format_profile_change_notice(pc),
                        MessageType::ProfileChange,
                    );
                }
                TimelineItemContent::RtcNotification => {
                    return event_as_matrix_call_row(
                        ev,
                        own_user_id,
                        matrix_rtc_call_display_body(ev, own_user_id),
                    );
                }
                TimelineItemContent::CallInvite => {
                    return event_as_matrix_call_row(
                        ev,
                        own_user_id,
                        matrix_call_invite_display_body(ev, own_user_id),
                    );
                }
                _ => {}
            }
            let (send_state, send_error, send_recoverable) = send_state_fields(ev);
            let is_redacted = ev.content().is_redacted();
            let event_id = ev.event_id().map(|id| id.to_string()).unwrap_or_default();
            let transaction_id = ev
                .transaction_id()
                .map(|t| t.to_string())
                .unwrap_or_default();
            let sender_user_id = ev.sender().to_string();
            let (sender, sender_avatar_mxc) =
                sender_display_and_avatar_from_profile(&sender_user_id, ev.sender_profile());
            let is_own = own_user_id.is_some_and(|o| o == sender_user_id.as_str());
            let content = event_message_body(ev);
            let timestamp = u64::from(ev.timestamp().0);
            let (media_mimetype, media_size_bytes) = event_media_attachment_info(ev);
            let (media_blurhash, media_preview_width, media_preview_height) =
                event_media_attachment_preview(ev);
            let (mut audio_duration_ms, mut audio_waveform) = ev
                .content()
                .as_message()
                .map(sdk_ui_message_audio_details)
                .unwrap_or((0, Vec::new()));
            if audio_waveform.is_empty() {
                if let Some((d, wf)) = msc1767_audio_from_latest_json(ev) {
                    audio_duration_ms = audio_duration_ms.max(d);
                    if !wf.is_empty() {
                        audio_waveform = wf;
                    }
                }
            }
            let ir = event_in_reply_snapshot(ev);
            let reactions = reaction_entries_from_event(ev, own_user_id);
            let (poll_options_json, poll_state_json) =
                if let Some(p) = ev.content().as_poll() {
                    (
                        poll_options_json_from_state(p),
                        poll_state_json_from_state(p),
                    )
                } else {
                    (String::new(), String::new())
                };
            let link_previews_json = event_link_previews_json(ev);
            let (read_receipt_count, read_receipt_latest_timestamp_ms) =
                other_read_receipt_stats(ev, own_user_id);
            Message {
                event_id,
                transaction_id,
                sender,
                sender_user_id,
                sender_avatar_mxc,
                content,
                timestamp,
                message_type: MessageType::Message,
                room_msg_kind: event_room_msg_kind(ev),
                send_state,
                send_error,
                send_recoverable,
                is_own,
                media_mimetype,
                media_size_bytes,
                media_blurhash,
                media_preview_width,
                media_preview_height,
                audio_duration_ms,
                audio_waveform,
                in_reply_to_event_id: ir.event_id,
                in_reply_to_sender: format_user_id_for_display(&ir.sender),
                in_reply_to_preview: ir.preview,
                in_reply_to_room_msg_kind: ir.room_msg_kind,
                in_reply_to_media_mimetype: ir.media_mimetype,
                in_reply_to_media_size_bytes: ir.media_size_bytes,
                in_reply_to_media_blurhash: ir.media_blurhash,
                in_reply_to_media_preview_width: ir.media_preview_width,
                in_reply_to_media_preview_height: ir.media_preview_height,
                in_reply_to_parent_redacted: ir.parent_redacted,
                reactions,
                poll_options_json,
                poll_state_json,
                link_previews_json,
                is_redacted,
                read_receipt_count,
                read_receipt_latest_timestamp_ms,
            }
        }
        TimelineItemKind::Virtual(virtual_timeline_item) => {
            match virtual_timeline_item {
                matrix_sdk_ui::timeline::VirtualTimelineItem::DateDivider(
                    milli_seconds_since_unix_epoch,
                ) => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    sender_user_id: "".to_string(),
                    sender_avatar_mxc: "".to_string(),
                    content: format!("Date: {}", u64::from(milli_seconds_since_unix_epoch.0)),
                    timestamp: u64::from(milli_seconds_since_unix_epoch.0),
                    message_type: MessageType::DateDivider,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                    media_blurhash: String::new(),
                    media_preview_width: 0,
                    media_preview_height: 0,
                    audio_duration_ms: 0,
                    audio_waveform: vec![],
                    in_reply_to_event_id: String::new(),
                    in_reply_to_sender: String::new(),
                    in_reply_to_preview: String::new(),
                    in_reply_to_room_msg_kind: RoomMessageKind::Other,
                    in_reply_to_media_mimetype: String::new(),
                    in_reply_to_media_size_bytes: 0,
                    in_reply_to_media_blurhash: String::new(),
                    in_reply_to_media_preview_width: 0,
                    in_reply_to_media_preview_height: 0,
                    in_reply_to_parent_redacted: false,
                    reactions: vec![],
                    poll_options_json: String::new(),
                    poll_state_json: String::new(),
                    link_previews_json: "[]".to_string(),
                    is_redacted: false,
                    read_receipt_count: 0,
                    read_receipt_latest_timestamp_ms: 0,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::ReadMarker => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    sender_user_id: "".to_string(),
                    sender_avatar_mxc: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::ReadMarker,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                    media_blurhash: String::new(),
                    media_preview_width: 0,
                    media_preview_height: 0,
                    audio_duration_ms: 0,
                    audio_waveform: vec![],
                    in_reply_to_event_id: String::new(),
                    in_reply_to_sender: String::new(),
                    in_reply_to_preview: String::new(),
                    in_reply_to_room_msg_kind: RoomMessageKind::Other,
                    in_reply_to_media_mimetype: String::new(),
                    in_reply_to_media_size_bytes: 0,
                    in_reply_to_media_blurhash: String::new(),
                    in_reply_to_media_preview_width: 0,
                    in_reply_to_media_preview_height: 0,
                    in_reply_to_parent_redacted: false,
                    reactions: vec![],
                    poll_options_json: String::new(),
                    poll_state_json: String::new(),
                    link_previews_json: "[]".to_string(),
                    is_redacted: false,
                    read_receipt_count: 0,
                    read_receipt_latest_timestamp_ms: 0,
                },
                matrix_sdk_ui::timeline::VirtualTimelineItem::TimelineStart => Message {
                    event_id: "".to_string(),
                    transaction_id: "".to_string(),
                    sender: "".to_string(),
                    sender_user_id: "".to_string(),
                    sender_avatar_mxc: "".to_string(),
                    content: "".to_string(),
                    timestamp: 0,
                    message_type: MessageType::TimelineStart,
                    room_msg_kind: RoomMessageKind::Other,
                    send_state: EventSendStateKind::Delivered,
                    send_error: "".to_string(),
                    send_recoverable: false,
                    is_own: false,
                    media_mimetype: String::new(),
                    media_size_bytes: 0,
                    media_blurhash: String::new(),
                    media_preview_width: 0,
                    media_preview_height: 0,
                    audio_duration_ms: 0,
                    audio_waveform: vec![],
                    in_reply_to_event_id: String::new(),
                    in_reply_to_sender: String::new(),
                    in_reply_to_preview: String::new(),
                    in_reply_to_room_msg_kind: RoomMessageKind::Other,
                    in_reply_to_media_mimetype: String::new(),
                    in_reply_to_media_size_bytes: 0,
                    in_reply_to_media_blurhash: String::new(),
                    in_reply_to_media_preview_width: 0,
                    in_reply_to_media_preview_height: 0,
                    in_reply_to_parent_redacted: false,
                    reactions: vec![],
                    poll_options_json: String::new(),
                    poll_state_json: String::new(),
                    link_previews_json: "[]".to_string(),
                    is_redacted: false,
                    read_receipt_count: 0,
                    read_receipt_latest_timestamp_ms: 0,
                },
            }
        }
    }
}

/// Add or remove a reaction on a timeline item ([`SdkTimeline::toggle_reaction`]).
pub async fn toggle_timeline_reaction(
    timeline: &SdkTimeline,
    event_id: String,
    transaction_id: String,
    reaction_key: String,
) -> Result<bool, String> {
    use matrix_sdk::ruma::{OwnedEventId, OwnedTransactionId};
    use matrix_sdk_ui::timeline::TimelineEventItemId;

    let item_id = if !event_id.is_empty() {
        let id: OwnedEventId = event_id.parse().map_err(|e| format!("Invalid event_id: {e}"))?;
        TimelineEventItemId::EventId(id)
    } else if !transaction_id.is_empty() {
        let id: OwnedTransactionId = transaction_id
            .as_str()
            .try_into()
            .map_err(|e| format!("Invalid transaction_id: {e}"))?;
        TimelineEventItemId::TransactionId(id)
    } else {
        return Err("event_id or transaction_id required to toggle reaction".to_string());
    };

    timeline
        .toggle_reaction(&item_id, &reaction_key)
        .await
        .map_err(|e| e.to_string())
}

/// Redact or abort a timeline row ([`SdkTimeline::redact`]) — same item id rules as reactions.
///
/// Resolves the row by server [`EventId`] or local [`TransactionId`], then either sends
/// `m.room.redaction` or aborts a pending local echo (see matrix-sdk-ui).
pub async fn redact_timeline_item(
    timeline: &SdkTimeline,
    event_id: String,
    transaction_id: String,
    reason: Option<&str>,
) -> Result<(), String> {
    use matrix_sdk::ruma::{OwnedEventId, OwnedTransactionId};
    use matrix_sdk_ui::timeline::TimelineEventItemId;

    let item_id = if !event_id.is_empty() {
        let id: OwnedEventId = event_id.parse().map_err(|e| format!("Invalid event_id: {e}"))?;
        TimelineEventItemId::EventId(id)
    } else if !transaction_id.is_empty() {
        let id: OwnedTransactionId = transaction_id
            .as_str()
            .try_into()
            .map_err(|e| format!("Invalid transaction_id: {e}"))?;
        TimelineEventItemId::TransactionId(id)
    } else {
        return Err(
            "event_id or transaction_id required to redact a message".to_string(),
        );
    };

    timeline
        .redact(&item_id, reason)
        .await
        .map_err(|e| {
            let s = e.to_string();
            if s.trim().is_empty() {
                format!("Redact failed: {e:?}")
            } else {
                s
            }
        })
}

/// Retry a failed local send (same as send-queue [SendHandle::unwedge]).
pub(crate) async fn retry_send_by_transaction_id(
    timeline: &SdkTimeline,
    transaction_id: &str,
) -> Result<(), String> {
    let items = timeline.items().await;
    for item in items.iter() {
        let Some(ev) = item.as_event() else {
            continue;
        };
        let Some(tid) = ev.transaction_id() else {
            continue;
        };
        if tid.as_str() != transaction_id {
            continue;
        }
        let Some(handle) = ev.local_echo_send_handle() else {
            return Err("No send handle for this local echo".to_string());
        };
        return handle.unwedge().await.map_err(|e| e.to_string());
    }
    Err("No failed local message with that transaction id".to_string())
}

/// `true` when a timeline [Message] is a peer MatrixRTC **ring** row (sliding-sync notification path).
pub(crate) fn timeline_message_is_peer_incoming_call_ring(m: &Message) -> bool {
    !m.is_own
        && m.room_msg_kind == RoomMessageKind::Call
        && m.content.trim() == "Incoming call"
        && !m.event_id.trim().is_empty()
}

/// MatrixRTC ring row on the UI timeline (sliding sync), when sync may not hit [Client::add_event_handler].
pub(crate) fn summary_from_timeline_incoming_call_ring(
    room: &Room,
    message: &Message,
) -> Option<SyncNotificationSummary> {
    if !timeline_message_is_peer_incoming_call_ring(message) {
        return None;
    }
    let event_id = message.event_id.trim();
    let room_id = room.room_id().to_string();
    let room_display_name = room.cached_display_name().map(|n| n.to_string());
    let sender_raw = message.sender_user_id.trim();
    let sender_id = if sender_raw.is_empty() {
        "Unknown".to_owned()
    } else {
        format_user_id_for_display(sender_raw)
    };
    let sender_display_name = if message.sender.trim().is_empty() {
        None
    } else {
        Some(message.sender.clone())
    };

    Some(SyncNotificationSummary {
        room_id,
        room_display_name,
        kind: SyncNotificationKind::IncomingCall,
        sender_id,
        sender_display_name,
        body_preview: "Incoming call".to_owned(),
        is_highlight: true,
        is_noisy: true,
        event_id: event_id.to_owned(),
        incoming_call_ring: true,
    })
}

/// Runs the timeline diff stream for the room; applies each diff to the room's cache and pushes full list.
/// When timeline list updates, also updates the room list with the last message so the listing shows it.
/// Stops when [cancel] is triggered (e.g. when the client re-subscribes for this room).
/// Caller must ensure cache_map and sinks_map contain an entry for room_id before spawning.
///
/// If [shared_timeline] is set, uses that [`SdkTimeline`] (same as [crate::matrix::sync_service] listen_task);
/// otherwise builds a separate live timeline (e.g. sync not started or room not yet in the sliding list).
pub(crate) async fn subscribe_to_timeline_list_loop(
    client: Client,
    room_id: String,
    shared_timeline: Option<Arc<SdkTimeline>>,
    own_user_id: Option<String>,
    cache_map: Arc<AsyncMutex<HashMap<String, Vec<Message>>>>,
    sinks_map: Arc<AsyncMutex<HashMap<String, Arc<StreamSink<Vec<Message>>>>>>,
    room_list_cache: Arc<AsyncMutex<Vec<rooms::RoomUpdate>>>,
    room_list_sink: Arc<AsyncMutex<Option<Arc<StreamSink<Vec<rooms::RoomUpdate>>>>>>,
    rtc_notify_tx: Option<broadcast::Sender<SyncNotificationSummary>>,
    cancel: CancellationToken,
) {
    let room_id_parsed: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID for timeline list");
            return;
        }
    };

    let room = match client.get_room(room_id_parsed.as_ref()) {
        Some(room) => room,
        None => {
            error!("Room not found for timeline list");
            return;
        }
    };

    let timeline: Arc<SdkTimeline> = if let Some(t) = shared_timeline {
        t
    } else {
        let timeline = match room
            .timeline_builder()
            .track_read_marker_and_receipts(TimelineReadReceiptTracking::MessageLikeEvents)
            .with_focus(TimelineFocus::Live {
                hide_threaded_events: true,
            })
            .build()
            .await
        {
            Ok(t) => t,
            Err(e) => {
                error!("Failed to build timeline: {}", e);
                return;
            }
        };
        Arc::new(timeline)
    };

    // Load up to 50 messages initially so the list fills the screen and is scrollable;
    // if the room has fewer, we get all of them.
    const INITIAL_TIMELINE_PAGE_SIZE: u16 = 50;
    if let Err(e) = timeline
        .paginate_backwards(INITIAL_TIMELINE_PAGE_SIZE)
        .await
    {
        debug!(
            "Initial timeline paginate_backwards failed (non-fatal): {}",
            e
        );
    }

    let (_events, mut diff_stream) = timeline.subscribe().await;
    let own = own_user_id.as_deref();

    loop {
        tokio::select! {
            _ = cancel.cancelled() => {
                debug!("Timeline list loop cancelled for room {}", room_id);
                break;
            }
            next = diff_stream.next() => match next {
            Some(diffs) => {
                if diffs.is_empty() {
                    continue;
                }
                // Rebuild from the UI timeline after each diff batch. Incremental
                // [apply_vector_diff_to_messages] could desync (e.g. skipped inserts), which
                // dropped read-receipt [VectorDiff::Set] updates on the wrong index.
                let list = {
                    let prev_event_ids: HashSet<String> = {
                        let cache_guard = cache_map.lock().await;
                        cache_guard
                            .get(&room_id)
                            .map(|prev| {
                                prev.iter()
                                    .filter_map(|m| {
                                        let e = m.event_id.trim();
                                        if e.is_empty() {
                                            None
                                        } else {
                                            Some(e.to_owned())
                                        }
                                    })
                                    .collect()
                            })
                            .unwrap_or_default()
                    };
                    let items = timeline.items().await;
                    let mut messages: Vec<Message> = items
                        .iter()
                        .map(|v| get_message_from_timeline_item(v.as_ref(), own))
                        .collect();
                    dedupe_stale_local_echoes(&mut messages);
                    if let Some(ref tx) = rtc_notify_tx {
                        let now_ms = SystemTime::now()
                            .duration_since(UNIX_EPOCH)
                            .map(|d| d.as_millis() as u64)
                            .unwrap_or(0);
                        for m in &messages {
                            let eid = m.event_id.trim();
                            if eid.is_empty() || prev_event_ids.contains(eid) {
                                continue;
                            }
                            if !timeline_message_is_peer_incoming_call_ring(m) {
                                continue;
                            }
                            let stale = m.timestamp == 0
                                || now_ms.saturating_sub(m.timestamp)
                                    > RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS;
                            if stale {
                                continue;
                            }
                            if let Some(summary) =
                                summary_from_timeline_incoming_call_ring(&room, m)
                            {
                                let _ = tx.send(summary);
                            }
                        }
                    }
                    let mut cache_guard = cache_map.lock().await;
                    cache_guard.insert(room_id.clone(), messages.clone());
                    messages
                };
                let sinks_guard = sinks_map.lock().await;
                if let Some(sink) = sinks_guard.get(&room_id) {
                    let _ = sink.add(list.clone());
                }
                drop(sinks_guard);
                // Refresh room list with last *message* row from timeline (not date divider / markers)
                if let Some(last_msg) = last_message_row_for_room_preview(&list) {
                    let mut update = rooms::get_room_update_data(&room, own).await;
                    update.message = Some(last_msg);
                    let mut cache = room_list_cache.lock().await;
                    rooms::merge_room_update_into_list(&mut cache, update);
                    rooms::sort_room_list_by_activity(&mut cache);
                    let list_to_push = cache.clone();
                    drop(cache);
                    let sink_guard = room_list_sink.lock().await;
                    if let Some(ref s) = *sink_guard {
                        let _ = s.add(list_to_push);
                    }
                }
            }
            None => {
                debug!("Timeline list stream ended for room {}", room_id);
                break;
            }
            }
        }
    }
}

/// True when this row is suitable for the chat list subtitle (real message / poll / media / redacted).
///
/// Skips virtual rows and system rows ([`MessageType::MembershipChange`], [`MessageType::ProfileChange`]).
/// Other non-message `TimelineItemKind::Event` items still map to [`MessageType::Message`] with
/// [`RoomMessageKind::Other`] and empty body — skip those so the listing shows the previous chat line.
pub(crate) fn is_usable_room_list_preview_message(m: &Message) -> bool {
    if !matches!(m.message_type, MessageType::Message) {
        return false;
    }
    if m.room_msg_kind == RoomMessageKind::Call {
        return !m.is_redacted;
    }
    if m.is_redacted {
        return true;
    }
    if m.room_msg_kind != RoomMessageKind::Other {
        return true;
    }
    !m.poll_options_json.is_empty()
        || !m.content.trim().is_empty()
        || !m.media_mimetype.is_empty()
}

/// Last timeline row that is an actual chat message (skips date dividers, read markers, etc.).
/// Use for room-list preview so the subtitle is not a virtual row like `Date: …`.
pub(crate) fn last_message_row_for_room_preview(list: &[Message]) -> Option<Message> {
    list
        .iter()
        .rev()
        .find(|m| is_usable_room_list_preview_message(m))
        .cloned()
}

#[cfg(test)]
mod room_preview_tests {
    use super::*;

    fn sample(kind: RoomMessageKind, content: &str) -> Message {
        Message {
            event_id: "e1".to_string(),
            transaction_id: String::new(),
            sender: String::new(),
            sender_user_id: String::new(),
            sender_avatar_mxc: String::new(),
            content: content.to_string(),
            timestamp: 1,
            message_type: MessageType::Message,
            room_msg_kind: kind,
            send_state: EventSendStateKind::Delivered,
            send_error: String::new(),
            send_recoverable: false,
            is_own: false,
            media_mimetype: String::new(),
            media_size_bytes: 0,
            media_blurhash: String::new(),
            media_preview_width: 0,
            media_preview_height: 0,
            audio_duration_ms: 0,
            audio_waveform: vec![],
            in_reply_to_event_id: String::new(),
            in_reply_to_sender: String::new(),
            in_reply_to_preview: String::new(),
            in_reply_to_room_msg_kind: RoomMessageKind::Other,
            in_reply_to_media_mimetype: String::new(),
            in_reply_to_media_size_bytes: 0,
            in_reply_to_media_blurhash: String::new(),
            in_reply_to_media_preview_width: 0,
            in_reply_to_media_preview_height: 0,
            in_reply_to_parent_redacted: false,
            reactions: vec![],
            poll_options_json: String::new(),
            poll_state_json: String::new(),
            link_previews_json: "[]".to_string(),
            is_redacted: false,
            read_receipt_count: 0,
            read_receipt_latest_timestamp_ms: 0,
        }
    }

    #[test]
    fn preview_skips_empty_other_kind_tail() {
        let list = vec![
            sample(RoomMessageKind::Text, "hi"),
            sample(RoomMessageKind::Other, ""),
        ];
        let last = last_message_row_for_room_preview(&list);
        assert_eq!(last.map(|m| m.content), Some("hi".to_string()));
    }

    #[test]
    fn preview_keeps_redacted_other() {
        let mut m = sample(RoomMessageKind::Other, "");
        m.is_redacted = true;
        let list = vec![m];
        assert!(last_message_row_for_room_preview(&list).is_some());
    }

    #[test]
    fn preview_prefers_matrix_call_row() {
        let list = vec![
            sample(RoomMessageKind::Text, "hi"),
            sample(RoomMessageKind::Call, "Incoming call"),
        ];
        let last = last_message_row_for_room_preview(&list);
        assert_eq!(last.map(|m| m.content), Some("Incoming call".to_string()));
    }
}

#[cfg(test)]
mod incoming_call_timeline_tests {
    use super::*;
    use crate::matrix::sync_notifications::RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS;
    use std::collections::HashSet;

    fn base_message() -> Message {
        Message {
            event_id: "$rtc1:example.org".to_string(),
            transaction_id: String::new(),
            sender: "Alice".to_string(),
            sender_user_id: "@alice:example.org".to_string(),
            sender_avatar_mxc: String::new(),
            content: "Incoming call".to_string(),
            timestamp: 1,
            message_type: MessageType::Message,
            room_msg_kind: RoomMessageKind::Call,
            send_state: EventSendStateKind::Delivered,
            send_error: String::new(),
            send_recoverable: false,
            is_own: false,
            media_mimetype: String::new(),
            media_size_bytes: 0,
            media_blurhash: String::new(),
            media_preview_width: 0,
            media_preview_height: 0,
            audio_duration_ms: 0,
            audio_waveform: vec![],
            in_reply_to_event_id: String::new(),
            in_reply_to_sender: String::new(),
            in_reply_to_preview: String::new(),
            in_reply_to_room_msg_kind: RoomMessageKind::Other,
            in_reply_to_media_mimetype: String::new(),
            in_reply_to_media_size_bytes: 0,
            in_reply_to_media_blurhash: String::new(),
            in_reply_to_media_preview_width: 0,
            in_reply_to_media_preview_height: 0,
            in_reply_to_parent_redacted: false,
            reactions: vec![],
            poll_options_json: String::new(),
            poll_state_json: String::new(),
            link_previews_json: "[]".to_string(),
            is_redacted: false,
            read_receipt_count: 0,
            read_receipt_latest_timestamp_ms: 0,
        }
    }

    #[test]
    fn peer_incoming_call_ring_matches_sliding_sync_row() {
        assert!(timeline_message_is_peer_incoming_call_ring(&base_message()));
    }

    #[test]
    fn own_call_row_is_not_incoming_ring() {
        let mut m = base_message();
        m.is_own = true;
        assert!(!timeline_message_is_peer_incoming_call_ring(&m));
    }

    #[test]
    fn silent_call_body_is_not_ring() {
        let mut m = base_message();
        m.content = "Call".to_string();
        assert!(!timeline_message_is_peer_incoming_call_ring(&m));
    }

    #[test]
    fn empty_event_id_is_not_ring() {
        let mut m = base_message();
        m.event_id = String::new();
        assert!(!timeline_message_is_peer_incoming_call_ring(&m));
    }

    #[test]
    fn rtc_ring_older_than_window_is_stale_for_notify() {
        let now_ms: u64 = 1_700_000_000_000;
        let mut m = base_message();
        m.timestamp = now_ms.saturating_sub(RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS + 1);
        let stale = m.timestamp == 0
            || now_ms.saturating_sub(m.timestamp) > RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS;
        assert!(stale);
    }

    #[test]
    fn rtc_ring_inside_window_is_fresh_for_notify() {
        let now_ms: u64 = 1_700_000_000_000;
        let mut m = base_message();
        m.timestamp = now_ms.saturating_sub(1_000);
        let stale = m.timestamp == 0
            || now_ms.saturating_sub(m.timestamp) > RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS;
        assert!(!stale);
    }

    /// Mirrors the timeline-list loop: only rows whose event id was **not** in the previous cache
    /// should be considered for RTC notify (avoids ringing on history replay).
    #[test]
    fn only_new_event_ids_would_emit_rtc_path() {
        let prev: HashSet<String> = HashSet::from([base_message().event_id.clone()]);
        let m = base_message();
        let eid = m.event_id.trim();
        let is_new = !eid.is_empty() && !prev.contains(eid);
        assert!(!is_new);

        let mut m2 = m.clone();
        m2.event_id = "$newevt:example.org".to_string();
        let e2 = m2.event_id.trim();
        assert!(timeline_message_is_peer_incoming_call_ring(&m2));
        assert!(!prev.contains(e2));
    }
}

/// Send read receipts for the latest timeline event (public + private) so other clients
/// (e.g. Element in encrypted rooms) and our own read-marker state stay aligned.
pub(crate) async fn mark_timeline_as_read(timeline: &SdkTimeline) -> Result<bool, String> {
    use matrix_sdk::ruma::api::client::receipt::create_receipt::v3::ReceiptType;
    let mut any = timeline
        .mark_as_read(ReceiptType::Read)
        .await
        .map_err(|e| e.to_string())?;
    match timeline.mark_as_read(ReceiptType::ReadPrivate).await {
        Ok(v) => any |= v,
        Err(e) => tracing::debug!(error = %e, "optional ReadPrivate receipt skipped"),
    }
    Ok(any)
}

/// Clone the shared UI timeline for a room (same instance as the sync listen_task).
pub(crate) fn clone_timeline_arc(
    timelines: &Timelines,
    room_id: &OwnedRoomId,
) -> Option<Arc<SdkTimeline>> {
    let guard = timelines.lock().ok()?;
    guard.get(room_id).map(|t| t.timeline.clone())
}

/// Current messages from the sync-owned item vector (no extra SDK timeline).
pub(crate) fn get_timeline_items_from_timelines_map(
    timelines: &Timelines,
    room_id: &str,
    own_user_id: Option<&str>,
) -> Option<Vec<Message>> {
    let room_id: OwnedRoomId = room_id.parse().ok()?;
    let guard = timelines.lock().ok()?;
    let t = guard.get(&room_id)?;
    let items = t.items.lock().ok()?;
    Some(
        items
            .iter()
            .map(|v| get_message_from_timeline_item(v.as_ref(), own_user_id))
            .collect(),
    )
}

/// Snapshot from the shared UI timeline (same underlying object as sync).
pub(crate) async fn messages_from_sdk_timeline(
    timeline: &SdkTimeline,
    own_user_id: Option<&str>,
) -> Vec<Message> {
    let items = timeline.items().await;
    items
        .iter()
        .map(|item| get_message_from_timeline_item(item.as_ref(), own_user_id))
        .collect()
}

/// Local echoes only expose [Message::transaction_id]; the remote echo has [Message::event_id] and
/// empty txn in our bridge — matching uses content/time, not ids — so the UI can briefly show
/// duplicates (pending spinner + delivered). Drop stale pending rows when a matching delivered
/// echo exists.
fn ts_millis_near(a: u64, b: u64, max_delta_ms: u64) -> bool {
    if a > b {
        a - b <= max_delta_ms
    } else {
        b - a <= max_delta_ms
    }
}

fn dedupe_stale_local_echoes(vec: &mut Vec<Message>) {
    let mut i = 0;
    while i < vec.len() {
        let stale_pending = {
            let m = &vec[i];
            m.is_own && matches!(m.send_state, EventSendStateKind::Pending)
        };
        if stale_pending {
            let pending = &vec[i];
            let has_delivered_twin = vec.iter().enumerate().any(|(j, other)| {
                j != i
                    && other.is_own
                    && matches!(other.send_state, EventSendStateKind::Delivered)
                    && other.content == pending.content
                    && other.in_reply_to_event_id == pending.in_reply_to_event_id
                    && other.sender == pending.sender
                    && other.room_msg_kind == pending.room_msg_kind
                    && ts_millis_near(pending.timestamp, other.timestamp, 300_000)
            });
            if has_delivered_twin {
                vec.remove(i);
                continue;
            }
        }
        i += 1;
    }
}

/// Timeline items for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub(crate) async fn get_timeline_items_by_room_id(
    client: &Client,
    room_id: String,
) -> Vec<Message> {
    let mut messages = Vec::new();
    let room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return messages;
        }
    };

    let room_id_ref = room_id.as_ref();
    let room = match client.get_room(room_id_ref) {
        Some(room) => room,
        None => {
            error!("Room not found");
            return messages;
        }
    };

    let timeline = match room.timeline().await {
        Ok(timeline) => timeline,
        Err(e) => {
            error!("Failed to get timeline: {}", e);
            return messages;
        }
    };

    let own = client.user_id().map(|u| u.to_string());
    let own_ref = own.as_deref();
    let items = timeline.items().await;

    for item in items.iter() {
        messages.push(get_message_from_timeline_item(item, own_ref));
    }
    messages
}

/// Subscribe to timeline updates for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub async fn subscribe_to_timeline_updates(
    client: &Client,
    stream: StreamSink<MessageUpdate>,
    room_id: String,
    shared_timeline: Option<Arc<SdkTimeline>>,
) {
    let room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return;
        }
    };

    let room_id_ref = room_id.as_ref();
    let room = match client.get_room(room_id_ref) {
        Some(room) => room,
        None => {
            error!("Room not found");
            return;
        }
    };

    let timeline: Arc<SdkTimeline> = if let Some(t) = shared_timeline {
        t
    } else {
        let timeline = room
            .timeline_builder()
            .track_read_marker_and_receipts(TimelineReadReceiptTracking::MessageLikeEvents)
            .with_focus(TimelineFocus::Live {
                hide_threaded_events: true,
            })
            .build()
            .await;

        let timeline = match timeline {
            Ok(timeline) => timeline,
            Err(e) => {
                error!("Failed to build timeline: {}", e);
                return;
            }
        };
        Arc::new(timeline)
    };

    let (_events, mut diff_stream) = timeline.subscribe().await;
    let own = client.user_id().map(|u| u.to_string());
    let own_ref = own.as_deref();

    // Send initial heartbeat to confirm connection
    let _ = stream.add(MessageUpdate {
        message_update_type: MessageUpdateType::TimelineStart,
        messages: None,
        index: MESSAGE_UPDATE_NONE_INDEX,
        length: MESSAGE_UPDATE_NONE_INDEX,
    });

    // Create a heartbeat timer
    let mut heartbeat_interval = tokio::time::interval(tokio::time::Duration::from_secs(30));

    loop {
        tokio::select! {
            // Handle timeline updates
            diffs = diff_stream.next() => {
                match diffs {
                    Some(diffs) => {
                        for diff in diffs {
                            debug!("Timeline diff: {:?}", diff);
                            match diff {
                                matrix_sdk_ui::eyeball_im::VectorDiff::Append { values } => {
                                    let mut messages = Vec::new();
                                    for value in values {
                                        let message =
                                            get_message_from_timeline_item(&value, own_ref);
                                        messages.push(message);
                                    }
                                    let _ = stream.add(MessageUpdate {
                                        messages: Some(messages),
                                        message_update_type: MessageUpdateType::Append,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Clear => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Clear,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PushFront { value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PushFront,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PushBack { value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PushBack,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PopFront => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PopFront,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::PopBack => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::PopBack,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Insert { index, value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);

                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Insert,
                                        messages: Some(messages),
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Set { index, value } => {
                                    let mut messages = Vec::new();
                                    let message =
                                        get_message_from_timeline_item(&value, own_ref);
                                    messages.push(message);

                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Set,
                                        messages: Some(messages),
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Remove { index } => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Remove,
                                        messages: None,
                                        index,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Truncate { length } => {
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Truncate,
                                        messages: None,
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length,
                                    });
                                }
                                matrix_sdk_ui::eyeball_im::VectorDiff::Reset { values } => {
                                    let mut messages = Vec::new();
                                    for value in values {
                                        let message =
                                            get_message_from_timeline_item(&value, own_ref);
                                        messages.push(message);
                                    }
                                    let _ = stream.add(MessageUpdate {
                                        message_update_type: MessageUpdateType::Reset,
                                        messages: Some(messages),
                                        index: MESSAGE_UPDATE_NONE_INDEX,
                                        length: MESSAGE_UPDATE_NONE_INDEX,
                                    });
                                }
                            }
                        }
                    }
                    None => {
                        debug!("Timeline stream ended, exiting subscription loop");
                        break;
                    }
                }
            }

            // Handle heartbeat
            _ = heartbeat_interval.tick() => {
                // Send a heartbeat to keep the connection alive
                let _ = stream.add(MessageUpdate {
                    message_update_type: MessageUpdateType::ReadMarker, // Use ReadMarker as heartbeat
                    messages: None,
                    index: MESSAGE_UPDATE_NONE_INDEX,
                    length: MESSAGE_UPDATE_NONE_INDEX,
                });
                debug!("Timeline heartbeat sent");
            }
        }
    }

    debug!("Timeline subscription ended for room {}", room_id);
}

/// Paginate and read items from a UI timeline (shared or ad hoc).
pub(crate) async fn get_older_messages_for_timeline(
    timeline: &SdkTimeline,
    count: u16,
    own_user_id: Option<&str>,
) -> Result<Vec<Message>, String> {
    timeline
        .paginate_backwards(count)
        .await
        .map_err(|e| format!("Failed to paginate backwards: {}", e))?;

    let items = timeline.items().await;
    Ok(items
        .iter()
        .map(|item| get_message_from_timeline_item(item.as_ref(), own_user_id))
        .collect())
}

/// Older messages for the given app (used by [crate::api::matrix_client::MatrixClient]).
pub async fn get_older_messages(
    client: &Client,
    room_id: String,
    count: u16,
) -> Result<Vec<Message>, String> {
    let owned_room_id: OwnedRoomId = match room_id.parse() {
        Ok(id) => id,
        Err(_) => {
            error!("Failed to parse room ID");
            return Err("Failed to parse room ID".to_string());
        }
    };

    let room_id_ref = owned_room_id.as_ref();
    let room = client
        .get_room(room_id_ref)
        .ok_or_else(|| "Room not found".to_string())?;
    let timeline = room
        .timeline()
        .await
        .map_err(|e| format!("Failed to get timeline: {}", e))?;

    let own = client.user_id().map(|u| u.to_string());
    get_older_messages_for_timeline(&timeline, count, own.as_deref()).await
}

// pub(crate) async fn send_message(
//     client: &Client,
//     room_id: String,
//     content: String,
// ) -> Result<SendMessageResult, String> {
//     let room_id_parsed = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
//     let room = client.get_room(&room_id_parsed).ok_or("Room not found")?;
//     let sender = client.user_id().ok_or("Not logged in")?.to_string();

//     let result = room
//         .send(
//             matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_plain(&content),
//         )
//         .await
//         .map_err(|e| e.to_string())?;

//     let event_id = result.response.event_id.to_string();
//     let timestamp_ms = std::time::SystemTime::now()
//         .duration_since(std::time::UNIX_EPOCH)
//         .map(|d| d.as_millis() as u64)
//         .unwrap_or(0);

//     let mut room_update = get_room_update_data(&room).await;
//     room_update.message = Some(Message {
//         event_id: event_id.clone(),
//         sender,
//         content: content.clone(),
//         timestamp: timestamp_ms,
//         message_type: MessageType::Message,
//     });

//     Ok(SendMessageResult {
//         event_id,
//         room_update,
//     })
// }

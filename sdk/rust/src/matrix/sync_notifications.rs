//! Push-rule-driven sync notifications forwarded to Dart via FRB streams.

use std::time::{SystemTime, UNIX_EPOCH};

/// Ignore MatrixRTC `ring` rows older than this when turning timeline history into CallKit/UI rings.
///
/// Without this, opening a room (initial pagination / cache fill) replays every past
/// `m.rtc.notification` ring in the loaded window as a new incoming call.
pub const RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS: u64 = 120_000;

fn now_ms_since_epoch() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

/// True when a server `origin_server_ts` is too old to still be an active ring.
pub(crate) fn rtc_ring_event_is_stale(origin_server_ts_ms: u64) -> bool {
    origin_server_ts_ms == 0
        || now_ms_since_epoch().saturating_sub(origin_server_ts_ms)
            > RTC_INCOMING_RING_NOTIFY_MAX_AGE_MS
}

use matrix_sdk::{
    deserialized_responses::RawAnySyncOrStrippedTimelineEvent,
    ruma::events::{
        rtc::notification::{NotificationType, RtcNotificationEventContent},
        AnySyncTimelineEvent, OriginalSyncMessageLikeEvent,
    },
    Room,
};
use matrix_sdk_base::sync::Notification;
use ruma::events::AnyMessageLikeEventContent;

use super::client::format_user_id_for_display;

/// Kind of Matrix event that produced the notification.
#[derive(Clone, Debug)]
pub enum SyncNotificationKind {
    Message,
    Invite,
    /// MatrixRTC / Element Call `m.rtc.notification` (incoming call UI).
    IncomingCall,
    Other,
}

/// Summary of a sync notification for local/system UI (titles, dedupe).
#[derive(Clone, Debug)]
pub struct SyncNotificationSummary {
    pub room_id: String,
    pub room_display_name: Option<String>,
    pub kind: SyncNotificationKind,
    pub sender_id: String,
    pub sender_display_name: Option<String>,
    pub body_preview: String,
    pub is_highlight: bool,
    pub is_noisy: bool,
    pub event_id: String,
    /// `true` when the RTC notification requests ringing (vs silent banner).
    pub incoming_call_ring: bool,
    /// Matrix `origin_server_ts` in milliseconds since epoch; `0` when unknown (e.g. stripped invite).
    pub origin_server_ts_ms: u64,
}

/// Incoming ring from a synced timeline event (not push-rule filtered).
///
/// Matrix push rules often omit `m.rtc.notification`; this path still drives CallKit when sync runs.
pub(crate) async fn summary_from_sync_rtc_notification(
    ev: &OriginalSyncMessageLikeEvent<RtcNotificationEventContent>,
    room: &Room,
) -> Option<SyncNotificationSummary> {
    let room_id = room.room_id().to_string();
    let room_display_name = room.cached_display_name().map(|n| n.to_string());
    let sender = ev.sender.to_string();
    let sender_display_name = room
        .get_member_no_sync(&ev.sender)
        .await
        .ok()
        .flatten()
        .and_then(|m| m.display_name().map(|s| s.to_owned()));

    let c = &ev.content;
    let requested_ring = matches!(c.notification_type, NotificationType::Ring);
    let ts_ms: u64 = ev.origin_server_ts.get().into();
    let stale = requested_ring && rtc_ring_event_is_stale(ts_ms);
    let incoming_call_ring = requested_ring && !stale;
    let body_preview = if requested_ring {
        if stale {
            "Missed call".to_owned()
        } else {
            "Incoming call".to_owned()
        }
    } else {
        "Call".to_owned()
    };
    let event_id = ev.event_id.to_string();

    Some(SyncNotificationSummary {
        room_id,
        room_display_name,
        kind: SyncNotificationKind::IncomingCall,
        sender_id: format_user_id_for_display(&sender),
        sender_display_name: sender_display_name.map(|s| format_user_id_for_display(&s)),
        body_preview,
        is_highlight: true,
        is_noisy: incoming_call_ring,
        event_id,
        incoming_call_ring,
        origin_server_ts_ms: ts_ms,
    })
}

pub(crate) async fn summary_from_notification(
    notification: Notification,
    room: Room,
) -> Option<SyncNotificationSummary> {
    let room_id = room.room_id().to_string();
    let room_display_name = room.cached_display_name().map(|n| n.to_string());
    let is_highlight = notification.actions.iter().any(|a| a.is_highlight());
    let is_noisy = notification.actions.iter().any(|a| a.sound().is_some());

    match notification.event {
        RawAnySyncOrStrippedTimelineEvent::Sync(raw) => {
            let ev = raw.deserialize().ok()?;
            let sender = ev.sender().to_string();
            let sender_display_name = room
                .get_member_no_sync(ev.sender())
                .await
                .ok()
                .flatten()
                .and_then(|m| m.display_name().map(|s| s.to_owned()));

            let (kind, body_preview, event_id, incoming_call_ring, origin_server_ts_ms) =
                match &ev {
                AnySyncTimelineEvent::MessageLike(ml) => {
                    let eid = ml.event_id().to_string();
                    let ts_ms: u64 = ml.origin_server_ts().get().into();
                    if let Some(AnyMessageLikeEventContent::RtcNotification(c)) =
                        ml.original_content()
                    {
                        let requested_ring = matches!(c.notification_type, NotificationType::Ring);
                        let stale = requested_ring && rtc_ring_event_is_stale(ts_ms);
                        let incoming_call_ring = requested_ring && !stale;
                        let body = if requested_ring {
                            if stale {
                                "Missed call".to_owned()
                            } else {
                                "Incoming call".to_owned()
                            }
                        } else {
                            "Call".to_owned()
                        };
                        (
                            SyncNotificationKind::IncomingCall,
                            body,
                            eid,
                            incoming_call_ring,
                            ts_ms,
                        )
                    } else {
                        let body = ml
                            .original_content()
                            .and_then(|c| match c {
                                AnyMessageLikeEventContent::RoomMessage(msg) => {
                                    Some(msg.body().to_owned())
                                }
                                _ => None,
                            })
                            .unwrap_or_else(|| "New message".to_owned());
                        (SyncNotificationKind::Message, body, eid, false, ts_ms)
                    }
                }
                _ => (
                    SyncNotificationKind::Other,
                    "New activity".to_owned(),
                    ev.event_id().to_string(),
                    false,
                    ev.origin_server_ts().get().into(),
                ),
            };

            let is_noisy_out = if matches!(kind, SyncNotificationKind::IncomingCall) {
                incoming_call_ring
            } else {
                is_noisy
            };

            Some(SyncNotificationSummary {
                room_id,
                room_display_name,
                kind,
                sender_id: format_user_id_for_display(&sender),
                sender_display_name: sender_display_name
                    .map(|s| format_user_id_for_display(&s)),
                body_preview,
                is_highlight,
                is_noisy: is_noisy_out,
                event_id,
                incoming_call_ring,
                origin_server_ts_ms,
            })
        }
        RawAnySyncOrStrippedTimelineEvent::Stripped(raw) => {
            let ev = raw.deserialize().ok()?;
            let sender = ev.sender().to_string();
            let sender_display_name = room
                .get_member_no_sync(ev.sender())
                .await
                .ok()
                .flatten()
                .and_then(|m| m.display_name().map(|s| s.to_owned()));
            Some(SyncNotificationSummary {
                room_id,
                room_display_name,
                kind: SyncNotificationKind::Invite,
                sender_id: format_user_id_for_display(&sender),
                sender_display_name: sender_display_name
                    .map(|s| format_user_id_for_display(&s)),
                body_preview: "Room invite".to_owned(),
                is_highlight,
                is_noisy,
                event_id: String::new(),
                incoming_call_ring: false,
                origin_server_ts_ms: 0,
            })
        }
    }
}

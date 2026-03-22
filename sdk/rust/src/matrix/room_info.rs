//! Room details, member list (groups), file index from timeline, and moderation helpers.

use std::collections::HashSet;

use flutter_rust_bridge::frb;
use matrix_sdk::deserialized_responses::TimelineEvent;
use matrix_sdk::ruma::events::{
    room::message::MessageType, AnySyncMessageLikeEvent, AnySyncTimelineEvent,
};
use matrix_sdk::ruma::{
    events::room::power_levels::UserPowerLevel, int, Int, RoomId, UInt, UserId,
};
use matrix_sdk::{Client, RoomMemberships};
use matrix_sdk::room::RoomMemberRole;
use matrix_sdk_base::event_cache::store::EventCacheStoreLockState;
use matrix_sdk_common::linked_chunk::{ChunkContent, LinkedChunkId};
use serde::{Deserialize, Serialize};
use serde_json::json;

use crate::matrix::client::format_user_id_for_display;
use crate::matrix::timelines::RoomMessageKind;

/// Role derived from power levels (creator / admin / moderator / user).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum RoomMemberRoleDto {
    Creator,
    Administrator,
    Moderator,
    User,
}

impl From<RoomMemberRole> for RoomMemberRoleDto {
    fn from(r: RoomMemberRole) -> Self {
        match r {
            RoomMemberRole::Creator => Self::Creator,
            RoomMemberRole::Administrator => Self::Administrator,
            RoomMemberRole::Moderator => Self::Moderator,
            RoomMemberRole::User => Self::User,
        }
    }
}

/// One joined member row for the room info screen.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct RoomMemberRow {
    pub user_id: String,
    /// `user_id` formatted for labels; `user_id` stays canonical for kick / power APIs.
    pub user_id_display: String,
    pub display_name: String,
    /// Power level as integer (101 = creator / infinite).
    pub power_level: i64,
    pub role: RoomMemberRoleDto,
    pub is_self: bool,
    /// Whether the **current** user may kick this member (server rules: own power ≥ kick, own > target).
    pub current_user_can_kick: bool,
}

/// Summary for the room info / settings UI.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct RoomDetails {
    pub room_id: String,
    pub display_name: String,
    pub topic: String,
    pub is_direct: bool,
    pub is_encrypted: bool,
    pub member_count: u32,
    pub members: Vec<RoomMemberRow>,
    pub current_user_id: String,
    pub current_user_is_admin: bool,
    pub current_user_is_moderator: bool,
}

/// Filter for file rows from the cached timeline.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum RoomFileFilter {
    All,
    Received,
    Sent,
}

/// One `m.room.message` attachment row from the event cache DB (file / image / video / audio).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct RoomFileItem {
    pub event_id: String,
    pub transaction_id: String,
    pub sender: String,
    pub caption: String,
    pub timestamp: u64,
    pub kind: RoomMessageKind,
    /// True if [sender] is the logged-in user.
    pub is_outgoing: bool,
    /// File size in bytes from event `info.size`; `0` if unknown (e.g. missing or encrypted stub).
    pub size_bytes: u64,
}

/// Text message row with at least one HTTP(S) URL; optional MSC4095 previews in [link_previews_json].
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct RoomLinkItem {
    pub event_id: String,
    pub transaction_id: String,
    pub sender: String,
    pub body: String,
    pub timestamp: u64,
    pub is_outgoing: bool,
    /// JSON array (`com.beeper.linkpreviews` / `m.url_previews` shape); `"[]"` when absent.
    pub link_previews_json: String,
    /// `true` when the sender bundled link previews (MSC4095) on this event.
    pub is_link_message: bool,
}

/// One `org.matrix.msc3381.poll.start` row from the event cache (group room index).
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb]
pub struct RoomPollItem {
    pub event_id: String,
    pub transaction_id: String,
    pub sender: String,
    pub question: String,
    pub timestamp: u64,
    pub is_outgoing: bool,
}

fn user_power_to_i64(p: UserPowerLevel) -> i64 {
    match p {
        UserPowerLevel::Infinite => 101,
        UserPowerLevel::Int(v) => v.into(),
        _ => 0,
    }
}

fn current_user_can_kick_target(
    own: UserPowerLevel,
    target: UserPowerLevel,
    kick_threshold: i64,
    target_is_self: bool,
) -> bool {
    if target_is_self {
        return false;
    }
    let own_i = user_power_to_i64(own);
    let tgt_i = user_power_to_i64(target);
    own_i >= kick_threshold && own_i > tgt_i
}

/// Load room metadata and joined members (members list is empty for DMs).
pub async fn fetch_room_details(client: &Client, room_id: String) -> Result<RoomDetails, String> {
    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&rid).ok_or_else(|| "Room not found".to_string())?;

    let own_uid = client.user_id().ok_or_else(|| "Not logged in".to_string())?;
    let own_id = own_uid.to_string();

    let is_direct = room.is_direct().await.unwrap_or(false);
    let topic = room.topic().unwrap_or_default();
    let display_name_raw = room
        .cached_display_name()
        .map(|s| s.to_string())
        .or_else(|| room.name().map(|n| n.to_string()))
        .unwrap_or_default();
    let display_name = format_user_id_for_display(&display_name_raw);

    let is_encrypted = room
        .latest_encryption_state()
        .await
        .map(|s| s.is_encrypted())
        .unwrap_or(false);

    let power_levels = room.power_levels().await.ok();
    let kick_threshold: i64 = power_levels
        .as_ref()
        .map(|pl| pl.kick.into())
        .unwrap_or(50);

    let own_power = room
        .get_user_power_level(own_uid)
        .await
        .unwrap_or(UserPowerLevel::Int(int!(0)));
    let current_user_is_admin = matches!(
        RoomMemberRole::suggested_role_for_power_level(own_power),
        RoomMemberRole::Administrator | RoomMemberRole::Creator
    );
    let current_user_is_moderator = matches!(
        RoomMemberRole::suggested_role_for_power_level(own_power),
        RoomMemberRole::Moderator | RoomMemberRole::Administrator | RoomMemberRole::Creator
    );

    let mut members = Vec::new();

    let member_count: u32 = if !is_direct {
        let joined = room
            .members(RoomMemberships::JOIN)
            .await
            .map_err(|e| e.to_string())?;
        let member_count = joined.len() as u32;

        let mut rows: Vec<(RoomMemberRow, String)> = Vec::new();
        for m in joined {
            let uid = m.user_id().to_string();
            let is_self = m.is_account_user();
            let display_name_raw = m
                .display_name()
                .map(|s| s.to_owned())
                .unwrap_or_else(|| uid.clone());
            let role = RoomMemberRoleDto::from(m.suggested_role_for_power_level());
            let pl = m.power_level();
            let power_level = user_power_to_i64(pl);
            let can_kick = current_user_can_kick_target(own_power, pl, kick_threshold, is_self);
            let uid_display = format_user_id_for_display(&uid);
            rows.push((
                RoomMemberRow {
                    user_id: uid,
                    user_id_display: uid_display,
                    display_name: display_name_raw.clone(),
                    power_level,
                    role,
                    is_self,
                    current_user_can_kick: can_kick,
                },
                display_name_raw,
            ));
        }

        rows.sort_by(|(a, ar), (b, br)| {
            let rank = |r: &RoomMemberRow| match r.role {
                RoomMemberRoleDto::Creator => 0,
                RoomMemberRoleDto::Administrator => 1,
                RoomMemberRoleDto::Moderator => 2,
                RoomMemberRoleDto::User => 3,
            };
            rank(a)
                .cmp(&rank(b))
                .then_with(|| ar.to_lowercase().cmp(&br.to_lowercase()))
        });
        members = rows
            .into_iter()
            .map(|(mut row, raw)| {
                row.display_name = format_user_id_for_display(&raw);
                row
            })
            .collect();
        member_count
    } else {
        // DM: still report member count when joined list is available.
        room.members(RoomMemberships::JOIN)
            .await
            .map(|v| v.len() as u32)
            .unwrap_or(0)
    };

    Ok(RoomDetails {
        room_id: room_id.clone(),
        display_name,
        topic,
        is_direct,
        is_encrypted,
        member_count,
        members,
        current_user_id: format_user_id_for_display(&own_id),
        current_user_is_admin,
        current_user_is_moderator,
    })
}

/// Parse a persisted timeline [`TimelineEvent`] as `m.room.message` with a media attachment
/// (`m.file`, `m.image`, `m.video`, `m.audio`). Text-only messages are skipped.
fn optional_info_size(opt: Option<UInt>) -> u64 {
    opt.map(Into::into).unwrap_or(0)
}

fn timeline_event_to_file_item(ev: &TimelineEvent, own_id: &str) -> Option<RoomFileItem> {
    let raw = ev.kind.raw();
    let Ok(AnySyncTimelineEvent::MessageLike(msg_like)) = raw.deserialize() else {
        return None;
    };
    let AnySyncMessageLikeEvent::RoomMessage(room_msg) = msg_like else {
        return None;
    };
    let orig = room_msg.as_original()?;

    let (caption, kind, size_bytes) = match &orig.content.msgtype {
        MessageType::File(f) => {
            let sz = optional_info_size(f.info.as_ref().and_then(|i| i.size));
            (
                f.filename
                    .clone()
                    .unwrap_or_else(|| f.body.clone()),
                RoomMessageKind::File,
                sz,
            )
        }
        MessageType::Image(i) => {
            let sz = optional_info_size(i.info.as_ref().and_then(|info| info.size));
            (
                i.filename
                    .clone()
                    .unwrap_or_else(|| i.body.clone()),
                RoomMessageKind::Image,
                sz,
            )
        }
        MessageType::Video(v) => {
            let sz = optional_info_size(v.info.as_ref().and_then(|info| info.size));
            (
                v.filename
                    .clone()
                    .unwrap_or_else(|| v.body.clone()),
                RoomMessageKind::Video,
                sz,
            )
        }
        MessageType::Audio(a) => {
            let sz = optional_info_size(a.info.as_ref().and_then(|info| info.size));
            (
                a.filename
                    .clone()
                    .unwrap_or_else(|| a.body.clone()),
                RoomMessageKind::Audio,
                sz,
            )
        }
        _ => return None,
    };

    let event_id = orig.event_id.to_string();

    let transaction_id = orig
        .unsigned
        .transaction_id
        .as_ref()
        .map(|t| t.to_string())
        .unwrap_or_default();

    let sender_raw = orig.sender.to_string();
    let is_outgoing = sender_raw == own_id;

    let timestamp = ev
        .timestamp
        .map(|t| u64::from(t.0))
        .unwrap_or(0);

    Some(RoomFileItem {
        event_id,
        transaction_id,
        sender: format_user_id_for_display(&sender_raw),
        caption,
        timestamp,
        kind,
        is_outgoing,
        size_bytes,
    })
}

/// All `m.room.message` attachment events (`m.file`, `m.image`, `m.video`, `m.audio`) from the event cache store.
///
/// The UI timeline is persisted in **linked chunks** (`linked_chunks` / `event_chunks` tables).
/// The separate flat `events` table (used by [`EventCacheStore::get_room_events`]) is often empty,
/// so we read timeline rows via [`EventCacheStore::load_all_chunks`]\(`LinkedChunkId::Room`\)
/// and also merge any `m.room.message` rows from `get_room_events` for completeness.
pub async fn list_room_files_from_event_cache(
    client: &Client,
    room_id: String,
    filter: RoomFileFilter,
) -> Result<Vec<RoomFileItem>, String> {
    let own_id = client
        .user_id()
        .ok_or_else(|| "Not logged in".to_string())?
        .as_str()
        .to_owned();

    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room_id_ref: &RoomId = rid.as_ref();

    let lock_state = client
        .event_cache_store()
        .lock()
        .await
        .map_err(|e| e.to_string())?;

    let guard = match lock_state {
        EventCacheStoreLockState::Clean(g) | EventCacheStoreLockState::Dirty(g) => g,
    };

    let mut seen_ids: HashSet<String> = HashSet::new();
    let mut out: Vec<RoomFileItem> = Vec::new();

    let chunks = guard
        .load_all_chunks(LinkedChunkId::Room(room_id_ref))
        .await
        .map_err(|e| e.to_string())?;

    for chunk in chunks {
        let items = match chunk.content {
            ChunkContent::Items(items) => items,
            ChunkContent::Gap(_) => continue,
        };
        for ev in items {
            push_file_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
        }
    }

    let flat = guard
        .get_room_events(room_id_ref, Some("m.room.message"), None)
        .await
        .map_err(|e| e.to_string())?;
    for ev in flat {
        push_file_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
    }

    match filter {
        RoomFileFilter::All => {}
        RoomFileFilter::Received => out.retain(|f| !f.is_outgoing),
        RoomFileFilter::Sent => out.retain(|f| f.is_outgoing),
    }

    out.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    Ok(out)
}

fn push_file_item_if_new(
    out: &mut Vec<RoomFileItem>,
    seen_ids: &mut HashSet<String>,
    ev: &TimelineEvent,
    own_id: &str,
) {
    let Some(item) = timeline_event_to_file_item(ev, own_id) else {
        return;
    };
    if !item.event_id.is_empty() {
        if !seen_ids.insert(item.event_id.clone()) {
            return;
        }
    }
    out.push(item);
}

const UNSTABLE_POLL_START_EVENT_TYPE: &str = "org.matrix.msc3381.poll.start";

fn timeline_event_to_poll_item(ev: &TimelineEvent, own_id: &str) -> Option<RoomPollItem> {
    if ev.kind.is_utd() {
        return None;
    }
    let raw = ev.kind.raw();
    let Ok(AnySyncTimelineEvent::MessageLike(msg_like)) = raw.deserialize() else {
        return None;
    };
    let AnySyncMessageLikeEvent::UnstablePollStart(poll_ev) = msg_like else {
        return None;
    };
    let orig = poll_ev.as_original()?;
    let block = orig.content.poll_start();
    let question = block.question.text.clone();
    let event_id = orig.event_id.to_string();
    let transaction_id = orig
        .unsigned
        .transaction_id
        .as_ref()
        .map(|t| t.to_string())
        .unwrap_or_default();
    let sender_raw = orig.sender.to_string();
    let is_outgoing = sender_raw == own_id;
    let timestamp = ev
        .timestamp
        .map(|t| u64::from(t.0))
        .unwrap_or(0);
    Some(RoomPollItem {
        event_id,
        transaction_id,
        sender: format_user_id_for_display(&sender_raw),
        question,
        timestamp,
        is_outgoing,
    })
}

fn push_poll_item_if_new(
    out: &mut Vec<RoomPollItem>,
    seen_ids: &mut HashSet<String>,
    ev: &TimelineEvent,
    own_id: &str,
) {
    let Some(item) = timeline_event_to_poll_item(ev, own_id) else {
        return;
    };
    if !item.event_id.is_empty() {
        if !seen_ids.insert(item.event_id.clone()) {
            return;
        }
    }
    out.push(item);
}

/// Unstable MSC3381 poll start events from the same event-cache sources as [list_room_files_from_event_cache].
pub async fn list_room_polls_from_event_cache(
    client: &Client,
    room_id: String,
    filter: RoomFileFilter,
) -> Result<Vec<RoomPollItem>, String> {
    let own_id = client
        .user_id()
        .ok_or_else(|| "Not logged in".to_string())?
        .as_str()
        .to_owned();

    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room_id_ref: &RoomId = rid.as_ref();

    let lock_state = client
        .event_cache_store()
        .lock()
        .await
        .map_err(|e| e.to_string())?;

    let guard = match lock_state {
        EventCacheStoreLockState::Clean(g) | EventCacheStoreLockState::Dirty(g) => g,
    };

    let mut seen_ids: HashSet<String> = HashSet::new();
    let mut out: Vec<RoomPollItem> = Vec::new();

    let chunks = guard
        .load_all_chunks(LinkedChunkId::Room(room_id_ref))
        .await
        .map_err(|e| e.to_string())?;

    for chunk in chunks {
        let items = match chunk.content {
            ChunkContent::Items(items) => items,
            ChunkContent::Gap(_) => continue,
        };
        for ev in items {
            push_poll_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
        }
    }

    let flat = guard
        .get_room_events(
            room_id_ref,
            Some(UNSTABLE_POLL_START_EVENT_TYPE),
            None,
        )
        .await
        .map_err(|e| e.to_string())?;
    for ev in flat {
        push_poll_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
    }

    match filter {
        RoomFileFilter::All => {}
        RoomFileFilter::Received => out.retain(|f| !f.is_outgoing),
        RoomFileFilter::Sent => out.retain(|f| f.is_outgoing),
    }

    out.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    Ok(out)
}

fn link_previews_json_from_content(content: &serde_json::Value) -> (String, bool) {
    for key in ["com.beeper.linkpreviews", "m.url_previews"] {
        if let Some(v) = content.get(key) {
            let s = serde_json::to_string(v).unwrap_or_else(|_| "[]".to_string());
            let is_link = v
                .as_array()
                .map(|a| !a.is_empty())
                .unwrap_or(false);
            return (s, is_link);
        }
    }
    (json!([]).to_string(), false)
}

fn body_has_extractable_url(body: &str) -> bool {
    !crate::matrix::link_preview::extract_http_urls(body).is_empty()
}

/// `m.text` / `m.notice` with an HTTP(S) URL in the body (optionally with MSC4095 previews).
fn timeline_event_to_link_item(ev: &TimelineEvent, own_id: &str) -> Option<RoomLinkItem> {
    if ev.kind.is_utd() {
        return None;
    }
    let raw = ev.raw();
    let json_val: serde_json::Value = serde_json::from_str(raw.json().get()).ok()?;
    let content = json_val.get("content")?;
    let msgtype = content.get("msgtype").and_then(|v| v.as_str()).unwrap_or("");
    if msgtype != "m.text" && msgtype != "m.notice" {
        return None;
    }
    let body = content
        .get("body")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();
    if !body_has_extractable_url(&body) {
        return None;
    }
    let (link_previews_json, bundled) = link_previews_json_from_content(content);

    let Ok(AnySyncTimelineEvent::MessageLike(msg_like)) = raw.deserialize() else {
        return None;
    };
    let AnySyncMessageLikeEvent::RoomMessage(room_msg) = msg_like else {
        return None;
    };
    let orig = room_msg.as_original()?;

    let event_id = orig.event_id.to_string();
    let transaction_id = orig
        .unsigned
        .transaction_id
        .as_ref()
        .map(|t| t.to_string())
        .unwrap_or_default();
    let sender_raw = orig.sender.to_string();
    let is_outgoing = sender_raw == own_id;
    let timestamp = ev
        .timestamp
        .map(|t| u64::from(t.0))
        .unwrap_or(0);

    Some(RoomLinkItem {
        event_id,
        transaction_id,
        sender: format_user_id_for_display(&sender_raw),
        body,
        timestamp,
        is_outgoing,
        link_previews_json,
        is_link_message: bundled,
    })
}

fn push_link_item_if_new(
    out: &mut Vec<RoomLinkItem>,
    seen_ids: &mut HashSet<String>,
    ev: &TimelineEvent,
    own_id: &str,
) {
    let Some(item) = timeline_event_to_link_item(ev, own_id) else {
        return;
    };
    if !item.event_id.is_empty() {
        if !seen_ids.insert(item.event_id.clone()) {
            return;
        }
    }
    out.push(item);
}

/// Text messages that contain URLs, from the same event-cache sources as [list_room_files_from_event_cache].
pub async fn list_room_links_from_event_cache(
    client: &Client,
    room_id: String,
    filter: RoomFileFilter,
) -> Result<Vec<RoomLinkItem>, String> {
    let own_id = client
        .user_id()
        .ok_or_else(|| "Not logged in".to_string())?
        .as_str()
        .to_owned();

    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room_id_ref: &RoomId = rid.as_ref();

    let lock_state = client
        .event_cache_store()
        .lock()
        .await
        .map_err(|e| e.to_string())?;

    let guard = match lock_state {
        EventCacheStoreLockState::Clean(g) | EventCacheStoreLockState::Dirty(g) => g,
    };

    let mut seen_ids: HashSet<String> = HashSet::new();
    let mut out: Vec<RoomLinkItem> = Vec::new();

    let chunks = guard
        .load_all_chunks(LinkedChunkId::Room(room_id_ref))
        .await
        .map_err(|e| e.to_string())?;

    for chunk in chunks {
        let items = match chunk.content {
            ChunkContent::Items(items) => items,
            ChunkContent::Gap(_) => continue,
        };
        for ev in items {
            push_link_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
        }
    }

    let flat = guard
        .get_room_events(room_id_ref, Some("m.room.message"), None)
        .await
        .map_err(|e| e.to_string())?;
    for ev in flat {
        push_link_item_if_new(&mut out, &mut seen_ids, &ev, &own_id);
    }

    match filter {
        RoomFileFilter::All => {}
        RoomFileFilter::Received => out.retain(|f| !f.is_outgoing),
        RoomFileFilter::Sent => out.retain(|f| f.is_outgoing),
    }

    out.sort_by(|a, b| b.timestamp.cmp(&a.timestamp));
    Ok(out)
}

pub async fn kick_room_member(
    client: &Client,
    room_id: String,
    user_id: String,
) -> Result<(), String> {
    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&rid).ok_or_else(|| "Room not found".to_string())?;
    let uid = UserId::parse(&user_id).map_err(|e| e.to_string())?;
    room.kick_user(&uid, None).await.map_err(|e| e.to_string())
}

/// Leave, then forget the room locally (removes it from the room list after leave).
pub async fn leave_and_forget_room(client: &Client, room_id: String) -> Result<String, String> {
    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&rid).ok_or_else(|| "Room not found".to_string())?;
    room.leave().await.map_err(|e| e.to_string())?;
    // Re-fetch after state change
    let left = client
        .get_room(&rid)
        .ok_or_else(|| "Room not found after leave".to_string())?;
    left.forget().await.map_err(|e| e.to_string())?;
    Ok(room_id)
}

/// Sets a member's power level (e.g. 50 moderator, 100 admin). Caller must have permission.
pub async fn set_room_member_power_level(
    client: &Client,
    room_id: String,
    user_id: String,
    power_level: i64,
) -> Result<(), String> {
    let rid = RoomId::parse(&room_id).map_err(|e| e.to_string())?;
    let room = client.get_room(&rid).ok_or_else(|| "Room not found".to_string())?;
    let uid = UserId::parse(&user_id).map_err(|e| e.to_string())?;
    let pl = Int::new(power_level).ok_or_else(|| "Invalid power level".to_string())?;
    room
        .update_power_levels(vec![(&uid, pl)])
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

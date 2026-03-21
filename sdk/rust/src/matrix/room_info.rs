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
    let display_name = room
        .cached_display_name()
        .map(|s| s.to_string())
        .or_else(|| room.name().map(|n| n.to_string()))
        .unwrap_or_default();

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

        for m in joined {
            let uid = m.user_id().to_string();
            let is_self = m.is_account_user();
            let display_name = m
                .display_name()
                .map(|s| s.to_owned())
                .unwrap_or_else(|| uid.clone());
            let role = RoomMemberRoleDto::from(m.suggested_role_for_power_level());
            let pl = m.power_level();
            let power_level = user_power_to_i64(pl);
            let can_kick = current_user_can_kick_target(own_power, pl, kick_threshold, is_self);
            members.push(RoomMemberRow {
                user_id: uid,
                display_name,
                power_level,
                role,
                is_self,
                current_user_can_kick: can_kick,
            });
        }

        members.sort_by(|a, b| {
            let rank = |r: &RoomMemberRow| match r.role {
                RoomMemberRoleDto::Creator => 0,
                RoomMemberRoleDto::Administrator => 1,
                RoomMemberRoleDto::Moderator => 2,
                RoomMemberRoleDto::User => 3,
            };
            rank(a)
                .cmp(&rank(b))
                .then_with(|| a.display_name.to_lowercase().cmp(&b.display_name.to_lowercase()))
        });
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
        current_user_id: own_id,
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

    let sender = orig.sender.to_string();
    let is_outgoing = sender == own_id;

    let timestamp = ev
        .timestamp
        .map(|t| u64::from(t.0))
        .unwrap_or(0);

    Some(RoomFileItem {
        event_id,
        transaction_id,
        sender,
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

//! Global account data for app-specific profile fields (e.g. timeline initials).

use matrix_sdk::Client;
use matrix_sdk::ruma::events::{AnyGlobalAccountDataEventContent, GlobalAccountDataEventType};
use matrix_sdk::ruma::serde::Raw;
use serde::{Deserialize, Serialize};

const PROFILE_ACCOUNT_EVENT_TYPE: &str = "com.matrixrustdart.profile";

#[derive(Debug, Serialize, Deserialize)]
struct ProfileAccountContent {
    #[serde(skip_serializing_if = "Option::is_none")]
    initials: Option<String>,
}

/// Optional short initials/nickname label for avatars (synced via account data).
pub async fn get_profile_initials(client: &Client) -> Result<Option<String>, String> {
    let et = GlobalAccountDataEventType::from(PROFILE_ACCOUNT_EVENT_TYPE.to_owned());
    let raw = client
        .account()
        .fetch_account_data(et)
        .await
        .map_err(|e| e.to_string())?;
    let Some(raw) = raw else {
        return Ok(None);
    };
    let c: ProfileAccountContent = raw
        .deserialize_as_unchecked()
        .map_err(|e| format!("profile account data: {e}"))?;
    Ok(c
        .initials
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty()))
}

/// Set or clear initials (`None` / empty removes the field from the stored object).
pub async fn set_profile_initials(client: &Client, initials: Option<String>) -> Result<(), String> {
    let initials = initials.and_then(|s| {
        let t = s.trim().to_string();
        if t.is_empty() {
            None
        } else {
            Some(t.chars().take(8).collect::<String>())
        }
    });
    let content = ProfileAccountContent { initials };
    let json = serde_json::to_string(&content).map_err(|e| e.to_string())?;
    let raw: Raw<AnyGlobalAccountDataEventContent> =
        Raw::from_json_string(json).map_err(|e| e.to_string())?;
    let et = GlobalAccountDataEventType::from(PROFILE_ACCOUNT_EVENT_TYPE.to_owned());
    client
        .account()
        .set_account_data_raw(et, raw)
        .await
        .map_err(|e| e.to_string())?;
    Ok(())
}

//! Matrix recovery (secret storage + key backup) helpers for the FRB API.

use matrix_sdk::{
    encryption::recovery::RecoveryState,
    Client,
};

pub fn get_recovery_state_label(client: &Client) -> String {
    match client.encryption().recovery().state() {
        RecoveryState::Unknown => "unknown".to_owned(),
        RecoveryState::Enabled => "enabled".to_owned(),
        RecoveryState::Disabled => "disabled".to_owned(),
        RecoveryState::Incomplete => "incomplete".to_owned(),
    }
}

/// Waits for background E2EE setup (including recovery state refresh from account data).
pub async fn wait_for_recovery_state_ready(client: &Client) {
    client.encryption().wait_for_e2ee_initialization_tasks().await;
}

/// Whether the homeserver already has a room-key backup for this account.
/// When true but recovery is not [RecoveryState::Enabled], the user should unlock with an
/// existing passphrase — not run [enable_recovery_with_passphrase] (that returns
/// `BackupExistsOnServer`).
pub async fn backup_exists_on_server(client: &Client) -> Result<bool, String> {
    client
        .encryption()
        .backups()
        .fetch_exists_on_server()
        .await
        .map_err(|e| e.to_string())
}

pub async fn enable_recovery_with_passphrase(
    client: &Client,
    passphrase: String,
) -> Result<String, String> {
    client
        .encryption()
        .recovery()
        .enable()
        .wait_for_backups_to_upload()
        .with_passphrase(passphrase.as_str())
        .await
        .map_err(|e| e.to_string())
}

pub async fn recover_with_passphrase(client: &Client, passphrase: String) -> Result<(), String> {
    client
        .encryption()
        .recovery()
        .recover_and_fix_backup(passphrase.as_str())
        .await
        .map_err(|e| e.to_string())
}

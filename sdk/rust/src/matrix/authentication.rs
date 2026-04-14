use matrix_sdk::{
    ruma::{
        api::client::{
            account::register,
            uiaa::{AuthData, Dummy, RegistrationToken},
        },
        assign,
    },
    AuthSession, Client,
};
use std::path::Path;
use tracing::{error, info};

static SESSION_JSON: &str = "session.json";

/// Check if client is properly authenticated.
pub(crate) fn is_client_authenticated(client: &Client) -> Result<bool, String> {
    Ok(client.session().is_some())
}

/// Register using the given client and session path (no global client). Used by [crate::api::matrix_client::MatrixClient].
pub(crate) async fn register(
    client: &Client,
    session_path: &str,
    username: String,
    password: String,
    display_name: String,
    token: Option<String>,
) -> Result<bool, String> {
    info!("Attempting to register user: {}", username);

    if client.session().is_some() {
        info!("Skipping register: client already holds a session");
        return Ok(true);
    }

    info!("Attempting Matrix authentication...");
    let mut auth = AuthData::Dummy(Dummy::new());

    if let Some(token) = token {
        auth = AuthData::RegistrationToken(RegistrationToken::new(token));
    }

    let req = assign!(register::v3::Request::new(), {
        username: Some(username.to_owned()),
        password: Some(password.to_owned()),
        auth: Some(auth),
        refresh_token: true,
    });

    client.matrix_auth().register(req).await.map_err(|e| {
        error!("Login failed: {}", e);
        e.to_string()
    })?;

    info!("Registration successful, retrieving session...");

    let Some(session) = client.session() else {
        error!("Session not found after login");
        return Err("Session not found".to_string());
    };

    let AuthSession::Matrix(session) = session else {
        error!("Unexpected OAuth 2.0 session");
        return Err("Unexpected OAuth 2.0 session".to_string());
    };

    let path = Path::new(session_path);
    let session_path = path.join(SESSION_JSON);
    let serialized_session =
        serde_json::to_string(&session).map_err(|e| e.to_string())?;
    let _ = std::fs::write(session_path, serialized_session);

    info!("Registration completed successfully for user: {}", username);

    client
        .account()
        .set_display_name(Some(&display_name))
        .await
        .map_err(|e| {
            error!("Failed to set display name: {}", e);
            e.to_string()
        })?;

    Ok(true)
}

/// Login using the given client and session path (no global client). Used by [crate::api::matrix_client::MatrixClient].
pub(crate) async fn login(
    client: &Client,
    session_path: &str,
    username: String,
    password: String,
) -> Result<bool, String> {
    info!("Attempting to login user: {}", username);

    if client.session().is_some() {
        info!("Skipping password login: client already holds a session (e.g. restored from session.json)");
        return Ok(true);
    }

    info!("Attempting Matrix authentication...");

    client
        .matrix_auth()
        .login_username(&username, &password)
        .initial_device_display_name("Matrix Flutter App ")
        .request_refresh_token()
        .await
        .map_err(|e| {
            error!("Login failed: {}", e);
            e.to_string()
        })?;

    info!("Login successful, retrieving session...");

    let Some(session) = client.session() else {
        error!("Session not found after login");
        return Err("Session not found".to_string());
    };

    let AuthSession::Matrix(session) = session else {
        error!("Unexpected OAuth 2.0 session");
        return Err("Unexpected OAuth 2.0 session".to_string());
    };

    let path = Path::new(session_path);
    let session_path = path.join(SESSION_JSON);
    let serialized_session =
        serde_json::to_string(&session).map_err(|e| e.to_string())?;
    let _ = std::fs::write(session_path, serialized_session);

    info!("Login completed successfully for user: {}", username);
    Ok(true)
}

/// Logout using the given client and clear session file at session_path. Used by [crate::api::matrix_client::MatrixClient].
pub(crate) async fn logout(client: &Client, session_path: &str) -> Result<bool, String> {
    client
        .matrix_auth()
        .logout()
        .await
        .map_err(|e| e.to_string())?;

    let path = Path::new(session_path).join(SESSION_JSON);
    let _ = std::fs::remove_file(&path);
    Ok(true)
}

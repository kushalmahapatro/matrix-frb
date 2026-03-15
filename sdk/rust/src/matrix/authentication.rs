use matrix_sdk::{
    ruma::{
        api::client::{
            account::register,
            uiaa::{AuthData, Dummy},
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
) -> Result<bool, String> {
    info!("Attempting to register user: {}", username);

    info!("Attempting Matrix authentication...");

    let req = assign!(register::v3::Request::new(), {
        username: Some(username.to_owned()),
        password: Some(password.to_owned()),
        auth: Some(AuthData::Dummy(Dummy::new())),
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
        panic!("Unexpected OAuth 2.0 session")
    };

    let path = Path::new(session_path);
    let session_path = path.join(SESSION_JSON);
    let serialized_session = serde_json::to_string(&session).unwrap();
    let _ = std::fs::write(session_path, serialized_session);

    info!("Registration completed successfully for user: {}", username);
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

    info!("Attempting Matrix authentication...");

    client
        .matrix_auth()
        .login_username(&username, &password)
        .initial_device_display_name("Matrix Flutter App ")
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
        panic!("Unexpected OAuth 2.0 session")
    };

    let path = Path::new(session_path);
    let session_path = path.join(SESSION_JSON);
    let serialized_session = serde_json::to_string(&session).unwrap();
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

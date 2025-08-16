use crate::{
    api::{
        logger::{log_error, log_info},
        platform::GLOBAL_RUNTIME,
    },
    matrix::client::{get_global_client, set_global_client, GLOBAL_CONFIG},
};
use matrix_sdk::{
    ruma::{
        api::client::{
            account::register,
            uiaa::{AuthData, Dummy},
        },
        assign,
    },
    AuthSession,
};
use std::path::Path;

static SESSION_JSON: &str = "session.json";

// Check if client is properly authenticated
pub fn is_client_authenticated() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME.get();
        if runtime.is_none() {
            return Err("Global runtime not initialized".to_string());
        }

        runtime.unwrap().block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                // Check if client has a valid session
                Ok(client.session().is_some())
            } else {
                Ok(false)
            }
        })
    })
}

pub fn register(username: String, password: String) -> Result<bool, String> {
    log_info(format!("Attempting to register user: {}", username));
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                log_info("Attempting Matrix authentication...".to_string());

                let req = assign!(register::v3::Request::new(), {
                    username: Some(username.to_owned()),
                    password: Some(password.to_owned()),
                    auth: Some(AuthData::Dummy(Dummy::new())),
                    refresh_token: true,
                });

                client.matrix_auth().register(req).await.map_err(|e| {
                    log_error(format!("Login failed: {}", e));
                    e.to_string()
                })?;

                log_info("Registration successful, retrieving session...".to_string());

                let Some(session) = client.session() else {
                    log_error("Session not found after login".to_string());
                    return Err("Session not found".to_string());
                };

                let AuthSession::Matrix(session) = session else {
                    log_error("Unexpected OAuth 2.0 session".to_string());
                    panic!("Unexpected OAuth 2.0 session")
                };

                let global_config = GLOBAL_CONFIG.get();
                let Some(config) = global_config else {
                    log_error("Config not found during login".to_string());
                    return Err("Config not found".to_string());
                };

                let path = Path::new(&config.session_path);
                let session_path = path.join(SESSION_JSON);
                let serialized_session = serde_json::to_string(&session).unwrap();
                let _ = std::fs::write(session_path, serialized_session);

                log_info(format!(
                    "Registration completed successfully for user: {}",
                    username
                ));
                Ok(true)
            } else {
                log_error("Client not initialized for registration".to_string());
                Err("Client not initialized".to_string())
            }
        })
    })
}

pub fn login(username: String, password: String) -> Result<bool, String> {
    log_info(format!("Attempting to login user: {}", username));

    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                log_info("Attempting Matrix authentication...".to_string());

                client
                    .matrix_auth()
                    .login_username(&username, &password)
                    .initial_device_display_name("Matrix Flutter App ")
                    .await
                    .map_err(|e| {
                        log_error(format!("Login failed: {}", e));
                        e.to_string()
                    })?;

                log_info("Login successful, retrieving session...".to_string());

                let Some(session) = client.session() else {
                    log_error("Session not found after login".to_string());
                    return Err("Session not found".to_string());
                };

                let AuthSession::Matrix(session) = session else {
                    log_error("Unexpected OAuth 2.0 session".to_string());
                    panic!("Unexpected OAuth 2.0 session")
                };

                let global_config = GLOBAL_CONFIG.get();
                let Some(config) = global_config else {
                    log_error("Config not found during login".to_string());
                    return Err("Config not found".to_string());
                };

                let path = Path::new(&config.session_path);
                let session_path = path.join(SESSION_JSON);
                let serialized_session = serde_json::to_string(&session).unwrap();
                let _ = std::fs::write(session_path, serialized_session);

                log_info(format!(
                    "Login completed successfully for user: {}",
                    username
                ));
                Ok(true)
            } else {
                log_error("Client not initialized for login".to_string());
                Err("Client not initialized".to_string())
            }
        })
    })
}

pub fn logout() -> Result<bool, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let global_client = get_global_client().await?;
            if let Some(client) = global_client {
                client
                    .matrix_auth()
                    .logout()
                    .await
                    .map_err(|e| e.to_string())?;

                // Stop sync
                set_global_client(None).await?;
                Ok(true)
            } else {
                Err("Client not initialized".to_string())
            }
        })
    })
}

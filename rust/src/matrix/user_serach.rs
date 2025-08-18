use crate::{
    api::{logger::log_error, platform::GLOBAL_RUNTIME},
    matrix::sync_service::GLOBAL_APP,
};

#[derive(Clone)]
pub struct UserSearchResult {
    pub users: Vec<User>,
    pub limited: bool,
}

#[derive(Clone)]
pub struct User {
    pub user_id: String,
    pub display_name: Option<String>,
    pub avatar_url: Option<String>,
}

pub fn search_users(query: String) -> Result<UserSearchResult, String> {
    tokio::task::block_in_place(|| {
        let runtime = GLOBAL_RUNTIME
            .get()
            .expect("Global runtime not initialized");
        runtime.block_on(async {
            let app = GLOBAL_APP.get().expect("Global app not initialized");
            let response = app.client.search_users(&query, 100).await;

            // For now, we'll implement a simple search that looks for exact user IDs
            // In a real implementation, you might want to use the homeserver's user directory
            let mut results = Vec::new();

            match response {
                Ok(search_response) => {
                    for user in search_response.results {
                        results.push(User {
                            user_id: user.user_id.to_string(),
                            display_name: user.display_name,
                            avatar_url: user.avatar_url.map(|uri| uri.to_string()),
                        });
                    }

                    Ok(UserSearchResult {
                        users: results,
                        limited: search_response.limited,
                    })
                }
                Err(e) => {
                    log_error(format!("User search failed: {}", e));
                    Err(format!("User search failed: {}", e))
                }
            }
        })
    })
}

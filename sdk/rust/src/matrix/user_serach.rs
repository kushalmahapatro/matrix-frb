use matrix_sdk::Client;
use tracing::error;

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

/// User search using the given client (used by [crate::api::matrix_client::MatrixClient]).
pub(crate) async fn search_users(
    client: &Client,
    query: String,
) -> Result<UserSearchResult, String> {
    let response = &client.search_users(&query, 100).await;

    let mut results = Vec::new();

    match response {
        Ok(search_response) => {
            for user in search_response.results.clone() {
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
            error!("User search failed: {}", e);
            Err(format!("User search failed: {}", e))
        }
    }
}

//! Extract HTTP(S) URLs from outgoing text and fetch lightweight Open Graph–style metadata
//! for [MSC4095](https://github.com/matrix-org/matrix-spec-proposals/pull/4095) `com.beeper.linkpreviews`.

use std::time::Duration;

use matrix_sdk::ruma::events::room::message::UrlPreview;
use regex::Regex;
use reqwest::header::{ACCEPT, USER_AGENT};

const MAX_URLS: usize = 4;
const FETCH_TIMEOUT: Duration = Duration::from_secs(12);
const MAX_HTML_BYTES: usize = 512 * 1024;
const UA: &str = "MatrixChat/1.0 (+https://matrix.org) LinkPreview";

fn url_regex() -> &'static Regex {
    static RE: std::sync::OnceLock<Regex> = std::sync::OnceLock::new();
    RE.get_or_init(|| Regex::new(r#"https?://[^\s<>\[\]()"'{}|\\]+"#).expect("url regex"))
}

/// Trim common trailing punctuation from URL matches.
fn normalize_url_match(s: &str) -> String {
    s.trim_end_matches(|c: char| matches!(c, '.' | ',' | ';' | ':' | '!' | ')' | ']' | '}' | '"'))
        .to_string()
}

/// Distinct HTTP(S) URLs in appearance order (capped).
pub fn extract_http_urls(text: &str) -> Vec<String> {
    let re = url_regex();
    let mut out = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for m in re.find_iter(text) {
        let u = normalize_url_match(m.as_str());
        if u.len() < 8 {
            continue;
        }
        if seen.insert(u.clone()) && out.len() < MAX_URLS {
            out.push(u);
        }
    }
    out
}

fn meta_tag_content(html: &str, prop: &str) -> Option<String> {
    let prop_lower = prop.to_ascii_lowercase();
    // property="og:title" content="..."
    let re1 = Regex::new(&format!(
        r#"(?is)<meta[^>]+property\s*=\s*["']{}["'][^>]+content\s*=\s*["']([^"']*)["']"#,
        regex::escape(&prop_lower)
    ))
    .ok()?;
    if let Some(c) = re1
        .captures(html)
        .and_then(|c| c.get(1))
        .map(|m| html_unescape(m.as_str().trim()))
    {
        if !c.is_empty() {
            return Some(c);
        }
    }
    // content="..." property="og:title"
    let re2 = Regex::new(&format!(
        r#"(?is)<meta[^>]+content\s*=\s*["']([^"']*)["'][^>]+property\s*=\s*["']{}["']"#,
        regex::escape(&prop_lower)
    ))
    .ok()?;
    re2.captures(html)
        .and_then(|c| c.get(1))
        .map(|m| html_unescape(m.as_str().trim()))
        .filter(|s| !s.is_empty())
}

fn html_unescape(s: &str) -> String {
    s.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
}

/// Fetch Open Graph–style fields; image is omitted (MSC4095 expects MXC for images).
pub async fn fetch_preview_for_url(url: &str) -> UrlPreview {
    let client = match reqwest::Client::builder()
        .timeout(FETCH_TIMEOUT)
        .redirect(reqwest::redirect::Policy::limited(5))
        .build()
    {
        Ok(c) => c,
        Err(_) => return UrlPreview::matched_url(url.to_owned()),
    };

    let response = match client
        .get(url)
        .header(USER_AGENT, UA)
        .header(ACCEPT, "text/html,application/xhtml+xml;q=0.9,*/*;q=0.8")
        .send()
        .await
    {
        Ok(r) => r,
        Err(_) => return UrlPreview::matched_url(url.to_owned()),
    };

    let bytes = match response.bytes().await {
        Ok(b) => b,
        Err(_) => return UrlPreview::matched_url(url.to_owned()),
    };

    let slice = if bytes.len() > MAX_HTML_BYTES {
        &bytes[..MAX_HTML_BYTES]
    } else {
        &bytes[..]
    };

    let html = String::from_utf8_lossy(slice);
    let title = meta_tag_content(&html, "og:title")
        .or_else(|| meta_tag_content(&html, "twitter:title"))
        .or_else(|| meta_tag_content(&html, "title"));
    let description = meta_tag_content(&html, "og:description")
        .or_else(|| meta_tag_content(&html, "twitter:description"));
    let og_url = meta_tag_content(&html, "og:url");

    let mut p = UrlPreview::matched_url(url.to_owned());
    p.title = title;
    p.description = description;
    p.url = og_url;
    p
}

/// One preview per distinct URL (same order as [extract_http_urls]).
pub async fn fetch_url_previews(urls: &[String]) -> Vec<UrlPreview> {
    let mut out = Vec::with_capacity(urls.len());
    for u in urls {
        out.push(fetch_preview_for_url(u).await);
    }
    out
}

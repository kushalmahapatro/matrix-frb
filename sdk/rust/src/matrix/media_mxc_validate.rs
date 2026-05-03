//! Check that plain MXC media still exists on the homeserver before reusing upload-cache rows.

use matrix_sdk::media::{MediaFormat, MediaRequestParameters};
use matrix_sdk::ruma::api::client::error::ErrorKind;
use matrix_sdk::ruma::events::room::MediaSource;
use matrix_sdk::ruma::{MxcUri, OwnedMxcUri};
use matrix_sdk::{Client, Error as SdkError};

/// Whether cached MXC media is still on the server, unknown (network/transient), or gone.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MxcPresence {
    Present,
    /// `M_NOT_FOUND` / equivalent — safe to drop the cache row and re-upload.
    Gone,
    /// Parse error, offline, or non-404 error — keep cache and try reuse (optimistic).
    Unknown,
}

/// `true` when the server responded with a client API “not found” (e.g. deleted media).
pub fn sdk_http_not_found(err: &SdkError) -> bool {
    if let SdkError::Http(boxed) = err {
        return matches!(boxed.client_api_error_kind(), Some(ErrorKind::NotFound));
    }
    false
}

/// One full media download (no local media cache) to see if the MXC still exists.
pub async fn probe_plain_mxc(client: &Client, mxc: &str) -> MxcPresence {
    let m: &MxcUri = mxc.into();
    if m.validate().is_err() {
        return MxcPresence::Gone;
    }
    let uri: OwnedMxcUri = mxc.to_owned().into();
    let req = MediaRequestParameters {
        source: MediaSource::Plain(uri),
        format: MediaFormat::File,
    };
    match client.media().get_media_content(&req, false).await {
        Ok(_) => MxcPresence::Present,
        Err(e) if sdk_http_not_found(&e) => MxcPresence::Gone,
        Err(_) => MxcPresence::Unknown,
    }
}

/// Result of checking cached **plain** file + optional thumbnail MXC before reusing uploads.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CachedPlainMediaProbe {
    /// Both requested MXCs are not known to be deleted (present or unknown/network).
    Reusable,
    /// Main file MXC returned 404 — drop cache row and re-upload.
    FileGone,
    /// Thumbnail MXC returned 404 — drop cache row and re-upload.
    ThumbGone,
}

/// Probes the main file MXC and, when [thumb_mxc] is [Some], the thumbnail MXC.
/// Any definite `M_NOT_FOUND` on a required MXC returns [CachedPlainMediaProbe::FileGone] or
/// [CachedPlainMediaProbe::ThumbGone].
pub async fn probe_cached_plain_media(
    client: &Client,
    file_mxc: &str,
    thumb_mxc: Option<&str>,
) -> CachedPlainMediaProbe {
    match probe_plain_mxc(client, file_mxc).await {
        MxcPresence::Gone => return CachedPlainMediaProbe::FileGone,
        MxcPresence::Present | MxcPresence::Unknown => {}
    }
    if let Some(t) = thumb_mxc {
        match probe_plain_mxc(client, t).await {
            MxcPresence::Gone => return CachedPlainMediaProbe::ThumbGone,
            MxcPresence::Present | MxcPresence::Unknown => {}
        }
    }
    CachedPlainMediaProbe::Reusable
}

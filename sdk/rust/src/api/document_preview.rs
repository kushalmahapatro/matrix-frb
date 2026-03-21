//! Bridge: in-app document preview JSON for Flutter ([`crate::matrix::document_preview`]).

/// Returns JSON with ok/preview or ok/error keys (see matrix document_preview module).
pub fn document_preview_json(extension: String, data: Vec<u8>) -> String {
    crate::matrix::document_preview::document_preview_json(&extension, &data)
}

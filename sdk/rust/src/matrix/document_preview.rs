//! In-app document previews: text extraction / tabular data via Rust (calamine, OOXML zip, pdf-extract).
//! This is layout‑stripped preview, not pixel‑perfect rendering.
//! Paragraph breaks are preserved where the format allows (`</w:p>`, `</a:p>`, ODF `text:p` / `text:h`).
//!
//! Legacy **`.doc`** (Word 97–2003, OLE compound) has no XML: we read the `WordDocument` stream and
//! pull printable runs (similar to `strings`), plus UTF‑16LE runs — best‑effort only.

use calamine::{Data, Reader, Sheets};
use cfb::CompoundFile;
use quick_xml::escape::unescape;
use quick_xml::events::Event;
use quick_xml::Reader as XmlReader;
use serde_json::{json, Value};
use std::collections::HashSet;
use std::io::{Cursor, Read};

const MAX_SHEET_ROWS: usize = 400;
const MAX_SHEET_COLS: usize = 48;
const MAX_CELL_CHARS: usize = 256;
const MAX_SLIDES: usize = 80;
const MAX_PREVIEW_CHARS: usize = 512_000;

fn cell_display(cell: &Data) -> String {
    let s = format!("{cell}");
    if s.chars().count() > MAX_CELL_CHARS {
        s.chars().take(MAX_CELL_CHARS).collect::<String>() + "…"
    } else {
        s
    }
}

fn spreadsheet_from_bytes(data: &[u8]) -> Result<Value, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut workbook: Sheets<_> =
        calamine::open_workbook_auto_from_rs(cursor).map_err(|e| format!("Spreadsheet: {e}"))?;

    let names = workbook.sheet_names();
    let first = names
        .first()
        .cloned()
        .ok_or_else(|| "Spreadsheet has no sheets".to_string())?;

    let range = workbook
        .worksheet_range(&first)
        .map_err(|e| format!("Spreadsheet: {e}"))?;

    let height = range.height() as usize;
    let width = range.width() as usize;
    let row_take = height.min(MAX_SHEET_ROWS);
    let col_take = width.min(MAX_SHEET_COLS);
    let truncated = height > MAX_SHEET_ROWS || width > MAX_SHEET_COLS;

    let mut rows: Vec<Vec<String>> = Vec::with_capacity(row_take);
    for row in range.rows().take(row_take) {
        let mut r = Vec::with_capacity(col_take);
        for cell in row.iter().take(col_take) {
            r.push(cell_display(cell));
        }
        rows.push(r);
    }

    Ok(json!({
        "kind": "sheet",
        "sheet": first,
        "rows": rows,
        "truncated": truncated,
        "note": "Tabular preview (formulas and formatting not preserved).",
    }))
}

/// Pull character data from `<tag ...>inner</tag>` fragments (OOXML `w:t`, `a:t`, etc.).
fn extract_tag_inners(xml_frag: &str, open: &str, close: &str) -> String {
    let mut out = String::new();
    let mut rest = xml_frag;
    let close_len = close.len();
    while let Some(i) = rest.find(open) {
        let after_open = &rest[i + open.len()..];
        let Some(gt) = after_open.find('>') else {
            break;
        };
        let inner_start = &after_open[gt + 1..];
        let Some(end) = inner_start.find(close) else {
            break;
        };
        out.push_str(&inner_start[..end]);
        rest = &inner_start[end + close_len..];
    }
    out
}

fn unescape_xml_text(raw: &str) -> String {
    match unescape(raw) {
        Ok(c) => c.into_owned(),
        Err(_) => raw.to_string(),
    }
}

/// Word `document.xml`: one preview paragraph per `</w:p>` (preserves line breaks between paragraphs).
fn extract_docx_paragraphs(xml: &str) -> String {
    let parts: Vec<String> = xml
        .split("</w:p>")
        .map(|seg| {
            let raw = extract_tag_inners(seg, "<w:t", "</w:t>");
            unescape_xml_text(raw.trim())
        })
        .filter(|s| !s.is_empty())
        .collect();
    parts.join("\n\n")
}

/// PPTX slide XML: paragraphs from `</a:p>`; text runs from `<a:t>`.
fn extract_pptx_slide_paragraphs(xml: &str) -> String {
    let parts: Vec<String> = xml
        .split("</a:p>")
        .map(|seg| {
            let raw = extract_tag_inners(seg, "<a:t", "</a:t>");
            unescape_xml_text(raw.trim())
        })
        .filter(|s| !s.is_empty())
        .collect();
    parts.join("\n\n")
}

/// ODF `content.xml`: walk `<text:p>` / `<text:h>` blocks in document order.
fn extract_odf_paragraphs(xml: &str) -> String {
    let mut out: Vec<String> = Vec::new();
    let mut i = 0usize;
    while i < xml.len() {
        let rest = &xml[i..];
        let op = rest.find("<text:p");
        let oh = rest.find("<text:h");
        let (rel, open_tag_len, close_tag) = match (op, oh) {
            (Some(a), Some(b)) => {
                if a < b {
                    (a, "<text:p".len(), "</text:p>")
                } else {
                    (b, "<text:h".len(), "</text:h>")
                }
            }
            (Some(a), None) => (a, "<text:p".len(), "</text:p>"),
            (None, Some(b)) => (b, "<text:h".len(), "</text:h>"),
            (None, None) => break,
        };
        let open_abs = i + rel;
        let after_open = &xml[open_abs + open_tag_len..];
        let Some(gt) = after_open.find('>') else {
            break;
        };
        let content_start = open_abs + open_tag_len + gt + 1;
        let after_content = &xml[content_start..];
        let Some(end_rel) = after_content.find(close_tag) else {
            break;
        };
        let inner = &after_content[..end_rel];
        let wrapped = format!("<x>{inner}</x>");
        let t = collect_all_text_nodes(&wrapped).trim().to_string();
        if !t.is_empty() {
            out.push(t);
        }
        i = content_start + end_rel + close_tag.len();
    }
    out.join("\n\n")
}

/// Collect text from `w:t` / `a:t` style runs (local name `t`).
fn collect_t_runs(xml: &str) -> String {
    let mut reader = XmlReader::from_str(xml);
    reader.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut out = String::new();
    let mut depth: i32 = 0;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                if e.local_name().as_ref() == b"t" {
                    depth += 1;
                }
            }
            Ok(Event::Text(e)) => {
                if depth > 0 {
                    if let Ok(u) = e.decode() {
                        out.push_str(&u);
                    }
                }
            }
            Ok(Event::End(e)) => {
                if e.local_name().as_ref() == b"t" {
                    depth = (depth - 1).max(0);
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
        buf.clear();
    }
    out
}

fn collect_all_text_nodes(xml: &str) -> String {
    let mut reader = XmlReader::from_str(xml);
    reader.config_mut().trim_text(true);
    let mut buf = Vec::new();
    let mut out = String::new();

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Text(e)) => {
                if let Ok(u) = e.decode() {
                    let t = u.trim();
                    if !t.is_empty() {
                        if !out.is_empty() {
                            out.push('\n');
                        }
                        out.push_str(t);
                    }
                }
            }
            Ok(Event::Eof) => break,
            Err(_) => break,
            _ => {}
        }
        buf.clear();
    }

    if out.chars().count() > MAX_PREVIEW_CHARS {
        out.chars().take(MAX_PREVIEW_CHARS).collect::<String>() + "\n…"
    } else {
        out
    }
}

fn read_zip_entry(archive: &mut zip::ZipArchive<Cursor<Vec<u8>>>, name: &str) -> Option<String> {
    let mut f = archive.by_name(name).ok()?;
    let mut s = String::new();
    f.read_to_string(&mut s).ok()?;
    Some(s)
}

fn preview_docx(data: &[u8]) -> Result<Value, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut archive = zip::ZipArchive::new(cursor).map_err(|e| format!("DOCX (zip): {e}"))?;
    let xml = read_zip_entry(&mut archive, "word/document.xml")
        .ok_or_else(|| "DOCX missing word/document.xml".to_string())?;
    let body = extract_docx_paragraphs(&xml);
    if body.trim().is_empty() {
        return Err("No text could be extracted from this DOCX".to_string());
    }
    let text = if body.chars().count() > MAX_PREVIEW_CHARS {
        body.chars().take(MAX_PREVIEW_CHARS).collect::<String>() + "\n…"
    } else {
        body
    };
    Ok(json!({
        "kind": "text",
        "body": text,
        "note": "Text extracted from Word (layout and images not shown).",
    }))
}

fn preview_pptx(data: &[u8]) -> Result<Value, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut archive = zip::ZipArchive::new(cursor).map_err(|e| format!("PPTX (zip): {e}"))?;

    let mut names: Vec<String> = (0..archive.len())
        .filter_map(|i| archive.by_index(i).ok().map(|z| z.name().to_string()))
        .filter(|n| n.starts_with("ppt/slides/slide") && n.ends_with(".xml"))
        .collect();
    names.sort();

    if names.is_empty() {
        return Err("PPTX has no slide XML".to_string());
    }

    let mut slides: Vec<String> = Vec::new();
    for name in names.into_iter().take(MAX_SLIDES) {
        if let Some(xml) = read_zip_entry(&mut archive, &name) {
            let slide = extract_pptx_slide_paragraphs(&xml);
            if !slide.is_empty() {
                slides.push(slide);
            }
        }
    }

    if slides.is_empty() {
        return Err("No slide text could be extracted from this PPTX".to_string());
    }

    Ok(json!({
        "kind": "slides",
        "slides": slides,
        "note": "Slide text only (no images or animations).",
    }))
}

fn preview_odf(data: &[u8]) -> Result<Value, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut archive = zip::ZipArchive::new(cursor).map_err(|e| format!("ODF (zip): {e}"))?;
    let xml = read_zip_entry(&mut archive, "content.xml")
        .ok_or_else(|| "ODF missing content.xml".to_string())?;
    let body = extract_odf_paragraphs(&xml);
    if body.trim().is_empty() {
        return Err("No text could be extracted from this ODF file".to_string());
    }
    Ok(json!({
        "kind": "text",
        "body": body,
        "note": "Text extracted from OpenDocument (layout not preserved).",
    }))
}

fn preview_pdf_text(data: &[u8]) -> Result<Value, String> {
    let text = pdf_extract::extract_text_from_mem(data).map_err(|e| format!("PDF: {e}"))?;
    let t = text.trim();
    if t.is_empty() {
        return Err(
            "No extractable text in this PDF (may be image‑only or encrypted).".to_string(),
        );
    }
    let body = if t.chars().count() > MAX_PREVIEW_CHARS {
        t.chars().take(MAX_PREVIEW_CHARS).collect::<String>() + "\n…"
    } else {
        t.to_string()
    };
    Ok(json!({
        "kind": "text",
        "body": body,
        "note": "Text extracted from PDF (layout not preserved).",
    }))
}

/// Word stores the main binary in this OLE stream (MS‑DOC).
const WORD_DOCUMENT_STREAMS: [&str; 4] = [
    "/WordDocument",
    "WordDocument",
    "/worddocument",
    "worddocument",
];

fn read_word_document_stream(data: &[u8]) -> Result<Vec<u8>, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut comp = CompoundFile::open(cursor).map_err(|e| format!("OLE (.doc): {e}"))?;
    for path in WORD_DOCUMENT_STREAMS {
        if let Ok(mut s) = comp.open_stream(path) {
            let mut buf = Vec::new();
            if s.read_to_end(&mut buf).map_err(|e| e.to_string()).is_ok() && !buf.is_empty() {
                return Ok(buf);
            }
        }
    }
    Err("OLE file has no WordDocument stream".to_string())
}

/// Printable ASCII runs (min length) — picks up embedded English / identifiers from binary Word.
fn ascii_string_runs(data: &[u8], min_run: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut cur: Vec<u8> = Vec::new();
    for &b in data {
        if b == b'\n' || b == b'\t' || (b >= 0x20 && b < 0x7f) {
            cur.push(if b == b'\t' { b' ' } else { b });
        } else {
            if cur.len() >= min_run {
                if let Ok(s) = std::str::from_utf8(&cur) {
                    let t = s.trim();
                    if t.chars().filter(|c| c.is_alphanumeric()).count() >= 5 {
                        out.push(t.to_string());
                    }
                }
            }
            cur.clear();
        }
    }
    if cur.len() >= min_run {
        if let Ok(s) = std::str::from_utf8(&cur) {
            let t = s.trim();
            if t.chars().filter(|c| c.is_alphanumeric()).count() >= 5 {
                out.push(t.to_string());
            }
        }
    }
    out
}

/// UTF‑16LE text runs (two alignment passes).
fn utf16le_string_runs(data: &[u8], min_chars: usize) -> Vec<String> {
    let mut out = Vec::new();
    for align in 0..2 {
        let mut i = align;
        while i + 1 < data.len() {
            let mut run = String::new();
            let start = i;
            while i + 1 < data.len() {
                let u = u16::from_le_bytes([data[i], data[i + 1]]);
                if u < 0x20 && u != 0x09 && u != 0x0a {
                    break;
                }
                if let Some(c) = char::from_u32(u.into()) {
                    if u >= 0x20 || u == 0x09 || u == 0x0a {
                        run.push(c);
                    } else {
                        break;
                    }
                } else {
                    break;
                }
                i += 2;
            }
            if run.chars().count() >= min_chars {
                let t = run.trim().to_string();
                if t.chars().any(|c| c.is_alphanumeric()) {
                    out.push(t);
                }
            }
            i = if i > start { i } else { start + 2 };
        }
    }
    out
}

fn merge_preview_chunks(parts: Vec<String>) -> String {
    let mut seen = HashSet::new();
    let mut ordered: Vec<String> = Vec::new();
    for s in parts {
        let t = s.trim().to_string();
        if t.len() < 8 {
            continue;
        }
        if seen.insert(t.clone()) {
            ordered.push(t);
        }
    }
    let mut body = ordered.join("\n\n");
    while body.contains("\n\n\n") {
        body = body.replace("\n\n\n", "\n\n");
    }
    if body.chars().count() > MAX_PREVIEW_CHARS {
        body.chars().take(MAX_PREVIEW_CHARS).collect::<String>() + "\n…"
    } else {
        body
    }
}

/// Legacy Word `.doc` (OLE), or a `.doc` that is actually OOXML (zip) mislabeled.
fn preview_doc_binary(data: &[u8]) -> Result<Value, String> {
    if data.len() >= 4 && data.starts_with(b"PK\x03\x04") {
        return preview_docx(data);
    }
    let stream = read_word_document_stream(data)?;
    let mut chunks = ascii_string_runs(&stream, 12);
    chunks.extend(utf16le_string_runs(&stream, 8));
    if chunks.is_empty() {
        chunks = ascii_string_runs(data, 14);
        chunks.extend(utf16le_string_runs(data, 10));
    }
    let body = merge_preview_chunks(chunks);
    if body.trim().is_empty() {
        return Err(
            "No readable text in this .doc (binary Word; try opening in Word or export as .docx)."
                .to_string(),
        );
    }
    Ok(json!({
        "kind": "text",
        "body": body,
        "note": "Best-effort text from legacy Word (.doc) binary (layout and images not shown).",
    }))
}

/// Legacy PowerPoint 97–2003 main stream name (OLE).
const PPT_MAIN_STREAMS: [&str; 4] = [
    "/PowerPoint Document",
    "PowerPoint Document",
    "/PowerPoint document",
    "PowerPoint document",
];

fn read_powerpoint_document_stream(data: &[u8]) -> Result<Vec<u8>, String> {
    let cursor = Cursor::new(data.to_vec());
    let mut comp = CompoundFile::open(cursor).map_err(|e| format!("OLE (.ppt): {e}"))?;
    for path in PPT_MAIN_STREAMS {
        if let Ok(mut s) = comp.open_stream(path) {
            let mut buf = Vec::new();
            if s.read_to_end(&mut buf).map_err(|e| e.to_string()).is_ok() && !buf.is_empty() {
                return Ok(buf);
            }
        }
    }
    Err("OLE file has no PowerPoint Document stream".to_string())
}

/// Legacy `.ppt` (OLE), or zip mislabeled as `.ppt` → reuse PPTX path.
fn preview_ppt_binary(data: &[u8]) -> Result<Value, String> {
    if data.len() >= 4 && data.starts_with(b"PK\x03\x04") {
        return preview_pptx(data);
    }
    let stream = read_powerpoint_document_stream(data)?;
    let mut chunks = ascii_string_runs(&stream, 12);
    chunks.extend(utf16le_string_runs(&stream, 8));
    if chunks.is_empty() {
        chunks = ascii_string_runs(data, 14);
        chunks.extend(utf16le_string_runs(data, 10));
    }
    let body = merge_preview_chunks(chunks);
    if body.trim().is_empty() {
        return Err(
            "No readable text in this .ppt (legacy PowerPoint; open in an office app or use .pptx)."
                .to_string(),
        );
    }
    Ok(json!({
        "kind": "text",
        "body": body,
        "note": "Best-effort text from legacy PowerPoint (.ppt); slide boundaries are not preserved.",
    }))
}

fn preview_csv_as_sheet(data: &[u8]) -> Result<Value, String> {
    let mut rdr = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .from_reader(data);

    let mut rows: Vec<Vec<String>> = Vec::new();
    let mut records = rdr.records();
    while rows.len() < MAX_SHEET_ROWS {
        let rec = match records.next() {
            None => break,
            Some(Err(e)) => return Err(format!("CSV: {e}")),
            Some(Ok(r)) => r,
        };
        let mut r = Vec::new();
        for field in rec.iter().take(MAX_SHEET_COLS) {
            let mut s = field.to_string();
            if s.chars().count() > MAX_CELL_CHARS {
                s = s.chars().take(MAX_CELL_CHARS).collect::<String>() + "…";
            }
            r.push(s);
        }
        rows.push(r);
    }

    let truncated = records.next().is_some();

    Ok(json!({
        "kind": "sheet",
        "sheet": "CSV",
        "rows": rows,
        "truncated": truncated,
        "note": "CSV rows (delimiter‑parsed in Rust).",
    }))
}

/// JSON for Flutter: `{ "ok": true, "preview": { "kind": "text"|"sheet"|"slides", ... } }` or `{ "ok": false, "error": "..." }`.
pub fn document_preview_json(extension: &str, data: &[u8]) -> String {
    let ext = extension.trim().trim_start_matches('.').to_lowercase();

    let preview = match ext.as_str() {
        "pdf" => preview_pdf_text(data),
        "doc" => preview_doc_binary(data),
        "docx" => preview_docx(data),
        "ppt" => preview_ppt_binary(data),
        "pptx" => preview_pptx(data),
        "odt" | "odp" => preview_odf(data),
        "ods" | "xlsx" | "xlsm" | "xls" | "xlsb" => spreadsheet_from_bytes(data),
        "csv" => preview_csv_as_sheet(data),
        "rtf" => preview_rtf_plain(data),
        _ => Err(format!("No Rust preview for .{ext}")),
    };

    match preview {
        Ok(p) => json!({ "ok": true, "preview": p }).to_string(),
        Err(e) => json!({ "ok": false, "error": e }).to_string(),
    }
}

/// Best-effort: drop RTF control words (`\foo123`) and braces; keep readable characters.
fn preview_rtf_plain(data: &[u8]) -> Result<Value, String> {
    let s = String::from_utf8_lossy(data);
    let mut out = String::new();
    let mut it = s.chars().peekable();
    while let Some(c) = it.next() {
        if c == '\\' {
            match it.peek().copied() {
                Some('\\') | Some('{') | Some('}') => {
                    out.push(it.next().unwrap_or(c));
                }
                Some(_) => {
                    while let Some(&x) = it.peek() {
                        if x.is_alphabetic() {
                            it.next();
                        } else {
                            break;
                        }
                    }
                    while let Some(&x) = it.peek() {
                        if x.is_ascii_digit() || x == '-' {
                            it.next();
                        } else {
                            break;
                        }
                    }
                    if it.peek() == Some(&' ') {
                        it.next();
                    }
                    if it.peek() == Some(&'\n') {
                        it.next();
                    }
                }
                None => {}
            }
            continue;
        }
        if c == '{' || c == '}' {
            continue;
        }
        if c == '\r' {
            continue;
        }
        if c == '\n' {
            out.push('\n');
            continue;
        }
        out.push(c);
    }

    let body = out.trim();
    if body.is_empty() {
        return Err("No readable text in RTF".to_string());
    }
    let body = if body.chars().count() > MAX_PREVIEW_CHARS {
        body.chars().take(MAX_PREVIEW_CHARS).collect::<String>() + "\n…"
    } else {
        body.to_string()
    };
    Ok(json!({
        "kind": "text",
        "body": body,
        "note": "RTF stripped to plain text (formatting not preserved).",
    }))
}

#[cfg(test)]
mod document_preview_tests {
    use super::document_preview_json;
    use serde_json::Value;
    use std::io::{Cursor, Write};

    #[test]
    fn unknown_extension_fails() {
        let j = document_preview_json("weird", b"abc");
        assert!(j.contains("\"ok\":false"));
        assert!(j.contains("No Rust preview"));
    }

    #[test]
    fn pptx_invalid_zip_fails() {
        let j = document_preview_json("pptx", b"this is not a zip");
        assert!(j.contains("\"ok\":false"));
    }

    #[test]
    fn csv_single_cell_ok() {
        let j = document_preview_json("csv", b"a,b\n1,2");
        assert!(j.contains("\"ok\":true"));
        assert!(j.contains("sheet"));
    }

    #[test]
    fn docx_preserves_paragraph_breaks_in_json() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Hello</w:t></w:r></w:p>
    <w:p><w:r><w:t>World line two</w:t></w:r></w:p>
  </w:body>
</w:document>"#;
        let mut buf = Cursor::new(Vec::new());
        {
            let mut zip = zip::ZipWriter::new(&mut buf);
            zip.start_file(
                "word/document.xml",
                zip::write::SimpleFileOptions::default(),
            )
            .unwrap();
            zip.write_all(xml.as_bytes()).unwrap();
            zip.finish().unwrap();
        }
        let bytes = buf.into_inner();
        let j = document_preview_json("docx", &bytes);
        assert!(j.contains("\"ok\":true"), "{j}");
        let v: Value = serde_json::from_str(&j).expect(&j);
        let body = v["preview"]["body"].as_str().expect("body");
        assert!(body.contains("Hello"), "{body}");
        assert!(body.contains("World line two"), "{body}");
        assert!(
            body.contains("\n\n"),
            "expected paragraph break between runs: {body:?}"
        );
    }
}

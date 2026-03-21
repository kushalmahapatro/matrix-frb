//! Client-side thumbnails for outgoing attachments: raster resize, PDF first page (Pdfium),
//! and first embedded image in OOXML / ODF packages.

use std::io::Read;
use std::path::Path;

use mime::Mime;
use pdfium_render::prelude::{PdfRenderConfig, Pdfium};

use super::native_media_env::{ENV_MATRIX_PDFIUM_DIR, ENV_PDFIUM_DYNAMIC_LIB_PATH};

/// Load Pdfium once per call (avoids `Sync` requirements on the default bindings).
fn bind_pdfium() -> Option<Pdfium> {
    let mut dirs: Vec<std::path::PathBuf> = Vec::new();
    if let Ok(dir) = std::env::var(ENV_PDFIUM_DYNAMIC_LIB_PATH) {
        dirs.push(std::path::PathBuf::from(dir));
    }
    if let Ok(dir) = std::env::var(ENV_MATRIX_PDFIUM_DIR) {
        dirs.push(std::path::PathBuf::from(dir));
    }
    dirs.push(std::path::PathBuf::from("."));
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            dirs.push(parent.to_path_buf());
        }
    }
    for dir in dirs {
        let lib = Pdfium::pdfium_platform_library_name_at_path(&dir);
        if let Ok(b) = Pdfium::bind_to_library(&lib) {
            return Some(Pdfium::new(b));
        }
    }
    Pdfium::bind_to_system_library().ok().map(Pdfium::new)
}

/// JPEG thumbnail from decoded raster (max longest side 320px).
pub fn try_raster_thumbnail_from_bytes(data: &[u8]) -> Option<(Vec<u8>, u32, u32, usize)> {
    let img = image::ImageReader::new(std::io::Cursor::new(data))
        .with_guessed_format()
        .ok()?
        .decode()
        .ok()?;
    let (w0, h0) = (img.width(), img.height());
    let max_dim = 320u32;
    let rgba = if w0 > max_dim || h0 > max_dim {
        let scale = (max_dim as f64 / w0.max(h0) as f64).min(1.0);
        let nw = ((w0 as f64) * scale).round() as u32;
        let nh = ((h0 as f64) * scale).round() as u32;
        image::imageops::resize(
            &img.to_rgba8(),
            nw,
            nh,
            image::imageops::FilterType::Lanczos3,
        )
    } else {
        img.to_rgba8()
    };
    let tw = rgba.width();
    let th = rgba.height();
    let rgb = image::DynamicImage::ImageRgba8(rgba).to_rgb8();
    let mut out = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut out);
    rgb.write_to(&mut cursor, image::ImageFormat::Jpeg).ok()?;
    let len = out.len();
    Some((out, tw, th, len))
}

/// First page of a PDF → JPEG (~480px wide).
pub fn try_pdf_first_page_jpeg(data: &[u8]) -> Option<(Vec<u8>, u32, u32, usize)> {
    let pdfium = bind_pdfium()?;
    let document = pdfium.load_pdf_from_byte_slice(data, None).ok()?;
    if document.pages().is_empty() {
        return None;
    }
    let page = document.pages().get(0_u16).ok()?;
    let cfg = PdfRenderConfig::new()
        .set_target_width(480)
        .set_maximum_height(480);
    let rendered = page.render_with_config(&cfg).ok()?;
    let dyn_img = rendered.as_image();
    let rgb = dyn_img.into_rgb8();
    let tw = rgb.width();
    let th = rgb.height();
    let mut out = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut out);
    rgb.write_to(&mut cursor, image::ImageFormat::Jpeg).ok()?;
    let len = out.len();
    Some((out, tw, th, len))
}

fn is_ooxml_or_odf_media_path(name: &str) -> bool {
    (name.starts_with("word/media/")
        || name.starts_with("ppt/media/")
        || name.starts_with("xl/media/")
        || name.starts_with("Pictures/"))
        && (name.ends_with(".png")
            || name.ends_with(".jpg")
            || name.ends_with(".jpeg")
            || name.ends_with(".webp")
            || name.ends_with(".gif"))
}

/// First suitable image inside docx / pptx / xlsx / ODF zips.
pub fn try_package_embedded_image_thumbnail(path: &Path) -> Option<(Vec<u8>, u32, u32, usize)> {
    let file = std::fs::File::open(path).ok()?;
    let reader = std::io::BufReader::new(file);
    let mut archive = zip::ZipArchive::new(reader).ok()?;

    let mut names: Vec<String> = (0..archive.len())
        .filter_map(|i| archive.by_index(i).ok().map(|z| z.name().to_string()))
        .filter(|n| is_ooxml_or_odf_media_path(n))
        .collect();
    names.sort();

    for name in names {
        let mut zf = archive.by_name(&name).ok()?;
        let mut buf = Vec::new();
        zf.read_to_end(&mut buf).ok()?;
        if let Some(t) = try_raster_thumbnail_from_bytes(&buf) {
            return Some(t);
        }
    }

    for name in ["Thumbnails/thumbnail.png", "Thumbnails/thumbnail.jpg"] {
        let mut zf = archive.by_name(name).ok()?;
        let mut buf = Vec::new();
        zf.read_to_end(&mut buf).ok()?;
        if let Some(t) = try_raster_thumbnail_from_bytes(&buf) {
            return Some(t);
        }
    }

    None
}

/// Scan raw bytes for an embedded JPEG (OLE / zip aggregate). Used when `.ppt` / legacy `.doc`
/// do not expose images via normal package paths.
fn try_first_jpeg_thumbnail_in_bytes(data: &[u8], max_scan: usize) -> Option<(Vec<u8>, u32, u32, usize)> {
    let n = data.len().min(max_scan);
    let mut i = 0usize;
    while i + 3 < n {
        if data[i] == 0xFF && data[i + 1] == 0xD8 && data[i + 2] == 0xFF {
            let tail = &data[i..n];
            if let Some(rel_end) = tail.windows(2).position(|w| w[0] == 0xFF && w[1] == 0xD9) {
                let end = i + rel_end + 2;
                let slice = &data[i..end];
                if (500..=12_000_000).contains(&slice.len()) {
                    if let Some(t) = try_raster_thumbnail_from_bytes(slice) {
                        return Some(t);
                    }
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }
    None
}

/// PDF first page, else first image in office zip, else `None`.
pub fn try_document_thumbnail(
    path: &Path,
    mime_type: &Mime,
    file_bytes: &[u8],
) -> Option<(Vec<u8>, u32, u32, usize)> {
    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .unwrap_or("")
        .to_lowercase();
    let is_pdf = ext == "pdf" || mime_type.subtype().as_str() == "pdf";
    if is_pdf {
        if let Some(t) = try_pdf_first_page_jpeg(file_bytes) {
            return Some(t);
        }
    }

    let ooxml_ext = matches!(
        ext.as_str(),
        "docx" | "pptx" | "xlsx" | "xlsm" | "pptm" | "docm" | "ods" | "odp" | "odt"
    );
    let ooxml_mime = mime_type.subtype().as_str().contains("officedocument")
        || mime_type.subtype().as_str().contains("opendocument");
    if ooxml_ext || ooxml_mime {
        if let Some(t) = try_package_embedded_image_thumbnail(path) {
            return Some(t);
        }
        if let Some(t) = try_first_jpeg_thumbnail_in_bytes(file_bytes, file_bytes.len().min(8 * 1024 * 1024))
        {
            return Some(t);
        }
    }

    let legacy_office = matches!(ext.as_str(), "ppt" | "doc" | "xls");
    if legacy_office {
        if let Some(t) = try_first_jpeg_thumbnail_in_bytes(file_bytes, file_bytes.len().min(16 * 1024 * 1024))
        {
            return Some(t);
        }
    }

    None
}

#[cfg(test)]
mod attachment_thumbnail_tests {
    use super::*;
    use std::io::Cursor;
    use std::path::PathBuf;

    #[test]
    fn raster_thumbnail_from_png_bytes_returns_jpeg() {
        let img = image::DynamicImage::ImageRgba8(image::RgbaImage::from_pixel(
            80,
            60,
            image::Rgba([10u8, 120u8, 200u8, 255u8]),
        ));
        let mut png = Vec::new();
        img.write_to(&mut Cursor::new(&mut png), image::ImageFormat::Png)
            .expect("encode png");

        let (jpeg, w, h, len) =
            try_raster_thumbnail_from_bytes(&png).expect("thumbnail");

        assert!(w > 0 && h > 0);
        assert!(len > 100);
        assert!(jpeg.starts_with(&[0xff, 0xd8, 0xff]));
    }

    /// PDF first page needs Pdfium at runtime; empty input must not panic.
    #[test]
    fn pdf_first_page_empty_yields_none_without_crash() {
        assert!(try_pdf_first_page_jpeg(&[]).is_none());
    }

    #[test]
    fn document_thumbnail_non_pdf_non_office_yields_none() {
        let p = PathBuf::from("notes.txt");
        let mime: Mime = "text/plain".parse().unwrap();
        let t = try_document_thumbnail(&p, &mime, b"hello");
        assert!(t.is_none());
    }
}

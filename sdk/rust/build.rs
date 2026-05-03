//! Ensure WebRTC / LiveKit static ObjC (categories on NSString, H264 helpers, etc.) is linked.
//! Without `-ObjC`, iOS Simulator and macOS 26+ often crash at load with
//! `doesNotRecognizeSelector` inside `RTCH264ProfileLevelId` or codec setup
//! (see <https://github.com/livekit/rust-sdks/issues/795>).
//!
//! Android: `libwebrtc.a` JNI entrypoints (e.g. `Java_livekit_org_webrtc_SoftwareVideoEncoderFactory_*`)
//! must survive the **final** `cdylib` link. `webrtc-sys`'s build script emits `-Wl,--undefined=…` and
//! a version script, but those are not always applied when linking the top-level `matrix` shared
//! library, so the linker drops the symbols and Java fails with `UnsatisfiedLinkError`.

fn main() {
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if matches!(os.as_str(), "macos" | "ios") {
        println!("cargo:rustc-link-arg=-ObjC");
    }
    if os == "android" {
        webrtc_sys_build::configure_jni_symbols()
            .expect("webrtc_sys_build::configure_jni_symbols (Android JNI exports)");
    }
}

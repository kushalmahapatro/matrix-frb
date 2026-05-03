//! Initializes rustls-platform-verifier on Android before any TLS connection.
//! Caches [`jni::JavaVM`] for **libwebrtc** [`livekit::webrtc::android::initialize_android`].
//!
//! `webrtc::InitAndroid` must run on the **Android main thread** so JNI `FindClass` sees the app
//! `ClassLoader` (calling it from a `tokio` worker gives `ClassNotFoundException` for
//! `livekit.org.jni_zero.JniInit`). Use [`Java_dev_inve_matrixchat_WebRtcAndroidInit_init`] from
//! Kotlin after `FlutterActivity.super.onCreate`.
//!
//! [`RustlsInit.init`] must still run first (with application `Context`) to cache the `JavaVM`.

#![cfg(target_os = "android")]

use std::ffi::c_void;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::OnceLock;

/// Filled by [`Java_dev_inve_matrixchat_RustlsInit_init`].
static ANDROID_JAVA_VM: OnceLock<jni::JavaVM> = OnceLock::new();

static ANDROID_WEBRTC_INIT: std::sync::Once = std::sync::Once::new();
static ANDROID_WEBRTC_INITIALIZED: AtomicBool = AtomicBool::new(false);

/// JNI entrypoint: called from Kotlin `RustlsInit.init(context)`.
/// Initializes the platform certificate verifier so HTTPS works on Android.
///
/// Signature matches JNI native method `init(Landroid/content/Context;)V` on
/// class `dev.inve.matrixchat.RustlsInit`.
#[no_mangle]
pub unsafe extern "C" fn Java_dev_inve_matrixchat_RustlsInit_init(
    raw_env: *mut c_void,
    _class: *mut c_void,
    raw_context: *mut c_void,
) {
    let result = android_init(raw_env, raw_context);
    if let Err(e) = result {
        log::error!("rustls-platform-verifier init failed: {:?}", e);
    }
}

fn android_init(raw_env: *mut c_void, raw_context: *mut c_void) -> Result<(), jni::errors::Error> {
    let mut env = unsafe { jni::JNIEnv::from_raw(raw_env as *mut jni::sys::JNIEnv) }?;
    let context = unsafe { jni::objects::JObject::from_raw(raw_context as jni::sys::jobject) };
    rustls_platform_verifier::android::init_with_env(&mut env, context)?;

    let vm = env.get_java_vm()?;
    let _ = ANDROID_JAVA_VM.set(vm);

    Ok(())
}

/// Set after a successful main-thread [`Java_dev_inve_matrixchat_WebRtcAndroidInit_init`].
pub(crate) fn webrtc_android_initialized() -> bool {
    ANDROID_WEBRTC_INITIALIZED.load(Ordering::Acquire)
}

/// JNI: `dev.inve.matrixchat.WebRtcAndroidInit.init()` — call once from the **main** thread after
/// `super.onCreate` (same activity as [`Java_dev_inve_matrixchat_RustlsInit_init`]).
#[no_mangle]
pub unsafe extern "C" fn Java_dev_inve_matrixchat_WebRtcAndroidInit_init(
    _raw_env: *mut c_void,
    _class: *mut c_void,
) {
    ANDROID_WEBRTC_INIT.call_once(|| {
        let Some(vm) = ANDROID_JAVA_VM.get() else {
            log::error!("WebRtcAndroidInit.init: JavaVM not cached; call RustlsInit.init first");
            return;
        };
        livekit::webrtc::android::initialize_android(vm);
        ANDROID_WEBRTC_INITIALIZED.store(true, Ordering::Release);
    });
}

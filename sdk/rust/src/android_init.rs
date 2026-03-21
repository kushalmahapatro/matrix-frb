//! Initializes rustls-platform-verifier on Android before any TLS connection.
//! Must be called from the app's MainActivity (or similar) with the application
//! Context, before any code path that uses the Matrix SDK / network.

#![cfg(target_os = "android")]

use std::ffi::c_void;

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
    Ok(())
}

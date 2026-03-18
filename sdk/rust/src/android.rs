//! Android-specific initialization. Must run before any TLS/HTTP (e.g. Matrix) uses the platform verifier.

use jni::objects::JObject;
use jni::sys::{jclass, jobject, JNIEnv};
use jni::JNIEnv as JNIEnvWrapper;

/// JNI entry point: initializes rustls-platform-verifier with the Android context.
/// Called from Kotlin `RustlsInit.initVerifier(context)` so TLS uses the system trust store.
///
/// Symbol name must match exactly: Java_<package>_<Class>_<method>
#[no_mangle]
pub unsafe extern "C" fn Java_dev_inve_matrixchat_RustlsInit_initVerifier(
    env: *mut JNIEnv,
    _class: jclass,
    context: jobject,
) {
    if env.is_null() || context.is_null() {
        return;
    }
    let Ok(mut env) = JNIEnvWrapper::from_raw(env) else {
        return;
    };
    let context = JObject::from_raw(context);
    if let Err(e) = rustls_platform_verifier::android::init_with_env(&mut env, context) {
        let _ = env.throw_new(
            "java/lang/IllegalStateException",
            format!("rustls-platform-verifier init failed: {}", e),
        );
    }
}

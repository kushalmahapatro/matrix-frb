package dev.inve.matrixchat

/**
 * Runs libwebrtc `InitAndroid` on the **main thread** via JNI.
 *
 * Must be called after [RustlsInit.init] and [FlutterActivity.onCreate] (`super.onCreate`), so the
 * app `ClassLoader` is correct for JNI (calling this from a `tokio` worker crashes with
 * `ClassNotFoundException` for `livekit.org.jni_zero.JniInit`).
 */
object WebRtcAndroidInit {
    init {
        System.loadLibrary("matrix")
    }

    @JvmStatic
    external fun init()
}

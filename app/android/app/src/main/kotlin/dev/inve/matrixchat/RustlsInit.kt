package dev.inve.matrixchat

import android.content.Context

/**
 * Initializes rustls-platform-verifier for TLS certificate verification on Android.
 * Must be called before any Matrix SDK / network usage (e.g. in MainActivity.onCreate).
 */
object RustlsInit {
    init {
        System.loadLibrary("matrix")
    }

    /**
     * Call with application context (e.g. applicationContext) before making any HTTPS requests.
     */
    @JvmStatic
    external fun init(context: Context)
}

package dev.inve.matrixchat

import android.content.Context

/**
 * Initializes rustls-platform-verifier with the Android context so TLS uses the system trust store.
 * Must be called before any HTTP/TLS (e.g. Matrix) runs.
 */
object RustlsInit {
    init {
        System.loadLibrary("matrix")
    }

    @JvmStatic
    external fun initVerifier(context: Context)
}

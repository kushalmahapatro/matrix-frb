package dev.inve.matrixchat

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        // Initialize rustls-platform-verifier before Flutter/Matrix run so TLS uses system certs.
        RustlsInit.initVerifier(applicationContext)
        super.onCreate(savedInstanceState)
    }
}

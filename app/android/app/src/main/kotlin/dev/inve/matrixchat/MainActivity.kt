package dev.inve.matrixchat

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        RustlsInit.init(applicationContext)
        super.onCreate(savedInstanceState)
        WebRtcAndroidInit.init()
        captureCallAcceptIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureCallAcceptIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "dev.inve.matrixchat/native_media",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getNativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_LAUNCH_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "takePendingCallAccept" -> {
                    synchronized(pendingLock) {
                        val p = pendingCallAccept
                        pendingCallAccept = null
                        result.success(p)
                    }
                }
                "finishCallOnlyTask" -> {
                    runOnUiThread {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                            finishAffinity()
                        } else {
                            finish()
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun captureCallAcceptIntent(intent: Intent?) {
        if (intent == null) return
        if (intent.action != ACTION_CALL_ACCEPT) return
        val data = intent.getBundleExtra(EXTRA_CALLKIT_CALL_DATA) ?: return
        val payload = buildCallAcceptPayload(data) ?: return
        synchronized(pendingLock) {
            pendingCallAccept = payload
        }
    }

    companion object {
        private const val APP_LAUNCH_CHANNEL = "dev.inve.matrixchat/app_launch"
        private const val EXTRA_CALLKIT_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"
        private const val EXTRA_CALLKIT_ID = "EXTRA_CALLKIT_ID"
        private const val EXTRA_CALLKIT_EXTRA = "EXTRA_CALLKIT_EXTRA"
        private const val ACTION_CALL_ACCEPT =
            "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"

        private val pendingLock = Any()
        private var pendingCallAccept: HashMap<String, Any?>? = null

        private fun buildCallAcceptPayload(data: Bundle): HashMap<String, Any?>? {
            val id = data.getString(EXTRA_CALLKIT_ID) ?: return null
            @Suppress("DEPRECATION")
            val rawExtra = data.getSerializable(EXTRA_CALLKIT_EXTRA) as? HashMap<*, *> ?: return null
            val roomId = rawExtra["roomId"]?.toString() ?: return null
            if (roomId.isEmpty()) return null
            val rtcEventId = rawExtra["rtcEventId"]?.toString() ?: ""
            var roomName = rawExtra["roomName"]?.toString() ?: ""
            if (roomName.isEmpty()) roomName = roomId
            return HashMap(
                mapOf(
                    "callKitId" to id,
                    "roomId" to roomId,
                    "rtcEventId" to rtcEventId,
                    "roomName" to roomName,
                ),
            )
        }
    }
}

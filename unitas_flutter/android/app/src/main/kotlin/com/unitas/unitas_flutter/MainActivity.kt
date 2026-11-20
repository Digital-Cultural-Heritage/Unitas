package com.unitas.unitas_flutter

import android.os.Bundle
import com.unitas.security.SecurityCheck
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SECURITY_CHANNEL = "com.unitas/security"
    }

    private var securityChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        )
        securityChannel = channel

        // Daftarkan MethodChannel handler untuk root check & anti-debug init on demand
        SecurityCheck.registerWith(channel, packageManager) {
            // Callback ketika foreign debugger terdeteksi di native monitor thread
            runOnUiThread {
                channel.invokeMethod("onDebuggerDetected", null)
            }
        }
    }
}

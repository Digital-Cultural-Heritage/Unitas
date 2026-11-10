package com.unitas.unitas_flutter

import android.os.Bundle
import android.os.Process
import com.unitas.security.SecurityCheck
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val SECURITY_CHANNEL = "com.unitas/security"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Anti-debug init dilakukan sedini mungkin, sebelum UI apapun dirender
        SecurityCheck.startAntiDebug {
            // Callback dijalankan di main thread → kirim sinyal shutdown ke Flutter
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, SECURITY_CHANNEL)
                    .invokeMethod("onDebuggerDetected", null)
            }
            // Hard kill sebagai fallback jika Flutter layer sudah ter-bypass
            Process.killProcess(Process.myPid())
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SECURITY_CHANNEL
        )

        // Daftarkan handler isRooted & getTracerPid
        SecurityCheck.registerWith(channel, packageManager)
    }
}

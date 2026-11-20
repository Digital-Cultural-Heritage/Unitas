package com.unitas.unitas_flutter

import android.os.Bundle
import com.unitas.security.SecurityCheck
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        private const val SECURITY_CHANNEL = "com.unitas/security"
    }

    private var securityChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Thread { cleanStaleCache() }.start()
    }

    private fun cleanStaleCache() {
        try {
            val cutoffMs = System.currentTimeMillis() - 60_000L
            deleteChildrenIfOlder(cacheDir, cutoffMs, skipNames = setOf("flutter_engine"))
            externalCacheDir?.let { deleteChildrenIfOlder(it, cutoffMs) }
            codeCacheDir.listFiles()?.forEach { f ->
                val name = f.name
                if ((name.endsWith(".bin") || name.endsWith(".tmp") || name.contains("shader")) &&
                    f.lastModified() < cutoffMs
                ) {
                    f.deleteRecursively()
                }
            }
        } catch (_: Throwable) {
            // Abaikan error pembersihan cache agar startup tidak terganggu
        }
    }

    private fun deleteChildrenIfOlder(
        dir: File,
        cutoffMs: Long,
        skipNames: Set<String> = emptySet()
    ) {
        val children = dir.listFiles() ?: return
        for (child in children) {
            if (child.name in skipNames) continue
            if (child.isDirectory) {
                deleteChildrenIfOlder(child, cutoffMs, skipNames)
                if (child.listFiles()?.isEmpty() == true) {
                    child.delete()
                }
            } else if (child.lastModified() < cutoffMs) {
                child.delete()
            }
        }
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

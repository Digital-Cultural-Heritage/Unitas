package com.unitas.security

import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * SecurityCheck — JNI bridge antara libsecurity.so dan Flutter MethodChannel.
 *
 * Channel: "com.unitas/security"
 * Methods:
 *   - "isRooted"      → Boolean
 *   - "initAntiDebug" → Unit (fire-and-forget)
 *   - "getTracerPid"  → Int
 */
object SecurityCheck {

    private const val TAG = "UnitasSec"

    // ── Load native library ───────────────────────────────────────────────
    init {
        try {
            System.loadLibrary("security")
            Log.i(TAG, "libsecurity.so loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "Failed to load libsecurity.so: ${e.message}")
        }
    }

    // ── JNI declarations ──────────────────────────────────────────────────

    /**
     * @param rootPackages Array of installed root-related package names
     *                     (queried by PackageManager before calling native).
     * @return true if any root indicator found.
     */
    @JvmStatic
    external fun isDeviceRooted(rootPackages: Array<String>): Boolean

    /**
     * Inisialisasi anti-debug protection di native layer.
     */
    @JvmStatic
    external fun initAntiDebug(callback: SecurityCallback)

    /**
     * Membaca TracerPid dari /proc/self/status.
     * Mengembalikan 0 jika bersih, >0 jika sedang di-trace debugger.
     */
    @JvmStatic
    external fun getTracerPid(): Int

    // ── Root packages to check via PackageManager ────────────────────────
    private val ROOT_PACKAGES = arrayOf(
        "com.topjohnwu.magisk",
        "eu.chainfire.supersu",
        "com.noshufou.android.su",
        "com.koushikdutta.superuser",
        "com.zachspong.temprootremovejb",
        "com.ramdroid.appquarantine",
        "com.formyhm.hiddencamera"
    )

    // ── Public API ───────────────────────────────────────────────────────

    fun checkRooted(pm: PackageManager): Boolean {
        val installedRootPkgs = ROOT_PACKAGES.filter { pkg ->
            try {
                pm.getPackageInfo(pkg, 0)
                true
            } catch (_: PackageManager.NameNotFoundException) {
                false
            }
        }

        if (installedRootPkgs.isNotEmpty()) {
            Log.w(TAG, "Root packages found: $installedRootPkgs")
        }

        return try {
            isDeviceRooted(installedRootPkgs.toTypedArray())
        } catch (e: Throwable) {
            Log.e(TAG, "Error executing native isDeviceRooted: ${e.message}")
            false
        }
    }

    fun startAntiDebug(onDebuggerDetected: () -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        val callback = object : SecurityCallback {
            override fun onDebuggerDetected() {
                Log.e(TAG, "Foreign debugger detected — invoking callback")
                handler.post { onDebuggerDetected() }
            }
        }
        try {
            initAntiDebug(callback)
        } catch (e: Throwable) {
            Log.e(TAG, "Error executing native initAntiDebug: ${e.message}")
        }
    }

    /**
     * Register MethodChannel handler dengan opsional callback onDebuggerDetected.
     */
    fun registerWith(
        channel: MethodChannel,
        pm: PackageManager,
        onDebuggerDetected: (() -> Unit)? = null
    ) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isRooted" -> {
                    result.success(checkRooted(pm))
                }
                "initAntiDebug" -> {
                    if (onDebuggerDetected != null) {
                        startAntiDebug(onDebuggerDetected)
                    } else {
                        startAntiDebug {
                            channel.invokeMethod("onDebuggerDetected", null)
                        }
                    }
                    result.success(true)
                }
                "getTracerPid" -> {
                    try {
                        result.success(getTracerPid())
                    } catch (e: Throwable) {
                        result.success(0)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}

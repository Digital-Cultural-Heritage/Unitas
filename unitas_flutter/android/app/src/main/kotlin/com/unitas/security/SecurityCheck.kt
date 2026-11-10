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
 */
object SecurityCheck {

    private const val TAG = "UnitasSec"

    // ── Load native library ───────────────────────────────────────────────
    init {
        System.loadLibrary("security")
        Log.i(TAG, "libsecurity.so loaded")
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
     * Forks a child that PTRACE_ATTACH to parent, and starts a monitor
     * thread that fires [callback].onDebuggerDetected() if a foreign
     * tracer is detected.
     */
    @JvmStatic
    external fun initAntiDebug(callback: SecurityCallback)

    /**
     * Reads TracerPid from /proc/self/status.
     * Returns 0 if no tracer, >0 if traced.
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

    /**
     * Performs full root check:
     *  1. Query PackageManager for known root packages.
     *  2. Delegate remaining checks to native code.
     *
     * Must be called after [PackageManager] is available (i.e., after Activity created).
     */
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

        return isDeviceRooted(installedRootPkgs.toTypedArray())
    }

    /**
     * Initialises the fork+ptrace anti-debug protection.
     * [onDebuggerDetected] will be called on the main thread when a
     * foreign debugger is detected.
     */
    fun startAntiDebug(onDebuggerDetected: () -> Unit) {
        val handler = Handler(Looper.getMainLooper())
        val callback = object : SecurityCallback {
            override fun onDebuggerDetected() {
                Log.e(TAG, "Foreign debugger detected — shutting down")
                handler.post { onDebuggerDetected() }
            }
        }
        initAntiDebug(callback)
    }

    /**
     * Register the MethodChannel handler.
     * Call this from MainActivity / FlutterEngine setup.
     */
    fun registerWith(channel: MethodChannel, pm: PackageManager) {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isRooted" -> {
                    result.success(checkRooted(pm))
                }
                "getTracerPid" -> {
                    result.success(getTracerPid())
                }
                else -> result.notImplemented()
            }
        }
    }
}


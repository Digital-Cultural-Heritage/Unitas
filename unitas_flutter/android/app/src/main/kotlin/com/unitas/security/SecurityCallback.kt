package com.unitas.security

/**
 * Callback interface implemented in Kotlin, passed into native code.
 * Native monitor thread calls [onDebuggerDetected] when a foreign debugger
 * is detected via TracerPid mismatch.
 */
interface SecurityCallback {
    fun onDebuggerDetected()
}


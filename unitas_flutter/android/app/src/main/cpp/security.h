#pragma once

#include <jni.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Obfuscated string XOR helper.
 * key = 0x5A. Strings are encoded at compile-time with the same key.
 */
static inline void deobf(const unsigned char *in, char *out, int len) {
    for (int i = 0; i < len; i++) out[i] = (char)(in[i] ^ 0x5A);
    out[len] = '\0';
}

/* ── Root Detection ───────────────────────────────────────────────────────── */
JNIEXPORT jboolean JNICALL
Java_com_unitas_security_SecurityCheck_isDeviceRooted(JNIEnv *env, jclass clazz,
                                                       jobjectArray rootPackages);

/* ── Anti-Debug init ─────────────────────────────────────────────────────── */
JNIEXPORT void JNICALL
Java_com_unitas_security_SecurityCheck_initAntiDebug(JNIEnv *env, jclass clazz,
                                                      jobject callbackObj);

/* ── Tracer PID check (called from background monitor thread) ──────────────  */
JNIEXPORT jint JNICALL
Java_com_unitas_security_SecurityCheck_getTracerPid(JNIEnv *env, jclass clazz);

#ifdef __cplusplus
}
#endif


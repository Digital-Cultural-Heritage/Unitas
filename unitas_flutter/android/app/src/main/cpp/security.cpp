/**
 * security.cpp — Unitas Native Security Module (v2 — Stable Anti-Debug)
 *
 * Anti-debug diganti dari fork+ptrace (tidak kompatibel SELinux Android modern)
 * menjadi tiga metode pasif yang stabil:
 *   1. PTRACE_TRACEME  → gagal dengan EPERM jika sudah ada tracer asing
 *   2. TracerPid check → polling /proc/self/status secara periodik
 *   3. Callback aman   → native hanya mengirim sinyal, Flutter yang memutuskan flow
 */

#include "security.h"

#include <jni.h>
#include <android/log.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <pthread.h>
#include <signal.h>
#include <cerrno>
#include <fcntl.h>

/* ── Logging ─────────────────────────────────────────────────────────────── */
#define TAG  "UnitasSec"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

/* ── XOR obfuscation key ─────────────────────────────────────────────────── */
#define K 0x5A
#define E(c) (static_cast<unsigned char>((c) ^ K))

/* ── Obfuscated string table ─────────────────────────────────────────────── */

/* su binary paths */
static const unsigned char _su0[] = { E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su1[] = { E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su2[] = { E('/'),E('s'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su3[] = { E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),E('s'),E('d'),E('/'),E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su4[] = { E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),E('b'),E('i'),E('n'),E('/'),E('.'),E('e'),E('x'),E('t'),E('/'),E('.'),E('s'),E('u') };
static const unsigned char _su5[] = { E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su6[] = { E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u') };
static const unsigned char _su7[] = { E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),E('s'),E('u') };

/* "ro.build.tags" */
static const unsigned char _prop_tags[]    = { E('r'),E('o'),E('.'),E('b'),E('u'),E('i'),E('l'),E('d'),E('.'),E('t'),E('a'),E('g'),E('s') };
/* "test-keys" */
static const unsigned char _test_keys[]    = { E('t'),E('e'),E('s'),E('t'),E('-'),E('k'),E('e'),E('y'),E('s') };
/* "busybox" */
static const unsigned char _busybox[]      = { E('b'),E('u'),E('s'),E('y'),E('b'),E('o'),E('x') };
/* "/proc/self/status" */
static const unsigned char _proc_status[]  = { E('/'),E('p'),E('r'),E('o'),E('c'),E('/'),E('s'),E('e'),E('l'),E('f'),E('/'),E('s'),E('t'),E('a'),E('t'),E('u'),E('s') };
/* "TracerPid:" */
static const unsigned char _tracer_field[] = { E('T'),E('r'),E('a'),E('c'),E('e'),E('r'),E('P'),E('i'),E('d'),E(':') };

/* ── Deobfuscate helper ───────────────────────────────────────────────────── */
static void deobf_internal(const unsigned char *in, char *out, int len) {
    for (int i = 0; i < len; i++) out[i] = static_cast<char>(in[i] ^ K);
    out[len] = '\0';
}
#define DEOBF(arr, buf) deobf_internal((arr), (buf), static_cast<int>(sizeof(arr)))

/* ══════════════════════════════════════════════════════════════════════════
 * BAGIAN 1 — ROOT DETECTION
 * ══════════════════════════════════════════════════════════════════════════ */

static bool check_su_binaries() {
    char path[64];
    struct stat st;
    struct SuPath { const unsigned char *data; int len; };
    const SuPath paths[] = {
        { _su0, (int)sizeof(_su0) }, { _su1, (int)sizeof(_su1) },
        { _su2, (int)sizeof(_su2) }, { _su3, (int)sizeof(_su3) },
        { _su4, (int)sizeof(_su4) }, { _su5, (int)sizeof(_su5) },
        { _su6, (int)sizeof(_su6) }, { _su7, (int)sizeof(_su7) },
    };
    for (const auto &p : paths) {
        deobf_internal(p.data, path, p.len);
        if (stat(path, &st) == 0) { LOGW("su found: %s", path); return true; }
    }
    return false;
}

static bool check_build_tags() {
    char prop_name[32], test_keys_str[16], value[128] = {};
    DEOBF(_prop_tags,  prop_name);
    DEOBF(_test_keys,  test_keys_str);
    extern int __system_property_get(const char *name, char *value);
    __system_property_get(prop_name, value);
    if (strstr(value, test_keys_str)) { LOGW("test-keys build: %s", value); return true; }
    return false;
}

static bool check_path_busybox() {
    char busybox[16];
    DEOBF(_busybox, busybox);
    const char *p = getenv("PATH");
    if (p && strstr(p, busybox)) { LOGW("busybox in PATH"); return true; }
    return false;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_unitas_security_SecurityCheck_isDeviceRooted(JNIEnv *env, jclass,
                                                       jobjectArray rootPackages) {
    if (check_su_binaries())  return JNI_TRUE;
    if (check_build_tags())   return JNI_TRUE;
    if (check_path_busybox()) return JNI_TRUE;

    // Packages terdeteksi dari Kotlin PackageManager
    if (rootPackages && env->GetArrayLength(rootPackages) > 0) {
        LOGW("Root package found via PM");
        return JNI_TRUE;
    }

    // /system writable check
    int fd = open("/system/.unitas_rwtest", O_CREAT | O_WRONLY, 0644);
    if (fd >= 0) {
        close(fd); unlink("/system/.unitas_rwtest");
        LOGW("/system is rw");
        return JNI_TRUE;
    }

    return JNI_FALSE;
}

/* ══════════════════════════════════════════════════════════════════════════
 * BAGIAN 2 — ANTI-DEBUG (Pasif, SELinux-safe, tidak fork)
 *
 * Strategi:
 *   A. PTRACE_TRACEME: jika sudah ada debugger aktif → EPERM langsung
 *   B. Monitor thread: polling TracerPid tiap 5 detik
 *      Jika TracerPid > 0 → ada debugger eksternal → callback ke Flutter
 *
 * TIDAK ada fork(), tidak ada PTRACE_ATTACH ke PID lain.
 * Semua operasi dalam PID proses sendiri → aman dari SELinux Android.
 * ══════════════════════════════════════════════════════════════════════════ */

struct AntiDebugCtx {
    JavaVM  *jvm          = nullptr;
    jobject  callback_ref = nullptr;   // global ref
    bool     active       = false;     // monitor thread hidup?
};
static AntiDebugCtx g_ctx;

/* Baca TracerPid dari /proc/self/status */
static int read_tracer_pid() {
    char path[32], field[16];
    DEOBF(_proc_status, path);
    DEOBF(_tracer_field, field);
    FILE *f = fopen(path, "r");
    if (!f) return 0;
    char line[128];
    int tracer = 0;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, field, strlen(field)) == 0) {
            sscanf(line + strlen(field), "%d", &tracer);
            break;
        }
    }
    fclose(f);
    return tracer;
}

/* Kirim callback ke Kotlin → Flutter */
static void fire_debug_callback() {
    if (!g_ctx.jvm || !g_ctx.callback_ref) {
        // Fallback langsung: matikan proses
        LOGE("No JVM callback — killing process");
        kill(getpid(), SIGKILL);
        return;
    }

    JNIEnv *env = nullptr;
    bool attached = false;
    JavaVMAttachArgs args{ JNI_VERSION_1_6,
                           const_cast<char*>("SecMonitor"), nullptr };

    if (g_ctx.jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        g_ctx.jvm->AttachCurrentThread(&env, &args);
        attached = true;
    }

    if (env) {
        jclass  cls = env->GetObjectClass(g_ctx.callback_ref);
        if (cls) {
            jmethodID mid = env->GetMethodID(cls, "onDebuggerDetected", "()V");
            if (mid) env->CallVoidMethod(g_ctx.callback_ref, mid);
        }
    }

    if (attached) g_ctx.jvm->DetachCurrentThread();

    // Beri waktu Flutter merender dialog sebelum force-kill
    sleep(2);
    kill(getpid(), SIGKILL);
}

/* Monitor thread — hanya polling, tidak fork, tidak ptrace orang lain */
static void *monitor_thread(void *) {
    // Jeda awal: beri waktu app bootstrap selesai agar TracerPid dari
    // flutter-tools / Android Studio sudah bersih (jika build release)
    sleep(5);

    while (g_ctx.active) {
        sleep(5);
        int tracer = read_tracer_pid();

        // TracerPid > 0 berarti ada proses lain yang melakukan ptrace ke kita.
        // Pada build release yang berjalan normal di device: TracerPid selalu 0.
        if (tracer > 0) {
            LOGE("Debugger detected! TracerPid = %d", tracer);
            g_ctx.active = false;
            fire_debug_callback();
            break;
        }
    }
    return nullptr;
}

extern "C" JNIEXPORT void JNICALL
Java_com_unitas_security_SecurityCheck_initAntiDebug(JNIEnv *env, jclass,
                                                      jobject callbackObj) {
    env->GetJavaVM(&g_ctx.jvm);

    if (callbackObj) {
        g_ctx.callback_ref = env->NewGlobalRef(callbackObj);
    }

    /* ── A. PTRACE_TRACEME ──────────────────────────────────────────────
     * Jika ada debugger yang sudah aktif men-trace proses ini,
     * PTRACE_TRACEME akan gagal dengan errno == EPERM.
     * Ini AMAN: tidak ptrace proses lain, hanya self-declaration.
     * SELinux mengizinkan ini untuk proses yang men-trace dirinya sendiri. */
    long ret = ptrace(PTRACE_TRACEME, 0, nullptr, nullptr);
    if (ret == -1 && errno == EPERM) {
        LOGE("PTRACE_TRACEME failed: debugger already attached");
        // Langsung fire callback tanpa menunggu monitor thread
        fire_debug_callback();
        return;
    }
    // Jika berhasil, detach diri sendiri agar tidak mempengaruhi normal execution
    ptrace(PTRACE_DETACH, 0, nullptr, nullptr);

    /* ── B. Start background monitor thread ─────────────────────────── */
    g_ctx.active = true;
    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, monitor_thread, nullptr);
    pthread_attr_destroy(&attr);

    LOGI("Anti-debug monitor started (passive mode)");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_unitas_security_SecurityCheck_getTracerPid(JNIEnv *, jclass) {
    return static_cast<jint>(read_tracer_pid());
}

JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *) {
    g_ctx.jvm = vm;
    LOGI("libsecurity.so loaded");
    return JNI_VERSION_1_6;
}

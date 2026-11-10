/**
 * security.cpp — Unitas Native Security Module
 *
 * Kompilasi sebagai libsecurity.so via Android NDK + CMake.
 * Fungsi JNI:
 *   1. isDeviceRooted   — multi-indicator root detection
 *   2. initAntiDebug    — fork+ptrace self-attach anti-debugging
 *   3. getTracerPid     — membaca /proc/self/status → field TracerPid
 *
 * Catatan: file ini dikompilasi sebagai C++ → gunakan C++ JNI style:
 *   env->Method(arg)  bukan  (*env)->Method(env, arg)
 */

#include "security.h"

#include <jni.h>
#include <android/log.h>
#include <sys/ptrace.h>
#include <sys/wait.h>
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

/* Macro: encode a char literal with XOR key K */
#define E(c) (static_cast<unsigned char>((c) ^ K))

/* ── Obfuscated string table ─────────────────────────────────────────────── */

/* "/system/bin/su" */
static const unsigned char _su0[] = {
    E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),
    E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/system/xbin/su" */
static const unsigned char _su1[] = {
    E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),
    E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/sbin/su" */
static const unsigned char _su2[] = {
    E('/'),E('s'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/system/sd/xbin/su" */
static const unsigned char _su3[] = {
    E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),
    E('s'),E('d'),E('/'),E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/system/bin/.ext/.su" */
static const unsigned char _su4[] = {
    E('/'),E('s'),E('y'),E('s'),E('t'),E('e'),E('m'),E('/'),
    E('b'),E('i'),E('n'),E('/'),E('.'),E('e'),E('x'),E('t'),E('/'),E('.'),E('s'),E('u')
};
/* "/data/local/xbin/su" */
static const unsigned char _su5[] = {
    E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),
    E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),
    E('x'),E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/data/local/bin/su" */
static const unsigned char _su6[] = {
    E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),
    E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),
    E('b'),E('i'),E('n'),E('/'),E('s'),E('u')
};
/* "/data/local/su" */
static const unsigned char _su7[] = {
    E('/'),E('d'),E('a'),E('t'),E('a'),E('/'),
    E('l'),E('o'),E('c'),E('a'),E('l'),E('/'),E('s'),E('u')
};

/* "ro.build.tags" */
static const unsigned char _prop_tags[] = {
    E('r'),E('o'),E('.'),E('b'),E('u'),E('i'),E('l'),E('d'),E('.'),E('t'),E('a'),E('g'),E('s')
};
/* "test-keys" */
static const unsigned char _test_keys[] = {
    E('t'),E('e'),E('s'),E('t'),E('-'),E('k'),E('e'),E('y'),E('s')
};
/* "busybox" */
static const unsigned char _busybox[] = {
    E('b'),E('u'),E('s'),E('y'),E('b'),E('o'),E('x')
};
/* "/proc/self/status" */
static const unsigned char _proc_status[] = {
    E('/'),E('p'),E('r'),E('o'),E('c'),E('/'),
    E('s'),E('e'),E('l'),E('f'),E('/'),
    E('s'),E('t'),E('a'),E('t'),E('u'),E('s')
};
/* "TracerPid:" */
static const unsigned char _tracer_field[] = {
    E('T'),E('r'),E('a'),E('c'),E('e'),E('r'),E('P'),E('i'),E('d'),E(':')
};

/* ── Helper: deobfuscate ─────────────────────────────────────────────────── */
static void deobf_internal(const unsigned char *in, char *out, int len) {
    for (int i = 0; i < len; i++) out[i] = static_cast<char>(in[i] ^ K);
    out[len] = '\0';
}

#define DEOBF(arr, buf) deobf_internal((arr), (buf), static_cast<int>(sizeof(arr)))

/* ── 1. Root Detection Helpers ───────────────────────────────────────────── */

static bool check_su_binaries() {
    char path[64];
    struct stat st;

    struct SuPath { const unsigned char *data; int len; };
    const SuPath paths[] = {
        { _su0, static_cast<int>(sizeof(_su0)) },
        { _su1, static_cast<int>(sizeof(_su1)) },
        { _su2, static_cast<int>(sizeof(_su2)) },
        { _su3, static_cast<int>(sizeof(_su3)) },
        { _su4, static_cast<int>(sizeof(_su4)) },
        { _su5, static_cast<int>(sizeof(_su5)) },
        { _su6, static_cast<int>(sizeof(_su6)) },
        { _su7, static_cast<int>(sizeof(_su7)) },
    };

    for (const auto &p : paths) {
        deobf_internal(p.data, path, p.len);
        if (stat(path, &st) == 0) {
            LOGW("su binary found: %s", path);
            return true;
        }
    }
    return false;
}

static bool check_build_tags() {
    char prop_name[32];
    char test_keys_str[16];
    char value[128] = {};

    DEOBF(_prop_tags, prop_name);
    DEOBF(_test_keys, test_keys_str);

    // __system_property_get is available on all Android API levels
    extern int __system_property_get(const char *name, char *value);
    __system_property_get(prop_name, value);

    if (strstr(value, test_keys_str) != nullptr) {
        LOGW("Build tags suspicious: %s", value);
        return true;
    }
    return false;
}

static bool check_path_busybox() {
    char busybox[16];
    DEOBF(_busybox, busybox);

    const char *path_env = getenv("PATH");
    if (path_env && strstr(path_env, busybox) != nullptr) {
        LOGW("busybox found in PATH");
        return true;
    }
    return false;
}

/* ── 1. JNI: isDeviceRooted ─────────────────────────────────────────────── */
extern "C" JNIEXPORT jboolean JNICALL
Java_com_unitas_security_SecurityCheck_isDeviceRooted(JNIEnv *env, jclass /*clazz*/,
                                                       jobjectArray rootPackages) {
    // a. Check su binaries
    if (check_su_binaries()) return JNI_TRUE;

    // b. Check build tags
    if (check_build_tags()) return JNI_TRUE;

    // c. Check root packages array (pre-filtered by Kotlin PackageManager)
    if (rootPackages != nullptr) {
        // C++ JNI style: env->Method(args) — no env as first arg
        jsize len = env->GetArrayLength(rootPackages);
        if (len > 0) {
            LOGW("Root package detected via PackageManager (%d package(s))", len);
            return JNI_TRUE;
        }
    }

    // d. Check /system mount writable
    {
        int fd = open("/system/unitas_rw_test_xZ7", O_CREAT | O_WRONLY, 0644);
        if (fd >= 0) {
            close(fd);
            unlink("/system/unitas_rw_test_xZ7");
            LOGW("/system is writable → rooted");
            return JNI_TRUE;
        }
    }

    // e. Check PATH env for busybox
    if (check_path_busybox()) return JNI_TRUE;

    return JNI_FALSE;
}

/* ── 2. Anti-Debug: shared state ─────────────────────────────────────────── */

struct AntiDebugCtx {
    pid_t  parent_pid  = 0;
    pid_t  child_pid   = 0;
    JavaVM *jvm        = nullptr;
    jobject callback_ref = nullptr;   // global ref
};

static AntiDebugCtx g_ctx;

/* ── Read TracerPid from /proc/self/status ──────────────────────────────── */
static int read_tracer_pid() {
    char path[32];
    char field[16];
    DEOBF(_proc_status, path);
    DEOBF(_tracer_field, field);

    FILE *f = fopen(path, "r");
    if (!f) return -1;

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

/* ── Monitor thread: runs in parent, watches TracerPid ───────────────────── */
static void *monitor_thread(void *) {
    // Give child time to fully attach
    sleep(2);

    while (true) {
        sleep(3);
        int tracer = read_tracer_pid();

        // tracer == 0 → no tracer (child died)
        // tracer != child_pid → foreign debugger attached
        bool threat = (tracer == 0) ||
                      (g_ctx.child_pid > 0 && tracer != (int)g_ctx.child_pid);

        if (threat) {
            LOGE("Debugger detected! TracerPid=%d expected=%d", tracer, g_ctx.child_pid);

            if (g_ctx.jvm && g_ctx.callback_ref) {
                JNIEnv *env = nullptr;
                JavaVMAttachArgs args{ JNI_VERSION_1_6,
                                       const_cast<char*>("AntiDebugMonitor"),
                                       nullptr };
                bool attached = false;

                // C++ JavaVM style: jvm->Method(args)
                if (g_ctx.jvm->GetEnv(reinterpret_cast<void**>(&env),
                                       JNI_VERSION_1_6) != JNI_OK) {
                    g_ctx.jvm->AttachCurrentThread(&env, &args);
                    attached = true;
                }

                if (env) {
                    // C++ JNIEnv style: env->Method(args)
                    jclass cls = env->GetObjectClass(g_ctx.callback_ref);
                    if (cls) {
                        jmethodID mid = env->GetMethodID(cls,
                                                          "onDebuggerDetected", "()V");
                        if (mid) {
                            env->CallVoidMethod(g_ctx.callback_ref, mid);
                        }
                    }
                }

                if (attached) {
                    g_ctx.jvm->DetachCurrentThread();
                }
            }

            // Hard kill as final fallback
            sleep(1);
            kill(g_ctx.parent_pid, SIGKILL);
            break;
        }
    }
    return nullptr;
}

/* ── Child process: holds the ptrace slot ───────────────────────────────── */
static void child_tracer_loop(pid_t parent_pid) {
    if (ptrace(PTRACE_ATTACH, parent_pid, nullptr, nullptr) != 0) {
        _exit(1);
    }

    int status;
    if (waitpid(parent_pid, &status, 0) < 0) {
        _exit(1);
    }

    // Resume parent after SIGSTOP from PTRACE_ATTACH
    ptrace(PTRACE_CONT, parent_pid, nullptr, nullptr);

    // Loop: re-continue parent on every future stop
    while (true) {
        int ws = 0;
        pid_t ret = waitpid(parent_pid, &ws, 0);
        if (ret < 0 || WIFEXITED(ws) || WIFSIGNALED(ws)) {
            _exit(0);
        }
        int sig = WIFSTOPPED(ws) ? WSTOPSIG(ws) : 0;
        ptrace(PTRACE_CONT, parent_pid, nullptr,
               reinterpret_cast<void*>(static_cast<long>(sig)));
    }
}

/* ── 2. JNI: initAntiDebug ──────────────────────────────────────────────── */
extern "C" JNIEXPORT void JNICALL
Java_com_unitas_security_SecurityCheck_initAntiDebug(JNIEnv *env, jclass /*clazz*/,
                                                      jobject callbackObj) {
    // C++ JNIEnv style: env->GetJavaVM(...)
    env->GetJavaVM(&g_ctx.jvm);
    g_ctx.parent_pid = getpid();

    if (callbackObj != nullptr) {
        // C++ style: env->NewGlobalRef(obj)
        g_ctx.callback_ref = env->NewGlobalRef(callbackObj);
    }

    pid_t child = fork();
    if (child < 0) {
        LOGE("fork() failed: %s", strerror(errno));
        return;
    }

    if (child == 0) {
        // ── Child process ──
        child_tracer_loop(g_ctx.parent_pid);
        _exit(0);
    }

    // ── Parent process ──
    g_ctx.child_pid = child;
    LOGI("Anti-debug child pid: %d", child);

    pthread_t tid;
    pthread_attr_t attr;
    pthread_attr_init(&attr);
    pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
    pthread_create(&tid, &attr, monitor_thread, nullptr);
    pthread_attr_destroy(&attr);
}

/* ── 3. JNI: getTracerPid ───────────────────────────────────────────────── */
extern "C" JNIEXPORT jint JNICALL
Java_com_unitas_security_SecurityCheck_getTracerPid(JNIEnv * /*env*/, jclass /*clazz*/) {
    return static_cast<jint>(read_tracer_pid());
}

/* ── JNI_OnLoad ─────────────────────────────────────────────────────────── */
JNIEXPORT jint JNI_OnLoad(JavaVM *vm, void *) {
    g_ctx.jvm = vm;
    LOGI("libsecurity loaded");
    return JNI_VERSION_1_6;
}

cmake_minimum_required(VERSION 3.22.1)

project("unitas_security" LANGUAGES CXX)

# ── Compiler flags ─────────────────────────────────────────────────────────
# -O2            : optimise (makes string analysis harder)
# -fvisibility=hidden : hide all symbols except explicitly exported ones
# -fstack-protector-strong : stack smashing protection
# -D_FORTIFY_SOURCE=2 : buffer overflow detection
# -fno-rtti / -fno-exceptions : smaller binary, harder to reverse
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(
    -O2
    -fvisibility=hidden
    -fstack-protector-strong
    -D_FORTIFY_SOURCE=2
    -fno-rtti
    -fno-exceptions
    -Wall
)

# ── Shared library target ──────────────────────────────────────────────────
add_library(
    security        # → libsecurity.so
    SHARED
    security.cpp
)

# ── Link system libraries ──────────────────────────────────────────────────
find_library(log-lib log)

target_link_libraries(
    security
    ${log-lib}
    android
)

# ── Strip debug symbols in release ────────────────────────────────────────
# (Flutter Gradle release build strips by default via ndk strip)
set_target_properties(security PROPERTIES
    LINK_FLAGS_RELEASE "-Wl,--strip-all"
)


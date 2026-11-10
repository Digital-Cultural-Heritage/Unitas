plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.unitas.unitas_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.unitas.unitas_flutter"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── NDK / CMake config ─────────────────────────────────────────────
        externalNativeBuild {
            cmake {
                // Flags passed through to CMakeLists.txt
                cppFlags += listOf("-std=c++17", "-fno-rtti", "-fno-exceptions")
                // Target ABI list
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }

        ndk {
            // Mirror the ABI list above so packaging is consistent
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    // ── Point Gradle to our CMakeLists.txt ────────────────────────────────
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            // TODO: Replace with your own signing config for production releases.
            signingConfig = signingConfigs.getByName("debug")

            // Strip debug symbols from .so files in release builds
            ndk {
                debugSymbolLevel = "NONE"
            }
        }
        debug {
            // Keep symbols in debug for easier native debugging
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

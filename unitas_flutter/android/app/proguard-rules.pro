# Keep app security & JNI native bridge classes
-keep class com.unitas.** { *; }
-keepclassmembers class com.unitas.** { *; }

# Keep Flutter engine & plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Google Sign-In & Android Credential Manager
-keep class com.google.android.gms.** { *; }
-keep class androidx.credentials.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.**

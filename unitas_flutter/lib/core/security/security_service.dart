import 'dart:io';
import 'package:flutter/services.dart';

/// SecurityService — Dart-side wrapper untuk MethodChannel "com.unitas/security".
///
/// Dipanggil di main() SEBELUM runApp() untuk memastikan root check dan
/// anti-debug aktif sebelum UI apapun dirender.
class SecurityService {
  static const _channel = MethodChannel('com.unitas/security');

  /// Pasang listener untuk event yang dikirim dari native (debugger detect).
  /// [onThreatDetected] dipanggil dengan pesan error.
  static void listenForThreats(void Function(String reason) onThreatDetected) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDebuggerDetected') {
        onThreatDetected('Sesi debugging terdeteksi. Aplikasi dihentikan.');
      }
    });
  }

  /// Cek apakah perangkat di-root. Hanya berjalan di Android.
  /// Di platform lain (iOS, Web) selalu mengembalikan false.
  static Future<bool> isRooted() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('isRooted');
      return result ?? false;
    } on PlatformException catch (e) {
      // Jika native gagal dipanggil (e.g. di emulator CI), tidak block app.
      return false;
    }
  }

  /// Inisialisasi anti-debug (dipanggil dari native di onCreate, tapi
  /// method ini bisa dipakai untuk trigger ulang jika diperlukan).
  static Future<void> initAntiDebug() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('initAntiDebug');
    } on PlatformException {
      // Ignore — anti-debug init dilakukan di MainActivity.onCreate()
    }
  }
}


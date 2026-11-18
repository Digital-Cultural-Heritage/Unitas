import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'api_client.dart';

const String _envGoogleServerClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

class AuthService {
  static Future<void>? _googleInit;

  static String? get googleServerClientId {
    if (_envGoogleServerClientId.isNotEmpty) return _envGoogleServerClientId;
    try {
      final v = dotenv.env['GOOGLE_SERVER_CLIENT_ID']?.trim();
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    return null;
  }

  static Future<void> _ensureGoogleInitialized() {
    return _googleInit ??= GoogleSignIn.instance
        .initialize(serverClientId: googleServerClientId)
        .catchError((Object e) {
          _googleInit = null;
          throw e;
        });
  }

  // ── Login ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final res = await ApiClient.post(
      '/api/auth/login',
      body: {'email': email.trim(), 'password': password},
      auth: false,
    );
    await _saveSession(res);
    return Map<String, dynamic>.from(res as Map);
  }

  // ── Register ───────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String fullName,
    required String prodi,
    required String angkatan,
    String? kota,
  }) async {
    final trimmedKota = kota?.trim();
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'prodi': prodi.trim(),
      'angkatan': angkatan.trim(),
    };
    if (trimmedKota != null && trimmedKota.isNotEmpty) {
      body['kota'] = trimmedKota;
    }

    final res = await ApiClient.post('/api/auth/register', body: body, auth: false);
    await _saveSession(res);
    return Map<String, dynamic>.from(res as Map);
  }

  // ── Google Sign-In ─────────────────────────────────────────────────────
  /// Mengembalikan data sesi jika berhasil, atau `null` jika dibatalkan pengguna.
  static Future<Map<String, dynamic>?> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    if (!GoogleSignIn.instance.supportsAuthenticate()) {
      throw const ApiException(
        'Masuk dengan Google tidak didukung pada platform ini.',
        400,
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw ApiException(_mapGoogleError(e), 400);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      await signOutGoogleQuietly();
      throw const ApiException(
        'Token Google tidak ditemukan. Pastikan GOOGLE_SERVER_CLIENT_ID sudah dikonfigurasi.',
        400,
      );
    }

    try {
      final res = await ApiClient.post(
        '/api/auth/google',
        body: {'id_token': idToken},
        auth: false,
      );
      await _saveSession(res);
      return Map<String, dynamic>.from(res as Map);
    } catch (_) {
      // Bersihkan sesi Google lokal agar pengguna bisa memilih akun lain saat coba ulang.
      await signOutGoogleQuietly();
      rethrow;
    }
  }

  static String _mapGoogleError(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
        return 'Login Google dibatalkan.';
      case GoogleSignInExceptionCode.interrupted:
        return 'Login Google terganggu. Silakan coba lagi.';
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return 'Konfigurasi Google Sign-In belum lengkap. Periksa GOOGLE_SERVER_CLIENT_ID dan SHA-1.';
      case GoogleSignInExceptionCode.uiUnavailable:
        return 'Tampilan login Google tidak tersedia saat ini.';
      case GoogleSignInExceptionCode.userMismatch:
        return 'Akun Google tidak cocok. Coba pilih ulang akun.';
      case GoogleSignInExceptionCode.unknownError:
        final desc = e.description?.trim();
        return desc != null && desc.isNotEmpty
            ? 'Login Google gagal: $desc'
            : 'Login Google gagal. Silakan coba lagi.';
    }
  }

  // ── Logout ─────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    try {
      final refreshToken = await ApiClient.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await ApiClient.post(
          '/api/auth/logout',
          body: {'refresh_token': refreshToken},
          auth: false,
        ).timeout(const Duration(seconds: 5));
      }
    } catch (_) {
      // Tetap lanjut hapus sesi lokal meski offline.
    } finally {
      await ApiClient.clearSession();
      await signOutGoogleQuietly();
    }
  }

  static Future<void> signOutGoogleQuietly() async {
    try {
      await _ensureGoogleInitialized();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  // ── Session restore & helpers ──────────────────────────────────────────
  static Future<Map<String, dynamic>> getMe() async {
    final res = await ApiClient.get('/api/auth/me');
    if (res is! Map) {
      throw const ApiException('Respons server tidak valid.', 500);
    }
    return Map<String, dynamic>.from(res);
  }

  static Future<bool> isLoggedIn() async {
    try {
      final token = await ApiClient.getToken();
      final refresh = await ApiClient.getRefreshToken();
      return (token != null && token.isNotEmpty) ||
          (refresh != null && refresh.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// Pulihkan sesi saat aplikasi dibuka dan validasi ke server jika online.
  static Future<bool> restoreSession() async {
    final token = await ApiClient.getToken();
    final refresh = await ApiClient.getRefreshToken();
    final hasAccess = token != null && token.isNotEmpty;
    final hasRefresh = refresh != null && refresh.isNotEmpty;
    if (!hasAccess && !hasRefresh) return false;

    try {
      final me = await getMe().timeout(const Duration(seconds: 10));
      await ApiClient.saveStoredUserJson(jsonEncode(me));
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) {
        await ApiClient.clearSession();
        return false;
      }
      return _hasUnexpiredTokenLocally(token, refresh);
    } catch (_) {
      // Offline / timeout -> izinkan masuk jika token lokal belum kedaluwarsa.
      return _hasUnexpiredTokenLocally(token, refresh);
    }
  }

  static Future<bool> _hasUnexpiredTokenLocally(
    String? accessToken,
    String? refreshToken,
  ) async {
    final accessValid =
        accessToken != null && accessToken.isNotEmpty && !_isJwtExpired(accessToken);
    final refreshValid =
        refreshToken != null && refreshToken.isNotEmpty && !_isJwtExpired(refreshToken);
    if (accessValid || refreshValid) return true;
    await ApiClient.clearSession();
    return false;
  }

  static bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return false;
      final normalized = base64Url.normalize(parts[1]);
      final payload = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (payload is! Map || payload['exp'] is! num) return false;
      final expSec = (payload['exp'] as num).toInt();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= expSec;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getStoredUser() async {
    try {
      final userStr = await ApiClient.getStoredUserJson();
      if (userStr == null || userStr.isEmpty) return null;
      final decoded = jsonDecode(userStr);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  // ── Password management ────────────────────────────────────────────────
  static Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await ApiClient.post(
      '/api/auth/change-password',
      body: {
        'current_password': currentPassword,
        'new_password': newPassword,
      },
    );
  }

  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    final res = await ApiClient.post(
      '/api/auth/forgot-password',
      body: {'email': email.trim()},
      auth: false,
    );
    return Map<String, dynamic>.from(res as Map);
  }

  static Future<void> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    await ApiClient.post(
      '/api/auth/reset-password',
      body: {
        'email': email.trim(),
        'otp': otp.trim(),
        'new_password': newPassword,
      },
      auth: false,
    );
  }

  // ── Internal ───────────────────────────────────────────────────────────
  static Future<void> _saveSession(dynamic res) async {
    if (res is! Map) {
      throw const ApiException('Respons server tidak valid.', 500);
    }
    final accessToken = res['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw const ApiException('Token akses tidak ditemukan.', 500);
    }
    final refreshToken = res['refresh_token'];
    final user = res['user'];
    await ApiClient.saveSession(
      accessToken: accessToken,
      refreshToken: refreshToken is String && refreshToken.isNotEmpty
          ? refreshToken
          : null,
      userJson: user != null ? jsonEncode(user) : null,
    );
  }
}

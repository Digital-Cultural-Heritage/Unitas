import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

class AuthService {
  // ── Login ──────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    final res = await ApiClient.post(
      '/api/auth/login',
      body: {'email': email, 'password': password},
      auth: false,
    );
    await _saveSession(res);
    return Map<String, dynamic>.from(res);
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
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'full_name': fullName,
      'prodi': prodi,
      'angkatan': angkatan,
    };
    if (kota != null && kota.isNotEmpty) body['kota'] = kota;

    final res = await ApiClient.post('/api/auth/register', body: body, auth: false);
    await _saveSession(res);
    return Map<String, dynamic>.from(res);
  }

  // ── Logout ─────────────────────────────────────────────────────────────
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final refreshToken = prefs.getString('refresh_token');
      if (refreshToken != null) {
        await ApiClient.post(
          '/api/auth/logout',
          body: {'refresh_token': refreshToken},
          auth: false,
        );
      }
    } catch (_) {}
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user');
  }

  // ── Token helpers ──────────────────────────────────────────────────────
  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token') != null;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, dynamic>?> getStoredUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userStr = prefs.getString('user');
      if (userStr == null) return null;
      return Map<String, dynamic>.from(jsonDecode(userStr));
    } catch (_) {
      return null;
    }
  }

  // ── Internal ───────────────────────────────────────────────────────────
  static Future<void> _saveSession(dynamic res) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', res['access_token']);
    await prefs.setString('refresh_token', res['refresh_token']);
    await prefs.setString('user', jsonEncode(res['user']));
  }
}

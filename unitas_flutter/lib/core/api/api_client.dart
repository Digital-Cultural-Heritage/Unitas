import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../crypto/e2ee_service.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/image_validator.dart';

const String _envBackendUrl = String.fromEnvironment('BACKEND_URL');

/// URL backend Unitas (prioritas: `--dart-define=BACKEND_URL` -> `.env` -> prod).
String get kBaseUrl {
  if (_envBackendUrl.isNotEmpty) return _envBackendUrl;
  try {
    final envUrl = dotenv.env['BACKEND_URL']?.trim();
    if (envUrl != null && envUrl.isNotEmpty) return envUrl;
  } catch (_) {}
  return 'https://unitas-beta.vercel.app';
}

/// Batas waktu request supaya UI tidak menggantung saat jaringan buruk.
const Duration _kRequestTimeout = Duration(seconds: 30);
const Duration _kUploadTimeout = Duration(seconds: 90);

class ApiClient {
  // ── Secure token storage ───────────────────────────────────────────────
  static const _storage = FlutterSecureStorage();
  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kUser = 'user';

  // Cache di memori agar tidak membaca keystore di setiap request,
  // sekaligus fallback saat secure storage tidak tersedia (mis. web non-HTTPS).
  static String? _accessCache;
  static String? _refreshCache;
  static String? _userJsonCache;
  static bool _loaded = false;
  static Future<void>? _loading;
  // Mencegah race condition antara load/refresh in-flight dengan save/clearSession.
  static int _sessionEpoch = 0;

  static final _sessionExpired = StreamController<void>.broadcast();

  /// Dipicu ketika sesi tidak bisa dipulihkan lagi (401 + refresh ditolak).
  /// UI (`main.dart`) mendengarkan ini untuk logout otomatis.
  static Stream<void> get onSessionExpired => _sessionExpired.stream;

  static Future<void> _ensureLoaded() {
    if (_loaded) return Future.value();
    final epoch = _sessionEpoch;
    return _loading ??= () async {
      try {
        await _migrateLegacyPrefs();
        final access = await _storage.read(key: _kAccess);
        final refresh = await _storage.read(key: _kRefresh);
        final userJson = await _storage.read(key: _kUser);
        if (_sessionEpoch == epoch) {
          _accessCache = access;
          _refreshCache = refresh;
          _userJsonCache = userJson;
        }
      } catch (_) {
        if (_sessionEpoch == epoch) {
          _accessCache = null;
          _refreshCache = null;
          _userJsonCache = null;
        }
      } finally {
        _loaded = true;
        _loading = null;
      }
    }();
  }

  /// Pindahkan token lama dari SharedPreferences (plaintext) ke secure storage.
  static Future<void> _migrateLegacyPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final oldAccess = prefs.getString(_kAccess);
    final oldRefresh = prefs.getString(_kRefresh);
    final oldUser = prefs.getString(_kUser);
    if (oldAccess == null && oldRefresh == null && oldUser == null) return;
    if (oldAccess != null && await _storage.read(key: _kAccess) == null) {
      await _storage.write(key: _kAccess, value: oldAccess);
      if (oldRefresh != null) {
        await _storage.write(key: _kRefresh, value: oldRefresh);
      }
      if (oldUser != null) await _storage.write(key: _kUser, value: oldUser);
    }
    await prefs.remove(_kAccess);
    await prefs.remove(_kRefresh);
    await prefs.remove(_kUser);
  }

  static Future<String?> getToken() async {
    await _ensureLoaded();
    return _accessCache;
  }

  static Future<String?> getRefreshToken() async {
    await _ensureLoaded();
    return _refreshCache;
  }

  static Future<String?> getStoredUserJson() async {
    try {
      await _ensureLoaded();
      if (_userJsonCache != null) return _userJsonCache;
      _userJsonCache = await _storage.read(key: _kUser);
      return _userJsonCache;
    } catch (_) {
      return _userJsonCache;
    }
  }

  static Future<void> saveSession({
    required String accessToken,
    String? refreshToken,
    String? userJson,
  }) async {
    await _ensureLoaded();
    _sessionEpoch++;
    _accessCache = accessToken;
    if (refreshToken != null) _refreshCache = refreshToken;
    if (userJson != null) _userJsonCache = userJson;
    try {
      await _storage.write(key: _kAccess, value: accessToken);
      if (refreshToken != null) {
        await _storage.write(key: _kRefresh, value: refreshToken);
      }
      if (userJson != null) await _storage.write(key: _kUser, value: userJson);
    } catch (_) {
      // Fallback ke cache memori jika Web Crypto tidak tersedia (non-HTTPS/LAN).
    }
  }

  static Future<void> saveStoredUserJson(String userJson) async {
    try {
      await _ensureLoaded();
      _userJsonCache = userJson;
      await _storage.write(key: _kUser, value: userJson);
    } catch (_) {}
  }

  static Future<void> clearSession() async {
    _sessionEpoch++;
    _accessCache = null;
    _refreshCache = null;
    _userJsonCache = null;
    _loaded = true;
    try {
      E2eeService.clearCache();
      await _storage.delete(key: _kAccess);
      await _storage.delete(key: _kRefresh);
      await _storage.delete(key: _kUser);
    } catch (_) {}
  }

  // ── Headers ────────────────────────────────────────────────────────────
  static Map<String, String> _headers(String? token) {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  // ── Core request with 401 -> refresh -> retry once ─────────────────────
  static Future<dynamic> _request(
    Future<http.Response> Function(String? token) send, {
    required bool auth,
  }) async {
    String? token = auth ? await getToken() : null;

    if (auth && (token == null || token.isEmpty)) {
      final refreshed = await _refreshSession();
      if (refreshed == true) {
        token = _accessCache;
      } else if (refreshed == false) {
        await _expireSession();
        throw const ApiException('Sesi berakhir. Silakan masuk kembali.', 401);
      } else {
        throw const ApiException('Tidak dapat memverifikasi sesi. Cek koneksi kamu.', 503);
      }
    }

    http.Response res = await send(token);

    if (auth && res.statusCode == 401) {
      final refreshed = await _refreshSession(failedToken: token);
      if (refreshed == true) {
        res = await send(_accessCache);
      } else if (refreshed == false) {
        // Refresh token tidak ada atau ditolak server (400/401) -> sesi berakhir.
        await _expireSession();
      }
      // refreshed == null: gangguan sementara (jaringan/5xx) -> sesi dipertahankan.
      // 401 setelah refresh sukses = error level aplikasi (mis. password salah).
    }
    return _parse(res);
  }

  static Future<bool?>? _refreshing;

  /// Single-flight refresh: request paralel yang kena 401 berbagi satu refresh.
  static Future<bool?> _refreshSession({String? failedToken}) {
    if (failedToken != null &&
        _accessCache != null &&
        _accessCache != failedToken) {
      return Future.value(true);
    }
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  /// `true` = refresh berhasil, `false` = ditolak/tidak ada, `null` = error sementara.
  static Future<bool?> _doRefresh() async {
    final refresh = await getRefreshToken();
    if (refresh == null || refresh.isEmpty) return false;
    final epoch = _sessionEpoch;
    try {
      final res = await http
          .post(
            Uri.parse('$kBaseUrl/api/auth/refresh'),
            headers: _headers(null),
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(_kRequestTimeout);
      if (res.statusCode == 400 || res.statusCode == 401) return false;
      if (res.statusCode != 200) return null;

      final body = jsonDecode(utf8.decode(res.bodyBytes));
      final access = body is Map ? body['access_token'] : null;
      final newRefresh = body is Map ? body['refresh_token'] : null;
      if (access is! String || access.isEmpty) return false;
      if (_sessionEpoch != epoch) return false;

      await saveSession(
        accessToken: access,
        refreshToken: newRefresh is String && newRefresh.isNotEmpty
            ? newRefresh
            : null,
      );
      return true;
    } catch (_) {
      return null;
    }
  }

  static bool _expiring = false;
  static Future<void> _expireSession() async {
    if (_expiring) return;
    _expiring = true;
    try {
      await clearSession();
      if (!_sessionExpired.isClosed) _sessionExpired.add(null);
    } finally {
      _expiring = false;
    }
  }

  // ── HTTP Methods ───────────────────────────────────────────────────────
  static Future<dynamic> get(String path, {bool auth = true}) {
    return _request(
      (token) => http
          .get(Uri.parse('$kBaseUrl$path'), headers: _headers(token))
          .timeout(_kRequestTimeout),
      auth: auth,
    );
  }

  static Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    bool auth = true,
  }) {
    return _request(
      (token) => http
          .post(
            Uri.parse('$kBaseUrl$path'),
            headers: _headers(token),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(_kRequestTimeout),
      auth: auth,
    );
  }

  static Future<dynamic> put(String path, {Map<String, dynamic>? body}) {
    return _request(
      (token) => http
          .put(
            Uri.parse('$kBaseUrl$path'),
            headers: _headers(token),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(_kRequestTimeout),
      auth: true,
    );
  }

  static Future<dynamic> delete(String path) {
    return _request(
      (token) => http
          .delete(Uri.parse('$kBaseUrl$path'), headers: _headers(token))
          .timeout(_kRequestTimeout),
      auth: true,
    );
  }

  static Future<dynamic> uploadFile(
    String path, {
    required List<int> bytes,
    required String filename,
  }) {
    final mediaType = ImageValidator.validate(bytes, filename);
    return _request(
      (token) async {
        final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl$path'));
        if (token != null) req.headers['Authorization'] = 'Bearer $token';
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: mediaType,
        ));
        final streamed = await req.send().timeout(_kUploadTimeout);
        return http.Response.fromStream(streamed);
      },
      auth: true,
    );
  }

  static Future<dynamic> uploadPdf(
    String path, {
    required List<int> bytes,
    required String filename,
  }) {
    if (bytes.isEmpty) {
      throw const ApiException('File CV PDF kosong.', 400);
    }
    if (bytes.length > 4 * 1024 * 1024) {
      throw const ApiException('Ukuran file PDF awal maksimal 4 MB sebelum dikompresi.', 400);
    }
    if (!filename.toLowerCase().endsWith('.pdf')) {
      throw const ApiException('Format CV harus berupa file PDF (.pdf).', 400);
    }
    if (bytes.length < 5 ||
        bytes[0] != 0x25 || // %
        bytes[1] != 0x50 || // P
        bytes[2] != 0x44 || // D
        bytes[3] != 0x46 || // F
        bytes[4] != 0x2D) { // -
      throw const ApiException('File bukan PDF yang valid.', 400);
    }

    return _request(
      (token) async {
        final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl$path'));
        if (token != null) req.headers['Authorization'] = 'Bearer $token';
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: filename,
          contentType: MediaType('application', 'pdf'),
        ));
        final streamed = await req.send().timeout(_kUploadTimeout);
        return http.Response.fromStream(streamed);
      },
      auth: true,
    );
  }

  // ── Parse response ─────────────────────────────────────────────────────
  static dynamic _parse(http.Response res) {
    dynamic body;
    try {
      final text = utf8.decode(res.bodyBytes);
      body = text.isEmpty ? null : jsonDecode(text);
    } catch (_) {
      body = null;
    }
    if (res.statusCode >= 400) {
      throw ApiException(_errorMessage(body, res.statusCode), res.statusCode);
    }
    return body;
  }

  static String _errorMessage(dynamic body, int status) {
    if (body is Map) {
      final err = body['error'] ?? body['message'];
      if (err != null) return err.toString();
      final errors = body['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['msg'] != null) {
          return first['msg'].toString();
        }
      }
    }
    if (status == 429) {
      return 'Terlalu banyak percobaan. Coba lagi beberapa menit lagi.';
    }
    if (status >= 500) return 'Server sedang bermasalah. Coba lagi nanti.';
    return 'Terjadi kesalahan';
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  const ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

import '../utils/json_utils.dart';
import 'api_client.dart';

class UsersService {
  // ── Directory ──────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getDirectory({
    String? q,
    String? kota,
    bool? isOnline,
    int page = 1,
  }) async {
    final params = StringBuffer('/api/users?page=$page&limit=30');
    if (q != null && q.isNotEmpty) params.write('&q=${Uri.encodeComponent(q)}');
    if (kota != null && kota != 'Semua') params.write('&kota=${Uri.encodeComponent(kota)}');
    if (isOnline == true) params.write('&is_online=true');

    final res = await ApiClient.get(params.toString(), auth: true);
    return asJsonMapList(res);
  }

  // ── Get single user profile ────────────────────────────────────────────
  static Future<Map<String, dynamic>> getUserById(String userId) async {
    final res = await ApiClient.get('/api/users/$userId', auth: true);
    return asJsonMap(res);
  }

  // ── My profile ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getMe() async {
    final res = asJsonMap(await ApiClient.get('/api/users/me'));
    if (res['full_name'] == null && res['id'] != null) {
      try {
        final profile = asJsonMap(
          await ApiClient.get('/api/users/${res['id']}', auth: false),
        );
        return {...profile, ...res};
      } catch (_) {}
    }
    return res;
  }

  // ── Update profile ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> updates) async {
    final res = await ApiClient.put('/api/users/me', body: updates);
    return asJsonMap(res);
  }

  // ── Upload avatar ──────────────────────────────────────────────────────
  static Future<String> uploadAvatar(List<int> bytes, String filename) async {
    final res = asJsonMap(
      await ApiClient.uploadFile('/api/upload/avatar', bytes: bytes, filename: filename),
    );
    final url = res['url']?.toString();
    if (url == null || url.isEmpty) {
      throw const ApiException('URL avatar tidak ditemukan', 500);
    }
    return url;
  }

  // ── Connect ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> connect(String userId) async {
    final res = await ApiClient.post('/api/users/$userId/connect');
    return asJsonMap(res);
  }

  // ── My connections ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyConnections() async {
    final res = await ApiClient.get('/api/users/me/connections');
    return asJsonMapList(res);
  }

  // ── Incoming Requests ──────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    final res = await ApiClient.get('/api/users/me/requests');
    return asJsonMapList(res);
  }

  static Future<void> respondRequest(String requestId, String action) async {
    await ApiClient.put('/api/users/requests/$requestId', body: {'action': action});
  }
}

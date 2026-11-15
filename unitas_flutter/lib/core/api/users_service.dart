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
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── My profile ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getMe() async {
    final res = Map<String, dynamic>.from(await ApiClient.get('/api/users/me'));
    if (res['full_name'] == null && res['id'] != null) {
      try {
        final profile = Map<String, dynamic>.from(
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
    return Map<String, dynamic>.from(res);
  }

  // ── Upload avatar ──────────────────────────────────────────────────────
  static Future<String> uploadAvatar(List<int> bytes, String filename) async {
    final res = await ApiClient.uploadFile('/api/upload/avatar', bytes: bytes, filename: filename);
    return res['url'] as String;
  }

  // ── Connect ────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> connect(String userId) async {
    final res = await ApiClient.post('/api/users/$userId/connect');
    return Map<String, dynamic>.from(res);
  }

  // ── My connections ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyConnections() async {
    final res = await ApiClient.get('/api/users/me/connections');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Incoming Requests ──────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getIncomingRequests() async {
    final res = await ApiClient.get('/api/users/me/requests');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<void> respondRequest(String requestId, String action) async {
    await ApiClient.put('/api/users/requests/$requestId', body: {'action': action});
  }
}

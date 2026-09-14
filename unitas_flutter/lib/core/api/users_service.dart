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

    final res = await ApiClient.get(params.toString(), auth: false);
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── My profile ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> getMe() async {
    final res = await ApiClient.get('/api/users/me');
    return Map<String, dynamic>.from(res);
  }

  // ── Update profile ─────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> updates) async {
    final res = await ApiClient.put('/api/users/me', body: updates);
    return Map<String, dynamic>.from(res);
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
}

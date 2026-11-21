import '../utils/json_utils.dart';
import 'api_client.dart';

class DirectoryPage {
  final List<Map<String, dynamic>> items;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final bool hasPrev;
  final bool hasNext;

  const DirectoryPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.hasPrev,
    required this.hasNext,
  });
}

class UsersService {
  // ── Directory ──────────────────────────────────────────────────────────
  static Future<DirectoryPage> getDirectory({
    String? q,
    String? kota,
    String? excludeKota,
    bool connectedOnly = false,
    bool? isOnline,
    int page = 1,
    int limit = 15,
  }) async {
    final safePage = page < 1 ? 1 : page;
    final safeLimit = limit < 1 ? 15 : limit;
    final params = StringBuffer('/api/users?page=$safePage&limit=$safeLimit');
    if (q != null && q.trim().isNotEmpty) {
      params.write('&q=${Uri.encodeComponent(q.trim())}');
    }
    if (kota != null && kota.trim().isNotEmpty && kota != 'Semua') {
      params.write('&kota=${Uri.encodeComponent(kota.trim())}');
    } else if (excludeKota != null && excludeKota.trim().isNotEmpty) {
      params.write('&exclude_kota=${Uri.encodeComponent(excludeKota.trim())}');
    }
    if (connectedOnly) params.write('&connected=true');
    if (isOnline == true) params.write('&is_online=true');

    final res = await ApiClient.get(params.toString(), auth: true);
    final map = asJsonMap(res);
    final items = asJsonMapList(res);
    final total = (map['total'] as num?)?.toInt() ?? items.length;
    final respPage = (map['page'] as num?)?.toInt() ?? safePage;
    final respLimit = (map['limit'] as num?)?.toInt() ?? safeLimit;
    final computedPages = respLimit > 0 ? ((total + respLimit - 1) ~/ respLimit) : 1;
    final rawTotalPages = (map['total_pages'] as num?)?.toInt() ?? computedPages;
    final totalPages = rawTotalPages < 1 ? 1 : rawTotalPages;
    final normalizedPage = respPage < 1 ? 1 : respPage;

    return DirectoryPage(
      items: items,
      total: total,
      page: normalizedPage,
      limit: respLimit,
      totalPages: totalPages,
      hasPrev: normalizedPage > 1,
      hasNext: normalizedPage < totalPages,
    );
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

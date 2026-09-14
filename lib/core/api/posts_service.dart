import 'api_client.dart';

class PostsService {
  // ── Feed ───────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getFeed({int page = 1}) async {
    final res = await ApiClient.get('/api/posts?page=$page&limit=20', auth: false);
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Create post ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> createPost(
    String content, {
    String? imageUrl,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (imageUrl != null) body['image_url'] = imageUrl;
    final res = await ApiClient.post('/api/posts', body: body);
    return Map<String, dynamic>.from(res);
  }

  // ── Toggle like ────────────────────────────────────────────────────────
  static Future<bool> toggleLike(String postId) async {
    final res = await ApiClient.post('/api/posts/$postId/like');
    return res['liked'] == true;
  }

  // ── Leaderboard ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 10}) async {
    final res = await ApiClient.get('/api/posts/leaderboard?limit=$limit', auth: false);
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }
}

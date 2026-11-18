import '../utils/json_utils.dart';
import 'api_client.dart';

class PostsService {
  // ── Feed ───────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getFeed({int page = 1}) async {
    final res = await ApiClient.get('/api/posts?page=$page&limit=20', auth: false);
    return asJsonMapList(res);
  }

  // ── Create post ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> createPost(
    String content, {
    String? imageUrl,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (imageUrl != null) body['image_url'] = imageUrl;
    final res = await ApiClient.post('/api/posts', body: body);
    return asJsonMap(res);
  }

  // ── Upload Image ───────────────────────────────────────────────────────
  static Future<String> uploadImage(List<int> bytes, String filename) async {
    final res = asJsonMap(
      await ApiClient.uploadFile('/api/upload/post', bytes: bytes, filename: filename),
    );
    final url = res['url']?.toString();
    if (url == null || url.isEmpty) {
      throw const ApiException('URL gambar tidak ditemukan', 500);
    }
    return url;
  }

  // ── Comments ───────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getComments(String postId) async {
    final res = await ApiClient.get('/api/posts/$postId/comments');
    return asJsonMapList(res);
  }

  static Future<Map<String, dynamic>> addComment(
    String postId,
    String content, {
    String? parentId,
  }) async {
    final body = <String, dynamic>{'content': content};
    if (parentId != null && parentId.isNotEmpty) body['parent_id'] = parentId;
    final res = await ApiClient.post('/api/posts/$postId/comments', body: body);
    return asJsonMap(res);
  }

  // ── Update Post ────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updatePost(String postId, String content) async {
    final res = await ApiClient.put('/api/posts/$postId', body: {'content': content});
    return asJsonMap(res);
  }

  // ── Delete Post ────────────────────────────────────────────────────────
  static Future<void> deletePost(String postId) async {
    await ApiClient.delete('/api/posts/$postId');
  }

  // ── Delete Comment ─────────────────────────────────────────────────────
  static Future<void> deleteComment(String postId, String commentId) async {
    await ApiClient.delete('/api/posts/$postId/comments/$commentId');
  }

  // ── Toggle like ────────────────────────────────────────────────────────
  static Future<bool> toggleLike(String postId) async {
    final res = asJsonMap(await ApiClient.post('/api/posts/$postId/like'));
    return res['liked'] == true;
  }

  // ── Leaderboard ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 10}) async {
    final res = await ApiClient.get('/api/posts/leaderboard?limit=$limit', auth: false);
    return asJsonMapList(res);
  }
}

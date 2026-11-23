import 'dart:async';
import '../utils/json_utils.dart';
import 'api_client.dart';

class PostsService {
  static final PostLikeSync likeSync = PostLikeSync();

  // ── Feed ───────────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getFeed({int page = 1}) async {
    final res = await ApiClient.get('/api/posts?page=$page&limit=20');
    return asJsonMapList(res);
  }

  static Future<Map<String, dynamic>?> getPostById(String postId) async {
    if (postId.isEmpty) return null;
    try {
      final res = asJsonMap(await ApiClient.get('/api/posts/$postId'));
      final data = res['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      if (res['id'] != null) return res;
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 400) {
        // Fallback jika backend remote belum memiliki endpoint GET /api/posts/:id
        try {
          final feed = await getFeed(page: 1);
          for (final p in feed) {
            if (p['id']?.toString() == postId) return p;
          }
        } catch (_) {}
        return null;
      }
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> getUserPosts(
    String userId, {
    int page = 1,
  }) async {
    final res = await ApiClient.get(
      '/api/posts?user_id=$userId&page=$page&limit=20',
    );
    final list = asJsonMapList(res);
    return list.where((p) {
      final user = p['user'] is Map ? p['user'] as Map : const {};
      final uid = (user['id'] ?? p['user_id'] ?? '').toString();
      return uid == userId;
    }).toList();
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

  // ── Like (idempotent set + shared client sync) ─────────────────────────
  static Future<PostLikeResult> setLike(
    String postId, {
    required bool liked,
  }) async {
    final res = asJsonMap(
      await ApiClient.post('/api/posts/$postId/like', body: {'liked': liked}),
    );
    final rawCount = res['likes_count'];
    return PostLikeResult(
      liked: res['liked'] == true,
      likesCount: rawCount is num ? rawCount.toInt() : null,
    );
  }

  // ── Leaderboard ────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getLeaderboard({int limit = 10}) async {
    final res = await ApiClient.get('/api/posts/leaderboard?limit=$limit', auth: false);
    return asJsonMapList(res);
  }
}

class PostLikeResult {
  final bool liked;
  final int? likesCount;
  const PostLikeResult({required this.liked, this.likesCount});
}

class PostLikeSnapshot {
  final bool liked;
  final int likesCount;
  const PostLikeSnapshot({required this.liked, required this.likesCount});
}

typedef LikeSender = Future<PostLikeResult> Function(String postId, bool liked);
typedef LikeListener = void Function(String postId, PostLikeSnapshot snapshot);

class _LikeEntry {
  bool confirmedLiked;
  int confirmedCount;
  bool desiredLiked;
  bool inFlight = false;
  Timer? timer;

  _LikeEntry({
    required this.confirmedLiked,
    required this.confirmedCount,
    required this.desiredLiked,
  });

  int get optimisticCount {
    if (desiredLiked == confirmedLiked) return confirmedCount;
    return (confirmedCount + (desiredLiked ? 1 : -1)).clamp(0, 999999);
  }

  PostLikeSnapshot get snapshot =>
      PostLikeSnapshot(liked: desiredLiked, likesCount: optimisticCount);
}

class PostLikeSync {
  final Duration debounceDuration;
  final LikeSender _sendLike;
  final Map<String, _LikeEntry> _entries = {};
  final Set<LikeListener> _listeners = {};
  int _epoch = 0;

  PostLikeSync({
    this.debounceDuration = const Duration(milliseconds: 300),
    LikeSender? sendLike,
  }) : _sendLike = sendLike ?? ((id, liked) => PostsService.setLike(id, liked: liked));

  void addListener(LikeListener listener) => _listeners.add(listener);
  void removeListener(LikeListener listener) => _listeners.remove(listener);

  PostLikeSnapshot? pendingFor(String postId) => _entries[postId]?.snapshot;

  List<Map<String, dynamic>> applyPending(List<Map<String, dynamic>> posts) {
    if (_entries.isEmpty) return posts;
    return posts.map((post) {
      final id = post['id']?.toString();
      final pending = id == null ? null : _entries[id]?.snapshot;
      if (pending == null) return post;
      return {
        ...post,
        'is_liked': pending.liked,
        'likes_count': pending.likesCount,
      };
    }).toList();
  }

  void toggle({
    required String postId,
    required bool currentLiked,
    required int currentCount,
  }) {
    if (postId.isEmpty) return;
    final cleanCount = currentCount < 0 ? 0 : currentCount;
    final existing = _entries[postId];
    if (existing != null) {
      existing.desiredLiked = !existing.desiredLiked;
    } else {
      _entries[postId] = _LikeEntry(
        confirmedLiked: currentLiked,
        confirmedCount: cleanCount,
        desiredLiked: !currentLiked,
      );
    }

    final entry = _entries[postId]!;
    _emit(postId, entry.snapshot);

    if (entry.inFlight) return;

    entry.timer?.cancel();
    entry.timer = null;
    if (entry.desiredLiked == entry.confirmedLiked) {
      _entries.remove(postId);
      return;
    }

    entry.timer = Timer(debounceDuration, () => _drain(postId));
  }

  void flush(String postId) {
    final entry = _entries[postId];
    if (entry == null || entry.inFlight || entry.timer == null) return;
    entry.timer?.cancel();
    entry.timer = null;
    _drain(postId);
  }

  void flushAll() {
    for (final id in _entries.keys.toList()) {
      flush(id);
    }
  }

  void clear() {
    _epoch++;
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
  }

  void _emit(String postId, PostLikeSnapshot snapshot) {
    for (final listener in _listeners.toList()) {
      listener(postId, snapshot);
    }
  }

  Future<void> _drain(String postId) async {
    final entry = _entries[postId];
    if (entry == null || entry.inFlight) return;
    if (entry.desiredLiked == entry.confirmedLiked) {
      _entries.remove(postId);
      return;
    }

    final epoch = _epoch;
    entry.inFlight = true;

    try {
      while (true) {
        if (epoch != _epoch || !identical(_entries[postId], entry)) return;
        final target = entry.desiredLiked;
        if (target == entry.confirmedLiked) break;

        final prevConfirmedLiked = entry.confirmedLiked;
        final prevConfirmedCount = entry.confirmedCount;
        final res = await _sendLike(postId, target);

        if (epoch != _epoch || !identical(_entries[postId], entry)) return;

        entry.confirmedLiked = res.liked;
        if (res.likesCount != null) {
          entry.confirmedCount = res.likesCount!.clamp(0, 999999);
        } else if (res.liked != prevConfirmedLiked) {
          entry.confirmedCount =
              (prevConfirmedCount + (res.liked ? 1 : -1)).clamp(0, 999999);
        }

        // If user did not tap again mid-request (or server already matches desired),
        // adopt server state without re-dispatching (safe with legacy blind-toggle servers).
        if (entry.desiredLiked == target ||
            entry.desiredLiked == entry.confirmedLiked) {
          entry.desiredLiked = entry.confirmedLiked;
          _emit(
            postId,
            PostLikeSnapshot(
              liked: entry.confirmedLiked,
              likesCount: entry.confirmedCount,
            ),
          );
          break;
        }
        _emit(postId, entry.snapshot);
      }
    } catch (_) {
      if (epoch != _epoch || !identical(_entries[postId], entry)) return;
      entry.desiredLiked = entry.confirmedLiked;
      _emit(postId, entry.snapshot);
    } finally {
      if (epoch == _epoch && identical(_entries[postId], entry)) {
        entry.inFlight = false;
        entry.timer?.cancel();
        entry.timer = null;
        if (entry.desiredLiked == entry.confirmedLiked) {
          _entries.remove(postId);
        } else {
          entry.timer = Timer(debounceDuration, () => _drain(postId));
        }
      }
    }
  }
}

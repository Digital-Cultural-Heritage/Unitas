import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/posts_service.dart';
import '../core/api/users_service.dart';
import '../widgets/avatar.dart';
import 'alumni_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;
  final VoidCallback onPostDeleted;
  const PostDetailScreen({super.key, required this.post, required this.onPostDeleted});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;
  bool _mutatingPost = false;
  final Set<String> _deletingCommentIds = {};
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  Map<String, dynamic>? _me;

  late int _likesCount;
  late String _postContent;
  late bool _liked;
  String? _replyToCommentId;
  String? _replyToName;
  final Set<String> _expandedThreads = {};

  @override
  void initState() {
    super.initState();
    _postContent = (widget.post['content'] ?? '').toString();
    final postId = widget.post['id']?.toString();
    final pending = postId != null && postId.isNotEmpty
        ? PostsService.likeSync.pendingFor(postId)
        : null;
    if (pending != null) {
      _liked = pending.liked;
      _likesCount = pending.likesCount;
    } else {
      _liked = widget.post['is_liked'] == true;
      _likesCount = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
      if (_likesCount < 0) _likesCount = 0;
    }
    PostsService.likeSync.addListener(_onLikeSyncChanged);
    _load();
  }

  @override
  void dispose() {
    PostsService.likeSync.removeListener(_onLikeSyncChanged);
    final postId = widget.post['id']?.toString();
    if (postId != null && postId.isNotEmpty) {
      PostsService.likeSync.flush(postId);
    }
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  String? get _myId => (_me?['user_id'] ?? _me?['id'])?.toString();

  Future<void> _load() async {
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Postingan tidak valid';
        });
      }
      return;
    }
    if (_comments.isEmpty && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      final results = await Future.wait([
        PostsService.getComments(postId),
        _me == null
            ? UsersService.getMe().catchError((_) => <String, dynamic>{})
            : Future.value(_me!),
      ]);
      if (mounted) {
        final rawComments = results[0];
        final rawMe = results[1];
        setState(() {
          _comments = rawComments is List
              ? rawComments.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
              : [];
          _me = rawMe is Map ? Map<String, dynamic>.from(rawMe) : null;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_comments.isEmpty) _error = 'Gagal memuat komentar';
        });
      }
    }
  }

  bool _isMyComment(Map<String, dynamic> c) {
    final myId = _myId;
    final userRaw = c['user'];
    final authorId = ((userRaw is Map ? userRaw['id'] : null) ?? c['user_id'])?.toString();
    return myId != null && myId.isNotEmpty && authorId != null && myId == authorId;
  }

  void _onLikeSyncChanged(String postId, PostLikeSnapshot snap) {
    if (!mounted || postId != widget.post['id']?.toString()) return;
    setState(() {
      _liked = snap.liked;
      _likesCount = snap.likesCount;
    });
  }

  void _toggleLike() {
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) return;
    PostsService.likeSync.toggle(
      postId: postId,
      currentLiked: _liked,
      currentCount: _likesCount,
    );
  }

  void _startReply(Map<String, dynamic> targetComment, {String? rootParentId}) {
    final profile = _profile(targetComment);
    final name = (profile['full_name'] ?? 'Alumni').toString();
    final parentId = rootParentId ?? targetComment['id']?.toString();
    if (parentId == null) return;

    setState(() {
      _replyToCommentId = parentId;
      _replyToName = name;
      if (rootParentId != null) {
        _expandedThreads.add(parentId);
      }
    });

    final mention = '@${name.split(' ').first} ';
    if (!_commentCtrl.text.startsWith(mention)) {
      _commentCtrl.text = mention;
      _commentCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _commentCtrl.text.length),
      );
    }
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() {
      _replyToCommentId = null;
      _replyToName = null;
    });
  }

  Future<void> _deleteComment(String commentId) async {
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty || _deletingCommentIds.contains(commentId)) return;
    _deletingCommentIds.add(commentId);
    try {
      await PostsService.deleteComment(postId, commentId);
      if (mounted) {
        setState(() {
          _comments.removeWhere(
            (c) => c['id']?.toString() == commentId || c['parent_id']?.toString() == commentId,
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Komentar dihapus')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus komentar')),
        );
      }
    } finally {
      _deletingCommentIds.remove(commentId);
    }
  }

  Future<void> _submitComment() async {
    final postId = widget.post['id']?.toString();
    final text = _commentCtrl.text.trim();
    if (postId == null || postId.isEmpty || text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final parentId = _replyToCommentId;
      final newComment = await PostsService.addComment(
        postId,
        text,
        parentId: parentId,
      );
      if (mounted) {
        setState(() {
          _comments = [..._comments, newComment];
          _commentCtrl.clear();
          if (parentId != null) _expandedThreads.add(parentId);
          _replyToCommentId = null;
          _replyToName = null;
        });
        FocusScope.of(context).unfocus();
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '').replaceFirst('ApiException: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengirim komentar: $msg')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _editPost() async {
    if (_mutatingPost) return;
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) return;
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _EditPostDialog(initialContent: _postContent),
    );
    if (updated == null || !mounted) return;

    _mutatingPost = true;
    try {
      await PostsService.updatePost(postId, updated);
      if (mounted) {
        setState(() => _postContent = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Postingan berhasil diperbarui')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memperbarui postingan')),
        );
      }
    } finally {
      _mutatingPost = false;
    }
  }

  void _openImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
                errorBuilder: (_, _, _) => const Center(
                  child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePost() async {
    if (_mutatingPost) return;
    final postId = widget.post['id']?.toString();
    if (postId == null || postId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Postingan'),
        content: const Text('Yakin ingin menghapus postingan ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    _mutatingPost = true;
    try {
      await PostsService.deletePost(postId);
      if (!mounted) return;
      widget.onPostDeleted();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus postingan')),
        );
      }
    } finally {
      _mutatingPost = false;
    }
  }

  void _openUserProfile(String? userId, Map<String, dynamic> profile) {
    if (userId == null || userId.isEmpty) return;
    if (userId == _myId) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlumniProfileScreen(
          userId: userId,
          initialProfile: {...profile, 'user_id': userId},
        ),
      ),
    );
  }

  Map<String, dynamic> _profile(Map<String, dynamic> obj) {
    final u = obj['user'];
    if (u is Map) {
      final p = u['user_profiles'];
      if (p is List && p.isNotEmpty && p.first is Map) {
        return Map<String, dynamic>.from(p.first as Map);
      }
      if (p is Map) return Map<String, dynamic>.from(p);
    }
    return {};
  }

  String _initials(Map<String, dynamic> p) {
    final ini = (p['initials'] ?? '').toString().trim();
    if (ini.isNotEmpty) return ini.toUpperCase();
    final rawName = (p['full_name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'AL' : rawName;
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}j';
    return '${diff.inDays}h';
  }

  Color _colorFor(String seed) {
    const colors = [brandNavy, Color(0xFF4A6B82), Color(0xFF7A5C3E), Color(0xFF5B9A6F), Color(0xFF6B5B8A)];
    return colors[seed.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final postProfile = _profile(widget.post);
    final postUser = widget.post['user'];
    final posterId = ((postUser is Map ? postUser['id'] : null) ?? widget.post['user_id'])?.toString();
    final amIOwner = _myId != null && posterId != null && _myId == posterId;
    final posterNameRaw = (postProfile['full_name'] ?? '').toString().trim();
    final posterName = posterNameRaw.isEmpty ? 'Alumni Unitas' : posterNameRaw;
    final posterProdi = (postProfile['prodi'] ?? '').toString().trim();
    final posterAngkatan = (postProfile['angkatan'] ?? '').toString().trim();
    final postImageUrl = widget.post['image_url']?.toString().trim();
    final imageCacheWidth = (600 * MediaQuery.devicePixelRatioOf(context)).round().clamp(300, 1440);

    final topComments = _comments.where((c) => c['parent_id'] == null).toList();
    final repliesByParent = <String, List<Map<String, dynamic>>>{};
    for (final c in _comments) {
      final pid = c['parent_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        repliesByParent.putIfAbsent(pid, () => []).add(c);
      }
    }

    final showCommentsPlaceholder = _loading || _error != null || _comments.isEmpty;
    final itemCount = 1 + (showCommentsPlaceholder ? 0 : topComments.length);

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        title: Text('Postingan', style: heading.copyWith(fontSize: 18)),
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        iconTheme: const IconThemeData(color: brandNavy),
        actions: [
          if (amIOwner)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: brandNavy),
              onSelected: (val) {
                if (val == 'edit') _editPost();
                if (val == 'delete') _deletePost();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, color: brandNavy, size: 18),
                      SizedBox(width: 8),
                      Text('Edit Postingan'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, color: Colors.red, size: 18),
                      SizedBox(width: 8),
                      Text('Hapus Postingan', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: brandNavy,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: itemCount,
                    itemBuilder: (_, index) {
                      if (index == 0) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Post Original
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () => _openUserProfile(posterId, postProfile),
                                  child: UnitasAvatar(
                                    initials: _initials(postProfile),
                                    color: _colorFor(posterId ?? posterName),
                                    size: 40,
                                    avatarUrl: postProfile['avatar_url']?.toString(),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _openUserProfile(posterId, postProfile),
                                        child: Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                posterName,
                                                style: subTitle.copyWith(fontSize: 15),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(_timeAgo(widget.post['created_at']?.toString()), style: caption),
                                          ],
                                        ),
                                      ),
                                      if (posterProdi.isNotEmpty || posterAngkatan.isNotEmpty)
                                        Text(
                                          '$posterProdi $posterAngkatan'.trim(),
                                          style: caption,
                                        ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _postContent,
                                        style: body.copyWith(color: textPrimary, height: 1.45),
                                      ),
                                      if (postImageUrl != null && postImageUrl.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        GestureDetector(
                                          onTap: () => _openImageViewer(postImageUrl),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.network(
                                              postImageUrl,
                                              fit: BoxFit.cover,
                                              cacheWidth: imageCacheWidth,
                                              loadingBuilder: (_, child, progress) {
                                                if (progress == null) return child;
                                                return Container(
                                                  height: 180,
                                                  width: double.infinity,
                                                  color: card,
                                                  alignment: Alignment.center,
                                                  child: const CircularProgressIndicator(strokeWidth: 2),
                                                );
                                              },
                                              errorBuilder: (_, _, _) => const SizedBox(),
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          InkWell(
                                            onTap: _toggleLike,
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    _liked ? Icons.favorite : Icons.favorite_border,
                                                    size: 19,
                                                    color: _liked ? const Color(0xFFE54D4D) : dim1,
                                                  ),
                                                  const SizedBox(width: 5),
                                                  Text(
                                                    '$_likesCount',
                                                    style: caption.copyWith(
                                                      color: _liked ? const Color(0xFFE54D4D) : dim1,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Row(
                                            children: [
                                              Icon(Icons.chat_bubble_outline, size: 18, color: dim1),
                                              const SizedBox(width: 5),
                                              Text(
                                                '${_comments.length}',
                                                style: caption.copyWith(color: dim1, fontWeight: FontWeight.w600),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1, thickness: 1, color: borderColor),
                            ),
                            Text(
                              'Komentar (${_comments.length})',
                              style: label,
                            ),
                            const SizedBox(height: 14),
                            if (_loading)
                              const Padding(
                                padding: EdgeInsets.only(top: 24),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            else if (_error != null && _comments.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 20),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Text(_error!, style: caption.copyWith(color: dim1)),
                                      const SizedBox(height: 8),
                                      TextButton(
                                        onPressed: _load,
                                        child: const Text('Coba Lagi'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (_comments.isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Center(
                                  child: Text('Belum ada komentar. Jadilah yang pertama!', style: caption),
                                ),
                              ),
                          ],
                        );
                      }

                      final c = topComments[index - 1];
                      final cid = c['id']?.toString() ?? '';
                      final replies = repliesByParent[cid] ?? [];
                      final isExpanded = _expandedThreads.contains(cid) || replies.length <= 2;
                      final visibleReplies = isExpanded ? replies : replies.take(1).toList();

                      return RepaintBoundary(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCommentRow(c, isReply: false),
                            if (replies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 38),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border(left: BorderSide(color: borderColor, width: 1.5)),
                                  ),
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ...visibleReplies.map(
                                        (r) => _buildCommentRow(r, isReply: true, rootParentId: cid),
                                      ),
                                      if (replies.length > 2)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 12),
                                          child: InkWell(
                                            onTap: () {
                                              setState(() {
                                                if (_expandedThreads.contains(cid)) {
                                                  _expandedThreads.remove(cid);
                                                } else {
                                                  _expandedThreads.add(cid);
                                                }
                                              });
                                            },
                                            child: Text(
                                              isExpanded
                                                  ? 'Sembunyikan balasan'
                                                  : 'Lihat ${replies.length - 1} balasan lainnya',
                                              style: caption.copyWith(
                                                color: brandNavy,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Reply indicator + Comment input
          Container(
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_replyToName != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          color: card,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Membalas $_replyToName',
                                  style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                ),
                              ),
                              InkWell(
                                onTap: _cancelReply,
                                child: Icon(Icons.close, size: 16, color: dim1),
                              ),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _commentCtrl,
                                focusNode: _commentFocus,
                                minLines: 1,
                                maxLines: 3,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _submitComment(),
                                decoration: InputDecoration(
                                  hintText: _replyToName != null
                                      ? 'Tulis balasan untuk $_replyToName…'
                                      : 'Tulis komentar…',
                                  hintStyle: caption,
                                  filled: true,
                                  fillColor: card,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(22),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: _submitting ? null : _submitComment,
                              style: IconButton.styleFrom(backgroundColor: brandNavy),
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.send, color: Colors.white, size: 19),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentRow(
    Map<String, dynamic> c, {
    required bool isReply,
    String? rootParentId,
  }) {
    final p = _profile(c);
    final userRaw = c['user'];
    final authorId = ((userRaw is Map ? userRaw['id'] : null) ?? c['user_id'])?.toString();
    final rawName = (p['full_name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'Alumni Unitas' : rawName;

    return Padding(
      padding: EdgeInsets.only(bottom: isReply ? 12 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openUserProfile(authorId, p),
            child: UnitasAvatar(
              initials: _initials(p),
              color: _colorFor(authorId ?? name),
              size: isReply ? 26 : 32,
              avatarUrl: p['avatar_url']?.toString(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: GestureDetector(
                              onTap: () => _openUserProfile(authorId, p),
                              child: Text(
                                name,
                                style: body.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: textPrimary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_timeAgo(c['created_at']?.toString()), style: caption.copyWith(fontSize: 11)),
                        ],
                      ),
                    ),
                    if (_isMyComment(c) && c['id'] != null)
                      InkWell(
                        onTap: () => _deleteComment(c['id'].toString()),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline, size: 15, color: Colors.red),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                _buildCommentContent(c['content']?.toString() ?? ''),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _startReply(c, rootParentId: isReply ? rootParentId : null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      'Balas',
                      style: caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: dim1,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentContent(String text) {
    final baseStyle = body.copyWith(fontSize: 13.5, color: textPrimary, height: 1.35);
    final match = RegExp(r'^(@\S+)(\s+.*)?$', dotAll: true).firstMatch(text);
    if (match == null) {
      return Text(text, style: baseStyle);
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: match.group(1),
            style: baseStyle.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
          ),
          if (match.group(2) != null)
            TextSpan(text: match.group(2), style: baseStyle),
        ],
      ),
    );
  }
}

class _EditPostDialog extends StatefulWidget {
  final String initialContent;
  const _EditPostDialog({required this.initialContent});

  @override
  State<_EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<_EditPostDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialContent);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Postingan'),
      content: TextField(
        controller: _ctrl,
        maxLines: 5,
        minLines: 2,
        decoration: const InputDecoration(
          hintText: 'Tulis pembaruan…',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: brandNavy),
          onPressed: () {
            final txt = _ctrl.text.trim();
            if (txt.isNotEmpty) Navigator.pop(context, txt);
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

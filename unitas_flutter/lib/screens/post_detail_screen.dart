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
  bool _submitting = false;
  final _commentCtrl = TextEditingController();
  final _commentFocus = FocusNode();
  Map<String, dynamic>? _me;

  late int _likesCount;
  late String _postContent;
  bool _liked = false;
  String? _replyToCommentId;
  String? _replyToName;
  final Set<String> _expandedThreads = {};

  @override
  void initState() {
    super.initState();
    _postContent = (widget.post['content'] ?? '').toString();
    _likesCount = (widget.post['likes_count'] as num?)?.toInt() ?? 0;
    if (_likesCount < 0) _likesCount = 0;
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  String? get _myId => (_me?['user_id'] ?? _me?['id'])?.toString();

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        PostsService.getComments(widget.post['id'].toString()),
        UsersService.getMe().catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        setState(() {
          _comments = results[0] as List<Map<String, dynamic>>;
          _me = results[1] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isMyComment(Map<String, dynamic> c) {
    final myId = _myId;
    final authorId = (c['user']?['id'] ?? c['user_id'])?.toString();
    return myId != null && myId.isNotEmpty && authorId != null && myId == authorId;
  }

  Future<void> _toggleLike() async {
    final postId = widget.post['id']?.toString();
    if (postId == null) return;
    final wasLiked = _liked;
    setState(() {
      _liked = !wasLiked;
      _likesCount = (_likesCount + (wasLiked ? -1 : 1)).clamp(0, 999999);
    });
    try {
      final serverLiked = await PostsService.toggleLike(postId);
      if (mounted && serverLiked != _liked) {
        setState(() {
          _liked = serverLiked;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = wasLiked;
          _likesCount = (_likesCount + (wasLiked ? 1 : -1)).clamp(0, 999999);
        });
      }
    }
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
    try {
      await PostsService.deleteComment(widget.post['id'].toString(), commentId);
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
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final parentId = _replyToCommentId;
      final newComment = await PostsService.addComment(
        widget.post['id'].toString(),
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
    final postId = widget.post['id']?.toString();
    if (postId == null) return;
    final ctrl = TextEditingController(text: _postContent);
    final updated = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit Postingan'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 2,
          decoration: const InputDecoration(
            hintText: 'Tulis pembaruan…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brandNavy),
            onPressed: () {
              final txt = ctrl.text.trim();
              if (txt.isNotEmpty) Navigator.pop(c, txt);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (updated == null) return;

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
              child: Image.network(url, fit: BoxFit.contain),
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
    if (confirm != true) return;

    try {
      await PostsService.deletePost(widget.post['id'].toString());
      widget.onPostDeleted();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus postingan')),
        );
      }
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
      if (p is List && p.isNotEmpty) return Map<String, dynamic>.from(p.first);
      if (p is Map) return Map<String, dynamic>.from(p);
    }
    return {};
  }

  String _initials(Map<String, dynamic> p) {
    final ini = (p['initials'] ?? '').toString().trim();
    if (ini.isNotEmpty) return ini;
    final name = (p['full_name'] ?? 'AL').toString().trim();
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
    final posterId = (widget.post['user']?['id'] ?? widget.post['user_id'])?.toString();
    final amIOwner = _myId != null && posterId != null && _myId == posterId;

    final topComments = _comments.where((c) => c['parent_id'] == null).toList();
    final repliesByParent = <String, List<Map<String, dynamic>>>{};
    for (final c in _comments) {
      final pid = c['parent_id']?.toString();
      if (pid != null && pid.isNotEmpty) {
        repliesByParent.putIfAbsent(pid, () => []).add(c);
      }
    }

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        title: Text('Postingan', style: heading.copyWith(fontSize: 18)),
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
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
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Post Original
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _openUserProfile(posterId, postProfile),
                          child: UnitasAvatar(
                            initials: _initials(postProfile),
                            color: _colorFor(posterId ?? postProfile['full_name'] ?? '?'),
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
                                    Text(
                                      postProfile['full_name'] ?? 'Alumni Unitas',
                                      style: subTitle.copyWith(fontSize: 15),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(_timeAgo(widget.post['created_at']?.toString()), style: caption),
                                  ],
                                ),
                              ),
                              if (postProfile['prodi'] != null)
                                Text(
                                  '${postProfile['prodi']} ${postProfile['angkatan'] ?? ''}'.trim(),
                                  style: caption,
                                ),
                              const SizedBox(height: 8),
                              Text(
                                _postContent,
                                style: body.copyWith(color: textPrimary, height: 1.45),
                              ),
                              if (widget.post['image_url'] != null) ...[
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: () => _openImageViewer(widget.post['image_url'].toString()),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      widget.post['image_url'].toString(),
                                      fit: BoxFit.cover,
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
                    const Padding(
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
                    else if (_comments.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(child: Text('Belum ada komentar. Jadilah yang pertama!', style: caption)),
                      )
                    else
                      ...topComments.map((c) {
                        final cid = c['id']?.toString() ?? '';
                        final replies = repliesByParent[cid] ?? [];
                        final isExpanded = _expandedThreads.contains(cid) || replies.length <= 2;
                        final visibleReplies = isExpanded ? replies : replies.take(1).toList();

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildCommentRow(c, isReply: false),
                            if (replies.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 38),
                                child: Container(
                                  decoration: const BoxDecoration(
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
                        );
                      }),
                  ],
                ),
              ),
            ),
          ),

          // Reply indicator + Comment input
          Container(
            decoration: const BoxDecoration(
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
                                child: const Icon(Icons.close, size: 16, color: dim1),
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
    final authorId = (c['user']?['id'] ?? c['user_id'])?.toString();
    final name = (p['full_name'] ?? 'Alumni Unitas').toString();

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
                    GestureDetector(
                      onTap: () => _openUserProfile(authorId, p),
                      child: Text(
                        name,
                        style: body.copyWith(fontWeight: FontWeight.w600, fontSize: 13, color: textPrimary),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(_timeAgo(c['created_at']?.toString()), style: caption.copyWith(fontSize: 11)),
                    const Spacer(),
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

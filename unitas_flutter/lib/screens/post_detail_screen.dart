import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/posts_service.dart';
import '../core/api/users_service.dart';
import '../widgets/avatar.dart';

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
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _load();
  }
  
  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        PostsService.getComments(widget.post['id']),
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

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final newComment = await PostsService.addComment(widget.post['id'], text);
      setState(() {
        _comments.add(newComment);
        _commentCtrl.clear();
      });
      FocusScope.of(context).unfocus();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengirim komentar')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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
            child: const Text('Hapus', style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );
    if (confirm != true) return;
    
    try {
      await PostsService.deletePost(widget.post['id']);
      widget.onPostDeleted();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus postingan')));
    }
  }

  Map<String, dynamic> _profile(Map<String, dynamic> entity) {
    final user = entity['user'] as Map?;
    if (user == null) return <String, dynamic>{};
    final profiles = user['user_profiles'];
    if (profiles is Map) return Map<String, dynamic>.from(profiles);
    if (profiles is List && profiles.isNotEmpty) return Map<String, dynamic>.from(profiles[0]);
    return <String, dynamic>{};
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}j';
    return '${diff.inDays}h';
  }

  Color _colorFor(String text) {
    final colors = [
      const Color(0xFF1E3A5F), const Color(0xFF2E7D32),
      const Color(0xFFC62828), const Color(0xFFE65100),
      const Color(0xFF0277BD), const Color(0xFF6A1B9A),
    ];
    final hash = text.hashCode.abs();
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final postProfile = _profile(widget.post);
    final posterId = widget.post['user']?['id'];
    final amIOwner = _me != null && _me!['id'] == posterId;

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        title: const Text('Postingan', style: TextStyle(color: brandNavy, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: surface,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: brandNavy),
        actions: [
          if (amIOwner)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _deletePost,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Post Original
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    UnitasAvatar(initials: postProfile['initials'] ?? '?', color: _colorFor(postProfile['full_name'] ?? '?'), size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(postProfile['full_name'] ?? 'Alumni Unitas', style: body.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 8),
                              Text(_timeAgo(widget.post['created_at']), style: caption),
                            ],
                          ),
                          if (postProfile['prodi'] != null)
                            Text('${postProfile['prodi']} ${postProfile['angkatan'] ?? ''}', style: caption),
                          const SizedBox(height: 8),
                          Text(widget.post['content'] ?? '', style: body),
                          if (widget.post['image_url'] != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(widget.post['image_url'], fit: BoxFit.cover),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 32),
                Text('Komentar', style: label),
                const SizedBox(height: 16),
                
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_comments.isEmpty)
                  Center(child: Text('Belum ada komentar.', style: caption))
                else
                  ..._comments.asMap().entries.map((e) {
                    final i = e.key;
                    final c = e.value;
                    final p = _profile(c);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          UnitasAvatar(initials: p['initials'] ?? '?', color: _colorFor(p['full_name'] ?? '?'), size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(p['full_name'] ?? 'Alumni Unitas', style: body.copyWith(fontWeight: FontWeight.w600, fontSize: 13)),
                                    const SizedBox(width: 8),
                                    Text(_timeAgo(c['created_at']), style: caption.copyWith(fontSize: 11)),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(c['content'] ?? '', style: body.copyWith(fontSize: 14)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
              ],
            ),
          ),
          
          // Comment input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      decoration: InputDecoration(
                        hintText: 'Tulis komentar...',
                        hintStyle: body.copyWith(color: dim2),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: _submitting 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.send, color: brandNavy),
                    onPressed: _submitting ? null : _submitComment,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

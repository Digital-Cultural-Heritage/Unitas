import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/posts_service.dart';
import '../core/api/stats_service.dart';
import '../core/api/users_service.dart';
import '../core/api/auth_service.dart';
import '../widgets/avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _leaderboard = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _me;
  bool _loadingFeed = true;
  bool _loadingMeta = true;
  bool _posting = false;
  final Map<String, bool> _likedMap = {};
  final _postCtrl = TextEditingController();

  @override
  void dispose() {
    _postCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Load me, stats, leaderboard in parallel
    _loadMeta();
    // Load feed
    try {
      final posts = await PostsService.getFeed();
      if (mounted) setState(() { _posts = posts; _loadingFeed = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingFeed = false);
    }
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        StatsService.getStats(),
        PostsService.getLeaderboard(limit: 3),
        UsersService.getMe().catchError((_) => {}),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _leaderboard = (results[1] as List).cast<Map<String, dynamic>>();
          _me = results[2] as Map<String, dynamic>?;
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _toggleLike(String postId) async {
    final wasLiked = _likedMap[postId] ?? false;
    setState(() {
      _likedMap[postId] = !wasLiked;
      final idx = _posts.indexWhere((p) => p['id'] == postId);
      if (idx != -1) {
        _posts[idx] = Map.from(_posts[idx])
          ..['likes_count'] = (_posts[idx]['likes_count'] ?? 0) + (wasLiked ? -1 : 1);
      }
    });
    try {
      await PostsService.toggleLike(postId);
    } catch (_) {
      // Revert on error
      if (mounted) setState(() {
        _likedMap[postId] = wasLiked;
        final idx = _posts.indexWhere((p) => p['id'] == postId);
        if (idx != -1) {
          _posts[idx] = Map.from(_posts[idx])
            ..['likes_count'] = (_posts[idx]['likes_count'] ?? 0) + (wasLiked ? 1 : -1);
        }
      });
    }
  }

  String _initials(Map<String, dynamic> post) {
    final profile = _profile(post);
    if (profile['initials'] != null) return profile['initials'];
    final name = profile['full_name'] ?? '';
    final parts = name.split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Map<String, dynamic> _profile(Map<String, dynamic> post) {
    final user = post['user'];
    if (user == null) return {};
    final profiles = user['user_profiles'];
    if (profiles is List && profiles.isNotEmpty) return Map<String, dynamic>.from(profiles[0]);
    return {};
  }

  String _meInitials() {
    if (_me == null) return '?';
    final name = _me!['full_name'] ?? '';
    final parts = name.split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
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

  Future<void> _createPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);
    try {
      await PostsService.createPost(text);
      _postCtrl.clear();
      FocusScope.of(context).unfocus();
      _load(); // Reload feed to show new post
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Postingan berhasil dikirim')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal mengirim postingan')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  static const List<Color> _avatarColors = [
    Color(0xFF2B4F7A), Color(0xFF2D6A27), Color(0xFF5C3D8C),
    Color(0xFF7A4B2B), Color(0xFF2D6060), Color(0xFF6B2A4F),
  ];

  Color _colorFor(int idx) => _avatarColors[idx % _avatarColors.length];

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      color: brandNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildSearch(),
              _buildStats(),
              _buildComposer(),
              _buildLeaderboard(),
              _buildFeed(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _me?['full_name'] ?? '...';
    final initials = _meInitials();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Selamat datang kembali', style: caption),
              Text(name, style: heading, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Row(children: [
            Stack(children: [
              const Icon(Icons.notifications_outlined, color: Color(0x991E3A5F), size: 22),
              Positioned(top: 0, right: 0, child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(color: brandNavy, shape: BoxShape.circle,
                  border: Border.all(color: brandBg, width: 1.5)),
              )),
            ]),
            const SizedBox(width: 10),
            UnitasAvatar(initials: initials, color: _colorFor(0), size: 36),
          ]),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(children: [
        const Icon(Icons.search, color: Color(0x611E3A5F), size: 16),
        const SizedBox(width: 10),
        Text('Cari alumni, acara, lowongan…', style: body.copyWith(color: dim2)),
      ]),
    );
  }

  Widget _buildStats() {
    final totalAlumni = _stats['total_alumni'];
    final activeEvents = _stats['active_events'];
    final stats = [
      {'val': totalAlumni != null ? '$totalAlumni+' : '—', 'label': 'Total Alumni', 'sub': 'di seluruh Indonesia'},
      {'val': activeEvents?.toString() ?? '—', 'label': 'Acara Aktif', 'sub': 'saat ini'},
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      child: Row(children: stats.map((s) => Expanded(
        child: Container(
          margin: EdgeInsets.only(right: s == stats.first ? 10 : 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: _loadingMeta
            ? const Center(child: SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: brandNavy)))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['val']!, style: statStyle),
                const SizedBox(height: 4),
                Text(s['label']!, style: subTitle),
                Text(s['sub']!, style: caption),
              ]),
        ),
      )).toList()),
    );
  }

  Widget _buildComposer() {
    final initials = _meInitials();
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          UnitasAvatar(initials: initials, color: _colorFor(0), size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _postCtrl,
              maxLines: null,
              style: body,
              decoration: InputDecoration(
                hintText: 'Bagikan sesuatu…',
                hintStyle: body.copyWith(color: dim2),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          // Hanya foto (video dihapus)
          Row(children: [
            Icon(Icons.image_outlined, color: dim2, size: 16),
            const SizedBox(width: 5),
            Text('Foto', style: caption),
          ]),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brandNavy, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: _posting ? null : _createPost,
            child: _posting 
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('Posting', style: buttonStyle),
          ),
        ]),
      ]),
    );
  }

  Widget _buildLeaderboard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Papan Peringkat', style: label),
            const Icon(Icons.emoji_events_outlined, color: Color(0xFF1E3A5F), size: 16),
          ]),
        ),
        const Divider(height: 1, color: Color(0x1A1E3A5F)),
        if (_loadingMeta)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2)),
          )
        else if (_leaderboard.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Belum ada data', style: caption.copyWith(color: dim2)),
          )
        else
          ..._leaderboard.asMap().entries.map((e) {
            final i = e.key; final item = e.value;
            final rank = item['rank'] ?? (i + 1);
            final name = item['full_name'] ?? '—';
            final pts  = item['points']?.toString() ?? '0';
            final ini  = item['initials'] ?? name.substring(0, name.length >= 2 ? 2 : 1);
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  rank == 1
                    ? const Icon(Icons.military_tech, color: brandNavy, size: 16)
                    : SizedBox(width: 16, child: Text('$rank', style: caption, textAlign: TextAlign.center)),
                  const SizedBox(width: 12),
                  UnitasAvatar(initials: ini, color: _colorFor(i), size: 34),
                  const SizedBox(width: 12),
                  Expanded(child: Text(name, style: subTitle)),
                  Text(pts, style: subTitle.copyWith(
                    color: rank == 1 ? brandNavy : dim1, fontWeight: FontWeight.w700)),
                ]),
              ),
              if (i < _leaderboard.length - 1) const Divider(height: 1, color: Color(0x1A1E3A5F)),
            ]);
          }),
      ]),
    );
  }

  Widget _buildFeed() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Aktivitas Terbaru', style: label),
        const SizedBox(height: 14),
        if (_loadingFeed)
          const Center(child: Padding(
            padding: EdgeInsets.all(40),
            child: CircularProgressIndicator(color: brandNavy),
          ))
        else if (_posts.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(children: [
              const Icon(Icons.article_outlined, color: Color(0x611E3A5F), size: 40),
              const SizedBox(height: 12),
              Text('Belum ada postingan', style: subTitle),
              const SizedBox(height: 4),
              Text('Jadilah yang pertama berbagi!', style: caption.copyWith(color: dim2)),
            ]),
          )
        else
          ..._posts.asMap().entries.map((e) {
            final i = e.key; final post = e.value;
            final id = post['id']?.toString() ?? '$i';
            final profile = _profile(post);
            final name = profile['full_name'] ?? 'Alumni';
            final prodi = profile['prodi'] ?? '';
            final angk  = profile['angkatan'] ?? '';
            final initials = _initials(post);
            final likes = post['likes_count'] ?? 0;
            final comments = post['comments_count'] ?? 0;
            final liked = _likedMap[id] ?? false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: surface, borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  UnitasAvatar(initials: initials, color: _colorFor(i)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: subTitle),
                    Text('$prodi · $angk · ${_timeAgo(post['created_at'])}', style: caption),
                  ])),
                  const Icon(Icons.more_vert, color: Color(0x611E3A5F), size: 18),
                ]),
                const SizedBox(height: 10),
                Text(post['content'] ?? '', style: body.copyWith(height: 1.6)),
                if (post['image_url'] != null) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(post['image_url'], fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ],
                const SizedBox(height: 14),
                Row(children: [
                  GestureDetector(
                    onTap: () => _toggleLike(id),
                    child: Row(children: [
                      Icon(liked ? Icons.favorite : Icons.favorite_border,
                        color: liked ? const Color(0xFFE54D4D) : dim2, size: 16),
                      const SizedBox(width: 5),
                      Text('$likes', style: caption.copyWith(
                        color: liked ? const Color(0xFFE54D4D) : dim2,
                        fontWeight: FontWeight.w500)),
                    ]),
                  ),
                  const SizedBox(width: 18),
                  Row(children: [
                    Icon(Icons.chat_bubble_outline, color: dim2, size: 16),
                    const SizedBox(width: 5),
                    Text('$comments', style: caption.copyWith(fontWeight: FontWeight.w500)),
                  ]),
                  const Spacer(),
                  Icon(Icons.share_outlined, color: dim2, size: 16),
                ]),
              ]),
            );
          }),
      ]),
    );
  }
}

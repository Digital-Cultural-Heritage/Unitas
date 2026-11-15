import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/posts_service.dart';
import '../core/api/stats_service.dart';
import '../core/api/users_service.dart';
import '../core/api/events_service.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/image_cropper_dialog.dart';
import '../core/utils/image_validator.dart';
import 'package:image_picker/image_picker.dart';
import 'post_detail_screen.dart';


class HomeScreen extends StatefulWidget {
  final int refreshTrigger;
  final VoidCallback? onOpenEvents;
  final VoidCallback? onOpenDirectory;
  const HomeScreen({
    super.key,
    this.refreshTrigger = 0,
    this.onOpenEvents,
    this.onOpenDirectory,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _leaderboard = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _me;
  bool _loadingFeed = true;
  bool _loadingMeta = true;
  bool _posting = false;
  final Map<String, bool> _likedMap = {};
  final _postCtrl = TextEditingController();
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      _avatarVersion = DateTime.now().millisecondsSinceEpoch;
      _load();
    }
  }

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
        UsersService.getMe().catchError((_) => <String, dynamic>{}),
        EventsService.getEvents().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, dynamic>;
          _leaderboard = (results[1] as List).cast<Map<String, dynamic>>();
          _me = results[2] as Map<String, dynamic>?;
          _upcomingEvents = (results[3] as List).cast<Map<String, dynamic>>().take(3).toList();
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _toggleLike(String postId) async {
    final wasLiked = _likedMap[postId] ?? false;
    final idx = _posts.indexWhere((p) => p['id'] == postId);
    final originalLikes = idx != -1 ? ((_posts[idx]['likes_count'] ?? 0) as int) : 0;

    setState(() {
      _likedMap[postId] = !wasLiked;
      if (idx != -1) {
        final next = originalLikes + (wasLiked ? -1 : 1);
        _posts[idx] = Map.from(_posts[idx])..['likes_count'] = next < 0 ? 0 : next;
      }
    });
    try {
      final serverLiked = await PostsService.toggleLike(postId);
      if (mounted) {
        setState(() {
          _likedMap[postId] = serverLiked;
          final curIdx = _posts.indexWhere((p) => p['id'] == postId);
          if (curIdx != -1) {
            final expectedLikes = originalLikes + (serverLiked ? 1 : -1);
            _posts[curIdx] = Map.from(_posts[curIdx])
              ..['likes_count'] = expectedLikes < 0 ? 0 : expectedLikes;
          }
        });
      }
    } catch (_) {
      // Revert on error
      if (mounted) {
        setState(() {
          _likedMap[postId] = wasLiked;
          final curIdx = _posts.indexWhere((p) => p['id'] == postId);
          if (curIdx != -1) {
            _posts[curIdx] = Map.from(_posts[curIdx])
              ..['likes_count'] = originalLikes < 0 ? 0 : originalLikes;
          }
        });
      }
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
    final user = post['user'] as Map?;
    if (user == null) return <String, dynamic>{};
    final profiles = user['user_profiles'];
    if (profiles is Map) return Map<String, dynamic>.from(profiles);
    if (profiles is List && profiles.isNotEmpty) return Map<String, dynamic>.from(profiles[0]);
    return <String, dynamic>{};
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

  Future<void> _pickImage({VoidCallback? onPicked}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      ImageValidator.validate(bytes, picked.name);
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    final cropped = await showImageCropDialog(
      context,
      bytes,
      aspectRatio: 4 / 3,
      isCircle: false,
      title: 'Sesuaikan Foto Postingan',
    );
    if (cropped != null && mounted) {
      setState(() {
        _selectedImage = picked;
        _selectedImageBytes = cropped;
      });
      onPicked?.call();
    }
  }

  Future<bool> _createPost() async {
    final text = _postCtrl.text.trim();
    if (text.isEmpty && _selectedImage == null) return false;
    setState(() => _posting = true);
    try {
      String? imageUrl;
      if (_selectedImage != null) {
        final bytes = _selectedImageBytes ?? await _selectedImage!.readAsBytes();
        imageUrl = await PostsService.uploadImage(bytes, 'post.png');
      }
      await PostsService.createPost(text, imageUrl: imageUrl);
      _postCtrl.clear();
      _selectedImage = null;
      _selectedImageBytes = null;
      if (mounted) FocusScope.of(context).unfocus();
      _load(); // Reload feed to show new post
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Postingan berhasil dikirim')),
        );
      }
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal mengirim postingan')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  static const List<Color> _avatarColors = [
    Color(0xFF2B4F7A), Color(0xFF2D6A27), Color(0xFF5C3D8C),
    Color(0xFF7A4B2B), Color(0xFF2D6060), Color(0xFF6B2A4F),
  ];

  Color _colorFor(String text) {
    final hash = text.hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  bool _isMyPost(Map<String, dynamic> post) {
    final myId = _me?['id'] ?? _me?['user_id'];
    final posterId = post['user']?['id'] ?? post['user_id'];
    return myId != null && posterId != null && myId == posterId;
  }

  Future<void> _deletePost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Postingan'),
        content: const Text('Yakin ingin menghapus postingan ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await PostsService.deletePost(postId);
      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p['id']?.toString() == postId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Postingan berhasil dihapus')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus postingan')),
        );
      }
    }
  }

  String? _avatarWithVersion(dynamic rawUrl) {
    final u = rawUrl?.toString().trim();
    if (u == null || u.isEmpty) return null;
    final sep = u.contains('?') ? '&' : '?';
    return '$u${sep}v=$_avatarVersion';
  }

  void _openComposerSheet({bool pickImageImmediately = false}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (pickImageImmediately && _selectedImage == null) {
              pickImageImmediately = false;
              Future.microtask(() => _pickImage(onPicked: () => setSheetState(() {})));
            }
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20, 14, 20, MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: dim3, borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Buat Postingan', style: subTitle.copyWith(fontSize: 16)),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: _posting
                            ? null
                            : () async {
                                setSheetState(() {});
                                final ok = await _createPost();
                                if (ok && ctx.mounted) Navigator.pop(ctx);
                              },
                        child: _posting
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Posting', style: buttonStyle),
                      ),
                    ],
                  ),
                  const Divider(height: 20, color: Color(0x1A1E3A5F)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      UnitasAvatar(
                        initials: _meInitials(),
                        color: _colorFor(_me?['id'] ?? 'me'),
                        size: 36,
                        avatarUrl: _avatarWithVersion(_me?['avatar_url']),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _postCtrl,
                          autofocus: true,
                          maxLines: 6,
                          minLines: 3,
                          style: body.copyWith(color: textPrimary),
                          decoration: InputDecoration(
                            hintText: 'Apa yang ingin kamu bagikan?',
                            hintStyle: body.copyWith(color: dim2),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_selectedImageBytes != null) ...[
                    const SizedBox(height: 12),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _selectedImageBytes!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 8, right: 8,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedImage = null;
                                _selectedImageBytes = null;
                              });
                              setSheetState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: const BoxDecoration(
                                color: Colors.black54, shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  InkWell(
                    onTap: () => _pickImage(onPicked: () => setSheetState(() {})),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.image_outlined, color: brandGreen, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _selectedImage != null ? 'Ganti Foto' : 'Tambah Foto',
                            style: caption.copyWith(color: textPrimary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openComposerSheet(),
        backgroundColor: brandNavy,
        foregroundColor: Colors.white,
        elevation: 3,
        child: const Icon(Icons.edit_outlined, size: 22),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: _load,
              color: brandNavy,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 84),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildComposerBar(),
                    _buildHighlights(),
                    _buildFeed(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _me?['full_name'] ?? 'Alumni';
    final initials = _meInitials();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: brandNavy,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              'U',
              style: subTitle.copyWith(color: brandGold, fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Unitas', style: heading.copyWith(fontSize: 20)),
                Text('Halo, $name', style: caption, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: borderColor),
                ),
                child: const Icon(Icons.notifications_outlined, color: brandNavy, size: 20),
              ),
              Positioned(
                top: 6, right: 6,
                child: Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: brandGold,
                    shape: BoxShape.circle,
                    border: Border.all(color: surface, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          UnitasAvatar(
            initials: initials,
            color: _colorFor(_me?['id'] ?? 'me'),
            size: 36,
            avatarUrl: _avatarWithVersion(_me?['avatar_url']),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerBar() {
    final firstName = ((_me?['full_name'] as String?) ?? 'Alumni').split(' ').first;
    final initials = _meInitials();
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          UnitasAvatar(
            initials: initials,
            color: _colorFor(_me?['id'] ?? 'me'),
            size: 34,
            avatarUrl: _avatarWithVersion(_me?['avatar_url']),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _openComposerSheet(),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: brandBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  'Apa yang kamu pikirkan, $firstName?',
                  style: body.copyWith(color: dim2, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _openComposerSheet(pickImageImmediately: true),
            borderRadius: BorderRadius.circular(10),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.image_outlined, color: brandGreen, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlights() {
    final totalAlumni = _stats['total_alumni'];
    final activeEvents = _stats['active_events'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
          child: Text('Sorotan & Peringkat', style: label),
        ),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              InkWell(
                onTap: widget.onOpenDirectory,
                borderRadius: BorderRadius.circular(14),
                child: _highlightStatCard(
                  icon: Icons.people_alt_outlined,
                  value: totalAlumni != null ? '$totalAlumni+' : '—',
                  title: 'Total Alumni',
                  subtitle: 'se-Indonesia',
                  accent: brandNavy,
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: widget.onOpenEvents,
                borderRadius: BorderRadius.circular(14),
                child: _highlightStatCard(
                  icon: Icons.event_available_outlined,
                  value: activeEvents?.toString() ?? '—',
                  title: 'Acara Aktif',
                  subtitle: 'saat ini',
                  accent: brandGold,
                ),
              ),
              ..._upcomingEvents.map((ev) => Padding(
                padding: const EdgeInsets.only(left: 10),
                child: _highlightEventCard(ev),
              )),
              ..._leaderboard.asMap().entries.map((e) {
                final i = e.key;
                final item = e.value;
                final rank = item['rank'] ?? (i + 1);
                final name = (item['full_name'] ?? '—').toString();
                final pts = item['points']?.toString() ?? '0';
                final ini = item['initials'] ??
                    name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
                return Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Container(
                    width: 132,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: rank == 1 ? brandGold.withValues(alpha: 0.6) : borderColor,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            UnitasAvatar(
                              initials: ini,
                              color: _colorFor(item['user_id'] ?? name),
                              size: 30,
                              avatarUrl: _avatarWithVersion(item['avatar_url']),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: rank == 1 ? brandGold.withValues(alpha: 0.2) : card,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '#$rank',
                                style: label.copyWith(
                                  color: rank == 1 ? brandNavy : dim1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: subTitle.copyWith(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text('$pts poin', style: caption),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _highlightEventCard(Map<String, dynamic> ev) {
    final cover = ev['cover_url']?.toString();
    final dt = DateTime.tryParse(ev['event_date']?.toString() ?? '');
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN', 'JUL', 'AGU', 'SEP', 'OKT', 'NOV', 'DES'];
    final dateBadge = dt != null ? '${dt.day} ${months[dt.month - 1]}' : 'ACARA';

    return InkWell(
      onTap: widget.onOpenEvents,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 186,
        decoration: BoxDecoration(
          color: brandNavy,
          borderRadius: BorderRadius.circular(14),
          image: cover != null && cover.isNotEmpty
              ? DecorationImage(image: NetworkImage(cover), fit: BoxFit.cover)
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.25),
                brandNavy.withValues(alpha: 0.88),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: brandGold,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dateBadge,
                      style: label.copyWith(color: brandNavy, fontWeight: FontWeight.w800, fontSize: 10),
                    ),
                  ),
                  Text(
                    (ev['category'] ?? '').toString(),
                    style: caption.copyWith(color: Colors.white70, fontSize: 10.5),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ev['title'] ?? 'Acara Alumni',
                    style: subTitle.copyWith(color: Colors.white, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    ev['location'] ?? '',
                    style: caption.copyWith(color: Colors.white70, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _highlightStatCard({
    required IconData icon,
    required String value,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    return Container(
      width: 132,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: _loadingMeta
          ? const HighlightSkeletonContent()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: accent, size: 18),
                    Text(value, style: statStyle.copyWith(fontSize: 20)),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: subTitle.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(subtitle, style: caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildFeed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          child: Text('Aktivitas Terbaru', style: label),
        ),
        if (_loadingFeed)
          const FeedSkeletonList()
        else if (_posts.isEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 18),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: [
                const Icon(Icons.article_outlined, color: Color(0x611E3A5F), size: 40),
                const SizedBox(height: 12),
                Text('Belum ada postingan', style: subTitle),
                const SizedBox(height: 4),
                Text('Jadilah yang pertama berbagi!', style: caption.copyWith(color: dim2)),
              ],
            ),
          )
        else
          ..._posts.asMap().entries.map((e) {
            final i = e.key;
            final post = e.value;
            final id = post['id']?.toString() ?? '$i';
            final profile = _profile(post);
            final name = profile['full_name'] ?? 'Alumni';
            final prodi = profile['prodi'] ?? '';
            final angk = profile['angkatan'] ?? '';
            final initials = _initials(post);
            final rawLikes = (post['likes_count'] as num?)?.toInt() ?? 0;
            final likes = rawLikes < 0 ? 0 : rawLikes;
            final rawComments = (post['comments_count'] as num?)?.toInt() ?? 0;
            final comments = rawComments < 0 ? 0 : rawComments;
            final liked = _likedMap[id] ?? false;
            final metaLine = [
              if (prodi.toString().isNotEmpty) prodi,
              if (angk.toString().isNotEmpty) angk,
              _timeAgo(post['created_at']),
            ].where((s) => s.toString().isNotEmpty).join(' · ');

            return RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Container(
                  height: 6,
                  color: card,
                ),
                InkWell(
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: post,
                          onPostDeleted: _load,
                        ),
                      ),
                    );
                    _load();
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header post (avatar, nama, waktu, menu)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                        child: Row(
                          children: [
                            UnitasAvatar(
                              initials: initials,
                              color: _colorFor(post['user_id'] ?? name),
                              size: 40,
                              avatarUrl: _avatarWithVersion(profile['avatar_url']),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: subTitle.copyWith(fontSize: 15)),
                                  const SizedBox(height: 1),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          metaLine,
                                          style: caption,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(Icons.public, size: 12, color: dim2),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (_isMyPost(post))
                              PopupMenuButton<String>(
                                icon: Icon(Icons.more_horiz, color: dim1, size: 22),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onSelected: (val) {
                                  if (val == 'delete') _deletePost(id);
                                },
                                itemBuilder: (_) => const [
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
                      ),
                      // Teks caption
                      if ((post['content'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: Text(
                            post['content'],
                            style: body.copyWith(height: 1.45, color: textPrimary, fontSize: 14.5),
                          ),
                        ),
                      // Gambar full-bleed (mentok kiri-kanan)
                      if (post['image_url'] != null)
                        Image.network(
                          post['image_url'],
                          width: double.infinity,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => const SizedBox(),
                        ),
                      // Baris aksi (Like, Komentar, Share)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => _toggleLike(id),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                child: Row(
                                  children: [
                                    Icon(
                                      liked ? Icons.favorite : Icons.favorite_border,
                                      color: liked ? const Color(0xFFE54D4D) : dim1,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$likes',
                                      style: caption.copyWith(
                                        color: liked ? const Color(0xFFE54D4D) : dim1,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Row(
                                children: [
                                  Icon(Icons.chat_bubble_outline, color: dim1, size: 19),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$comments',
                                    style: caption.copyWith(
                                      color: dim1,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              child: Icon(Icons.share_outlined, color: dim1, size: 19),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            );
          }),
      ],
    );
  }
}

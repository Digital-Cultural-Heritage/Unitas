import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/posts_service.dart';
import '../core/api/stats_service.dart';
import '../core/api/users_service.dart';
import '../core/api/events_service.dart';
import '../core/api/jobs_service.dart';
import '../core/api/notifications_service.dart';
import '../core/api/messages_service.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/image_cropper_dialog.dart';
import '../core/utils/image_validator.dart';
import 'package:image_picker/image_picker.dart';
import 'post_detail_screen.dart';
import 'notifications_screen.dart';
import 'chat_list_screen.dart';
import 'alumni_profile_screen.dart';


class HomeScreen extends StatefulWidget {
  final int refreshTrigger;
  final VoidCallback? onOpenEvents;
  final VoidCallback? onOpenDirectory;
  final VoidCallback? onOpenJobs;
  final VoidCallback? onOpenProfile;
  const HomeScreen({
    super.key,
    this.refreshTrigger = 0,
    this.onOpenEvents,
    this.onOpenDirectory,
    this.onOpenJobs,
    this.onOpenProfile,
  });
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _upcomingEvents = [];
  List<Map<String, dynamic>> _latestJobs = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _me;
  int _unreadNotifications = 0;
  int _unreadMessages = 0;
  bool _loadingFeed = true;
  bool _loadingMeta = true;
  bool _loadingMoreFeed = false;
  bool _hasMoreFeed = true;
  int _feedPage = 1;
  String? _feedError;
  int _loadSeq = 0;
  bool _posting = false;
  final ValueNotifier<bool> _postingNotifier = ValueNotifier<bool>(false);
  bool _refreshingBadges = false;
  bool _pickingImage = false;
  bool _mutatingPost = false;
  final Set<String> _likingIds = {};
  final Map<String, bool> _likedMap = {};
  final _postCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _badgeTimer;
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
    WidgetsBinding.instance.removeObserver(this);
    _badgeTimer?.cancel();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _postCtrl.dispose();
    _postingNotifier.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _startBadgePolling();
    _load();
  }

  void _startBadgePolling() {
    _badgeTimer?.cancel();
    _badgeTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshBadges());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshBadges();
      _startBadgePolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _badgeTimer?.cancel();
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 250) {
      _loadMoreFeed();
    }
  }

  Future<void> _refreshBadges() async {
    if (_refreshingBadges) return;
    _refreshingBadges = true;
    try {
      final results = await Future.wait([
        NotificationsService.getNotifications(limit: 10).catchError((_) => <String, dynamic>{}),
        MessagesService.getConversations().catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        final notifRes = results[0];
        final msgRes = results[1];
        final nextNotif = (notifRes['unread_count'] as num?)?.toInt() ?? _unreadNotifications;
        final nextMsg = (msgRes['total_unread'] as num?)?.toInt() ?? _unreadMessages;
        if (nextNotif != _unreadNotifications || nextMsg != _unreadMessages) {
          setState(() {
            _unreadNotifications = nextNotif;
            _unreadMessages = nextMsg;
          });
        }
      }
    } catch (_) {
    } finally {
      _refreshingBadges = false;
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    _feedError = null;
    if (_posts.isEmpty && mounted) {
      setState(() => _loadingFeed = true);
    }
    // Load me, stats, events, and jobs in parallel
    _loadMeta();
    // Load feed (page 1)
    try {
      final posts = await PostsService.getFeed(page: 1);
      if (mounted && seq == _loadSeq) {
        setState(() {
          _posts = posts;
          _feedPage = 1;
          _hasMoreFeed = posts.length >= 20;
          _feedError = null;
          _loadingFeed = false;
        });
      }
    } catch (_) {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _loadingFeed = false;
          if (_posts.isEmpty) _feedError = 'Gagal memuat postingan';
        });
        if (_posts.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memperbarui beranda')),
          );
        }
      }
    }
  }

  Future<void> _loadMoreFeed() async {
    if (_loadingMoreFeed || !_hasMoreFeed || _loadingFeed) return;
    final seq = _loadSeq;
    setState(() => _loadingMoreFeed = true);
    try {
      final nextPage = _feedPage + 1;
      final more = await PostsService.getFeed(page: nextPage);
      if (mounted && seq == _loadSeq) {
        setState(() {
          _posts = [..._posts, ...more];
          _feedPage = nextPage;
          _hasMoreFeed = more.length >= 20;
          _loadingMoreFeed = false;
        });
      }
    } catch (_) {
      if (mounted && seq == _loadSeq) setState(() => _loadingMoreFeed = false);
    }
  }

  Future<void> _loadMeta() async {
    try {
      final results = await Future.wait([
        StatsService.getStats().catchError((_) => <String, dynamic>{}),
        UsersService.getMe().catchError((_) => <String, dynamic>{}),
        EventsService.getEvents().catchError((_) => <Map<String, dynamic>>[]),
        JobsService.getJobs().catchError((_) => <Map<String, dynamic>>[]),
        NotificationsService.getNotifications(limit: 10).catchError((_) => <String, dynamic>{}),
        MessagesService.getConversations().catchError((_) => <String, dynamic>{}),
      ]);
      if (mounted) {
        final rawStats = results[0];
        final rawMe = results[1];
        final rawEvents = results[2];
        final rawJobs = results[3];
        final rawNotif = results[4];
        final rawMsg = results[5];
        final notifRes = rawNotif is Map ? Map<String, dynamic>.from(rawNotif) : <String, dynamic>{};
        final msgRes = rawMsg is Map ? Map<String, dynamic>.from(rawMsg) : <String, dynamic>{};
        setState(() {
          _stats = rawStats is Map ? Map<String, dynamic>.from(rawStats) : <String, dynamic>{};
          _me = rawMe is Map && rawMe.isNotEmpty ? Map<String, dynamic>.from(rawMe) : _me;
          _upcomingEvents = rawEvents is List
              ? rawEvents.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).take(3).toList()
              : const [];
          _latestJobs = rawJobs is List
              ? rawJobs.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).take(3).toList()
              : const [];
          _unreadNotifications = (notifRes['unread_count'] as num?)?.toInt() ?? _unreadNotifications;
          _unreadMessages = (msgRes['total_unread'] as num?)?.toInt() ?? _unreadMessages;
          _loadingMeta = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMeta = false);
    }
  }

  Future<void> _toggleLike(String postId) async {
    if (postId.isEmpty || _likingIds.contains(postId)) return;
    _likingIds.add(postId);
    final wasLiked = _likedMap[postId] ?? false;
    final idx = _posts.indexWhere((p) => p['id']?.toString() == postId);
    final originalLikes = idx != -1 ? ((_posts[idx]['likes_count'] as num?)?.toInt() ?? 0) : 0;

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
          final curIdx = _posts.indexWhere((p) => p['id']?.toString() == postId);
          if (curIdx != -1) {
            final expectedLikes = serverLiked == wasLiked
                ? originalLikes
                : originalLikes + (serverLiked ? 1 : -1);
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
          final curIdx = _posts.indexWhere((p) => p['id']?.toString() == postId);
          if (curIdx != -1) {
            _posts[curIdx] = Map.from(_posts[curIdx])
              ..['likes_count'] = originalLikes < 0 ? 0 : originalLikes;
          }
        });
      }
    } finally {
      _likingIds.remove(postId);
    }
  }

  String _initials(Map<String, dynamic> post) {
    final profile = _profile(post);
    final rawIni = (profile['initials'] ?? '').toString().trim();
    if (rawIni.isNotEmpty) return rawIni.toUpperCase();
    final name = (profile['full_name'] ?? '').toString().trim();
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Map<String, dynamic> _profile(Map<String, dynamic> post) {
    final user = post['user'];
    if (user is! Map) return <String, dynamic>{};
    final profiles = user['user_profiles'];
    if (profiles is Map) return Map<String, dynamic>.from(profiles);
    if (profiles is List && profiles.isNotEmpty && profiles.first is Map) {
      return Map<String, dynamic>.from(profiles.first as Map);
    }
    return <String, dynamic>{};
  }

  String _meInitials() {
    if (_me == null) return '?';
    final name = (_me!['full_name'] ?? '').toString().trim();
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}j';
    return '${diff.inDays}h';
  }

  Future<void> _pickImage({VoidCallback? onPicked}) async {
    if (_pickingImage) return;
    _pickingImage = true;
    try {
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
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memilih foto')),
        );
      }
    } finally {
      _pickingImage = false;
    }
  }

  Future<bool> _createPost() async {
    if (_posting) return false;
    final text = _postCtrl.text.trim();
    final selectedImage = _selectedImage;
    final selectedBytes = _selectedImageBytes;
    if (text.isEmpty && selectedImage == null) return false;
    _posting = true;
    _postingNotifier.value = true;
    if (mounted) setState(() {});
    try {
      String? imageUrl;
      if (selectedImage != null) {
        final bytes = selectedBytes ?? await selectedImage.readAsBytes();
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
      _posting = false;
      _postingNotifier.value = false;
      if (mounted) setState(() {});
    }
  }

  static const List<Color> _avatarColors = [
    Color(0xFF2B4F7A), Color(0xFF2D6A27), Color(0xFF5C3D8C),
    Color(0xFF7A4B2B), Color(0xFF2D6060), Color(0xFF6B2A4F),
  ];

  Color _colorFor(dynamic seed) {
    final hash = (seed?.toString() ?? '?').hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  bool _isMyPost(Map<String, dynamic> post) {
    final myId = (_me?['user_id'] ?? _me?['id'])?.toString();
    final userRaw = post['user'];
    final posterId = ((userRaw is Map ? userRaw['id'] : null) ?? post['user_id'])?.toString();
    return myId != null && myId.isNotEmpty && posterId != null && myId == posterId;
  }

  Future<void> _editPostDialog(Map<String, dynamic> post) async {
    if (_mutatingPost) return;
    final postId = post['id']?.toString();
    if (postId == null || postId.isEmpty) return;
    final updated = await showDialog<String>(
      context: context,
      builder: (_) => _HomeEditPostDialog(initialContent: post['content']?.toString() ?? ''),
    );
    if (updated == null || !mounted) return;

    _mutatingPost = true;
    try {
      final res = await PostsService.updatePost(postId, updated);
      if (mounted) {
        setState(() {
          final idx = _posts.indexWhere((p) => p['id']?.toString() == postId);
          if (idx != -1) {
            _posts[idx] = {..._posts[idx], 'content': res['content'] ?? updated};
          }
        });
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

  Future<void> _deletePost(String postId) async {
    if (_mutatingPost || postId.isEmpty) return;
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
    if (confirm != true || !mounted) return;

    _mutatingPost = true;
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
    } finally {
      _mutatingPost = false;
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
              Future.microtask(() => _pickImage(
                    onPicked: () {
                      if (ctx.mounted) setSheetState(() {});
                    },
                  ));
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
                      ValueListenableBuilder<bool>(
                        valueListenable: _postingNotifier,
                        builder: (_, isPosting, _) => ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandNavy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          onPressed: isPosting
                              ? null
                              : () async {
                                  final ok = await _createPost();
                                  if (ok && ctx.mounted) Navigator.pop(ctx);
                                },
                          child: isPosting
                              ? const SizedBox(
                                  width: 14, height: 14,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : Text('Posting', style: buttonStyle),
                        ),
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
                  ValueListenableBuilder<bool>(
                    valueListenable: _postingNotifier,
                    builder: (_, isPosting, _) => InkWell(
                      onTap: isPosting
                          ? null
                          : () => _pickImage(
                                onPicked: () {
                                  if (ctx.mounted) setSheetState(() {});
                                },
                              ),
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
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: _load,
              color: brandNavy,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        _buildComposerBar(),
                        _buildHighlights(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                          child: Text('Aktivitas Terbaru', style: label),
                        ),
                      ],
                    ),
                  ),
                  if (_loadingFeed)
                    const SliverToBoxAdapter(child: FeedSkeletonList())
                  else if (_feedError != null && _posts.isEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 18),
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.error_outline, color: dim2, size: 36),
                            const SizedBox(height: 10),
                            Text(_feedError!, style: subTitle),
                            const SizedBox(height: 10),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandNavy,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _load,
                              child: const Text('Coba Lagi'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_posts.isEmpty)
                    SliverToBoxAdapter(
                      child: Container(
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
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: _posts.length,
                      itemBuilder: (ctx, i) => _buildPostCard(ctx, i, _posts[i]),
                    ),
                  if (_loadingMoreFeed)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 84)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final rawName = (_me?['full_name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'Alumni' : rawName;
    final initials = _meInitials();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
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
          InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatListScreen()),
              );
              if (mounted) _refreshBadges();
            },
            borderRadius: BorderRadius.circular(99),
            child: Stack(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor),
                  ),
                  child: const Icon(Icons.chat_bubble_outline, color: brandNavy, size: 20),
                ),
                if (_unreadMessages > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
              if (mounted) _refreshBadges();
            },
            borderRadius: BorderRadius.circular(99),
            child: Stack(
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
                if (_unreadNotifications > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: brandGold,
                        shape: BoxShape.circle,
                        border: Border.all(color: surface, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Profil Saya',
            child: InkWell(
              onTap: widget.onOpenProfile,
              borderRadius: BorderRadius.circular(99),
              child: UnitasAvatar(
                initials: initials,
                color: _colorFor(_me?['id'] ?? 'me'),
                size: 36,
                avatarUrl: _avatarWithVersion(_me?['avatar_url']),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerBar() {
    final rawName = (_me?['full_name'] ?? '').toString().trim();
    final firstName = rawName.isEmpty ? 'Alumni' : rawName.split(RegExp(r'\s+')).first;
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
    final totalJobs = _stats['total_jobs'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
          child: Row(
            children: [
              Text('Sorotan Acara & Karier', style: label),
              const Spacer(),
              InkWell(
                onTap: widget.onOpenEvents,
                child: Text(
                  'Acara',
                  style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 11.5),
                ),
              ),
              Text(' · ', style: caption),
              InkWell(
                onTap: widget.onOpenJobs,
                child: Text(
                  'Karier',
                  style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              ..._upcomingEvents.map((ev) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _highlightEventCard(ev),
              )),
              ..._latestJobs.map((job) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _highlightJobCard(job),
              )),
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
              const SizedBox(width: 10),
              InkWell(
                onTap: widget.onOpenJobs,
                borderRadius: BorderRadius.circular(14),
                child: _highlightStatCard(
                  icon: Icons.work_outline,
                  value: totalJobs?.toString() ?? '—',
                  title: 'Lowongan Aktif',
                  subtitle: 'peluang karier',
                  accent: brandNavy,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _highlightJobCard(Map<String, dynamic> job) {
    final jobType = (job['job_type'] ?? 'Full-time').toString();
    final company = (job['company'] ?? '').toString();
    final location = (job['location'] ?? '').toString();
    final companyMeta = [company, location].where((s) => s.isNotEmpty).join(' • ');

    return InkWell(
      onTap: () => _openJobDetailSheet(job),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 186,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
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
                    color: brandNavy.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    jobType,
                    style: label.copyWith(color: brandNavy, fontWeight: FontWeight.w700, fontSize: 10),
                  ),
                ),
                const Icon(Icons.work_outline, size: 16, color: brandGold),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (job['title'] ?? '').toString().trim().isNotEmpty
                      ? job['title'].toString()
                      : 'Lowongan Kerja',
                  style: subTitle.copyWith(fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  companyMeta.isNotEmpty ? companyMeta : 'Karier Alumni',
                  style: caption.copyWith(fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _highlightEventCard(Map<String, dynamic> ev) {
    final cover = ev['cover_url']?.toString().trim();
    final dt = DateTime.tryParse(ev['event_date']?.toString() ?? '')?.toLocal();
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN', 'JUL', 'AGU', 'SEP', 'OKT', 'NOV', 'DES'];
    final dateBadge = dt != null ? '${dt.day} ${months[dt.month - 1]}' : 'ACARA';
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final coverCacheWidth = (186 * dpr).round().clamp(186, 720);

    return InkWell(
      onTap: () => _openEventDetailSheet(ev),
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 186,
          color: brandNavy,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null && cover.isNotEmpty)
                Image.network(
                  cover,
                  fit: BoxFit.cover,
                  cacheWidth: coverCacheWidth,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : const SizedBox.shrink(),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
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
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            (ev['category'] ?? '').toString(),
                            style: caption.copyWith(color: Colors.white70, fontSize: 10.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (ev['title'] ?? '').toString().trim().isNotEmpty
                              ? ev['title'].toString()
                              : 'Acara Alumni',
                          style: subTitle.copyWith(color: Colors.white, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          (ev['location'] ?? '').toString(),
                          style: caption.copyWith(color: Colors.white70, fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
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

  Widget _buildPostCard(BuildContext context, int i, Map<String, dynamic> post) {
    final rawId = post['id']?.toString();
    final id = rawId ?? '$i';
    final profile = _profile(post);
    final rawName = (profile['full_name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'Alumni' : rawName;
    final prodiRaw = (profile['prodi'] ?? '').toString().trim();
    final prodi = prodiRaw.isEmpty
        ? ''
        : prodiRaw
            .split(RegExp(r'\s+'))
            .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
    final angk = (profile['angkatan'] ?? '').toString().trim();
    final initials = _initials(post);
    final rawLikes = (post['likes_count'] as num?)?.toInt() ?? 0;
    final likes = rawLikes < 0 ? 0 : rawLikes;
    final rawComments = (post['comments_count'] as num?)?.toInt() ?? 0;
    final comments = rawComments < 0 ? 0 : rawComments;
    final liked = _likedMap[id] ?? false;
    final content = (post['content'] ?? '').toString();
    final imageUrl = post['image_url']?.toString().trim();
    final imageCacheWidth = (600 * MediaQuery.devicePixelRatioOf(context)).round().clamp(300, 1440);
    final metaLine = [
      if (prodi.isNotEmpty) prodi,
      if (angk.isNotEmpty) angk,
      _timeAgo(post['created_at']?.toString()),
    ].where((s) => s.isNotEmpty).join(' · ');

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
              var deletedFromDetail = false;
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PostDetailScreen(
                    post: post,
                    onPostDeleted: () {
                      deletedFromDetail = true;
                      if (mounted && rawId != null) {
                        setState(() {
                          _posts.removeWhere((p) => p['id']?.toString() == rawId);
                        });
                      }
                    },
                  ),
                ),
              );
              if (mounted) {
                if (deletedFromDetail) {
                  _loadMeta();
                } else {
                  _load();
                }
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header post (avatar, nama, waktu, menu)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _openAuthorProfileSheet(post, prodi, angk),
                        child: UnitasAvatar(
                          initials: initials,
                          color: _colorFor(post['user_id'] ?? name),
                          size: 40,
                          avatarUrl: _avatarWithVersion(profile['avatar_url']),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _openAuthorProfileSheet(post, prodi, angk),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: subTitle.copyWith(fontSize: 15), overflow: TextOverflow.ellipsis),
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
                      ),
                      if (_isMyPost(post) && rawId != null)
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_horiz, color: dim1, size: 22),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onSelected: (val) {
                            if (val == 'edit') _editPostDialog(post);
                            if (val == 'delete') _deletePost(rawId);
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
                ),
                // Teks caption
                if (content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Text(
                      content,
                      style: body.copyWith(height: 1.45, color: textPrimary, fontSize: 14.5),
                    ),
                  ),
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        cacheWidth: imageCacheWidth,
                        gaplessPlayback: true,
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
                // Baris aksi (Like, Komentar, Share)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: rawId != null ? () => _toggleLike(rawId) : null,
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
                      InkWell(
                        onTap: () {
                          final shareText = '$name ($metaLine):\n$content';
                          Clipboard.setData(ClipboardData(text: shareText.trim()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Postingan disalin ke clipboard')),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Icon(Icons.share_outlined, color: dim1, size: 19),
                        ),
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
  }

  void _openEventDetailSheet(Map<String, dynamic> ev) {
    showModalBottomSheet(
      context: context,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((ev['category'] ?? 'Acara Alumni').toString(), style: label.copyWith(color: brandNavy)),
            const SizedBox(height: 6),
            Text((ev['title'] ?? 'Acara Alumni').toString(), style: heading.copyWith(fontSize: 19)),
            const SizedBox(height: 8),
            Text(
              '${ev['event_date'] ?? ''} · ${ev['location'] ?? ''}',
              style: caption,
            ),
            if ((ev['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(ev['description'].toString(), style: body, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: brandNavy),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onOpenEvents?.call();
                },
                child: const Text('Lihat di Tab Acara'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openJobDetailSheet(Map<String, dynamic> job) {
    final applyUrl = (job['apply_url'] ?? '').toString().trim();
    final contactEmail = (job['contact_email'] ?? '').toString().trim();
    showModalBottomSheet(
      context: context,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text((job['job_type'] ?? 'Full-time').toString(), style: label.copyWith(color: brandNavy)),
            const SizedBox(height: 6),
            Text((job['title'] ?? 'Lowongan Kerja').toString(), style: heading.copyWith(fontSize: 19)),
            const SizedBox(height: 6),
            Text(
              '${job['company'] ?? ''} · ${job['location'] ?? ''}',
              style: caption,
            ),
            if ((job['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(job['description'].toString(), style: body, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            if (applyUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Link: $applyUrl', style: caption.copyWith(color: brandNavy)),
            ],
            if (contactEmail.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Email: $contactEmail', style: caption.copyWith(color: brandNavy)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: brandNavy),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.onOpenJobs?.call();
                },
                child: const Text('Buka Bursa Karier'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAuthorProfileSheet(Map<String, dynamic> post, String prodi, dynamic angkatan) {
    if (_isMyPost(post)) {
      widget.onOpenProfile?.call();
      return;
    }
    final userRaw = post['user'];
    final posterId = ((userRaw is Map ? userRaw['id'] : null) ?? post['user_id'] ?? '').toString();
    if (posterId.isEmpty) return;
    final profile = _profile(post);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlumniProfileScreen(
          userId: posterId,
          initialProfile: {
            ...profile,
            'user_id': posterId,
            if (prodi.isNotEmpty) 'prodi': prodi,
            if (angkatan != null && angkatan.toString().isNotEmpty) 'angkatan': angkatan,
          },
        ),
      ),
    );
  }
}

class _HomeEditPostDialog extends StatefulWidget {
  final String initialContent;
  const _HomeEditPostDialog({required this.initialContent});

  @override
  State<_HomeEditPostDialog> createState() => _HomeEditPostDialogState();
}

class _HomeEditPostDialogState extends State<_HomeEditPostDialog> {
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

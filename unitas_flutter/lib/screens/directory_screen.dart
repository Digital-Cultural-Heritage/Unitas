import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/users_service.dart';
import '../core/api/api_client.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';
import '../widgets/linkable_text.dart';
import 'chat_room_screen.dart';

/// Menghasilkan daftar nomor halaman (maks 7 slot) dengan `null` sebagai elipsis (`…`).
List<int?> buildVisiblePageNumbers(int currentPage, int totalPages) {
  if (totalPages <= 1) return const [1];
  if (totalPages <= 7) return List<int?>.generate(totalPages, (i) => i + 1);

  final current = currentPage.clamp(1, totalPages);
  if (current <= 3) {
    return [1, 2, 3, 4, null, totalPages];
  }
  if (current >= totalPages - 2) {
    return [1, null, totalPages - 3, totalPages - 2, totalPages - 1, totalPages];
  }
  return [1, null, current - 1, current, current + 1, null, totalPages];
}

class DirectoryPaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final int currentCount;
  final bool loading;
  final ValueChanged<int> onPageChanged;

  const DirectoryPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.currentCount,
    required this.loading,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final startItem =
        totalItems == 0 || currentCount == 0 ? 0 : (currentPage - 1) * pageSize + 1;
    final endItem = totalItems == 0 || currentCount == 0
        ? 0
        : (startItem + currentCount - 1).clamp(startItem, totalItems);
    final pages = buildVisiblePageNumbers(currentPage, totalPages);

    return Container(
      margin: const EdgeInsets.fromLTRB(22, 12, 22, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Menampilkan $startItem–$endItem dari $totalItems alumni',
            style: caption.copyWith(color: dim1),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 6,
            children: [
              IconButton(
                tooltip: 'Halaman sebelumnya',
                icon: const Icon(Icons.chevron_left, size: 20),
                color: brandNavy,
                disabledColor: dim3,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                onPressed: loading || currentPage <= 1
                    ? null
                    : () => onPageChanged(currentPage - 1),
              ),
              for (final p in pages)
                if (p == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('…', style: caption.copyWith(color: dim2)),
                  )
                else
                  _buildPagePill(p),
              IconButton(
                tooltip: 'Halaman berikutnya',
                icon: const Icon(Icons.chevron_right, size: 20),
                color: brandNavy,
                disabledColor: dim3,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                onPressed: loading || currentPage >= totalPages
                    ? null
                    : () => onPageChanged(currentPage + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPagePill(int page) {
    final active = page == currentPage;
    return Material(
      color: active ? brandNavy : card,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: loading || active ? null : () => onPageChanged(page),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? brandNavy : borderColor),
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Text(
              '$page',
              style: caption.copyWith(
                color: active ? Colors.white : dim1,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DirectoryScreen extends StatefulWidget {
  final int refreshTrigger;
  const DirectoryScreen({super.key, this.refreshTrigger = 0});
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  static const int _pageSize = 15;

  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _searchDebounce;
  int _loadSeq = 0;
  String _q = '';
  String _filter = 'Semua';
  List<Map<String, dynamic>> _alumni = [];
  bool _loading = true;
  int _page = 1;
  int _total = 0;
  int _totalPages = 1;
  String? _error;
  String? _currentUserId;
  final Map<String, String> _connectionStatus = {};
  final Set<String> _connectingIds = {};

  static const List<String> _filters = ['Semua', 'Terhubung', 'Jakarta', 'Lainnya'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DirectoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshTrigger != oldWidget.refreshTrigger) {
      _load(page: _page);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _q = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load();
    });
  }

  Future<void> _load({int page = 1}) async {
    final seq = ++_loadSeq;
    final targetPage = page < 1 ? 1 : page;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kota = _filter == 'Jakarta' ? 'Jakarta' : null;
      final excludeKota = _filter == 'Lainnya' ? 'Jakarta' : null;
      final connectedOnly = _filter == 'Terhubung';

      if (_currentUserId == null) {
        final stored = await AuthService.getStoredUser();
        final storedId = (stored?['user_id'] ?? stored?['id'])?.toString();
        if (storedId != null && storedId.isNotEmpty) {
          _currentUserId = storedId;
        }
      }

      final dirFuture = UsersService.getDirectory(
        q: _q,
        kota: kota,
        excludeKota: excludeKota,
        connectedOnly: connectedOnly,
        page: targetPage,
        limit: _pageSize,
      );
      final meFuture = _currentUserId == null
          ? UsersService.getMe().catchError((_) => <String, dynamic>{})
          : null;

      final result = await dirFuture;
      if (meFuture != null) {
        final profile = await meFuture;
        if (profile.isNotEmpty) {
          _currentUserId = (profile['user_id'] ?? profile['id'])?.toString();
        }
      }

      if (!mounted || seq != _loadSeq) return;

      if (result.items.isEmpty &&
          targetPage > 1 &&
          result.total > 0 &&
          result.totalPages < targetPage) {
        await _load(page: result.totalPages);
        return;
      }

      final prevPage = _page;
      setState(() {
        _alumni = result.items;
        _page = result.page;
        _total = result.total;
        _totalPages = result.totalPages;
        for (final a in result.items) {
          final uid = a['user_id']?.toString() ?? '';
          if (uid.isNotEmpty) {
            _connectionStatus[uid] = a['connection_status']?.toString() ?? 'none';
          }
        }
        _loading = false;
      });
      if (_scrollCtrl.hasClients && result.page != prevPage) {
        _scrollCtrl.jumpTo(0);
      }
    } on ApiException catch (e) {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _error = 'Tidak dapat memuat data';
          _loading = false;
        });
      }
    }
  }

  void _goToPage(int target) {
    if (_loading || target == _page || target < 1 || target > _totalPages) return;
    _load(page: target);
  }

  static const List<Color> _colors = [
    Color(0xFF2B4F7A), Color(0xFF2D6A27), Color(0xFF2D6060),
    Color(0xFF6B5B2A), Color(0xFF6B2A4F), Color(0xFF5C3D8C),
  ];
  Color _colorFor(int i) => _colors[i % _colors.length];

  String _initials(Map<String, dynamic> a) {
    final rawIni = (a['initials'] ?? '').toString().trim();
    if (rawIni.isNotEmpty) return rawIni.toUpperCase();
    final name = (a['full_name'] ?? '').toString().trim();
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _connect(String userId) async {
    if (userId.isEmpty || _connectingIds.contains(userId)) return;
    final currentStatus = _connectionStatus[userId] ?? 'none';
    if (currentStatus == 'accepted' || currentStatus == 'pending') return;

    setState(() => _connectingIds.add(userId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await UsersService.connect(userId);
      if (!mounted) return;
      final conn = res['connection'];
      final serverStatus = conn is Map ? conn['status']?.toString() : null;
      final msg = (res['message'] ?? '').toString();
      final nextStatus = (serverStatus == 'accepted' ||
              msg == 'Sudah terhubung' ||
              msg == 'Koneksi diterima')
          ? 'accepted'
          : 'pending';
      setState(() => _connectionStatus[userId] = nextStatus);
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'Permintaan koneksi dikirim'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Gagal mengirim permintaan koneksi'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _connectingIds.remove(userId));
    }
  }

  void _showAlumniDetail(Map<String, dynamic> p, Color avatarColor, bool isMe) {
    final userId = p['user_id']?.toString() ?? '';
    final connStatus = _connectionStatus[userId] ?? 'none';
    final isConnecting = _connectingIds.contains(userId);
    final isConnected = connStatus == 'accepted';
    final isPending = connStatus == 'pending';
    final isIncoming = connStatus == 'incoming';
    final prodi = (p['prodi'] ?? '').toString();
    final angkatan = (p['angkatan'] ?? '').toString();
    final jobLine = '${p['pekerjaan'] ?? ''} · ${p['perusahaan'] ?? ''}'
        .trim()
        .replaceAll(RegExp(r'^\s*·\s*|\s*·\s*$'), '');
    final kota = (p['kota'] ?? '').toString().trim();
    final bio = (p['bio'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: brandBg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 14, 22, MediaQuery.of(ctx).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: dim3,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                UnitasAvatar(
                  initials: _initials(p),
                  color: avatarColor,
                  size: 56,
                  avatarUrl: p['avatar_url']?.toString(),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (p['full_name'] ?? '').toString().trim().isNotEmpty
                            ? p['full_name'].toString()
                            : '—',
                        style: subTitle.copyWith(fontSize: 17),
                      ),
                      if (prodi.isNotEmpty || angkatan.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          [if (prodi.isNotEmpty) prodi, if (angkatan.isNotEmpty) 'Angkatan $angkatan'].join(' · '),
                          style: caption.copyWith(color: dim1),
                        ),
                      ],
                      if (kota.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 13, color: dim2),
                            const SizedBox(width: 3),
                            Text(kota, style: caption),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (jobLine.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.work_outline, size: 16, color: brandNavy),
                    const SizedBox(width: 8),
                    Expanded(child: Text(jobLine, style: body)),
                  ],
                ),
              ),
            ],
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Tentang', style: label),
              const SizedBox(height: 6),
              LinkableText(bio, style: body.copyWith(height: 1.5)),
            ],
            const SizedBox(height: 20),
            if (!isMe)
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (isConnected || isPending) ? surface : brandNavy,
                    foregroundColor: isConnected
                        ? brandGreen
                        : (isPending ? dim1 : Colors.white),
                    disabledBackgroundColor: surface,
                    disabledForegroundColor: isConnected ? brandGreen : dim1,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: (isConnected || isPending || isConnecting)
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _connect(userId);
                        },
                  icon: Icon(
                    isConnected
                        ? Icons.check_circle_outline
                        : (isPending
                            ? Icons.schedule_outlined
                            : (isIncoming ? Icons.how_to_reg_outlined : Icons.person_add_outlined)),
                    size: 18,
                  ),
                  label: Text(
                    isConnected
                        ? 'Sudah Terhubung'
                        : (isPending
                            ? 'Permintaan Terkirim'
                            : (isIncoming ? 'Terima Permintaan Koneksi' : 'Hubungi Alumni')),
                  ),
                ),
              ),
            if (!isMe && isConnected) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    if (userId.isEmpty) return;
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatRoomScreen(
                          peerId: userId,
                          peerName: (p['full_name'] ?? 'Alumni').toString(),
                          peerInitials: _initials(p),
                          peerAvatarUrl: p['avatar_url']?.toString(),
                          peerSubtitle: jobLine,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Kirim Pesan'),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton(String userId) {
    final isConnecting = _connectingIds.contains(userId);
    final status = _connectionStatus[userId] ?? 'none';

    if (isConnecting) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: brandNavy),
        ),
      );
    }

    if (status == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: brandGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: brandGreen.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 14, color: brandGreen),
            const SizedBox(width: 4),
            Text(
              'Terhubung',
              style: caption.copyWith(color: brandGreen, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (status == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule_outlined, size: 14, color: dim1),
            const SizedBox(width: 4),
            Text(
              'Terkirim',
              style: caption.copyWith(color: dim1, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    final isIncoming = status == 'incoming';
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        backgroundColor: isIncoming ? brandGold : brandNavy,
        foregroundColor: isIncoming ? brandNavy : Colors.white,
        side: BorderSide(color: isIncoming ? brandGold : brandNavy),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => _connect(userId),
      icon: Icon(
        isIncoming ? Icons.how_to_reg_outlined : Icons.person_add_outlined,
        size: 14,
        color: isIncoming ? brandNavy : Colors.white,
      ),
      label: Text(
        isIncoming ? 'Terima' : 'Hubungi',
        style: caption.copyWith(
          color: isIncoming ? brandNavy : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAlumniCard(int i, Map<String, dynamic> p) {
    final userId = p['user_id']?.toString() ?? '';
    final isMe = _currentUserId != null && userId == _currentUserId;
    final isOnline = p['is_online'] == true;
    final prodi = (p['prodi'] ?? '').toString().trim();
    final angkatan = (p['angkatan'] ?? '').toString().trim();
    final short = angkatan.length >= 2 ? angkatan.substring(angkatan.length - 2) : angkatan;
    final badgeText = short.isNotEmpty
        ? (prodi.isNotEmpty ? "$prodi '$short" : "'$short")
        : prodi;
    final kota = (p['kota'] ?? '').toString().trim();
    final fullName = (p['full_name'] ?? '').toString().trim();
    final jobLine = '${p['pekerjaan'] ?? ''} · ${p['perusahaan'] ?? ''}'
        .trim()
        .replaceAll(RegExp(r'^\s*·\s*|\s*·\s*$'), '');
    final avatarColor = _colorFor((_page - 1) * _pageSize + i);

    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: InkWell(
          onTap: () => _showAlumniDetail(p, avatarColor, isMe),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              UnitasAvatar(
                initials: _initials(p),
                color: avatarColor,
                size: 46,
                avatarUrl: p['avatar_url']?.toString(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        fullName.isNotEmpty ? fullName : '—',
                        style: subTitle,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isOnline) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: brandGreen, shape: BoxShape.circle),
                      ),
                    ],
                  ]),
                  if (jobLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(jobLine, style: caption, overflow: TextOverflow.ellipsis),
                  ],
                  if (badgeText.isNotEmpty || kota.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      if (badgeText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: card,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(badgeText, style: caption.copyWith(fontSize: 11)),
                        ),
                      if (kota.isNotEmpty) ...[
                        if (badgeText.isNotEmpty) const SizedBox(width: 8),
                        Icon(Icons.location_on_outlined, size: 12, color: dim2),
                        const SizedBox(width: 2),
                        Flexible(child: Text(kota, style: caption, overflow: TextOverflow.ellipsis)),
                      ],
                    ]),
                  ],
                ]),
              ),
              const SizedBox(width: 8),
              if (isMe)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: borderColor),
                  ),
                  child: Text('Kamu', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                )
              else
                _buildConnectButton(userId),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: () => _load(page: _page),
            color: brandNavy,
            child: CustomScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            _loading && _total == 0
                                ? '— alumni ditemukan'
                                : _totalPages > 1
                                    ? '$_total alumni ditemukan · Hal. $_page/$_totalPages'
                                    : '$_total alumni ditemukan',
                            style: caption,
                          ),
                          Text('Direktori Alumni', style: heading),
                        ]),
                      ),
                      // Search
                      Container(
                        margin: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor),
                        ),
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          onSubmitted: (_) {
                            _searchDebounce?.cancel();
                            _load();
                          },
                          style: body,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Cari nama atau jurusan…',
                            hintStyle: body.copyWith(color: dim2),
                            icon: Icon(Icons.search, color: dim2, size: 18),
                            suffixIcon: ValueListenableBuilder<TextEditingValue>(
                              valueListenable: _searchCtrl,
                              builder: (_, val, _) => val.text.isNotEmpty
                                  ? IconButton(
                                      icon: Icon(Icons.close, size: 18, color: dim2),
                                      onPressed: () {
                                        _searchDebounce?.cancel();
                                        _searchCtrl.clear();
                                        _q = '';
                                        _load();
                                      },
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ),
                      // Filters
                      SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 22),
                          children: _filters.map((f) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                if (_filter == f) return;
                                _searchDebounce?.cancel();
                                setState(() => _filter = f);
                                _load();
                              },
                              child: Container(
                                alignment: Alignment.center,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: _filter == f ? brandNavy : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: _filter == f ? brandNavy : borderColor),
                                ),
                                child: Text(f, style: caption.copyWith(
                                  color: _filter == f ? Colors.white : dim1,
                                  fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                                )),
                              ),
                            ),
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                if (_loading)
                  const SliverToBoxAdapter(child: DirectorySkeletonList())
                else if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.error_outline, color: dim2, size: 32),
                            const SizedBox(height: 8),
                            Text(_error!, style: caption.copyWith(color: dim1), textAlign: TextAlign.center),
                            const SizedBox(height: 12),
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
                    ),
                  )
                else if (_alumni.isEmpty)
                  SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(children: [
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: brandGold.withValues(alpha: 0.16),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.people_outline, color: brandNavy, size: 28),
                        ),
                        const SizedBox(height: 14),
                        Text('Tidak ada alumni ditemukan', style: subTitle.copyWith(fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Coba ubah kata kunci pencarian atau filter kota.', style: caption, textAlign: TextAlign.center),
                      ]),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    sliver: SliverList.builder(
                      itemCount: _alumni.length,
                      itemBuilder: (_, i) => _buildAlumniCard(i, _alumni[i]),
                    ),
                  ),
                if (!_loading && _error == null && _alumni.isNotEmpty && _totalPages > 1)
                  SliverToBoxAdapter(
                    child: DirectoryPaginationBar(
                      currentPage: _page,
                      totalPages: _totalPages,
                      totalItems: _total,
                      pageSize: _pageSize,
                      currentCount: _alumni.length,
                      loading: _loading,
                      onPageChanged: _goToPage,
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

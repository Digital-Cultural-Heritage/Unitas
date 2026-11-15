import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/api_client.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  final _searchCtrl = TextEditingController();
  String _q = '';
  String _filter = 'Semua';
  List<Map<String, dynamic>> _alumni = [];
  bool _loading = true;
  String? _error;
  String? _currentUserId;
  final Map<String, String> _connectionStatus = {};
  final Set<String> _connectingIds = {};

  final List<String> _filters = ['Semua', 'Terhubung', 'Jakarta', 'Lainnya'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final kota = _filter == 'Jakarta' ? 'Jakarta' : null;
      final isOnline = _filter == 'Terhubung' ? true : null;
      var data = await UsersService.getDirectory(
        q: _q, kota: kota, isOnline: isOnline,
      );
      // Filter "Lainnya" = bukan Jakarta
      if (_filter == 'Lainnya') {
        data = data.where((a) => (a['kota'] ?? '') != 'Jakarta').toList();
      }

      try {
        final profile = await UsersService.getMe();
        _currentUserId = profile['user_id']?.toString() ?? profile['id']?.toString();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _alumni = data;
          for (final a in data) {
            final uid = a['user_id']?.toString() ?? '';
            if (uid.isNotEmpty) {
              _connectionStatus[uid] = a['connection_status']?.toString() ?? 'none';
            }
          }
          _loading = false;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _error = 'Tidak dapat memuat data'; _loading = false; });
    }
  }

  static const List<Color> _colors = [
    Color(0xFF2B4F7A), Color(0xFF2D6A27), Color(0xFF2D6060),
    Color(0xFF6B5B2A), Color(0xFF6B2A4F), Color(0xFF5C3D8C),
  ];
  Color _colorFor(int i) => _colors[i % _colors.length];

  String _initials(Map<String, dynamic> a) {
    if (a['initials'] != null) return a['initials'];
    final name = a['full_name'] ?? '';
    final parts = name.split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _connect(String userId) async {
    if (_connectingIds.contains(userId)) return;
    final currentStatus = _connectionStatus[userId] ?? 'none';
    if (currentStatus == 'accepted' || currentStatus == 'pending') return;

    setState(() => _connectingIds.add(userId));
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await UsersService.connect(userId);
      if (!mounted) return;
      final serverStatus = res['connection']?['status']?.toString();
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
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
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
                      Text(p['full_name'] ?? '—', style: subTitle.copyWith(fontSize: 17)),
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
                            const Icon(Icons.location_on_outlined, size: 13, color: dim2),
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
              Text(bio, style: body.copyWith(height: 1.5)),
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
          ],
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
            const Icon(Icons.schedule_outlined, size: 14, color: dim1),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _load,
            color: brandNavy,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_alumni.isNotEmpty ? _alumni.length.toString() : "—"} alumni ditemukan', style: caption),
                      Text('Direktori Alumni', style: heading),
                    ]),
                  ),
          // Search
          Container(
            margin: const EdgeInsets.fromLTRB(22, 0, 22, 16),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: surface, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) { _q = v; _load(); },
              style: body,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Cari nama atau jurusan…',
                hintStyle: body.copyWith(color: dim2),
                icon: Icon(Icons.search, color: dim2, size: 18),
                suffixIcon: _q.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close, size: 18, color: dim2),
                        onPressed: () {
                          _searchCtrl.clear();
                          _q = '';
                          _load();
                        },
                      )
                    : null,
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
                  onTap: () { setState(() => _filter = f); _load(); },
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
          // Content
          if (_loading)
            const DirectorySkeletonList()
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(_error!, style: caption.copyWith(color: dim2)),
            )
          else if (_alumni.isEmpty)
            Container(
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
                  width: 60, height: 60,
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
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: _alumni.asMap().entries.map((e) {
                  final i = e.key; final p = e.value;
                  final userId = p['user_id']?.toString() ?? '';
                  final isMe = _currentUserId != null && userId == _currentUserId;
                  final isOnline = p['is_online'] == true;
                  final prodi = (p['prodi'] ?? '').toString();
                  final angkatan = (p['angkatan'] ?? '').toString();
                  final short = angkatan.length >= 2 ? angkatan.substring(angkatan.length - 2) : angkatan;
                  final jobLine = '${p['pekerjaan'] ?? ''} · ${p['perusahaan'] ?? ''}'
                      .trim()
                      .replaceAll(RegExp(r'^\s*·\s*|\s*·\s*$'), '');
                  final avatarColor = _colorFor(i);

                  return Container(
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
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(child: Text(p['full_name'] ?? '—', style: subTitle, overflow: TextOverflow.ellipsis)),
                              if (isOnline) ...[
                                const SizedBox(width: 6),
                                Container(width: 6, height: 6,
                                  decoration: const BoxDecoration(color: brandGreen, shape: BoxShape.circle)),
                              ],
                            ]),
                            if (jobLine.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(jobLine, style: caption, overflow: TextOverflow.ellipsis),
                            ],
                            const SizedBox(height: 6),
                            Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: card, borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text("$prodi '$short", style: caption.copyWith(fontSize: 11)),
                              ),
                              if ((p['kota'] ?? '').toString().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.location_on_outlined, size: 12, color: dim2),
                                const SizedBox(width: 2),
                                Flexible(child: Text(p['kota'], style: caption, overflow: TextOverflow.ellipsis)),
                              ],
                            ]),
                          ])),
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
                  );
                }).toList(),
              ),
            ),
        ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

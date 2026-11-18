import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/auth_service.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const List<Color> _avatarColors = [
    Color(0xFF1E3A5F),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFFE65100),
    Color(0xFF0277BD),
    Color(0xFF6A1B9A),
  ];

  String _tab = 'tentang';
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _connections = [];
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _responding = {};
  bool _loading = true;
  bool _loggingOut = false;
  String? _error;
  int _avatarVersion = DateTime.now().millisecondsSinceEpoch;
  bool _notifPosts = true;
  bool _notifConnections = true;
  bool _notifEvents = true;
  bool _privacyShowEmail = false;
  bool _privacyAllowConnect = true;
  String _language = 'Bahasa Indonesia';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _load();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifPosts = prefs.getBool('pref_notif_posts') ?? true;
      _notifConnections = prefs.getBool('pref_notif_connections') ?? true;
      _notifEvents = prefs.getBool('pref_notif_events') ?? true;
      _privacyShowEmail = prefs.getBool('pref_privacy_email') ?? false;
      _privacyAllowConnect = prefs.getBool('pref_privacy_connect') ?? true;
      _language = prefs.getString('pref_language') ?? 'Bahasa Indonesia';
    });
  }

  Future<void> _load() async {
    if (mounted && _profile == null && !_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        UsersService.getMe(),
        UsersService.getMyConnections().catchError((_) => <Map<String, dynamic>>[]),
        UsersService.getIncomingRequests().catchError((_) => <Map<String, dynamic>>[]),
      ]);
      if (mounted) {
        setState(() {
          _profile = results[0] as Map<String, dynamic>?;
          _connections = results[1] as List<Map<String, dynamic>>;
          _requests = results[2] as List<Map<String, dynamic>>;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      final stored = await AuthService.getStoredUser();
      if (!mounted) return;
      final hadProfile = _profile != null;
      setState(() {
        _profile ??= stored;
        if (_profile == null) {
          _error = 'Gagal memuat profil';
        }
        _loading = false;
      });
      if (hadProfile) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memperbarui profil')),
        );
      }
    }
  }

  Future<void> _respond(String id, String action) async {
    if (_responding.contains(id)) return;
    setState(() => _responding.add(id));
    try {
      await UsersService.respondRequest(id, action);
      if (mounted) _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal merespons')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _responding.remove(id));
      } else {
        _responding.remove(id);
      }
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        title: Text('Keluar', style: heading.copyWith(fontSize: 18)),
        content: Text('Apakah kamu yakin ingin keluar?', style: body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: caption.copyWith(color: dim1)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Keluar', style: caption.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _loggingOut = true;
    try {
      await AuthService.logout();
      if (mounted) widget.onLogout();
    } finally {
      _loggingOut = false;
    }
  }

  String _initials(Map<String, dynamic>? p) {
    final name = (p?['full_name'] ?? '').toString().trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  Map<String, dynamic>? _extractProfileMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  Color _colorFor(String text) {
    final hash = text.hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final coverCacheW = (600 * dpr).round().clamp(600, 1200);
    final avatarCacheW = (70 * dpr).round();
    final avatarUrl = _profile?['avatar_url']?.toString().trim() ?? '';
    final fullName = (_profile?['full_name'] ?? '').toString().trim();
    final prodi = (_profile?['prodi'] ?? '').toString().trim();
    final angkatan = (_profile?['angkatan'] ?? '').toString().trim();
    final pekerjaan = (_profile?['pekerjaan'] ?? '').toString().trim();
    final perusahaan = (_profile?['perusahaan'] ?? '').toString().trim();
    final kota = (_profile?['kota'] ?? '').toString().trim();
    final jobSummary = [pekerjaan, perusahaan, kota].where((e) => e.isNotEmpty).join(' · ');

    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: RefreshIndicator(
          onRefresh: _load,
          color: brandNavy,
          child: (!_loading && _profile == null && _error != null)
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(32),
                  children: [
                    const SizedBox(height: 80),
                    const Icon(Icons.error_outline, size: 42, color: dim2),
                    const SizedBox(height: 12),
                    Text(_error!, style: subTitle, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandNavy,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: Text('Coba Lagi', style: buttonStyle),
                      ),
                    ),
                  ],
                )
              : CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Stack(
                        children: [
                          // Cover
                          SizedBox(
                            height: 128,
                            width: double.infinity,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Image.network(
                                    'https://images.unsplash.com/photo-1748144679532-c36d9d5584e6?w=600&h=240&fit=crop',
                                    fit: BoxFit.cover,
                                    cacheWidth: coverCacheW,
                                    color: Colors.black54,
                                    colorBlendMode: BlendMode.darken,
                                    errorBuilder: (_, _, _) => Container(color: brandNavy),
                                  ),
                                ),
                                Positioned.fill(
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, brandBg],
                                        stops: [0.45, 1.0],
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 12,
                                  right: 14,
                                  child: SafeArea(
                                    bottom: false,
                                    child: InkWell(
                                      onTap: _openEditProfile,
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.35),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 16),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Profile header section overlapping cover
                          Padding(
                            padding: const EdgeInsets.fromLTRB(22, 86, 22, 0),
                            child: _loading
                                ? const ProfileSkeleton()
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          // Avatar dengan frame & bayangan lembut
                                          Container(
                                            width: 76,
                                            height: 76,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF7A4B2B),
                                              borderRadius: BorderRadius.circular(20),
                                              border: Border.all(color: brandBg, width: 3),
                                              boxShadow: const [
                                                BoxShadow(
                                                  color: Color(0x181E3A5F),
                                                  blurRadius: 10,
                                                  offset: Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(17),
                                              child: avatarUrl.isNotEmpty
                                                  ? Image.network(
                                                      avatarUrl.contains('?')
                                                          ? '$avatarUrl&v=$_avatarVersion'
                                                          : '$avatarUrl?v=$_avatarVersion',
                                                      width: 70,
                                                      height: 70,
                                                      cacheWidth: avatarCacheW,
                                                      fit: BoxFit.cover,
                                                      gaplessPlayback: true,
                                                      errorBuilder: (_, _, _) => Center(
                                                        child: Text(
                                                          _initials(_profile),
                                                          style: heading.copyWith(color: Colors.white, fontSize: 20),
                                                        ),
                                                      ),
                                                    )
                                                  : Center(
                                                      child: Text(
                                                        _initials(_profile),
                                                        style: heading.copyWith(color: Colors.white, fontSize: 20),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: brandNavy,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              elevation: 1,
                                            ),
                                            onPressed: _openEditProfile,
                                            icon: const Icon(Icons.edit_outlined, size: 15),
                                            label: Text('Edit Profil', style: buttonStyle.copyWith(fontSize: 12.5)),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 14),
                                      Text(fullName.isNotEmpty ? fullName : '—', style: heading),
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.school_outlined, size: 15, color: dim1),
                                              const SizedBox(width: 5),
                                              Text(
                                                prodi.isNotEmpty ? prodi : 'Alumni',
                                                style: body.copyWith(color: dim1, fontWeight: FontWeight.w500),
                                              ),
                                            ],
                                          ),
                                          if (angkatan.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: surface,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: borderColor),
                                              ),
                                              child: Text(
                                                'Angkatan $angkatan',
                                                style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 11),
                                              ),
                                            ),
                                        ],
                                      ),
                                      if (pekerjaan.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          jobSummary,
                                          style: body.copyWith(color: dim2),
                                        ),
                                      ],
                                      const SizedBox(height: 18),
                                      // Stats
                                      Row(children: [
                                        {'val': '${_profile?['points'] ?? 0}', 'label': 'Poin', 'icon': Icons.stars_outlined, 'tap': false},
                                        {'val': '${_connections.length}', 'label': 'Koneksi', 'icon': Icons.people_outline, 'tap': true},
                                        {'val': '${_profile?['events_count'] ?? 0}', 'label': 'Acara', 'icon': Icons.event_available_outlined, 'tap': false},
                                      ].asMap().entries.map((e) {
                                        final i = e.key;
                                        final s = e.value;
                                        final canTap = s['tap'] == true;
                                        return Expanded(
                                          child: InkWell(
                                            onTap: canTap ? () => setState(() => _tab = 'koneksi') : null,
                                            borderRadius: BorderRadius.horizontal(
                                              left: i == 0 ? const Radius.circular(12) : Radius.zero,
                                              right: i == 2 ? const Radius.circular(12) : Radius.zero,
                                            ),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(vertical: 12),
                                              decoration: BoxDecoration(
                                                color: surface,
                                                border: Border(
                                                  top: BorderSide(color: borderColor),
                                                  bottom: BorderSide(color: borderColor),
                                                  left: BorderSide(color: borderColor),
                                                  right: i == 2 ? BorderSide(color: borderColor) : BorderSide.none,
                                                ),
                                                borderRadius: BorderRadius.horizontal(
                                                  left: i == 0 ? const Radius.circular(12) : Radius.zero,
                                                  right: i == 2 ? const Radius.circular(12) : Radius.zero,
                                                ),
                                              ),
                                              child: Column(children: [
                                                Row(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Icon(s['icon'] as IconData, size: 15, color: brandGold),
                                                    const SizedBox(width: 4),
                                                    Text(s['val'] as String, style: statStyle.copyWith(fontSize: 19, color: brandNavy)),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                Text(s['label'] as String, style: caption),
                                              ]),
                                            ),
                                          ),
                                        );
                                      }).toList()),
                                      _buildProfileCompletionBanner(),
                                      const SizedBox(height: 20),
                                      // Tabs
                                      Row(children: ['tentang', 'koneksi', 'pengaturan'].map((t) =>
                                        Expanded(child: GestureDetector(
                                          onTap: () => setState(() => _tab = t),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            decoration: BoxDecoration(
                                              border: Border(bottom: BorderSide(
                                                color: _tab == t ? brandNavy : Colors.transparent, width: 1.5,
                                              )),
                                            ),
                                            child: Text(
                                              '${t[0].toUpperCase()}${t.substring(1)}${t == 'koneksi' && _requests.isNotEmpty ? ' (${_requests.length})' : ''}',
                                              style: caption.copyWith(
                                                color: _tab == t ? brandNavy : dim2,
                                                fontWeight: _tab == t ? FontWeight.w600 : FontWeight.w400,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        )),
                                      ).toList()),
                                      const SizedBox(height: 20),
                                    ],
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (!_loading) ..._buildTabSlivers(),
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                  ],
                ),
        ),
      ),
      ),
    );
  }

  List<Widget> _buildTabSlivers() {
    if (_tab == 'tentang') {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverToBoxAdapter(child: _buildTentang()),
        ),
      ];
    }
    if (_tab == 'koneksi') {
      return _buildKoneksiSlivers();
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverToBoxAdapter(child: _buildPengaturan()),
      ),
    ];
  }

  Widget _buildProfileCompletionBanner() {
    if (_profile == null) return const SizedBox.shrink();
    final fields = <String, String>{
      'Foto': (_profile?['avatar_url'] ?? '').toString().trim(),
      'Bio': (_profile?['bio'] ?? '').toString().trim(),
      'Pekerjaan': (_profile?['pekerjaan'] ?? '').toString().trim(),
      'Perusahaan': (_profile?['perusahaan'] ?? '').toString().trim(),
      'Kota': (_profile?['kota'] ?? '').toString().trim(),
      'LinkedIn': (_profile?['linkedin'] ?? '').toString().trim(),
    };
    final filled = fields.values.where((v) => v.isNotEmpty).length;
    if (filled >= fields.length) return const SizedBox.shrink();
    final pct = ((filled / fields.length) * 100).round();
    final missing = fields.entries.where((e) => e.value.isEmpty).map((e) => e.key).take(3).join(', ');

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: InkWell(
        onTap: _openEditProfile,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: brandGold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: brandGold.withValues(alpha: 0.45)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 16, color: brandNavy),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Kelengkapan Profil ($pct%)',
                      style: subTitle.copyWith(fontSize: 13),
                    ),
                  ),
                  Text('Lengkapi →', style: label.copyWith(color: brandNavy)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: filled / fields.length,
                  minHeight: 5,
                  color: brandNavy,
                  backgroundColor: Colors.white70,
                ),
              ),
              const SizedBox(height: 5),
              Text('Belum diisi: $missing', style: caption.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTentang() {
    final bio = (_profile?['bio'] ?? '').toString().trim();
    final linkedin = (_profile?['linkedin'] ?? '').toString().trim();
    final email = (_profile?['email'] ?? '').toString().trim();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person_outline, size: 16, color: brandNavy),
                    const SizedBox(width: 6),
                    Text('Tentang Saya', style: label),
                  ],
                ),
                if (bio.isEmpty)
                  InkWell(
                    onTap: _openEditProfile,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        '+ Tambah Bio',
                        style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              bio.isNotEmpty ? bio : 'Ceritakan sedikit tentang pengalaman, minat, atau kegiatanmu saat ini.',
              style: body.copyWith(
                height: 1.55,
                color: bio.isNotEmpty ? textPrimary : dim2,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Informasi Kontak', style: label),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.email_outlined, size: 17, color: dim1),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(email.isNotEmpty ? email : '—', style: body),
                ),
              ],
            ),
            if (linkedin.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(color: borderColor, height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.link, size: 17, color: brandNavy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(linkedin, style: body.copyWith(color: brandNavy)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  List<Widget> _buildKoneksiSlivers() {
    final myId = (_profile?['user_id'] ?? _profile?['id'])?.toString();
    return [
      if (_requests.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Permintaan Masuk (${_requests.length})', style: label),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverList.builder(
            itemCount: _requests.length,
            itemBuilder: (context, index) {
              final req = _requests[index];
              final requester = req['requester'];
              final p = _extractProfileMap(requester is Map ? requester['user_profiles'] : null);
              if (p == null) return const SizedBox.shrink();
              final rawName = (p['full_name'] ?? '').toString().trim();
              final name = rawName.isEmpty ? '—' : rawName;
              final prodi = (p['prodi'] ?? '').toString().trim();
              final angkatan = (p['angkatan'] ?? '').toString().trim();
              final reqId = req['id']?.toString() ?? '';
              final busy = reqId.isEmpty || _responding.contains(reqId);
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  UnitasAvatar(initials: _initials(p), color: _colorFor(name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: subTitle),
                        Text('$prodi · Angkatan $angkatan', style: caption),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.check_circle, color: Color(0xFF2E7D32)),
                    onPressed: busy ? null : () => _respond(reqId, 'accept'),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Color(0xFFDC2626)),
                    onPressed: busy ? null : () => _respond(reqId, 'reject'),
                  ),
                ]),
              );
            },
          ),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(22, 4, 22, 16),
          sliver: SliverToBoxAdapter(
            child: Divider(color: Color(0x1A1E3A5F)),
          ),
        ),
      ],
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 22),
        sliver: SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('Jaringan Saya (${_connections.length})', style: label),
          ),
        ),
      ),
      if (_connections.isEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Belum ada koneksi. Jelajahi direktori untuk terhubung dengan alumni lain.',
              style: caption,
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          sliver: SliverList.builder(
            itemCount: _connections.length,
            itemBuilder: (context, index) {
              final conn = _connections[index];
              final requester = conn['requester'];
              final addressee = conn['addressee'];
              final reqId = requester is Map ? (requester['user_id'] ?? requester['id'])?.toString() : null;
              final rawProfile = reqId == myId
                  ? (addressee is Map ? addressee['user_profiles'] : null)
                  : (requester is Map ? requester['user_profiles'] : null);
              final p = _extractProfileMap(rawProfile);
              if (p == null) return const SizedBox.shrink();
              final rawName = (p['full_name'] ?? '').toString().trim();
              final name = rawName.isEmpty ? '—' : rawName;
              final job = (p['pekerjaan'] ?? '').toString().trim();
              final company = (p['perusahaan'] ?? '').toString().trim();
              final jobLine = [job, company].where((e) => e.isNotEmpty).join(' · ');

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  UnitasAvatar(initials: _initials(p), color: _colorFor(name)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: subTitle),
                        if (job.isNotEmpty)
                          Text(jobLine, style: caption, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
    ];
  }

  Future<void> _openEditProfile() async {
    if (_profile == null) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfileScreen(initialProfile: _profile!),
      ),
    );
    if (result == true && mounted) {
      _avatarVersion = DateTime.now().millisecondsSinceEpoch;
      _load();
    }
  }

  void _showSettingSheet({required String title, required Widget Function(BuildContext sheetCtx) builder}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, 14, 20, MediaQuery.of(sheetCtx).viewInsets.bottom + 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: dim3, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(title, style: heading.copyWith(fontSize: 18)),
              const SizedBox(height: 14),
              builder(sheetCtx),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openChangePasswordSheet() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ChangePasswordSheet(),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kata sandi berhasil diubah')),
      );
    }
  }

  void _openPrivacySheet() {
    _showSettingSheet(
      title: 'Privasi & Keamanan',
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: brandNavy,
              title: Text('Tampilkan Email di Direktori', style: subTitle),
              subtitle: Text('Izinkan alumni lain melihat alamat emailmu', style: caption),
              value: _privacyShowEmail,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pref_privacy_email', v);
                if (mounted) setState(() => _privacyShowEmail = v);
                if (ctx.mounted) setSheet(() {});
              },
            ),
            const Divider(height: 1, color: Color(0x1A1E3A5F)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: brandNavy,
              title: Text('Terima Permintaan Koneksi', style: subTitle),
              subtitle: Text('Alumni lain dapat mengirim permintaan koneksi', style: caption),
              value: _privacyAllowConnect,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pref_privacy_connect', v);
                if (mounted) setState(() => _privacyAllowConnect = v);
                if (ctx.mounted) setSheet(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openNotificationsSheet() {
    _showSettingSheet(
      title: 'Pengaturan Notifikasi',
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: brandNavy,
              title: Text('Postingan & Komentar', style: subTitle),
              subtitle: Text('Notifikasi saat ada komentar atau like baru', style: caption),
              value: _notifPosts,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pref_notif_posts', v);
                if (mounted) setState(() => _notifPosts = v);
                if (ctx.mounted) setSheet(() {});
              },
            ),
            const Divider(height: 1, color: Color(0x1A1E3A5F)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: brandNavy,
              title: Text('Permintaan Koneksi', style: subTitle),
              subtitle: Text('Notifikasi saat alumni mengajak terhubung', style: caption),
              value: _notifConnections,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pref_notif_connections', v);
                if (mounted) setState(() => _notifConnections = v);
                if (ctx.mounted) setSheet(() {});
              },
            ),
            const Divider(height: 1, color: Color(0x1A1E3A5F)),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: brandNavy,
              title: Text('Acara Alumni', style: subTitle),
              subtitle: Text('Pengingat acara kampus & reuni terdekat', style: caption),
              value: _notifEvents,
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('pref_notif_events', v);
                if (mounted) setState(() => _notifEvents = v);
                if (ctx.mounted) setSheet(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  void _openLanguageSheet() {
    const options = ['Bahasa Indonesia', 'English'];
    _showSettingSheet(
      title: 'Pilih Bahasa',
      builder: (sheetCtx) => Column(
        children: options.map((lang) {
          final selected = _language == lang;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(lang, style: subTitle),
            trailing: Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? brandNavy : dim2,
            ),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('pref_language', lang);
              if (mounted) setState(() => _language = lang);
              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Bahasa diatur ke $lang')),
                );
              }
            },
          );
        }).toList(),
      ),
    );
  }

  void _openHelpSheet() {
    _showSettingSheet(
      title: 'Bantuan & Dukungan',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _helpItem('Cara mengganti foto & data profil', 'Buka Edit Profil, pilih foto baru atau ubah prodi/angkatan, lalu tekan Simpan.'),
          const SizedBox(height: 10),
          _helpItem('Menghapus postingan', 'Klik tombol titik tiga (⋯) di pojok kanan atas postinganmu di Beranda, lalu pilih Hapus Postingan.'),
          const SizedBox(height: 10),
          _helpItem('Kontak Dukungan', 'Butuh bantuan lebih lanjut? Hubungi tim Unitas di support@unitas.id.'),
        ],
      ),
    );
  }

  Widget _helpItem(String q, String a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q, style: subTitle.copyWith(fontSize: 13.5)),
          const SizedBox(height: 4),
          Text(a, style: caption),
        ],
      ),
    );
  }

  void _openAboutSheet() {
    _showSettingSheet(
      title: 'Tentang Aplikasi',
      builder: (_) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: brandNavy, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: Text('U', style: subTitle.copyWith(color: brandGold, fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Unitas', style: subTitle.copyWith(fontSize: 16)),
                    Text('Versi 1.0.0', style: caption),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Unitas adalah Platform Alumni Digital untuk terhubung dengan sesama alumni, berbagi aktivitas, mengikuti acara kampus, dan menemukan peluang karier.',
              style: body.copyWith(fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPengaturan() {
    final groups = [
      {
        'title': 'Akun',
        'items': [
          {'label': 'Edit Profil', 'icon': Icons.person_outline, 'onTap': _openEditProfile},
          {'label': 'Ubah Kata Sandi', 'icon': Icons.lock_outline, 'onTap': _openChangePasswordSheet},
          {'label': 'Privasi & Keamanan', 'icon': Icons.shield_outlined, 'onTap': _openPrivacySheet},
        ],
      },
      {
        'title': 'Preferensi',
        'items': [
          {'label': 'Notifikasi', 'icon': Icons.notifications_outlined, 'onTap': _openNotificationsSheet},
          {'label': 'Bahasa', 'icon': Icons.language, 'trailing': _language, 'onTap': _openLanguageSheet},
        ],
      },
      {
        'title': 'Lainnya',
        'items': [
          {'label': 'Bantuan & Dukungan', 'icon': Icons.help_outline, 'onTap': _openHelpSheet},
          {'label': 'Tentang Aplikasi', 'icon': Icons.info_outline, 'onTap': _openAboutSheet},
          {'label': 'Keluar', 'icon': Icons.logout, 'danger': true, 'onTap': _logout},
        ],
      },
    ];

    return Column(
      children: groups.map((group) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group['title'] as String, style: label),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              children: (group['items'] as List).asMap().entries.map((e) {
                final i = e.key; final item = e.value as Map;
                final isDanger = item['danger'] == true;
                final onTap = item['onTap'] as VoidCallback?;
                final trailingText = item['trailing'] as String?;
                return Column(children: [
                  Material(
                    color: surface,
                    borderRadius: i == 0
                      ? const BorderRadius.vertical(top: Radius.circular(12))
                      : i == (group['items'] as List).length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(12))
                        : BorderRadius.zero,
                    child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          Icon(item['icon'] as IconData, size: 18,
                            color: isDanger ? const Color(0xFFE54D4D) : dim1),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item['label'] as String,
                            style: subTitle.copyWith(
                              color: isDanger ? const Color(0xFFE54D4D) : textPrimary))),
                          if (trailingText != null) ...[
                            Text(trailingText, style: caption),
                            const SizedBox(width: 6),
                          ],
                          Icon(Icons.chevron_right, color: dim2, size: 16),
                        ]),
                      ),
                    ),
                  ),
                  if (i < (group['items'] as List).length - 1)
                    const Divider(height: 1, color: Color(0x1A1E3A5F)),
                ]);
              }).toList(),
            ),
          ),
        ]),
      )).toList(),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _errMsg;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_newCtrl.text.length < 8) {
      setState(() => _errMsg = 'Password baru minimal 8 karakter');
      return;
    }
    if (_newCtrl.text != _confirmCtrl.text) {
      setState(() => _errMsg = 'Konfirmasi password tidak cocok');
      return;
    }
    setState(() {
      _busy = true;
      _errMsg = null;
    });
    try {
      await AuthService.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _errMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Ubah Kata Sandi', style: heading.copyWith(fontSize: 18)),
            const SizedBox(height: 14),
            if (_errMsg != null) ...[
              Text(_errMsg!, style: caption.copyWith(color: Colors.red)),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Kata Sandi Saat Ini'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Kata Sandi Baru (min 8 karakter)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Konfirmasi Kata Sandi Baru'),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: brandNavy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Text('Simpan Kata Sandi', style: buttonStyle),
            ),
          ],
        ),
      ),
    );
  }
}

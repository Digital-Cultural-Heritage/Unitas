import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/auth_service.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.onLogout});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _tab = 'tentang';
  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await UsersService.getMe();
      if (mounted) setState(() { _profile = data; _loading = false; });
    } catch (_) {
      // Fallback ke stored user
      final stored = await AuthService.getStoredUser();
      if (mounted) setState(() { _profile = stored; _loading = false; });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        title: Text('Keluar', style: heading.copyWith(fontSize: 18)),
        content: Text('Apakah kamu yakin ingin keluar?', style: body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text('Batal', style: caption.copyWith(color: dim1))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Keluar', style: caption.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await AuthService.logout();
      widget.onLogout();
    }
  }

  String _initials() {
    final name = _profile?['full_name'] ?? '';
    final parts = name.split(' ');
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Cover
        Stack(children: [
          SizedBox(
            height: 120, width: double.infinity,
            child: Image.network(
              'https://images.unsplash.com/photo-1748144679532-c36d9d5584e6?w=600&h=240&fit=crop',
              fit: BoxFit.cover,
              color: Colors.black54,
              colorBlendMode: BlendMode.darken,
            ),
          ),
          Positioned.fill(child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, brandBg], stops: [0.5, 1.0],
              ),
            ),
          )),
        ]),
        // Profile section
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Transform.translate(
            offset: const Offset(0, -42),
            child: _loading
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: brandNavy)))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end, children: [
                    // Avatar
                    _profile?['avatar_url'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(_profile!['avatar_url'], width: 70, height: 70, fit: BoxFit.cover))
                      : Container(
                          width: 70, height: 70,
                          decoration: BoxDecoration(
                            color: const Color(0xFF7A4B2B),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: brandBg, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(_initials(), style: heading.copyWith(color: Colors.white, fontSize: 20)),
                        ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () async {
                        if (_profile == null) return;
                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EditProfileScreen(initialProfile: _profile!),
                          ),
                        );
                        if (result == true) {
                          _load();
                        }
                      },
                      child: Text('Edit Profil', style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Text(_profile?['full_name'] ?? '—', style: heading),
                  const SizedBox(height: 3),
                  Text('${_profile?['prodi'] ?? ''} · Angkatan ${_profile?['angkatan'] ?? ''}',
                    style: body.copyWith(color: dim2)),
                  if ((_profile?['pekerjaan'] ?? '').isNotEmpty)
                    Text('${_profile!['pekerjaan']} · ${_profile!['perusahaan'] ?? ''} · ${_profile!['kota'] ?? ''}',
                      style: body.copyWith(color: dim2)),
                  const SizedBox(height: 18),
                  // Stats
                  Row(children: [
                    {'val': '${_profile?['points'] ?? 0}', 'label': 'Poin'},
                    {'val': '—', 'label': 'Koneksi'},
                    {'val': '—', 'label': 'Acara'},
                  ].asMap().entries.map((e) {
                    final i = e.key; final s = e.value;
                    return Expanded(child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: surface,
                        border: Border(
                          top: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor),
                          left: BorderSide(color: borderColor),
                          right: i < 2 ? BorderSide(color: borderColor) : BorderSide.none,
                        ),
                        borderRadius: BorderRadius.horizontal(
                          left: i == 0 ? const Radius.circular(10) : Radius.zero,
                          right: i == 2 ? const Radius.circular(10) : Radius.zero,
                        ),
                      ),
                      child: Column(children: [
                        Text(s['val']!, style: statStyle.copyWith(fontSize: 20, color: brandNavy)),
                        const SizedBox(height: 2),
                        Text(s['label']!, style: caption),
                      ]),
                    ));
                  }).toList()),
                  const SizedBox(height: 20),
                  // Tabs
                  Row(children: ['tentang', 'pencapaian', 'pengaturan'].map((t) =>
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
                          '${t[0].toUpperCase()}${t.substring(1)}',
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
                  if (_tab == 'tentang') _buildTentang(),
                  if (_tab == 'pencapaian') _buildPencapaian(),
                  if (_tab == 'pengaturan') _buildPengaturan(),
                ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildTentang() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tentang Saya', style: label),
      const SizedBox(height: 8),
      Text(
        (_profile?['bio'] ?? '').isNotEmpty
          ? _profile!['bio']
          : 'Belum ada bio. Tambahkan bio kamu di Edit Profil.',
        style: body.copyWith(height: 1.65, color: (_profile?['bio'] ?? '').isEmpty ? dim2 : textPrimary),
      ),
      const SizedBox(height: 16),
      const Divider(color: Color(0x1A1E3A5F)),
      const SizedBox(height: 16),
      Text('Email', style: label),
      const SizedBox(height: 8),
      Text(_profile?['email'] ?? '—', style: body),
      if ((_profile?['linkedin'] ?? '').isNotEmpty) ...[
        const SizedBox(height: 12),
        Text('LinkedIn', style: label),
        const SizedBox(height: 8),
        Text(_profile!['linkedin'], style: body.copyWith(color: brandNavy)),
      ],
    ]);
  }

  Widget _buildPencapaian() {
    final items = [
      {'label': 'Poin Komunitas', 'desc': '${_profile?['points'] ?? 0} poin', 'icon': Icons.emoji_events_outlined},
      {'label': 'Bergabung', 'desc': 'Anggota Unitas', 'icon': Icons.military_tech_outlined},
    ];
    return Column(children: items.asMap().entries.map((e) {
      final i = e.key; final a = e.value;
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: const Color(0x1A1E3A5F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Icon(a['icon'] as IconData, color: brandNavy, size: 18),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['label'] as String, style: subTitle),
              Text(a['desc'] as String, style: caption),
            ]),
          ]),
        ),
        if (i < items.length - 1) const Divider(height: 1, color: Color(0x1A1E3A5F)),
      ]);
    }).toList());
  }

  Widget _buildPengaturan() {
    final groups = [
      {
        'title': 'Akun',
        'items': [
          {'label': 'Edit Profil', 'icon': Icons.person_outline},
          {'label': 'Ubah Kata Sandi', 'icon': Icons.lock_outline},
          {'label': 'Privasi & Keamanan', 'icon': Icons.shield_outlined},
        ],
      },
      {
        'title': 'Preferensi',
        'items': [
          {'label': 'Notifikasi', 'icon': Icons.notifications_outlined},
          {'label': 'Bahasa', 'icon': Icons.language},
        ],
      },
      {
        'title': 'Lainnya',
        'items': [
          {'label': 'Bantuan & Dukungan', 'icon': Icons.help_outline},
          {'label': 'Tentang Aplikasi', 'icon': Icons.info_outline},
          {'label': 'Keluar', 'icon': Icons.logout, 'danger': true},
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
                final isLogout = item['label'] == 'Keluar';
                return Column(children: [
                  Material(
                    color: surface,
                    borderRadius: i == 0
                      ? const BorderRadius.vertical(top: Radius.circular(12))
                      : i == (group['items'] as List).length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(12))
                        : BorderRadius.zero,
                    child: InkWell(
                      onTap: isLogout ? _logout : () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          Icon(item['icon'] as IconData, size: 18,
                            color: isDanger ? const Color(0xFFE54D4D) : dim1),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item['label'] as String,
                            style: subTitle.copyWith(
                              color: isDanger ? const Color(0xFFE54D4D) : textPrimary))),
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

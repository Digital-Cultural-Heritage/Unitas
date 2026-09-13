import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String _tab = 'tentang';

  final List<Map<String, dynamic>> _menuGroups = [
    {
      'title': 'Akun',
      'items': [
        {'label': 'Edit Profil',         'icon': Icons.person_outline},
        {'label': 'Ubah Kata Sandi',      'icon': Icons.lock_outline},
        {'label': 'Privasi & Keamanan',   'icon': Icons.shield_outlined},
      ],
    },
    {
      'title': 'Preferensi',
      'items': [
        {'label': 'Notifikasi',           'icon': Icons.notifications_outlined},
        {'label': 'Bahasa',               'icon': Icons.language},
        {'label': 'Tema Tampilan',        'icon': Icons.palette_outlined},
      ],
    },
    {
      'title': 'Lainnya',
      'items': [
        {'label': 'Bantuan & Dukungan',   'icon': Icons.help_outline},
        {'label': 'Tentang Aplikasi',     'icon': Icons.info_outline},
        {'label': 'Keluar',               'icon': Icons.logout, 'danger': true},
      ],
    },
  ];

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
                colors: [Colors.transparent, brandBg],
                stops: [0.5, 1.0],
              ),
            ),
          )),
        ]),
        // Profile section
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
          child: Transform.translate(
            offset: const Offset(0, -42),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Container(
                  width: 70, height: 70,
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A4B2B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: brandBg, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: Text('AF', style: heading.copyWith(color: Colors.white, fontSize: 20)),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {},
                  child: Text('Edit Profil', style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
                ),
              ]),
              const SizedBox(height: 14),
              Text('Ahmad Fauzi', style: heading),
              const SizedBox(height: 3),
              Text('Teknik Informatika · Angkatan 2012', style: body.copyWith(color: dim2)),
              Text('Lead Engineer · Bukalapak · Jakarta', style: body.copyWith(color: dim2)),
              const SizedBox(height: 18),
              // Stats
              Row(children: [
                {'val': '1.990', 'label': 'Poin'},
                {'val': '248',   'label': 'Koneksi'},
                {'val': '7',     'label': 'Acara'},
              ].asMap().entries.map((e) {
                final i = e.key; final s = e.value;
                return Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: surface,
                    border: Border(
                      top: BorderSide(color: borderColor),
                      bottom: BorderSide(color: borderColor),
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
              // Tab content
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
        'Lead Engineer dengan 10+ tahun pengalaman di pengembangan produk digital. Alumnus Teknik Informatika Universitas Nusantara 2012. Passionate dalam membangun teknologi yang berdampak.',
        style: body.copyWith(height: 1.65),
      ),
      const SizedBox(height: 16),
      const Divider(color: Color(0x1A_1E3A5F)),
      const SizedBox(height: 16),
      Text('Koneksi Alumni', style: label),
      const SizedBox(height: 12),
      Row(children: [
        ...[ {'i': 'BS', 'c': const Color(0xFF2B4F7A)},
             {'i': 'CD', 'c': const Color(0xFF2D6060)},
             {'i': 'ER', 'c': const Color(0xFF6B2A4F)},
             {'i': 'HK', 'c': const Color(0xFF2B4F7A)},
             {'i': 'FN', 'c': const Color(0xFF2D6A27)},
        ].asMap().entries.map((e) => Transform.translate(
          offset: Offset(e.key > 0 ? -10.0 * e.key : 0, 0),
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: e.value['c'] as Color, shape: BoxShape.circle,
              border: Border.all(color: brandBg, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(e.value['i'] as String, style: caption.copyWith(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
          ),
        )),
        const SizedBox(width: 4),
        Text('+243 lainnya', style: caption),
      ]),
    ]);
  }

  Widget _buildPencapaian() {
    final items = [
      {'label': 'Top Kontributor', 'desc': 'Maret 2026',     'icon': Icons.emoji_events_outlined},
      {'label': 'Mentor Aktif',    'desc': '12 mentee',      'icon': Icons.military_tech_outlined},
      {'label': 'Event Organizer', 'desc': '3 acara dikelola','icon': Icons.notifications_outlined},
    ];
    return Column(
      children: items.asMap().entries.map((e) {
        final i = e.key; final a = e.value;
        return Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color: const Color(0x1A_1E3A5F),
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
          if (i < items.length - 1) const Divider(height: 1, color: Color(0x1A_1E3A5F)),
        ]);
      }).toList(),
    );
  }

  Widget _buildPengaturan() {
    return Column(
      children: _menuGroups.map((group) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(group['title'], style: label),
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
                return Column(children: [
                  Material(
                    color: surface,
                    borderRadius: i == 0
                      ? const BorderRadius.vertical(top: Radius.circular(12))
                      : i == (group['items'] as List).length - 1
                        ? const BorderRadius.vertical(bottom: Radius.circular(12))
                        : BorderRadius.zero,
                    child: InkWell(
                      onTap: () {},
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        child: Row(children: [
                          Icon(item['icon'] as IconData, size: 18,
                            color: isDanger ? const Color(0xFFE54D4D) : dim1),
                          const SizedBox(width: 12),
                          Expanded(child: Text(item['label'] as String,
                            style: subTitle.copyWith(color: isDanger ? const Color(0xFFE54D4D) : textPrimary))),
                          Icon(Icons.chevron_right, color: dim2, size: 16),
                        ]),
                      ),
                    ),
                  ),
                  if (i < (group['items'] as List).length - 1)
                    const Divider(height: 1, color: Color(0x1A_1E3A5F)),
                ]);
              }).toList(),
            ),
          ),
        ]),
      )).toList(),
    );
  }
}

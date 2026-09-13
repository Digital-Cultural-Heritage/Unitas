import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../widgets/avatar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Map<String, dynamic>> _posts = [
    {'id': 1, 'name': 'Budi Santoso', 'sub': 'Tek. Sipil · 2010', 'init': 'BS', 'col': const Color(0xFF2B4F7A), 'time': '2j', 'text': 'Reuni Akbar 2026 sungguh luar biasa. Bertemu teman-teman lama setelah belasan tahun — tidak ada yang bisa menggantikan momen seperti itu.', 'likes': 48, 'comments': 12, 'liked': false},
    {'id': 2, 'name': 'Redaksi Alumni', 'sub': 'Universitas Nusantara', 'init': 'UN', 'col': const Color(0xFF2D6A27), 'time': '5j', 'text': 'Selamat kepada Prof. Dr. Amalia Putri (Angkatan 1995) yang baru dilantik sebagai Rektor UGM periode 2026–2031.', 'likes': 234, 'comments': 56, 'liked': true},
    {'id': 3, 'name': 'Reza Firmansyah', 'sub': 'Ekonomi · 2015', 'init': 'RF', 'col': const Color(0xFF5C3D8C), 'time': '1h', 'text': 'Startup kami baru mendapatkan pendanaan Seri A. Terima kasih kepada semua mentor dari jaringan alumni yang selalu mendukung.', 'likes': 189, 'comments': 34, 'liked': false},
  ];

  final List<Map<String, String>> _friends = [
    {'name': 'Adzana',   'img': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=80&h=80&fit=crop'},
    {'name': 'Feera',    'img': 'https://images.unsplash.com/photo-1438761681033-6461ffad8d80?w=80&h=80&fit=crop'},
    {'name': 'Kevin',    'img': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=80&h=80&fit=crop'},
    {'name': 'Laila',    'img': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=80&h=80&fit=crop'},
    {'name': 'Fernando', 'img': 'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=80&h=80&fit=crop'},
  ];

  final List<Map<String, dynamic>> _leaderboard = [
    {'rank': 1, 'name': 'Amalia Putri',  'pts': '2.840', 'init': 'AP', 'col': const Color(0xFF2D6A27)},
    {'rank': 2, 'name': 'Hendra Kusuma', 'pts': '2.310', 'init': 'HK', 'col': const Color(0xFF2B4F7A)},
    {'rank': 3, 'name': 'Ahmad Fauzi',   'pts': '1.990', 'init': 'AF', 'col': const Color(0xFF7A4B2B)},
  ];

  void _toggleLike(int id) {
    setState(() {
      final post = _posts.firstWhere((p) => p['id'] == id);
      post['liked'] = !post['liked'];
      post['likes'] += post['liked'] ? 1 : -1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildSearch(),
            _buildFriends(),
            _buildComposer(),
            _buildStats(),
            _buildLeaderboard(),
            _buildFeed(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Selamat datang kembali', style: caption),
            Text('Ahmad Fauzi', style: heading),
          ]),
          Row(children: [
            Stack(children: [
              const Icon(Icons.notifications_outlined, color: Color(0x99_1E3A5F), size: 22),
              Positioned(top: 0, right: 0, child: Container(
                width: 7, height: 7,
                decoration: BoxDecoration(color: brandNavy, shape: BoxShape.circle,
                  border: Border.all(color: brandBg, width: 1.5)),
              )),
            ]),
            const SizedBox(width: 10),
            Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(color: Color(0xFF7A4B2B), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text('AF', style: small.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
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
        const Icon(Icons.search, color: Color(0x61_1E3A5F), size: 16),
        const SizedBox(width: 10),
        Text('Cari alumni, acara, lowongan…', style: body.copyWith(color: dim2)),
      ]),
    );
  }

  Widget _buildFriends() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Teman Alumni', style: label),
          Text('Lihat semua', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
        ]),
      ),
      SizedBox(
        height: 80,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          children: [
            // Add button
            Column(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: dim2, style: BorderStyle.solid, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Color(0x61_1E3A5F), size: 20),
              ),
              const SizedBox(height: 6),
              Text('Tambah', style: caption),
            ]),
            const SizedBox(width: 16),
            ..._friends.map((f) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor, width: 1.5),
                    image: DecorationImage(image: NetworkImage(f['img']!), fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(height: 6),
                Text(f['name']!, style: caption),
              ]),
            )),
          ],
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildComposer() {
    return Container(
      margin: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(color: Color(0xFF7A4B2B), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text('AF', style: small.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text('Bagikan sesuatu…', style: body.copyWith(color: dim2))),
        ]),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(Icons.image_outlined, color: dim2, size: 16),
            const SizedBox(width: 5),
            Text('Foto', style: caption),
            const SizedBox(width: 14),
            Icon(Icons.videocam_outlined, color: dim2, size: 16),
            const SizedBox(width: 5),
            Text('Video', style: caption),
          ]),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: brandNavy, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () {},
            child: Text('Posting', style: buttonStyle),
          ),
        ]),
      ]),
    );
  }

  Widget _buildStats() {
    final stats = [
      {'val': '42.500+', 'label': 'Total Alumni', 'sub': 'di seluruh Indonesia'},
      {'val': '12', 'label': 'Acara Aktif', 'sub': 'bulan September'},
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s['val']!, style: statStyle),
            const SizedBox(height: 4),
            Text(s['label']!, style: subTitle),
            Text(s['sub']!, style: caption),
          ]),
        ),
      )).toList()),
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
        const Divider(height: 1, color: Color(0x1A_1E3A5F)),
        ..._leaderboard.asMap().entries.map((e) {
          final i = e.key; final item = e.value;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                item['rank'] == 1
                  ? const Icon(Icons.military_tech, color: brandNavy, size: 16)
                  : SizedBox(width: 16, child: Text('${item['rank']}', style: caption, textAlign: TextAlign.center)),
                const SizedBox(width: 12),
                UnitasAvatar(initials: item['init'], color: item['col'], size: 34),
                const SizedBox(width: 12),
                Expanded(child: Text(item['name'], style: subTitle)),
                Text(item['pts'], style: subTitle.copyWith(
                  color: item['rank'] == 1 ? brandNavy : dim1,
                  fontWeight: FontWeight.w700,
                )),
              ]),
            ),
            if (i < _leaderboard.length - 1) const Divider(height: 1, color: Color(0x1A_1E3A5F)),
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
        ..._posts.map((post) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              UnitasAvatar(initials: post['init'], color: post['col']),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(post['name'], style: subTitle),
                Text('${post['sub']} · ${post['time']}', style: caption),
              ])),
              const Icon(Icons.more_vert, color: Color(0x61_1E3A5F), size: 18),
            ]),
            const SizedBox(height: 10),
            Text(post['text'], style: body.copyWith(height: 1.6)),
            const SizedBox(height: 14),
            Row(children: [
              GestureDetector(
                onTap: () => _toggleLike(post['id']),
                child: Row(children: [
                  Icon(post['liked'] ? Icons.favorite : Icons.favorite_border,
                    color: post['liked'] ? const Color(0xFFE54D4D) : dim2, size: 16),
                  const SizedBox(width: 5),
                  Text('${post['likes']}', style: caption.copyWith(
                    color: post['liked'] ? const Color(0xFFE54D4D) : dim2,
                    fontWeight: FontWeight.w500,
                  )),
                ]),
              ),
              const SizedBox(width: 18),
              Row(children: [
                Icon(Icons.chat_bubble_outline, color: dim2, size: 16),
                const SizedBox(width: 5),
                Text('${post['comments']}', style: caption.copyWith(fontWeight: FontWeight.w500)),
              ]),
              const Spacer(),
              Icon(Icons.share_outlined, color: dim2, size: 16),
            ]),
          ]),
        )),
      ]),
    );
  }
}

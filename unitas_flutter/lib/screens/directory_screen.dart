import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/api_client.dart';
import '../widgets/avatar.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  String _q = '';
  String _filter = 'Semua';
  List<Map<String, dynamic>> _alumni = [];
  bool _loading = true;
  String? _error;
  String? _currentUserId;

  final List<String> _filters = ['Semua', 'Terhubung', 'Jakarta', 'Lainnya'];

  @override
  void initState() {
    super.initState();
    _load();
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

      if (mounted) setState(() { _alumni = data; _loading = false; });
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
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
              onChanged: (v) { _q = v; _load(); },
              style: body,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Cari nama atau jurusan…',
                hintStyle: body.copyWith(color: dim2),
                icon: Icon(Icons.search, color: dim2, size: 16),
              ),
            ),
          ),
          // Filters
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
              children: _filters.map((f) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () { setState(() => _filter = f); _load(); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _filter == f ? brandNavy : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _filter == f ? brandNavy : borderColor),
                    ),
                    child: Text(f, style: caption.copyWith(
                      color: _filter == f ? Colors.white : dim2,
                      fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                    )),
                  ),
                ),
              )).toList(),
            ),
          ),
          // Content
          if (_loading)
            const Center(child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: brandNavy),
            ))
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(_error!, style: caption.copyWith(color: dim2)),
            )
          else if (_alumni.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(child: Column(children: [
                const Icon(Icons.people_outline, color: Color(0x611E3A5F), size: 40),
                const SizedBox(height: 12),
                Text('Tidak ada alumni ditemukan', style: subTitle),
              ])),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Column(
                children: _alumni.asMap().entries.map((e) {
                  final i = e.key; final p = e.value;
                  final userId = p['user_id']?.toString() ?? '';
                  final isOnline = p['is_online'] == true;
                  final prodi = p['prodi'] ?? '';
                  final angkatan = p['angkatan'] ?? '';
                  final short = angkatan.length >= 2 ? angkatan.substring(angkatan.length - 2) : angkatan;
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(children: [
                        UnitasAvatar(initials: _initials(p), color: _colorFor(i)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(child: Text(p['full_name'] ?? '—', style: subTitle, overflow: TextOverflow.ellipsis)),
                            if (isOnline) ...[
                              const SizedBox(width: 6),
                              Container(width: 6, height: 6,
                                decoration: const BoxDecoration(color: brandNavy, shape: BoxShape.circle)),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text('${p['pekerjaan'] ?? ''} · ${p['perusahaan'] ?? ''}'.trim().replaceAll(RegExp(r'^\s*·\s*|\s*·\s*$'), ''),
                            style: caption, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 4),
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: card, borderRadius: BorderRadius.circular(5),
                                border: Border.all(color: borderColor),
                              ),
                              child: Text("$prodi '$short", style: caption),
                            ),
                            if ((p['kota'] ?? '').isNotEmpty) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.location_on_outlined, size: 10, color: Color(0x611E3A5F)),
                              Flexible(child: Text(p['kota'], style: caption, overflow: TextOverflow.ellipsis)),
                            ],
                          ]),
                        ])),
                        const SizedBox(width: 8),
                        if (_currentUserId != null && userId == _currentUserId)
                          const SizedBox.shrink()
                        else
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isOnline ? Colors.transparent : brandNavy,
                              foregroundColor: isOnline ? dim2 : Colors.white,
                              side: BorderSide(color: isOnline ? borderColor : brandNavy),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () async {
                              try {
                                await UsersService.connect(userId);
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Permintaan koneksi dikirim')));
                              } catch (_) {}
                            },
                            child: Text(isOnline ? 'Terhubung' : 'Hubungi',
                              style: caption.copyWith(
                                color: isOnline ? dim2 : Colors.white,
                                fontWeight: FontWeight.w600,
                              )),
                          ),
                      ]),
                    ),
                    if (i < _alumni.length - 1) const Divider(height: 1, color: Color(0x1A1E3A5F)),
                  ]);
                }).toList(),
              ),
            ),
        ]),
      ),
    );
  }
}

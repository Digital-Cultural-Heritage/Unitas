import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../widgets/avatar.dart';

class DirectoryScreen extends StatefulWidget {
  const DirectoryScreen({super.key});
  @override
  State<DirectoryScreen> createState() => _DirectoryScreenState();
}

class _DirectoryScreenState extends State<DirectoryScreen> {
  String _q = '';
  String _filter = 'Semua';

  final List<Map<String, dynamic>> _alumni = [
    {'id': 1, 'name': 'Amalia Putri',   'prodi': 'Hukum',       'year': '1995', 'role': 'Rektor UGM',              'init': 'AP', 'col': const Color(0xFF2D6A27), 'city': 'Yogyakarta', 'on': true},
    {'id': 2, 'name': 'Budi Santoso',   'prodi': 'Tek. Sipil',  'year': '2010', 'role': 'Sr. Engineer · Waskita',  'init': 'BS', 'col': const Color(0xFF2B4F7A), 'city': 'Jakarta',    'on': true},
    {'id': 3, 'name': 'Citra Dewi',     'prodi': 'Manajemen',   'year': '2013', 'role': 'Marketing Dir · Tokopedia','init': 'CD', 'col': const Color(0xFF2D6060), 'city': 'Jakarta',    'on': false},
    {'id': 4, 'name': 'Denny Wirawan',  'prodi': 'Kedokteran',  'year': '2008', 'role': 'Spesialis Jantung · RSCM', 'init': 'DW', 'col': const Color(0xFF6B5B2A), 'city': 'Jakarta',    'on': false},
    {'id': 5, 'name': 'Eka Rahmawati',  'prodi': 'Psikologi',   'year': '2016', 'role': 'HR Lead · Gojek',          'init': 'ER', 'col': const Color(0xFF6B2A4F), 'city': 'Bandung',    'on': true},
    {'id': 6, 'name': 'Fajar Nugroho',  'prodi': 'Ekonomi',     'year': '2011', 'role': 'Co-Founder · FinTech ID',  'init': 'FN', 'col': const Color(0xFF2D6A27), 'city': 'Surabaya',   'on': false},
    {'id': 7, 'name': 'Gita Sari',      'prodi': 'Arsitektur',  'year': '2014', 'role': 'Principal Arch · DKSA',    'init': 'GS', 'col': const Color(0xFF7A4B2B), 'city': 'Bali',       'on': false},
    {'id': 8, 'name': 'Hendra Kusuma',  'prodi': 'Informatika', 'year': '2017', 'role': 'Software Eng · Google',    'init': 'HK', 'col': const Color(0xFF2B4F7A), 'city': 'Singapura',  'on': true},
  ];

  final List<String> _filters = ['Semua', 'Terhubung', 'Jakarta', 'Lainnya'];

  List<Map<String, dynamic>> get _filtered => _alumni.where((a) {
    final match = a['name'].toString().toLowerCase().contains(_q.toLowerCase()) ||
                  a['prodi'].toString().toLowerCase().contains(_q.toLowerCase());
    if (_filter == 'Terhubung') return match && a['on'] == true;
    if (_filter == 'Jakarta')   return match && a['city'] == 'Jakarta';
    if (_filter == 'Lainnya')   return match && a['city'] != 'Jakarta';
    return match;
  }).toList();

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
              Text('42.500+ alumni', style: caption),
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
              onChanged: (v) => setState(() => _q = v),
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
                  onTap: () => setState(() => _filter = f),
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
          // List
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: _filtered.asMap().entries.map((e) {
                final i = e.key; final p = e.value;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    child: Row(children: [
                      UnitasAvatar(initials: p['init'], color: p['col']),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(p['name'], style: subTitle),
                          if (p['on'] == true) ...[
                            const SizedBox(width: 6),
                            Container(width: 6, height: 6,
                              decoration: const BoxDecoration(color: brandNavy, shape: BoxShape.circle)),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(p['role'], style: caption, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: card, borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text("${p['prodi']} '${p['year'].toString().substring(2)}", style: caption),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.location_on_outlined, size: 10, color: Color(0x61_1E3A5F)),
                          Text(p['city'], style: caption),
                        ]),
                      ])),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: p['on'] == true ? Colors.transparent : brandNavy,
                          foregroundColor: p['on'] == true ? dim2 : Colors.white,
                          side: BorderSide(color: p['on'] == true ? borderColor : brandNavy),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () {},
                        child: Text(p['on'] == true ? 'Terhubung' : 'Hubungi',
                          style: caption.copyWith(
                            color: p['on'] == true ? dim2 : Colors.white,
                            fontWeight: FontWeight.w600,
                          )),
                      ),
                    ]),
                  ),
                  if (i < _filtered.length - 1) const Divider(height: 1, color: Color(0x1A_1E3A5F)),
                ]);
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _filter = 'Semua';
  final Map<int, bool> _saved = {1: false, 2: true, 3: false, 4: false, 5: false};

  final List<Map<String, dynamic>> _jobs = [
    {'id': 1, 'title': 'Senior Software Engineer', 'co': 'Tokopedia',    'logo': 'TO', 'col': const Color(0xFF1A5C2E), 'loc': 'Jakarta · Hybrid', 'sal': 'Rp 25–40 jt', 'tags': ['React','Node.js','AWS'],    'by': "Hendra K. '17"},
    {'id': 2, 'title': 'Product Manager',          'co': 'Gojek',        'logo': 'GO', 'col': const Color(0xFF1A5C1A), 'loc': 'Jakarta · Remote', 'sal': 'Rp 30–50 jt', 'tags': ['Product','Agile','Data'],  'by': "Eka R. '16"},
    {'id': 3, 'title': 'Financial Analyst',        'co': 'Bank Mandiri', 'logo': 'BM', 'col': const Color(0xFF0A2E6B), 'loc': 'Jakarta · Onsite', 'sal': 'Rp 15–22 jt', 'tags': ['Finance','SQL','Excel'],   'by': "Fajar N. '11"},
    {'id': 4, 'title': 'UI/UX Designer',           'co': 'Traveloka',    'logo': 'TR', 'col': const Color(0xFF0A3D6B), 'loc': 'Jakarta · Hybrid', 'sal': 'Rp 18–28 jt', 'tags': ['Figma','Research'],        'by': "Gita S. '14"},
    {'id': 5, 'title': 'Data Scientist',           'co': 'Bukalapak',    'logo': 'BL', 'col': const Color(0xFF5C1A1A), 'loc': 'Remote',           'sal': 'Rp 22–35 jt', 'tags': ['Python','ML','SQL'],        'by': "Rizky M. '15"},
  ];

  final List<String> _filters = ['Semua', 'Full-time', 'Remote', 'Tersimpan'];

  List<Map<String, dynamic>> get _list => _jobs.where((j) {
    if (_filter == 'Remote')    return j['loc'].toString().contains('Remote');
    if (_filter == 'Tersimpan') return _saved[j['id']] == true;
    return true;
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
              Text('87 lowongan eksklusif alumni', style: caption),
              Text('Bursa Karier', style: heading),
            ]),
          ),
          // Stats strip
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Builder(builder: (context) {
              final stats = [
                {'val': '87', 'label': 'Lowongan'},
                {'val': '34', 'label': 'Perusahaan'},
                {'val': '12', 'label': 'Remote'},
              ];
              return Row(children: stats.asMap().entries.map((e) {
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
                    Text(s['val']!, style: statStyle.copyWith(fontSize: 18, color: brandNavy)),
                    Text(s['label']!, style: caption),
                  ]),
                ));
              }).toList());
            }),
          ),
          // Filters
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
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
          // Job list
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              children: _list.asMap().entries.map((e) {
                final i = e.key; final job = e.value;
                final isSaved = _saved[job['id']] ?? false;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Column(children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(color: job['col'], borderRadius: BorderRadius.circular(10)),
                          alignment: Alignment.center,
                          child: Text(job['logo'], style: caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(job['title'], style: subTitle),
                          Text(job['co'], style: caption),
                        ])),
                        GestureDetector(
                          onTap: () => setState(() => _saved[job['id']] = !isSaved),
                          child: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border,
                            color: isSaved ? brandNavy : dim2, size: 20),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 5, runSpacing: 5, children: (job['tags'] as List).map<Widget>((tag) =>
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: card, borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(tag, style: caption.copyWith(color: dim1)),
                        ),
                      ).toList()),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Icon(Icons.location_on_outlined, size: 10, color: dim2),
                            const SizedBox(width: 4),
                            Text(job['loc'], style: caption),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.attach_money, size: 10, color: brandNavy),
                            const SizedBox(width: 4),
                            Text('${job['sal']}/bln', style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
                          ]),
                          const SizedBox(height: 2),
                          RichText(text: TextSpan(children: [
                            TextSpan(text: 'via ', style: caption),
                            TextSpan(text: job['by'], style: caption.copyWith(color: brandNavy)),
                          ])),
                        ]),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandNavy, foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          onPressed: () {},
                          child: Text('Lamar', style: buttonStyle),
                        ),
                      ]),
                    ]),
                  ),
                  if (i < _list.length - 1) const Divider(height: 1, color: Color(0x1A_1E3A5F)),
                ]);
              }).toList(),
            ),
          ),
        ]),
      ),
    );
  }
}

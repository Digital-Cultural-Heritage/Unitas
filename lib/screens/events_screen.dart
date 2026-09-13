import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _active = 'Semua';
  final Map<int, bool> _reg = {1: true, 2: false, 3: false, 4: true};

  final List<String> _cats = ['Semua', 'Reuni', 'Seminar', 'Networking', 'Webinar'];

  final List<Map<String, dynamic>> _events = [
    {'id': 1, 'title': 'Reuni Akbar 2026',          'day': '15', 'month': 'NOV', 'year': '2026', 'time': '09.00–17.00', 'location': 'Graha Nusantara, Jakarta',  'cat': 'Reuni',      'attend': 1240},
    {'id': 2, 'title': 'Alumni Tech Summit',         'day': '22', 'month': 'OKT', 'year': '2026', 'time': '08.00–16.00', 'location': 'The Kasablanka, Jakarta',   'cat': 'Seminar',    'attend': 450},
    {'id': 3, 'title': 'Networking Malam Alumni',    'day': '5',  'month': 'OKT', 'year': '2026', 'time': '18.30–21.00', 'location': 'Ritz Carlton, Bandung',     'cat': 'Networking', 'attend': 120},
    {'id': 4, 'title': 'Webinar: Tren Industri 4.0', 'day': '28', 'month': 'SEP', 'year': '2026', 'time': '14.00–16.00', 'location': 'Online · Zoom',             'cat': 'Webinar',    'attend': 890},
  ];

  List<Map<String, dynamic>> get _list => _events
    .where((e) => _active == 'Semua' || e['cat'] == _active)
    .toList();

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
              Text('12 acara aktif', style: caption),
              Text('Acara & Kegiatan', style: heading),
            ]),
          ),
          // Featured card
          Container(
            margin: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            height: 170,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: surface,
              image: const DecorationImage(
                image: NetworkImage('https://images.unsplash.com/photo-1685401704618-fd8243812ef7?w=700&h=340&fit=crop'),
                fit: BoxFit.cover,
                opacity: 0.5,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x88_1E3A5F)],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: brandNavy, borderRadius: BorderRadius.circular(6)),
                  child: Text('UNGGULAN', style: buttonStyle.copyWith(fontSize: 11)),
                ),
                const SizedBox(height: 8),
                Text('Reuni Akbar 2026', style: heading.copyWith(color: Colors.white, fontSize: 18)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time, size: 11, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('15 November · 09.00 WIB', style: caption.copyWith(color: Colors.white70)),
                  const SizedBox(width: 10),
                  const Icon(Icons.location_on_outlined, size: 11, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text('Jakarta', style: caption.copyWith(color: Colors.white70)),
                ]),
              ]),
            ),
          ),
          // Filters
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              children: _cats.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => setState(() => _active = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _active == cat ? brandNavy : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _active == cat ? brandNavy : borderColor),
                    ),
                    child: Text(cat, style: caption.copyWith(
                      color: _active == cat ? Colors.white : dim2,
                      fontWeight: _active == cat ? FontWeight.w600 : FontWeight.w400,
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
              children: _list.asMap().entries.map((e) {
                final i = e.key; final ev = e.value;
                final isReg = _reg[ev['id']] ?? false;
                return Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Date column
                      SizedBox(
                        width: 44,
                        child: Column(children: [
                          Text(ev['day'], style: statStyle.copyWith(fontSize: 22)),
                          Text(ev['month'], style: label.copyWith(color: brandNavy)),
                        ]),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(ev['title'], style: subTitle, maxLines: 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: card, borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: borderColor),
                            ),
                            child: Text(ev['cat'], style: caption.copyWith(color: dim2)),
                          ),
                        ]),
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.access_time, size: 10, color: Color(0x61_1E3A5F)),
                          const SizedBox(width: 4),
                          Text('${ev['time']} WIB', style: caption),
                        ]),
                        const SizedBox(height: 2),
                        Row(children: [
                          const Icon(Icons.location_on_outlined, size: 10, color: Color(0x61_1E3A5F)),
                          const SizedBox(width: 4),
                          Expanded(child: Text(ev['location'], style: caption, overflow: TextOverflow.ellipsis)),
                        ]),
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          RichText(text: TextSpan(children: [
                            TextSpan(text: ev['attend'].toString(), style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                            TextSpan(text: ' akan hadir', style: caption),
                          ])),
                          GestureDetector(
                            onTap: () => setState(() => _reg[ev['id']] = !isReg),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: isReg ? Colors.transparent : brandNavy,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isReg ? borderColor : brandNavy),
                              ),
                              child: Text(isReg ? 'Terdaftar ✓' : 'Daftar', style: caption.copyWith(
                                color: isReg ? dim2 : Colors.white, fontWeight: FontWeight.w600,
                              )),
                            ),
                          ),
                        ]),
                      ])),
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

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/events_service.dart';
import '../core/api/api_client.dart';
import '../widgets/skeleton.dart';
import 'create_event_screen.dart';
import 'manage_event_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _active = 'Semua';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _events = [];
  List<Map<String, dynamic>> _myEvents = [];
  final Set<String> _registered = {};
  bool _loading = true;
  bool _loadingMyEvents = true;

  final List<Map<String, dynamic>> _cats = const [
    {'label': 'Semua', 'icon': Icons.apps_rounded},
    {'label': 'Reuni', 'icon': Icons.groups_outlined},
    {'label': 'Seminar', 'icon': Icons.mic_none_outlined},
    {'label': 'Networking', 'icon': Icons.hub_outlined},
    {'label': 'Webinar', 'icon': Icons.videocam_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _loadMyEvents();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await EventsService.getEvents(
        category: _active == 'Semua' ? null : _active,
      );
      if (mounted) {
        setState(() {
          _events = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMyEvents() async {
    setState(() => _loadingMyEvents = true);
    try {
      final data = await EventsService.getMyEvents();
      if (mounted) {
        setState(() {
          _myEvents = data;
          _loadingMyEvents = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMyEvents = false);
    }
  }

  Future<void> _openCreateEvent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );
    if (result == true) {
      _load();
      _loadMyEvents();
    }
  }

  Future<void> _toggleReg(String id) async {
    final isReg = _registered.contains(id);
    setState(() {
      isReg ? _registered.remove(id) : _registered.add(id);
    });
    try {
      if (isReg) {
        await EventsService.unregister(id);
      } else {
        await EventsService.register(id);
      }
    } on ApiException catch (e) {
      if (e.statusCode != 409) {
        if (mounted) {
          setState(() {
            isReg ? _registered.add(id) : _registered.remove(id);
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          isReg ? _registered.add(id) : _registered.remove(id);
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return dt.day.toString();
  }

  String _formatMonth(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MEI', 'JUN', 'JUL', 'AGU', 'SEP', 'OKT', 'NOV', 'DES'];
    return months[dt.month - 1];
  }

  List<Map<String, dynamic>> get _filteredEvents {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _events;
    return _events.where((ev) {
      final title = (ev['title'] ?? '').toString().toLowerCase();
      final loc = (ev['location'] ?? '').toString().toLowerCase();
      final cat = (ev['category'] ?? '').toString().toLowerCase();
      return title.contains(q) || loc.contains(q) || cat.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          backgroundColor: brandNavy,
          foregroundColor: Colors.white,
          onPressed: _openCreateEvent,
          icon: const Icon(Icons.add),
          label: const Text('Buat Acara', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        body: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                children: [
                  const SizedBox(
                    height: 34,
                    child: TabBar(
                      labelColor: brandNavy,
                      unselectedLabelColor: dim2,
                      indicatorColor: brandNavy,
                      indicatorWeight: 3,
                      labelPadding: EdgeInsets.zero,
                      tabs: [
                        Tab(height: 34, text: 'Semua Acara'),
                        Tab(height: 34, text: 'Acara Saya'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildAllEvents(),
                        _buildMyEvents(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyCard({
    required IconData icon,
    required String title,
    required String subtitle,
    String? secondaryLabel,
    VoidCallback? onSecondary,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: brandGold.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: brandNavy, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, style: subTitle.copyWith(fontSize: 16), textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: caption.copyWith(color: dim1, height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                onPressed: _openCreateEvent,
                icon: const Icon(Icons.add, size: 17),
                label: Text('Buat Acara', style: buttonStyle),
              ),
              if (secondaryLabel != null && onSecondary != null)
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: brandNavy,
                    side: BorderSide(color: borderColor),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: onSecondary,
                  child: Text(secondaryLabel, style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMyEvents() {
    return RefreshIndicator(
      onRefresh: _loadMyEvents,
      color: brandNavy,
      child: _loadingMyEvents
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 90),
              children: const [EventSkeletonList(padding: EdgeInsets.zero)],
            )
          : _myEvents.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 32, bottom: 90),
                  children: [
                    _buildEmptyCard(
                      icon: Icons.event_note_outlined,
                      title: 'Kamu belum membuat acara',
                      subtitle: 'Buat acara reuni, seminar, atau gathering agar alumni lain bisa ikut mendaftar.',
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 90),
                  itemCount: _myEvents.length,
                  itemBuilder: (context, index) {
                    final ev = _myEvents[index];
                    return GestureDetector(
                      onTap: () async {
                        final deleted = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ManageEventScreen(event: ev)),
                        );
                        if (deleted == true) {
                          _load();
                          _loadMyEvents();
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: brandNavy,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _formatDate(ev['event_date']),
                                    style: statStyle.copyWith(fontSize: 18, color: Colors.white),
                                  ),
                                  Text(
                                    _formatMonth(ev['event_date']),
                                    style: label.copyWith(color: brandGold, fontSize: 10),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(ev['title'] ?? '', style: subTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${ev['attendee_count'] ?? 0} pendaftar',
                                    style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: dim2),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildAllEvents() {
    final list = _filteredEvents;
    final featured = list.isNotEmpty ? list.first : null;
    final hasFilter = _active != 'Semua' || _searchQuery.trim().isNotEmpty;

    return RefreshIndicator(
      onRefresh: _load,
      color: brandNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${list.length} acara aktif', style: caption),
                        Text('Acara & Kegiatan', style: heading, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: brandGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.celebration_outlined, size: 15, color: brandNavy),
                        const SizedBox(width: 5),
                        Text('Alumni Hub', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Search bar
            Container(
              margin: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor),
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: body.copyWith(color: textPrimary),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Cari nama acara atau lokasi…',
                  hintStyle: body.copyWith(color: dim2),
                  icon: Icon(Icons.search, color: dim2, size: 18),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, size: 16, color: dim2),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
              ),
            ),

            if (featured != null)
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: surface,
                  image: featured['cover_url'] != null
                      ? DecorationImage(
                          image: NetworkImage(featured['cover_url']),
                          fit: BoxFit.cover,
                          opacity: 0.55,
                        )
                      : const DecorationImage(
                          image: NetworkImage('https://images.unsplash.com/photo-1685401704618-fd8243812ef7?w=700&h=340&fit=crop'),
                          fit: BoxFit.cover,
                          opacity: 0.55,
                        ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xAA1E3A5F)],
                    ),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: brandGold, borderRadius: BorderRadius.circular(6)),
                        child: Text('UNGGULAN', style: buttonStyle.copyWith(fontSize: 10.5, color: brandNavy)),
                      ),
                      const SizedBox(height: 8),
                      Text(featured['title'] ?? '', style: heading.copyWith(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 12, color: Colors.white70),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDate(featured['event_date'])} ${_formatMonth(featured['event_date'])} · ${featured['start_time'] ?? ''}',
                            style: caption.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.location_on_outlined, size: 12, color: Colors.white70),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              featured['location'] ?? '',
                              style: caption.copyWith(color: Colors.white70),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

            // Category chips (anti-terpotong)
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 22),
                children: _cats.map((c) {
                  final cat = c['label'] as String;
                  final icon = c['icon'] as IconData;
                  final selected = _active == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () {
                        setState(() => _active = cat);
                        _load();
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? brandNavy : surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: selected ? brandNavy : borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 14, color: selected ? brandGold : dim1),
                            const SizedBox(width: 6),
                            Text(
                              cat,
                              style: caption.copyWith(
                                color: selected ? Colors.white : dim1,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),

            if (_loading)
              const EventSkeletonList()
            else if (list.isEmpty)
              _buildEmptyCard(
                icon: Icons.event_available_outlined,
                title: hasFilter ? 'Tidak ada acara yang cocok' : 'Belum ada acara aktif',
                subtitle: hasFilter
                    ? 'Coba ubah kata kunci atau pilih kategori lain untuk melihat acara alumni.'
                    : 'Jadilah yang pertama membuat acara reuni, seminar, atau webinar untuk sesama alumni!',
                secondaryLabel: hasFilter ? 'Reset Filter' : null,
                onSecondary: hasFilter
                    ? () {
                        _searchCtrl.clear();
                        setState(() {
                          _active = 'Semua';
                          _searchQuery = '';
                        });
                        _load();
                      }
                    : null,
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: list.asMap().entries.map((e) {
                    final i = e.key;
                    final ev = e.value;
                    final id = ev['id']?.toString() ?? '$i';
                    final isReg = _registered.contains(id);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 50,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: brandBg,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              children: [
                                Text(_formatDate(ev['event_date']), style: statStyle.copyWith(fontSize: 20)),
                                Text(_formatMonth(ev['event_date']), style: label.copyWith(color: brandNavy, fontSize: 10)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        ev['title'] ?? '',
                                        style: subTitle,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: brandGold.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        ev['category'] ?? '',
                                        style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 11),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if ((ev['start_time'] ?? '').isNotEmpty)
                                  Row(
                                    children: [
                                      Icon(Icons.access_time, size: 12, color: dim1),
                                      const SizedBox(width: 5),
                                      Text('${ev['start_time']} WIB', style: caption),
                                    ],
                                  ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Icon(Icons.location_on_outlined, size: 12, color: dim1),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        ev['location'] ?? '',
                                        style: caption,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: '${ev['attendee_count'] ?? 0}',
                                              style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                            ),
                                            TextSpan(text: ' akan hadir', style: caption),
                                          ],
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () => _toggleReg(id),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                        decoration: BoxDecoration(
                                          color: isReg ? Colors.transparent : brandNavy,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isReg ? borderColor : brandNavy),
                                        ),
                                        child: Text(
                                          isReg ? 'Terdaftar ✓' : 'Daftar',
                                          style: caption.copyWith(
                                            color: isReg ? dim1 : Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

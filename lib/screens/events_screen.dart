import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/events_service.dart';
import '../core/api/api_client.dart';
import 'create_event_screen.dart';

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});
  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  String _active = 'Semua';
  List<Map<String, dynamic>> _events = [];
  final Set<String> _registered = {};
  bool _loading = true;

  final List<String> _cats = ['Semua', 'Reuni', 'Seminar', 'Networking', 'Webinar'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await EventsService.getEvents(
        category: _active == 'Semua' ? null : _active,
      );
      if (mounted) setState(() { _events = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleReg(String id) async {
    final isReg = _registered.contains(id);
    setState(() { isReg ? _registered.remove(id) : _registered.add(id); });
    try {
      if (isReg) {
        await EventsService.unregister(id);
      } else {
        await EventsService.register(id);
      }
    } on ApiException catch (e) {
      // Revert on error (except 409 = already registered)
      if (e.statusCode != 409) {
        if (mounted) setState(() { isReg ? _registered.add(id) : _registered.remove(id); });
      }
    } catch (_) {
      if (mounted) setState(() { isReg ? _registered.add(id) : _registered.remove(id); });
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
    const months = ['JAN','FEB','MAR','APR','MEI','JUN','JUL','AGU','SEP','OKT','NOV','DES'];
    return months[dt.month - 1];
  }

  @override
  Widget build(BuildContext context) {
    final featured = _events.isNotEmpty ? _events.first : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: brandNavy,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateEventScreen()),
          );
          if (result == true) {
            _load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Buat Acara', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: brandNavy,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_events.length} acara aktif', style: caption),
                Text('Acara & Kegiatan', style: heading),
              ]),
            ),
            // Featured card
            if (featured != null)
              Container(
                margin: const EdgeInsets.fromLTRB(22, 0, 22, 20),
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: surface,
                  image: featured['cover_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(featured['cover_url']),
                        fit: BoxFit.cover, opacity: 0.5)
                    : const DecorationImage(
                        image: NetworkImage('https://images.unsplash.com/photo-1685401704618-fd8243812ef7?w=700&h=340&fit=crop'),
                        fit: BoxFit.cover, opacity: 0.5),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0x881E3A5F)],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: brandNavy, borderRadius: BorderRadius.circular(6)),
                      child: Text('UNGGULAN', style: buttonStyle.copyWith(fontSize: 11)),
                    ),
                    const SizedBox(height: 8),
                    Text(featured['title'] ?? '', style: heading.copyWith(color: Colors.white, fontSize: 18)),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Icon(Icons.access_time, size: 11, color: Colors.white70),
                      const SizedBox(width: 4),
                      Text('${_formatDate(featured['event_date'])} ${_formatMonth(featured['event_date'])} · ${featured['start_time'] ?? ''}',
                        style: caption.copyWith(color: Colors.white70)),
                      const SizedBox(width: 10),
                      const Icon(Icons.location_on_outlined, size: 11, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(child: Text(featured['location'] ?? '', style: caption.copyWith(color: Colors.white70),
                        overflow: TextOverflow.ellipsis)),
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
                    onTap: () { setState(() => _active = cat); _load(); },
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
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: brandNavy),
              ))
            else if (_events.isEmpty)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: Column(children: [
                  const Icon(Icons.event_outlined, color: Color(0x611E3A5F), size: 40),
                  const SizedBox(height: 12),
                  Text('Tidak ada acara untuk kategori ini', style: subTitle),
                ])),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: _events.asMap().entries.map((e) {
                    final i = e.key; final ev = e.value;
                    final id = ev['id']?.toString() ?? '$i';
                    final isReg = _registered.contains(id);
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(
                            width: 44,
                            child: Column(children: [
                              Text(_formatDate(ev['event_date']), style: statStyle.copyWith(fontSize: 22)),
                              Text(_formatMonth(ev['event_date']), style: label.copyWith(color: brandNavy)),
                            ]),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(ev['title'] ?? '', style: subTitle,
                                maxLines: 2, overflow: TextOverflow.ellipsis)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: card, borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text(ev['category'] ?? '', style: caption.copyWith(color: dim2)),
                              ),
                            ]),
                            const SizedBox(height: 6),
                            if ((ev['start_time'] ?? '').isNotEmpty)
                              Row(children: [
                                const Icon(Icons.access_time, size: 10, color: Color(0x611E3A5F)),
                                const SizedBox(width: 4),
                                Text('${ev['start_time']} WIB', style: caption),
                              ]),
                            const SizedBox(height: 2),
                            Row(children: [
                              const Icon(Icons.location_on_outlined, size: 10, color: Color(0x611E3A5F)),
                              const SizedBox(width: 4),
                              Expanded(child: Text(ev['location'] ?? '', style: caption,
                                overflow: TextOverflow.ellipsis)),
                            ]),
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              RichText(text: TextSpan(children: [
                                TextSpan(text: '${ev['attendee_count'] ?? 0}',
                                  style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                                TextSpan(text: ' akan hadir', style: caption),
                              ])),
                              GestureDetector(
                                onTap: () => _toggleReg(id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isReg ? Colors.transparent : brandNavy,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isReg ? borderColor : brandNavy),
                                  ),
                                  child: Text(isReg ? 'Terdaftar ✓' : 'Daftar', style: caption.copyWith(
                                    color: isReg ? dim2 : Colors.white, fontWeight: FontWeight.w600)),
                                ),
                              ),
                            ]),
                          ])),
                        ]),
                      ),
                      if (i < _events.length - 1) const Divider(height: 1, color: Color(0x1A1E3A5F)),
                    ]);
                  }).toList(),
                ),
              ),
          ]),
        ),
      ),
    ));
  }
}

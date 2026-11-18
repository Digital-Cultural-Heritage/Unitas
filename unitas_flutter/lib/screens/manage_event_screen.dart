import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/events_service.dart';
import '../widgets/avatar.dart';

class ManageEventScreen extends StatefulWidget {
  final Map<String, dynamic> event;
  const ManageEventScreen({super.key, required this.event});

  @override
  State<ManageEventScreen> createState() => _ManageEventScreenState();
}

class _ManageEventScreenState extends State<ManageEventScreen> {
  static const List<Color> _avatarColors = [
    Color(0xFF1E3A5F),
    Color(0xFF2E7D32),
    Color(0xFFC62828),
    Color(0xFFE65100),
    Color(0xFF0277BD),
    Color(0xFF6A1B9A),
  ];

  List<Map<String, dynamic>> _attendees = [];
  bool _loading = true;
  bool _deleting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final eventId = widget.event['id']?.toString().trim() ?? '';
    if (eventId.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'ID acara tidak valid';
        });
      }
      return;
    }
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await EventsService.getAttendees(eventId);
      if (mounted) {
        setState(() {
          _attendees = data;
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat daftar peserta';
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteEvent() async {
    if (_deleting) return;
    final eventId = widget.event['id']?.toString().trim() ?? '';
    if (eventId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Acara'),
        content: const Text('Yakin ingin membatalkan dan menghapus acara ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kembali')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await EventsService.deleteEvent(eventId);
      if (mounted) Navigator.pop(context, true); // true = deleted
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menghapus acara')),
        );
      }
    }
  }

  Color _colorFor(String text) {
    final hash = text.hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        title: const Text('Kelola Acara', style: TextStyle(color: brandNavy, fontSize: 18, fontWeight: FontWeight.bold)),
        backgroundColor: surface,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: brandNavy),
        actions: [
          _deleting
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: _deleteEvent,
                ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.event['title']?.toString() ?? '', style: heading.copyWith(fontSize: 18)),
                const SizedBox(height: 8),
                Text('Status: Aktif', style: caption.copyWith(color: const Color(0xFF2E7D32), fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Text('Daftar Peserta (${_attendees.length})', style: label),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    color: brandNavy,
                    child: _error != null
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    const Icon(Icons.error_outline, size: 36, color: dim2),
                                    const SizedBox(height: 10),
                                    Text(_error!, style: caption, textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: _load,
                                      icon: const Icon(Icons.refresh, size: 16, color: brandNavy),
                                      label: Text('Coba Lagi', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : _attendees.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 64),
                                    child: Center(
                                      child: Text('Belum ada peserta yang mendaftar.', style: caption),
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _attendees.length,
                                itemBuilder: (context, index) {
                                  final att = _attendees[index];
                                  final user = att['user'] is Map ? att['user'] as Map : const {};
                                  final profile = user['user_profiles'];

                                  // Parse profile if it's a list (legacy support)
                                  Map<String, dynamic> p = {};
                                  if (profile is Map) {
                                    p = Map<String, dynamic>.from(profile);
                                  } else if (profile is List && profile.isNotEmpty && profile[0] is Map) {
                                    p = Map<String, dynamic>.from(profile[0] as Map);
                                  }

                                  final rawName = (att['attendee_name'] ?? p['full_name'])?.toString().trim() ?? '';
                                  final name = rawName.isEmpty ? 'Alumni' : rawName;
                                  final rawInit = p['initials']?.toString().trim() ?? '';
                                  final initials = rawInit.isNotEmpty ? rawInit : name[0].toUpperCase();
                                  final prodi = p['prodi']?.toString().trim() ?? '';
                                  final angk = p['angkatan']?.toString().trim() ?? '';
                                  final email = (att['attendee_email'] ?? '').toString().trim();
                                  final phone = (att['attendee_phone'] ?? '').toString().trim();
                                  final notes = (att['notes'] ?? '').toString().trim();
                                  final subParts = [
                                    [prodi, angk].where((e) => e.isNotEmpty).join(' '),
                                    if (email.isNotEmpty) email,
                                    if (phone.isNotEmpty) phone,
                                  ].where((e) => e.isNotEmpty).toList();
                                  final sub = subParts.join(' · ');

                                  return ListTile(
                                    leading: UnitasAvatar(initials: initials, color: _colorFor(name), size: 40),
                                    title: Text(name, style: subTitle),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (sub.isNotEmpty) Text(sub, style: caption),
                                        if (notes.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Catatan: $notes',
                                              style: caption.copyWith(color: brandNavy),
                                            ),
                                          ),
                                      ],
                                    ),
                                    tileColor: surface,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                                  );
                                },
                              ),
                  ),
          ),
        ],
      ),
    );
  }
}
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
  List<Map<String, dynamic>> _attendees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await EventsService.getAttendees(widget.event['id']);
      if (mounted) setState(() { _attendees = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteEvent() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hapus Acara'),
        content: const Text('Yakin ingin membatalkan dan menghapus acara ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Kembali')),
          TextButton(
            onPressed: () => Navigator.pop(c, true), 
            child: const Text('Hapus', style: TextStyle(color: Colors.red))
          ),
        ],
      )
    );
    if (confirm != true) return;

    try {
      await EventsService.deleteEvent(widget.event['id']);
      if (mounted) Navigator.pop(context, true); // true = deleted
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menghapus acara')));
    }
  }

  Color _colorFor(String text) {
    final colors = [
      const Color(0xFF1E3A5F), const Color(0xFF2E7D32),
      const Color(0xFFC62828), const Color(0xFFE65100),
      const Color(0xFF0277BD), const Color(0xFF6A1B9A),
    ];
    final hash = text.hashCode.abs();
    return colors[hash % colors.length];
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
          IconButton(
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
                Text(widget.event['title'] ?? '', style: heading.copyWith(fontSize: 18)),
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
              : _attendees.isEmpty
                  ? Center(child: Text('Belum ada peserta yang mendaftar.', style: caption))
                  : ListView.builder(
                      itemCount: _attendees.length,
                      itemBuilder: (context, index) {
                        final att = _attendees[index];
                        final user = att['user'] ?? {};
                        final profile = user['user_profiles'] ?? {};
                        
                        // Parse profile if it's a list (legacy support)
                        Map<String, dynamic> p = {};
                        if (profile is Map) {
                          p = Map<String, dynamic>.from(profile);
                        } else if (profile is List && profile.isNotEmpty) {
                          p = Map<String, dynamic>.from(profile[0]);
                        }

                        final name = p['full_name'] ?? 'Alumni';
                        final initials = p['initials'] ?? '?';
                        final prodi = p['prodi'] ?? '';
                        final angk = p['angkatan'] ?? '';
                        
                        return ListTile(
                          leading: UnitasAvatar(initials: initials, color: _colorFor(name), size: 40),
                          title: Text(name, style: subTitle),
                          subtitle: Text('$prodi $angk', style: caption),
                          tileColor: surface,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
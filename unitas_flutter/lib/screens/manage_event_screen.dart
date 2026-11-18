import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/events_service.dart';
import '../core/api/posts_service.dart';
import '../core/utils/image_validator.dart';
import '../widgets/avatar.dart';
import 'alumni_profile_screen.dart';

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

  late Map<String, dynamic> _event;
  List<Map<String, dynamic>> _attendees = [];
  bool _loading = true;
  bool _deleting = false;
  bool _updated = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _event = Map<String, dynamic>.from(widget.event);
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

  Future<void> _openEditSheet() async {
    final eventId = _event['id']?.toString().trim() ?? '';
    if (eventId.isEmpty) return;

    final titleCtrl = TextEditingController(text: (_event['title'] ?? '').toString());
    final locCtrl = TextEditingController(text: (_event['location'] ?? '').toString());
    final startCtrl = TextEditingController(text: (_event['start_time'] ?? '').toString());
    final endCtrl = TextEditingController(text: (_event['end_time'] ?? '').toString());
    final descCtrl = TextEditingController(text: (_event['description'] ?? '').toString());

    const categories = ['Seminar', 'Workshop', 'Reuni', 'Networking', 'Karier', 'Lainnya'];
    String category = (_event['category'] ?? 'Seminar').toString();
    if (!categories.contains(category)) category = 'Lainnya';

    DateTime selectedDate = DateTime.tryParse((_event['event_date'] ?? '').toString()) ?? DateTime.now();
    bool isOnline = _event['is_online'] == true;
    String? coverUrl = _event['cover_url']?.toString().trim();
    if (coverUrl != null && coverUrl.isEmpty) coverUrl = null;
    Uint8List? newBannerBytes;
    bool saving = false;
    String? errMsg;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: dim3, borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Text('Edit Acara', style: heading.copyWith(fontSize: 18))),
                      IconButton(
                        onPressed: saving ? null : () => Navigator.pop(sheetCtx, false),
                        icon: const Icon(Icons.close, size: 20, color: dim1),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Pamflet / Banner
                  Text('Pamflet / Banner Acara', style: label),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: saving
                        ? null
                        : () async {
                            try {
                              final picked = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                imageQuality: 90,
                              );
                              if (picked == null) return;
                              final bytes = await picked.readAsBytes();
                              ImageValidator.validate(bytes, picked.name);
                              setSheet(() {
                                newBannerBytes = bytes;
                                errMsg = null;
                              });
                            } on ImageValidationException catch (e) {
                              setSheet(() => errMsg = e.message);
                            } catch (_) {
                              setSheet(() => errMsg = 'Gagal memilih pamflet');
                            }
                          },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      child: (newBannerBytes != null || coverUrl != null)
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: newBannerBytes != null
                                      ? Image.memory(newBannerBytes!, fit: BoxFit.contain)
                                      : Image.network(coverUrl!, fit: BoxFit.contain),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: IconButton.filled(
                                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                                    icon: const Icon(Icons.close, color: Colors.white, size: 16),
                                    onPressed: saving
                                        ? null
                                        : () => setSheet(() {
                                              newBannerBytes = null;
                                              coverUrl = null;
                                            }),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.add_photo_alternate_outlined, color: brandNavy, size: 24),
                                const SizedBox(height: 6),
                                Text('Pilih Pamflet / Banner Baru', style: caption.copyWith(color: brandNavy)),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Text('Judul Acara *', style: label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: titleCtrl,
                    enabled: !saving,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 12),

                  Text('Kategori', style: label),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories.map((c) {
                      final sel = c == category;
                      return ChoiceChip(
                        label: Text(c),
                        selected: sel,
                        selectedColor: brandNavy,
                        labelStyle: caption.copyWith(color: sel ? Colors.white : textPrimary),
                        onSelected: saving ? null : (_) => setSheet(() => category = c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),

                  Text('Tanggal Acara', style: label),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: saving
                        ? null
                        : () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setSheet(() => selectedDate = picked);
                          },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 16, color: brandNavy),
                          const SizedBox(width: 8),
                          Text(
                            '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}',
                            style: body.copyWith(color: textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Jam Mulai',
                            hintText: '09:00',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: endCtrl,
                          enabled: !saving,
                          decoration: const InputDecoration(
                            labelText: 'Jam Selesai',
                            hintText: '12:00',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  Text('Lokasi / Link Meeting *', style: label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: locCtrl,
                    enabled: !saving,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: brandNavy,
                    title: Text('Acara Online (Zoom / Meet)', style: subTitle.copyWith(fontSize: 13.5)),
                    value: isOnline,
                    onChanged: saving ? null : (v) => setSheet(() => isOnline = v),
                  ),
                  const SizedBox(height: 6),

                  Text('Deskripsi', style: label),
                  const SizedBox(height: 6),
                  TextField(
                    controller: descCtrl,
                    enabled: !saving,
                    maxLines: 3,
                    decoration: const InputDecoration(border: OutlineInputBorder()),
                  ),

                  if (errMsg != null) ...[
                    const SizedBox(height: 10),
                    Text(errMsg!, style: caption.copyWith(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: saving
                          ? null
                          : () async {
                              if (titleCtrl.text.trim().isEmpty || locCtrl.text.trim().isEmpty) {
                                setSheet(() => errMsg = 'Judul dan lokasi wajib diisi');
                                return;
                              }
                              setSheet(() {
                                saving = true;
                                errMsg = null;
                              });
                              try {
                                String? finalCover = coverUrl;
                                if (newBannerBytes != null) {
                                  finalCover = await PostsService.uploadImage(newBannerBytes!, 'banner.png');
                                }
                                final isoDate =
                                    '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';
                                final payload = <String, dynamic>{
                                  'title': titleCtrl.text.trim(),
                                  'category': category,
                                  'event_date': isoDate,
                                  'start_time': startCtrl.text.trim(),
                                  'end_time': endCtrl.text.trim(),
                                  'location': locCtrl.text.trim(),
                                  'is_online': isOnline,
                                  'description': descCtrl.text.trim(),
                                  'cover_url': finalCover ?? '',
                                };
                                await EventsService.updateEvent(eventId, payload);
                                _event = {..._event, ...payload, 'cover_url': finalCover};
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx, true);
                              } catch (e) {
                                setSheet(() {
                                  saving = false;
                                  errMsg = e.toString().replaceFirst('Exception: ', '');
                                });
                              }
                            },
                      child: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Simpan Perubahan', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (saved == true && mounted) {
      setState(() => _updated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acara berhasil diperbarui')),
      );
    }
  }

  Color _colorFor(String text) {
    final hash = text.hashCode.abs();
    return _avatarColors[hash % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _updated);
      },
      child: Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        title: Text('Kelola Acara', style: heading.copyWith(fontSize: 18)),
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        iconTheme: const IconThemeData(color: brandNavy),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: brandNavy),
            tooltip: 'Edit Acara',
            onPressed: _deleting ? null : _openEditSheet,
          ),
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
                  tooltip: 'Hapus Acara',
                  onPressed: _deleteEvent,
                ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEventSummaryCard(),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
            child: Row(
              children: [
                Text('Daftar Peserta (${_attendees.length})', style: label),
              ],
            ),
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
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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

                                  final userId = (user['id'] ?? '').toString();
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

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(14),
                                      onTap: userId.isEmpty
                                          ? null
                                          : () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => AlumniProfileScreen(
                                                    userId: userId,
                                                    initialProfile: {...p, 'user_id': userId},
                                                  ),
                                                ),
                                              );
                                            },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        child: Row(
                                          children: [
                                            UnitasAvatar(
                                              initials: initials,
                                              color: _colorFor(name),
                                              size: 42,
                                              avatarUrl: p['avatar_url']?.toString(),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(name, style: subTitle.copyWith(fontSize: 14.5)),
                                                  if (sub.isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(sub, style: caption),
                                                  ],
                                                  if (notes.isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Text(
                                                      'Catatan: $notes',
                                                      style: caption.copyWith(color: brandNavy),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (email.isNotEmpty)
                                              IconButton(
                                                icon: const Icon(Icons.copy, size: 17, color: dim1),
                                                tooltip: 'Salin email peserta',
                                                onPressed: () {
                                                  Clipboard.setData(ClipboardData(text: email));
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Email $email disalin')),
                                                  );
                                                },
                                              )
                                            else
                                              const Icon(Icons.chevron_right, size: 18, color: dim2),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
          ),
        ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildEventSummaryCard() {
    final coverUrl = (_event['cover_url'] ?? '').toString().trim();
    final title = (_event['title'] ?? 'Acara Alumni').toString();
    final category = (_event['category'] ?? 'Acara').toString();
    final date = (_event['event_date'] ?? '').toString();
    final startTime = (_event['start_time'] ?? '').toString().trim();
    final loc = (_event['location'] ?? '').toString().trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (coverUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    coverUrl,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: brandGreen.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '● Aktif',
                            style: label.copyWith(color: brandGreen, fontSize: 10.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: brandGold.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            category,
                            style: label.copyWith(color: brandNavy, fontSize: 10.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(title, style: heading.copyWith(fontSize: 18)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            [date, if (startTime.isNotEmpty) startTime, loc].where((s) => s.isNotEmpty).join(' · '),
            style: caption,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleting ? null : _openEditSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: brandNavy,
                side: const BorderSide(color: borderColor),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Detail & Pamflet Acara'),
            ),
          ),
        ],
      ),
    );
  }
}
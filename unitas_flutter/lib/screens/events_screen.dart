import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/events_service.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_service.dart';
import '../core/api/users_service.dart';
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
  final Set<String> _toggling = {};
  bool _loading = true;
  bool _loadingMyEvents = true;
  String? _error;
  String? _myEventsError;
  int _loadReqId = 0;
  int _myEventsReqId = 0;

  static const List<Map<String, dynamic>> _cats = [
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
    final reqId = ++_loadReqId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await EventsService.getEvents(
        category: _active == 'Semua' ? null : _active,
      );
      if (!mounted || reqId != _loadReqId) return;
      setState(() {
        _events = data;
        _error = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || reqId != _loadReqId) return;
      setState(() {
        _error = 'Gagal memuat daftar acara';
        _loading = false;
      });
    }
  }

  Future<void> _loadMyEvents() async {
    final reqId = ++_myEventsReqId;
    setState(() {
      _loadingMyEvents = true;
      _myEventsError = null;
    });
    try {
      final data = await EventsService.getMyEvents();
      if (!mounted || reqId != _myEventsReqId) return;
      setState(() {
        _myEvents = data;
        _myEventsError = null;
        _loadingMyEvents = false;
      });
    } catch (_) {
      if (!mounted || reqId != _myEventsReqId) return;
      setState(() {
        _myEventsError = 'Gagal memuat acara saya';
        _loadingMyEvents = false;
      });
    }
  }

  Future<void> _openCreateEvent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventScreen()),
    );
    if (result == true && mounted) {
      _load();
      _loadMyEvents();
    }
  }

  Future<void> _handleRegisterTap(Map<String, dynamic> ev) async {
    final id = ev['id']?.toString() ?? '';
    if (id.isEmpty || _toggling.contains(id)) return;
    final isReg = _registered.contains(id);

    if (isReg) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Batalkan Pendaftaran'),
          content: Text('Yakin ingin membatalkan pendaftaran untuk "${ev['title'] ?? 'acara ini'}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tetap Terdaftar')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Batalkan', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      if (confirm != true) return;

      _toggling.add(id);
      setState(() => _registered.remove(id));
      try {
        await EventsService.unregister(id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pendaftaran acara dibatalkan')),
          );
          _load();
        }
      } on ApiException catch (e) {
        if (mounted) {
          setState(() => _registered.add(id));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      } catch (_) {
        if (mounted) {
          setState(() => _registered.add(id));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal membatalkan pendaftaran')),
          );
        }
      } finally {
        _toggling.remove(id);
      }
      return;
    }

    await _openRegisterSheet(ev);
  }

  Future<void> _openRegisterSheet(Map<String, dynamic> ev) async {
    final id = ev['id']?.toString() ?? '';
    final title = (ev['title'] ?? 'Acara Alumni').toString();
    final category = (ev['category'] ?? 'Acara').toString();
    final dateStr = _formatDate(ev['event_date']);
    final loc = (ev['location'] ?? '').toString();

    final stored = await AuthService.getStoredUser();
    Map<String, dynamic>? me;
    try {
      me = await UsersService.getMe();
    } catch (_) {}

    if (!mounted) return;

    final nameCtrl = TextEditingController(
      text: (me?['full_name'] ?? stored?['full_name'] ?? '').toString(),
    );
    final emailCtrl = TextEditingController(
      text: (me?['email'] ?? stored?['email'] ?? '').toString(),
    );
    final phoneCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool submitting = false;
    String? errorMsg;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              16,
              22,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category.toUpperCase(), style: label.copyWith(color: brandNavy)),
                          const SizedBox(height: 3),
                          Text('Daftar: $title', style: heading.copyWith(fontSize: 18)),
                          const SizedBox(height: 3),
                          Text(
                            [dateStr, loc].where((s) => s.isNotEmpty).join(' · '),
                            style: caption.copyWith(color: dim1),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: const Icon(Icons.close, size: 20, color: dim1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                Text('Nama Lengkap *', style: label),
                const SizedBox(height: 6),
                TextField(
                  controller: nameCtrl,
                  enabled: !submitting,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Masukkan nama lengkap untuk sertifikat/absensi',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Email *', style: label),
                const SizedBox(height: 6),
                TextField(
                  controller: emailCtrl,
                  enabled: !submitting,
                  keyboardType: TextInputType.emailAddress,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Email untuk info link acara / e-sertifikat',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                Text('No. WhatsApp (opsional)', style: label),
                const SizedBox(height: 6),
                TextField(
                  controller: phoneCtrl,
                  enabled: !submitting,
                  keyboardType: TextInputType.phone,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Contoh: 081234567890',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Catatan / Pertanyaan (opsional)', style: label),
                const SizedBox(height: 6),
                TextField(
                  controller: notesCtrl,
                  enabled: !submitting,
                  maxLines: 2,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Pertanyaan untuk pembicara atau catatan kehadiran…',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),

                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(errorMsg!, style: caption.copyWith(color: const Color(0xFFDC2626))),
                ],

                const SizedBox(height: 18),
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
                    onPressed: submitting
                        ? null
                        : () async {
                            final nama = nameCtrl.text.trim();
                            final email = emailCtrl.text.trim();
                            if (nama.isEmpty) {
                              setSheet(() => errorMsg = 'Nama lengkap wajib diisi');
                              return;
                            }
                            if (email.isEmpty || !email.contains('@')) {
                              setSheet(() => errorMsg = 'Masukkan email yang valid');
                              return;
                            }
                            setSheet(() {
                              submitting = true;
                              errorMsg = null;
                            });
                            try {
                              await EventsService.register(
                                id,
                                attendeeName: nama,
                                attendeeEmail: email,
                                attendeePhone: phoneCtrl.text.trim(),
                                notes: notesCtrl.text.trim(),
                              );
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (mounted) {
                                setState(() => _registered.add(id));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Berhasil mendaftar di "$title"!')),
                                );
                                _load();
                              }
                            } on ApiException catch (e) {
                              if (e.statusCode == 409) {
                                if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                                if (mounted) setState(() => _registered.add(id));
                              } else {
                                setSheet(() {
                                  submitting = false;
                                  errorMsg = e.message;
                                });
                              }
                            } catch (_) {
                              setSheet(() {
                                submitting = false;
                                errorMsg = 'Gagal mendaftar acara. Coba lagi.';
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Konfirmasi Pendaftaran', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(dynamic iso) {
    final s = iso?.toString().trim();
    if (s == null || s.isEmpty) return '—';
    final dt = DateTime.tryParse(s);
    if (dt == null) return s;
    return dt.day.toString();
  }

  String _formatMonth(dynamic iso) {
    final s = iso?.toString().trim();
    if (s == null || s.isEmpty) return '';
    final dt = DateTime.tryParse(s);
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

  Widget _buildErrorCard(String message, VoidCallback onRetry) {
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
          const Icon(Icons.error_outline, color: dim2, size: 36),
          const SizedBox(height: 12),
          Text(message, style: subTitle.copyWith(fontSize: 15), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: brandNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 17),
            label: Text('Coba Lagi', style: buttonStyle),
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
          : _myEventsError != null
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(top: 32, bottom: 90),
                  children: [_buildErrorCard(_myEventsError!, _loadMyEvents)],
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
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(22, 16, 22, 90),
                      itemCount: _myEvents.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text('ACARA YANG KAMU KELOLA', style: label),
                          );
                        }
                        final ev = _myEvents[index - 1];
                        final category = (ev['category'] ?? 'Acara').toString();
                        final loc = (ev['location'] ?? '').toString().trim();
                        final startTime = (ev['start_time'] ?? '').toString().trim();
                        final meta = [if (startTime.isNotEmpty) startTime, if (loc.isNotEmpty) loc].join(' · ');
                        final evDate = DateTime.tryParse((ev['event_date'] ?? '').toString());
                        final today = DateTime.now();
                        final isPast = evDate != null &&
                            evDate.isBefore(DateTime(today.year, today.month, today.day));

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              final deleted = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ManageEventScreen(event: ev)),
                              );
                              if (deleted == true && mounted) {
                                _load();
                                _loadMyEvents();
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 52,
                                    height: 54,
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
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: (isPast ? dim2 : brandGreen).withValues(alpha: 0.14),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                isPast ? 'Selesai' : '● Aktif',
                                                style: label.copyWith(
                                                  color: isPast ? dim1 : brandGreen,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: brandGold.withValues(alpha: 0.18),
                                                borderRadius: BorderRadius.circular(99),
                                              ),
                                              child: Text(
                                                category,
                                                style: label.copyWith(color: brandNavy, fontSize: 10),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          ev['title']?.toString() ?? '',
                                          style: subTitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (meta.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            meta,
                                            style: caption.copyWith(fontSize: 11.5),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        const SizedBox(height: 4),
                                        Text(
                                          '${ev['attendee_count'] ?? 0} pendaftar',
                                          style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: brandNavy.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Kelola',
                                          style: caption.copyWith(
                                            color: brandNavy,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(Icons.chevron_right, size: 15, color: brandNavy),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> ev, int index) {
    final id = ev['id']?.toString() ?? '$index';
    final isReg = _registered.contains(id);
    final startTime = ev['start_time']?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _openEventDetailSheet(ev),
        borderRadius: BorderRadius.circular(14),
        child: Container(
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
                        ev['title']?.toString() ?? '',
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
                        ev['category']?.toString() ?? '',
                        style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600, fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (startTime.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: dim1),
                      const SizedBox(width: 5),
                      Text('$startTime WIB', style: caption),
                    ],
                  ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.location_on_outlined, size: 12, color: dim1),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        ev['location']?.toString() ?? '',
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
                      onTap: () => _handleRegisterTap(ev),
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
        ),
      ),
    );
  }

  Widget _buildAllEvents() {
    final list = _filteredEvents;
    final featured = list.isNotEmpty ? list.first : null;
    final hasFilter = _active != 'Semua' || _searchQuery.trim().isNotEmpty;
    final coverUrlRaw = featured?['cover_url']?.toString().trim() ?? '';
    final coverUrl = coverUrlRaw.isNotEmpty
        ? coverUrlRaw
        : 'https://images.unsplash.com/photo-1685401704618-fd8243812ef7?w=700&h=340&fit=crop';
    final coverCacheW = (600 * MediaQuery.devicePixelRatioOf(context)).round().clamp(600, 1200);

    return RefreshIndicator(
      onRefresh: _load,
      color: brandNavy,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                    child: InkWell(
                      onTap: () => _openEventDetailSheet(featured),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        height: 170,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: surface,
                        ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            cacheWidth: coverCacheW,
                            opacity: const AlwaysStoppedAnimation(0.55),
                            errorBuilder: (_, _, _) => Container(color: brandNavy),
                          ),
                          Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
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
                                Text(
                                  featured['title']?.toString() ?? '',
                                  style: heading.copyWith(color: Colors.white, fontSize: 18),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time, size: 12, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${_formatDate(featured['event_date'])} ${_formatMonth(featured['event_date'])} · ${featured['start_time']?.toString() ?? ''}',
                                      style: caption.copyWith(color: Colors.white70),
                                    ),
                                    const SizedBox(width: 10),
                                    const Icon(Icons.location_on_outlined, size: 12, color: Colors.white70),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        featured['location']?.toString() ?? '',
                                        style: caption.copyWith(color: Colors.white70),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
                            if (_active == cat) return;
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
              ],
            ),
          ),
          if (_loading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(bottom: 90),
                child: EventSkeletonList(),
              ),
            )
          else if (_error != null && _events.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 90),
                child: _buildErrorCard(_error!, _load),
              ),
            )
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 90),
                child: _buildEmptyCard(
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
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 90),
              sliver: SliverList.builder(
                itemCount: list.length,
                itemBuilder: (context, index) => _buildEventCard(list[index], index),
              ),
            ),
        ],
      ),
    );
  }

  void _openPamphletViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Stack(
        children: [
          Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4.0,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: 16,
            right: 16,
            child: SafeArea(
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openEventDetailSheet(Map<String, dynamic> ev) {
    final id = ev['id']?.toString() ?? '';
    final isReg = _registered.contains(id);
    final coverUrl = ev['cover_url']?.toString().trim() ?? '';
    final title = (ev['title'] ?? 'Acara Alumni').toString();
    final category = (ev['category'] ?? 'Acara').toString();
    final desc = (ev['description'] ?? '').toString().trim();
    final loc = (ev['location'] ?? '').toString().trim();
    final isOnline = ev['is_online'] == true;
    final startTime = (ev['start_time'] ?? '').toString().trim();
    final endTime = (ev['end_time'] ?? '').toString().trim();
    final timeStr = [startTime, endTime].where((s) => s.isNotEmpty).join(' – ');
    final dateStr = '${_formatDate(ev['event_date'])} ${_formatMonth(ev['event_date'])}';
    final count = ev['attendee_count']?.toString() ?? '0';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 24),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: brandGold.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              category.toUpperCase(),
                              style: label.copyWith(color: brandNavy, fontSize: 10.5),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(title, style: heading.copyWith(fontSize: 20)),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: const Icon(Icons.close, size: 20, color: dim1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),

                if (coverUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => _openPamphletViewer(coverUrl),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 360),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(13),
                              child: Image.network(
                                coverUrl,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) => const SizedBox(height: 80),
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.all(10),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.zoom_in, color: Colors.white, size: 15),
                                const SizedBox(width: 4),
                                Text(
                                  'Tap untuk perbesar',
                                  style: caption.copyWith(color: Colors.white, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 16, color: brandNavy),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              timeStr.isNotEmpty ? '$dateStr · $timeStr' : dateStr,
                              style: body.copyWith(color: textPrimary, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                            size: 16,
                            color: brandNavy,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              isOnline ? '$loc (Online)' : loc,
                              style: body.copyWith(color: textPrimary, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          const Icon(Icons.people_outline, size: 16, color: brandNavy),
                          const SizedBox(width: 10),
                          Text(
                            '$count alumni akan hadir',
                            style: body.copyWith(color: textPrimary, fontSize: 13.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Deskripsi Acara', style: label),
                  const SizedBox(height: 6),
                  Text(
                    desc,
                    style: body.copyWith(color: textPrimary, height: 1.5),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isReg ? surface : brandNavy,
                      foregroundColor: isReg ? dim1 : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isReg ? const BorderSide(color: borderColor) : BorderSide.none,
                      ),
                    ),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _handleRegisterTap(ev);
                    },
                    child: Text(
                      isReg ? 'Terdaftar ✓ (Ketuk untuk kelola)' : 'Daftar Acara',
                      style: const TextStyle(fontWeight: FontWeight.bold),
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
}

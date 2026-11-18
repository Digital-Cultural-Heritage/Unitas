import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/jobs_service.dart';
import '../core/utils/pdf_picker.dart';
import '../widgets/avatar.dart';
import '../widgets/skeleton.dart';
import 'chat_room_screen.dart';
import 'create_job_screen.dart';
import 'manage_job_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _filter = 'Semua';
  String _searchQuery = '';
  String? _myUserId;
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _jobs = [];
  final Set<String> _savedIds = {};
  final Map<String, String> _appliedStatusByJobId = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _page = 1;

  final List<Map<String, dynamic>> _filters = const [
    {'label': 'Semua', 'icon': Icons.apps_rounded},
    {'label': 'Full-time', 'icon': Icons.work_outline},
    {'label': 'Part-time', 'icon': Icons.schedule_outlined},
    {'label': 'Magang', 'icon': Icons.school_outlined},
    {'label': 'Remote', 'icon': Icons.laptop_mac_outlined},
    {'label': 'Tersimpan', 'icon': Icons.bookmark_outline},
    {'label': 'Lamaran Saya', 'icon': Icons.assignment_turned_in_outlined},
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _initUser();
    _load();
    _loadSavedIds();
  }

  Future<void> _initUser() async {
    final user = await AuthService.getStoredUser();
    if (mounted && user != null) {
      setState(() => _myUserId = user['id']?.toString());
    }
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 250) {
      _loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Muat id lowongan yang sudah disimpan supaya ikon bookmark akurat di semua filter.
  Future<void> _loadSavedIds() async {
    try {
      final saved = await JobsService.getSavedJobs();
      if (!mounted) return;
      setState(() => _savedIds.addAll(
            saved.map((j) => j['id']?.toString() ?? '').where((id) => id.isNotEmpty),
          ));
    } catch (_) {}
  }

  int _loadEpoch = 0; // abaikan respons lama saat filter berganti cepat
  bool _error = false;
  int _autoFillPages = 0;

  bool _matchesTypeFilter(Map<String, dynamic> job) {
    if (_filter == 'Semua' || _filter == 'Remote') return true;
    final jt = (job['job_type'] ?? '').toString();
    if (_filter == 'Magang') {
      return jt == 'Magang' || jt == 'Internship';
    }
    return jt == _filter;
  }

  Future<void> _syncAppliedStatuses() async {
    try {
      final applied = await JobsService.getAppliedJobs();
      if (!mounted) return;
      setState(() {
        _appliedStatusByJobId.clear();
        for (final j in applied) {
          final id = j['id']?.toString() ?? '';
          final st = j['application_status']?.toString() ?? 'pending';
          if (id.isNotEmpty) _appliedStatusByJobId[id] = st;
        }
      });
    } catch (_) {}
  }
  Future<void> _load() async {
    final epoch = ++_loadEpoch;
    _autoFillPages = 0;
    setState(() {
      _loading = true;
      _error = false;
      _loadingMore = false;
      _page = 1;
      _hasMore = true;
    });
    try {
      if (_filter == 'Tersimpan') {
        final results = await Future.wait([
          JobsService.getSavedJobs(),
          JobsService.getAppliedJobs().catchError((_) => <Map<String, dynamic>>[]),
        ]);
        final saved = results[0];
        final applied = results[1];
        if (mounted && epoch == _loadEpoch) {
          setState(() {
            _jobs = saved;
            _hasMore = false;
            _savedIds.addAll(saved.map((j) => j['id']?.toString() ?? '').where((id) => id.isNotEmpty));
            _appliedStatusByJobId.clear();
            for (final j in applied) {
              final id = j['id']?.toString() ?? '';
              if (id.isNotEmpty) {
                _appliedStatusByJobId[id] = j['application_status']?.toString() ?? 'pending';
              }
            }
            _loading = false;
          });
        }
      } else if (_filter == 'Lamaran Saya') {
        final applied = await JobsService.getAppliedJobs();
        if (mounted && epoch == _loadEpoch) {
          setState(() {
            _jobs = applied;
            _hasMore = false;
            _appliedStatusByJobId.clear();
            for (final j in applied) {
              final id = j['id']?.toString() ?? '';
              if (id.isNotEmpty) {
                _appliedStatusByJobId[id] = j['application_status']?.toString() ?? 'pending';
              }
            }
            _loading = false;
          });
        }
      } else {
        final isRemote = _filter == 'Remote' ? true : null;
        final results = await Future.wait([
          JobsService.getJobs(isRemote: isRemote, page: 1),
          JobsService.getAppliedJobs().catchError((_) => <Map<String, dynamic>>[]),
        ]);
        final jobs = results[0];
        final applied = results[1];
        if (mounted && epoch == _loadEpoch) {
          setState(() {
            _hasMore = jobs.length >= 20;
            _jobs = jobs.where(_matchesTypeFilter).toList();
            _appliedStatusByJobId.clear();
            for (final j in applied) {
              final id = j['id']?.toString() ?? '';
              if (id.isNotEmpty) {
                _appliedStatusByJobId[id] = j['application_status']?.toString() ?? 'pending';
              }
            }
            _loading = false;
          });
          _maybeAutoFill();
        }
      }
    } catch (_) {
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  /// Filter tipe dilakukan di klien: jika hasil terlalu sedikit untuk di-scroll,
  /// ambil halaman berikutnya (dibatasi) agar filter tidak tampak kosong.
  void _maybeAutoFill() {
    if (!_hasMore || _autoFillPages >= 4) return;
    if (_filter == 'Semua' || _filter == 'Remote' || _filter == 'Tersimpan' || _filter == 'Lamaran Saya') return;
    if (_jobs.length >= 6) return;
    _autoFillPages++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore ||
        !_hasMore ||
        _loading ||
        _filter == 'Tersimpan' ||
        _filter == 'Lamaran Saya') {
      return;
    }
    final epoch = _loadEpoch;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final isRemote = _filter == 'Remote' ? true : null;
      final more = await JobsService.getJobs(isRemote: isRemote, page: nextPage);
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          final filtered = more.where(_matchesTypeFilter).toList();
          _jobs = [..._jobs, ...filtered];
          _page = nextPage;
          _hasMore = more.length >= 20;
          _loadingMore = false;
        });
        _maybeAutoFill();
      }
    } catch (_) {
      if (mounted && epoch == _loadEpoch) setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCreateJob() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateJobScreen()),
    );
    if (result == true && mounted) {
      _load();
    }
  }

  final Set<String> _savingIds = {};

  Future<void> _toggleSave(String id) async {
    if (!_savingIds.add(id)) return; // cegah double-tap
    final wasSaved = _savedIds.contains(id);
    setState(() {
      wasSaved ? _savedIds.remove(id) : _savedIds.add(id);
    });
    try {
      await JobsService.toggleSave(id);
    } catch (_) {
      if (mounted) {
        setState(() {
          wasSaved ? _savedIds.add(id) : _savedIds.remove(id);
        });
      }
    } finally {
      _savingIds.remove(id);
    }
  }

  List<Map<String, dynamic>> get _filteredJobs {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _jobs;
    return _jobs.where((j) {
      final title = (j['title'] ?? '').toString().toLowerCase();
      final company = (j['company'] ?? '').toString().toLowerCase();
      final loc = (j['location'] ?? '').toString().toLowerCase();
      return title.contains(q) || company.contains(q) || loc.contains(q);
    }).toList();
  }

  Map<String, dynamic>? _posterProfile(Map<String, dynamic> job) {
    final poster = job['poster'];
    if (poster is! Map) return null;
    final profiles = poster['user_profiles'];
    if (profiles is List && profiles.isNotEmpty) {
      return Map<String, dynamic>.from(profiles.first as Map);
    }
    if (profiles is Map) {
      return Map<String, dynamic>.from(profiles);
    }
    return null;
  }

  String _initialsFromName(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    if (parts.isNotEmpty) return parts[0][0].toUpperCase();
    return 'A';
  }

  static const List<Color> _logoColors = [
    Color(0xFF1A5C2E),
    Color(0xFF1A5C1A),
    Color(0xFF0A2E6B),
    Color(0xFF0A3D6B),
    Color(0xFF5C1A1A),
    Color(0xFF2B4F7A),
  ];
  Color _colorFor(int i) => _logoColors[i % _logoColors.length];

  String _logoText(Map<String, dynamic> job) {
    final co = (job['company'] ?? '').toString().trim();
    if (co.isEmpty) return '?';
    return co.length >= 2 ? co.substring(0, 2).toUpperCase() : co.toUpperCase();
  }

  String _str(Map<String, dynamic> job, String key, [String fallback = '']) {
    final v = job[key];
    if (v == null) return fallback;
    final s = v.toString();
    return s.isEmpty ? fallback : s;
  }

  String _salary(Map<String, dynamic> job) {
    final min = num.tryParse('${job['salary_min'] ?? ''}');
    final max = num.tryParse('${job['salary_max'] ?? ''}');
    if (min == null && max == null) return 'Dirahasiakan';
    if (min != null && max != null) {
      return 'Rp ${(min / 1000000).toStringAsFixed(1)}–${(max / 1000000).toStringAsFixed(1)} jt';
    }
    if (min != null) return 'Rp ${(min / 1000000).toStringAsFixed(1)}+ jt';
    return '—';
  }

  String _timeAgo(String? isoDate) {
    if (isoDate == null) return '';
    final dt = DateTime.tryParse(isoDate)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} menit lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  List<String> _tags(Map<String, dynamic> job) {
    final t = job['tags'];
    if (t is List) return t.map((e) => e.toString()).toList();
    return [];
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reviewed':
        return 'Direview Alumni';
      case 'referred':
        return 'Diteruskan ke HR ✓';
      case 'rejected':
        return 'Belum Cocok';
      default:
        return 'Menunggu Review';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'reviewed':
        return const Color(0xFF1D4ED8);
      case 'referred':
        return brandGreen;
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFB45309);
    }
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        _statusLabel(status),
        style: caption.copyWith(color: color, fontWeight: FontWeight.w700, fontSize: 11.5),
      ),
    );
  }

  Future<void> _openExternalUrl(String rawUrl) async {
    final normalized = rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
        ? rawUrl
        : 'https://$rawUrl';
    final uri = Uri.tryParse(normalized);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: rawUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link disalin ke clipboard')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filteredJobs;
    final hasFilter = _filter != 'Semua' || _searchQuery.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: brandNavy,
        foregroundColor: Colors.white,
        onPressed: _openCreateJob,
        icon: const Icon(Icons.add),
        label: const Text('Pasang Lowongan', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: RefreshIndicator(
              onRefresh: _load,
              color: brandNavy,
              child: CustomScrollView(
                controller: _scrollCtrl,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Eksklusif untuk Alumni',
                                  style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text('Bursa Karier', style: heading, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            children: [
                              InkWell(
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const ManageJobScreen()),
                                  );
                                   if (mounted) _load();
                                 },
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.tune, size: 15, color: brandNavy),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Kelola',
                                        style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
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
                                    const Icon(Icons.business_center_outlined, size: 15, color: brandNavy),
                                    const SizedBox(width: 5),
                                    Text(
                                      '${list.length} Lowongan',
                                      style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Search Bar
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
                          hintText: 'Cari posisi, perusahaan, atau lokasi…',
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

                    // Filters
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        children: _filters.map((item) {
                          final f = item['label'] as String;
                          final icon = item['icon'] as IconData;
                          final selected = _filter == f;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: InkWell(
                              onTap: () {
                                setState(() => _filter = f);
                                _load();
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
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
                                      f,
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
                    const SizedBox(height: 18),
                  ],
                ),
                  ),

                  // Content
                  if (_loading || _error || list.isEmpty)
                    SliverToBoxAdapter(
                      child: _loading
                      ? const JobSkeletonList()
                      : _error
                      ? _errorBox()
                      : Container(
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
                              child: Icon(
                                _filter == 'Lamaran Saya'
                                    ? Icons.assignment_turned_in_outlined
                                    : Icons.work_outline,
                                color: brandNavy,
                                size: 30,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _filter == 'Lamaran Saya'
                                  ? 'Belum ada lamaran dikirim'
                                  : (hasFilter ? 'Tidak ada lowongan yang cocok' : 'Belum ada lowongan tersedia'),
                              style: subTitle.copyWith(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _filter == 'Lamaran Saya'
                                  ? 'Kirim lamaran dengan CV PDF ke lowongan dari alumni untuk melacak statusnya di sini.'
                                  : (hasFilter
                                      ? 'Coba ubah kata kunci pencarian atau pilih tipe pekerjaan lainnya.'
                                      : 'Bagikan info lowongan kerja atau magang dari perusahaanmu untuk sesama alumni!'),
                              style: caption.copyWith(color: dim1, height: 1.45),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              alignment: WrapAlignment.center,
                              children: [
                                if (_filter != 'Lamaran Saya')
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: brandNavy,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      elevation: 0,
                                    ),
                                    onPressed: _openCreateJob,
                                    icon: const Icon(Icons.add, size: 17),
                                    label: Text('Pasang Lowongan', style: buttonStyle),
                                  ),
                                if (hasFilter)
                                  OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: brandNavy,
                                      side: BorderSide(color: borderColor),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {
                                        _filter = 'Semua';
                                        _searchQuery = '';
                                      });
                                      _load();
                                    },
                                    child: Text(
                                      'Lihat Semua Lowongan',
                                      style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      sliver: SliverList.builder(
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                            final job = list[i];
                            final id = job['id']?.toString() ?? '$i';
                            final isSaved = _savedIds.contains(id);
                            final tags = _tags(job);
                            final jobType = _str(job, 'job_type', 'Full-time');
                            final posterProf = _posterProfile(job);
                            final posterName = (posterProf?['full_name'] ?? '').toString().trim();
                            final posterProdi = (posterProf?['prodi'] ?? '').toString().trim();
                            final posterAngkatan = (posterProf?['angkatan'] ?? '').toString().trim();
                            final isOwner = _myUserId != null &&
                                job['poster_id']?.toString() == _myUserId;
                            final appStatus = _appliedStatusByJobId[id] ??
                                job['application_status']?.toString();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: surface,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: borderColor),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: InkWell(
                                onTap: () => _showJobDetailSheet(job, posterProf),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: _colorFor(i),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            alignment: Alignment.center,
                                            child: Text(
                                              _logoText(job),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 14),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _str(job, 'title', '—'),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: subTitle.copyWith(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: brandNavy,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _str(job, 'company'),
                                                  style: body.copyWith(fontWeight: FontWeight.w500, color: dim1),
                                                ),
                                              ],
                                            ),
                                          ),
                                          InkWell(
                                            onTap: () => _toggleSave(id),
                                            borderRadius: BorderRadius.circular(8),
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                isSaved ? Icons.bookmark : Icons.bookmark_border,
                                                color: isSaved ? brandNavy : dim2,
                                                size: 24,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (posterName.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            const Icon(Icons.verified_user_outlined, size: 13, color: brandNavy),
                                            const SizedBox(width: 5),
                                            Expanded(
                                              child: Text(
                                                'Info dari $posterName${posterProdi.isNotEmpty || posterAngkatan.isNotEmpty ? " · ${[posterProdi, posterAngkatan].where((x) => x.isNotEmpty).join(" '")}" : ""}',
                                                style: caption.copyWith(
                                                  color: brandNavy,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _infoChip(Icons.location_on_outlined, _str(job, 'location', 'Lokasi tidak disebutkan')),
                                          _infoChip(Icons.work_outline, jobType),
                                          _infoChip(Icons.attach_money, _salary(job)),
                                        ],
                                      ),
                                      if (tags.isNotEmpty) ...[
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: tags
                                              .map(
                                                (tag) => Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: card,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    tag,
                                                    style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ],
                                      const SizedBox(height: 14),
                                      const Divider(height: 1, color: Color(0x1A1E3A5F)),
                                      const SizedBox(height: 12),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              _filter == 'Lamaran Saya' && job['applied_at'] != null
                                                  ? 'Dilamar ${_timeAgo(job['applied_at']?.toString())}'
                                                  : _timeAgo(job['created_at']?.toString()),
                                              style: caption.copyWith(color: dim2),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (isOwner)
                                            OutlinedButton(
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: brandNavy,
                                                side: BorderSide(color: borderColor),
                                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              onPressed: () async {
                                                await Navigator.push(
                                                  context,
                                                  MaterialPageRoute(builder: (_) => const ManageJobScreen()),
                                                );
                                                _load();
                                              },
                                              child: const Text('Kelola Loker', style: TextStyle(fontWeight: FontWeight.w600)),
                                            )
                                          else if (appStatus != null)
                                            _statusBadge(appStatus)
                                          else
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: brandNavy,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                elevation: 0,
                                              ),
                                              onPressed: () => _showApplySheet(job),
                                              child: const Text('Lamar Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                        },
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 100),
                      child: _loadingMore
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                          : const SizedBox.shrink(),
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

  Widget _errorBox() {
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
          Icon(Icons.wifi_off_rounded, color: dim2, size: 36),
          const SizedBox(height: 12),
          Text('Gagal memuat lowongan', style: subTitle.copyWith(fontSize: 16)),
          const SizedBox(height: 6),
          Text('Periksa koneksi internetmu lalu coba lagi.', style: caption.copyWith(color: dim1)),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: _load, child: const Text('Coba lagi')),
        ],
      ),
    );
  }

  void _showJobDetailSheet(Map<String, dynamic> job, Map<String, dynamic>? posterProf) {
    final id = job['id']?.toString() ?? '';
    final title = job['title']?.toString() ?? 'Lowongan';
    final company = job['company']?.toString() ?? '';
    final location = job['location']?.toString() ?? '';
    final jobType = job['job_type']?.toString() ?? 'Full-time';
    final desc = job['description']?.toString().trim() ?? '';
    final applyUrl = job['apply_url']?.toString().trim() ?? '';
    final contactEmail = job['contact_email']?.toString().trim() ?? '';
    final posterId = job['poster_id']?.toString() ?? '';
    final posterName = (posterProf?['full_name'] ?? 'Alumni Unitas').toString();
    final posterAvatar = posterProf?['avatar_url']?.toString();
    final posterJob = [posterProf?['pekerjaan'], posterProf?['perusahaan']]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' · ');
    final isOwner = _myUserId != null && posterId == _myUserId;
    final appStatus = _appliedStatusByJobId[id] ?? job['application_status']?.toString();
    final cvUrl = job['cv_url']?.toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 24),
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
                Text(title, style: heading.copyWith(fontSize: 20)),
                const SizedBox(height: 4),
                Text(company, style: subTitle.copyWith(color: dim1)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _infoChip(Icons.location_on_outlined, location),
                    _infoChip(Icons.work_outline, jobType),
                    _infoChip(Icons.attach_money, _salary(job)),
                  ],
                ),
                if (posterId.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        UnitasAvatar(
                          initials: _initialsFromName(posterName),
                          color: brandNavy,
                          size: 42,
                          avatarUrl: posterAvatar,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dibagikan oleh Alumni', style: caption.copyWith(fontSize: 11)),
                              Text(posterName, style: subTitle.copyWith(fontSize: 14)),
                              if (posterJob.isNotEmpty)
                                Text(posterJob, style: caption, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                        if (!isOwner)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: brandNavy,
                              side: BorderSide(color: borderColor),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatRoomScreen(
                                    peerId: posterId,
                                    peerName: posterName,
                                    peerInitials: _initialsFromName(posterName),
                                    peerAvatarUrl: posterAvatar,
                                    peerSubtitle: posterJob.isNotEmpty ? posterJob : company,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 15),
                            label: const Text('Tanya'),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Text('Deskripsi Pekerjaan', style: label),
                const SizedBox(height: 6),
                Text(
                  desc.isNotEmpty ? desc : 'Tidak ada deskripsi tambahan.',
                  style: body.copyWith(height: 1.55, color: desc.isEmpty ? dim2 : textPrimary),
                ),
                if (applyUrl.isNotEmpty || contactEmail.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Jalur Eksternal Perusahaan', style: label),
                  const SizedBox(height: 6),
                  if (applyUrl.isNotEmpty)
                    InkWell(
                      onTap: () => _openExternalUrl(applyUrl),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_new, size: 16, color: brandNavy),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                applyUrl,
                                style: caption.copyWith(
                                  color: brandNavy,
                                  decoration: TextDecoration.underline,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (contactEmail.isNotEmpty)
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: contactEmail));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Email rekruter disalin')),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.email_outlined, size: 16, color: brandNavy),
                            const SizedBox(width: 6),
                            Expanded(child: Text(contactEmail, style: caption.copyWith(color: brandNavy))),
                            Icon(Icons.copy, size: 14, color: dim2),
                          ],
                        ),
                      ),
                    ),
                ],
                if (cvUrl != null && cvUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () => _openExternalUrl(cvUrl),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                    label: const Text('Lihat CV yang Dikirim'),
                  ),
                ],
                const SizedBox(height: 20),
                if (!isOwner)
                  if (appStatus != null)
                    Row(
                      children: [
                        Text('Status Lamaran: ', style: label),
                        const SizedBox(width: 8),
                        _statusBadge(appStatus),
                      ],
                    )
                  else
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
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showApplySheet(job);
                        },
                        child: const Text('Lamar Sekarang (Upload CV)', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showApplySheet(Map<String, dynamic> job) {
    final jobId = job['id']?.toString() ?? '';
    final title = job['title']?.toString() ?? 'Lowongan';
    final company = job['company']?.toString() ?? '';
    final applyUrl = job['apply_url']?.toString().trim() ?? '';
    final contactEmail = job['contact_email']?.toString().trim() ?? '';

    final linkCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    PickedPdf? pickedPdf;
    bool submitting = false;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
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
                          Text('Lamar: $title', style: heading.copyWith(fontSize: 18)),
                          if (company.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(company, style: caption.copyWith(color: dim1)),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetCtx),
                      icon: Icon(Icons.close, size: 20, color: dim1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Tutup',
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Upload PDF CV (kompres otomatis & maks 1 MB)
                Text('Upload CV (PDF, kompres otomatis & maks 1 MB)', style: label),
                const SizedBox(height: 8),
                InkWell(
                  onTap: submitting
                      ? null
                      : () async {
                          try {
                            final f = await PdfPicker.pickPdf();
                            if (f == null) return;
                            if (!f.name.toLowerCase().endsWith('.pdf')) {
                              setSheetState(() => errorMsg = 'Format CV harus berupa file PDF (.pdf).');
                              return;
                            }
                            if (f.bytes.isEmpty) {
                              setSheetState(() => errorMsg = 'Gagal membaca file PDF.');
                              return;
                            }
                            if (f.bytes.length > 4 * 1024 * 1024) {
                              setSheetState(() => errorMsg = 'Ukuran PDF awal maksimal 4 MB.');
                              return;
                            }
                            setSheetState(() {
                              pickedPdf = f;
                              errorMsg = null;
                            });
                          } catch (e) {
                            setSheetState(() {
                              errorMsg = 'Gagal membuka pemilih file: $e';
                            });
                          }
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: pickedPdf != null
                          ? brandNavy.withValues(alpha: 0.06)
                          : brandNavy.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: pickedPdf != null ? brandNavy : brandNavy.withValues(alpha: 0.25),
                        width: pickedPdf != null ? 1.4 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: brandNavy.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            pickedPdf != null ? Icons.picture_as_pdf : Icons.upload_file_outlined,
                            color: brandNavy,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                pickedPdf != null ? pickedPdf!.name : 'Pilih file CV (.pdf)',
                                style: subTitle.copyWith(fontSize: 13.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pickedPdf != null
                                    ? '${(pickedPdf!.bytes.length / 1024).ceil()} KB · Siap dikompresi & diunggah'
                                    : 'Otomatis dikompres di server, hasil akhir maks 1 MB',
                                style: caption.copyWith(fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        if (pickedPdf != null)
                          IconButton(
                            icon: Icon(Icons.close, size: 18, color: dim2),
                            onPressed: submitting
                                ? null
                                : () => setSheetState(() {
                                      pickedPdf = null;
                                    }),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: brandNavy,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Pilih File',
                              style: label.copyWith(color: Colors.white, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                Text('Atau Link CV / LinkedIn (opsional jika sudah upload PDF)', style: caption),
                const SizedBox(height: 6),
                TextField(
                  controller: linkCtrl,
                  enabled: !submitting,
                  keyboardType: TextInputType.url,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'https://drive.google.com/... atau linkedin.com/in/...',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),

                const SizedBox(height: 14),
                Text('Catatan untuk Alumni (opsional)', style: label),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  enabled: !submitting,
                  maxLines: 3,
                  style: body.copyWith(color: textPrimary, fontSize: 13.5),
                  decoration: InputDecoration(
                    hintText: 'Ceritakan singkat pengalamanmu atau alasan tertarik posisi ini…',
                    hintStyle: body.copyWith(color: dim2, fontSize: 13.5),
                    filled: true,
                    fillColor: surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: borderColor),
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),

                if (applyUrl.isNotEmpty || contactEmail.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: brandGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brandGold.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Info Rekrutmen Resmi', style: caption.copyWith(fontWeight: FontWeight.w700, color: brandNavy)),
                        if (applyUrl.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.link, size: 15, color: brandNavy),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(applyUrl, style: caption.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: applyUrl));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Link lamaran disalin')),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text('Salin', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (contactEmail.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.mail_outline, size: 15, color: brandNavy),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(contactEmail, style: caption.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis),
                              ),
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(ClipboardData(text: contactEmail));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Email rekruter disalin')),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  child: Text('Salin', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w700)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

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
                            final link = linkCtrl.text.trim();
                            if (pickedPdf == null && link.isEmpty) {
                              setSheetState(() {
                                errorMsg = 'Upload file PDF CV atau isi link CV terlebih dahulu.';
                              });
                              return;
                            }
                            setSheetState(() {
                              submitting = true;
                              errorMsg = null;
                            });
                            try {
                              String finalCvUrl = link;
                              String? sizeNote;
                              if (pickedPdf != null) {
                                final uploadRes = await JobsService.uploadCv(
                                  bytes: pickedPdf!.bytes,
                                  filename: pickedPdf!.name,
                                );
                                finalCvUrl = uploadRes['url']?.toString() ?? '';
                                final finalBytes = (uploadRes['size_bytes'] as num?)?.toInt();
                                if (finalBytes != null) {
                                  sizeNote = ' (${(finalBytes / 1024).ceil()} KB)';
                                }
                              }

                              await JobsService.applyJob(
                                jobId,
                                cvUrl: finalCvUrl,
                                coverNote: noteCtrl.text.trim(),
                              );

                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (mounted) {
                                setState(() {
                                  _appliedStatusByJobId[jobId] = 'pending';
                                });
                                _syncAppliedStatuses();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Lamaran & CV${sizeNote ?? ''} berhasil dikirim ke alumni!'),
                                  ),
                                );
                              }
                            } catch (e) {
                              setSheetState(() {
                                submitting = false;
                                errorMsg = e.toString().replaceFirst('Exception: ', '');
                              });
                            }
                          },
                    child: submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text('Kirim Lamaran ke Alumni', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: brandBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: dim1),
          const SizedBox(width: 4),
          Text(label, style: caption.copyWith(fontSize: 11.5, color: dim1)),
        ],
      ),
    );
  }
}

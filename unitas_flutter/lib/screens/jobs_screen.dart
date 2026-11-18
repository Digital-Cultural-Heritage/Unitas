import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/jobs_service.dart';
import '../widgets/skeleton.dart';
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
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _jobs = [];
  final Set<String> _savedIds = {};
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
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
    _loadSavedIds();
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
      final isRemote = _filter == 'Remote' ? true : null;
      if (_filter == 'Tersimpan') {
        final saved = await JobsService.getSavedJobs();
        if (mounted && epoch == _loadEpoch) {
          setState(() {
            _jobs = saved;
            _hasMore = false;
            _savedIds.addAll(saved.map((j) => j['id']?.toString() ?? ''));
            _loading = false;
          });
        }
      } else {
        final jobs = await JobsService.getJobs(isRemote: isRemote, page: 1);
        if (mounted && epoch == _loadEpoch) {
          setState(() {
            _hasMore = jobs.length >= 20;
            if (_filter != 'Semua' && _filter != 'Remote') {
              _jobs = jobs
                  .where((j) =>
                      j['job_type'] == _filter ||
                      (_filter == 'Magang' && j['job_type'] == 'Internship'))
                  .toList();
            } else {
              _jobs = jobs;
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
    if (_filter == 'Semua' || _filter == 'Remote' || _filter == 'Tersimpan') return;
    if (_jobs.length >= 6) return;
    _autoFillPages++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _filter == 'Tersimpan') return;
    final epoch = _loadEpoch;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final isRemote = _filter == 'Remote' ? true : null;
      final more = await JobsService.getJobs(isRemote: isRemote, page: nextPage);
      if (mounted && epoch == _loadEpoch) {
        setState(() {
          final filtered = (_filter != 'Semua' && _filter != 'Remote')
              ? more
                  .where((j) =>
                      j['job_type'] == _filter ||
                      (_filter == 'Magang' && j['job_type'] == 'Internship'))
                  .toList()
              : more;
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
                              child: const Icon(Icons.work_outline, color: brandNavy, size: 30),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              hasFilter ? 'Tidak ada lowongan yang cocok' : 'Belum ada lowongan tersedia',
                              style: subTitle.copyWith(fontSize: 16),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasFilter
                                  ? 'Coba ubah kata kunci pencarian atau pilih tipe pekerjaan lainnya.'
                                  : 'Bagikan info lowongan kerja atau magang dari perusahaanmu untuk sesama alumni!',
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
                                      'Reset Filter',
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
                                    const SizedBox(height: 14),
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
                                            _timeAgo(job['created_at']?.toString()),
                                            style: caption.copyWith(color: dim2),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandNavy,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                          onPressed: () {
                                            _showApplySheet(job);
                                          },
                                          child: const Text('Lamar Sekarang', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
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
          const Icon(Icons.wifi_off_rounded, color: dim2, size: 36),
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

  void _showApplySheet(Map<String, dynamic> job) {
    final applyUrl = job['apply_url']?.toString().trim() ?? '';
    final contactEmail = job['contact_email']?.toString().trim() ?? '';
    final title = job['title']?.toString() ?? 'Lowongan';
    final company = job['company']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Lamar: $title'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (company.isNotEmpty) ...[
              Text(company, style: subTitle),
              const SizedBox(height: 10),
            ],
            if (applyUrl.isEmpty && contactEmail.isEmpty)
              Text(
                'Pembuat lowongan belum mencantumkan link atau email lamaran. Kamu bisa menghubungi alumni terkait melalui tab Alumni.',
                style: body.copyWith(fontSize: 13),
              ),
            if (applyUrl.isNotEmpty) ...[
              Text('Link Lamaran:', style: label),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(applyUrl, style: body.copyWith(color: brandNavy, fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Salin link',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: applyUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link lamaran disalin')),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (contactEmail.isNotEmpty) ...[
              Text('Email Rekruter:', style: label),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(contactEmail, style: body.copyWith(color: brandNavy, fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Salin email',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: contactEmail));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Email rekruter disalin')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
        ],
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
          Icon(icon, size: 14, color: dim1),
          const SizedBox(width: 4),
          Text(label, style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

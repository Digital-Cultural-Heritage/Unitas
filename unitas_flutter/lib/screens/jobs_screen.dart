import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/jobs_service.dart';
import '../widgets/skeleton.dart';
import 'create_job_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _filter = 'Semua';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _jobs = [];
  final Set<String> _savedIds = {};
  bool _loading = true;

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
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final isRemote = _filter == 'Remote' ? true : null;
      if (_filter == 'Tersimpan') {
        final saved = await JobsService.getSavedJobs();
        if (mounted) {
          setState(() {
            _jobs = saved;
            _savedIds.addAll(saved.map((j) => j['id']?.toString() ?? ''));
            _loading = false;
          });
        }
      } else {
        final jobs = await JobsService.getJobs(isRemote: isRemote);
        if (mounted) {
          setState(() {
            if (_filter != 'Semua' && _filter != 'Remote') {
              _jobs = jobs.where((j) => j['job_type'] == _filter).toList();
            } else {
              _jobs = jobs;
            }
            _loading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCreateJob() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateJobScreen()),
    );
    if (result == true) {
      _load();
    }
  }

  Future<void> _toggleSave(String id) async {
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
    final co = (job['company'] ?? '').toString();
    return co.length >= 2 ? co.substring(0, 2).toUpperCase() : co.toUpperCase();
  }

  String _salary(Map<String, dynamic> job) {
    final min = job['salary_min'];
    final max = job['salary_max'];
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
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 12, 22, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Eksklusif untuk Alumni',
                                style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                              ),
                              Text('Bursa Karier', style: heading),
                            ],
                          ),
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

                    // Content
                    if (_loading)
                      const JobSkeletonList()
                    else if (list.isEmpty)
                      Container(
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
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          children: list.asMap().entries.map((e) {
                            final i = e.key;
                            final job = e.value;
                            final id = job['id']?.toString() ?? '$i';
                            final isSaved = _savedIds.contains(id);
                            final tags = _tags(job);
                            final jobType = job['job_type'] ?? 'Full-time';
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
                                                job['title'] ?? '—',
                                                style: subTitle.copyWith(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color: brandNavy,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                job['company'] ?? '',
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
                                        _infoChip(Icons.location_on_outlined, job['location'] ?? 'Lokasi tidak disebutkan'),
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
                                        Text(_timeAgo(job['created_at']), style: caption.copyWith(color: dim2)),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandNavy,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            elevation: 0,
                                          ),
                                          onPressed: () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Mengarahkan ke halaman lamaran (Segera hadir)')),
                                            );
                                          },
                                          child: const Text('Lamar Cepat', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
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
          Icon(icon, size: 14, color: dim1),
          const SizedBox(width: 4),
          Text(label, style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

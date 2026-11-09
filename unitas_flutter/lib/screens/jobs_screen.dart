import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/jobs_service.dart';
import 'create_job_screen.dart';

class JobsScreen extends StatefulWidget {
  const JobsScreen({super.key});
  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  String _filter = 'Semua';
  List<Map<String, dynamic>> _jobs = [];
  final Set<String> _savedIds = {};
  bool _loading = true;

  final List<String> _filters = ['Semua', 'Full-time', 'Part-time', 'Magang', 'Remote', 'Tersimpan'];

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _toggleSave(String id) async {
    final wasSaved = _savedIds.contains(id);
    setState(() { wasSaved ? _savedIds.remove(id) : _savedIds.add(id); });
    try {
      await JobsService.toggleSave(id);
    } catch (_) {
      if (mounted) setState(() { wasSaved ? _savedIds.add(id) : _savedIds.remove(id); });
    }
  }

  static const List<Color> _logoColors = [
    Color(0xFF1A5C2E), Color(0xFF1A5C1A), Color(0xFF0A2E6B),
    Color(0xFF0A3D6B), Color(0xFF5C1A1A), Color(0xFF2B4F7A),
  ];
  Color _colorFor(int i) => _logoColors[i % _logoColors.length];

  String _logoText(Map<String, dynamic> job) {
    final co = job['company'] ?? '';
    return co.length >= 2 ? co.substring(0, 2).toUpperCase() : co.toUpperCase();
  }

  String _salary(Map<String, dynamic> job) {
    final min = job['salary_min'];
    final max = job['salary_max'];
    if (min == null && max == null) return 'Dirahasiakan';
    if (min != null && max != null) return 'Rp ${(min / 1000000).toStringAsFixed(1)}–${(max / 1000000).toStringAsFixed(1)} jt';
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        backgroundColor: brandNavy,
        foregroundColor: Colors.white,
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateJobScreen()),
          );
          if (result == true) {
            _load();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Pasang Lowongan', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: brandNavy,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Eksklusif untuk Alumni', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.bold)),
                  Text('Bursa Karier', style: heading),
                ]),
              ),
              // Filters
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
                  children: _filters.map((f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () { setState(() => _filter = f); _load(); },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _filter == f ? brandNavy : surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _filter == f ? brandNavy : borderColor),
                        ),
                        child: Text(f, style: caption.copyWith(
                          color: _filter == f ? Colors.white : dim2,
                          fontWeight: _filter == f ? FontWeight.bold : FontWeight.w500,
                        )),
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 10),
              // Content
              if (_loading)
                const Center(child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: brandNavy),
                ))
              else if (_jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: Column(children: [
                    Icon(Icons.work_off_outlined, color: dim2.withOpacity(0.5), size: 48),
                    const SizedBox(height: 12),
                    Text('Belum ada lowongan', style: subTitle),
                  ])),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: _jobs.asMap().entries.map((e) {
                      final i = e.key; final job = e.value;
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
                            BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 48, height: 48,
                                decoration: BoxDecoration(
                                  color: _colorFor(i),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: Text(_logoText(job), style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                              const SizedBox(width: 14),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(job['title'] ?? '—', style: subTitle.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: brandNavy)),
                                const SizedBox(height: 4),
                                Text(job['company'] ?? '', style: body.copyWith(fontWeight: FontWeight.w500, color: dim1)),
                              ])),
                              GestureDetector(
                                onTap: () => _toggleSave(id),
                                child: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border,
                                  color: isSaved ? brandNavy : dim2, size: 24),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              _infoChip(Icons.location_on_outlined, job['location'] ?? 'Lokasi tidak disebutkan'),
                              _infoChip(Icons.work_outline, jobType),
                              _infoChip(Icons.attach_money, _salary(job)),
                            ]),
                            if (tags.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Wrap(spacing: 6, runSpacing: 6, children: tags.map((tag) =>
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: card, borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(tag, style: caption.copyWith(color: dim1, fontWeight: FontWeight.w500)),
                                ),
                              ).toList()),
                            ],
                            const SizedBox(height: 16),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(_timeAgo(job['created_at']), style: caption.copyWith(color: dim2)),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandNavy,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 0,
                                ),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Mengarahkan ke halaman lamaran (Segera hadir)')),
                                  );
                                },
                                child: const Text('Lamar Cepat', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: surface, borderRadius: BorderRadius.circular(4),
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

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

  final List<String> _filters = ['Semua', 'Full-time', 'Remote', 'Tersimpan'];

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
          setState(() { _jobs = jobs; _loading = false; });
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
    if (min == null && max == null) return 'Negosiasi';
    if (min != null && max != null) return 'Rp ${(min / 1000000).round()}–${(max / 1000000).round()} jt';
    if (min != null) return 'Rp ${(min / 1000000).round()}+ jt';
    return '—';
  }

  String _posterLabel(Map<String, dynamic> job) {
    final poster = job['poster'];
    if (poster == null) return '';
    final profiles = poster['user_profiles'];
    if (profiles is List && profiles.isNotEmpty) {
      final p = profiles[0];
      return "${p['full_name'] ?? ''} '${(p['angkatan'] ?? '').toString().length >= 2 ? (p['angkatan'] ?? '').toString().substring(2) : ''}";
    }
    return '';
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
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_jobs.length} lowongan eksklusif alumni', style: caption),
                Text('Bursa Karier', style: heading),
              ]),
            ),
            // Stats
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
              child: Row(
                children: [
                  {'val': '${_jobs.length}', 'label': 'Lowongan'},
                  {'val': '${_jobs.map((j) => j['company']).toSet().length}', 'label': 'Perusahaan'},
                  {'val': '${_jobs.where((j) => (j['location'] ?? '').toString().contains('Remote')).length}', 'label': 'Remote'},
                ].asMap().entries.map((e) {
                  final i = e.key; final s = e.value;
                  return Expanded(child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: surface,
                      border: Border(
                        top: BorderSide(color: borderColor), bottom: BorderSide(color: borderColor),
                        left: BorderSide(color: borderColor),
                        right: i < 2 ? BorderSide(color: borderColor) : BorderSide.none,
                      ),
                      borderRadius: BorderRadius.horizontal(
                        left: i == 0 ? const Radius.circular(10) : Radius.zero,
                        right: i == 2 ? const Radius.circular(10) : Radius.zero,
                      ),
                    ),
                    child: Column(children: [
                      Text(s['val']!, style: statStyle.copyWith(fontSize: 18, color: brandNavy)),
                      Text(s['label']!, style: caption),
                    ]),
                  ));
                }).toList(),
              ),
            ),
            // Filters
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                children: _filters.map((f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () { setState(() => _filter = f); _load(); },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: _filter == f ? brandNavy : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _filter == f ? brandNavy : borderColor),
                      ),
                      child: Text(f, style: caption.copyWith(
                        color: _filter == f ? Colors.white : dim2,
                        fontWeight: _filter == f ? FontWeight.w600 : FontWeight.w400,
                      )),
                    ),
                  ),
                )).toList(),
              ),
            ),
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
                  const Icon(Icons.work_outline, color: Color(0x611E3A5F), size: 40),
                  const SizedBox(height: 12),
                  Text('Belum ada lowongan', style: subTitle),
                ])),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Column(
                  children: _jobs.asMap().entries.map((e) {
                    final i = e.key; final job = e.value;
                    final id = job['id']?.toString() ?? '$i';
                    final isSaved = _savedIds.contains(id);
                    final tags = _tags(job);
                    return Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(children: [
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: _colorFor(i), borderRadius: BorderRadius.circular(10)),
                              alignment: Alignment.center,
                              child: Text(_logoText(job), style: caption.copyWith(
                                color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(job['title'] ?? '—', style: subTitle),
                              Text(job['company'] ?? '', style: caption),
                            ])),
                            GestureDetector(
                              onTap: () => _toggleSave(id),
                              child: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border,
                                color: isSaved ? brandNavy : dim2, size: 20),
                            ),
                          ]),
                          if (tags.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(spacing: 5, runSpacing: 5, children: tags.map((tag) =>
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: card, borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Text(tag, style: caption.copyWith(color: dim1)),
                              ),
                            ).toList()),
                          ],
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(Icons.location_on_outlined, size: 10, color: dim2),
                                const SizedBox(width: 4),
                                Text(job['location'] ?? '', style: caption),
                              ]),
                              const SizedBox(height: 2),
                              Row(children: [
                                Icon(Icons.attach_money, size: 10, color: brandNavy),
                                const SizedBox(width: 4),
                                Text('${_salary(job)}/bln', style: caption.copyWith(
                                  color: dim1, fontWeight: FontWeight.w500)),
                              ]),
                              if (_posterLabel(job).isNotEmpty) ...[
                                const SizedBox(height: 2),
                                RichText(text: TextSpan(children: [
                                  TextSpan(text: 'via ', style: caption),
                                  TextSpan(text: _posterLabel(job), style: caption.copyWith(color: brandNavy)),
                                ])),
                              ],
                            ]),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: brandNavy, foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                elevation: 0,
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Mengarahkan ke halaman lamaran (Segera hadir)')),
                                );
                              },
                              child: Text('Lamar', style: buttonStyle),
                            ),
                          ]),
                        ]),
                      ),
                      if (i < _jobs.length - 1) const Divider(height: 1, color: Color(0x1A1E3A5F)),
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

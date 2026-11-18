import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/jobs_service.dart';

class ManageJobScreen extends StatefulWidget {
  const ManageJobScreen({super.key});

  @override
  State<ManageJobScreen> createState() => _ManageJobScreenState();
}

class _ManageJobScreenState extends State<ManageJobScreen> {
  List<Map<String, dynamic>> _myJobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await JobsService.getMyJobs();
      if (mounted) {
        setState(() {
          _myJobs = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> job) async {
    final current = job['is_active'] != false;
    try {
      final updated = await JobsService.updateJob(
        job['id'].toString(),
        {'is_active': !current},
      );
      if (mounted) {
        setState(() {
          final idx = _myJobs.indexWhere((j) => j['id'] == job['id']);
          if (idx != -1) _myJobs[idx] = updated;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!current ? 'Lowongan diaktifkan kembali' : 'Lowongan ditutup'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _deleteJob(String jobId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Lowongan'),
        content: const Text('Yakin ingin menghapus lowongan ini secara permanen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await JobsService.deleteJob(jobId);
      if (mounted) {
        setState(() => _myJobs.removeWhere((j) => j['id'].toString() == jobId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lowongan dihapus')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  Future<void> _editJobDialog(Map<String, dynamic> job) async {
    final titleCtrl = TextEditingController(text: job['title']?.toString() ?? '');
    final companyCtrl = TextEditingController(text: job['company']?.toString() ?? '');
    final locCtrl = TextEditingController(text: job['location']?.toString() ?? '');
    final descCtrl = TextEditingController(text: job['description']?.toString() ?? '');
    final applyCtrl = TextEditingController(text: job['apply_url']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: job['contact_email']?.toString() ?? '');

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Edit Lowongan', style: heading.copyWith(fontSize: 18)),
              const SizedBox(height: 14),
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Posisi')),
              const SizedBox(height: 10),
              TextField(controller: companyCtrl, decoration: const InputDecoration(labelText: 'Perusahaan')),
              const SizedBox(height: 10),
              TextField(controller: locCtrl, decoration: const InputDecoration(labelText: 'Lokasi')),
              const SizedBox(height: 10),
              TextField(
                controller: applyCtrl,
                decoration: const InputDecoration(labelText: 'Link Lamaran (opsional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email Rekruter (opsional)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Deskripsi'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: brandNavy),
                onPressed: () async {
                  try {
                    await JobsService.updateJob(job['id'].toString(), {
                      'title': titleCtrl.text.trim(),
                      'company': companyCtrl.text.trim(),
                      'location': locCtrl.text.trim(),
                      'apply_url': applyCtrl.text.trim().isEmpty ? null : applyCtrl.text.trim(),
                      'contact_email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                      'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    });
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                      );
                    }
                  }
                },
                child: const Text('Simpan Perubahan'),
              ),
            ],
          ),
        ),
      ),
    );

    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        title: Text('Kelola Lowongan Saya', style: heading.copyWith(fontSize: 18)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _myJobs.isEmpty
              ? Center(
                  child: Text('Kamu belum membuat lowongan kerja.', style: caption),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _myJobs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final job = _myJobs[i];
                      final active = job['is_active'] != false;
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    job['title']?.toString() ?? '',
                                    style: subTitle.copyWith(fontSize: 15),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (active ? brandGreen : dim2).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    active ? 'Aktif' : 'Ditutup',
                                    style: label.copyWith(
                                      color: active ? brandGreen : dim1,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${job['company'] ?? ''} • ${job['location'] ?? ''}',
                              style: caption,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => _editJobDialog(job),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: () => _toggleActive(job),
                                  child: Text(active ? 'Tutup' : 'Aktifkan'),
                                ),
                                const Spacer(),
                                IconButton(
                                  onPressed: () => _deleteJob(job['id'].toString()),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: 'Hapus lowongan',
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

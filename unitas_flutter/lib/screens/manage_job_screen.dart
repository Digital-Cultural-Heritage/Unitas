import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/jobs_service.dart';
import '../widgets/avatar.dart';
import 'chat_room_screen.dart';

class ManageJobScreen extends StatefulWidget {
  const ManageJobScreen({super.key});

  @override
  State<ManageJobScreen> createState() => _ManageJobScreenState();
}

class _ManageJobScreenState extends State<ManageJobScreen> {
  List<Map<String, dynamic>> _myJobs = [];
  final Set<String> _busyIds = {};
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_error || _myJobs.isEmpty) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final list = await JobsService.getMyJobs();
      if (mounted) {
        setState(() {
          _myJobs = list;
          _loading = false;
          _error = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _myJobs.isEmpty;
        });
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> job) async {
    final jobId = job['id']?.toString() ?? '';
    if (jobId.isEmpty || !_busyIds.add(jobId)) return;
    final current = job['is_active'] != false;
    setState(() {});
    try {
      final updated = await JobsService.updateJob(
        jobId,
        {'is_active': !current},
      );
      if (mounted) {
        setState(() {
          final idx = _myJobs.indexWhere((j) => j['id']?.toString() == jobId);
          if (idx != -1) {
            _myJobs[idx] = {
              ...updated,
              'applicant_count': _myJobs[idx]['applicant_count'] ?? 0,
            };
          }
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
    } finally {
      _busyIds.remove(jobId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteJob(String jobId) async {
    if (jobId.isEmpty || _busyIds.contains(jobId)) return;
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
    if (confirm != true || !mounted) return;
    if (!_busyIds.add(jobId)) return;
    setState(() {});

    try {
      await JobsService.deleteJob(jobId);
      if (mounted) {
        setState(() => _myJobs.removeWhere((j) => j['id']?.toString() == jobId));
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
    } finally {
      _busyIds.remove(jobId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editJobDialog(Map<String, dynamic> job) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditJobSheet(job: job),
    );
    if (saved == true && mounted) _load();
  }

  Map<String, dynamic>? _applicantProfile(Map<String, dynamic> app) {
    final applicant = app['applicant'];
    if (applicant is! Map) return null;
    final profiles = applicant['user_profiles'];
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

  String _statusLabel(String status) {
    switch (status) {
      case 'reviewed':
        return 'Direview';
      case 'referred':
        return 'Diteruskan ke HR';
      case 'rejected':
        return 'Belum Cocok';
      default:
        return 'Menunggu';
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

  Future<void> _openCvUrl(String rawUrl) async {
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
          const SnackBar(content: Text('Link CV disalin ke clipboard')),
        );
      }
    }
  }

  void _openApplicantsSheet(Map<String, dynamic> job) {
    final jobId = job['id'].toString();
    final jobTitle = job['title']?.toString() ?? 'Lowongan';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        List<Map<String, dynamic>> applicants = [];
        bool loadingApps = true;
        bool initialized = false;
        String? busyAppId;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            if (!initialized) {
              initialized = true;
              JobsService.getJobApplicants(jobId).then((data) {
                if (ctx.mounted) {
                  setSheetState(() {
                    applicants = data;
                    loadingApps = false;
                  });
                }
              }).catchError((_) {
                if (ctx.mounted) {
                  setSheetState(() => loadingApps = false);
                }
              });
            }

            Future<void> changeStatus(String appId, String newStatus) async {
              setSheetState(() => busyAppId = appId);
              try {
                await JobsService.updateApplicationStatus(appId, newStatus);
                if (ctx.mounted) {
                  setSheetState(() {
                    final idx = applicants.indexWhere((a) => a['id'].toString() == appId);
                    if (idx != -1) applicants[idx] = {...applicants[idx], 'status': newStatus};
                    busyAppId = null;
                  });
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Status pelamar diubah ke ${_statusLabel(newStatus)}')),
                  );
                }
              } catch (e) {
                if (ctx.mounted) setSheetState(() => busyAppId = null);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                  );
                }
              }
            }

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.sizeOf(ctx).height * 0.8,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(color: dim3, borderRadius: BorderRadius.circular(99)),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Daftar Pelamar', style: heading.copyWith(fontSize: 18)),
                                    Text(jobTitle, style: caption, overflow: TextOverflow.ellipsis),
                                  ],
                                ),
                              ),
                              Text(
                                '${applicants.length} orang',
                                style: label.copyWith(color: brandNavy),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: borderColor),
                    Expanded(
                      child: loadingApps
                          ? const Center(child: CircularProgressIndicator())
                          : applicants.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Text(
                                      'Belum ada alumni yang melamar lowongan ini.',
                                      style: caption,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: applicants.length,
                                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                                  itemBuilder: (_, idx) {
                                    final app = applicants[idx];
                                    final appId = app['id'].toString();
                                    final applicantId = app['applicant_id']?.toString() ?? '';
                                    final status = app['status']?.toString() ?? 'pending';
                                    final cvUrl = app['cv_url']?.toString() ?? '';
                                    final coverNote = app['cover_note']?.toString().trim() ?? '';
                                    final prof = _applicantProfile(app);
                                    final name = (prof?['full_name'] ?? 'Alumni Unitas').toString();
                                    final avatarUrl = prof?['avatar_url']?.toString();
                                    final edu = [prof?['prodi'], prof?['angkatan']]
                                        .where((x) => x != null && x.toString().trim().isNotEmpty)
                                        .join(' · ');
                                    final currentJob = [prof?['pekerjaan'], prof?['perusahaan']]
                                        .where((x) => x != null && x.toString().trim().isNotEmpty)
                                        .join(' · ');
                                    final stColor = _statusColor(status);
                                    final isBusy = busyAppId == appId;

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
                                              UnitasAvatar(
                                                initials: _initialsFromName(name),
                                                color: brandNavy,
                                                size: 42,
                                                avatarUrl: avatarUrl,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(name, style: subTitle.copyWith(fontSize: 14.5)),
                                                    if (edu.isNotEmpty)
                                                      Text(edu, style: caption, overflow: TextOverflow.ellipsis),
                                                    if (currentJob.isNotEmpty)
                                                      Text(currentJob, style: caption, overflow: TextOverflow.ellipsis),
                                                  ],
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: stColor.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  _statusLabel(status),
                                                  style: label.copyWith(color: stColor, fontSize: 11),
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (coverNote.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(
                                                color: brandBg,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(coverNote, style: body.copyWith(fontSize: 12.5)),
                                            ),
                                          ],
                                          const SizedBox(height: 10),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (cvUrl.isNotEmpty)
                                                OutlinedButton.icon(
                                                  onPressed: () => _openCvUrl(cvUrl),
                                                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                                                  label: const Text('Lihat CV'),
                                                ),
                                              if (applicantId.isNotEmpty)
                                                OutlinedButton.icon(
                                                  onPressed: () {
                                                    Navigator.pop(sheetCtx);
                                                    Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) => ChatRoomScreen(
                                                          peerId: applicantId,
                                                          peerName: name,
                                                          peerInitials: _initialsFromName(name),
                                                          peerAvatarUrl: avatarUrl,
                                                          peerSubtitle: edu,
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                                                  label: const Text('Chat'),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Divider(height: 1, color: borderColor),
                                          const SizedBox(height: 10),
                                          Text('Update Status Referral:', style: caption.copyWith(fontSize: 11.5)),
                                          const SizedBox(height: 6),
                                          Wrap(
                                            spacing: 6,
                                            runSpacing: 6,
                                            children: [
                                              for (final opt in const [
                                                ('reviewed', 'Direview'),
                                                ('referred', 'Teruskan ke HR'),
                                                ('rejected', 'Belum Cocok'),
                                              ])
                                                ChoiceChip(
                                                  label: Text(opt.$2),
                                                  selected: status == opt.$1,
                                                  selectedColor: brandNavy,
                                                  labelStyle: caption.copyWith(
                                                    color: status == opt.$1 ? Colors.white : dim1,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  onSelected: isBusy || status == opt.$1
                                                      ? null
                                                      : (_) => changeStatus(appId, opt.$1),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
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
          : _error && _myJobs.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.wifi_off_rounded, size: 42, color: dim2),
                        const SizedBox(height: 12),
                        Text('Gagal memuat lowongan', style: subTitle),
                        const SizedBox(height: 6),
                        Text('Periksa koneksi internetmu lalu coba lagi.', style: caption),
                        const SizedBox(height: 16),
                        OutlinedButton(onPressed: _load, child: const Text('Coba lagi')),
                      ],
                    ),
                  ),
                )
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
                      final jobId = job['id']?.toString() ?? '';
                      final isBusy = _busyIds.contains(jobId);
                      final active = job['is_active'] != false;
                      final appCount = (job['applicant_count'] as num?)?.toInt() ?? 0;

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
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: brandNavy,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: () => _openApplicantsSheet(job),
                                  icon: const Icon(Icons.people_outline, size: 16),
                                  label: Text('Pelamar ($appCount)'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: isBusy ? null : () => _editJobDialog(job),
                                  icon: const Icon(Icons.edit_outlined, size: 16),
                                  label: const Text('Edit'),
                                ),
                                OutlinedButton(
                                  onPressed: isBusy ? null : () => _toggleActive(job),
                                  child: Text(active ? 'Tutup' : 'Aktifkan'),
                                ),
                                IconButton(
                                  onPressed: isBusy ? null : () => _deleteJob(jobId),
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

class _EditJobSheet extends StatefulWidget {
  final Map<String, dynamic> job;
  const _EditJobSheet({required this.job});

  @override
  State<_EditJobSheet> createState() => _EditJobSheetState();
}

class _EditJobSheetState extends State<_EditJobSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _locCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _applyCtrl;
  late final TextEditingController _emailCtrl;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.job['title']?.toString() ?? '');
    _companyCtrl = TextEditingController(text: widget.job['company']?.toString() ?? '');
    _locCtrl = TextEditingController(text: widget.job['location']?.toString() ?? '');
    _descCtrl = TextEditingController(text: widget.job['description']?.toString() ?? '');
    _applyCtrl = TextEditingController(text: widget.job['apply_url']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: widget.job['contact_email']?.toString() ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _locCtrl.dispose();
    _descCtrl.dispose();
    _applyCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await JobsService.updateJob(widget.job['id'].toString(), {
        'title': _titleCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'apply_url': _applyCtrl.text.trim().isEmpty ? null : _applyCtrl.text.trim(),
        'contact_email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Edit Lowongan', style: heading.copyWith(fontSize: 18)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Posisi'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Posisi wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _companyCtrl,
                  decoration: const InputDecoration(labelText: 'Perusahaan'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Perusahaan wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _locCtrl,
                  decoration: const InputDecoration(labelText: 'Lokasi'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Lokasi wajib diisi' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _applyCtrl,
                  decoration: const InputDecoration(labelText: 'Link Lamaran (opsional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Rekruter (opsional)'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Deskripsi'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, style: caption.copyWith(color: const Color(0xFFDC2626))),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: brandNavy),
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Menyimpan…' : 'Simpan Perubahan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/api_client.dart';

class CreateJobScreen extends StatefulWidget {
  const CreateJobScreen({super.key});

  @override
  State<CreateJobScreen> createState() => _CreateJobScreenState();
}

class _CreateJobScreenState extends State<CreateJobScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _locCtrl = TextEditingController();
  final _salaryMinCtrl = TextEditingController();
  final _salaryMaxCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  String _type = 'Full-time';
  bool _isRemote = false;
  final List<String> _types = ['Full-time', 'Part-time', 'Contract', 'Internship'];
  final List<String> _suggestedTags = ['Startup', 'Flutter', 'Backend', 'UI/UX', 'Fresh Graduate', 'WFA'];
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _locCtrl.dispose();
    _salaryMinCtrl.dispose();
    _salaryMaxCtrl.dispose();
    _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  List<String> _currentTags() {
    return _tagsCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _toggleSuggestedTag(String tag) {
    final list = _currentTags();
    final exists = list.any((t) => t.toLowerCase() == tag.toLowerCase());
    if (exists) {
      list.removeWhere((t) => t.toLowerCase() == tag.toLowerCase());
    } else {
      list.add(tag);
    }
    setState(() {
      _tagsCtrl.text = list.join(', ');
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final sMin = int.tryParse(_salaryMinCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final sMax = int.tryParse(_salaryMaxCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (sMin != null && sMax != null && sMax < sMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gaji maksimal tidak boleh lebih kecil dari gaji minimal')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final tags = _currentTags();

      final Map<String, dynamic> body = {
        'title': _titleCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'job_type': _type,
        'is_remote': _isRemote,
        'description': _descCtrl.text.trim(),
      };
      if (sMin != null) body['salary_min'] = sMin;
      if (sMax != null) body['salary_max'] = sMax;
      if (tags.isNotEmpty) body['tags'] = tags;

      await ApiClient.post('/api/jobs', body: body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lowongan berhasil diposting!')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terjadi kesalahan')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTags = _currentTags().map((e) => e.toLowerCase()).toSet();

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: brandBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: brandNavy),
        title: Text('Pasang Lowongan', style: subTitle.copyWith(fontSize: 17)),
        actions: [
          _loading
              ? const Padding(
                  padding: EdgeInsets.only(right: 20),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _submit,
                  child: Text('Posting', style: buttonStyle.copyWith(color: brandNavy)),
                ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle('DETAIL POSISI'),
                  const SizedBox(height: 12),

                  // Tipe Pekerjaan
                  Text('Tipe Pekerjaan', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _types.map((c) {
                      final selected = _type == c;
                      return InkWell(
                        onTap: () => setState(() => _type = c),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? brandNavy : surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: selected ? brandNavy : borderColor),
                          ),
                          child: Text(
                            c,
                            style: caption.copyWith(
                              color: selected ? Colors.white : dim1,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),

                  _field(
                    'Judul Posisi',
                    _titleCtrl,
                    Icons.work_outline,
                    'Contoh: Senior Backend Engineer',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Posisi wajib diisi' : null,
                  ),
                  const SizedBox(height: 14),

                  _field(
                    'Nama Perusahaan',
                    _companyCtrl,
                    Icons.business_outlined,
                    'Contoh: PT Teknologi Indonesia',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Perusahaan wajib diisi' : null,
                  ),
                  const SizedBox(height: 14),

                  _field(
                    'Lokasi Kerja',
                    _locCtrl,
                    _isRemote ? Icons.laptop_mac_outlined : Icons.location_on_outlined,
                    _isRemote ? 'Contoh: Remote (Indonesia)' : 'Contoh: Jakarta Selatan',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Lokasi wajib diisi' : null,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: SwitchListTile.adaptive(
                      dense: true,
                      activeThumbColor: brandNavy,
                      title: Text('Bisa Kerja Remote (WFH / WFA)', style: subTitle.copyWith(fontSize: 13.5)),
                      value: _isRemote,
                      onChanged: (v) => setState(() => _isRemote = v),
                    ),
                  ),
                  const SizedBox(height: 24),

                  _sectionTitle('KOMPENSASI & TAGS'),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _salaryField('Gaji Min. (opsional)', _salaryMinCtrl, '5000000'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _salaryField('Gaji Max. (opsional)', _salaryMaxCtrl, '10000000'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  _field(
                    'Tags (pisahkan dengan koma)',
                    _tagsCtrl,
                    Icons.label_outline,
                    'Contoh: Node.js, Remote, Startup',
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _suggestedTags.map((tag) {
                      final isAdded = activeTags.contains(tag.toLowerCase());
                      return InkWell(
                        onTap: () => _toggleSuggestedTag(tag),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isAdded ? brandNavy : card,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isAdded ? brandNavy : borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isAdded ? Icons.check : Icons.add,
                                size: 13,
                                color: isAdded ? Colors.white : dim1,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tag,
                                style: caption.copyWith(
                                  color: isAdded ? Colors.white : dim1,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  _sectionTitle('DESKRIPSI'),
                  const SizedBox(height: 12),

                  Text('Deskripsi Pekerjaan', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 5,
                    style: body.copyWith(color: textPrimary),
                    decoration: _inputDeco('Tuliskan persyaratan, tanggung jawab, atau cara melamar...'),
                  ),
                  const SizedBox(height: 28),

                  // Tombol utama di bawah (ergonomis untuk jari di HP)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text('Publikasikan Lowongan', style: buttonStyle.copyWith(fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: label.copyWith(
        fontSize: 11,
        color: brandNavy,
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _salaryField(String label_, TextEditingController ctrl, String hint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label_, style: label.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: body.copyWith(color: textPrimary),
          decoration: _inputDeco(hint).copyWith(
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 14, right: 6),
              child: Text(
                'Rp',
                style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
      ],
    );
  }

  Widget _field(
    String label_,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType? type,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label_, style: label.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: type,
          onChanged: onChanged,
          style: body.copyWith(color: textPrimary),
          decoration: _inputDeco(hint).copyWith(
            prefixIcon: Icon(icon, color: dim2, size: 18),
          ),
          validator: validator,
        ),
      ],
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: body.copyWith(color: dim2),
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: brandNavy, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
      );
}

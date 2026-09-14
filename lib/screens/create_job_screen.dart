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
  final List<String> _types = ['Full-time', 'Part-time', 'Contract', 'Internship'];
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose(); _companyCtrl.dispose(); _locCtrl.dispose();
    _salaryMinCtrl.dispose(); _salaryMaxCtrl.dispose(); _descCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    
    try {
      final sMin = int.tryParse(_salaryMinCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
      final sMax = int.tryParse(_salaryMaxCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''));
      final tagsStr = _tagsCtrl.text.trim();
      final tags = tagsStr.isNotEmpty 
          ? tagsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
          : [];

      final Map<String, dynamic> body = {
        'title': _titleCtrl.text.trim(),
        'company': _companyCtrl.text.trim(),
        'location': _locCtrl.text.trim(),
        'job_type': _type,
        'description': _descCtrl.text.trim(),
      };
      if (sMin != null) body['salary_min'] = sMin;
      if (sMax != null) body['salary_max'] = sMax;
      if (tags.isNotEmpty) body['tags'] = tags;

      await ApiClient.post('/api/jobs', body: body);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lowongan berhasil diposting!'))
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Terjadi kesalahan')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: brandBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: brandNavy),
        title: Text('Pasang Lowongan', style: label),
        actions: [
          _loading
            ? const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2))),
              )
            : TextButton(
                onPressed: _submit,
                child: Text('Posting', style: buttonStyle.copyWith(color: brandNavy)),
              ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Tipe
            Text('Tipe Pekerjaan', style: label.copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _types.map((c) => GestureDetector(
                onTap: () => setState(() => _type = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _type == c ? brandNavy : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _type == c ? brandNavy : borderColor),
                  ),
                  child: Text(c, style: caption.copyWith(
                    color: _type == c ? Colors.white : dim2,
                    fontWeight: _type == c ? FontWeight.w600 : FontWeight.w400,
                  )),
                ),
              )).toList(),
            ),
            const SizedBox(height: 24),

            _field('Judul Posisi', _titleCtrl, Icons.work_outline, 'Contoh: Senior Backend Engineer',
              validator: (v) => v == null || v.isEmpty ? 'Posisi wajib diisi' : null),
            const SizedBox(height: 16),
            
            _field('Nama Perusahaan', _companyCtrl, Icons.business_outlined, 'Contoh: PT Teknologi Indonesia',
              validator: (v) => v == null || v.isEmpty ? 'Perusahaan wajib diisi' : null),
            const SizedBox(height: 16),

            _field('Lokasi', _locCtrl, Icons.location_on_outlined, 'Contoh: Jakarta / Remote',
              validator: (v) => v == null || v.isEmpty ? 'Lokasi wajib diisi' : null),
            const SizedBox(height: 16),

            Row(children: [
              Expanded(child: _field('Gaji Min. (opsional)', _salaryMinCtrl, Icons.attach_money, 'Contoh: 10000000', type: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: _field('Gaji Max. (opsional)', _salaryMaxCtrl, Icons.attach_money, 'Contoh: 20000000', type: TextInputType.number)),
            ]),
            const SizedBox(height: 16),

            _field('Tags (pisahkan dengan koma)', _tagsCtrl, Icons.label_outline, 'Contoh: Node.js, Remote, Startup'),
            const SizedBox(height: 16),

            Text('Deskripsi Pekerjaan', style: label.copyWith(fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              maxLines: 5,
              style: body,
              decoration: _inputDeco('Persyaratan, tanggung jawab, dll...').copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 70),
                  child: Icon(Icons.description_outlined, color: dim2, size: 18),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  Widget _field(String label_, TextEditingController ctrl, IconData icon, String hint, {TextInputType? type, String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label_, style: label.copyWith(fontSize: 13)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl, keyboardType: type, style: body,
        decoration: _inputDeco(hint).copyWith(prefixIcon: Icon(icon, color: dim2, size: 18)),
        validator: validator,
      ),
    ]);
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
    hintText: hint, hintStyle: body.copyWith(color: dim2), filled: true, fillColor: surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: borderColor)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: brandNavy, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626))),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5)),
  );
}

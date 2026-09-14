import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/api_client.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialProfile;
  const EditProfileScreen({super.key, required this.initialProfile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pekerjaanCtrl;
  late final TextEditingController _perusahaanCtrl;
  late final TextEditingController _kotaCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _linkedinCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl = TextEditingController(text: p['full_name']);
    _pekerjaanCtrl = TextEditingController(text: p['pekerjaan']);
    _perusahaanCtrl = TextEditingController(text: p['perusahaan']);
    _kotaCtrl = TextEditingController(text: p['kota']);
    _bioCtrl = TextEditingController(text: p['bio']);
    _linkedinCtrl = TextEditingController(text: p['linkedin']);
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _pekerjaanCtrl.dispose(); _perusahaanCtrl.dispose();
    _kotaCtrl.dispose(); _bioCtrl.dispose(); _linkedinCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    
    try {
      final body = {
        'full_name': _nameCtrl.text.trim(),
        'pekerjaan': _pekerjaanCtrl.text.trim(),
        'perusahaan': _perusahaanCtrl.text.trim(),
        'kota': _kotaCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'linkedin': _linkedinCtrl.text.trim(),
      };

      await UsersService.updateMe(body);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui'))
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
        title: Text('Edit Profil', style: label),
        actions: [
          _loading
            ? const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2))),
              )
            : TextButton(
                onPressed: _submit,
                child: Text('Simpan', style: buttonStyle.copyWith(color: brandNavy)),
              ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _field('Nama Lengkap', _nameCtrl, Icons.person_outline, 'Nama lengkap',
              validator: (v) => v == null || v.isEmpty ? 'Nama wajib diisi' : null),
            const SizedBox(height: 16),
            
            _field('Pekerjaan / Jabatan', _pekerjaanCtrl, Icons.work_outline, 'Contoh: Software Engineer'),
            const SizedBox(height: 16),

            _field('Perusahaan', _perusahaanCtrl, Icons.business_outlined, 'Contoh: PT Teknologi Indonesia'),
            const SizedBox(height: 16),

            _field('Kota Domisili', _kotaCtrl, Icons.location_on_outlined, 'Contoh: Jakarta'),
            const SizedBox(height: 16),

            _field('URL LinkedIn', _linkedinCtrl, Icons.link, 'Contoh: https://linkedin.com/in/username'),
            const SizedBox(height: 16),

            Text('Bio Singkat', style: label.copyWith(fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _bioCtrl,
              maxLines: 4,
              style: body,
              decoration: _inputDeco('Ceritakan sedikit tentang dirimu...').copyWith(
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(bottom: 50),
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

  Widget _field(String label_, TextEditingController ctrl, IconData icon, String hint, {String? Function(String?)? validator}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label_, style: label.copyWith(fontSize: 13)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl, style: body,
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

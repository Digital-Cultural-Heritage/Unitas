import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/api_client.dart';

class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegisterSuccess;
  const RegisterScreen({super.key, required this.onRegisterSuccess});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _prodiCtrl   = TextEditingController();
  final _angkCtrl    = TextEditingController();
  final _kotaCtrl    = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose(); _emailCtrl.dispose(); _passCtrl.dispose();
    _prodiCtrl.dispose(); _angkCtrl.dispose(); _kotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.register(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        fullName: _nameCtrl.text.trim(),
        prodi: _prodiCtrl.text.trim(),
        angkatan: _angkCtrl.text.trim(),
        kota: _kotaCtrl.text.trim(),
      );
      widget.onRegisterSuccess();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Tidak dapat terhubung ke server.');
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
        title: Text('Daftar Akun', style: label),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bergabung dengan Unitas', style: heading),
                const SizedBox(height: 6),
                Text('Platform alumni terbesar Indonesia', style: body.copyWith(color: dim2)),
                const SizedBox(height: 24),

                // Error banner
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!, style: caption.copyWith(color: const Color(0xFFDC2626)))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                ],

                _field('Nama Lengkap', _nameCtrl, Icons.person_outline, 'Budi Santoso',
                  validator: (v) => v == null || v.isEmpty ? 'Nama lengkap wajib diisi' : null),
                const SizedBox(height: 14),
                _field('Email', _emailCtrl, Icons.email_outlined, 'email@contoh.com',
                  type: TextInputType.emailAddress,
                  validator: (v) => v == null || !v.contains('@') ? 'Email tidak valid' : null),
                const SizedBox(height: 14),

                // Password
                Text('Kata Sandi', style: label.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: body,
                  decoration: _inputDeco('Min. 8 karakter', Icons.lock_outlined).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: dim2, size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 8 ? 'Password minimal 8 karakter' : null,
                ),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(child: _field('Program Studi', _prodiCtrl, Icons.school_outlined, 'Informatika',
                    validator: (v) => v == null || v.isEmpty ? 'Wajib diisi' : null)),
                  const SizedBox(width: 12),
                  Expanded(child: _field('Angkatan', _angkCtrl, Icons.calendar_today_outlined, '2020',
                    type: TextInputType.number,
                    validator: (v) => v == null || v.isEmpty ? 'Wajib diisi' : null)),
                ]),
                const SizedBox(height: 14),
                _field('Kota (opsional)', _kotaCtrl, Icons.location_on_outlined, 'Jakarta'),
                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    onPressed: _loading ? null : _register,
                    child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Daftar Sekarang', style: buttonStyle.copyWith(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Sudah punya akun?', style: body.copyWith(color: dim2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('Masuk', style: body.copyWith(
                      color: brandNavy, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label_,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType? type,
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label_, style: label.copyWith(fontSize: 13)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        keyboardType: type,
        style: body,
        decoration: _inputDeco(hint, icon),
        validator: validator,
      ),
    ]);
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: body.copyWith(color: dim2),
    prefixIcon: Icon(icon, color: dim2, size: 18),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/api_client.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const LoginScreen({super.key, required this.onLoginSuccess});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.login(_emailCtrl.text.trim(), _passCtrl.text);
      widget.onLoginSuccess();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Tidak dapat terhubung ke server. Cek koneksi kamu.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 40),
                // Logo / Brand
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                      color: brandNavy,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text('U', style: GoogleFonts.outfit(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800,
                    )),
                  ),
                  const SizedBox(width: 12),
                  Text('Unitas', style: GoogleFonts.outfit(
                    color: brandNavy, fontSize: 24, fontWeight: FontWeight.w800,
                  )),
                ]),
                const SizedBox(height: 40),
                Text('Selamat datang kembali', style: heading),
                const SizedBox(height: 6),
                Text('Masuk untuk melanjutkan', style: body.copyWith(color: dim2)),
                const SizedBox(height: 32),

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

                // Email
                Text('Email', style: label.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  style: body,
                  decoration: _inputDeco('email@contoh.com', Icons.email_outlined),
                  validator: (v) => v == null || !v.contains('@') ? 'Email tidak valid' : null,
                ),
                const SizedBox(height: 18),

                // Password
                Text('Kata Sandi', style: label.copyWith(fontSize: 13)),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  style: body,
                  decoration: _inputDeco('••••••••', Icons.lock_outlined).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        color: dim2, size: 18),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => v == null || v.length < 8 ? 'Password minimal 8 karakter' : null,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _openForgotPasswordSheet,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      'Lupa kata sandi?',
                      style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Login button
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
                    onPressed: _loading ? null : _login,
                    child: _loading
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text('Masuk', style: buttonStyle.copyWith(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 20),

                // Register link
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Belum punya akun?', style: body.copyWith(color: dim2)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => RegisterScreen(
                        onRegisterSuccess: widget.onLoginSuccess,
                      )),
                    ),
                    child: Text('Daftar sekarang', style: body.copyWith(
                      color: brandNavy, fontWeight: FontWeight.w600,
                    )),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: body.copyWith(color: dim2),
    prefixIcon: Icon(icon, color: dim2, size: 18),
    filled: true,
    fillColor: surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: borderColor),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: brandNavy, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
    ),
  );

  void _openForgotPasswordSheet() {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool otpSent = false;
    bool busy = false;
    String? devOtpHint;
    String? errMsg;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetCtx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reset Kata Sandi', style: heading.copyWith(fontSize: 18)),
                const SizedBox(height: 6),
                Text(
                  otpSent
                      ? 'Masukkan kode OTP 6 digit dan kata sandi baru kamu.'
                      : 'Masukkan email terdaftar untuk menerima kode OTP.',
                  style: caption,
                ),
                const SizedBox(height: 16),
                if (errMsg != null) ...[
                  Text(errMsg!, style: caption.copyWith(color: Colors.red)),
                  const SizedBox(height: 8),
                ],
                if (devOtpHint != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: brandGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Kode OTP (dev): $devOtpHint',
                      style: label.copyWith(color: brandNavy),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: emailCtrl,
                  enabled: !otpSent,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _inputDeco('nama@alumni.ac.id', Icons.email_outlined),
                ),
                if (otpSent) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _inputDeco('Kode OTP 6 digit', Icons.pin_outlined),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassCtrl,
                    obscureText: true,
                    decoration: _inputDeco('Kata sandi baru (min 8 karakter)', Icons.lock_outline),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brandNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: busy
                      ? null
                      : () async {
                          setSheet(() {
                            busy = true;
                            errMsg = null;
                          });
                          try {
                            if (!otpSent) {
                              final res = await AuthService.forgotPassword(emailCtrl.text.trim());
                              setSheet(() {
                                otpSent = true;
                                busy = false;
                                devOtpHint = res['dev_otp']?.toString();
                              });
                            } else {
                              await AuthService.resetPassword(
                                email: emailCtrl.text.trim(),
                                otp: otpCtrl.text.trim(),
                                newPassword: newPassCtrl.text,
                              );
                              if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Password berhasil direset. Silakan login.')),
                                );
                              }
                            }
                          } catch (e) {
                            setSheet(() {
                              busy = false;
                              errMsg = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(otpSent ? 'Simpan Kata Sandi Baru' : 'Kirim Kode OTP', style: buttonStyle),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

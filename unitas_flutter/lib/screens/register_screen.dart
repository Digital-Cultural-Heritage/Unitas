import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_service.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

bool isValidAuthEmail(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(trimmed);
}

String? validateAuthPassword(String? value, {bool checkMaxBytes = false}) {
  if (value == null || value.length < 8) {
    return 'Password minimal 8 karakter';
  }
  if (checkMaxBytes && utf8.encode(value).length > 72) {
    return 'Password maksimal 72 karakter';
  }
  return null;
}

InputDecoration authInputDecoration(
  String hint,
  IconData icon, {
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: body.copyWith(color: dim2),
    prefixIcon: Icon(icon, color: dim2, size: 18),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: borderColor),
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
}

class AuthErrorBanner extends StatelessWidget {
  final String message;
  const AuthErrorBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: caption.copyWith(color: const Color(0xFFDC2626)),
            ),
          ),
        ],
      ),
    );
  }
}

class GoogleContinueButton extends StatelessWidget {
  final bool loading;
  final bool disabled;
  final VoidCallback onPressed;

  const GoogleContinueButton({
    super.key,
    required this.loading,
    required this.disabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: borderColor, height: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('atau', style: caption.copyWith(color: dim2)),
            ),
            const Expanded(child: Divider(color: borderColor, height: 1)),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandNavy,
              side: const BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: disabled ? null : onPressed,
            child: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: brandNavy,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CustomPaint(painter: _GoogleLogoPainter()),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Continue with Google',
                        style: buttonStyle.copyWith(
                          color: brandNavy,
                          fontSize: 14.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.19;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Blue top-right arc + horizontal bar
    paint.color = const Color(0xFF4285F4);
    canvas.drawArc(rect, -0.05, math.pi * 0.45, false, paint);
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(size.width * 0.52, midY),
      Offset(size.width - stroke * 0.15, midY),
      paint,
    );

    // Green bottom-right/bottom arc
    paint.color = const Color(0xFF34A853);
    canvas.drawArc(rect, math.pi * 0.35, math.pi * 0.48, false, paint);

    // Yellow bottom-left arc
    paint.color = const Color(0xFFFBBC05);
    canvas.drawArc(rect, math.pi * 0.80, math.pi * 0.42, false, paint);

    // Red top-left arc
    paint.color = const Color(0xFFEA4335);
    canvas.drawArc(rect, math.pi * 1.20, math.pi * 0.55, false, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RegisterScreen extends StatefulWidget {
  final VoidCallback onRegisterSuccess;
  const RegisterScreen({super.key, required this.onRegisterSuccess});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _prodiCtrl = TextEditingController();
  final _angkCtrl = TextEditingController();
  final _kotaCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;
  String? _error;

  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _prodiCtrl.dispose();
    _angkCtrl.dispose();
    _kotaCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.register(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text,
        fullName: _nameCtrl.text.trim(),
        prodi: _prodiCtrl.text.trim(),
        angkatan: _angkCtrl.text.trim(),
        kota: _kotaCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onRegisterSuccess();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Tidak dapat terhubung ke server.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueWithGoogle() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final session = await AuthService.signInWithGoogle();
      if (!mounted) return;
      if (session == null) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      widget.onRegisterSuccess();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Gagal masuk dengan Google. Cek koneksi atau coba lagi.',
      );
    } finally {
      if (mounted) setState(() => _googleLoading = false);
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
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Bergabung dengan Unitas', style: heading),
                    const SizedBox(height: 6),
                    Text(
                      'Platform alumni terbesar Indonesia',
                      style: body.copyWith(color: dim2),
                    ),
                    const SizedBox(height: 24),

                    if (_error != null) ...[
                      AuthErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],

                    _field(
                      'Nama Lengkap',
                      _nameCtrl,
                      Icons.person_outline,
                      'Budi Santoso',
                      autofillHints: const [AutofillHints.name],
                      action: TextInputAction.next,
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Nama lengkap wajib diisi';
                        if (t.length > 100) return 'Maksimal 100 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    _field(
                      'Email',
                      _emailCtrl,
                      Icons.email_outlined,
                      'email@contoh.com',
                      type: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      action: TextInputAction.next,
                      validator: (v) =>
                          isValidAuthEmail(v) ? null : 'Email tidak valid',
                    ),
                    const SizedBox(height: 14),

                    // Password
                    Text('Kata Sandi', style: label.copyWith(fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passCtrl,
                      enabled: !_busy,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      style: body,
                      decoration: authInputDecoration(
                        'Min. 8 karakter',
                        Icons.lock_outlined,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: dim2,
                            size: 18,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) =>
                          validateAuthPassword(v, checkMaxBytes: true),
                    ),
                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            'Program Studi',
                            _prodiCtrl,
                            Icons.school_outlined,
                            'Informatika',
                            action: TextInputAction.next,
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Wajib diisi';
                              if (t.length > 100) return 'Maks. 100 karakter';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            'Angkatan',
                            _angkCtrl,
                            Icons.calendar_today_outlined,
                            '2020',
                            type: TextInputType.number,
                            action: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Wajib diisi';
                              if (!RegExp(r'^\d{4}$').hasMatch(t)) {
                                return 'Harus 4 digit';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _field(
                      'Kota (opsional)',
                      _kotaCtrl,
                      Icons.location_on_outlined,
                      'Jakarta',
                      action: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      validator: (v) {
                        if (v != null && v.trim().length > 100) {
                          return 'Maksimal 100 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brandNavy,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _busy ? null : _register,
                        child: _loading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                'Daftar Sekarang',
                                style: buttonStyle.copyWith(fontSize: 15),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    GoogleContinueButton(
                      loading: _googleLoading,
                      disabled: _busy,
                      onPressed: _continueWithGoogle,
                    ),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Sudah punya akun?', style: body.copyWith(color: dim2)),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: _busy ? null : () => Navigator.pop(context),
                          child: Text(
                            'Masuk',
                            style: body.copyWith(
                              color: brandNavy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    String labelText,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    TextInputType? type,
    TextInputAction? action,
    Iterable<String>? autofillHints,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onFieldSubmitted,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: label.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          enabled: !_busy,
          keyboardType: type,
          textInputAction: action,
          autofillHints: autofillHints,
          inputFormatters: inputFormatters,
          onFieldSubmitted: onFieldSubmitted,
          style: body,
          decoration: authInputDecoration(hint, icon),
          validator: validator,
        ),
      ],
    );
  }
}

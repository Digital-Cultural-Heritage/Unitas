import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_service.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
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
  bool _googleLoading = false;
  bool _obscure = true;
  String? _error;

  bool get _busy => _loading || _googleLoading;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;
      final res = await AuthService.login(email, pass);
      if (!mounted) return;
      if (res['require_otp'] == true) {
        final verified = await showEmailOtpSheet(
          context: context,
          email: email,
          title: 'Verifikasi Login',
          subtitle: 'Masukkan kode OTP 6 digit yang dikirim ke email kampusmu.',
          initialOtpToken: res['otp_token']?.toString(),
          initialDevOtp: res['dev_otp']?.toString(),
          onVerify: (otp, otpToken) async {
            await AuthService.login(email, pass, otp: otp, otpToken: otpToken);
          },
          onResend: () => AuthService.sendOtp(
            email: email,
            purpose: 'login',
            password: pass,
          ),
        );
        if (!mounted || !verified) return;
      }
      widget.onLoginSuccess();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'Tidak dapat terhubung ke server. Cek koneksi kamu.',
      );
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
      widget.onLoginSuccess();
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
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    // Logo / Brand
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: brandNavy,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'U',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Unitas',
                          style: GoogleFonts.outfit(
                            color: brandNavy,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text('Selamat datang kembali', style: heading),
                    const SizedBox(height: 6),
                    Text(
                      'Masuk untuk melanjutkan',
                      style: body.copyWith(color: dim2),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: brandNavy.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: brandNavy.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.school_outlined,
                              size: 16,
                              color: brandNavy,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Khusus civitas & alumni Unud (@unud.ac.id atau @student.unud.ac.id). Pengguna baru bisa langsung masuk 1 klik lewat Google tanpa daftar manual.',
                              style: caption.copyWith(
                                color: brandNavy,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

                    if (_error != null) ...[
                      AuthErrorBanner(message: _error!),
                      const SizedBox(height: 16),
                    ],

                    // Email
                    Text('Email Kampus', style: label.copyWith(fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _emailCtrl,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      style: body,
                      decoration: authInputDecoration(
                        'nama@student.unud.ac.id',
                        Icons.email_outlined,
                      ),
                      validator: validateAuthEmail,
                    ),
                    const SizedBox(height: 18),

                    // Password
                    Text('Kata Sandi', style: label.copyWith(fontSize: 13)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _passCtrl,
                      enabled: !_busy,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _login(),
                      style: body,
                      decoration: authInputDecoration(
                        '••••••••',
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
                      validator: (v) => validateAuthPassword(v),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _busy ? null : _openForgotPasswordSheet,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          'Lupa kata sandi?',
                          style: caption.copyWith(
                            color: brandNavy,
                            fontWeight: FontWeight.w600,
                          ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: _busy ? null : _login,
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
                                'Masuk',
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

                    // Register link
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: [
                        Text(
                          'Belum punya akun?',
                          style: body.copyWith(color: dim2),
                        ),
                        GestureDetector(
                          onTap: _busy
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RegisterScreen(
                                        onRegisterSuccess:
                                            widget.onLoginSuccess,
                                      ),
                                    ),
                                  ),
                          child: Text(
                            'Daftar sekarang',
                            style: body.copyWith(
                              color: brandNavy,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openForgotPasswordSheet() async {
    final resetDone = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ForgotPasswordSheet(initialEmail: _emailCtrl.text.trim()),
    );
    if (resetDone == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password berhasil direset. Silakan login.'),
        ),
      );
    }
  }
}

class _ForgotPasswordSheet extends StatefulWidget {
  final String initialEmail;
  const _ForgotPasswordSheet({required this.initialEmail});

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl =
      TextEditingController(text: widget.initialEmail);
  final _otpCtrl = TextEditingController();
  final _newPassCtrl = TextEditingController();

  bool _otpSent = false;
  bool _busy = false;
  bool _obscurePass = true;
  String? _devOtpHint;
  String? _errMsg;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errMsg = null;
    });
    try {
      if (!_otpSent) {
        final res = await AuthService.forgotPassword(_emailCtrl.text.trim());
        if (!mounted) return;
        setState(() {
          _otpSent = true;
          _devOtpHint = res['dev_otp']?.toString();
        });
      } else {
        await AuthService.resetPassword(
          email: _emailCtrl.text.trim(),
          otp: _otpCtrl.text.trim(),
          newPassword: _newPassCtrl.text,
        );
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errMsg = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errMsg = 'Tidak dapat terhubung ke server.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
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
              Text('Reset Kata Sandi', style: heading.copyWith(fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                _otpSent
                    ? 'Masukkan kode OTP 6 digit dan kata sandi baru kamu.'
                    : 'Masukkan email terdaftar untuk menerima kode OTP.',
                style: caption,
              ),
              const SizedBox(height: 16),
              if (_errMsg != null) ...[
                AuthErrorBanner(message: _errMsg!),
                const SizedBox(height: 10),
              ],
              if (_devOtpHint != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: brandGold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Kode OTP (dev): $_devOtpHint',
                    style: label.copyWith(color: brandNavy),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _emailCtrl,
                enabled: !_otpSent && !_busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction:
                    _otpSent ? TextInputAction.next : TextInputAction.done,
                decoration: authInputDecoration(
                  'nama@student.unud.ac.id',
                  Icons.email_outlined,
                ),
                validator: validateAuthEmail,
              ),
              if (_otpSent) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _otpCtrl,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: authInputDecoration(
                    'Kode OTP 6 digit',
                    Icons.pin_outlined,
                  ),
                  validator: (v) =>
                      v != null && RegExp(r'^\d{6}$').hasMatch(v.trim())
                          ? null
                          : 'Kode OTP harus 6 digit',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPassCtrl,
                  enabled: !_busy,
                  obscureText: _obscurePass,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: authInputDecoration(
                    'Kata sandi baru (min 8 karakter)',
                    Icons.lock_outline,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePass
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: dim2,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                  validator: (v) =>
                      validateAuthPassword(v, checkMaxBytes: true),
                ),
              ],
              const SizedBox(height: 18),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _otpSent ? 'Simpan Kata Sandi Baru' : 'Kirim Kode OTP',
                        style: buttonStyle,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

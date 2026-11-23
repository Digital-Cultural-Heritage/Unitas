import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/api/api_client.dart';
import '../core/api/auth_service.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../widgets/unitas_logo.dart';
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
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSub;
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscure = true;
  String? _error;

  bool get _busy => _loading || _googleLoading;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(
        AuthService.ensureGoogleInitialized().then((_) {
          if (!mounted) return;
          _googleAuthSub = GoogleSignIn.instance.authenticationEvents.listen(
            (event) {
              if (event is GoogleSignInAuthenticationEventSignIn) {
                unawaited(_handleWebGoogleAccount(event.user));
              }
            },
            onError: (Object err) {
              if (!mounted) return;
              if (err is GoogleSignInException &&
                  err.code == GoogleSignInExceptionCode.canceled) {
                return;
              }
              final msg = err is GoogleSignInException
                  ? AuthService.mapGoogleError(err)
                  : 'Gagal masuk dengan Google. Cek koneksi atau coba lagi.';
              setState(() => _error = msg);
            },
          );
        }).catchError((_) {}),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_googleAuthSub?.cancel());
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
      final session = await AuthService.login(
        _emailCtrl.text.trim(),
        _passCtrl.text,
      );
      if (!mounted) return;
      final user = session['user'];
      if (user is Map && user['profile_completed'] == false) {
        final saved = await showGoogleOnboardingSheet(
          context: context,
          email: user['email']?.toString(),
          initialFullName: user['full_name']?.toString(),
          initialProdi: user['prodi']?.toString(),
          initialAngkatan: user['angkatan']?.toString(),
          initialKota: user['kota']?.toString(),
          initialPekerjaan: user['pekerjaan']?.toString(),
          initialPerusahaan: user['perusahaan']?.toString(),
          requirePassword: false,
          requireProfile: true,
        );
        if (!saved) {
          await AuthService.logout();
          return;
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profil alumni berhasil dilengkapi.'),
          ),
        );
      }
      if (!await AuthService.isLoggedIn() || !mounted) return;
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

  Future<void> _handleWebGoogleAccount(GoogleSignInAccount account) =>
      _runGoogleSignIn(() => AuthService.completeGoogleSignIn(account));

  Future<void> _continueWithGoogle() =>
      _runGoogleSignIn(AuthService.signInWithGoogle);

  Future<void> _runGoogleSignIn(
    Future<Map<String, dynamic>?> Function() action,
  ) async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    try {
      final session = await action();
      if (!mounted || session == null) return;
      final user = session['user'];
      final userMap = user is Map ? user : null;
      final needsPassword = userMap?['has_password'] == false;
      final needsProfile = userMap != null &&
          (userMap.containsKey('profile_completed')
              ? userMap['profile_completed'] == false
              : needsPassword);
      if (userMap != null && (needsPassword || needsProfile)) {
        final saved = await showGoogleOnboardingSheet(
          context: context,
          email: userMap['email']?.toString(),
          initialFullName: userMap['full_name']?.toString(),
          initialProdi: userMap['prodi']?.toString(),
          initialAngkatan: userMap['angkatan']?.toString(),
          initialKota: userMap['kota']?.toString(),
          initialPekerjaan: userMap['pekerjaan']?.toString(),
          initialPerusahaan: userMap['perusahaan']?.toString(),
          requirePassword: needsPassword,
          requireProfile: needsProfile,
        );
        if (!saved) {
          await AuthService.logout();
          return;
        }
        if (!mounted) return;
        final msg = needsPassword && needsProfile
            ? 'Profil dilengkapi dan kata sandi berhasil dibuat. Kamu sekarang juga bisa masuk langsung dengan email.'
            : needsPassword
                ? 'Kata sandi berhasil dibuat. Kamu sekarang juga bisa masuk dengan email.'
                : 'Profil alumni berhasil dilengkapi.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      if (!await AuthService.isLoggedIn() || !mounted) return;
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
                        const UnitasLogo(size: 44),
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
                              'Khusus civitas & alumni Unud (@unud.ac.id atau @student.unud.ac.id). Akun Google dan login email kampus otomatis terhubung ke akun yang sama.',
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
                    const SizedBox(height: 6),
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
                    Center(
                      child: Wrap(
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
  int _cooldown = 0;
  Timer? _timer;
  String? _devOtpHint;
  String? _errMsg;

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _newPassCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
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
        _startCooldown();
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

  Future<void> _resendOtp() async {
    if (_busy || _cooldown > 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errMsg = null;
    });
    try {
      final res = await AuthService.forgotPassword(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() => _devOtpHint = res['dev_otp']?.toString());
      _startCooldown();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errMsg = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errMsg = 'Gagal mengirim ulang OTP.');
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
              if (_otpSent) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: (_busy || _cooldown > 0) ? null : _resendOtp,
                  child: Text(
                    _cooldown > 0
                        ? 'Kirim Ulang OTP ($_cooldown dtk)'
                        : 'Kirim Ulang OTP',
                    style: caption.copyWith(
                      color: _cooldown > 0 ? dim2 : brandNavy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class GoogleOnboardingData {
  final String fullName;
  final String prodi;
  final String angkatan;
  final String? kota;
  final String? pekerjaan;
  final String? perusahaan;
  final String? newPassword;

  const GoogleOnboardingData({
    required this.fullName,
    required this.prodi,
    required this.angkatan,
    this.kota,
    this.pekerjaan,
    this.perusahaan,
    this.newPassword,
  });
}

Future<bool> showGoogleOnboardingSheet({
  required BuildContext context,
  String? email,
  String? initialFullName,
  String? initialProdi,
  String? initialAngkatan,
  String? initialKota,
  String? initialPekerjaan,
  String? initialPerusahaan,
  bool requirePassword = true,
  bool requireProfile = true,
  Future<void> Function(GoogleOnboardingData data)? onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: brandBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _GoogleOnboardingSheet(
      email: email,
      initialFullName: initialFullName,
      initialProdi: initialProdi,
      initialAngkatan: initialAngkatan,
      initialKota: initialKota,
      initialPekerjaan: initialPekerjaan,
      initialPerusahaan: initialPerusahaan,
      requirePassword: requirePassword,
      requireProfile: requireProfile,
      onSave: onSave ??
          (data) async {
            if (requireProfile) {
              await AuthService.completeOnboarding(
                fullName: data.fullName,
                prodi: data.prodi,
                angkatan: data.angkatan,
                kota: data.kota,
                pekerjaan: data.pekerjaan,
                perusahaan: data.perusahaan,
                newPassword: data.newPassword,
              );
            } else if (data.newPassword != null &&
                data.newPassword!.isNotEmpty) {
              await AuthService.setPassword(data.newPassword!);
            }
          },
    ),
  );
  return saved == true;
}

class _GoogleOnboardingSheet extends StatefulWidget {
  final String? email;
  final String? initialFullName;
  final String? initialProdi;
  final String? initialAngkatan;
  final String? initialKota;
  final String? initialPekerjaan;
  final String? initialPerusahaan;
  final bool requirePassword;
  final bool requireProfile;
  final Future<void> Function(GoogleOnboardingData data) onSave;

  const _GoogleOnboardingSheet({
    this.email,
    this.initialFullName,
    this.initialProdi,
    this.initialAngkatan,
    this.initialKota,
    this.initialPekerjaan,
    this.initialPerusahaan,
    required this.requirePassword,
    required this.requireProfile,
    required this.onSave,
  });

  @override
  State<_GoogleOnboardingSheet> createState() => _GoogleOnboardingSheetState();
}

class _GoogleOnboardingSheetState extends State<_GoogleOnboardingSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl =
      TextEditingController(text: widget.initialFullName ?? '');
  late final TextEditingController _prodiCtrl =
      TextEditingController(text: widget.initialProdi ?? '');
  late final TextEditingController _angkCtrl =
      TextEditingController(text: widget.initialAngkatan ?? '');
  late final TextEditingController _kotaCtrl =
      TextEditingController(text: widget.initialKota ?? '');
  late final TextEditingController _pekerjaanCtrl =
      TextEditingController(text: widget.initialPekerjaan ?? '');
  late final TextEditingController _perusahaanCtrl =
      TextEditingController(text: widget.initialPerusahaan ?? '');
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busy = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _errMsg;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _prodiCtrl.dispose();
    _angkCtrl.dispose();
    _kotaCtrl.dispose();
    _pekerjaanCtrl.dispose();
    _perusahaanCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
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
      await widget.onSave(
        GoogleOnboardingData(
          fullName: _nameCtrl.text.trim(),
          prodi: _prodiCtrl.text.trim(),
          angkatan: _angkCtrl.text.trim(),
          kota: _kotaCtrl.text.trim(),
          pekerjaan: _pekerjaanCtrl.text.trim(),
          perusahaan: _perusahaanCtrl.text.trim(),
          newPassword: widget.requirePassword ? _passCtrl.text : null,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
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
    final cleanEmail = widget.email?.trim() ?? '';
    final titleText = widget.requireProfile && widget.requirePassword
        ? 'Lengkapi Profil & Kata Sandi'
        : (widget.requireProfile
            ? 'Lengkapi Profil Alumni'
            : 'Buat Kata Sandi');

    final subtitleText = widget.requireProfile && widget.requirePassword
        ? (cleanEmail.isNotEmpty
            ? 'Lengkapi data alumni dan buat kata sandi untuk $cleanEmail agar kamu bisa masuk lewat Google maupun email langsung.'
            : 'Lengkapi data alumni dan buat kata sandi agar kamu bisa masuk lewat Google maupun email langsung.')
        : (widget.requireProfile
            ? (cleanEmail.isNotEmpty
                ? 'Lengkapi data alumni untuk akun $cleanEmail sebelum melanjutkan ke Unitas.'
                : 'Lengkapi data alumni kamu sebelum melanjutkan ke Unitas.')
            : (cleanEmail.isNotEmpty
                ? 'Akun Google ($cleanEmail) wajib membuat kata sandi sebelum melanjutkan ke Unitas.'
                : 'Akun Google kamu wajib membuat kata sandi sebelum melanjutkan ke Unitas.'));

    return PopScope(
      canPop: false,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(titleText, style: heading.copyWith(fontSize: 18)),
                  const SizedBox(height: 6),
                  Text(subtitleText, style: caption),
                  const SizedBox(height: 16),
                  if (_errMsg != null) ...[
                    AuthErrorBanner(message: _errMsg!),
                    const SizedBox(height: 12),
                  ],
                  if (widget.requireProfile) ...[
                    Text(
                      'PROFIL ALUMNI',
                      style: label.copyWith(
                        fontSize: 11,
                        color: brandNavy,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _nameCtrl,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      decoration: authInputDecoration(
                        'Nama lengkap',
                        Icons.person_outline,
                      ),
                      validator: (v) {
                        final t = v?.trim() ?? '';
                        if (t.isEmpty) return 'Nama lengkap wajib diisi';
                        if (t.length > 100) return 'Maksimal 100 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _prodiCtrl,
                            enabled: !_busy,
                            textInputAction: TextInputAction.next,
                            decoration: authInputDecoration(
                              'Program Studi',
                              Icons.school_outlined,
                            ),
                            validator: (v) {
                              final t = v?.trim() ?? '';
                              if (t.isEmpty) return 'Wajib diisi';
                              if (t.length > 100) return 'Maks. 100 karakter';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _angkCtrl,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            decoration: authInputDecoration(
                              'Angkatan',
                              Icons.calendar_today_outlined,
                            ),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _kotaCtrl,
                      enabled: !_busy,
                      textInputAction: TextInputAction.next,
                      decoration: authInputDecoration(
                        'Kota Domisili (opsional)',
                        Icons.location_on_outlined,
                      ),
                      validator: (v) {
                        if (v != null && v.trim().length > 100) {
                          return 'Maksimal 100 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _pekerjaanCtrl,
                            enabled: !_busy,
                            textInputAction: TextInputAction.next,
                            decoration: authInputDecoration(
                              'Pekerjaan (opsional)',
                              Icons.work_outline,
                            ),
                            validator: (v) {
                              if (v != null && v.trim().length > 100) {
                                return 'Maks. 100 karakter';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _perusahaanCtrl,
                            enabled: !_busy,
                            textInputAction: widget.requirePassword
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onFieldSubmitted: widget.requirePassword
                                ? null
                                : (_) => _submit(),
                            decoration: authInputDecoration(
                              'Perusahaan (opsional)',
                              Icons.business_outlined,
                            ),
                            validator: (v) {
                              if (v != null && v.trim().length > 100) {
                                return 'Maks. 100 karakter';
                              }
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (widget.requireProfile && widget.requirePassword)
                    const SizedBox(height: 18),
                  if (widget.requirePassword) ...[
                    Text(
                      'KATA SANDI AKUN',
                      style: label.copyWith(
                        fontSize: 11,
                        color: brandNavy,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Gunakan kata sandi ini agar kamu juga bisa masuk langsung menggunakan email kampus.',
                      style: caption.copyWith(fontSize: 11.5),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passCtrl,
                      enabled: !_busy,
                      obscureText: _obscurePass,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      enabled: !_busy,
                      obscureText: _obscureConfirm,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: authInputDecoration(
                        'Konfirmasi kata sandi',
                        Icons.lock_outline,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: dim2,
                            size: 18,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) {
                          return 'Konfirmasi kata sandi wajib diisi';
                        }
                        if (v != _passCtrl.text) {
                          return 'Konfirmasi kata sandi tidak cocok';
                        }
                        return null;
                      },
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
                      elevation: 0,
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
                        : Text('Simpan & Lanjutkan', style: buttonStyle),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, false),
                    child: Text(
                      'Keluar',
                      style: caption.copyWith(
                        color: dim2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showSetPasswordSheet({
  required BuildContext context,
  String? email,
  bool isPostLoginPrompt = false,
  Future<void> Function(String newPassword)? onSave,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: !isPostLoginPrompt,
    enableDrag: !isPostLoginPrompt,
    backgroundColor: brandBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SetPasswordSheet(
      email: email,
      isPostLoginPrompt: isPostLoginPrompt,
      onSave: onSave ?? AuthService.setPassword,
    ),
  );
  return saved == true;
}

class _SetPasswordSheet extends StatefulWidget {
  final String? email;
  final bool isPostLoginPrompt;
  final Future<void> Function(String newPassword) onSave;

  const _SetPasswordSheet({
    this.email,
    required this.isPostLoginPrompt,
    required this.onSave,
  });

  @override
  State<_SetPasswordSheet> createState() => _SetPasswordSheetState();
}

class _SetPasswordSheetState extends State<_SetPasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _busy = false;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  String? _errMsg;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
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
      await widget.onSave(_passCtrl.text);
      if (!mounted) return;
      Navigator.pop(context, true);
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
    final cleanEmail = widget.email?.trim() ?? '';
    final subtitleText = widget.isPostLoginPrompt
        ? (cleanEmail.isNotEmpty
            ? 'Akun Google ($cleanEmail) wajib membuat kata sandi sebelum melanjutkan ke Unitas.'
            : 'Akun Google kamu wajib membuat kata sandi sebelum melanjutkan ke Unitas.')
        : (cleanEmail.isNotEmpty
            ? 'Akun Google ($cleanEmail) belum memiliki kata sandi. Buat kata sandi sekarang agar kamu juga bisa masuk pakai email dan kata sandi.'
            : 'Akun Google kamu belum memiliki kata sandi. Buat kata sandi sekarang agar kamu juga bisa masuk pakai email dan kata sandi.');

    return PopScope(
      canPop: !widget.isPostLoginPrompt && !_busy,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Buat Kata Sandi',
                    style: heading.copyWith(fontSize: 18),
                  ),
                  const SizedBox(height: 6),
                  Text(subtitleText, style: caption),
                  const SizedBox(height: 16),
                  if (_errMsg != null) ...[
                    AuthErrorBanner(message: _errMsg!),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _passCtrl,
                    enabled: !_busy,
                    obscureText: _obscurePass,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
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
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    enabled: !_busy,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: authInputDecoration(
                      'Konfirmasi kata sandi',
                      Icons.lock_outline,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: dim2,
                          size: 18,
                        ),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'Konfirmasi kata sandi wajib diisi';
                      }
                      if (v != _passCtrl.text) {
                        return 'Konfirmasi kata sandi tidak cocok';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: brandNavy,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
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
                        : Text('Simpan Kata Sandi', style: buttonStyle),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.pop(context, false),
                    child: Text(
                      widget.isPostLoginPrompt ? 'Keluar' : 'Batal',
                      style: caption.copyWith(
                        color: dim2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

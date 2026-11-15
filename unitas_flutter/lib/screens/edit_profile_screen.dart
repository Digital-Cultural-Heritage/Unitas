import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../core/api/api_client.dart';
import '../core/utils/image_validator.dart';
import '../widgets/avatar.dart';
import '../widgets/image_cropper_dialog.dart';

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> initialProfile;
  const EditProfileScreen({super.key, required this.initialProfile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _prodiCtrl;
  late final TextEditingController _angkatanCtrl;
  late final TextEditingController _pekerjaanCtrl;
  late final TextEditingController _perusahaanCtrl;
  late final TextEditingController _kotaCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _linkedinCtrl;
  XFile? _pickedAvatar;
  Uint8List? _pickedAvatarBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _nameCtrl = TextEditingController(text: p['full_name']?.toString() ?? '');
    _prodiCtrl = TextEditingController(text: p['prodi']?.toString() ?? '');
    _angkatanCtrl = TextEditingController(text: p['angkatan']?.toString() ?? '');
    _pekerjaanCtrl = TextEditingController(text: p['pekerjaan']?.toString() ?? '');
    _perusahaanCtrl = TextEditingController(text: p['perusahaan']?.toString() ?? '');
    _kotaCtrl = TextEditingController(text: p['kota']?.toString() ?? '');
    _bioCtrl = TextEditingController(text: p['bio']?.toString() ?? '');
    _linkedinCtrl = TextEditingController(text: p['linkedin']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _prodiCtrl.dispose();
    _angkatanCtrl.dispose();
    _pekerjaanCtrl.dispose();
    _perusahaanCtrl.dispose();
    _kotaCtrl.dispose();
    _bioCtrl.dispose();
    _linkedinCtrl.dispose();
    super.dispose();
  }

  String _initials() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return '?';
    final parts = name.split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name[0].toUpperCase();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    try {
      ImageValidator.validate(bytes, picked.name);
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (!mounted) return;
    final cropped = await showImageCropDialog(
      context,
      bytes,
      aspectRatio: 1.0,
      isCircle: true,
      title: 'Sesuaikan Foto Profil',
    );
    if (cropped != null && mounted) {
      setState(() {
        _pickedAvatar = picked;
        _pickedAvatarBytes = cropped;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      if (_pickedAvatar != null) {
        final bytes = _pickedAvatarBytes ?? await _pickedAvatar!.readAsBytes();
        await UsersService.uploadAvatar(bytes, 'avatar.png');
      }

      final body = {
        'full_name': _nameCtrl.text.trim(),
        'prodi': _prodiCtrl.text.trim(),
        'angkatan': _angkatanCtrl.text.trim(),
        'pekerjaan': _pekerjaanCtrl.text.trim(),
        'perusahaan': _perusahaanCtrl.text.trim(),
        'kota': _kotaCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'linkedin': _linkedinCtrl.text.trim(),
      };

      await UsersService.updateMe(body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profil berhasil diperbarui')),
        );
        Navigator.pop(context, true);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
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
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: brandBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: brandNavy),
        title: Text('Edit Profil', style: subTitle.copyWith(fontSize: 17)),
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
                  child: Text('Simpan', style: buttonStyle.copyWith(color: brandNavy)),
                ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Avatar Preview + Ganti Foto
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _pickAvatar,
                          child: Stack(
                            children: [
                              if (_pickedAvatarBytes != null)
                                ClipOval(
                                  child: Image.memory(
                                    _pickedAvatarBytes!,
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              else if (widget.initialProfile['avatar_url'] != null &&
                                  widget.initialProfile['avatar_url'].toString().isNotEmpty)
                                ClipOval(
                                  child: Image.network(
                                    widget.initialProfile['avatar_url'],
                                    width: 76,
                                    height: 76,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => UnitasAvatar(
                                      initials: widget.initialProfile['initials']?.toString() ?? _initials(),
                                      color: brandNavy,
                                      size: 76,
                                    ),
                                  ),
                                )
                              else
                                UnitasAvatar(
                                  initials: widget.initialProfile['initials']?.toString() ?? _initials(),
                                  color: brandNavy,
                                  size: 76,
                                ),
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: brandNavy,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: brandBg, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _pickAvatar,
                          icon: const Icon(Icons.photo_library_outlined, size: 16, color: brandNavy),
                          label: Text(
                            _pickedAvatarBytes != null ? 'Ganti Foto Terpilih' : 'Ubah Foto Profil',
                            style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          _nameCtrl.text.isEmpty ? 'Profil Alumni' : _nameCtrl.text,
                          style: subTitle.copyWith(fontSize: 16),
                        ),
                        if (_prodiCtrl.text.isNotEmpty || _angkatanCtrl.text.isNotEmpty)
                          Text(
                            [_prodiCtrl.text, _angkatanCtrl.text]
                                .where((e) => e.isNotEmpty)
                                .join(' · '),
                            style: caption,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Bagian 1: Identitas Alumni
                  _sectionTitle('IDENTITAS ALUMNI'),
                  const SizedBox(height: 12),
                  _field(
                    'Nama Lengkap',
                    _nameCtrl,
                    Icons.person_outline,
                    'Nama lengkap',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _field(
                          'Program Studi',
                          _prodiCtrl,
                          Icons.school_outlined,
                          'Contoh: Informatika',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _field(
                          'Angkatan',
                          _angkatanCtrl,
                          Icons.calendar_today_outlined,
                          '2020',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Bagian 2: Karier & Domisili
                  _sectionTitle('KARIER & DOMISILI'),
                  const SizedBox(height: 12),
                  _field(
                    'Pekerjaan / Jabatan',
                    _pekerjaanCtrl,
                    Icons.work_outline,
                    'Contoh: Software Engineer',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    'Perusahaan',
                    _perusahaanCtrl,
                    Icons.business_outlined,
                    'Contoh: PT Teknologi Indonesia',
                  ),
                  const SizedBox(height: 14),
                  _field(
                    'Kota Domisili',
                    _kotaCtrl,
                    Icons.location_on_outlined,
                    'Contoh: Jakarta',
                  ),
                  const SizedBox(height: 24),

                  // Bagian 3: Sosial & Bio
                  _sectionTitle('SOSIAL & TENTANG SAYA'),
                  const SizedBox(height: 12),
                  _field(
                    'URL LinkedIn',
                    _linkedinCtrl,
                    Icons.link,
                    'https://linkedin.com/in/username',
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return null;
                      final val = v.trim();
                      if (!val.startsWith('http://') && !val.startsWith('https://')) {
                        return 'Awali URL dengan http:// atau https://';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  Text('Bio Singkat', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    style: body.copyWith(color: textPrimary),
                    decoration: _inputDeco('Ceritakan sedikit tentang dirimu...').copyWith(
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(bottom: 50),
                        child: Icon(Icons.description_outlined, color: dim2, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Tombol Simpan Penuh di Bawah
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandNavy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _loading ? null : _submit,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text('Simpan Perubahan', style: buttonStyle.copyWith(fontSize: 14)),
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

  Widget _field(
    String label_,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    String? Function(String?)? validator,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label_, style: label.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
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
}

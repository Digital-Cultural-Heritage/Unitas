import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/api_client.dart';
import '../core/api/posts_service.dart';
import '../core/utils/image_validator.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl = TextEditingController();

  String _category = 'Seminar';
  static const List<String> _cats = ['Reuni', 'Seminar', 'Networking', 'Webinar'];

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isOnline = false;
  bool _loading = false;
  bool _picking = false;
  XFile? _bannerFile;
  Uint8List? _bannerBytes;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBanner() async {
    if (_picking || _loading) return;
    _picking = true;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2048,
        maxHeight: 2048,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      try {
        ImageValidator.validate(bytes, picked.name);
      } on ImageValidationException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _bannerFile = picked;
        _bannerBytes = bytes;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memilih gambar banner')),
        );
      }
    } finally {
      _picking = false;
    }
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = _date != null && !_date!.isBefore(today)
        ? _date!
        : today.add(const Duration(days: 1));
    final dt = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: brandNavy),
          ),
          child: child!,
        );
      },
    );
    if (dt != null && mounted) setState(() => _date = dt);
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (_endTime ?? const TimeOfDay(hour: 12, minute: 0)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: brandNavy),
          ),
          child: child!,
        );
      },
    );
    if (t != null && mounted) {
      setState(() {
        if (isStart) {
          _startTime = t;
        } else {
          _endTime = t;
        }
      });
    }
  }

  String _formatDateApi(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatDateDisplay(DateTime? dt) {
    if (dt == null) return 'Pilih Tanggal';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(TimeOfDay? t) {
    if (t == null) return 'Pilih Waktu';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanggal acara wajib diisi')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      String? coverUrl;
      if (_bannerFile != null) {
        final bytes = _bannerBytes ?? await _bannerFile!.readAsBytes();
        coverUrl = await PostsService.uploadImage(bytes, 'banner.png');
      }

      final body = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'event_date': _formatDateApi(_date),
        'location': _locCtrl.text.trim(),
        'is_online': _isOnline,
      };
      if (_startTime != null) body['start_time'] = _formatTime(_startTime);
      if (_endTime != null) body['end_time'] = _formatTime(_endTime);
      if (coverUrl != null) body['cover_url'] = coverUrl;

      await ApiClient.post('/api/events', body: body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acara berhasil dibuat!')),
        );
        Navigator.pop(context, true);
      }
    } on ImageValidationException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
        title: Text('Buat Acara', style: subTitle.copyWith(fontSize: 17)),
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
                  // Pamflet / Banner Acara (Upload Gambar Sendiri)
                  Text('Pamflet / Banner Acara (Opsional)', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickBanner,
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: _bannerBytes != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image.memory(
                                    _bannerBytes!,
                                    fit: BoxFit.contain,
                                    cacheWidth: 1200,
                                    gaplessPlayback: true,
                                  ),
                                ),
                                Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Row(
                                    children: [
                                      _bannerActionBtn(
                                        icon: Icons.edit_outlined,
                                        label: 'Ganti',
                                        onTap: _pickBanner,
                                      ),
                                      const SizedBox(width: 6),
                                      _bannerActionBtn(
                                        icon: Icons.close,
                                        label: 'Hapus',
                                        onTap: () => setState(() {
                                          _bannerFile = null;
                                          _bannerBytes = null;
                                        }),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: brandGold.withValues(alpha: 0.16),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add_photo_alternate_outlined, color: brandNavy, size: 24),
                                ),
                                const SizedBox(height: 8),
                                Text('Pilih Pamflet / Banner Acara', style: subTitle.copyWith(fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text('Mendukung poster portrait maupun landscape', style: caption),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Kategori
                  Text('Kategori Acara', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _cats.map((c) {
                      final selected = _category == c;
                      return InkWell(
                        onTap: () => setState(() => _category = c),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
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
                  const SizedBox(height: 20),

                  // Judul
                  _field(
                    'Judul Acara',
                    _titleCtrl,
                    Icons.title,
                    'Contoh: Temu Kangen Angkatan 2018',
                    validator: (v) => v == null || v.trim().isEmpty ? 'Judul wajib diisi' : null,
                  ),
                  const SizedBox(height: 16),

                  // Tanggal
                  Text('Tanggal', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, size: 16, color: dim2),
                          const SizedBox(width: 10),
                          Text(
                            _formatDateDisplay(_date),
                            style: body.copyWith(color: _date == null ? dim2 : textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Jam Mulai & Jam Selesai
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Jam Mulai', style: label.copyWith(fontSize: 13)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickTime(true),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, size: 16, color: dim2),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatTime(_startTime),
                                      style: body.copyWith(color: _startTime == null ? dim2 : textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Jam Selesai', style: label.copyWith(fontSize: 13)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => _pickTime(false),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                decoration: BoxDecoration(
                                  color: surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.access_time, size: 16, color: dim2),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatTime(_endTime),
                                      style: body.copyWith(color: _endTime == null ? dim2 : textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Lokasi / Link Meeting (dinamis sesuai checkbox)
                  _field(
                    _isOnline ? 'Link Meeting' : 'Lokasi Acara',
                    _locCtrl,
                    _isOnline ? Icons.videocam_outlined : Icons.location_on_outlined,
                    _isOnline ? 'Contoh: https://zoom.us/j/...' : 'Contoh: Aula Barat ITB atau IMAX Jakarta',
                    validator: (v) => v == null || v.trim().isEmpty
                        ? (_isOnline ? 'Link meeting wajib diisi' : 'Lokasi wajib diisi')
                        : null,
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () => setState(() => _isOnline = !_isOnline),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _isOnline,
                          activeColor: brandNavy,
                          onChanged: (v) => setState(() => _isOnline = v ?? false),
                        ),
                        Expanded(
                          child: Text(
                            'Acara ini diselenggarakan secara online (virtual)',
                            style: caption.copyWith(color: dim1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Deskripsi
                  Text('Deskripsi Acara', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _descCtrl,
                    maxLines: 4,
                    style: body.copyWith(color: textPrimary),
                    decoration: _inputDeco('Ceritakan detail acaramu...'),
                  ),
                  const SizedBox(height: 28),

                  // Tombol Publikasikan Acara penuh di bawah
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
                          : Text('Publikasikan Acara', style: buttonStyle.copyWith(fontSize: 14)),
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

  Widget _bannerActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 4),
            Text(label, style: caption.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label_,
    TextEditingController ctrl,
    IconData icon,
    String hint, {
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label_, style: label.copyWith(fontSize: 13)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
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

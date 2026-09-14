import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/api_client.dart';

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
  final List<String> _cats = ['Reuni', 'Seminar', 'Networking', 'Webinar'];

  DateTime? _date;
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  bool _isOnline = false;
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: brandNavy),
          ),
          child: child!,
        );
      },
    );
    if (dt != null) setState(() => _date = dt);
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart
          ? const TimeOfDay(hour: 9, minute: 0)
          : const TimeOfDay(hour: 12, minute: 0),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(primary: brandNavy),
          ),
          child: child!,
        );
      },
    );
    if (t != null) {
      setState(() {
        if (isStart) _startTime = t;
        else _endTime = t;
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Pilih Tanggal';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  String _formatTime(TimeOfDay? t) {
    if (t == null) return 'Pilih Waktu';
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tanggal acara wajib diisi'))
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final body = {
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'category': _category,
        'event_date': _formatDate(_date),
        'location': _locCtrl.text.trim(),
        'is_online': _isOnline,
      };
      if (_startTime != null) body['start_time'] = _formatTime(_startTime);
      if (_endTime != null) body['end_time'] = _formatTime(_endTime);

      await ApiClient.post('/api/events', body: body);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acara berhasil dibuat!'))
        );
        Navigator.pop(context, true); // return true = success
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message))
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Terjadi kesalahan'))
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
        title: Text('Buat Acara', style: label),
        actions: [
          _loading
            ? const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Center(child: SizedBox(width: 20, height: 20, 
                  child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2))),
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
            // Kategori
            Text('Kategori Acara', style: label.copyWith(fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _cats.map((c) => GestureDetector(
                onTap: () => setState(() => _category = c),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: _category == c ? brandNavy : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _category == c ? brandNavy : borderColor),
                  ),
                  child: Text(c, style: caption.copyWith(
                    color: _category == c ? Colors.white : dim2,
                    fontWeight: _category == c ? FontWeight.w600 : FontWeight.w400,
                  )),
                ),
              )).toList(),
            ),
            const SizedBox(height: 24),

            // Judul
            _field('Judul Acara', _titleCtrl, Icons.title, 'Contoh: Temu Kangen Angkatan 2018',
              validator: (v) => v == null || v.isEmpty ? 'Judul wajib diisi' : null),
            const SizedBox(height: 16),

            // Tanggal & Waktu
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tanggal', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: surface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        Icon(Icons.calendar_today, size: 16, color: dim2),
                        const SizedBox(width: 8),
                        Text(_formatDate(_date), style: body.copyWith(
                          color: _date == null ? dim2 : textPrimary)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Jam Mulai', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _pickTime(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: surface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        Icon(Icons.access_time, size: 16, color: dim2),
                        const SizedBox(width: 8),
                        Text(_formatTime(_startTime), style: body.copyWith(
                          color: _startTime == null ? dim2 : textPrimary)),
                      ]),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Jam Selesai', style: label.copyWith(fontSize: 13)),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => _pickTime(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      decoration: BoxDecoration(
                        color: surface, borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(children: [
                        Icon(Icons.access_time, size: 16, color: dim2),
                        const SizedBox(width: 8),
                        Text(_formatTime(_endTime), style: body.copyWith(
                          color: _endTime == null ? dim2 : textPrimary)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ]),
            const SizedBox(height: 16),

            // Lokasi
            _field('Lokasi / Link Meeting', _locCtrl, Icons.location_on_outlined, 'Contoh: Aula Barat ITB atau Link Zoom',
              validator: (v) => v == null || v.isEmpty ? 'Lokasi wajib diisi' : null),
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(
                value: _isOnline,
                activeColor: brandNavy,
                onChanged: (v) => setState(() => _isOnline = v ?? false),
              ),
              Text('Acara ini diselenggarakan secara online (virtual)', style: caption),
            ]),
            const SizedBox(height: 16),

            // Deskripsi
            Text('Deskripsi Acara', style: label.copyWith(fontSize: 13)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descCtrl,
              maxLines: 4,
              style: body,
              decoration: _inputDeco('Ceritakan detail acaramu...').copyWith(
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

  Widget _field(
    String label_, TextEditingController ctrl, IconData icon, String hint, {
    String? Function(String?)? validator,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label_, style: label.copyWith(fontSize: 13)),
      const SizedBox(height: 6),
      TextFormField(
        controller: ctrl,
        style: body,
        decoration: _inputDeco(hint).copyWith(
          prefixIcon: Icon(icon, color: dim2, size: 18),
        ),
        validator: validator,
      ),
    ]);
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

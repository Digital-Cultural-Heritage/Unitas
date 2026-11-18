import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import 'chat_room_screen.dart';

class AlumniProfileScreen extends StatefulWidget {
  final String userId;
  final Map<String, dynamic>? initialProfile;

  const AlumniProfileScreen({
    super.key,
    required this.userId,
    this.initialProfile,
  });

  @override
  State<AlumniProfileScreen> createState() => _AlumniProfileScreenState();
}

class _AlumniProfileScreenState extends State<AlumniProfileScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _connecting = false;
  String _connStatus = 'none';
  String? _error;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _connStatus = (widget.initialProfile?['connection_status'] ?? 'none').toString();
    _load();
  }

  Future<void> _load() async {
    if (mounted && (_error != null || !_loading && _profile == null)) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await UsersService.getUserById(widget.userId);
      if (mounted) {
        setState(() {
          _profile = data;
          _connStatus = (data['connection_status'] ?? 'none').toString();
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_profile == null) {
            _error = 'Gagal memuat profil alumni';
          }
        });
        if (_profile != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memperbarui profil alumni')),
          );
        }
      }
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final res = await UsersService.connect(widget.userId);
      final conn = res['connection'];
      final serverStatus = conn is Map ? conn['status']?.toString() : null;
      final msg = (res['message'] ?? '').toString();
      final nextStatus = (serverStatus == 'accepted' ||
              msg == 'Sudah terhubung' ||
              msg == 'Koneksi diterima')
          ? 'accepted'
          : 'pending';
      if (mounted) {
        setState(() {
          _connStatus = nextStatus;
          _connecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg.isNotEmpty ? msg : 'Permintaan koneksi dikirim')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  String _initials(Map<String, dynamic>? p) {
    final ini = (p?['initials'] ?? '').toString().trim();
    if (ini.isNotEmpty) return ini;
    final name = (p?['full_name'] ?? '').toString().trim();
    if (name.isEmpty) return 'AL';
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  String _titleCase(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    return t
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final coverCacheW = (600 * dpr).round().clamp(600, 1200);
    final avatarCacheW = (70 * dpr).round();
    final p = _profile ?? {};
    final rawName = (p['full_name'] ?? '').toString().trim();
    final name = rawName.isEmpty ? 'Alumni Unitas' : rawName;
    final prodi = _titleCase((p['prodi'] ?? '').toString());
    final angkatan = (p['angkatan'] ?? '').toString().trim();
    final kota = _titleCase((p['kota'] ?? '').toString());
    final pekerjaan = (p['pekerjaan'] ?? '').toString().trim();
    final perusahaan = (p['perusahaan'] ?? '').toString().trim();
    final bio = (p['bio'] ?? '').toString().trim();
    final linkedin = (p['linkedin'] ?? '').toString().trim();
    final avatarUrl = p['avatar_url']?.toString().trim();
    final points = (p['points'] ?? 0).toString();

    final jobLine = [pekerjaan, perusahaan].where((e) => e.isNotEmpty).join(' Â· ');
    final eduLine = [prodi, angkatan].where((e) => e.isNotEmpty).join(' Â· ');

    final isConnected = _connStatus == 'accepted';
    final isPending = _connStatus == 'pending';
    final isIncoming = _connStatus == 'incoming';

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        title: Text('Profil Alumni', style: heading.copyWith(fontSize: 18)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: RefreshIndicator(
            onRefresh: _load,
            color: brandNavy,
            child: (!_loading && _profile == null && _error != null)
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(32),
                    children: [
                      const SizedBox(height: 80),
                      Icon(Icons.error_outline, size: 42, color: dim2),
                      const SizedBox(height: 12),
                      Text(_error!, style: subTitle, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Center(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandNavy,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                          onPressed: _load,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: Text('Coba Lagi', style: buttonStyle),
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover banner (sama seperti ProfileScreen)
                  Stack(
                    children: [
                      SizedBox(
                        height: 128,
                        width: double.infinity,
                        child: Image.network(
                          'https://images.unsplash.com/photo-1748144679532-c36d9d5584e6?w=600&h=240&fit=crop',
                          fit: BoxFit.cover,
                          cacheWidth: coverCacheW,
                          color: Colors.black54,
                          colorBlendMode: BlendMode.darken,
                          errorBuilder: (_, _, _) => Container(color: brandNavy),
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, brandBg],
                              stops: [0.45, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Profile section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
                    child: Transform.translate(
                      offset: const Offset(0, -42),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // Avatar rounded-square sama seperti ProfileScreen
                              Container(
                                width: 76,
                                height: 76,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7A4B2B),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: brandBg, width: 3),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x181E3A5F),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(17),
                                  child: avatarUrl != null && avatarUrl.isNotEmpty
                                      ? Image.network(
                                          avatarUrl,
                                          width: 70,
                                          height: 70,
                                          cacheWidth: avatarCacheW,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                          errorBuilder: (_, _, _) => Center(
                                            child: Text(
                                              _initials(p),
                                              style: heading.copyWith(color: Colors.white, fontSize: 20),
                                            ),
                                          ),
                                        )
                                      : Center(
                                          child: Text(
                                            _initials(p),
                                            style: heading.copyWith(color: Colors.white, fontSize: 20),
                                          ),
                                        ),
                                ),
                              ),

                              // Tombol Koneksi & Pesan
                              if (_loading && _profile == null)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: (isConnected || isPending) ? surface : brandNavy,
                                        foregroundColor: isConnected
                                            ? brandGreen
                                            : (isPending ? dim1 : Colors.white),
                                        disabledBackgroundColor: surface,
                                        disabledForegroundColor: isConnected ? brandGreen : dim1,
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: (isConnected || isPending)
                                              ? BorderSide(color: borderColor)
                                              : BorderSide.none,
                                        ),
                                        elevation: 0,
                                      ),
                                      onPressed: (isConnected || isPending || _connecting) ? null : _connect,
                                      icon: Icon(
                                        isConnected
                                            ? Icons.check_circle_outline
                                            : (isPending
                                                ? Icons.schedule_outlined
                                                : (isIncoming ? Icons.how_to_reg_outlined : Icons.person_add_outlined)),
                                        size: 15,
                                      ),
                                      label: Text(
                                        isConnected
                                            ? 'Terhubung'
                                            : (isPending
                                                ? 'Terkirim'
                                                : (isIncoming ? 'Terima' : 'Hubungkan')),
                                        style: buttonStyle.copyWith(
                                          fontSize: 12.5,
                                          color: isConnected
                                              ? brandGreen
                                              : (isPending ? dim1 : Colors.white),
                                        ),
                                      ),
                                    ),
                                    if (isConnected) ...[
                                      const SizedBox(width: 8),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: brandNavy,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          elevation: 0,
                                        ),
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => ChatRoomScreen(
                                                peerId: widget.userId,
                                                peerName: name,
                                                peerInitials: _initials(p),
                                                peerAvatarUrl: avatarUrl,
                                                peerSubtitle: jobLine,
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.chat_bubble_outline, size: 15),
                                        label: Text('Pesan', style: buttonStyle.copyWith(fontSize: 12.5)),
                                      ),
                                    ],
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(name, style: heading.copyWith(fontSize: 21)),
                          if (eduLine.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(eduLine, style: caption.copyWith(fontSize: 13)),
                          ],
                          if (jobLine.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(jobLine, style: body.copyWith(color: textPrimary, fontSize: 13.5)),
                          ],
                          const SizedBox(height: 16),

                          // Stats row (seragam dengan ProfileScreen)
                          Row(
                            children: [
                              _statBox(Icons.school_outlined, angkatan.isNotEmpty ? angkatan : 'â€”', 'Angkatan', isFirst: true),
                              _statBox(Icons.location_on_outlined, kota.isNotEmpty ? kota : 'â€”', 'Kota'),
                              _statBox(Icons.star_outline, points, 'Poin', isLast: true),
                            ],
                          ),
                          const SizedBox(height: 18),

                          // Tentang card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 16, color: brandNavy),
                                    const SizedBox(width: 6),
                                    Text('Tentang', style: label),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  bio.isNotEmpty ? bio : 'Alumni ini belum menambahkan bio.',
                                  style: body.copyWith(
                                    height: 1.55,
                                    color: bio.isNotEmpty ? textPrimary : dim2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Informasi Karier & Pendidikan card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.badge_outlined, size: 16, color: brandNavy),
                                    const SizedBox(width: 6),
                                    Text('Informasi Alumni', style: label),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _infoRow(Icons.school_outlined, 'Program Studi', prodi.isNotEmpty ? prodi : 'â€”'),
                                _infoRow(Icons.work_outline, 'Pekerjaan', pekerjaan.isNotEmpty ? pekerjaan : 'Belum diisi'),
                                _infoRow(Icons.business_outlined, 'Perusahaan', perusahaan.isNotEmpty ? perusahaan : 'Belum diisi'),
                                _infoRow(Icons.location_on_outlined, 'Kota', kota.isNotEmpty ? kota : 'Belum diisi'),
                                if (linkedin.isNotEmpty)
                                  InkWell(
                                    onTap: () async {
                                      await Clipboard.setData(ClipboardData(text: linkedin));
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Link LinkedIn disalin')),
                                      );
                                    },
                                    child: _infoRow(Icons.link, 'LinkedIn', linkedin, highlight: true),
                                  ),
                              ],
                            ),
                          ),
                        ],
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

  Widget _statBox(IconData icon, String val, String title, {bool isFirst = false, bool isLast = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: surface,
          border: Border(
            top: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
            left: BorderSide(color: borderColor),
            right: isLast ? BorderSide(color: borderColor) : BorderSide.none,
          ),
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(12) : Radius.zero,
            right: isLast ? const Radius.circular(12) : Radius.zero,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: brandGold),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    val,
                    style: statStyle.copyWith(fontSize: 16, color: brandNavy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(title, style: caption),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String title, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: dim2),
          const SizedBox(width: 10),
          SizedBox(
            width: 105,
            child: Text(title, style: caption),
          ),
          Expanded(
            child: Text(
              value,
              style: body.copyWith(
                fontSize: 13.5,
                color: highlight ? brandNavy : (value == 'Belum diisi' ? dim2 : textPrimary),
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

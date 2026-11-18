import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/users_service.dart';
import '../widgets/avatar.dart';
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

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await UsersService.getUserById(widget.userId);
      if (mounted) {
        setState(() {
          _profile = data;
          _connStatus = (data['connection_status'] ?? 'none').toString();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final res = await UsersService.connect(widget.userId);
      final serverStatus = res['connection']?['status']?.toString();
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
    final name = (p?['full_name'] ?? 'AL').toString().trim();
    final parts = name.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile ?? {};
    final name = (p['full_name'] ?? 'Alumni Unitas').toString();
    final prodi = (p['prodi'] ?? '').toString().trim();
    final angkatan = (p['angkatan'] ?? '').toString().trim();
    final kota = (p['kota'] ?? '').toString().trim();
    final pekerjaan = (p['pekerjaan'] ?? '').toString().trim();
    final perusahaan = (p['perusahaan'] ?? '').toString().trim();
    final bio = (p['bio'] ?? '').toString().trim();
    final linkedin = (p['linkedin'] ?? '').toString().trim();
    final avatarUrl = p['avatar_url']?.toString();

    final jobLine = [pekerjaan, perusahaan].where((e) => e.isNotEmpty).join(' · ');
    final eduLine = [prodi, angkatan].where((e) => e.isNotEmpty).join(' · ');

    final isConnected = _connStatus == 'accepted';
    final isPending = _connStatus == 'pending';
    final isIncoming = _connStatus == 'incoming';

    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        bottom: const PreferredSize(
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
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                // Header banner + avatar
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      height: 92,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [brandNavy, Color(0xFF2B5282)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: -36,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: brandBg,
                          shape: BoxShape.circle,
                        ),
                        child: UnitasAvatar(
                          initials: _initials(p),
                          color: brandNavy,
                          size: 72,
                          avatarUrl: avatarUrl,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 44),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: heading.copyWith(fontSize: 21)),
                      if (eduLine.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(eduLine, style: caption.copyWith(fontSize: 13)),
                      ],
                      if (jobLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.work_outline, size: 15, color: brandNavy),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(jobLine, style: body.copyWith(color: textPrimary, fontSize: 13.5)),
                            ),
                          ],
                        ),
                      ],
                      if (kota.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 15, color: dim1),
                            const SizedBox(width: 6),
                            Text(kota, style: caption.copyWith(fontSize: 12.5)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),

                      // Action buttons
                      if (_loading && _profile == null)
                        const Center(child: CircularProgressIndicator())
                      else
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 44,
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: (isConnected || isPending) ? surface : brandNavy,
                                    foregroundColor: isConnected
                                        ? brandGreen
                                        : (isPending ? dim1 : Colors.white),
                                    disabledBackgroundColor: surface,
                                    disabledForegroundColor: isConnected ? brandGreen : dim1,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side: (isConnected || isPending)
                                          ? const BorderSide(color: borderColor)
                                          : BorderSide.none,
                                    ),
                                  ),
                                  onPressed: (isConnected || isPending || _connecting) ? null : _connect,
                                  icon: Icon(
                                    isConnected
                                        ? Icons.check_circle_outline
                                        : (isPending
                                            ? Icons.schedule_outlined
                                            : (isIncoming ? Icons.how_to_reg_outlined : Icons.person_add_outlined)),
                                    size: 18,
                                  ),
                                  label: Text(
                                    isConnected
                                        ? 'Terhubung'
                                        : (isPending
                                            ? 'Terkirim'
                                            : (isIncoming ? 'Terima Koneksi' : 'Hubungkan')),
                                  ),
                                ),
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(width: 10),
                              Expanded(
                                child: SizedBox(
                                  height: 44,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: brandNavy,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                                    label: const Text('Kirim Pesan'),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),

                      if (bio.isNotEmpty) ...[
                        const SizedBox(height: 22),
                        Text('TENTANG', style: label),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(bio, style: body.copyWith(height: 1.5, color: textPrimary)),
                        ),
                      ],

                      if (linkedin.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text('TAUTAN', style: label),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: linkedin));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link LinkedIn disalin')),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 18, color: brandNavy),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    linkedin,
                                    style: body.copyWith(color: brandNavy, fontSize: 13.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const Icon(Icons.copy, size: 16, color: dim2),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

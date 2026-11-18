import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/messages_service.dart';
import '../widgets/avatar.dart';
import 'chat_room_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  static const _avatarColors = [
    brandNavy,
    Color(0xFF4A6B82),
    Color(0xFF7A5C3E),
    Color(0xFF5B9A6F),
    Color(0xFF6B5B8A),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await MessagesService.getConversations();
      if (mounted) {
        setState(() {
          _conversations = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic>? _extractProfile(Map<String, dynamic>? user) {
    final profiles = user?['user_profiles'];
    if (profiles is List && profiles.isNotEmpty) {
      return Map<String, dynamic>.from(profiles.first);
    }
    if (profiles is Map) {
      return Map<String, dynamic>.from(profiles);
    }
    return null;
  }

  Color _colorFor(String seed) {
    return _avatarColors[seed.hashCode.abs() % _avatarColors.length];
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Kemarin';
    return '${dt.day}/${dt.month}';
  }

  Future<void> _openRoom(Map<String, dynamic> peer, Map<String, dynamic>? profile) async {
    final peerId = (peer['id'] ?? '').toString();
    final name = (profile?['full_name'] ?? 'Alumni').toString();
    final ini = (profile?['initials'] ??
            name.substring(0, name.length >= 2 ? 2 : 1))
        .toString()
        .toUpperCase();
    final roleMeta = [
      profile?['pekerjaan'],
      profile?['perusahaan'],
    ].where((e) => e != null && e.toString().isNotEmpty).join(' · ');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatRoomScreen(
          peerId: peerId,
          peerName: name,
          peerInitials: ini,
          peerAvatarUrl: profile?['avatar_url']?.toString(),
          peerSubtitle: roleMeta,
        ),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _conversations
        : _conversations.where((c) {
            final peer = c['peer'] as Map<String, dynamic>? ?? {};
            final profile = _extractProfile(peer);
            final name = (profile?['full_name'] ?? '').toString().toLowerCase();
            final msg = (c['last_message'] ?? '').toString().toLowerCase();
            return name.contains(q) || msg.contains(q);
          }).toList();

    final activeChats = filtered.where((c) => c['last_message'] != null).toList();
    final newPeers = filtered.where((c) => c['last_message'] == null).toList();

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
        title: Text('Pesan Alumni', style: heading.copyWith(fontSize: 18)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _conversations.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 48, color: dim2),
                            const SizedBox(height: 12),
                            Text('Belum ada koneksi untuk diajak ngobrol', style: subTitle.copyWith(color: dim1)),
                            const SizedBox(height: 4),
                            Text(
                              'Terhubung dengan alumni di tab Alumni terlebih dahulu untuk mulai chat 1-on-1.',
                              style: caption,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Search Bar
                          Container(
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: borderColor),
                            ),
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (v) => setState(() => _query = v),
                              style: body.copyWith(color: textPrimary),
                              decoration: InputDecoration(
                                hintText: 'Cari nama alumni…',
                                hintStyle: caption,
                                prefixIcon: const Icon(Icons.search, color: dim2, size: 18),
                                suffixIcon: _query.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.close, size: 17, color: dim2),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _query = '');
                                        },
                                      )
                                    : null,
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 40),
                              child: Center(
                                child: Text('Tidak ada percakapan yang cocok.', style: caption),
                              ),
                            ),

                          if (newPeers.isNotEmpty) ...[
                            Text('MULAI OBROLAN BARU', style: label),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 82,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: newPeers.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 14),
                                itemBuilder: (_, i) {
                                  final peer = newPeers[i]['peer'] as Map<String, dynamic>? ?? {};
                                  final profile = _extractProfile(peer);
                                  final peerId = (peer['id'] ?? '').toString();
                                  final name = (profile?['full_name'] ?? 'Alumni').toString();
                                  final firstName = name.split(' ').first;
                                  final ini = (profile?['initials'] ??
                                          name.substring(0, name.length >= 2 ? 2 : 1))
                                      .toString()
                                      .toUpperCase();
                                  final isOnline = profile?['is_online'] == true;

                                  return InkWell(
                                    onTap: () => _openRoom(peer, profile),
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: 62,
                                      child: Column(
                                        children: [
                                          Stack(
                                            children: [
                                              UnitasAvatar(
                                                initials: ini,
                                                color: _colorFor(peerId.isNotEmpty ? peerId : name),
                                                size: 48,
                                                avatarUrl: profile?['avatar_url']?.toString(),
                                              ),
                                              if (isOnline)
                                                Positioned(
                                                  right: 1,
                                                  bottom: 1,
                                                  child: Container(
                                                    width: 12,
                                                    height: 12,
                                                    decoration: BoxDecoration(
                                                      color: brandGreen,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: brandBg, width: 2),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            firstName,
                                            style: caption.copyWith(color: textPrimary, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],

                          if (activeChats.isNotEmpty) ...[
                            Text('PERCAKAPAN TERBARU', style: label),
                            const SizedBox(height: 10),
                            ...activeChats.map((c) {
                              final peer = c['peer'] as Map<String, dynamic>? ?? {};
                              final profile = _extractProfile(peer);
                              final peerId = (peer['id'] ?? '').toString();
                              final name = (profile?['full_name'] ?? 'Alumni').toString();
                              final ini = (profile?['initials'] ??
                                      name.substring(0, name.length >= 2 ? 2 : 1))
                                  .toString()
                                  .toUpperCase();
                              final lastMsg = c['last_message']?.toString() ?? '';
                              final timeStr = _formatTime(c['last_message_at']?.toString());
                              final unread = (c['unread_count'] ?? 0) as int;
                              final isOnline = profile?['is_online'] == true;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: InkWell(
                                  onTap: () => _openRoom(peer, profile),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: unread > 0 ? brandNavy.withValues(alpha: 0.35) : borderColor,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Color(0x0A1E3A5F),
                                          blurRadius: 8,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        Stack(
                                          children: [
                                            UnitasAvatar(
                                              initials: ini,
                                              color: _colorFor(peerId.isNotEmpty ? peerId : name),
                                              size: 46,
                                              avatarUrl: profile?['avatar_url']?.toString(),
                                            ),
                                            if (isOnline)
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: BoxDecoration(
                                                    color: brandGreen,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: surface, width: 2),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: subTitle.copyWith(fontSize: 14.5),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                lastMsg,
                                                style: caption.copyWith(
                                                  color: unread > 0 ? textPrimary : dim1,
                                                  fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              timeStr,
                                              style: caption.copyWith(
                                                fontSize: 11,
                                                color: unread > 0 ? brandNavy : dim2,
                                                fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            if (unread > 0)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: brandNavy,
                                                  borderRadius: BorderRadius.circular(99),
                                                ),
                                                child: Text(
                                                  '$unread',
                                                  style: label.copyWith(color: Colors.white, fontSize: 10.5),
                                                ),
                                              )
                                            else
                                              const Icon(Icons.chevron_right, size: 16, color: dim2),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}

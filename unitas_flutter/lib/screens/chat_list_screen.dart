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
  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        title: Text('Pesan Alumni', style: heading.copyWith(fontSize: 18)),
      ),
      body: _loading
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
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final c = _conversations[i];
                      final peer = c['peer'] as Map<String, dynamic>? ?? {};
                      final profile = _extractProfile(peer);
                      final peerId = (peer['id'] ?? '').toString();
                      final name = (profile?['full_name'] ?? 'Alumni').toString();
                      final ini = (profile?['initials'] ??
                              name.substring(0, name.length >= 2 ? 2 : 1))
                          .toString()
                          .toUpperCase();
                      final lastMsg = c['last_message']?.toString();
                      final unread = (c['unread_count'] ?? 0) as int;
                      final roleMeta = [
                        profile?['pekerjaan'],
                        profile?['perusahaan'],
                      ].where((e) => e != null && e.toString().isNotEmpty).join(' @ ');

                      return InkWell(
                        onTap: () async {
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
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: unread > 0 ? brandNavy.withValues(alpha: 0.35) : borderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              UnitasAvatar(
                                initials: ini,
                                color: brandNavy,
                                size: 44,
                                avatarUrl: profile?['avatar_url']?.toString(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, style: subTitle.copyWith(fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text(
                                      lastMsg ?? (roleMeta.isNotEmpty ? roleMeta : 'Mulai percakapan'),
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
                              if (unread > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: brandNavy,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '$unread',
                                    style: label.copyWith(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

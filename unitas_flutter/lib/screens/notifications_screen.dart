import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/notifications_service.dart';
import '../widgets/avatar.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await NotificationsService.getNotifications();
      if (mounted) {
        setState(() {
          _items = (res['data'] as List? ?? []).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _markingAll = true);
    try {
      await NotificationsService.markAllAsRead();
      if (mounted) {
        setState(() {
          _items = _items.map((n) => {...n, 'is_read': true}).toList();
          _markingAll = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _markOneRead(int index) async {
    final item = _items[index];
    if (item['is_read'] == true) return;
    setState(() {
      _items[index] = {...item, 'is_read': true};
    });
    try {
      await NotificationsService.markAsRead(item['id'].toString());
    } catch (_) {}
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.chat_bubble;
      case 'connection_request':
        return Icons.person_add;
      case 'connection_accepted':
        return Icons.how_to_reg;
      case 'event_reminder':
        return Icons.event;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'like':
        return Colors.red;
      case 'comment':
        return brandNavy;
      case 'connection_request':
      case 'connection_accepted':
        return brandGreen;
      case 'event_reminder':
        return brandGold;
      default:
        return dim1;
    }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    if (diff.inDays < 7) return '${diff.inDays}h lalu';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((e) => e['is_read'] != true);

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
        title: Text('Notifikasi', style: heading.copyWith(fontSize: 18)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markingAll ? null : _markAllRead,
              child: Text(
                'Tandai dibaca',
                style: label.copyWith(color: brandNavy, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.notifications_none, size: 48, color: dim2),
                      const SizedBox(height: 12),
                      Text('Belum ada notifikasi', style: subTitle.copyWith(color: dim1)),
                      const SizedBox(height: 4),
                      Text(
                        'Aktivitas like, komentar, dan koneksi akan muncul di sini.',
                        style: caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final n = _items[i];
                      final isRead = n['is_read'] == true;
                      final type = (n['type'] ?? '').toString();
                      final actor = n['actor'] as Map<String, dynamic>?;
                      final profiles = actor?['user_profiles'];
                      final profile = profiles is List && profiles.isNotEmpty
                          ? profiles.first as Map<String, dynamic>
                          : (profiles is Map ? Map<String, dynamic>.from(profiles) : null);
                      final actorName = (profile?['full_name'] ?? 'Unitas').toString();
                      final ini = (profile?['initials'] ??
                              actorName.substring(0, actorName.length >= 2 ? 2 : 1))
                          .toString()
                          .toUpperCase();

                      return InkWell(
                        onTap: () => _markOneRead(i),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isRead ? surface : brandNavy.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isRead ? borderColor : brandNavy.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  UnitasAvatar(
                                    initials: ini,
                                    color: brandNavy,
                                    size: 40,
                                    avatarUrl: profile?['avatar_url']?.toString(),
                                  ),
                                  Positioned(
                                    right: -3,
                                    bottom: -3,
                                    child: Container(
                                      padding: const EdgeInsets.all(3),
                                      decoration: const BoxDecoration(
                                        color: surface,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _iconForType(type),
                                        size: 13,
                                        color: _colorForType(type),
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
                                      n['title']?.toString() ?? '',
                                      style: body.copyWith(
                                        fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                                        fontSize: 13.5,
                                      ),
                                    ),
                                    if (n['body'] != null && n['body'].toString().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        n['body'].toString(),
                                        style: caption,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Text(
                                      _formatTime(n['created_at']?.toString()),
                                      style: caption.copyWith(fontSize: 11, color: dim2),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(top: 6, left: 6),
                                  decoration: const BoxDecoration(
                                    color: brandNavy,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/notifications_service.dart';
import '../core/api/posts_service.dart';
import '../core/api/jobs_service.dart';
import '../widgets/avatar.dart';
import 'alumni_profile_screen.dart';
import 'events_screen.dart';
import 'jobs_screen.dart';
import 'manage_job_screen.dart';
import 'post_detail_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  bool _markingAll = false;
  String? _error;
  final Set<String> _markingIds = {};
  String? _navigatingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_items.isEmpty && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      _error = null;
    }
    try {
      final res = await NotificationsService.getNotifications();
      if (mounted) {
        setState(() {
          final raw = res['data'];
          _items = (raw is List ? raw : const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          if (_items.isEmpty) _error = 'Gagal memuat notifikasi';
        });
        if (_items.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal memperbarui notifikasi')),
          );
        }
      }
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
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
      if (mounted) {
        setState(() => _markingAll = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal menandai semua dibaca')),
        );
      }
    }
  }

  Future<void> _markOneRead(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final nid = item['id']?.toString();
    if (nid == null || nid.isEmpty) return;
    if (item['is_read'] == true || _markingIds.contains(nid)) return;

    _markingIds.add(nid);
    setState(() {
      _items[index] = {...item, 'is_read': true};
    });
    try {
      await NotificationsService.markAsRead(nid);
    } catch (_) {
      if (mounted) {
        final curIdx = _items.indexWhere((e) => e['id']?.toString() == nid);
        if (curIdx != -1) {
          setState(() {
            _items[curIdx] = {..._items[curIdx], 'is_read': false};
          });
        }
      }
    } finally {
      _markingIds.remove(nid);
    }
  }

  void _showUnavailable(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openNotificationTarget(int index) async {
    if (index < 0 || index >= _items.length) return;
    final n = _items[index];
    final nid = n['id']?.toString() ?? '';
    if (_navigatingId != null) return;

    _markOneRead(index);

    final type = (n['type'] ?? '').toString();
    final refId = (n['reference_id'] ?? '').toString().trim();
    final actorRaw = n['actor'];
    final actor = actorRaw is Map ? Map<String, dynamic>.from(actorRaw) : null;
    final actorId = (n['actor_id'] ?? actor?['id'] ?? '').toString().trim();

    if (type == 'like' || type == 'comment') {
      if (refId.isEmpty) {
        _showUnavailable('Postingan sudah tidak tersedia');
        return;
      }
      setState(() => _navigatingId = nid);
      try {
        final post = await PostsService.getPostById(refId);
        if (!mounted) return;
        if (post == null) {
          _showUnavailable('Postingan sudah tidak tersedia');
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              post: post,
              onPostDeleted: () {},
              scrollToComments: type == 'comment',
            ),
          ),
        );
      } catch (_) {
        _showUnavailable('Gagal membuka postingan');
      } finally {
        if (mounted) setState(() => _navigatingId = null);
      }
      return;
    }

    if (type == 'connection_request' || type == 'connection_accepted') {
      if (actorId.isEmpty) {
        _showUnavailable('Profil alumni tidak ditemukan');
        return;
      }
      final profiles = actor?['user_profiles'];
      final profile = profiles is List && profiles.isNotEmpty
          ? (profiles.first is Map ? Map<String, dynamic>.from(profiles.first as Map) : null)
          : (profiles is Map ? Map<String, dynamic>.from(profiles) : null);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AlumniProfileScreen(
            userId: actorId,
            initialProfile: profile != null ? {...profile, 'id': actorId} : null,
          ),
        ),
      );
      return;
    }

    if (type == 'job_application') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ManageJobScreen()),
      );
      return;
    }

    if (type == 'job_status') {
      if (refId.isEmpty) {
        _showUnavailable('Lowongan sudah tidak tersedia');
        return;
      }
      setState(() => _navigatingId = nid);
      try {
        final job = await JobsService.getJobById(refId);
        if (!mounted) return;
        if (job == null) {
          _showUnavailable('Lowongan sudah tidak tersedia');
          return;
        }
        _showJobDetailSheet(job);
      } catch (_) {
        _showUnavailable('Gagal memuat detail lowongan');
      } finally {
        if (mounted) setState(() => _navigatingId = null);
      }
      return;
    }

    if (type == 'event_reminder') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const EventsScreen()),
      );
    }
  }

  void _showJobDetailSheet(Map<String, dynamic> job) {
    final title = (job['title'] ?? 'Detail Lowongan').toString();
    final company = (job['company'] ?? '').toString();
    final location = (job['location'] ?? '').toString();
    final jobType = (job['job_type'] ?? '').toString();
    final salary = (job['salary'] ?? '').toString();
    final desc = (job['description'] ?? '').toString().trim();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: brandBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: borderColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(title, style: heading.copyWith(fontSize: 18)),
            if (company.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(company, style: subTitle.copyWith(color: brandNavy)),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (location.isNotEmpty) _jobChip(Icons.location_on_outlined, location),
                if (jobType.isNotEmpty) _jobChip(Icons.work_outline, jobType),
                if (salary.isNotEmpty) _jobChip(Icons.payments_outlined, salary),
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Text(desc, style: body.copyWith(height: 1.5)),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: brandNavy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JobsScreen()),
                  );
                },
                child: const Text('Lihat di Karier', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: dim2),
          const SizedBox(width: 5),
          Text(text, style: caption),
        ],
      ),
    );
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
      case 'job_application':
        return Icons.work;
      case 'job_status':
        return Icons.assignment_turned_in;
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
      case 'job_application':
        return brandNavy;
      case 'job_status':
        return brandGreen;
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
        bottom: PreferredSize(
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
          : _error != null && _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: dim2),
                        const SizedBox(height: 12),
                        Text(_error!, style: subTitle.copyWith(color: dim1)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: brandNavy,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _load,
                          child: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
          : _items.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 360,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.notifications_none, size: 48, color: dim2),
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
                          ),
                        ),
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
                      final actorRaw = n['actor'];
                      final actor = actorRaw is Map ? Map<String, dynamic>.from(actorRaw) : null;
                      final profiles = actor?['user_profiles'];
                      final profile = profiles is List && profiles.isNotEmpty
                          ? (profiles.first is Map ? Map<String, dynamic>.from(profiles.first as Map) : null)
                          : (profiles is Map ? Map<String, dynamic>.from(profiles) : null);
                      final rawName = (profile?['full_name'] ?? '').toString().trim();
                      final actorName = rawName.isEmpty ? 'Unitas' : rawName;
                      final rawIni = (profile?['initials'] ?? '').toString().trim();
                      final ini = (rawIni.isNotEmpty
                              ? rawIni
                              : actorName.substring(0, actorName.length >= 2 ? 2 : 1))
                          .toUpperCase();

                      return InkWell(
                        onTap: () => _openNotificationTarget(i),
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
                                      decoration: BoxDecoration(
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
                              if (_navigatingId != null && _navigatingId == n['id']?.toString())
                                const Padding(
                                  padding: EdgeInsets.only(top: 6, left: 8),
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              else if (!isRead)
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

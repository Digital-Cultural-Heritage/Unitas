import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/messages_service.dart';
import '../widgets/avatar.dart';

class ChatRoomScreen extends StatefulWidget {
  final String peerId;
  final String peerName;
  final String peerInitials;
  final String? peerAvatarUrl;
  final String? peerSubtitle;

  const ChatRoomScreen({
    super.key,
    required this.peerId,
    required this.peerName,
    required this.peerInitials,
    this.peerAvatarUrl,
    this.peerSubtitle,
  });

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with WidgetsBindingObserver {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _myId;
  bool _loading = true;
  bool _error = false;
  bool _sending = false;
  Timer? _pollTimer;

  static const _icebreakers = [
    'Halo, salam kenal!',
    'Boleh tanya soal karier / kerjaan?',
    'Lagi sibuk apa sekarang?',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final isCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (isCurrent) {
        _loadMessages(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages(silent: true);
      _startPolling();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pollTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = await AuthService.getStoredUser();
    if (!mounted) return;
    _myId = user?['id']?.toString();
    await _loadMessages();
    if (mounted) _startPolling();
  }

  bool _fetching = false; // cegah request polling menumpuk
  int _sendEpoch = 0; // respons polling lama diabaikan jika ada pesan baru terkirim

  bool _messagesChanged(List<Map<String, dynamic>> next) {
    if (next.length != _messages.length) return true;
    for (var i = 0; i < next.length; i++) {
      if (next[i]['id']?.toString() != _messages[i]['id']?.toString() ||
          next[i]['is_read'] != _messages[i]['is_read']) {
        return true;
      }
    }
    return false;
  }

  bool _isNearBottom() {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return (pos.maxScrollExtent - pos.pixels) <= 160;
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (_fetching) return;
    _fetching = true;
    final epoch = _sendEpoch;
    if (!silent && mounted && (_error || !_loading)) {
      setState(() {
        _loading = true;
        _error = false;
      });
    }
    try {
      final list = await MessagesService.getMessages(widget.peerId);
      if (mounted && epoch == _sendEpoch) {
        final changed = _messagesChanged(list);
        if (silent && !changed && !_loading && !_error) return;
        final wasEmptyOrInitial = !silent || _messages.isEmpty;
        final hasNew = list.length > _messages.length;
        final shouldScroll = wasEmptyOrInitial || (hasNew && _isNearBottom());
        setState(() {
          _messages = list;
          _loading = false;
          _error = false;
        });
        if (shouldScroll) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollCtrl.hasClients) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (_) {
      if (mounted && !silent) {
        setState(() {
          _loading = false;
          _error = _messages.isEmpty;
        });
      }
    } finally {
      _fetching = false;
    }
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final sent = await MessagesService.sendMessage(widget.peerId, text);
      if (!mounted) return;
      _sendEpoch++;
      if (preset == null) _msgCtrl.clear();
      setState(() {
        _messages = [..._messages, sent];
        _sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    }
  }

  String _formatClock(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _dateKey(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    return '${dt.year}-${dt.month}-${dt.day}';
  }

  String _formatDateLabel(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: brandBg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: borderColor),
        ),
        title: Row(
          children: [
            UnitasAvatar(
              initials: widget.peerInitials,
              color: brandNavy,
              size: 36,
              avatarUrl: widget.peerAvatarUrl,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.peerName,
                    style: subTitle.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.peerSubtitle != null && widget.peerSubtitle!.isNotEmpty)
                    Text(
                      widget.peerSubtitle!,
                      style: caption.copyWith(fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error && _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.wifi_off_rounded, size: 40, color: dim2),
                                  const SizedBox(height: 12),
                                  Text('Gagal memuat pesan', style: subTitle),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Periksa koneksi internetmu lalu coba lagi.',
                                    style: caption,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton(
                                    onPressed: () => _loadMessages(),
                                    child: const Text('Coba lagi'),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  UnitasAvatar(
                                    initials: widget.peerInitials,
                                    color: brandNavy,
                                    size: 56,
                                    avatarUrl: widget.peerAvatarUrl,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Mulai obrolan dengan ${widget.peerName}',
                                    style: subTitle.copyWith(fontSize: 15),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Pilih sapaan cepat di bawah atau tulis pesan sendiri.',
                                    style: caption,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: _icebreakers
                                        .map(
                                          (text) => ActionChip(
                                            label: Text(text, style: caption.copyWith(color: brandNavy)),
                                            backgroundColor: surface,
                                            side: BorderSide(color: borderColor),
                                            onPressed: () => _send(text),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                            itemCount: _messages.length,
                            itemBuilder: (_, i) {
                              final m = _messages[i];
                              final isMe = m['sender_id']?.toString() == _myId;
                              final isRead = m['is_read'] == true;
                              final curDate = _dateKey(m['created_at']?.toString());
                              final prevDate = i > 0 ? _dateKey(_messages[i - 1]['created_at']?.toString()) : '';
                              final showDateHeader = i == 0 || curDate != prevDate;

                              final prevSameSender = i > 0 &&
                                  !showDateHeader &&
                                  (_messages[i - 1]['sender_id']?.toString() == m['sender_id']?.toString());

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (showDateHeader)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: card,
                                            borderRadius: BorderRadius.circular(99),
                                          ),
                                          child: Text(
                                            _formatDateLabel(m['created_at']?.toString()),
                                            style: caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Align(
                                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: prevSameSender ? 4 : 10),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      constraints: const BoxConstraints(maxWidth: 420),
                                      decoration: BoxDecoration(
                                        color: isMe ? brandNavy : surface,
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 16),
                                        ),
                                        border: isMe ? null : Border.all(color: borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            m['content']?.toString() ?? '',
                                            style: body.copyWith(
                                              color: isMe ? Colors.white : textPrimary,
                                              fontSize: 14,
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                _formatClock(m['created_at']?.toString()),
                                                style: caption.copyWith(
                                                  fontSize: 10,
                                                  color: isMe ? Colors.white70 : dim2,
                                                ),
                                              ),
                                              if (isMe) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  isRead ? Icons.done_all : Icons.done,
                                                  size: 13,
                                                  color: isRead ? brandGold : Colors.white60,
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _msgCtrl,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                            hintText: 'Tulis pesan…',
                            hintStyle: caption,
                            filled: true,
                            fillColor: card,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : () => _send(),
                        style: IconButton.styleFrom(backgroundColor: brandNavy),
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/messages_service.dart';
import '../core/crypto/e2ee_service.dart';
import '../widgets/avatar.dart';
import '../widgets/linkable_text.dart';

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
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _myId;
  bool _loading = true;
  bool _error   = false;
  bool _sending = false;
  Timer? _pollTimer;

  // ── E2EE state ────────────────────────────────────────────────────────────
  SecretKey? _conversationKey;
  String? _currentPeerPubKey;
  bool _e2eeReady = false;         // sesi E2EE sudah aktif
  bool _e2eeInitializing = false;  // sedang setup kunci
  String? _e2eeNotice;             // pesan status enkripsi jika peer belum ada key

  // Cache pesan yang sudah didekripsi agar tidak pernah hilang / rusak saat key rotate
  static final Map<String, String> _decryptedCache = {};

  static const _icebreakers = [
    'Halo, salam kenal!',
    'Boleh tanya soal karier / kerjaan?',
    'Lagi sibuk apa sekarang?',
  ];

  String get _conversationId {
    final ids = [_myId ?? '', widget.peerId];
    ids.sort();
    return ids.join('_');
  }

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
      if (isCurrent) _loadMessages(silent: true);
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

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> _init() async {
    final user = await AuthService.getStoredUser();
    if (!mounted) return;
    _myId = user?['id']?.toString();

    // Setup E2EE key lalu muat pesan
    await _setupE2ee();
    await _loadMessages();
    if (mounted) _startPolling();
  }

  /// Setup sesi E2EE dengan peer.
  /// Menghitung Conversation Secret Key via ECDH X25519 + HKDF.
  Future<void> _setupE2ee([String? knownPeerPubKey]) async {
    if (!mounted) return;
    if (_myId == null) {
      final user = await AuthService.getStoredUser();
      if (!mounted) return;
      _myId = user?['id']?.toString();
    }
    setState(() => _e2eeInitializing = true);

    try {
      final myId = _myId;
      if (myId == null || myId.isEmpty) return;

      // 1. Pastikan kunci identitas kita sendiri sudah ada & terdaftar ke server
      //    URUTAN PENTING: cek server DULU, baru generate jika memang belum ada di mana pun.
      //    Ini mencegah key baru ter-generate hanya karena FlutterSecureStorage di-reset.
      if (!await E2eeService.hasIdentityKeys(myId)) {
        // Key tidak ada di lokal — cek server dulu sebelum generate baru
        final serverMyKey = await MessagesService.getMyKeyBundle();
        if (serverMyKey != null && serverMyKey['identity_public_key'] != null) {
          // Server punya key untuk akun ini tapi lokal tidak ada.
          // Private key tidak bisa direcovery — harus generate baru.
          debugPrint('[E2EE] ⚠️ Key lokal hilang tapi server masih punya key lama. '
              'Generate key baru — pesan lama dengan key ini tidak bisa didekripsi.');
        }
        await E2eeService.generateIdentityKeys(myId);
      }

      // Verifikasi & sinkronisasi key lokal dengan server
      // Jika server punya key berbeda (overwrite oleh device lain), upload ulang key lokal
      await E2eeService.verifyAndSyncKeys(
        myId,
        (bundle) => MessagesService.registerKeys(bundle),
        () => MessagesService.getMyKeyBundle(),
      );

      // 2. Ambil public key milik lawan bicara dari server / argumen
      String? peerPubKey = knownPeerPubKey;
      if (peerPubKey == null || peerPubKey.isEmpty) {
        final peerBundle = await MessagesService.getKeyBundle(widget.peerId);
        peerPubKey = peerBundle?['identity_public_key'] as String?;
      }

      if (peerPubKey == null || peerPubKey.isEmpty) {
        // Lawan bicara belum login versi baru — pesan dikirim normal (fallback)
        if (mounted) {
          setState(() {
            _e2eeReady        = false;
            _e2eeInitializing = false;
            _e2eeNotice       = 'Lawan bicara belum mengaktifkan kunci enkripsi';
          });
        }
        return;
      }

      // 3. Turunkan Secret Key percakapan (ECDH X25519)
      final convKey = await E2eeService.getConversationKey(
        myUserId: myId,
        conversationId: _conversationId,
        peerIdentityPublicKeyB64: peerPubKey,
      );

      if (mounted) {
        setState(() {
          _conversationKey   = convKey;
          _currentPeerPubKey = peerPubKey;
          _e2eeReady         = true;
          _e2eeInitializing  = false;
          _e2eeNotice        = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _e2eeReady        = false;
          _e2eeInitializing = false;
          _e2eeNotice       = 'Enkripsi tidak aktif: $e';
        });
      }
    }
  }

  // ── Load & decrypt messages ───────────────────────────────────────────────

  bool _fetching = false;
  int  _sendEpoch = 0;

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
      setState(() { _loading = true; _error = false; });
    }
    try {
      final res = await MessagesService.getMessagesWithMeta(widget.peerId);
      final raw = (res['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final latestPeerKey = res['peer_identity_public_key'] as String?;

      // Jika lawan bicara memperbarui kunci atau kita belum punya kunci, setup ulang E2EE secara otomatis
      if (latestPeerKey != null &&
          latestPeerKey.isNotEmpty &&
          latestPeerKey != _currentPeerPubKey) {
        await _setupE2ee(latestPeerKey);
      } else if (_conversationKey == null && mounted) {
        await _setupE2ee();
      }

      final decrypted = await _decryptMessages(raw);

      if (mounted && epoch == _sendEpoch) {
        final changed = _messagesChanged(decrypted);
        if (silent && !changed && !_loading && !_error) return;
        final wasEmptyOrInitial = !silent || _messages.isEmpty;
        final hasNew = decrypted.length > _messages.length;
        final shouldScroll = wasEmptyOrInitial || (hasNew && _isNearBottom());
        setState(() {
          _messages = decrypted;
          _loading  = false;
          _error    = false;
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
        setState(() { _loading = false; _error = _messages.isEmpty; });
      }
    } finally {
      _fetching = false;
    }
  }

  /// Dekripsi pesan dari server.
  /// Pesan yang terenkripsi di database otomatis didekripsi menjadi teks yang
  /// terbaca jelas dan normal di layar chat!
  Future<List<Map<String, dynamic>>> _decryptMessages(
    List<Map<String, dynamic>> raw,
  ) async {
    final result = <Map<String, dynamic>>[];
    var key = _conversationKey;

    for (final m in raw) {
      final msgId      = m['id']?.toString() ?? '';
      final ciphertext = m['ciphertext'] as String?;
      final nonce      = m['nonce'] as String?;
      final content    = m['content'] as String?;

      // 1. Cek cache plaintext yang sudah pernah berhasil didekripsi sebelumnya
      if (msgId.isNotEmpty && _decryptedCache.containsKey(msgId)) {
        result.add({...m, 'displayText': _decryptedCache[msgId]!});
        continue;
      }

      if (ciphertext != null && nonce != null) {
        if (key != null) {
          try {
            // Dekripsi ciphertext dari database menjadi teks asli
            final plain = await E2eeService.decryptMessage(
              ciphertextB64: ciphertext,
              nonceB64: nonce,
              conversationKey: key,
            );
            if (msgId.isNotEmpty) _decryptedCache[msgId] = plain;
            result.add({...m, 'displayText': plain});
          } catch (e) {
            // Coba re-fetch public key lawan bicara dari server sekali lagi (auto-retry)
            var decryptedOnRetry = false;
            try {
              final freshBundle = await MessagesService.getKeyBundle(widget.peerId);
              final freshPubKey = freshBundle?['identity_public_key'] as String?;
              if (freshPubKey != null &&
                  freshPubKey.isNotEmpty &&
                  freshPubKey != _currentPeerPubKey &&
                  _myId != null) {
                final freshKey = await E2eeService.getConversationKey(
                  myUserId: _myId!,
                  conversationId: _conversationId,
                  peerIdentityPublicKeyB64: freshPubKey,
                );
                final retryPlain = await E2eeService.decryptMessage(
                  ciphertextB64: ciphertext,
                  nonceB64: nonce,
                  conversationKey: freshKey,
                );
                key = freshKey;
                _conversationKey = freshKey;
                _currentPeerPubKey = freshPubKey;
                if (msgId.isNotEmpty) _decryptedCache[msgId] = retryPlain;
                result.add({...m, 'displayText': retryPlain});
                decryptedOnRetry = true;
              }
            } catch (_) {}

            if (!decryptedOnRetry) {
              debugPrint('[E2EE] Gagal dekripsi pesan id=$msgId: $e');
              result.add({...m, 'displayText': content ?? '🔒 Pesan terenkripsi (kunci perangkat telah berganti)'});
            }
          }
        } else {
          // Kunci belum didapat (lawan bicara belum register / sedang dimuat)
          result.add({...m, 'displayText': content ?? '🔒 Pesan terenkripsi (sedang memuat kunci…)'});
        }
      } else if (content != null) {
        if (msgId.isNotEmpty) _decryptedCache[msgId] = content;
        result.add({...m, 'displayText': content});
      } else {
        result.add({...m, 'displayText': ''});
      }
    }

    return result;
  }

  // ── Send message ──────────────────────────────────────────────────────────

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _msgCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      Map<String, dynamic> sent;

      if (_e2eeReady && _conversationKey != null) {
        // ── E2EE: Enkripsi teks sebelum kirim ke server ──────────────────
        // Database Supabase hanya menerima ciphertext & nonce acak
        final encrypted = await E2eeService.encryptMessage(
          plaintext: text,
          conversationKey: _conversationKey!,
        );

        sent = await MessagesService.sendEncryptedMessage(widget.peerId, {
          'ciphertext': encrypted['ciphertext'],
          'nonce': encrypted['nonce'],
        });

        final sentId = sent['id']?.toString() ?? '';
        if (sentId.isNotEmpty) {
          _decryptedCache[sentId] = text;
        }

        // Bubble chat di HP pengirim langsung menampilkan teks asli yang bisa dibaca
        sent = {...sent, 'displayText': text};
      } else {
        // ── Fallback pesan biasa jika lawan bicara belum ada kunci ────────
        sent = await MessagesService.sendMessage(widget.peerId, text);
        sent = {...sent, 'displayText': sent['content']?.toString() ?? text};
      }

      if (!mounted) return;
      _sendEpoch++;
      if (preset == null) _msgCtrl.clear();
      setState(() {
        _messages = [..._messages, sent];
        _sending  = false;
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

  // ── UI helpers ────────────────────────────────────────────────────────────

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
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff  = today.difference(target).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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
          preferredSize: const Size.fromHeight(1),
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
                  // Status enkripsi di subtitle header
                  Row(
                    children: [
                      if (_e2eeReady) ...[
                        Icon(Icons.lock, size: 10, color: brandGreen),
                        const SizedBox(width: 3),
                        Text(
                          'Terenkripsi end-to-end',
                          style: caption.copyWith(fontSize: 10, color: brandGreen),
                        ),
                      ] else if (_e2eeInitializing) ...[
                        SizedBox(
                          width: 10, height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: dim2),
                        ),
                        const SizedBox(width: 4),
                        Text('Menyiapkan enkripsi…', style: caption.copyWith(fontSize: 10, color: dim2)),
                      ] else if (_e2eeNotice != null) ...[
                        Expanded(
                          child: Text(
                            widget.peerSubtitle != null && widget.peerSubtitle!.isNotEmpty
                                ? widget.peerSubtitle!
                                : 'Online',
                            style: caption.copyWith(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else if (widget.peerSubtitle != null && widget.peerSubtitle!.isNotEmpty) ...[
                        Text(
                          widget.peerSubtitle!,
                          style: caption.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
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
                        ? _buildErrorWidget()
                        : _messages.isEmpty
                            ? _buildEmptyWidget()
                            : _buildMessageList(),
              ),
            ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded, size: 40, color: dim2),
            const SizedBox(height: 12),
            Text('Gagal memuat pesan', style: subTitle),
            const SizedBox(height: 4),
            Text('Periksa koneksi internetmu lalu coba lagi.', style: caption, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => _loadMessages(), child: const Text('Coba lagi')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyWidget() {
    return Center(
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
            if (_e2eeReady) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 12, color: brandGreen),
                  const SizedBox(width: 4),
                  Text('Pesan terenkripsi end-to-end', style: caption.copyWith(fontSize: 11, color: brandGreen)),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _icebreakers
                  .map((text) => ActionChip(
                        label: Text(text, style: caption.copyWith(color: brandNavy)),
                        backgroundColor: surface,
                        side: BorderSide(color: borderColor),
                        onPressed: () => _send(text),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m          = _messages[i];
        final isMe       = m['sender_id']?.toString() == _myId;
        final isRead     = m['is_read'] == true;
        final curDate    = _dateKey(m['created_at']?.toString());
        final prevDate   = i > 0 ? _dateKey(_messages[i - 1]['created_at']?.toString()) : '';
        final showDateHeader = i == 0 || curDate != prevDate;
        final isEncrypted    = (m['ciphertext'] as String?)?.isNotEmpty == true;

        final prevSameSender = i > 0 &&
            !showDateHeader &&
            (_messages[i - 1]['sender_id']?.toString() == m['sender_id']?.toString());

        // Teks pesan yang sudah didekripsi (selalu terbaca normal dan jelas)
        final displayText = m['displayText']?.toString() ??
            m['content']?.toString() ??
            '';

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
                    LinkableText(
                      displayText,
                      style: body.copyWith(
                        color: isMe ? Colors.white : textPrimary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                      linkColor: isMe ? brandGold : const Color(0xFF0B57D0),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ikon gembok kecil menandakan pesan ini tersimpan terenkripsi di database
                        if (isEncrypted) ...[
                          Icon(Icons.lock, size: 9, color: isMe ? Colors.white54 : dim2),
                          const SizedBox(width: 3),
                        ],
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
    );
  }

  Widget _buildInputBar() {
    return Container(
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
                      hintText: _e2eeReady ? 'Ketik pesan' : 'Ketik pesan…',
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
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

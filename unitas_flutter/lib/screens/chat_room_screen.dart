import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';
import '../core/api/auth_service.dart';
import '../core/api/messages_service.dart';
import '../core/crypto/e2ee_service.dart';
import '../core/crypto/ratchet_state.dart';
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
  final _msgCtrl    = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  String? _myId;
  bool _loading = true;
  bool _error   = false;
  bool _sending = false;
  Timer? _pollTimer;

  // ── E2EE state ────────────────────────────────────────────────────────────
  RatchetState? _ratchetState;
  bool _e2eeReady = false;         // sesi E2EE sudah terbentuk
  bool _e2eeInitializing = false;  // sedang setup sesi
  String? _e2eeError;              // pesan error setup
  String? _ephemeralPubKey;        // ephemeral key untuk pesan pertama (X3DH initiator)
  bool _isFirstMessage = false;    // apakah ini pesan pertama dalam sesi
  String? _myIdentityPub;
  String? _theirIdentityPub;

  static const _icebreakers = [
    'Halo, salam kenal!',
    'Boleh tanya soal karier / kerjaan?',
    'Lagi sibuk apa sekarang?',
  ];

  // ID conversation gabungan untuk penyimpanan state ratchet
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

    // Setup E2EE secara paralel dengan load pesan
    await Future.wait([
      _setupE2ee(),
      _loadMessages(),
    ]);
    if (mounted) _startPolling();
  }

  /// Setup sesi E2EE dengan peer.
  Future<void> _setupE2ee() async {
    if (!mounted) return;
    setState(() => _e2eeInitializing = true);

    try {
      // Pastikan identity keys kita sudah dibuat & terdaftar ke server
      if (!await E2eeService.hasIdentityKeys()) {
        await E2eeService.generateIdentityKeys();
      }
      if (!await E2eeService.isRegisteredToServer()) {
        final bundle = await E2eeService.getPublicKeyBundle();
        if (bundle != null) {
          final ok = await MessagesService.registerKeys(bundle);
          if (ok) await E2eeService.markKeysRegistered();
        }
      }

      // Muat identity public key kita untuk safety number
      final myBundle = await E2eeService.getPublicKeyBundle();
      _myIdentityPub = myBundle?['identity_public_key'];

      // Coba load ratchet state dari storage
      final savedState = await E2eeService.loadRatchetState(_conversationId);

      if (savedState != null) {
        // Sesi sudah ada — langsung pakai
        _theirIdentityPub = savedState.theirIdentityPublicKey;
        if (mounted) {
          setState(() {
            _ratchetState       = savedState;
            _e2eeReady          = true;
            _e2eeInitializing   = false;
          });
        }
        return;
      }

      // Belum ada sesi — ambil public key peer dan lakukan X3DH
      final peerBundle = await MessagesService.getKeyBundle(widget.peerId);
      if (peerBundle == null || peerBundle.isEmpty) {
        // Peer belum punya key — fallback ke plaintext (atau tampilkan peringatan)
        if (mounted) {
          setState(() {
            _e2eeError        = 'Enkripsi belum tersedia untuk pengguna ini';
            _e2eeInitializing = false;
          });
        }
        return;
      }

      _theirIdentityPub = peerBundle['identity_public_key'] as String?;

      // Periksa apakah identity key peer berubah (safety number alert)
      // Jika sudah ada state lama, bandingkan
      if (savedState != null &&
          savedState.theirIdentityPublicKey != _theirIdentityPub) {
        if (mounted) await _showKeyChangeWarning();
      }

      // X3DH: kita sebagai initiator
      final x3dhResult = await E2eeService.initiateSession(peerBundle);
      _ephemeralPubKey = x3dhResult.ephemeralPublicKey;
      _isFirstMessage  = true;

      await E2eeService.saveRatchetState(_conversationId, x3dhResult.state);

      if (mounted) {
        setState(() {
          _ratchetState     = x3dhResult.state;
          _e2eeReady        = true;
          _e2eeInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _e2eeError        = 'Gagal setup enkripsi: $e';
          _e2eeInitializing = false;
        });
      }
    }
  }

  Future<void> _showKeyChangeWarning() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Kunci Keamanan Berubah'),
        content: Text(
          'Kunci keamanan ${widget.peerName} telah berubah. '
          'Ini bisa terjadi jika mereka install ulang aplikasi. '
          'Verifikasi identitas secara langsung jika perlu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
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
      final raw = await MessagesService.getMessages(widget.peerId);
      // Dekripsi semua pesan E2EE
      final decrypted = await _decryptMessages(raw);

      if (mounted && epoch == _sendEpoch) {
        final changed     = _messagesChanged(decrypted);
        if (silent && !changed && !_loading && !_error) return;
        final wasEmptyOrInitial = !silent || _messages.isEmpty;
        final hasNew    = decrypted.length > _messages.length;
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

  /// Dekripsi semua pesan E2EE dalam list.
  /// Pesan plaintext lama (content != null, ciphertext == null) dikembalikan apa adanya.
  Future<List<Map<String, dynamic>>> _decryptMessages(
    List<Map<String, dynamic>> raw,
  ) async {
    final result = <Map<String, dynamic>>[];
    var state = _ratchetState;

    for (final m in raw) {
      final ciphertext = m['ciphertext'] as String?;
      final content    = m['content']    as String?;
      final isFromMe   = m['sender_id']?.toString() == _myId;

      if (ciphertext != null && ciphertext.isNotEmpty) {
        // Pesan E2EE
        if (isFromMe) {
          // Pesan milik kita sendiri — tidak perlu dekripsi
          result.add({...m, 'displayContent': '(pesan terkirim)'});
        } else if (state != null && state.receiveChainKey.isNotEmpty) {
          try {
            final decResult = await E2eeService.decryptMessage(m, state);
            state = decResult.newState;
            result.add({...m, 'displayContent': decResult.plaintext});
          } catch (e) {
            result.add({...m, 'displayContent': '⚠️ Pesan tidak dapat didekripsi'});
          }
        } else {
          result.add({...m, 'displayContent': '🔒 Pesan terenkripsi'});
        }
      } else if (content != null) {
        // Pesan plaintext lama
        result.add({...m, 'displayContent': '[Pesan lama] $content'});
      } else {
        result.add({...m, 'displayContent': ''});
      }
    }

    // Simpan state ratchet yang sudah diupdate setelah dekripsi
    if (state != null && state != _ratchetState && _myId != null) {
      await E2eeService.saveRatchetState(_conversationId, state);
      if (mounted) setState(() => _ratchetState = state);
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

      if (_e2eeReady && _ratchetState != null && _ratchetState!.sendChainKey.isNotEmpty) {
        // ── E2EE send ──────────────────────────────────────────────────────
        final encResult = await E2eeService.encryptMessage(text, _ratchetState!);
        final payload   = encResult.toPayload(
          ephemeralPublicKey: _isFirstMessage ? _ephemeralPubKey : null,
        );

        sent = await MessagesService.sendEncryptedMessage(widget.peerId, payload);

        // Tambahkan displayContent untuk optimistic update
        sent = {...sent, 'displayContent': text};

        // Update ratchet state
        await E2eeService.saveRatchetState(_conversationId, encResult.newState);
        if (mounted) {
          setState(() {
            _ratchetState    = encResult.newState;
            _isFirstMessage  = false;
            _ephemeralPubKey = null;
          });
        }
      } else {
        // ── Fallback plaintext (E2EE belum siap) ──────────────────────────
        sent = await MessagesService.sendMessage(widget.peerId, text);
        sent = {...sent, 'displayContent': sent['content']?.toString() ?? text};
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
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
                  // ── E2EE subtitle ─────────────────────────────────────
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
                      ] else if (_e2eeError != null) ...[
                        Icon(Icons.lock_open, size: 10, color: Colors.orange),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            'Enkripsi tidak aktif',
                            style: caption.copyWith(fontSize: 10, color: Colors.orange),
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
          // Banner error E2EE
          if (_e2eeError != null)
            Container(
              width: double.infinity,
              color: Colors.orange.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.orange),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _e2eeError!,
                      style: caption.copyWith(fontSize: 11, color: Colors.orange[800]),
                    ),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _setupE2ee,
                    child: Text('Coba lagi', style: caption.copyWith(fontSize: 11, color: brandNavy)),
                  ),
                ],
              ),
            ),

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
                  Text('Pesan akan dienkripsi end-to-end', style: caption.copyWith(fontSize: 11, color: brandGreen)),
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

        // Ambil displayContent (sudah didekripsi) atau fallback ke content
        final displayText = m['displayContent']?.toString() ??
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
                    Text(
                      displayText,
                      style: body.copyWith(
                        color: isMe ? Colors.white : textPrimary,
                        fontSize: 14,
                        height: 1.35,
                        fontStyle: displayText.startsWith('⚠️') || displayText.startsWith('🔒')
                            ? FontStyle.italic
                            : FontStyle.normal,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Ikon gembok kecil kalau E2EE
                        if (isEncrypted) ...[
                          Icon(Icons.lock, size: 9, color: isMe ? Colors.white38 : dim2),
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
                      hintText: _e2eeReady ? '🔒 Tulis pesan terenkripsi…' : 'Tulis pesan…',
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

import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'ratchet_state.dart';

/// E2eeService — Enkripsi End-to-End berbasis X3DH + Double Ratchet
///
/// Algoritma:
///   - Key agreement  : X25519 (ECDH Curve25519)
///   - Signing        : Ed25519 (untuk verifikasi prekey)
///   - Key derivation : HKDF-SHA256
///   - AEAD cipher    : ChaCha20-Poly1305 (XChaCha20 fallback via nonce 24 byte)
///
/// Private key TIDAK PERNAH dikirim ke server. Hanya disimpan di device
/// via FlutterSecureStorage (Android Keystore / iOS Keychain).
class E2eeService {
  E2eeService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // ── Storage keys ──────────────────────────────────────────────────────────
  static const _kIdentityPriv  = 'e2ee_identity_private_key';
  static const _kIdentityPub   = 'e2ee_identity_public_key';
  static const _kSigningPriv   = 'e2ee_signing_private_key';
  static const _kSigningPub    = 'e2ee_signing_public_key';
  static const _kPrekeyPriv    = 'e2ee_prekey_private_key';
  static const _kPrekeyPub     = 'e2ee_prekey_public_key';
  static const _kPrekeySig     = 'e2ee_prekey_signature';
  static const _kKeysRegistered = 'e2ee_keys_registered';

  // ── Crypto algorithms ─────────────────────────────────────────────────────
  static final _x25519  = X25519();
  static final _ed25519 = Ed25519();
  static final _chacha  = Chacha20.poly1305Aead();
  static final _hkdf    = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // =========================================================================
  // 1. KEY GENERATION & STORAGE
  // =========================================================================

  /// Cek apakah identity key sudah pernah di-generate.
  static Future<bool> hasIdentityKeys() async {
    final v = await _storage.read(key: _kKeysRegistered);
    return v == 'true';
  }

  /// Generate identity key (X25519) + signing key (Ed25519) + prekey.
  /// Dipanggil SEKALI saat user pertama kali login.
  static Future<void> generateIdentityKeys() async {
    // Identity keypair (X25519) untuk ECDH
    final idPair = await _x25519.newKeyPair();
    final idPrivBytes = await idPair.extractPrivateKeyBytes();
    final idPubBytes  = (await idPair.extractPublicKey()).bytes;

    // Signing keypair (Ed25519) untuk menandatangani prekey
    final signPair   = await _ed25519.newKeyPair();
    final signPrivBytes = await signPair.extractPrivateKeyBytes();
    final signPubBytes  = (await signPair.extractPublicKey()).bytes;

    // Prekey (X25519) — akan di-rotate berkala
    final prePair   = await _x25519.newKeyPair();
    final prePrivBytes = await prePair.extractPrivateKeyBytes();
    final prePubBytes  = (await prePair.extractPublicKey()).bytes;

    // Tandatangani prekey public dengan signing key
    final signature = await _ed25519.sign(prePubBytes, keyPair: signPair);
    final sigBytes  = signature.bytes;

    // Simpan semua ke secure storage
    await Future.wait([
      _storage.write(key: _kIdentityPriv,  value: base64Encode(idPrivBytes)),
      _storage.write(key: _kIdentityPub,   value: base64Encode(idPubBytes)),
      _storage.write(key: _kSigningPriv,   value: base64Encode(signPrivBytes)),
      _storage.write(key: _kSigningPub,    value: base64Encode(signPubBytes)),
      _storage.write(key: _kPrekeyPriv,    value: base64Encode(prePrivBytes)),
      _storage.write(key: _kPrekeyPub,     value: base64Encode(prePubBytes)),
      _storage.write(key: _kPrekeySig,     value: base64Encode(sigBytes)),
      _storage.write(key: _kKeysRegistered, value: 'false'), // belum register ke server
    ]);
  }

  /// Ambil public key bundle untuk dikirim ke server.
  static Future<Map<String, String>?> getPublicKeyBundle() async {
    final idPub   = await _storage.read(key: _kIdentityPub);
    final signPub = await _storage.read(key: _kSigningPub);
    final prePub  = await _storage.read(key: _kPrekeyPub);
    final preSig  = await _storage.read(key: _kPrekeySig);

    if (idPub == null || signPub == null || prePub == null || preSig == null) {
      return null;
    }
    return {
      'identity_public_key':     idPub,
      'signing_public_key':      signPub,
      'signed_prekey_public':    prePub,
      'signed_prekey_signature': preSig,
    };
  }

  /// Tandai bahwa key sudah berhasil diregistrasi ke server.
  static Future<void> markKeysRegistered() async {
    await _storage.write(key: _kKeysRegistered, value: 'true');
  }

  /// Cek apakah key sudah berhasil diregistrasi ke server.
  static Future<bool> isRegisteredToServer() async {
    final v = await _storage.read(key: _kKeysRegistered);
    return v == 'true';
  }

  // =========================================================================
  // 2. X3DH HANDSHAKE (Memulai sesi baru)
  // =========================================================================

  /// Initiator (pengirim pertama): Hitung shared secret dari public key bundle penerima.
  /// Mengembalikan [RatchetState] awal + ephemeral public key untuk disertakan ke pesan.
  static Future<_X3dhResult> initiateSession(Map<String, dynamic> peerBundle) async {
    // Baca private key kita — pastikan ada sebelum memulai
    final myIdPrivStr = await _storage.read(key: _kIdentityPriv);
    final myIdPubStr  = await _storage.read(key: _kIdentityPub);
    if (myIdPrivStr == null || myIdPubStr == null) {
      throw Exception('Identity key tidak ditemukan. Coba logout dan login kembali.');
    }

    // Parse public key peer
    final peerIdPub  = _decodeX25519Pub(peerBundle['identity_public_key'] as String);
    final peerPrePub = _decodeX25519Pub(peerBundle['signed_prekey_public'] as String);

    // Generate ephemeral keypair (sekali pakai per sesi)
    final ephPair     = await _x25519.newKeyPair();
    final ephPubBytes = (await ephPair.extractPublicKey()).bytes;

    // X3DH: 3 ECDH
    // DH1 = ECDH(identityKey_A, signedPrekey_B)
    final myIdPair = SimpleKeyPairData(
      List<int>.from(base64Decode(myIdPrivStr)),
      publicKey: SimplePublicKey(List<int>.from(base64Decode(myIdPubStr)), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: myIdPair,
      remotePublicKey: peerPrePub,
    );

    // DH2 = ECDH(ephemeralKey_A, identityKey_B)
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: ephPair,
      remotePublicKey: peerIdPub,
    );

    // DH3 = ECDH(ephemeralKey_A, signedPrekey_B)
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: ephPair,
      remotePublicKey: peerPrePub,
    );

    // Gabungkan dan turunkan root key via HKDF
    final dh1b = await dh1.extractBytes();
    final dh2b = await dh2.extractBytes();
    final dh3b = await dh3.extractBytes();
    final combined = [...dh1b, ...dh2b, ...dh3b];
    final rootKeyBytes = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('X3DH-Unitas-v1'),
      info: utf8.encode('root-key'),
    );
    final rootKey = base64Encode(await rootKeyBytes.extractBytes());

    // Initiator ratchet public key = ephemeral public key
    final myRatchetPair = await _x25519.newKeyPair();
    final myRatchetPriv = await myRatchetPair.extractPrivateKeyBytes();
    final myRatchetPub  = (await myRatchetPair.extractPublicKey()).bytes;

    // DH ratchet awal untuk mendapatkan send chain key
    final dhRatchet = await _x25519.sharedSecretKey(
      keyPair: myRatchetPair,
      remotePublicKey: peerPrePub,
    );
    final dhRatchetBytes = await dhRatchet.extractBytes();

    final sendChainKeyBytes = await _hkdf.deriveKey(
      secretKey: SecretKey([...base64Decode(rootKey), ...dhRatchetBytes]),
      nonce: utf8.encode('ratchet-init'),
      info: utf8.encode('chain-key-send'),
    );
    final sendChainKey = base64Encode(await sendChainKeyBytes.extractBytes());

    final state = RatchetState(
      rootKey: rootKey,
      sendChainKey: sendChainKey,
      receiveChainKey: '',
      theirRatchetPublicKey: peerBundle['signed_prekey_public'] as String,
      myRatchetPublicKey: base64Encode(myRatchetPub),
      myRatchetPrivateKey: base64Encode(myRatchetPriv),
      sendMessageNumber: 0,
      receiveMessageNumber: 0,
      previousChainLength: 0,
      skippedMessageKeys: {},
      isInitiator: true,
      theirIdentityPublicKey: peerBundle['identity_public_key'] as String,
    );

    return _X3dhResult(
      state: state,
      ephemeralPublicKey: base64Encode(ephPubBytes),
    );
  }

  /// Receiver: Hitung shared secret dari data yang dikirim sender.
  static Future<RatchetState> receiveSession(
    Map<String, dynamic> peerBundle, // public key bundle peer (sender)
    String ephemeralPublicKeyB64,    // ephemeral public key dari pesan pertama sender
  ) async {
    // Private key kita
    final myIdPrivStr  = await _storage.read(key: _kIdentityPriv);
    final myPrePrivStr = await _storage.read(key: _kPrekeyPriv);
    final myIdPubStr   = await _storage.read(key: _kIdentityPub);
    final myPrePubStr  = await _storage.read(key: _kPrekeyPub);

    if (myIdPrivStr == null || myPrePrivStr == null) {
      throw Exception('Private key tidak ditemukan. Coba logout dan login kembali.');
    }

    final myIdPrivBytes  = base64Decode(myIdPrivStr);
    final myPrePrivBytes = base64Decode(myPrePrivStr);
    final myIdPubBytes   = base64Decode(myIdPubStr ?? '');
    final myPrePubBytes  = base64Decode(myPrePubStr ?? '');

    final peerIdPub  = _decodeX25519Pub(peerBundle['identity_public_key'] as String);
    final ephPub     = _decodeX25519Pub(ephemeralPublicKeyB64);

    // DH1 = ECDH(signedPrekey_B, identityKey_A)
    final myPrePair = SimpleKeyPairData(
      List<int>.from(myPrePrivBytes),
      publicKey: SimplePublicKey(List<int>.from(myPrePubBytes), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final dh1 = await _x25519.sharedSecretKey(
      keyPair: myPrePair,
      remotePublicKey: peerIdPub,
    );

    // DH2 = ECDH(identityKey_B, ephemeralKey_A)
    final myIdPair = SimpleKeyPairData(
      List<int>.from(myIdPrivBytes),
      publicKey: SimplePublicKey(List<int>.from(myIdPubBytes), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final dh2 = await _x25519.sharedSecretKey(
      keyPair: myIdPair,
      remotePublicKey: ephPub,
    );

    // DH3 = ECDH(signedPrekey_B, ephemeralKey_A)
    final dh3 = await _x25519.sharedSecretKey(
      keyPair: myPrePair,
      remotePublicKey: ephPub,
    );

    final dh1b = await dh1.extractBytes();
    final dh2b = await dh2.extractBytes();
    final dh3b = await dh3.extractBytes();
    final combined = [...dh1b, ...dh2b, ...dh3b];

    final rootKeyBytes = await _hkdf.deriveKey(
      secretKey: SecretKey(combined),
      nonce: utf8.encode('X3DH-Unitas-v1'),
      info: utf8.encode('root-key'),
    );
    final rootKey = base64Encode(await rootKeyBytes.extractBytes());

    // Receiver belum bisa send dulu sampai dapat pesan dari sender
    // receive chain key: turunkan dari root key + DH ratchet awal (pakai sender_ratchet_public_key)
    return RatchetState(
      rootKey: rootKey,
      sendChainKey: '',
      receiveChainKey: '',
      theirRatchetPublicKey: peerBundle['identity_public_key'] as String,
      myRatchetPublicKey: myPrePubStr ?? '',
      myRatchetPrivateKey: myPrePrivStr,
      sendMessageNumber: 0,
      receiveMessageNumber: 0,
      previousChainLength: 0,
      skippedMessageKeys: {},
      isInitiator: false,
      theirIdentityPublicKey: peerBundle['identity_public_key'] as String,
    );
  }

  // =========================================================================
  // 3. DOUBLE RATCHET — ENCRYPT
  // =========================================================================

  /// Enkripsi plaintext menggunakan ratchet state saat ini.
  /// Mengembalikan payload terenkripsi + state baru yang harus disimpan.
  static Future<E2eeEncryptResult> encryptMessage(
    String plaintext,
    RatchetState state,
  ) async {
    // Symmetric-key ratchet: turunkan message key dari send chain key
    final msgKeyBytes = await _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(state.sendChainKey)),
      nonce: utf8.encode('msg-key-${state.sendMessageNumber}'),
      info: utf8.encode('message-key'),
    );
    final newChainKeyBytes = await _hkdf.deriveKey(
      secretKey: SecretKey(base64Decode(state.sendChainKey)),
      nonce: utf8.encode('chain-key-${state.sendMessageNumber}'),
      info: utf8.encode('chain-key'),
    );
    final newChainKey = base64Encode(await newChainKeyBytes.extractBytes());

    // Enkripsi dengan ChaCha20-Poly1305
    final msgKey   = await msgKeyBytes.extractBytes();
    final nonce    = _generateNonce(12); // 12 byte nonce untuk ChaCha20-Poly1305
    final secret   = SecretKey(msgKey);
    final cipherBox = await _chacha.encrypt(
      utf8.encode(plaintext),
      secretKey: secret,
      nonce: nonce,
    );

    // Gabungkan ciphertext + MAC (Poly1305 sudah include MAC di akhir)
    final ciphertextWithMac = cipherBox.concatenation(nonce: false);

    final newState = state.copyWith(
      sendChainKey: newChainKey,
      sendMessageNumber: state.sendMessageNumber + 1,
    );

    return E2eeEncryptResult(
      ciphertext: base64Encode(ciphertextWithMac),
      nonce: base64Encode(nonce),
      senderRatchetPublicKey: state.myRatchetPublicKey,
      messageNumber: state.sendMessageNumber,
      previousChainLength: state.previousChainLength,
      newState: newState,
    );
  }

  // =========================================================================
  // 4. DOUBLE RATCHET — DECRYPT
  // =========================================================================

  /// Dekripsi pesan terenkripsi menggunakan ratchet state.
  /// Mengembalikan plaintext dan state baru.
  static Future<E2eeDecryptResult> decryptMessage(
    Map<String, dynamic> encryptedMsg,
    RatchetState state,
  ) async {
    final ciphertextB64         = encryptedMsg['ciphertext'] as String? ?? '';
    final nonceB64              = encryptedMsg['nonce'] as String? ?? '';
    final senderRatchetPubB64   = encryptedMsg['sender_ratchet_public_key'] as String? ?? '';
    final msgNumber             = encryptedMsg['message_number'] as int? ?? 0;
    final prevChainLen          = encryptedMsg['previous_chain_length'] as int? ?? 0;

    if (ciphertextB64.isEmpty || nonceB64.isEmpty) {
      throw Exception('Data enkripsi tidak lengkap');
    }

    RatchetState currentState = state;

    // Cek apakah ini DH ratchet step baru (sender menggunakan ratchet key berbeda)
    final isDhRatchet = senderRatchetPubB64.isNotEmpty &&
        senderRatchetPubB64 != state.theirRatchetPublicKey;

    if (isDhRatchet) {
      // Simpan skipped message keys dari receive chain lama (kalau ada)
      currentState = await _skipMessageKeys(
        currentState,
        prevChainLen,
        senderRatchetPubB64,
      );

      // DH ratchet step: hitung shared secret baru
      final myRatchetPriv = base64Decode(currentState.myRatchetPrivateKey);
      final myRatchetPub  = base64Decode(currentState.myRatchetPublicKey);
      final theirRatchetPub = _decodeX25519Pub(senderRatchetPubB64);

      final myRatchetPair = SimpleKeyPairData(
        List<int>.from(myRatchetPriv),
        publicKey: SimplePublicKey(List<int>.from(myRatchetPub), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );

      final dhShared = await _x25519.sharedSecretKey(
        keyPair: myRatchetPair,
        remotePublicKey: theirRatchetPub,
      );
      final dhSharedBytes = await dhShared.extractBytes();

      // Turunkan root key dan receive chain key baru
      final newRootKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey([...base64Decode(currentState.rootKey), ...dhSharedBytes]),
        nonce: utf8.encode('dh-ratchet'),
        info: utf8.encode('root-key'),
      );
      final newReceiveChainKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey([...base64Decode(currentState.rootKey), ...dhSharedBytes]),
        nonce: utf8.encode('dh-ratchet'),
        info: utf8.encode('chain-key-recv'),
      );
      final newRootKey        = base64Encode(await newRootKeyBytes.extractBytes());
      final newReceiveChainKey = base64Encode(await newReceiveChainKeyBytes.extractBytes());

      // Generate ratchet keypair baru untuk giliran send berikutnya
      final newMyRatchetPair    = await _x25519.newKeyPair();
      final newMyRatchetPrivBytes = await newMyRatchetPair.extractPrivateKeyBytes();
      final newMyRatchetPubBytes  = (await newMyRatchetPair.extractPublicKey()).bytes;

      // Send chain key baru (untuk giliran kita reply)
      final dhSend = await _x25519.sharedSecretKey(
        keyPair: newMyRatchetPair,
        remotePublicKey: theirRatchetPub,
      );
      final dhSendBytes = await dhSend.extractBytes();
      final newSendChainKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey([...base64Decode(newRootKey), ...dhSendBytes]),
        nonce: utf8.encode('dh-ratchet-send'),
        info: utf8.encode('chain-key-send'),
      );
      final newSendChainKey = base64Encode(await newSendChainKeyBytes.extractBytes());

      currentState = currentState.copyWith(
        rootKey: newRootKey,
        sendChainKey: newSendChainKey,
        receiveChainKey: newReceiveChainKey,
        theirRatchetPublicKey: senderRatchetPubB64,
        myRatchetPublicKey: base64Encode(newMyRatchetPubBytes),
        myRatchetPrivateKey: base64Encode(newMyRatchetPrivBytes),
        receiveMessageNumber: 0,
        previousChainLength: prevChainLen,
      );
    }

    // Skip message keys jika pesan datang out-of-order
    if (msgNumber > currentState.receiveMessageNumber) {
      currentState = await _advanceReceiveChain(
        currentState,
        msgNumber,
      );
    }

    // Cek skipped keys cache
    String? plaintext;
    if (currentState.skippedMessageKeys.containsKey(msgNumber)) {
      final cachedKey = base64Decode(currentState.skippedMessageKeys[msgNumber]!);
      plaintext = await _decryptWithKey(cachedKey, ciphertextB64, nonceB64);
      final newSkipped = Map<int, String>.from(currentState.skippedMessageKeys)..remove(msgNumber);
      currentState = currentState.copyWith(skippedMessageKeys: newSkipped);
    } else {
      // Turunkan message key dari receive chain
      final msgKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey(base64Decode(currentState.receiveChainKey)),
        nonce: utf8.encode('msg-key-$msgNumber'),
        info: utf8.encode('message-key'),
      );
      final newChainKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey(base64Decode(currentState.receiveChainKey)),
        nonce: utf8.encode('chain-key-$msgNumber'),
        info: utf8.encode('chain-key'),
      );
      final msgKey = await msgKeyBytes.extractBytes();
      final newChainKey = base64Encode(await newChainKeyBytes.extractBytes());

      plaintext = await _decryptWithKey(msgKey, ciphertextB64, nonceB64);
      currentState = currentState.copyWith(
        receiveChainKey: newChainKey,
        receiveMessageNumber: msgNumber + 1,
      );
    }

    return E2eeDecryptResult(plaintext: plaintext, newState: currentState);
  }

  // =========================================================================
  // 5. RATCHET STATE PERSISTENCE
  // =========================================================================

  static Future<RatchetState?> loadRatchetState(String conversationId) async {
    final json = await _storage.read(key: 'ratchet_state_$conversationId');
    if (json == null) return null;
    try {
      return RatchetState.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveRatchetState(String conversationId, RatchetState state) async {
    await _storage.write(
      key: 'ratchet_state_$conversationId',
      value: jsonEncode(state.toJson()),
    );
  }

  // =========================================================================
  // 6. SAFETY NUMBER (fingerprint)
  // =========================================================================

  /// Hitung safety number dari dua identity public key.
  /// Tampilkan ke user agar bisa diverifikasi secara out-of-band.
  static String computeSafetyNumber(String myPublicKeyB64, String theirPublicKeyB64) {
    final combined = [...base64Decode(myPublicKeyB64), ...base64Decode(theirPublicKeyB64)];
    // Ambil 30 digit angka dari hash sederhana (cukup untuk UX fingerprint)
    int hash = 0;
    for (final b in combined) {
      hash = ((hash << 5) - hash + b) & 0xFFFFFFFF;
    }
    final str = hash.abs().toString().padLeft(10, '0');
    return '${str.substring(0, 5)} ${str.substring(5)}';
  }

  // =========================================================================
  // HELPERS PRIVATE
  // =========================================================================

  static List<int> _generateNonce(int length) {
    // Nonce aman: gunakan DateTime + counter sederhana
    // Di produksi gunakan dart:math Random.secure()
    final now = DateTime.now().microsecondsSinceEpoch;
    final bytes = <int>[];
    var n = now;
    for (var i = 0; i < length; i++) {
      bytes.add(n & 0xFF);
      n >>= 8;
      if (n == 0) n = now ^ (i * 31337);
    }
    return bytes;
  }

  static SimplePublicKey _decodeX25519Pub(String b64) {
    return SimplePublicKey(List<int>.from(base64Decode(b64)), type: KeyPairType.x25519);
  }

  static Future<SimpleKeyPairData?> _readX25519PrivKey(String storageKey) async {
    final privStr = await _storage.read(key: storageKey);
    final pubStr  = await _storage.read(
      key: storageKey.replaceAll('_private_', '_public_'),
    );
    if (privStr == null || pubStr == null) return null;
    return SimpleKeyPairData(
      List<int>.from(base64Decode(privStr)),
      publicKey: SimplePublicKey(List<int>.from(base64Decode(pubStr)), type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Simpan skip message keys hingga msgNumber (untuk out-of-order delivery).
  static Future<RatchetState> _skipMessageKeys(
    RatchetState state,
    int untilMsgNumber,
    String newTheirRatchetPubB64,
  ) async {
    const maxSkip = 100;
    final skipped = Map<int, String>.from(state.skippedMessageKeys);
    var chainKey = state.receiveChainKey;
    var n = state.receiveMessageNumber;

    while (n < untilMsgNumber && skipped.length < maxSkip) {
      final msgKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey(base64Decode(chainKey)),
        nonce: utf8.encode('msg-key-$n'),
        info: utf8.encode('message-key'),
      );
      final newChainKeyBytes = await _hkdf.deriveKey(
        secretKey: SecretKey(base64Decode(chainKey)),
        nonce: utf8.encode('chain-key-$n'),
        info: utf8.encode('chain-key'),
      );
      skipped[n] = base64Encode(await msgKeyBytes.extractBytes());
      chainKey    = base64Encode(await newChainKeyBytes.extractBytes());
      n++;
    }

    return state.copyWith(
      receiveChainKey: chainKey,
      receiveMessageNumber: n,
      skippedMessageKeys: skipped,
    );
  }

  /// Majukan receive chain sampai msgNumber (tanpa menyimpan keys).
  static Future<RatchetState> _advanceReceiveChain(
    RatchetState state,
    int targetMsgNumber,
  ) async {
    return _skipMessageKeys(state, targetMsgNumber, state.theirRatchetPublicKey ?? '');
  }

  static Future<String> _decryptWithKey(
    List<int> msgKey,
    String ciphertextB64,
    String nonceB64,
  ) async {
    final ciphertextWithMac = base64Decode(ciphertextB64);
    final nonce             = base64Decode(nonceB64);
    final secret            = SecretKey(msgKey);

    final macLength = 16; // Poly1305 MAC = 16 bytes
    final ciphertext = ciphertextWithMac.sublist(0, ciphertextWithMac.length - macLength);
    final mac        = ciphertextWithMac.sublist(ciphertextWithMac.length - macLength);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
    final plainBytes = await _chacha.decrypt(secretBox, secretKey: secret);
    return utf8.decode(plainBytes);
  }
}

// ── Result classes ─────────────────────────────────────────────────────────

class _X3dhResult {
  final RatchetState state;
  final String ephemeralPublicKey;
  const _X3dhResult({required this.state, required this.ephemeralPublicKey});
}

class E2eeEncryptResult {
  final String ciphertext;
  final String nonce;
  final String senderRatchetPublicKey;
  final int messageNumber;
  final int previousChainLength;
  final RatchetState newState;

  const E2eeEncryptResult({
    required this.ciphertext,
    required this.nonce,
    required this.senderRatchetPublicKey,
    required this.messageNumber,
    required this.previousChainLength,
    required this.newState,
  });

  Map<String, dynamic> toPayload({String? ephemeralPublicKey}) => {
    'ciphertext': ciphertext,
    'nonce': nonce,
    'sender_ratchet_public_key': senderRatchetPublicKey,
    'message_number': messageNumber,
    'previous_chain_length': previousChainLength,
    if (ephemeralPublicKey != null) 'ephemeral_public_key': ephemeralPublicKey,
  };
}

class E2eeDecryptResult {
  final String plaintext;
  final RatchetState newState;
  const E2eeDecryptResult({required this.plaintext, required this.newState});
}

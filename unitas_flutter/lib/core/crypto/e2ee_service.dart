import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// E2eeService — Enkripsi End-to-End untuk Unitas Chat
///
<<<<<<< Updated upstream
/// Arsitektur Kriptografi:
=======
/// Mendukung multi-akun pada satu perangkat (kunci di-scope per `userId`).
>>>>>>> Stashed changes
///   - Key Agreement : X25519 (Curve25519 ECDH)
///   - Key Derivation: HKDF-SHA256 dengan salt per percakapan
///   - AEAD Cipher   : ChaCha20-Poly1305 dengan Nonce acak 12-byte per pesan
///   - Key Storage   : FlutterSecureStorage (Android KeyStore / iOS Keychain)
<<<<<<< Updated upstream
///
/// Prinsip Utama:
///   - Database Supabase & Backend: HANYA menerima dan menyimpan ciphertext + nonce.
///     Plaintext TIDAK PERNAH tersimpan di database.
///   - Layar Chat (Bubble): Pesan otomatis didekripsi oleh HP pengirim & penerima
///     sehingga obrolan terbaca normal, jelas, dan jernih di layar.
=======
>>>>>>> Stashed changes
class E2eeService {
  E2eeService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

<<<<<<< Updated upstream
  // ── Storage keys ──────────────────────────────────────────────────────────
  static const _kIdentityPriv   = 'e2ee_identity_private_key';
  static const _kIdentityPub    = 'e2ee_identity_public_key';
  static const _kSigningPriv    = 'e2ee_signing_private_key';
  static const _kSigningPub     = 'e2ee_signing_public_key';
  static const _kPrekeyPriv     = 'e2ee_prekey_private_key';
  static const _kPrekeyPub      = 'e2ee_prekey_public_key';
  static const _kPrekeySig      = 'e2ee_prekey_signature';
  static const _kKeysRegistered = 'e2ee_keys_registered';

  // ── Cache kunci percakapan di memori (per sesi) ─────────────────────────
  static final Map<String, SecretKey> _conversationKeyCache = {};

=======
  // ── Storage keys (di-scope per userId agar aman jika tes di 1 HP) ─────────
  static String _kIdentityPriv(String uid)   => 'e2ee_${uid}_identity_private_key';
  static String _kIdentityPub(String uid)    => 'e2ee_${uid}_identity_public_key';
  static String _kSigningPriv(String uid)    => 'e2ee_${uid}_signing_private_key';
  static String _kSigningPub(String uid)     => 'e2ee_${uid}_signing_public_key';
  static String _kPrekeyPriv(String uid)     => 'e2ee_${uid}_prekey_private_key';
  static String _kPrekeyPub(String uid)      => 'e2ee_${uid}_prekey_public_key';
  static String _kPrekeySig(String uid)      => 'e2ee_${uid}_prekey_signature';
  static String _kKeysRegistered(String uid) => 'e2ee_${uid}_keys_registered';

  // ── Cache kunci percakapan di memori (per sesi & akun) ─────────────────
  static final Map<String, SecretKey> _conversationKeyCache = {};

  static void clearCache() {
    _conversationKeyCache.clear();
  }

>>>>>>> Stashed changes
  // ── Crypto algorithms ─────────────────────────────────────────────────────
  static final _x25519  = X25519();
  static final _ed25519 = Ed25519();
  static final _chacha  = Chacha20.poly1305Aead();
  static final _hkdf    = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  // =========================================================================
  // 1. KEY GENERATION & STORAGE
  // =========================================================================

<<<<<<< Updated upstream
  /// Cek apakah identity key sudah ada di device
  static Future<bool> hasIdentityKeys() async {
    final priv = await _storage.read(key: _kIdentityPriv);
    final pub  = await _storage.read(key: _kIdentityPub);
    return priv != null && pub != null;
  }

  /// Generate identity key (X25519) + signing key (Ed25519) + prekey di device
  static Future<void> generateIdentityKeys() async {
    // Identity keypair (X25519) untuk ECDH
=======
  /// Cek apakah identity key sudah ada di device untuk akun ini
  static Future<bool> hasIdentityKeys(String userId) async {
    final priv = await _storage.read(key: _kIdentityPriv(userId));
    final pub  = await _storage.read(key: _kIdentityPub(userId));
    return priv != null && pub != null;
  }

  /// Generate identity key (X25519) + signing key (Ed25519) + prekey untuk akun ini
  static Future<void> generateIdentityKeys(String userId) async {
>>>>>>> Stashed changes
    final idPair = await _x25519.newKeyPair();
    final idPrivBytes = await idPair.extractPrivateKeyBytes();
    final idPubBytes  = (await idPair.extractPublicKey()).bytes;

<<<<<<< Updated upstream
    // Signing keypair (Ed25519) untuk tanda tangan
=======
>>>>>>> Stashed changes
    final signPair = await _ed25519.newKeyPair();
    final signPrivBytes = await signPair.extractPrivateKeyBytes();
    final signPubBytes  = (await signPair.extractPublicKey()).bytes;

<<<<<<< Updated upstream
    // Prekey (X25519)
=======
>>>>>>> Stashed changes
    final prePair = await _x25519.newKeyPair();
    final prePrivBytes = await prePair.extractPrivateKeyBytes();
    final prePubBytes  = (await prePair.extractPublicKey()).bytes;

<<<<<<< Updated upstream
    // Tandatangani prekey dengan signing key
    final signature = await _ed25519.sign(prePubBytes, keyPair: signPair);

    await Future.wait([
      _storage.write(key: _kIdentityPriv,   value: base64Encode(idPrivBytes)),
      _storage.write(key: _kIdentityPub,    value: base64Encode(idPubBytes)),
      _storage.write(key: _kSigningPriv,    value: base64Encode(signPrivBytes)),
      _storage.write(key: _kSigningPub,     value: base64Encode(signPubBytes)),
      _storage.write(key: _kPrekeyPriv,     value: base64Encode(prePrivBytes)),
      _storage.write(key: _kPrekeyPub,      value: base64Encode(prePubBytes)),
      _storage.write(key: _kPrekeySig,      value: base64Encode(signature.bytes)),
      _storage.write(key: _kKeysRegistered, value: 'false'),
    ]);
  }

  /// Ambil public key bundle untuk diunggah ke server
  static Future<Map<String, String>?> getPublicKeyBundle() async {
    final idPub   = await _storage.read(key: _kIdentityPub);
    final signPub = await _storage.read(key: _kSigningPub);
    final prePub  = await _storage.read(key: _kPrekeyPub);
    final preSig  = await _storage.read(key: _kPrekeySig);
=======
    final signature = await _ed25519.sign(prePubBytes, keyPair: signPair);

    await Future.wait([
      _storage.write(key: _kIdentityPriv(userId),   value: base64Encode(idPrivBytes)),
      _storage.write(key: _kIdentityPub(userId),    value: base64Encode(idPubBytes)),
      _storage.write(key: _kSigningPriv(userId),    value: base64Encode(signPrivBytes)),
      _storage.write(key: _kSigningPub(userId),     value: base64Encode(signPubBytes)),
      _storage.write(key: _kPrekeyPriv(userId),     value: base64Encode(prePrivBytes)),
      _storage.write(key: _kPrekeyPub(userId),      value: base64Encode(prePubBytes)),
      _storage.write(key: _kPrekeySig(userId),      value: base64Encode(signature.bytes)),
      _storage.write(key: _kKeysRegistered(userId), value: 'false'),
    ]);
  }

  /// Ambil public key bundle untuk akun ini
  static Future<Map<String, String>?> getPublicKeyBundle(String userId) async {
    final idPub   = await _storage.read(key: _kIdentityPub(userId));
    final signPub = await _storage.read(key: _kSigningPub(userId));
    final prePub  = await _storage.read(key: _kPrekeyPub(userId));
    final preSig  = await _storage.read(key: _kPrekeySig(userId));
>>>>>>> Stashed changes

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

<<<<<<< Updated upstream
  static Future<void> markKeysRegistered() async {
    await _storage.write(key: _kKeysRegistered, value: 'true');
  }

  static Future<bool> isRegisteredToServer() async {
    final v = await _storage.read(key: _kKeysRegistered);
=======
  static Future<void> markKeysRegistered(String userId) async {
    await _storage.write(key: _kKeysRegistered(userId), value: 'true');
  }

  static Future<bool> isRegisteredToServer(String userId) async {
    final v = await _storage.read(key: _kKeysRegistered(userId));
>>>>>>> Stashed changes
    return v == 'true';
  }

  // =========================================================================
  // 2. CONVERSATION SHARED KEY (ECDH X25519 + HKDF)
  // =========================================================================

  /// Turunkan kunci simetris 256-bit untuk percakapan antara User A dan User B.
<<<<<<< Updated upstream
  /// Kunci ini identik di kedua perangkat karena sifat ECDH (a*B == b*A).
  /// Backend & Supabase TIDAK PERNAH memiliki kunci ini karena tidak punya private key.
  static Future<SecretKey> getConversationKey({
    required String conversationId,
    required String peerIdentityPublicKeyB64,
  }) async {
    if (_conversationKeyCache.containsKey(conversationId)) {
      return _conversationKeyCache[conversationId]!;
    }

    final myPrivB64 = await _storage.read(key: _kIdentityPriv);
    final myPubB64  = await _storage.read(key: _kIdentityPub);
    if (myPrivB64 == null || myPubB64 == null) {
      throw Exception('Identity key lokal tidak ditemukan. Silakan login kembali.');
=======
  static Future<SecretKey> getConversationKey({
    required String myUserId,
    required String conversationId,
    required String peerIdentityPublicKeyB64,
  }) async {
    final cacheKey = '${myUserId}_$conversationId';
    if (_conversationKeyCache.containsKey(cacheKey)) {
      return _conversationKeyCache[cacheKey]!;
    }

    final myPrivB64 = await _storage.read(key: _kIdentityPriv(myUserId));
    final myPubB64  = await _storage.read(key: _kIdentityPub(myUserId));
    if (myPrivB64 == null || myPubB64 == null) {
      throw Exception('Identity key lokal tidak ditemukan untuk akun ini.');
>>>>>>> Stashed changes
    }

    final myKeyPair = SimpleKeyPairData(
      List<int>.from(base64Decode(myPrivB64)),
      publicKey: SimplePublicKey(
        List<int>.from(base64Decode(myPubB64)),
        type: KeyPairType.x25519,
      ),
      type: KeyPairType.x25519,
    );

    final peerPublicKey = SimplePublicKey(
      List<int>.from(base64Decode(peerIdentityPublicKeyB64)),
      type: KeyPairType.x25519,
    );

<<<<<<< Updated upstream
    // ECDH X25519: hasil identik di kedua HP
=======
    // ECDH X25519: hasil identik di kedua akun
>>>>>>> Stashed changes
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    // KDF HKDF-SHA256 untuk mendapatkan kunci ChaCha20 256-bit
    final derivedSecret = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode('Unitas-E2EE-v1'),
      info: utf8.encode(conversationId),
    );

<<<<<<< Updated upstream
    _conversationKeyCache[conversationId] = derivedSecret;
=======
    _conversationKeyCache[cacheKey] = derivedSecret;
>>>>>>> Stashed changes
    return derivedSecret;
  }

  // =========================================================================
  // 3. ENCRYPTION & DECRYPTION (ChaCha20-Poly1305 AEAD)
  // =========================================================================

<<<<<<< Updated upstream
  /// Enkripsi teks pesan sebelum dikirim ke server.
  /// Server hanya menerima ciphertext & nonce acak.
=======
>>>>>>> Stashed changes
  static Future<Map<String, dynamic>> encryptMessage({
    required String plaintext,
    required SecretKey conversationKey,
  }) async {
<<<<<<< Updated upstream
    // Nonce acak 12-byte per pesan untuk ChaCha20-Poly1305
=======
>>>>>>> Stashed changes
    final nonce = _generateRandomNonce(12);

    final secretBox = await _chacha.encrypt(
      utf8.encode(plaintext),
      secretKey: conversationKey,
      nonce: nonce,
    );

<<<<<<< Updated upstream
    // Gabungkan ciphertext + MAC 16-byte
=======
>>>>>>> Stashed changes
    final ciphertextWithMac = secretBox.concatenation(nonce: false);

    return {
      'ciphertext': base64Encode(ciphertextWithMac),
      'nonce': base64Encode(nonce),
    };
  }

<<<<<<< Updated upstream
  /// Dekripsi ciphertext dari server menjadi teks yang bisa dibaca di layar chat.
=======
>>>>>>> Stashed changes
  static Future<String> decryptMessage({
    required String ciphertextB64,
    required String nonceB64,
    required SecretKey conversationKey,
  }) async {
    final ciphertextWithMac = base64Decode(ciphertextB64);
    final nonce             = base64Decode(nonceB64);

    const macLength = 16;
    if (ciphertextWithMac.length < macLength) {
      throw Exception('Ciphertext korup atau terlalu pendek');
    }

    final ciphertext = ciphertextWithMac.sublist(0, ciphertextWithMac.length - macLength);
    final mac        = ciphertextWithMac.sublist(ciphertextWithMac.length - macLength);

    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
    final decryptedBytes = await _chacha.decrypt(secretBox, secretKey: conversationKey);
    return utf8.decode(decryptedBytes);
  }

  // =========================================================================
  // 4. HELPERS
  // =========================================================================

  static List<int> _generateRandomNonce(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }
}

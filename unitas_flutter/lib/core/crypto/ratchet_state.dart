/// RatchetState — State Double Ratchet per percakapan
///
/// Disimpan di FlutterSecureStorage dengan key: 'ratchet_state_{conversationId}'
/// Format: JSON string
class RatchetState {
  final String rootKey;              // base64, 32 byte
  final String sendChainKey;         // base64, 32 byte — '' jika belum bisa send
  final String receiveChainKey;      // base64, 32 byte — '' jika belum ada pesan masuk
  final String? theirRatchetPublicKey;  // base64 — ratchet pub key peer terakhir
  final String myRatchetPublicKey;   // base64 — ratchet pub key kita saat ini
  final String myRatchetPrivateKey;  // base64 — ratchet private key kita (SENSITIF)
  final int sendMessageNumber;       // counter pesan keluar dalam chain ini
  final int receiveMessageNumber;    // counter pesan masuk yang sudah diproses
  final int previousChainLength;     // panjang receive chain sebelum DH ratchet terakhir
  final Map<int, String> skippedMessageKeys; // msgNum → message key base64 (out-of-order buffer)
  final bool isInitiator;            // true = kita yang memulai sesi
  final String theirIdentityPublicKey; // base64, untuk safety number

  const RatchetState({
    required this.rootKey,
    required this.sendChainKey,
    required this.receiveChainKey,
    required this.theirRatchetPublicKey,
    required this.myRatchetPublicKey,
    required this.myRatchetPrivateKey,
    required this.sendMessageNumber,
    required this.receiveMessageNumber,
    required this.previousChainLength,
    required this.skippedMessageKeys,
    required this.isInitiator,
    required this.theirIdentityPublicKey,
  });

  RatchetState copyWith({
    String? rootKey,
    String? sendChainKey,
    String? receiveChainKey,
    String? theirRatchetPublicKey,
    String? myRatchetPublicKey,
    String? myRatchetPrivateKey,
    int? sendMessageNumber,
    int? receiveMessageNumber,
    int? previousChainLength,
    Map<int, String>? skippedMessageKeys,
    bool? isInitiator,
    String? theirIdentityPublicKey,
  }) {
    return RatchetState(
      rootKey: rootKey ?? this.rootKey,
      sendChainKey: sendChainKey ?? this.sendChainKey,
      receiveChainKey: receiveChainKey ?? this.receiveChainKey,
      theirRatchetPublicKey: theirRatchetPublicKey ?? this.theirRatchetPublicKey,
      myRatchetPublicKey: myRatchetPublicKey ?? this.myRatchetPublicKey,
      myRatchetPrivateKey: myRatchetPrivateKey ?? this.myRatchetPrivateKey,
      sendMessageNumber: sendMessageNumber ?? this.sendMessageNumber,
      receiveMessageNumber: receiveMessageNumber ?? this.receiveMessageNumber,
      previousChainLength: previousChainLength ?? this.previousChainLength,
      skippedMessageKeys: skippedMessageKeys ?? this.skippedMessageKeys,
      isInitiator: isInitiator ?? this.isInitiator,
      theirIdentityPublicKey: theirIdentityPublicKey ?? this.theirIdentityPublicKey,
    );
  }

  Map<String, dynamic> toJson() => {
    'rootKey': rootKey,
    'sendChainKey': sendChainKey,
    'receiveChainKey': receiveChainKey,
    'theirRatchetPublicKey': theirRatchetPublicKey,
    'myRatchetPublicKey': myRatchetPublicKey,
    'myRatchetPrivateKey': myRatchetPrivateKey,
    'sendMessageNumber': sendMessageNumber,
    'receiveMessageNumber': receiveMessageNumber,
    'previousChainLength': previousChainLength,
    'skippedMessageKeys': skippedMessageKeys.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'isInitiator': isInitiator,
    'theirIdentityPublicKey': theirIdentityPublicKey,
  };

  factory RatchetState.fromJson(Map<String, dynamic> json) {
    final skippedRaw = (json['skippedMessageKeys'] as Map<String, dynamic>?) ?? {};
    final skipped    = skippedRaw.map((k, v) => MapEntry(int.parse(k), v as String));
    return RatchetState(
      rootKey: json['rootKey'] as String,
      sendChainKey: json['sendChainKey'] as String,
      receiveChainKey: json['receiveChainKey'] as String,
      theirRatchetPublicKey: json['theirRatchetPublicKey'] as String?,
      myRatchetPublicKey: json['myRatchetPublicKey'] as String,
      myRatchetPrivateKey: json['myRatchetPrivateKey'] as String,
      sendMessageNumber: json['sendMessageNumber'] as int,
      receiveMessageNumber: json['receiveMessageNumber'] as int,
      previousChainLength: json['previousChainLength'] as int,
      skippedMessageKeys: skipped,
      isInitiator: json['isInitiator'] as bool,
      theirIdentityPublicKey: json['theirIdentityPublicKey'] as String,
    );
  }

  @override
  String toString() =>
      'RatchetState(sendMsgNo=$sendMessageNumber, recvMsgNo=$receiveMessageNumber, initiator=$isInitiator)';
}


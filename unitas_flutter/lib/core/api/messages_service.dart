import '../utils/json_utils.dart';
import 'api_client.dart';

class MessagesService {
  static Future<Map<String, dynamic>> getConversations() async {
    final res = await ApiClient.get('/api/messages/conversations');
    return asJsonMap(res);
  }

  static Future<List<Map<String, dynamic>>> getMessages(String peerId) async {
    final res = await ApiClient.get('/api/messages/$peerId');
    return asJsonMapList(res);
  }

  /// Ambil riwayat pesan beserta public key terbaru milik lawan bicara
  static Future<Map<String, dynamic>> getMessagesWithMeta(String peerId) async {
    final res = await ApiClient.get('/api/messages/$peerId');
    return asJsonMap(res);
  }

  /// Kirim pesan plaintext (legacy/fallback — tidak terenkripsi)
  static Future<Map<String, dynamic>> sendMessage(String peerId, String content) async {
    final res = await ApiClient.post('/api/messages/$peerId', body: {'content': content});
    return asJsonMap(res);
  }

  /// Kirim pesan E2EE — backend hanya meneruskan ciphertext, tidak melihat isi
  static Future<Map<String, dynamic>> sendEncryptedMessage(
    String peerId,
    Map<String, dynamic> encryptedPayload,
  ) async {
    final res = await ApiClient.post('/api/messages/$peerId', body: encryptedPayload);
    return asJsonMap(res);
  }

  /// Ambil public key bundle user lain untuk memulai sesi E2EE
  static Future<Map<String, dynamic>?> getKeyBundle(String userId) async {
    try {
      final res = await ApiClient.get('/api/keys/$userId');
      return asJsonMap(res);
    } catch (_) {
      return null;
    }
  }

  /// Ambil public key bundle milik kita sendiri dari server
  /// Untuk verifikasi bahwa key lokal == key di server
  static Future<Map<String, dynamic>?> getMyKeyBundle() async {
    try {
      final res = await ApiClient.get('/api/keys/me');
      return asJsonMap(res);
    } catch (_) {
      return null;
    }
  }

  /// Upload public key bundle ke server (dipanggil sekali saat login pertama)
  static Future<bool> registerKeys(Map<String, String> keyBundle) async {
    try {
      await ApiClient.post('/api/keys/register', body: keyBundle);
      return true;
    } catch (_) {
      return false;
    }
  }
}

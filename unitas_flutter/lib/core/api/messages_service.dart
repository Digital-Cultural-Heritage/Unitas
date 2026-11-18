import 'api_client.dart';

class MessagesService {
  static Future<Map<String, dynamic>> getConversations() async {
    final res = await ApiClient.get('/api/messages/conversations');
    return Map<String, dynamic>.from(res);
  }

  static Future<List<Map<String, dynamic>>> getMessages(String peerId) async {
    final res = await ApiClient.get('/api/messages/$peerId');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  static Future<Map<String, dynamic>> sendMessage(String peerId, String content) async {
    final res = await ApiClient.post('/api/messages/$peerId', body: {'content': content});
    return Map<String, dynamic>.from(res);
  }
}

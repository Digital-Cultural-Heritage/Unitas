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

  static Future<Map<String, dynamic>> sendMessage(String peerId, String content) async {
    final res = await ApiClient.post('/api/messages/$peerId', body: {'content': content});
    return asJsonMap(res);
  }
}

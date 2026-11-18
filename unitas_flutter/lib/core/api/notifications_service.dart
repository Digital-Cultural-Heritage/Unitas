import 'api_client.dart';

class NotificationsService {
  static Future<Map<String, dynamic>> getNotifications({int limit = 30}) async {
    final res = await ApiClient.get('/api/notifications?limit=$limit');
    return Map<String, dynamic>.from(res);
  }

  static Future<void> markAsRead(String id) async {
    await ApiClient.put('/api/notifications/$id/read');
  }

  static Future<void> markAllAsRead() async {
    await ApiClient.put('/api/notifications/read-all');
  }
}

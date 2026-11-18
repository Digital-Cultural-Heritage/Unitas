import '../utils/json_utils.dart';
import 'api_client.dart';

class StatsService {
  static Future<Map<String, dynamic>> getStats() async {
    final res = await ApiClient.get('/api/stats', auth: false);
    return asJsonMap(res);
  }
}

import 'api_client.dart';

class EventsService {
  // ── Get events ─────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getEvents({String? category}) async {
    final params = StringBuffer('/api/events?limit=30');
    if (category != null && category != 'Semua') {
      params.write('&category=${Uri.encodeComponent(category)}');
    }
    final res = await ApiClient.get(params.toString(), auth: false);
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Register to event ──────────────────────────────────────────────────
  static Future<void> register(String eventId) async {
    await ApiClient.post('/api/events/$eventId/register');
  }

  // ── Unregister from event ──────────────────────────────────────────────
  static Future<void> unregister(String eventId) async {
    await ApiClient.delete('/api/events/$eventId/register');
  }

  // ── Get My Events ──────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyEvents() async {
    final res = await ApiClient.get('/api/events/my-events/all');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Get Attendees ──────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAttendees(String eventId) async {
    final res = await ApiClient.get('/api/events/$eventId/attendees');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Update Event ───────────────────────────────────────────────────────
  static Future<void> updateEvent(String eventId, Map<String, dynamic> data) async {
    await ApiClient.put('/api/events/$eventId', body: data);
  }

  // ── Delete Event ───────────────────────────────────────────────────────
  static Future<void> deleteEvent(String eventId) async {
    await ApiClient.delete('/api/events/$eventId');
  }
}

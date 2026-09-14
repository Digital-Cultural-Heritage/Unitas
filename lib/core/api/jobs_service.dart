import 'api_client.dart';

class JobsService {
  // ── Get jobs ───────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getJobs({
    String? q,
    bool? isRemote,
  }) async {
    final params = StringBuffer('/api/jobs?limit=30');
    if (q != null && q.isNotEmpty) params.write('&q=${Uri.encodeComponent(q)}');
    if (isRemote == true) params.write('&is_remote=true');

    final res = await ApiClient.get(params.toString(), auth: false);
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Get saved jobs ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getSavedJobs() async {
    final res = await ApiClient.get('/api/jobs/saved');
    final list = res['data'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  // ── Toggle save ────────────────────────────────────────────────────────
  static Future<bool> toggleSave(String jobId) async {
    final res = await ApiClient.post('/api/jobs/$jobId/save');
    return res['saved'] == true;
  }
}

import '../utils/json_utils.dart';
import 'api_client.dart';

class JobsService {
  // ── Get jobs ───────────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getJobs({
    String? q,
    bool? isRemote,
    int page = 1,
  }) async {
    final params = StringBuffer('/api/jobs?page=$page&limit=20');
    if (q != null && q.isNotEmpty) params.write('&q=${Uri.encodeComponent(q)}');
    if (isRemote == true) params.write('&is_remote=true');

    final res = await ApiClient.get(params.toString(), auth: false);
    return asJsonMapList(res);
  }

  // ── Get saved jobs ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getSavedJobs() async {
    final res = await ApiClient.get('/api/jobs/saved');
    return asJsonMapList(res);
  }

  // ── Toggle save ────────────────────────────────────────────────────────
  static Future<bool> toggleSave(String jobId) async {
    final res = asJsonMap(await ApiClient.post('/api/jobs/$jobId/save'));
    return res['saved'] == true;
  }

  // ── My Jobs (created by current user) ──────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyJobs() async {
    final res = await ApiClient.get('/api/jobs/my-jobs/all');
    return asJsonMapList(res);
  }

  // ── Update Job ─────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> updateJob(String jobId, Map<String, dynamic> data) async {
    final res = await ApiClient.put('/api/jobs/$jobId', body: data);
    return asJsonMap(res);
  }

  // ── Delete Job ─────────────────────────────────────────────────────────
  static Future<void> deleteJob(String jobId) async {
    await ApiClient.delete('/api/jobs/$jobId');
  }
}

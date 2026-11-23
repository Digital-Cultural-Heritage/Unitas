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

  static Future<Map<String, dynamic>?> getJobById(String jobId) async {
    if (jobId.isEmpty) return null;
    try {
      final res = asJsonMap(await ApiClient.get('/api/jobs/$jobId', auth: false));
      final data = res['data'];
      if (data is Map) return Map<String, dynamic>.from(data);
      if (res['id'] != null) return res;
      return null;
    } on ApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 400) return null;
      rethrow;
    }
  }

  // ── Get saved jobs ─────────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getSavedJobs() async {
    final res = await ApiClient.get('/api/jobs/saved');
    return asJsonMapList(res);
  }

  // ── Get applied jobs ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAppliedJobs() async {
    final res = await ApiClient.get('/api/jobs/applied');
    return asJsonMapList(res);
  }

  // ── Toggle save ────────────────────────────────────────────────────────
  static Future<bool> toggleSave(String jobId) async {
    final res = asJsonMap(await ApiClient.post('/api/jobs/$jobId/save'));
    return res['saved'] == true;
  }

  // ── Upload & compress CV PDF (max 1 MB) ───────────────────────────────
  static Future<Map<String, dynamic>> uploadCv({
    required List<int> bytes,
    required String filename,
  }) async {
    final res = await ApiClient.uploadPdf(
      '/api/upload/cv',
      bytes: bytes,
      filename: filename,
    );
    return asJsonMap(res);
  }

  // ── Apply job ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> applyJob(
    String jobId, {
    required String cvUrl,
    String? coverNote,
  }) async {
    final body = <String, dynamic>{'cv_url': cvUrl};
    if (coverNote != null && coverNote.trim().isNotEmpty) {
      body['cover_note'] = coverNote.trim();
    }
    final res = await ApiClient.post('/api/jobs/$jobId/apply', body: body);
    return asJsonMap(res);
  }

  // ── My Jobs (created by current user) ──────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyJobs() async {
    final res = await ApiClient.get('/api/jobs/my-jobs/all');
    return asJsonMapList(res);
  }

  // ── Job Applicants (for poster) ────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getJobApplicants(String jobId) async {
    final res = await ApiClient.get('/api/jobs/$jobId/applicants');
    return asJsonMapList(res);
  }

  // ── Update Application Status ──────────────────────────────────────────
  static Future<Map<String, dynamic>> updateApplicationStatus(
    String applicationId,
    String status,
  ) async {
    final res = await ApiClient.put(
      '/api/jobs/applications/$applicationId/status',
      body: {'status': status},
    );
    return asJsonMap(res);
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

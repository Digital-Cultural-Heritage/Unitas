/// Helper parsing JSON yang aman dari null dan tipe tidak terduga.
Map<String, dynamic> asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asJsonMapList(
  dynamic value, {
  String dataKey = 'data',
}) {
  final raw = value is Map ? value[dataKey] : value;
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw.whereType<Map>().map(asJsonMap).toList();
}

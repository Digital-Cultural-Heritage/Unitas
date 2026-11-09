const fs = require('fs');
let c = fs.readFileSync('lib/core/api/api_client.dart', 'utf8');
c = c.replace(
  "import 'package:shared_preferences/shared_preferences.dart';",
  "import 'package:shared_preferences/shared_preferences.dart';\nimport 'package:flutter_dotenv/flutter_dotenv.dart';"
);
c = c.replace(
  "const String kBaseUrl = 'http://localhost:3002';",
  "String get kBaseUrl => dotenv.env['BACKEND_URL'] ?? 'http://localhost:3002';"
);
fs.writeFileSync('lib/core/api/api_client.dart', c, 'utf8');

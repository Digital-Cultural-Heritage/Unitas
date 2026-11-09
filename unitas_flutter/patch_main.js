const fs = require('fs');
let c = fs.readFileSync('lib/main.dart', 'utf8');
c = c.replace(
  "import 'screens/profile_screen.dart';",
  "import 'screens/profile_screen.dart';\nimport 'package:flutter_dotenv/flutter_dotenv.dart';"
);
c = c.replace(
  "void main() {",
  "Future<void> main() async {"
);
c = c.replace(
  "WidgetsFlutterBinding.ensureInitialized();",
  "WidgetsFlutterBinding.ensureInitialized();\n  await dotenv.load(fileName: \".env\");"
);
fs.writeFileSync('lib/main.dart', c, 'utf8');

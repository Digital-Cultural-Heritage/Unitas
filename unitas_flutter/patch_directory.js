const fs = require('fs');
let c = fs.readFileSync('lib/screens/directory_screen.dart', 'utf8');
c = c.replace(
  "await UsersService.connect(userId);\n                                if (!mounted) return;\n                                ScaffoldMessenger.of(context).showSnackBar(\n                                  const SnackBar(content: Text('Permintaan koneksi dikirim')));",
  "final res = await UsersService.connect(userId);\n                                if (!mounted) return;\n                                ScaffoldMessenger.of(context).showSnackBar(\n                                  SnackBar(content: Text(res['message'] ?? 'Permintaan koneksi dikirim')));"
);
fs.writeFileSync('lib/screens/directory_screen.dart', c, 'utf8');

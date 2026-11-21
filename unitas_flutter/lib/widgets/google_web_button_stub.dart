import 'package:flutter/widgets.dart';

/// Placeholder untuk platform non-Web (Android/iOS memakai tombol Flutter biasa).
Widget buildGoogleWebButton({required Future<void> Function() initialize}) {
  return const SizedBox.shrink();
}

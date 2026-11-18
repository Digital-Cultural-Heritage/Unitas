import 'dart:typed_data';

import 'pdf_picker_stub.dart'
    if (dart.library.js_interop) 'pdf_picker_web.dart' as impl;

class PickedPdf {
  final String name;
  final Uint8List bytes;

  const PickedPdf({required this.name, required this.bytes});
}

class PdfPicker {
  static Future<PickedPdf?> pickPdf() => impl.pickPdfImpl();
}

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'pdf_picker.dart';

web.Element _ensureContainer() {
  const id = '__unitas_pdf_picker';
  final existing = web.document.querySelector('#$id');
  if (existing != null) return existing;
  final el = web.document.createElement('flt-pdf-picker-inputs')..id = id;
  web.document.body!.append(el);
  return el;
}

Future<Uint8List?> _readFileBytes(web.File file) {
  final completer = Completer<Uint8List?>();
  final reader = web.FileReader();

  reader.onloadend = ((web.Event _) {
    if (!completer.isCompleted) {
      final buf = (reader.result as JSArrayBuffer?)?.toDart;
      completer.complete(buf?.asUint8List());
    }
  }).toJS;

  reader.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }).toJS;

  reader.readAsArrayBuffer(file);
  return completer.future;
}

Future<void> _handleSelection(
  web.HTMLInputElement input,
  Completer<PickedPdf?> completer,
) async {
  try {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final bytes = await _readFileBytes(file);
    if (!completer.isCompleted) {
      if (bytes == null) {
        completer.completeError('Gagal membaca isi file PDF dari perangkat.');
      } else {
        completer.complete(PickedPdf(name: file.name, bytes: bytes));
      }
    }
  } catch (e) {
    if (!completer.isCompleted) completer.completeError(e);
  } finally {
    input.remove();
  }
}

Future<PickedPdf?> pickPdfImpl() {
  final completer = Completer<PickedPdf?>();
  final container = _ensureContainer();
  container.replaceChildren(<JSAny>[].toJS);

  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'application/pdf,.pdf';
  input.style.position = 'fixed';
  input.style.left = '-9999px';
  input.style.width = '1px';
  input.style.height = '1px';
  input.style.opacity = '0';

  input.onchange = ((web.Event _) {
    unawaited(_handleSelection(input, completer));
  }).toJS;

  input.oncancel = ((web.Event _) {
    input.remove();
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  input.onerror = ((web.Event e) {
    input.remove();
    if (!completer.isCompleted) {
      completer.completeError('Gagal membuka pemilih file ($e).');
    }
  }).toJS;

  container.append(input);
  input.click();
  return completer.future;
}

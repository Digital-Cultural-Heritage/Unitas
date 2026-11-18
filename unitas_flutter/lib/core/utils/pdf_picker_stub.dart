import 'package:file_picker/file_picker.dart';
import 'pdf_picker.dart';

Future<PickedPdf?> pickPdfImpl() async {
  final f = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  if (f == null) return null;
  final bytes = await f.readAsBytes();
  return PickedPdf(name: f.name, bytes: bytes);
}

import 'dart:typed_data';
import 'package:http_parser/http_parser.dart';

class ImageValidationException implements Exception {
  final String message;
  const ImageValidationException(this.message);

  @override
  String toString() => message;
}

class ImageValidator {
  static const int maxBytes = 10 * 1024 * 1024; // 10 MB

  static const Set<String> _allowedExt = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
  };

  /// Memvalidasi ekstensi, ukuran, dan magic bytes gambar untuk mencegah upload file berbahaya.
  static MediaType validate(List<int> bytes, String filename) {
    if (bytes.isEmpty) {
      throw const ImageValidationException('File gambar kosong.');
    }
    if (bytes.length > maxBytes) {
      throw const ImageValidationException('Ukuran gambar maksimal 10 MB.');
    }

    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase().trim()
        : '';
    if (ext.isEmpty || !_allowedExt.contains(ext)) {
      throw const ImageValidationException(
        'Format file tidak diizinkan. Hanya JPG, PNG, WebP, GIF, atau HEIC.',
      );
    }

    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final detected = _detectMagicType(data);
    if (detected == null) {
      throw const ImageValidationException(
        'File bukan gambar yang valid atau terindikasi bukan file foto asli.',
      );
    }
    return detected;
  }

  static MediaType? _detectMagicType(Uint8List b) {
    if (b.length < 12) return null;

    // JPEG: FF D8 FF
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return MediaType('image', 'jpeg');
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return MediaType('image', 'png');
    }

    // GIF: GIF87a / GIF89a
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38) {
      return MediaType('image', 'gif');
    }

    // WebP: RIFF....WEBP
    if (b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return MediaType('image', 'webp');
    }

    // HEIC/HEIF: ....ftypheic / ftypheix / ftypmif1
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return MediaType('image', 'heic');
    }

    return null;
  }
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unitas_flutter/core/api/auth_service.dart';
import 'package:unitas_flutter/core/theme/colors.dart';
import 'package:unitas_flutter/core/utils/image_validator.dart';
import 'package:unitas_flutter/core/utils/json_utils.dart';
import 'package:unitas_flutter/screens/login_screen.dart';
import 'package:unitas_flutter/widgets/avatar.dart';

void main() {
  testWidgets('UnitasAvatar displays initials', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnitasAvatar(initials: 'KP', color: brandNavy, size: 40),
        ),
      ),
    );

    expect(find.text('KP'), findsOneWidget);
  });

  testWidgets('LoginScreen renders key auth controls and validates input', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(onLoginSuccess: () {}),
      ),
    );

    expect(find.text('Masuk'), findsOneWidget);
    expect(find.text('Lupa kata sandi?'), findsOneWidget);
    expect(find.text('Daftar sekarang'), findsOneWidget);

    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pump();

    expect(find.text('Email tidak valid'), findsOneWidget);
    expect(find.text('Password minimal 8 karakter'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'user@gmail.com');
    await tester.ensureVisible(find.text('Masuk'));
    await tester.tap(find.text('Masuk'));
    await tester.pump();

    expect(find.text('Gunakan email @unud.ac.id atau @student.unud.ac.id'), findsOneWidget);
    expect(AuthService.isAllowedUnudEmail('mahasiswa@student.unud.ac.id'), isTrue);
    expect(AuthService.isAllowedUnudEmail('dosen@unud.ac.id'), isTrue);
    expect(AuthService.isAllowedUnudEmail('outsider@gmail.com'), isFalse);
  });

  group('json_utils', () {
    test('asJsonMap handles null, non-map, and dynamic maps safely', () {
      expect(asJsonMap(null), isEmpty);
      expect(asJsonMap('bad'), isEmpty);
      expect(asJsonMap(<dynamic, dynamic>{'id': 1, 'name': 'Unitas'}), {'id': 1, 'name': 'Unitas'});
    });

    test('asJsonMapList filters nulls and non-maps safely', () {
      final res = {
        'data': [
          {'id': 'a'},
          null,
          'unexpected',
          <dynamic, dynamic>{'id': 'b'},
        ],
      };
      expect(asJsonMapList(res), [
        {'id': 'a'},
        {'id': 'b'},
      ]);
      expect(asJsonMapList({'data': null}), isEmpty);
      expect(asJsonMapList(null), isEmpty);
    });
  });

  group('ImageValidator', () {
    test('accepts valid JPEG and PNG magic bytes', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0]);

      expect(ImageValidator.validate(jpeg, 'photo.jpg').mimeType, 'image/jpeg');
      expect(ImageValidator.validate(png, 'avatar.PNG').mimeType, 'image/png');
    });

    test('rejects empty bytes, disallowed extensions, and fake magic bytes', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final fake = Uint8List.fromList(List.filled(16, 0x41));

      expect(() => ImageValidator.validate([], 'a.jpg'), throwsA(isA<ImageValidationException>()));
      expect(() => ImageValidator.validate(jpeg, 'shell.exe'), throwsA(isA<ImageValidationException>()));
      expect(() => ImageValidator.validate(fake, 'fake.png'), throwsA(isA<ImageValidationException>()));
    });
  });
}

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unitas_flutter/core/api/api_client.dart';
import 'package:unitas_flutter/core/api/auth_service.dart';
import 'package:unitas_flutter/core/theme/colors.dart';
import 'package:unitas_flutter/core/utils/image_validator.dart';
import 'package:unitas_flutter/core/utils/json_utils.dart';
import 'package:unitas_flutter/screens/login_screen.dart';
import 'package:unitas_flutter/screens/profile_screen.dart';
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

  testWidgets('showSetPasswordSheet validates, shows server errors for retry, and handles skip', (WidgetTester tester) async {
    String? savedPassword;
    bool? sheetResult;
    var shouldFailSave = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  sheetResult = await showSetPasswordSheet(
                    context: context,
                    email: 'siti@student.unud.ac.id',
                    isPostLoginPrompt: true,
                    onSave: (pw) async {
                      if (shouldFailSave) {
                        throw const ApiException('Gagal menyimpan di server', 500);
                      }
                      savedPassword = pw;
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Buat Kata Sandi'), findsOneWidget);
    expect(find.textContaining('siti@student.unud.ac.id'), findsOneWidget);
    expect(find.text('Simpan Kata Sandi'), findsOneWidget);
    expect(find.text('Lewati dulu'), findsOneWidget);

    // Rejects short password & mismatched confirmation
    await tester.enterText(find.byType(TextFormField).at(0), '123');
    await tester.enterText(find.byType(TextFormField).at(1), '456');
    await tester.ensureVisible(find.text('Simpan Kata Sandi'));
    await tester.tap(find.text('Simpan Kata Sandi'));
    await tester.pump();

    expect(find.text('Password minimal 8 karakter'), findsOneWidget);
    expect(find.text('Konfirmasi kata sandi tidak cocok'), findsOneWidget);
    expect(savedPassword, isNull);

    // Shows ApiException error, keeps sheet open, and allows retry to succeed
    shouldFailSave = true;
    await tester.enterText(find.byType(TextFormField).at(0), 'Password123');
    await tester.enterText(find.byType(TextFormField).at(1), 'Password123');
    await tester.ensureVisible(find.text('Simpan Kata Sandi'));
    await tester.tap(find.text('Simpan Kata Sandi'));
    await tester.pumpAndSettle();

    expect(find.text('Gagal menyimpan di server'), findsOneWidget);
    expect(find.text('Buat Kata Sandi'), findsOneWidget);

    shouldFailSave = false;
    await tester.ensureVisible(find.text('Simpan Kata Sandi'));
    await tester.tap(find.text('Simpan Kata Sandi'));
    await tester.pumpAndSettle();

    expect(savedPassword, 'Password123');
    expect(sheetResult, isTrue);
    expect(find.text('Buat Kata Sandi'), findsNothing);

    // Tapping "Lewati dulu" closes with false without calling onSave
    savedPassword = null;
    sheetResult = null;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Lewati dulu'));
    await tester.tap(find.text('Lewati dulu'));
    await tester.pumpAndSettle();

    expect(savedPassword, isNull);
    expect(sheetResult, isFalse);
  });

  testWidgets('showDeleteAccountDialog requires typing HAPUS, surfaces ApiException, and pops true on retry', (WidgetTester tester) async {
    var failFirst = true;
    var calls = 0;
    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  dialogResult = await showDeleteAccountDialog(
                    context: context,
                    onConfirm: () async {
                      calls++;
                      if (failFirst) {
                        throw const ApiException('Server gagal menghapus akun', 500);
                      }
                    },
                  );
                },
                child: const Text('OpenDelete'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OpenDelete'));
    await tester.pumpAndSettle();

    // Button stays disabled before typing HAPUS
    await tester.tap(find.text('Hapus Akun'));
    await tester.pump();
    expect(calls, 0);

    // Typing "hapus" enables button; first attempt shows error and stays open
    await tester.enterText(find.byType(TextField), 'hapus');
    await tester.pump();
    await tester.tap(find.text('Hapus Akun'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Server gagal menghapus akun'), findsOneWidget);
    expect(find.text('Hapus Akun Permanen?'), findsOneWidget);

    // Retry succeeds and pops with true
    failFirst = false;
    await tester.tap(find.text('Hapus Akun'));
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(dialogResult, isTrue);
    expect(find.text('Hapus Akun Permanen?'), findsNothing);
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

  group('ApiClient session fallback', () {
    test('keeps tokens and user in memory when secure storage throws', () async {
      await ApiClient.saveSession(
        accessToken: 'acc-123',
        refreshToken: 'ref-456',
        userJson: '{"id":"u1"}',
      );
      expect(await ApiClient.getToken(), 'acc-123');
      expect(await ApiClient.getRefreshToken(), 'ref-456');
      expect(await ApiClient.getStoredUserJson(), '{"id":"u1"}');

      await ApiClient.saveStoredUserJson('{"id":"u2"}');
      expect(await ApiClient.getStoredUserJson(), '{"id":"u2"}');

      await ApiClient.clearSession();
      expect(await ApiClient.getToken(), isNull);
      expect(await ApiClient.getRefreshToken(), isNull);
      expect(await ApiClient.getStoredUserJson(), isNull);
    });
  });
}

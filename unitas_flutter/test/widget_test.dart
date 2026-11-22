import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unitas_flutter/core/api/api_client.dart';
import 'package:unitas_flutter/core/api/auth_service.dart';
import 'package:unitas_flutter/core/api/posts_service.dart';
import 'package:unitas_flutter/core/theme/colors.dart';
import 'package:unitas_flutter/core/utils/image_validator.dart';
import 'package:unitas_flutter/core/utils/json_utils.dart';
import 'package:unitas_flutter/screens/directory_screen.dart';
import 'package:unitas_flutter/screens/login_screen.dart';
import 'package:unitas_flutter/screens/profile_screen.dart';
import 'package:unitas_flutter/widgets/avatar.dart';
import 'package:unitas_flutter/widgets/linkable_text.dart';

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

  testWidgets('showSetPasswordSheet enforces mandatory setup post-login and optional mode in settings', (WidgetTester tester) async {
    String? savedPassword;
    bool? sheetResult;
    var shouldFailSave = false;
    var postLoginPrompt = true;

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
                    isPostLoginPrompt: postLoginPrompt,
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
    expect(find.textContaining('wajib membuat kata sandi'), findsOneWidget);
    expect(find.text('Simpan Kata Sandi'), findsOneWidget);
    expect(find.text('Lewati dulu'), findsNothing);
    expect(find.text('Keluar'), findsOneWidget);

    // Hardware Back / Navigator.maybePop cannot dismiss mandatory post-login prompt
    await Navigator.maybePop(tester.element(find.text('Buat Kata Sandi')));
    await tester.pumpAndSettle();
    expect(find.text('Buat Kata Sandi'), findsOneWidget);

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

    // Tapping "Keluar" in mandatory mode closes with false without calling onSave
    savedPassword = null;
    sheetResult = null;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Keluar'));
    await tester.tap(find.text('Keluar'));
    await tester.pumpAndSettle();

    expect(savedPassword, isNull);
    expect(sheetResult, isFalse);

    // Optional Profile Settings mode shows "Batal" and closes with false
    postLoginPrompt = false;
    sheetResult = null;
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Batal'), findsOneWidget);
    expect(find.text('Keluar'), findsNothing);
    await tester.ensureVisible(find.text('Batal'));
    await tester.tap(find.text('Batal'));
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

  group('PostLikeSync', () {
    test('rapid double-tap updates optimistically and sends zero network calls', () async {
      var calls = 0;
      final emitted = <PostLikeSnapshot>[];
      final sync = PostLikeSync(
        debounceDuration: const Duration(milliseconds: 25),
        sendLike: (id, liked) async {
          calls++;
          return PostLikeResult(liked: liked, likesCount: liked ? 6 : 5);
        },
      );
      sync.addListener((_, snap) => emitted.add(snap));

      sync.toggle(postId: 'p1', currentLiked: false, currentCount: 5);
      sync.toggle(postId: 'p1', currentLiked: true, currentCount: 6);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 0);
      expect(emitted.map((s) => (s.liked, s.likesCount)).toList(), [
        (true, 6),
        (false, 5),
      ]);
      expect(sync.pendingFor('p1'), isNull);
      sync.clear();
    });

    test('tap while in flight updates optimistically and reconciles with one follow-up call', () async {
      final c1 = Completer<PostLikeResult>();
      final c2 = Completer<PostLikeResult>();
      final sent = <bool>[];
      final emitted = <PostLikeSnapshot>[];
      final sync = PostLikeSync(
        debounceDuration: const Duration(seconds: 30),
        sendLike: (id, liked) {
          sent.add(liked);
          return sent.length == 1 ? c1.future : c2.future;
        },
      );
      sync.addListener((_, snap) => emitted.add(snap));

      // Tap 1 (like) + flush starts request 1
      sync.toggle(postId: 'p1', currentLiked: false, currentCount: 5);
      sync.flush('p1');
      expect(sent, [true]);

      // Tap 2 (unlike) while request 1 is still in flight
      sync.toggle(postId: 'p1', currentLiked: true, currentCount: 6);
      expect(sent, [true]);
      expect(emitted.last.liked, isFalse);
      expect(emitted.last.likesCount, 5);

      // Complete request 1 -> triggers reconciliation request 2 (liked: false)
      c1.complete(const PostLikeResult(liked: true, likesCount: 6));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(sent, [true, false]);

      // Complete request 2 -> settles cleanly at (false, 5)
      c2.complete(const PostLikeResult(liked: false, likesCount: 5));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(emitted.last.liked, isFalse);
      expect(emitted.last.likesCount, 5);
      expect(sync.pendingFor('p1'), isNull);
      sync.clear();
    });

    test('server failure reverts cleanly to last confirmed snapshot', () async {
      final emitted = <PostLikeSnapshot>[];
      final sync = PostLikeSync(
        debounceDuration: const Duration(seconds: 30),
        sendLike: (_, _) async => throw const ApiException('Server error', 500),
      );
      sync.addListener((_, snap) => emitted.add(snap));

      sync.toggle(postId: 'p1', currentLiked: false, currentCount: 5);
      sync.flush('p1');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(emitted.map((s) => (s.liked, s.likesCount)).toList(), [
        (true, 6),
        (false, 5),
      ]);
      expect(sync.pendingFor('p1'), isNull);
      sync.clear();
    });

    test('flush dispatches pending debounced like immediately', () async {
      final sent = <bool>[];
      final sync = PostLikeSync(
        debounceDuration: const Duration(seconds: 30),
        sendLike: (_, liked) async {
          sent.add(liked);
          return PostLikeResult(liked: liked, likesCount: 6);
        },
      );

      sync.toggle(postId: 'p1', currentLiked: false, currentCount: 5);
      expect(sent, isEmpty);

      sync.flush('p1');
      await Future<void>.delayed(Duration.zero);
      expect(sent, [true]);
      sync.clear();
    });
  });

  group('Directory pagination', () {
    test('buildVisiblePageNumbers produces compact page ranges with ellipsis', () {
      expect(buildVisiblePageNumbers(2, 4), [1, 2, 3, 4]);
      expect(buildVisiblePageNumbers(2, 10), [1, 2, 3, 4, null, 10]);
      expect(buildVisiblePageNumbers(5, 10), [1, null, 4, 5, 6, null, 10]);
      expect(buildVisiblePageNumbers(9, 10), [1, null, 7, 8, 9, 10]);
    });

    testWidgets('DirectoryPaginationBar displays item range and triggers page changes with boundary guards', (WidgetTester tester) async {
      final tapped = <int>[];

      Future<void> pumpBar(int page, int count) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DirectoryPaginationBar(
                currentPage: page,
                totalPages: 5,
                totalItems: 72,
                pageSize: 15,
                currentCount: count,
                loading: false,
                onPageChanged: tapped.add,
              ),
            ),
          ),
        );
      }

      // Page 2 of 5 -> shows 16-30, taps 4, prev (1), next (3)
      await pumpBar(2, 15);
      expect(find.text('Menampilkan 16–30 dari 72 alumni'), findsOneWidget);

      await tester.tap(find.text('4'));
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(tapped, [4, 1, 3]);

      // First page disables Previous button
      tapped.clear();
      await pumpBar(1, 15);
      final prevFirst = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left),
      );
      expect(prevFirst.onPressed, isNull);
      await tester.tap(find.byIcon(Icons.chevron_right));
      expect(tapped, [2]);

      // Last page shows 61-72 and disables Next button
      tapped.clear();
      await pumpBar(5, 12);
      expect(find.text('Menampilkan 61–72 dari 72 alumni'), findsOneWidget);
      final nextLast = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(nextLast.onPressed, isNull);
      await tester.tap(find.byIcon(Icons.chevron_left));
      expect(tapped, [4]);
    });
  });

  group('LinkableText', () {
    test('parseSegments detects http, https, and www URLs while trimming trailing punctuation', () {
      final segments = LinkableText.parseSegments(
        'Daftar di https://unud.ac.id/info, atau cek www.linkedin.com/in/alumni! (http://example.org/test).',
      );

      final links = segments.where((s) => s.isLink).toList();
      expect(links.length, 3);
      expect(links[0].text, 'https://unud.ac.id/info');
      expect(links[0].url, 'https://unud.ac.id/info');
      expect(links[1].text, 'www.linkedin.com/in/alumni');
      expect(links[1].url, 'https://www.linkedin.com/in/alumni');
      expect(links[2].text, 'http://example.org/test');
      expect(links[2].url, 'http://example.org/test');
    });

    test('parseSegments ignores plain words with dots without scheme or www', () {
      final segments = LinkableText.parseSegments(
        'Email saya nama.alumni dan file laporan.pdf tidak jadi link.',
      );
      expect(segments.where((s) => s.isLink), isEmpty);
    });

    testWidgets('LinkableText renders full text cleanly', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: LinkableText('Info acara: https://unud.ac.id/acara'),
          ),
        ),
      );
      expect(
        find.text('Info acara: https://unud.ac.id/acara', findRichText: true),
        findsOneWidget,
      );
    });
  });
}

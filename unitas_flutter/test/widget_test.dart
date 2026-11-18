import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unitas_flutter/core/theme/colors.dart';
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

    await tester.tap(find.text('Masuk'));
    await tester.pump();

    expect(find.text('Email tidak valid'), findsOneWidget);
    expect(find.text('Password minimal 8 karakter'), findsOneWidget);
  });
}

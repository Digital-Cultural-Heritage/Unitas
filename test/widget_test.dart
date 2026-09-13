import 'package:flutter_test/flutter_test.dart';
import 'package:unitas_flutter/main.dart';

void main() {
  testWidgets('Unitas app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const UnitasApp());
    expect(find.text('Beranda'), findsOneWidget);
  });
}

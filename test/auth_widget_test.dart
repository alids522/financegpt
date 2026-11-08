import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/main.dart';
import 'package:finance_tracker/theme.dart';

void main() {
  for (final width in [360.0, 768.0, 1366.0]) {
    testWidgets('authentication fits $width logical pixels', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: financeTheme(Brightness.light),
          home: const AuthPage(),
        ),
      );
      expect(find.text('Username atau Email'), findsOneWidget);
      expect(find.textContaining('Lupa password'), findsNothing);
      expect(find.byType(BottomNavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Belum punya akun? Daftar'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi password'), findsOneWidget);
      await tester.tap(find.text('Buat akun'));
      await tester.pumpAndSettle();
      expect(find.text('3–24 huruf, angka, atau underscore.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

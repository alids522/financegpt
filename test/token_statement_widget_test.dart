import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:finance_tracker/shell.dart';
import 'package:finance_tracker/domain.dart';
import 'package:finance_tracker/theme.dart';
import 'shell_widget_test.dart' show FixtureStore;

class IntegrationFixture extends FixtureStore {
  String? statementPath;
  @override
  Future<dynamic> api(
    String path, {
    String method = 'GET',
    FinanceRow? body,
    String? key,
  }) async {
    if (path == 'tokens' && method == 'POST') {
      return {
        'token': 'fgt_${'a' * 64}',
        'expires_at': financeNow()
            .add(const Duration(days: 30))
            .toIso8601String(),
      };
    }
    if (path.contains('/statement?')) {
      statementPath = path;
      return {
        'account_name': 'QA cash',
        'currency': 'IDR',
        'timezone': 'Asia/Jakarta',
        'opening_minor': 1000000,
        'debit_minor': 35000,
        'credit_minor': 0,
        'closing_minor': 965000,
        'row_count': 1,
        'generated_at': financeNow().toIso8601String(),
        'rows': [
          {
            'entry_id': 'entry-1',
            'transaction_id': 'transaction-1',
            'posted_at': financeNow().toIso8601String(),
            'description': 'Pembelian pengujian',
            'merchant': 'Merchant QA',
            'type': 'expense',
            'debit_minor': 35000,
            'credit_minor': 0,
            'balance_minor': 965000,
          },
        ],
      };
    }
    return {'data': []};
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
  });
  testWidgets('statement preview uses inclusive month and exports a real PDF', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = IntegrationFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: financeTheme(Brightness.light),
        home: Scaffold(
          body: AccountStatementDialog(
            store: store,
            account: store.rows('accounts').first,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tampilkan mutasi'));
    await tester.pumpAndSettle();
    final period = StatementRange.month(financeNow().year, financeNow().month);
    expect(
      store.statementPath,
      'accounts/cash/statement?start=${period.start}&end=${period.end}',
    );
    expect(find.text('Saldo akhir'), findsOneWidget);
    final fixture = FinanceRow.from(
      await store.api(
        'accounts/cash/statement?start=${period.start}&end=${period.end}',
      ),
    );
    final bytes = await tester.runAsync(
      () => buildAccountStatementPdf(fixture, period),
    );
    expect(utf8.decode(bytes!.take(5).toList()), '%PDF-');
    expect(
      String.fromCharCodes(bytes.skip(bytes.length - 32)),
      contains('%%EOF'),
    );
    if (const bool.fromEnvironment('GENERATE_PREVIEWS')) {
      await tester.runAsync(() async {
        await Directory('build/statement-preview').create(recursive: true);
        await File(
          'build/statement-preview/estatement.pdf',
        ).writeAsBytes(bytes);
      });
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('generated token is shown once and disappears after dismissal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: financeTheme(Brightness.light),
        home: FinanceShell(
          preferences: prefs,
          onTheme: (_) {},
          initialStore: IntegrationFixture(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final nav = find.text('API & AI Agents');
    await tester.scrollUntilVisible(
      nav,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await Scrollable.ensureVisible(tester.element(nav), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(nav);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generate token'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Generate token'),
      ),
    );
    await tester.pumpAndSettle();
    final secret = 'fgt_${'a' * 64}';
    expect(find.text(secret), findsOneWidget);
    await tester.tap(find.text('Sudah disimpan'));
    await tester.pumpAndSettle();
    expect(find.text(secret), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'dashboard renders forecast with zero actual and a nonzero budget',
    (tester) async {
      tester.view.physicalSize = const Size(393, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = IntegrationFixture();
      store.data['transactions'] = [];
      await tester.pumpWidget(
        MaterialApp(
          theme: financeTheme(Brightness.dark),
          home: FinanceShell(
            preferences: prefs,
            onTheme: (_) {},
            initialStore: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
      expect(find.textContaining('Forecast pengeluaran:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

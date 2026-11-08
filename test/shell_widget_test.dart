import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:finance_tracker/store.dart';
import 'package:finance_tracker/shell.dart';
import 'package:finance_tracker/theme.dart';

class FixtureStore extends FinanceStore {
  FixtureStore()
    : super(
        SupabaseClient(
          'https://example.invalid',
          'fixture',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      ) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1, 0);
    profile = {
      'display_name': 'Abdurahman',
      'theme': 'light',
      'base_currency': 'IDR',
      'week_start': 1,
    };
    data['accounts'] = [
      {
        'id': 'cash',
        'name': 'Cash',
        'type': 'cash',
        'currency': 'IDR',
        'balance': 12450000,
        'opening_balance': 10000000,
        'status': 'active',
      },
      {
        'id': 'bank',
        'name': 'Rekening utama',
        'type': 'bank',
        'currency': 'IDR',
        'balance': 5000000,
        'opening_balance': 5000000,
        'status': 'active',
      },
    ];
    data['categories'] = [
      {
        'id': 'food',
        'name': 'Makanan & Minuman',
        'type': 'expense',
        'archived': false,
      },
      {
        'id': 'salary',
        'name': 'Gaji & Bonus',
        'type': 'income',
        'archived': false,
      },
    ];
    data['transactions'] = [
      {
        'id': 't1',
        'type': 'expense',
        'status': 'posted',
        'amount': 35000,
        'currency': 'IDR',
        'account_id': 'cash',
        'category_id': 'food',
        'effective_at': now.toIso8601String(),
        'description': 'Makan siang',
        'merchant': 'Warung makan',
        'tags': [],
        'source': 'self',
        'row_version': 1,
      },
      {
        'id': 't2',
        'type': 'income',
        'status': 'posted',
        'amount': 6000000,
        'currency': 'IDR',
        'account_id': 'bank',
        'category_id': 'salary',
        'effective_at': start.toIso8601String(),
        'description': 'Gaji November',
        'merchant': '',
        'tags': [],
        'source': 'self',
        'row_version': 1,
      },
    ];
    data['budgets'] = [
      {
        'id': 'b1',
        'name': 'Pengeluaran bulanan',
        'amount': 5000000,
        'currency': 'IDR',
        'period_start': start.toIso8601String().substring(0, 10),
        'period_end': end.toIso8601String().substring(0, 10),
        'row_version': 1,
        'cadence': 'monthly',
        'rollover': 'none',
      },
    ];
  }
  @override
  Future<void> initialize() async {}
  @override
  Future<void> refresh() async {}
  @override
  String get uid => 'fixture-user';
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter.ttf'));
    await loader.load();
  });
  for (final width in [360.0, 768.0, 1366.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('sidebar and all P0 pages fit $width $brightness', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          MaterialApp(
            theme: financeTheme(brightness),
            home: FinanceShell(
              preferences: preferences,
              onTheme: (_) {},
              initialStore: FixtureStore(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BottomNavigationBar), findsNothing);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('GENERATE_PREVIEWS')) {
          await expectLater(
            find.byType(FinanceShell),
            matchesGoldenFile(
              'previews/dashboard-${width.toInt()}-${brightness.name}.png',
            ),
          );
        }
        for (final page in [
          'Transactions',
          'Accounts & Wallets',
          'Analytics',
          'Budgets',
          'Forecast',
          'Import & Export',
          'API & AI Agents',
          'Settings',
        ]) {
          if (width < 768) {
            await tester.tap(find.byTooltip('Buka navigasi'));
            await tester.pumpAndSettle();
          }
          final item = width >= 768 && width < 1200
              ? find.byTooltip(page)
              : find.text(page);
          await tester.scrollUntilVisible(
            item,
            150,
            scrollable: width < 768
                ? find
                      .descendant(
                        of: find.byType(Drawer),
                        matching: find.byType(Scrollable),
                      )
                      .first
                : find.byType(Scrollable).first,
          );
          await tester.tap(item);
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: '$page at $width $brightness',
          );
        }
      });
    }
  }
}

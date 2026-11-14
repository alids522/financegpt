import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:finance_tracker/shell.dart';
import 'package:finance_tracker/domain.dart';
import 'package:finance_tracker/theme.dart';
import 'token_statement_widget_test.dart' show IntegrationFixture;

class PolicyFixture extends IntegrationFixture {
  FinanceRow? saved;
  PolicyFixture(String mode) {
    data['agent_connections'] = [
      {
        'id': 'connection1',
        'oauth_client_id': 'pat:connection1',
        'display_name': 'API saya',
        'status': 'active',
      },
    ];
    data['personal_tokens'] = [
      {
        'id': 'token1',
        'connection_id': 'connection1',
        'prefix': 'fgt_test',
        'status': 'active',
        'expires_at': financeNow()
            .add(const Duration(days: 30))
            .toIso8601String(),
      },
    ];
    data['agent_permissions'] = [
      {
        'connection_id': 'connection1',
        'permission': 'transactions:read',
        'enabled': true,
      },
    ];
    data['agent_policies'] = [
      {
        'connection_id': 'connection1',
        'approval_mode': mode,
        'account_allowlist': [],
        'category_allowlist': [],
        'limits_json': {
          'create_limit': 1000,
          'edit_limit': 100,
          'daily_cap': 5000000,
          'hourly_cap': 17,
          'backdate_days': 14,
        },
      },
    ];
  }
  @override
  Future<dynamic> api(
    String path, {
    String method = 'GET',
    FinanceRow? body,
    String? key,
  }) async {
    if (path == 'agents/connections/connection1/policy' && method == 'POST') {
      saved = body;
      return {};
    }
    return super.api(path, method: method, body: body, key: key);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [360.0, 1000.0]) {
    testWidgets(
      'YOLO policy saves without resetting scopes and limits at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();
        final store = PolicyFixture(width == 360 ? 'risk' : 'yolo');
        await tester.pumpWidget(
          MaterialApp(
            theme: financeTheme(Brightness.light),
            home: FinanceShell(
              initialStore: store,
              preferences: prefs,
              onTheme: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (width == 360) {
          await tester.tap(find.byTooltip('Buka navigasi'));
          await tester.pumpAndSettle();
        }
        final nav = width >= 768 && width < 1200
            ? find.byTooltip('API & AI Agents')
            : find.text('API & AI Agents');
        await tester.scrollUntilVisible(
          nav,
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
        await Scrollable.ensureVisible(tester.element(nav), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(nav);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'agent page geometry');
        await tester.ensureVisible(find.byTooltip('Atur izin dan batas'));
        await tester.tap(find.byTooltip('Atur izin dan batas'));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: 'policy dialog geometry',
        );
        if (width == 360) {
          await tester.tap(find.byType(DropdownButtonFormField<String>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('YOLO · langsung jalankan').last);
          await tester.pumpAndSettle();
        }
        expect(find.text('YOLO · langsung jalankan'), findsOneWidget);
        await tester.tap(find.text('Simpan izin'));
        await tester.pumpAndSettle();
        expect(store.saved?['approval_mode'], 'yolo');
        expect(store.saved?['limits']['hourly_cap'], 17);
        expect(store.saved?['limits']['backdate_days'], 14);
        expect(store.saved?['permissions']['transactions:read'], isTrue);
        expect(
          store.saved?['permissions']['transactions:create'],
          isNot(isTrue),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}

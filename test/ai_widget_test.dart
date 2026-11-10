import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finance_tracker/shell.dart';
import 'package:finance_tracker/domain.dart';
import 'package:finance_tracker/theme.dart';
import 'token_statement_widget_test.dart' show IntegrationFixture;

class AiFixture extends IntegrationFixture {
  bool configured, approved = false;
  FinanceRow? saved;
  AiFixture({this.configured = true});
  @override
  Future<dynamic> api(
    String path, {
    String method = 'GET',
    FinanceRow? body,
    String? key,
  }) async {
    if (path == 'ai/providers' && method == 'GET') {
      return {
        'data': configured
            ? [
                {
                  'id': 'provider1',
                  'name': 'Gemini saya',
                  'format': 'gemini',
                  'base_url':
                      'https://generativelanguage.googleapis.com/v1beta',
                  'model': 'test-model',
                  'context_tokens': 32000,
                  'output_tokens': 2048,
                  'vision': true,
                  'tools': true,
                  'auto_record': false,
                },
              ]
            : [],
      };
    }
    if (path == 'ai/providers' && method == 'POST') {
      saved = body;
      configured = true;
      return {'id': 'provider1'};
    }
    if (path.startsWith('ai/providers/') && method == 'PATCH') {
      saved = body;
      return {'id': 'provider1'};
    }
    if (path.endsWith('/models')) {
      return {
        'data': [
          {'id': 'test-model', 'input_limit': 64000, 'output_limit': 8192},
        ],
      };
    }
    if (path == 'ai/chats' && method == 'GET') return {'data': []};
    if (path == 'ai/chats' && method == 'POST') return {'id': 'chat1'};
    if (path == 'ai/chats/chat1/send') {
      return {'content': 'Periksa usulan transaksi.'};
    }
    if (path == 'ai/chats/chat1/messages') {
      return {
        'data': [
          {
            'role': 'assistant',
            'content': 'Periksa usulan transaksi.',
            'usage_json': {},
          },
        ],
        'actions': [
          {
            'id': 'action1',
            'status': approved ? 'executed' : 'pending',
            'tool': 'finance_write',
            'args': {
              'path': 'transactions',
              'payload': {'amount': 35000},
            },
          },
        ],
      };
    }
    if (path == 'ai/actions/action1/approve') {
      approved = true;
      return {'status': 'executed'};
    }
    return super.api(path, method: method, body: body, key: key);
  }
}

void main() {
  for (final width in [360.0, 1000.0]) {
    testWidgets('AI chat requires confirmation at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AiFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: financeTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FinanceAiPage(store: store),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Finance AI'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Catat makan 35000');
      await tester.ensureVisible(find.text('Kirim'));
      await tester.tap(find.text('Kirim'));
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi tindakan'), findsOneWidget);
      expect(store.approved, isFalse);
      await tester.ensureVisible(find.text('Jalankan'));
      await tester.tap(find.text('Jalankan'));
      await tester.pumpAndSettle();
      expect(store.approved, isTrue);
      expect(find.text('Konfirmasi tindakan'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'provider configuration keeps key input obscured and loads model metadata',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AiFixture(configured: false);
      await tester.pumpWidget(
        MaterialApp(
          theme: financeTheme(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(child: FinanceAiPage(store: store)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Tambah provider'));
      await tester.pumpAndSettle();
      final secret = find.widgetWithText(TextFormField, 'API key');
      await tester.enterText(secret, 'test-private-key');
      final editable = tester.widget<EditableText>(
        find.descendant(of: secret, matching: find.byType(EditableText)),
      );
      expect(editable.obscureText, isTrue);
      await tester.ensureVisible(find.text('Simpan & ambil daftar model'));
      await tester.tap(find.text('Simpan & ambil daftar model'));
      await tester.pumpAndSettle();
      expect(store.saved?['api_key'], 'test-private-key');
      expect(find.text('test-private-key'), findsNothing);
      expect(find.text('Model dari provider'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

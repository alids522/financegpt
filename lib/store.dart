import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'domain.dart';
import 'config.dart';

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://supabase.adoetz52.my.id/functions/v1/finance-api',
);
const schemaName = String.fromEnvironment(
  'SUPABASE_SCHEMA',
  defaultValue: 'financegpt',
);
const uuid = Uuid();

class FinanceStore extends ChangeNotifier {
  final SupabaseClient client;
  FinanceStore(this.client);
  SupabaseQuerySchema get db => client.schema(schemaName);
  FinanceRow profile = {};
  final Map<String, List<FinanceRow>> data = {};
  bool loading = false, online = true, admin = false;
  String? error;
  RealtimeChannel? channel;
  Timer? debounce;
  String get uid => client.auth.currentUser!.id;
  List<FinanceRow> rows(String table) => data[table] ?? [];
  String name(String table, dynamic id) =>
      rows(table).where((r) => r['id'] == id).firstOrNull?['name'] as String? ??
      '—';
  String get currency => profile['base_currency'] ?? 'IDR';
  Future<void> initialize() async {
    await db.rpc('initialize_profile');
    await refresh();
    channel ??= client
        .channel('finance-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: schemaName,
          callback: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 400), refresh);
          },
        )
        .subscribe();
  }

  Future<void> refresh() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final p = await db.from('profiles').select().eq('user_id', uid).single();
      profile = p;
      final role = await db
          .from('user_roles')
          .select('role')
          .eq('user_id', uid)
          .maybeSingle();
      admin = role?['role'] == 'admin';
      await Future.wait(
        [
          'account_balances',
          'categories',
          'transaction_templates',
          'budgets',
          'savings_goals',
          'goal_allocations',
          'debts',
          'debt_payments',
          'recurring_rules',
          'agent_connections',
          'agent_permissions',
          'agent_policies',
          'agent_pending_actions',
          'agent_audit_logs',
          'custom_field_definitions',
          'transaction_splits',
          'import_jobs',
          'export_jobs',
        ].map((t) async {
          data[t == 'account_balances' ? 'accounts' : t] =
              (await db.from(t).select().limit(1000)).cast<FinanceRow>();
        }),
      );
      await loadTransactions();
      online = true;
    } catch (e) {
      error = readableError(e);
      online = false;
    }
    loading = false;
    notifyListeners();
  }

  // Fetch in bounded pages. Server order is stable, and the UI paginates its filtered view.
  Future<void> loadTransactions() async {
    final all = <FinanceRow>[];
    var offset = 0;
    while (true) {
      final page = await db
          .from('transactions')
          .select()
          .order('effective_at', ascending: false)
          .order('id')
          .range(offset, offset + 999);
      all.addAll(page.cast<FinanceRow>());
      if (page.length < 1000) break;
      offset += 1000;
    }
    data['transactions'] = all;
  }

  Future<void> save(String table, FinanceRow values, {String? id}) async {
    if (id == null) {
      await db.from(table).insert({...values, 'user_id': uid});
    } else {
      await db.from(table).update(values).eq('id', id);
    }
    await refresh();
  }

  Future<FinanceRow> saveTransaction(FinanceRow payload, String key) async {
    final result = FinanceRow.from(
      await db.rpc(
            'save_transaction',
            params: {'payload': payload, 'idempotency_key': key},
          )
          as Map,
    );
    await refresh();
    return result;
  }

  Future<void> createAccount(FinanceRow values, String key) async {
    await db.rpc(
      'create_account',
      params: {'payload': values, 'idempotency_key': key},
    );
    await refresh();
  }

  Future<dynamic> api(
    String path, {
    String method = 'GET',
    FinanceRow? body,
    String? key,
  }) async {
    await client.auth.refreshSession();
    final req = http.Request(method, Uri.parse('$apiUrl/api/v1/$path'));
    req.headers.addAll({
      'Authorization': 'Bearer ${client.auth.currentSession!.accessToken}',
      'apikey': const String.fromEnvironment(
        'SUPABASE_ANON_KEY',
        defaultValue: defaultAnonKey,
      ),
      'Content-Type': 'application/json',
      'Idempotency-Key': key ?? uuid.v4(),
    });
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(
      await req.send(),
    ).timeout(const Duration(seconds: 30));
    final value = jsonDecode(res.body);
    if (res.statusCode >= 400) {
      throw Exception(
        value['message'] ?? 'Permintaan gagal (${res.statusCode})',
      );
    }
    return value;
  }

  @override
  void dispose() {
    debounce?.cancel();
    if (channel != null) client.removeChannel(channel!);
    super.dispose();
  }
}

String readableError(Object e) {
  if (e is AuthException) return e.message;
  if (e is PostgrestException) return e.message;
  return e.toString().replaceFirst('Exception: ', '');
}

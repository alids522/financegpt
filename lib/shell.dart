import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'domain.dart';
import 'store.dart';
part 'pages.dart';
part 'editors.dart';
part 'data_tools.dart';
part 'agents.dart';
part 'form_preferences.dart';

const navigation = <(String, String, IconData)>[
  ('OVERVIEW', 'Dashboard', Icons.space_dashboard_outlined),
  ('', 'Transactions', Icons.receipt_long_outlined),
  ('', 'Accounts & Wallets', Icons.account_balance_wallet_outlined),
  ('', 'Analytics', Icons.bar_chart_outlined),
  ('PLANNING', 'Budgets', Icons.pie_chart_outline),
  ('', 'Forecast', Icons.show_chart),
  ('', 'Savings Goals', Icons.savings_outlined),
  ('', 'Debts & Installments', Icons.credit_card_outlined),
  ('MANAGEMENT', 'Categories', Icons.category_outlined),
  ('', 'Transaction Templates', Icons.bookmarks_outlined),
  ('', 'Recurring Transactions', Icons.event_repeat_outlined),
  ('', 'Import & Export', Icons.import_export),
  ('SYSTEM', 'API & AI Agents', Icons.hub_outlined),
  ('', 'Settings', Icons.settings_outlined),
  ('ADMIN', 'User Management', Icons.manage_accounts_outlined),
  ('', 'Admin Audit Logs', Icons.policy_outlined),
];

class FinanceShell extends StatefulWidget {
  final FinanceStore? initialStore;
  final ValueChanged<String> onTheme;
  final SharedPreferences preferences;
  const FinanceShell({
    super.key,
    required this.onTheme,
    required this.preferences,
    this.initialStore,
  });
  @override
  State<FinanceShell> createState() => _FinanceShellState();
}

class _FinanceShellState extends State<FinanceShell> {
  late final store =
      widget.initialStore ?? FinanceStore(Supabase.instance.client);
  int page = 0, tablePage = 0;
  bool tabletExpanded = false;
  late bool collapsed = widget.preferences.getBool('sidebarCollapsed') ?? false;
  DateTime anchor = financeNow();
  String periodType = 'Month', model = 'run_rate';
  Period? customPeriod;
  TransactionFilter filter = TransactionFilter();
  final searchController = TextEditingController();
  final scaffold = GlobalKey<ScaffoldState>();
  bool saving = false;
  int scenario = 0;
  List<FinanceRow> adminUsers = [], adminLogs = [];
  String adminSearch = '';
  late List<String> dashboardOrder =
      (widget.preferences.getStringList('dashboardOrder') ??
      ['summary', 'cashflow', 'budgets', 'recent', 'upcoming']);
  late Set<String> hiddenWidgets =
      (widget.preferences.getStringList('hiddenWidgets') ?? []).toSet();
  Period get period =>
      customPeriod ??
      Period.calendar(
        periodType,
        anchor,
        weekStart: integer(store.profile['week_start'] ?? 1),
      );
  Color get positive => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF72B39A)
      : const Color(0xFF287C60);
  Color get negative => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFD88989)
      : const Color(0xFFB64D52);
  List<FinanceRow> get periodTransactions => store
      .rows('transactions')
      .where(
        (t) =>
            t['currency'] == store.currency &&
            period.contains(t['effective_at']),
      )
      .toList();
  List<FinanceRow> get posted =>
      periodTransactions.where((t) => t['status'] == 'posted').toList();
  int sumType(String type, [List<FinanceRow>? rows]) => (rows ?? posted)
      .where((t) => t['type'] == type)
      .fold(
        0,
        (v, t) =>
            v + integer(t['amount']) * (t['reversal_of'] == null ? 1 : -1),
      );
  int get income => sumType('income');
  int get expense => sumType('expense');
  int get balance => store
      .rows('accounts')
      .where((a) => a['currency'] == store.currency)
      .fold(0, (v, a) => v + integer(a['balance']));
  List<FinanceRow> get currentBudgets => store
      .rows('budgets')
      .where(
        (b) =>
            b['currency'] == store.currency &&
            !DateTime.parse(b['period_end']).isBefore(period.start) &&
            DateTime.parse(b['period_start']).isBefore(period.end),
      )
      .toList();
  int get budgetTotal {
    final global = currentBudgets.where((b) => b['category_id'] == null);
    return (global.isNotEmpty ? global : currentBudgets).fold(
      0,
      (v, b) => v + integer(b['amount']),
    );
  }

  int get scheduled =>
      store
          .rows('recurring_rules')
          .where(
            (r) =>
                r['active'] == true &&
                r['payload_json']['type'] == 'expense' &&
                r['payload_json']['currency'] == store.currency,
          )
          .fold(
            0,
            (v, r) =>
                v +
                integer(r['payload_json']['amount']) *
                    scheduledOccurrences(r, period, financeNow()).length,
          ) +
      periodTransactions
          .where(
            (t) =>
                t['type'] == 'expense' &&
                t['status'] == 'pending' &&
                DateTime.parse(t['effective_at']).isAfter(financeNow()),
          )
          .fold<int>(0, (sum, t) => sum + integer(t['amount']));
  int get scheduledIncome =>
      store
          .rows('recurring_rules')
          .where(
            (r) =>
                r['payload_json']['type'] == 'income' &&
                r['payload_json']['currency'] == store.currency,
          )
          .fold<int>(
            0,
            (sum, r) =>
                sum +
                integer(r['payload_json']['amount']) *
                    scheduledOccurrences(r, period, financeNow()).length,
          ) +
      periodTransactions
          .where(
            (t) =>
                t['type'] == 'income' &&
                t['status'] == 'pending' &&
                DateTime.parse(t['effective_at']).isAfter(financeNow()),
          )
          .fold<int>(0, (sum, t) => sum + integer(t['amount']));
  Forecast get forecast => Forecast.calculate(
    actual: expense,
    budget: budgetTotal,
    period: period,
    now: financeNow(),
    method: model,
    scheduled: scheduled,
    variableActual: posted
        .where(
          (t) =>
              t['type'] == 'expense' &&
              t['source'] != 'recurring' &&
              !(t['tags'] as List? ?? []).contains('scheduled'),
        )
        .fold(0, (v, t) => v + integer(t['amount'])),
    historicalVariable: historicalVariableTotal,
    historicalDays: historicalVariableDays,
  );
  List<FinanceRow> get historicalVariableRows => store
      .rows('transactions')
      .where(
        (t) =>
            t['status'] == 'posted' &&
            t['type'] == 'expense' &&
            t['currency'] == store.currency &&
            t['source'] != 'recurring' &&
            !(t['tags'] as List? ?? []).contains('scheduled') &&
            DateTime.parse(t['effective_at']).isBefore(period.start) &&
            !DateTime.parse(
              t['effective_at'],
            ).isBefore(period.start.subtract(const Duration(days: 90))),
      )
      .toList();
  int get historicalVariableTotal => historicalVariableRows.fold(
    0,
    (sum, t) =>
        sum + integer(t['amount']) * (t['reversal_of'] == null ? 1 : -1),
  );
  int get historicalVariableDays {
    final rows = historicalVariableRows;
    if (rows.isEmpty) return 0;
    rows.sort(
      (a, b) => '${a['effective_at']}'.compareTo('${b['effective_at']}'),
    );
    return period.start
        .difference(DateTime.parse(rows.first['effective_at']))
        .inDays
        .clamp(1, 90);
  }

  @override
  void initState() {
    super.initState();
    store.addListener(changed);
    store.initialize().catchError((Object e) {
      store.error = readableError(e);
      store.loading = false;
      changed();
    });
  }

  void changed() {
    if (mounted) setState(() {});
  }

  void update(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void dispose() {
    searchController.dispose();
    store.removeListener(changed);
    store.dispose();
    super.dispose();
  }

  void toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> run(
    Future<void> Function() action, {
    String success = 'Perubahan disimpan.',
  }) async {
    if (saving) return;
    update(() => saving = true);
    try {
      await action();
      if (success.isNotEmpty) toast(success);
    } catch (e) {
      toast(readableError(e));
    } finally {
      update(() => saving = false);
    }
  }

  void go(int value) {
    update(() {
      page = value;
      tablePage = 0;
    });
    if (scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
    if (value >= 14) loadAdmin();
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Konfirmasi'),
            ),
          ],
        ),
      ) ??
      false;
  Widget section(
    String title, {
    String? subtitle,
    Widget? action,
    required Widget child,
  }) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    ),
  );
  Widget empty(String text, {String? action, VoidCallback? onPressed}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Column(
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 32,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: 16),
                OutlinedButton(onPressed: onPressed, child: Text(action)),
              ],
            ],
          ),
        ),
      );
  Widget amount(dynamic value, {Color? color, double size = 24}) => Text(
    money(value, store.currency),
    maxLines: 2,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
  Widget responsive(List<Widget> children, {double min = 260}) => LayoutBuilder(
    builder: (c, b) {
      final cols = math.max(1, (b.maxWidth / (min + 16)).floor());
      final width = (b.maxWidth - (cols - 1) * 16) / cols;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: children
            .map((x) => SizedBox(width: width, child: x))
            .toList(),
      );
    },
  );
  Widget kpi(String label, int value, {String? note, Color? color}) =>
      Semantics(
        label: '$label ${money(value, store.currency)}',
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                amount(value, color: color),
                const SizedBox(height: 8),
                Text(
                  note ?? store.currency,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
  Widget sidebar(bool rail) => Material(
    color: Theme.of(context).colorScheme.surface,
    child: Column(
      children: [
        SizedBox(
          height: 76,
          child: Row(
            mainAxisAlignment: rail
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              if (!rail) const SizedBox(width: 20),
              Icon(
                Icons.account_balance_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              if (!rail) ...[
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'FINANCE\nTRACKER',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (var i = 0; i < navigation.length; i++)
                if (i < 14 || store.admin) ...[
                  if (navigation[i].$1.isNotEmpty && !rail)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 22, 8, 8),
                      child: Text(
                        navigation[i].$1,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Tooltip(
                    message: navigation[i].$2,
                    child: ListTile(
                      dense: true,
                      minLeadingWidth: 20,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: rail ? 8 : 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      selected: page == i,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .1),
                      leading: Icon(navigation[i].$3, size: 20),
                      title: rail
                          ? null
                          : Text(
                              navigation[i].$2,
                              style: const TextStyle(fontSize: 13),
                            ),
                      onTap: () => go(i),
                    ),
                  ),
                ],
            ],
          ),
        ),
        const Divider(height: 1),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: const Icon(Icons.help_outline, size: 20),
          title: rail
              ? null
              : const Text(
                  'Pusat keuangan Anda',
                  style: TextStyle(fontSize: 12),
                ),
          subtitle: rail
              ? null
              : const Text(
                  'v1.0 · Personal workspace',
                  style: TextStyle(fontSize: 10),
                ),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
  Widget periodPicker() => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      IconButton(
        tooltip: 'Periode sebelumnya',
        onPressed: () => movePeriod(-1),
        icon: const Icon(Icons.chevron_left, size: 20),
      ),
      PopupMenuButton<String>(
        tooltip: 'Pilih periode',
        initialValue: periodType,
        onSelected: (v) async {
          if (v == 'Custom') {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              initialDateRange: DateTimeRange(
                start: period.start,
                end: period.end.subtract(const Duration(days: 1)),
              ),
            );
            if (range != null) {
              update(() {
                customPeriod = Period(
                  range.start,
                  range.end.add(const Duration(days: 1)),
                );
                periodType = v;
                tablePage = 0;
              });
            }
          } else {
            update(() {
              periodType = v;
              customPeriod = null;
              tablePage = 0;
            });
          }
        },
        itemBuilder: (c) => [
          'Day',
          'Week',
          'Month',
          'Year',
          'Custom',
        ].map((s) => PopupMenuItem(value: s, child: Text(s))).toList(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.calendar_today_outlined, size: 16),
              const SizedBox(width: 8),
              Text(
                periodType == 'Month'
                    ? DateFormat('MMMM yyyy', 'id_ID').format(anchor)
                    : period.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 16),
            ],
          ),
        ),
      ),
      IconButton(
        tooltip: 'Periode berikutnya',
        onPressed: () => movePeriod(1),
        icon: const Icon(Icons.chevron_right, size: 20),
      ),
    ],
  );
  void movePeriod(int n) => update(() {
    if (customPeriod != null) {
      final d = customPeriod!.days * n;
      customPeriod = Period(
        customPeriod!.start.add(Duration(days: d)),
        customPeriod!.end.add(Duration(days: d)),
      );
    } else {
      anchor = switch (periodType) {
        'Day' => anchor.add(Duration(days: n)),
        'Week' => anchor.add(Duration(days: 7 * n)),
        'Year' => DateTime(anchor.year + n, anchor.month, anchor.day),
        _ => DateTime(anchor.year, anchor.month + n),
      };
    }
    tablePage = 0;
  });
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (c, _) => LayoutBuilder(
      builder: (c, b) {
        final mobile = b.maxWidth < 768;
        final rail = b.maxWidth < 1200 ? !tabletExpanded : collapsed;
        return Scaffold(
          key: scaffold,
          drawer: mobile
              ? Drawer(width: 280, child: SafeArea(child: sidebar(false)))
              : null,
          body: SafeArea(
            child: Row(
              children: [
                if (!mobile) ...[
                  SizedBox(width: rail ? 64 : 240, child: sidebar(rail)),
                  const VerticalDivider(width: 1),
                ],
                Expanded(
                  child: Column(
                    children: [
                      Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: mobile ? 12 : 24,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                tooltip: mobile
                                    ? 'Buka navigasi'
                                    : 'Ciutkan navigasi',
                                onPressed: () {
                                  if (mobile) {
                                    scaffold.currentState!.openDrawer();
                                  } else {
                                    update(() {
                                      if (b.maxWidth < 1200) {
                                        tabletExpanded = !tabletExpanded;
                                      } else {
                                        collapsed = !collapsed;
                                      }
                                    });
                                    widget.preferences.setBool(
                                      'sidebarCollapsed',
                                      collapsed,
                                    );
                                  }
                                },
                                icon: Icon(
                                  mobile ? Icons.menu : Icons.menu_open,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  navigation[page].$2,
                                  style: TextStyle(
                                    fontSize: mobile ? 18 : 21,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (!mobile) periodPicker(),
                              if (b.maxWidth >= 1200)
                                IconButton(
                                  tooltip: 'Cari transaksi',
                                  onPressed: () => go(1),
                                  icon: const Icon(Icons.search, size: 20),
                                ),
                              if (b.maxWidth >= 1200)
                                IconButton(
                                  tooltip: 'Notifikasi',
                                  onPressed: showNotifications,
                                  icon: const Icon(
                                    Icons.notifications_none,
                                    size: 20,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Muat ulang',
                                onPressed: store.loading ? null : store.refresh,
                                icon: const Icon(Icons.refresh, size: 20),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'Profil',
                                onSelected: (v) {
                                  if (v == 'logout') {
                                    store.client.auth.signOut();
                                  } else {
                                    go(13);
                                  }
                                },
                                itemBuilder: (c) => [
                                  PopupMenuItem(
                                    enabled: false,
                                    child: Text(
                                      store.profile['display_name'] ??
                                          'Akun Anda',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'settings',
                                    child: Text('Pengaturan'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'logout',
                                    child: Text('Keluar'),
                                  ),
                                ],
                                child: CircleAvatar(
                                  radius: 17,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .12),
                                  child: Text(
                                    (store.profile['display_name'] ?? 'U')
                                        .toString()
                                        .substring(0, 1)
                                        .toUpperCase(),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      if (store.loading || saving)
                        const LinearProgressIndicator(minHeight: 2),
                      if (mobile)
                        Align(
                          alignment: Alignment.centerRight,
                          child: periodPicker(),
                        ),
                      if (store.error != null)
                        MaterialBanner(
                          content: Text(
                            'Koneksi belum tersedia: ${store.error}',
                          ),
                          actions: [
                            TextButton(
                              onPressed: store.refresh,
                              child: const Text('Coba lagi'),
                            ),
                          ],
                        ),
                      Expanded(
                        child: store.loading && store.profile.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : store.profile['must_change_password'] == true
                            ? SingleChildScrollView(
                                padding: const EdgeInsets.all(24),
                                child: passwordPanel(forced: true),
                              )
                            : RefreshIndicator(
                                onRefresh: store.refresh,
                                child: SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.all(mobile ? 16 : 24),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: b.maxHeight - 180,
                                    ),
                                    child: pageContent(),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: page == 0 || page == 1
              ? FloatingActionButton.extended(
                  onPressed: () => transactionEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Transaksi'),
                )
              : null,
        );
      },
    ),
  );
  Widget pageContent() => switch (page) {
    0 => dashboard(),
    1 => transactionsPage(),
    2 => accountsPage(),
    3 => analyticsPage(),
    4 => budgetsPage(),
    5 => forecastPage(),
    6 => savingsPage(),
    7 => debtsPage(),
    8 => categoriesPage(),
    9 => templatesPage(),
    10 => recurringPage(),
    11 => dataPage(),
    12 => agentsPage(),
    13 => settingsPage(),
    14 => usersPage(),
    _ => adminAuditPage(),
  };
}

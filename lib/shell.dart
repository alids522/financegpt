import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
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
import 'glass.dart';
part 'pages.dart';
part 'editors.dart';
part 'data_tools.dart';
part 'agents.dart';
part 'form_preferences.dart';
part 'dashboard.dart';
part 'statements.dart';
part 'ai.dart';

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
  ('AI', 'Finance AI', Icons.auto_awesome_outlined),
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
  final contentScroll = ScrollController();
  final scaffold = GlobalKey<ScaffoldState>();
  bool saving = false;
  DateTime? lastBackAt;
  int scenario = 0;
  List<FinanceRow> adminUsers = [], adminLogs = [];
  String adminSearch = '';
  bool balanceVisible = true, dashboardChartExpense = true;
  late List<String> dashboardOrder = initialDashboardOrder();
  List<String> initialDashboardOrder() {
    const defaults = [
      'summary',
      'accounts',
      'metrics',
      'cashflow',
      'budgets',
      'recent',
      'categories',
      'upcoming',
    ];
    final saved = widget.preferences.getStringList('dashboardOrder');
    if (saved == null) return [...defaults];
    final order = saved.where(defaults.contains).toList();
    for (final key in ['accounts', 'metrics', 'categories']) {
      if (!order.contains(key)) {
        final before = key == 'accounts'
            ? 'summary'
            : key == 'metrics'
            ? 'accounts'
            : 'recent';
        final index = order.indexOf(before);
        order.insert(index < 0 ? order.length : index + 1, key);
      }
    }
    return order;
  }

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
      ? const Color(0xFF62DDB0)
      : const Color(0xFF11875B);
  Color get negative => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFFFF8E9B)
      : const Color(0xFFBC3446);
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
    contentScroll.dispose();
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
      lastBackAt = null;
    });
    if (contentScroll.hasClients) contentScroll.jumpTo(0);
    if (scaffold.currentState?.isDrawerOpen ?? false) Navigator.pop(context);
    if (value >= 14) loadAdmin();
  }

  void handleSystemBack() {
    if (scaffold.currentState?.isDrawerOpen ?? false) {
      scaffold.currentState!.closeDrawer();
      lastBackAt = null;
      return;
    }
    if (page != 0) {
      go(0);
      return;
    }
    final now = DateTime.now();
    if (lastBackAt != null &&
        now.difference(lastBackAt!) <= const Duration(seconds: 2)) {
      if (!kIsWeb) SystemNavigator.pop();
    } else {
      lastBackAt = now;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tekan Back sekali lagi untuk keluar'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
  }) => GlassPanel(
    padding: EdgeInsets.zero,
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
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
  Widget sidebar(bool rail) => GlassPanel(
    padding: const EdgeInsets.all(8),
    radius: 26,
    child: Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: rail ? 0 : 10,
            vertical: 20,
          ),
          child: Row(
            mainAxisAlignment: rail
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              FinanceLogo(size: rail ? 38 : 44),
              if (!rail) ...[
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Adoetz Finance',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text('Personal finance', style: TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < navigation.length; i++)
                if (i < 14 || i == 16 || store.admin) ...[
                  if (navigation[i].$1.isNotEmpty && !rail)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 22, 8, 10),
                      child: Text(
                        navigation[i].$1,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: page == i
                            ? LinearGradient(
                                colors: [
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .25),
                                  Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: .10),
                                ],
                              )
                            : null,
                        border: Border.all(
                          color: page == i
                              ? Colors.white.withValues(alpha: .22)
                              : Colors.transparent,
                        ),
                      ),
                      child: Tooltip(
                        message: navigation[i].$2,
                        child: ListTile(
                          dense: true,
                          minLeadingWidth: 20,
                          horizontalTitleGap: 12,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: rail ? 10 : 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          selected: page == i,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          leading: Icon(navigation[i].$3, size: 22),
                          title: rail
                              ? null
                              : Text(
                                  navigation[i].$2,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: page == i
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                          onTap: () => go(i),
                        ),
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        GlassPanel(
          radius: 20,
          blur: false,
          padding: EdgeInsets.zero,
          child: rail
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Icon(Icons.layers_outlined, size: 22),
                )
              : ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: const Icon(Icons.layers_outlined, size: 22),
                  title: const Text(
                    'Pusat keuangan Anda',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Personal workspace',
                    style: TextStyle(fontSize: 10),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 16),
                ),
        ),
        const SizedBox(height: 4),
      ],
    ),
  );
  Widget periodPicker() => GlassPanel(
    radius: 28,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    blur: false,
    child: Wrap(
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
                    fontSize: 13,
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
    ),
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
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final mobile = box.maxWidth < 768;
        final rail = box.maxWidth < 1200 ? !tabletExpanded : collapsed;
        final dark = Theme.of(context).brightness == Brightness.dark;
        return PopScope(
          canPop: kIsWeb,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) handleSystemBack();
          },
          child: Scaffold(
            key: scaffold,
            drawer: mobile
                ? Drawer(
                    width: 288,
                    backgroundColor: Colors.transparent,
                    surfaceTintColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    elevation: 0,
                    child: BackdropGroup(
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: sidebar(false),
                        ),
                      ),
                    ),
                  )
                : null,
            body: FinanceBackdrop(
              child: SafeArea(
                child: Row(
                  children: [
                    if (!mobile)
                      SizedBox(
                        width: rail ? 88 : 260,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
                          child: sidebar(rail),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              mobile ? 20 : 24,
                              18,
                              mobile ? 20 : 28,
                              8,
                            ),
                            child: Row(
                              children: [
                                GlassIconButton(
                                  icon: mobile ? Icons.menu : Icons.menu_open,
                                  tooltip: mobile
                                      ? 'Buka navigasi'
                                      : 'Ciutkan navigasi',
                                  onPressed: () {
                                    if (mobile) {
                                      scaffold.currentState!.openDrawer();
                                    } else {
                                      update(() {
                                        if (box.maxWidth < 1200) {
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
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    navigation[page].$2,
                                    style: TextStyle(
                                      fontSize: mobile ? 23 : 28,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (box.maxWidth >= 1200) ...[
                                  periodPicker(),
                                  const SizedBox(width: 16),
                                ],
                                if (box.maxWidth >= 1100) ...[
                                  GlassIconButton(
                                    icon: Icons.search,
                                    tooltip: 'Cari transaksi',
                                    onPressed: () => go(1),
                                  ),
                                  const SizedBox(width: 10),
                                  GlassIconButton(
                                    icon: Icons.notifications_none_outlined,
                                    tooltip: 'Notifikasi',
                                    onPressed: showNotifications,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                if (!mobile) ...[
                                  GlassIconButton(
                                    icon: Icons.refresh,
                                    tooltip: 'Muat ulang',
                                    onPressed: store.loading
                                        ? null
                                        : store.refresh,
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                PopupMenuButton<String>(
                                  tooltip: 'Profil',
                                  onSelected: (value) {
                                    if (value == 'logout') {
                                      store.client.auth.signOut();
                                    } else if (value == 'refresh') {
                                      store.refresh();
                                    } else {
                                      go(13);
                                    }
                                  },
                                  itemBuilder: (_) => [
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
                                      value: 'refresh',
                                      child: Text('Muat ulang'),
                                    ),
                                    const PopupMenuItem(
                                      value: 'logout',
                                      child: Text('Keluar'),
                                    ),
                                  ],
                                  child: GlassPanel(
                                    radius: 24,
                                    padding: EdgeInsets.zero,
                                    blur: false,
                                    tint: Theme.of(context).colorScheme.primary
                                        .withValues(alpha: .07),
                                    child: SizedBox(
                                      width: 44,
                                      height: 44,
                                      child: Center(
                                        child: Text(
                                          (store.profile['display_name'] ?? 'U')
                                              .toString()
                                              .substring(0, 1)
                                              .toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: dark
                                                ? const Color(0xFFB9E2FF)
                                                : const Color(0xFF22568C),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (box.maxWidth < 1200)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 6,
                                bottom: 10,
                              ),
                              child: periodPicker(),
                            ),
                          if (store.loading || saving)
                            const LinearProgressIndicator(minHeight: 2),
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
                                ? const Center(
                                    child: CircularProgressIndicator(),
                                  )
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
                                      padding: EdgeInsets.fromLTRB(
                                        mobile ? 16 : 24,
                                        12,
                                        mobile ? 16 : 28,
                                        24,
                                      ),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          minHeight: box.maxHeight - 200,
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
            ),
            floatingActionButton:
                (page == 0 || page == 1) &&
                    store.profile['must_change_password'] != true
                ? SizedBox(
                    width: 64,
                    height: 64,
                    child: FloatingActionButton(
                      tooltip: 'Tambah transaksi',
                      onPressed: () => transactionEditor(),
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(mobile ? 32 : 22),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(mobile ? 32 : 22),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF79CAFF),
                              Color(0xFF197BFC),
                              Color(0xFF0858D2),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .55),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0775EF,
                              ).withValues(alpha: dark ? .45 : .25),
                              blurRadius: 22,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(Icons.add, size: 34, color: Colors.white),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
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
    16 => FinanceAiPage(store: store),
    _ => adminAuditPage(),
  };
}

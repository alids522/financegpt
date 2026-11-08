part of 'shell.dart';

extension _FinancePages on _FinanceShellState {
  Widget pageHeading(String title, String subtitle, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 16,
          spacing: 24,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            ?action,
          ],
        ),
      );
  Widget dashboard() {
    final parts = <String, Widget>{
      'summary': LayoutBuilder(
        builder: (context, box) => box.maxWidth < 600
            ? Column(
                children: [
                  kpi(
                    'Total saldo',
                    balance,
                    note:
                        'Arus kas bersih ${money(income - expense, store.currency)}',
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: compactKpi('Pemasukan', income, positive),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: compactKpi('Pengeluaran', expense, negative),
                      ),
                    ],
                  ),
                ],
              )
            : responsive([
                kpi(
                  'Total saldo',
                  balance,
                  note: 'Aset kas · ${store.currency}',
                ),
                kpi(
                  'Pemasukan',
                  income,
                  color: positive,
                  note: 'Transaksi posted',
                ),
                kpi(
                  'Pengeluaran',
                  expense,
                  color: negative,
                  note: 'Setelah refund',
                ),
                kpi(
                  'Arus kas bersih',
                  income - expense,
                  note: 'Pemasukan − pengeluaran',
                  color: income >= expense ? positive : negative,
                ),
              ], min: 220),
      ),
      'cashflow': section(
        'Arus kas',
        subtitle: 'Aktual & proyeksi · ${period.label}',
        action: TextButton(
          onPressed: () => go(5),
          child: const Text('Lihat forecast'),
        ),
        child: cashflowChart(),
      ),
      'budgets': section(
        'Budget vs Actual',
        subtitle: 'Rencana, realisasi, dan proyeksi akhir periode',
        action: TextButton(
          onPressed: () => go(4),
          child: const Text('Semua budget'),
        ),
        child: currentBudgets.isEmpty
            ? empty(
                'Belum ada budget untuk periode ini.',
                action: 'Buat budget',
                onPressed: () => budgetEditor(),
              )
            : Column(children: currentBudgets.take(4).map(budgetRow).toList()),
      ),
      'recent': section(
        'Transaksi terakhir',
        action: TextButton(
          onPressed: () => go(1),
          child: const Text('Lihat semua'),
        ),
        child: periodTransactions.isEmpty
            ? empty(
                'Mulai dengan mencatat transaksi pertama Anda.',
                action: 'Tambah transaksi',
                onPressed: () => transactionEditor(),
              )
            : Column(
                children: periodTransactions
                    .take(5)
                    .map(transactionTile)
                    .toList(),
              ),
      ),
      'upcoming': section(
        'Akan datang',
        subtitle: 'Tagihan, utang jatuh tempo, dan tabungan',
        child: Column(
          children: [
            ...store
                .rows('recurring_rules')
                .where((r) => r['active'] == true)
                .take(3)
                .map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_repeat_outlined, size: 20),
                    title: Text(r['name']),
                    subtitle: Text(dateLabel(r['next_at'])),
                    trailing: Text(
                      money(
                        r['payload_json']['amount'],
                        r['payload_json']['currency'] ?? 'IDR',
                      ),
                    ),
                  ),
                ),
            ...store
                .rows('debts')
                .take(3)
                .map(
                  (r) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.credit_card_outlined, size: 20),
                    title: Text(r['name']),
                    subtitle: Text('Jatuh tempo ${dateLabel(r['due'])}'),
                    trailing: Text(money(outstanding(r), r['currency'])),
                  ),
                ),
            if (store.rows('recurring_rules').isEmpty &&
                store.rows('debts').isEmpty)
              empty('Tidak ada tagihan terjadwal.'),
          ],
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Keuangan dalam kendali.',
          'Ringkasan Anda · ${period.label}',
          action: OutlinedButton.icon(
            onPressed: dashboardCustomize,
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Atur tampilan'),
          ),
        ),
        for (final key in dashboardOrder)
          if (!hiddenWidgets.contains(key)) ...[
            parts[key]!,
            const SizedBox(height: 20),
          ],
        if (store.rows('accounts').isEmpty)
          section(
            'Siap memulai?',
            subtitle: 'Tambahkan Cash, rekening bank, atau e-wallet Anda.',
            child: FilledButton.icon(
              onPressed: () => accountEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Tambah akun'),
            ),
          ),
        const SizedBox(height: 64),
      ],
    );
  }

  Widget compactKpi(String label, int value, Color color) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              money(value, store.currency),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> dashboardCustomize() async {
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, local) => AlertDialog(
          title: const Text('Widget dashboard'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < dashboardOrder.length; i++)
                  Row(
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            {
                              'summary': 'Ringkasan saldo',
                              'cashflow': 'Arus kas',
                              'budgets': 'Budget vs Actual',
                              'recent': 'Transaksi terakhir',
                              'upcoming': 'Akan datang',
                            }[dashboardOrder[i]]!,
                          ),
                          value: !hiddenWidgets.contains(dashboardOrder[i]),
                          onChanged: (v) {
                            update(() {
                              if (v == true) {
                                hiddenWidgets.remove(dashboardOrder[i]);
                              } else {
                                hiddenWidgets.add(dashboardOrder[i]);
                              }
                            });
                            local(() {});
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Pindah ke atas',
                        onPressed: i == 0
                            ? null
                            : () {
                                update(() {
                                  final x = dashboardOrder.removeAt(i);
                                  dashboardOrder.insert(i - 1, x);
                                });
                                local(() {});
                              },
                        icon: const Icon(Icons.arrow_upward, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Pindah ke bawah',
                        onPressed: i == dashboardOrder.length - 1
                            ? null
                            : () {
                                update(() {
                                  final x = dashboardOrder.removeAt(i);
                                  dashboardOrder.insert(i + 1, x);
                                });
                                local(() {});
                              },
                        icon: const Icon(Icons.arrow_downward, size: 18),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Selesai'),
            ),
          ],
        ),
      ),
    );
    await widget.preferences.setStringList('dashboardOrder', dashboardOrder);
    await widget.preferences.setStringList(
      'hiddenWidgets',
      hiddenWidgets.toList(),
    );
  }

  Widget cashflowChart({bool forecastLine = false}) {
    if (posted.isEmpty) {
      return empty('Grafik akan muncul setelah ada transaksi posted.');
    }
    final n = period.days;
    var acc = 0;
    final values = <FlSpot>[];
    for (var i = 0; i < n; i++) {
      final day = period.start.add(Duration(days: i));
      final rows = posted.where((t) {
        final d = localTime(t['effective_at']);
        return d.year == day.year && d.month == day.month && d.day == day.day;
      }).toList();
      acc += forecastLine
          ? sumType('expense', rows)
          : sumType('income', rows) - sumType('expense', rows);
      if (!day.isAfter(DateTime.now())) {
        values.add(FlSpot(i.toDouble(), acc.toDouble()));
      }
    }
    if (values.isEmpty) return empty('Tidak ada data aktual.');
    final future = forecastLine
        ? [
            values.last,
            FlSpot((n - 1).toDouble(), forecast.estimate.toDouble()),
          ]
        : <FlSpot>[];
    final maxValue = [
      1.0,
      ...values.map((x) => x.y.abs()),
      forecastLine ? forecast.estimate.abs().toDouble() : 1.0,
    ].reduce(math.max);
    return Column(
      children: [
        SizedBox(
          height: 240,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: (n - 1).toDouble().clamp(1, 366),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxValue / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Theme.of(context).dividerColor,
                  strokeWidth: .5,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 52,
                    getTitlesWidget: (v, _) => Text(
                      NumberFormat.compact(locale: 'id').format(v),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: math.max(1, n / 6),
                    getTitlesWidget: (v, _) => Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat(
                          n > 60 ? 'MMM' : 'd MMM',
                          'id_ID',
                        ).format(period.start.add(Duration(days: v.toInt()))),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots
                      .map(
                        (s) => LineTooltipItem(
                          money(s.y.round(), store.currency),
                          const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      )
                      .toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: values,
                  isCurved: false,
                  color: Theme.of(context).colorScheme.primary,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: .05),
                  ),
                ),
                if (future.isNotEmpty)
                  LineChartBarData(
                    spots: future,
                    color: const Color(0xFFA76A22),
                    barWidth: 2,
                    dashArray: [6, 5],
                    dotData: const FlDotData(show: false),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 20,
          children: [
            Text(
              '━ Aktual · ${store.currency}',
              style: const TextStyle(fontSize: 12),
            ),
            if (forecastLine)
              const Text(
                '┄ Forecast · estimasi',
                style: TextStyle(fontSize: 12),
              ),
          ],
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text(
            'Lihat data grafik',
            style: TextStyle(fontSize: 12),
          ),
          children: values
              .map(
                (s) => ListTile(
                  dense: true,
                  title: Text(
                    dateLabel(
                      period.start
                          .add(Duration(days: s.x.toInt()))
                          .toIso8601String(),
                    ),
                  ),
                  trailing: Text(money(s.y.round(), store.currency)),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget transactionTile(FinanceRow t) => ListTile(
    contentPadding: EdgeInsets.zero,
    minVerticalPadding: 10,
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        t['type'] == 'transfer'
            ? Icons.swap_horiz
            : t['type'] == 'income'
            ? Icons.south_west
            : Icons.north_east,
        size: 19,
      ),
    ),
    title: Text(
      (t['description'] as String? ?? '').isNotEmpty
          ? t['description']
          : store.name('categories', t['category_id']),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${store.name('accounts', t['account_id'])} · ${dateLabel(t['effective_at'])}\n${t['status']} ${t['source'] == 'agent' ? '· Agent' : ''}',
      style: const TextStyle(fontSize: 11),
    ),
    isThreeLine: true,
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Text(
        '${t['type'] == 'expense'
            ? '−'
            : t['type'] == 'income'
            ? '+'
            : ''}${money(t['amount'], t['currency'])}',
        textAlign: TextAlign.right,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: t['type'] == 'expense'
              ? negative
              : t['type'] == 'income'
              ? positive
              : null,
          fontSize: 13,
        ),
      ),
    ),
    onTap: () => transactionDetail(t),
  );
  List<FinanceRow> get filteredTransactions {
    final rows = store
        .rows('transactions')
        .where((t) => filter.matches(t, period))
        .toList();
    rows.sort((a, b) {
      final cmp = filter.sort == 'amount'
          ? integer(a['amount']).compareTo(integer(b['amount']))
          : '${a[filter.sort]}'.compareTo('${b[filter.sort]}');
      return filter.descending ? -cmp : cmp;
    });
    return rows;
  }

  Widget transactionsPage() {
    final rows = filteredTransactions;
    final start = math.min(tablePage * 20, rows.length);
    final end = math.min(start + 20, rows.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Transactions',
          'Semua aktivitas, satu catatan yang akurat.',
          action: FilledButton.icon(
            onPressed: () => transactionEditor(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah transaksi'),
          ),
        ),
        section(
          'Daftar transaksi',
          subtitle: '${rows.length} transaksi · ${period.label}',
          action: IconButton(
            tooltip: 'Ekspor hasil filter',
            onPressed: () => exportData(rows),
            icon: const Icon(Icons.file_download_outlined),
          ),
          child: Column(
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Cari transaksi',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => update(() {
                        filter.search = v;
                        tablePage = 0;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: filter.type,
                      decoration: const InputDecoration(labelText: 'Tipe'),
                      items: ['', 'expense', 'income', 'transfer', 'adjustment']
                          .map(
                            (v) => DropdownMenuItem(
                              value: v,
                              child: Text(v.isEmpty ? 'Semua' : v),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(() {
                        filter.type = v!;
                        tablePage = 0;
                      }),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: advancedFilters,
                    icon: const Icon(Icons.filter_list),
                    label: const Text('Filter lanjutan'),
                  ),
                  OutlinedButton.icon(
                    onPressed: saveView,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: const Text('Simpan view'),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'View tersimpan',
                    onSelected: loadView,
                    itemBuilder: (c) =>
                        (widget.preferences.getStringList('savedViews') ?? [])
                            .map(
                              (s) => PopupMenuItem(
                                value: s,
                                child: Text(jsonDecode(s)['name']),
                              ),
                            )
                            .toList(),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('View tersimpan ▾'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (rows.isEmpty)
                empty('Tidak ada transaksi yang sesuai filter.')
              else
                LayoutBuilder(
                  builder: (c, b) => b.maxWidth < 650
                      ? Column(
                          children: rows
                              .sublist(start, end)
                              .map(transactionTile)
                              .toList(),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            sortColumnIndex: filter.sort == 'amount' ? 4 : 0,
                            sortAscending: !filter.descending,
                            columns: [
                              DataColumn(
                                label: const Text('Tanggal'),
                                onSort: (_, asc) => update(() {
                                  filter.sort = 'effective_at';
                                  filter.descending = !asc;
                                }),
                              ),
                              const DataColumn(
                                label: Text('Transaksi / Merchant'),
                              ),
                              const DataColumn(label: Text('Akun')),
                              const DataColumn(label: Text('Kategori')),
                              DataColumn(
                                label: const Text('Nominal'),
                                numeric: true,
                                onSort: (_, asc) => update(() {
                                  filter.sort = 'amount';
                                  filter.descending = !asc;
                                }),
                              ),
                              const DataColumn(label: Text('Status')),
                              const DataColumn(label: Text('')),
                            ],
                            rows: rows
                                .sublist(start, end)
                                .map(
                                  (t) => DataRow(
                                    onSelectChanged: (_) =>
                                        transactionDetail(t),
                                    cells: [
                                      DataCell(
                                        Text(dateLabel(t['effective_at'])),
                                      ),
                                      DataCell(
                                        SizedBox(
                                          width: 180,
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                t['description']
                                                            ?.toString()
                                                            .isNotEmpty ==
                                                        true
                                                    ? t['description']
                                                    : t['type'],
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                t['merchant'] ?? '',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          store.name(
                                            'accounts',
                                            t['account_id'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          store.name(
                                            'categories',
                                            t['category_id'],
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          money(t['amount'], t['currency']),
                                          style: TextStyle(
                                            color: t['type'] == 'expense'
                                                ? negative
                                                : t['type'] == 'income'
                                                ? positive
                                                : null,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          t['status'],
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DataCell(
                                        IconButton(
                                          tooltip: 'Detail transaksi',
                                          onPressed: () => transactionDetail(t),
                                          icon: const Icon(
                                            Icons.more_horiz,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${rows.isEmpty ? 0 : start + 1}–$end dari ${rows.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  IconButton(
                    tooltip: 'Halaman sebelumnya',
                    onPressed: tablePage == 0
                        ? null
                        : () => update(() => tablePage--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Halaman berikutnya',
                    onPressed: end == rows.length
                        ? null
                        : () => update(() => tablePage++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 72),
      ],
    );
  }

  Future<void> saveView() async {
    final value = await recordDialog('Simpan view', [
      Field('name', 'Nama view'),
    ]);
    if (value != null) {
      final views = widget.preferences.getStringList('savedViews') ?? [];
      views.add(
        jsonEncode({
          'name': value['name'],
          'search': filter.search,
          'type': filter.type,
          'account': filter.account,
          'category': filter.category,
          'status': filter.status,
        }),
      );
      await widget.preferences.setStringList('savedViews', views);
      changed();
    }
  }

  void loadView(String raw) {
    final v = jsonDecode(raw);
    update(() {
      filter.search = v['search'];
      filter.type = v['type'];
      filter.account = v['account'];
      filter.category = v['category'];
      filter.status = v['status'];
      tablePage = 0;
    });
  }

  Future<void> advancedFilters() async {
    final result = await recordDialog('Filter transaksi', [
      Field(
        'account',
        'Akun',
        value: filter.account,
        options: {
          '': 'Semua akun',
          for (final a in store.rows('accounts')) a['id']: a['name'],
        },
      ),
      Field(
        'category',
        'Kategori',
        value: filter.category,
        options: {
          '': 'Semua kategori',
          for (final a in store.rows('categories')) a['id']: a['name'],
        },
      ),
      Field(
        'status',
        'Status',
        value: filter.status,
        options: {
          '': 'Semua status',
          'posted': 'Posted',
          'pending': 'Pending',
          'draft': 'Draft',
          'voided': 'Voided',
        },
      ),
      Field(
        'actor',
        'Sumber',
        value: filter.actor,
        options: {
          '': 'Semua sumber',
          'self': 'Manual',
          'agent': 'Agent',
          'import': 'Import',
        },
      ),
      Field('tag', 'Tag', value: filter.tag, required: false),
      Field('merchant', 'Merchant', value: filter.merchant, required: false),
      Field(
        'min',
        'Nominal minimum',
        value: filter.min?.toString() ?? '',
        number: true,
        required: false,
      ),
      Field(
        'max',
        'Nominal maksimum',
        value: filter.max?.toString() ?? '',
        number: true,
        required: false,
      ),
      Field(
        'attachment',
        'Lampiran',
        value: filter.attachmentOnly ? 'yes' : '',
        options: {'': 'Semua', 'yes': 'Hanya dengan lampiran'},
      ),
    ], saveLabel: 'Terapkan');
    if (result != null) {
      update(() {
        filter.account = result['account'];
        filter.category = result['category'];
        filter.status = result['status'];
        filter.actor = result['actor'];
        filter.tag = result['tag'];
        filter.merchant = result['merchant'];
        filter.min = int.tryParse(result['min']);
        filter.max = int.tryParse(result['max']);
        filter.attachmentOnly = result['attachment'] == 'yes';
        tablePage = 0;
      });
    }
  }

  Widget accountsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Accounts & Wallets',
        'Saldo dari jurnal. Setiap perubahan dapat ditelusuri.',
        action: FilledButton.icon(
          onPressed: () => accountEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah akun'),
        ),
      ),
      if (store.rows('accounts').isEmpty)
        section(
          'Akun Anda',
          child: empty(
            'Belum ada akun atau dompet.',
            action: 'Tambah akun',
            onPressed: () => accountEditor(),
          ),
        )
      else
        responsive(
          store
              .rows('accounts')
              .map(
                (a) => section(
                  a['name'],
                  subtitle: '${a['type']} · ${a['currency']} · ${a['status']}',
                  action: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        accountEditor(existing: a);
                      } else if (await confirm(
                        'Arsipkan akun?',
                        'Transaksi dan jurnal historis tetap tersimpan.',
                      )) {
                        run(
                          () => store.save('accounts', {
                            'status': a['status'] == 'active'
                                ? 'archived'
                                : 'active',
                          }, id: a['id']),
                        );
                      }
                    },
                    itemBuilder: (c) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Edit akun'),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(
                          a['status'] == 'active' ? 'Arsipkan' : 'Aktifkan',
                        ),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(a['balance'], a['currency']),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Saldo awal ${money(a['opening_balance'], a['currency'])}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          update(() => filter.account = a['id']);
                          go(1);
                        },
                        child: const Text('Lihat transaksi →'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          min: 280,
        ),
    ],
  );
  Widget analyticsPage() {
    final cats = <String, int>{}, merchants = <String, int>{};
    for (final t in posted.where((t) => t['type'] == 'expense')) {
      final value = integer(t['amount']) * (t['reversal_of'] == null ? 1 : -1);
      final name = store.name('categories', t['category_id']);
      cats[name] = (cats[name] ?? 0) + value;
      final merchant = t['merchant']?.toString().isNotEmpty == true
          ? t['merchant']
          : 'Tanpa merchant';
      merchants[merchant] = (merchants[merchant] ?? 0) + value;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading('Analytics', 'Kenali pola pemasukan dan pengeluaran Anda.'),
        responsive([
          kpi('Pemasukan', income, color: positive),
          kpi('Pengeluaran', expense, color: negative),
          kpi('Arus kas bersih', income - expense),
        ]),
        const SizedBox(height: 20),
        section(
          'Tren arus kas',
          subtitle: '${period.label} · ${store.currency}',
          child: cashflowChart(),
        ),
        const SizedBox(height: 20),
        responsive([
          section('Pengeluaran per kategori', child: breakdown(cats)),
          section('Merchant teratas', child: breakdown(merchants)),
          section(
            'Sumber pemasukan',
            child: breakdown({
              for (final c
                  in store
                      .rows('categories')
                      .where((c) => c['type'] == 'income'))
                c['name']: sumType(
                  'income',
                  posted.where((t) => t['category_id'] == c['id']).toList(),
                ),
            }),
          ),
        ], min: 300),
      ],
    );
  }

  Widget breakdown(Map<String, int> values) {
    final items = values.entries.where((x) => x.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = items.isEmpty ? 1 : items.first.value.abs();
    return items.isEmpty
        ? empty('Belum ada data pada periode ini.')
        : Column(
            children: items
                .take(12)
                .map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.key,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              money(e.value, store.currency),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: (e.value / max).clamp(0, 1),
                          minHeight: 5,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
          );
  }

  int budgetActual(FinanceRow b) {
    final start = DateTime.parse(b['period_start']);
    final end = DateTime.parse(b['period_end']).add(const Duration(days: 1));
    final p = Period(start, end);
    final children = store
        .rows('categories')
        .where((c) => c['parent_id'] == b['category_id'])
        .map((c) => c['id'])
        .toSet();
    final relevant = store
        .rows('transactions')
        .where(
          (t) =>
              t['status'] == 'posted' &&
              t['currency'] == b['currency'] &&
              p.contains(t['effective_at']) &&
              t['type'] == 'expense' &&
              (b['account_id'] == null || b['account_id'] == t['account_id']),
        )
        .toList();
    return relevant.fold<int>(0, (sum, t) {
      final splits = store
          .rows('transaction_splits')
          .where((s) => s['transaction_id'] == t['id'])
          .toList();
      final value = b['category_id'] == null
          ? integer(t['amount'])
          : splits.isNotEmpty
          ? splits
                .where(
                  (s) =>
                      s['category_id'] == b['category_id'] ||
                      children.contains(s['category_id']),
                )
                .fold<int>(0, (n, s) => n + integer(s['amount']))
          : t['category_id'] == b['category_id'] ||
                children.contains(t['category_id'])
          ? integer(t['amount'])
          : 0;
      return sum + value * (t['reversal_of'] == null ? 1 : -1);
    });
  }

  Widget budgetRow(FinanceRow b) {
    final actual = budgetActual(b), budget = integer(b['amount']);
    final f = Forecast.calculate(
      actual: actual,
      budget: budget,
      period: Period(
        DateTime.parse(b['period_start']),
        DateTime.parse(b['period_end']).add(const Duration(days: 1)),
      ),
      now: financeNow(),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: InkWell(
        onTap: () => budgetEditor(existing: b),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    b['name'],
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '${(actual / budget * 100).round()}% ${actual > budget ? '· Melebihi budget' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: actual > budget ? negative : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (actual / budget).clamp(0, 1),
              color: actual > budget
                  ? negative
                  : Theme.of(context).colorScheme.primary,
              minHeight: 6,
              borderRadius: BorderRadius.circular(2),
            ),
            const SizedBox(height: 5),
            LinearProgressIndicator(
              value: (f.estimate / budget).clamp(0, 1),
              color: const Color(0xFFA76A22).withValues(alpha: .5),
              minHeight: 3,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                Text(
                  'Budget ${money(budget, b['currency'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Actual ${money(actual, b['currency'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Sisa ${money(budget - actual, b['currency'])}',
                  style: TextStyle(
                    fontSize: 12,
                    color: budget < actual ? negative : positive,
                  ),
                ),
                Text(
                  'Forecast ${money(f.estimate, b['currency'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  'Proyeksi selisih ${money(f.projectedVariance, b['currency'])}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget budgetsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Budgets',
        'Rencana yang jelas. Realisasi yang terukur.',
        action: FilledButton.icon(
          onPressed: () => budgetEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Buat budget'),
        ),
      ),
      responsive([
        kpi(
          'Budget periode',
          budgetTotal,
          note: 'Global diutamakan; kategori tidak dihitung ganda',
        ),
        kpi('Actual', expense, note: 'Expense posted, setelah refund'),
        kpi(
          'Sisa budget',
          budgetTotal - expense,
          note: 'Budget − actual',
          color: budgetTotal < expense ? negative : positive,
        ),
      ]),
      const SizedBox(height: 20),
      section(
        'Budget vs Actual',
        subtitle:
            'Klik budget untuk mengubah rencana. Actual mengikuti transaksi.',
        child: currentBudgets.isEmpty
            ? empty('Belum ada budget pada periode ini.')
            : Column(children: currentBudgets.map(budgetRow).toList()),
      ),
    ],
  );
  Widget forecastPage() {
    final f = forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'Forecast',
          'Perkiraan yang dapat ditelusuri, dengan asumsi yang terbuka.',
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 250,
              child: DropdownButtonFormField<String>(
                initialValue: model,
                decoration: const InputDecoration(labelText: 'Metode'),
                items: ['run_rate', 'scheduled', 'hybrid']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => update(() => model = v!),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => run(
                () => store.save('forecast_runs', {
                  'period': {
                    'start': period.start.toIso8601String(),
                    'end': period.end.toIso8601String(),
                  },
                  'method': model,
                  'model_version': 'v1',
                  'assumptions_json': {
                    'elapsed_days': f.elapsed,
                    'total_days': f.days,
                    'confidence': 'low',
                  },
                  'totals_json': {
                    'actual': f.actual,
                    'forecast': f.estimate,
                    'scheduled': f.scheduled,
                    'budget': f.budget,
                  },
                }),
              ),
              icon: const Icon(Icons.save_outlined),
              label: const Text('Simpan snapshot'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        responsive([
          kpi('Expense akhir periode', f.estimate, note: '$model · v1'),
          kpi(
            'Proyeksi selisih',
            f.projectedVariance,
            note: 'Budget − forecast',
            color: f.projectedVariance < 0 ? negative : positive,
          ),
          kpi(
            'Perkiraan saldo akhir',
            balance - (f.estimate - expense),
            note: 'Tanpa pemasukan masa depan tambahan',
          ),
        ]),
        const SizedBox(height: 20),
        section(
          'Aktual & forecast',
          subtitle: 'Aktual solid · forecast putus-putus',
          child: cashflowChart(forecastLine: true),
        ),
        const SizedBox(height: 20),
        responsive([
          section(
            'Metode & asumsi',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Chip(label: Text('Confidence rendah · estimasi dasar')),
                const SizedBox(height: 12),
                Text(
                  'Model ${model}_v1\n${f.elapsed} dari ${f.days} hari periode.\n${model == 'run_rate'
                      ? 'Actual ÷ hari berjalan × total hari.'
                      : model == 'scheduled'
                      ? 'Actual + tagihan terjadwal yang belum posted.'
                      : 'Actual + jadwal diketahui + estimasi variabel untuk hari tersisa.'}\nJadwal diketahui: ${money(f.scheduled, store.currency)}.\nTidak menggabungkan mata uang berbeda.\nData generated: ${DateFormat('d MMM y HH:mm', 'id_ID').format(DateTime.now())}',
                  style: const TextStyle(height: 1.8),
                ),
              ],
            ),
          ),
          section(
            'What-if scenario',
            subtitle: 'Simulation only · tidak mengubah catatan aktual',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  initialValue: scenario.toString(),
                  decoration: const InputDecoration(
                    labelText: 'Tambahan pengeluaran (minor units)',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      update(() => scenario = int.tryParse(v) ?? 0),
                ),
                const SizedBox(height: 20),
                const Text('Expense simulasi'),
                amount(f.estimate + scenario),
                const SizedBox(height: 16),
                Text(
                  'Proyeksi selisih: ${money(f.budget - f.estimate - scenario, store.currency)}',
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => run(
                    () => store.save('forecast_scenarios', {
                      'changes_json': {'extra_expense': scenario},
                      'result_json': {
                        'estimate': f.estimate + scenario,
                        'method': model,
                      },
                    }),
                  ),
                  child: const Text('Simpan simulasi'),
                ),
              ],
            ),
          ),
        ], min: 330),
      ],
    );
  }

  Widget savingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Savings Goals',
        'Alokasi tabungan tidak dihitung sebagai pengeluaran.',
        action: FilledButton.icon(
          onPressed: goalEditor,
          icon: const Icon(Icons.add),
          label: const Text('Buat tujuan'),
        ),
      ),
      if (store.rows('savings_goals').isEmpty)
        section(
          'Tujuan tabungan',
          child: empty('Buat tujuan pertama untuk rencana Anda.'),
        )
      else
        responsive(
          store.rows('savings_goals').map((g) {
            final saved = store
                .rows('goal_allocations')
                .where((a) => a['goal_id'] == g['id'])
                .fold<int>(0, (s, a) => s + integer(a['amount']));
            final months = math.max(
              1,
              (DateTime.parse(
                        g['target_date'],
                      ).difference(DateTime.now()).inDays /
                      30)
                  .ceil(),
            );
            return section(
              g['name'],
              subtitle: 'Target ${dateLabel(g['target_date'])}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${money(saved, g['currency'])} / ${money(g['target_amount'], g['currency'])}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: (saved / integer(g['target_amount'])).clamp(0, 1),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Kebutuhan per bulan ${money(math.max(0, integer(g['target_amount']) - saved) ~/ months, g['currency'])}',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () async {
                      final v = await recordDialog('Tambah alokasi', [
                        Field('amount', 'Nominal', number: true),
                        Field('notes', 'Catatan', required: false),
                      ]);
                      if (v != null) {
                        run(
                          () => store.save('goal_allocations', {
                            'goal_id': g['id'],
                            'amount': parseMoney(v['amount'], g['currency']),
                            'notes': v['notes'],
                          }),
                        );
                      }
                    },
                    child: const Text('Tambah alokasi'),
                  ),
                ],
              ),
            );
          }).toList(),
          min: 300,
        ),
    ],
  );
  int outstanding(FinanceRow d) =>
      integer(d['principal']) -
      store
          .rows('debt_payments')
          .where((p) => p['debt_id'] == d['id'])
          .fold<int>(0, (s, p) => s + integer(p['principal_paid']));
  Widget debtsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Debts & Installments',
        'Pokok, bunga, dan jatuh tempo tercatat terpisah.',
        action: FilledButton.icon(
          onPressed: debtEditor,
          icon: const Icon(Icons.add),
          label: const Text('Tambah utang/piutang'),
        ),
      ),
      if (store.rows('debts').isEmpty)
        section(
          'Utang & piutang',
          child: empty('Belum ada utang atau piutang.'),
        )
      else
        responsive(
          store
              .rows('debts')
              .map(
                (d) => section(
                  d['name'],
                  subtitle:
                      '${d['counterparty']} · ${d['kind'] == 'debt' ? 'Utang' : 'Piutang'}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(outstanding(d), d['currency']),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Jatuh tempo ${dateLabel(d['due'])}'),
                      Text(
                        'Pokok ${money(d['principal'], d['currency'])} · bunga ${d['rate']}%',
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: outstanding(d) <= 0
                            ? null
                            : () => debtPaymentEditor(d),
                        child: const Text('Catat pembayaran'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          min: 300,
        ),
    ],
  );
  Widget categoriesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Categories',
        'Kategori kustom, hingga dua tingkat.',
        action: FilledButton.icon(
          onPressed: () => categoryEditor(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah kategori'),
        ),
      ),
      responsive(
        ['income', 'expense']
            .map(
              (type) => section(
                type == 'income' ? 'Pemasukan' : 'Pengeluaran',
                child: Column(
                  children: store
                      .rows('categories')
                      .where((c) => c['type'] == type)
                      .map(
                        (c) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            c['parent_id'] == null
                                ? Icons.category_outlined
                                : Icons.subdirectory_arrow_right,
                            size: 20,
                          ),
                          title: Text(c['name']),
                          subtitle: c['archived'] == true
                              ? const Text('Diarsipkan')
                              : null,
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'edit') {
                                categoryEditor(existing: c);
                              } else {
                                run(
                                  () => store.save('categories', {
                                    'archived': c['archived'] != true,
                                  }, id: c['id']),
                                );
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text(
                                  c['archived'] == true
                                      ? 'Aktifkan'
                                      : 'Arsipkan',
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
            .toList(),
        min: 330,
      ),
    ],
  );
  Widget templatesPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Transaction Templates',
        'Preset selalu dibuka untuk ditinjau sebelum disimpan.',
        action: FilledButton.icon(
          onPressed: templateEditor,
          icon: const Icon(Icons.add),
          label: const Text('Buat template'),
        ),
      ),
      if (store.rows('transaction_templates').isEmpty)
        section(
          'Template Anda',
          child: empty('Simpan transaksi favorit sebagai preset.'),
        )
      else
        responsive(
          store
              .rows('transaction_templates')
              .map(
                (t) => section(
                  t['name'],
                  subtitle:
                      '${t['payload_json']['type']} · ${t['favourite'] == true ? 'Favorit' : 'Preset'}',
                  action: IconButton(
                    tooltip: 'Favorit',
                    icon: Icon(
                      t['favourite'] == true ? Icons.star : Icons.star_outline,
                      size: 20,
                    ),
                    onPressed: () => run(
                      () => store.save('transaction_templates', {
                        'favourite': t['favourite'] != true,
                      }, id: t['id']),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money(
                          t['payload_json']['amount'],
                          t['payload_json']['currency'] ?? 'IDR',
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => transactionEditor(
                          prefill: FinanceRow.from(t['payload_json']),
                        ),
                        child: const Text('Gunakan template'),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
          min: 280,
        ),
    ],
  );
  Widget recurringPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Recurring Transactions',
        'Jadwal otomatis dengan posting idempotent.',
        action: FilledButton.icon(
          onPressed: recurringEditor,
          icon: const Icon(Icons.add),
          label: const Text('Buat jadwal'),
        ),
      ),
      section(
        'Jadwal transaksi',
        subtitle: 'Default pending agar nominal dapat Anda tinjau.',
        child: store.rows('recurring_rules').isEmpty
            ? empty('Belum ada transaksi berulang.')
            : Column(
                children: store
                    .rows('recurring_rules')
                    .map(
                      (r) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_repeat_outlined),
                        title: Text(r['name']),
                        subtitle: Text(
                          '${r['cadence']} · ${dateLabel(r['next_at'])} · ${r['mode']}',
                        ),
                        trailing: Switch(
                          value: r['active'] == true,
                          onChanged: (v) => run(
                            () => store.save('recurring_rules', {
                              'active': v,
                            }, id: r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
  Widget settingsPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading('Settings', 'Preferensi, keamanan, dan profil Anda.'),
      responsive([
        section(
          'Profil & regional',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                store.profile['display_name'] ?? '',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(store.client.auth.currentUser?.email ?? ''),
              const SizedBox(height: 8),
              Text(
                '${store.profile['timezone'] ?? 'Asia/Jakarta'} · ${store.currency}',
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: profileEditor,
                child: const Text('Edit profil'),
              ),
            ],
          ),
        ),
        section(
          'Tampilan',
          subtitle: 'Light, dark, atau mengikuti perangkat.',
          child: DropdownButtonFormField<String>(
            initialValue: store.profile['theme'] ?? 'system',
            decoration: const InputDecoration(labelText: 'Tema'),
            items: [
              'system',
              'light',
              'dark',
            ].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) {
              widget.onTheme(v!);
              run(() async {
                await store.db
                    .from('profiles')
                    .update({'theme': v})
                    .eq('user_id', store.uid);
                await store.refresh();
              });
            },
          ),
        ),
        passwordPanel(),
        section(
          'Custom fields',
          subtitle: 'Tipe dan definisi field transaksi.',
          action: IconButton(
            tooltip: 'Tambah custom field',
            onPressed: customFieldEditor,
            icon: const Icon(Icons.add),
          ),
          child: store.rows('custom_field_definitions').isEmpty
              ? const Text('Belum ada custom field.')
              : Column(
                  children: store
                      .rows('custom_field_definitions')
                      .map(
                        (f) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(f['field_key']),
                          subtitle: Text(
                            '${f['field_type']} ${f['required'] == true ? '· Wajib' : ''}',
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        section(
          'Sesi & privasi',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'File lampiran bersifat privat. Akses agent dapat dicabut kapan saja.',
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => run(
                  () => store.client.auth.signOut(scope: SignOutScope.global),
                  success: 'Semua sesi telah keluar.',
                ),
                child: const Text('Keluar dari semua perangkat'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => go(11),
                child: const Text('Ekspor data saya'),
              ),
            ],
          ),
        ),
      ], min: 330),
    ],
  );
  Widget passwordPanel({bool forced = false}) => section(
    forced ? 'Ganti password sementara' : 'Keamanan password',
    subtitle: forced
        ? 'Anda harus mengganti password sebelum melanjutkan.'
        : 'Gunakan password lama untuk memverifikasi perubahan.',
    child: FilledButton.tonal(
      onPressed: changePassword,
      child: const Text('Ganti password'),
    ),
  );
  Future<void> changePassword() async {
    final v = await recordDialog('Ganti password', [
      Field('old_password', 'Password lama', secret: true),
      Field('new_password', 'Password baru (min. 8 karakter)', secret: true),
      Field('confirm', 'Konfirmasi password', secret: true),
    ]);
    if (v == null) return;
    if (v['new_password'].length < 8 || v['new_password'] != v['confirm']) {
      toast('Minimal 8 karakter dan konfirmasi harus sama.');
      return;
    }
    run(() async {
      final result = await store.api(
        'auth/change-password',
        method: 'POST',
        body: v,
      );
      await store.client.auth.setSession(result['refresh_token']);
      await store.refresh();
    });
  }

  Future<void> profileEditor() async {
    final p = store.profile;
    final v = await recordDialog('Edit profil', [
      Field('display_name', 'Nama tampilan', value: p['display_name']),
      Field(
        'base_currency',
        'Mata uang utama',
        value: p['base_currency'],
        options: {
          'IDR': 'IDR · Rupiah',
          'USD': 'USD · US Dollar',
          'EUR': 'EUR · Euro',
          'SGD': 'SGD · Singapore Dollar',
        },
      ),
      Field(
        'timezone',
        'Timezone',
        value: p['timezone'],
        options: {
          'Asia/Jakarta': 'Asia/Jakarta',
          'Asia/Makassar': 'Asia/Makassar',
          'Asia/Jayapura': 'Asia/Jayapura',
          'UTC': 'UTC',
          'Asia/Singapore': 'Asia/Singapore',
        },
      ),
      Field(
        'week_start',
        'Awal minggu',
        value: '${p['week_start']}',
        options: {'1': 'Senin', '7': 'Minggu'},
      ),
    ]);
    if (v != null) {
      run(() async {
        await store.db
            .from('profiles')
            .update({...v, 'week_start': int.parse(v['week_start'])})
            .eq('user_id', store.uid);
        await store.refresh();
      });
    }
  }
}

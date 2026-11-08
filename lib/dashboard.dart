part of 'shell.dart';

extension _GlassDashboard on _FinanceShellState {
  Widget glassDashboard() => LayoutBuilder(
    builder: (context, box) {
      final desktop = box.maxWidth >= 860;
      final parts = <String, Widget>{
        'summary': desktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 4, child: balanceCard()),
                  const SizedBox(width: 16),
                  for (var i = 0; i < 3; i++) ...[
                    Expanded(flex: 2, child: dashboardMetric(i)),
                    if (i < 2) const SizedBox(width: 16),
                  ],
                ],
              )
            : balanceCard(),
        'accounts': dashboardAccounts(),
        'metrics': Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(child: dashboardMetric(i, compact: true)),
              if (i < 2) const SizedBox(width: 10),
            ],
          ],
        ),
        'cashflow': dashboardChart(),
        'budgets': dashboardBudgets(),
        'recent': section(
          'Transaksi terakhir',
          action: dashboardLink('Lihat semua', () => go(1)),
          child: periodTransactions.isEmpty
              ? empty(
                  'Belum ada transaksi di periode ini.',
                  action: 'Tambah transaksi',
                  onPressed: () => transactionEditor(),
                )
              : Column(
                  children: periodTransactions
                      .take(MediaQuery.sizeOf(context).width < 768 ? 2 : 3)
                      .map((t) => transactionTile(t, compact: true))
                      .toList(),
                ),
        ),
        'categories': dashboardCategories(),
        'upcoming': dashboardUpcoming(),
      };
      final visible = dashboardOrder
          .where(
            (key) =>
                !hiddenWidgets.contains(key) && (!desktop || key != 'metrics'),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Keuangan dalam kendali.',
                        style: TextStyle(
                          fontSize: box.maxWidth < 600 ? 23 : 30,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.8,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ringkasan Anda · ${period.label}',
                        style: TextStyle(
                          fontSize: box.maxWidth < 600 ? 12 : 14,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Atur tampilan',
                  onPressed: dashboardCustomize,
                  icon: const Icon(Icons.tune_rounded, size: 20),
                ),
              ],
            ),
          ),
          for (var i = 0; i < visible.length; i++) ...[
            if (desktop &&
                i + 1 < visible.length &&
                ((visible[i] == 'cashflow' && visible[i + 1] == 'budgets') ||
                    (visible[i] == 'recent' && visible[i + 1] == 'categories')))
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: parts[visible[i]]!),
                  const SizedBox(width: 18),
                  Expanded(child: parts[visible[++i]]!),
                ],
              )
            else
              parts[visible[i]]!,
            const SizedBox(height: 18),
          ],
          const SizedBox(height: 64),
        ],
      );
    },
  );
  Widget dashboardLink(String label, VoidCallback onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(44, 36),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 3),
        const Icon(Icons.chevron_right, size: 16),
      ],
    ),
  );
  Widget balanceCard() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final count = store
        .rows('accounts')
        .where((a) => a['currency'] == store.currency)
        .length;
    return GlassPanel(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: 150,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: CustomPaint(painter: BalanceWavePainter(dark)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 14, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Total saldo',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: balanceVisible
                            ? 'Sembunyikan total saldo'
                            : 'Tampilkan total saldo',
                        onPressed: () =>
                            update(() => balanceVisible = !balanceVisible),
                        icon: Icon(
                          balanceVisible
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                    ],
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      balanceVisible
                          ? money(balance, store.currency)
                          : '••••••••',
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1.1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    '$count rekening · ${store.currency}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget dashboardMetric(int index, {bool compact = false}) {
    final labels = ['Pemasukan', 'Pengeluaran', 'Arus kas bersih'];
    final values = [income, expense, income - expense];
    final colors = [positive, negative, Theme.of(context).colorScheme.primary];
    final icons = [
      Icons.south_rounded,
      Icons.north_rounded,
      Icons.swap_horiz_rounded,
    ];
    return GlassPanel(
      padding: EdgeInsets.all(compact ? 12 : 18),
      child: SizedBox(
        height: compact ? 88 : 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GlassIcon(
              icons[index],
              color: colors[index],
              size: compact ? 30 : 38,
            ),
            Text(
              labels[index],
              maxLines: 2,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.15,
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(values[index], store.currency),
                style: TextStyle(
                  fontSize: compact ? 16 : 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                  color: index == 2
                      ? Theme.of(context).colorScheme.onSurface
                      : colors[index],
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget dashboardAccounts() => GlassPanel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Rekening & dompet',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.4,
                ),
              ),
            ),
            dashboardLink('Lihat semua', () => go(2)),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, box) {
            final accounts = store
                .rows('accounts')
                .where((a) => a['status'] == 'active')
                .take(12)
                .toList();
            final cardWidth = box.maxWidth >= 700
                ? math.max(
                    144.0,
                    (box.maxWidth - math.min(accounts.length, 4) * 12) /
                        (math.min(accounts.length, 4) + 1),
                  )
                : 140.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < accounts.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: SizedBox(
                            width: cardWidth,
                            child: GlassPanel(
                              radius: 20,
                              padding: EdgeInsets.zero,
                              blur: false,
                              tint: i == 0
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.primary.withValues(alpha: .07)
                                  : null,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  update(() {
                                    filter = TransactionFilter()
                                      ..account = accounts[i]['id'];
                                    searchController.clear();
                                  });
                                  go(1);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      GlassIcon(
                                        switch (accounts[i]['type']) {
                                          'bank' =>
                                            Icons.account_balance_outlined,
                                          'ewallet' =>
                                            Icons
                                                .account_balance_wallet_outlined,
                                          _ => Icons.payments_outlined,
                                        },
                                        color: [
                                          const Color(0xFF2284FC),
                                          const Color(0xFF8D6BEA),
                                          const Color(0xFF28AC93),
                                          const Color(0xFFD29D36),
                                        ][i % 4],
                                        size: 28,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        accounts[i]['name'],
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          money(
                                            accounts[i]['balance'],
                                            accounts[i]['currency'],
                                          ),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            fontFeatures: [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: cardWidth,
                        child: GlassPanel(
                          radius: 20,
                          padding: EdgeInsets.zero,
                          blur: false,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => accountEditor(),
                            child: const SizedBox(
                              height: 104,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add, size: 28),
                                  SizedBox(height: 10),
                                  Text(
                                    'Tambah akun',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if ((cardWidth + 12) * (accounts.length + 1) - 12 >
                    box.maxWidth + 1) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Geser untuk melihat rekening lainnya',
                    style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    ),
  );
  Widget dashboardChart() => GlassPanel(
    padding: const EdgeInsets.all(18),
    child: LayoutBuilder(
      builder: (context, box) {
        final selector = Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest.withValues(alpha: .65),
            border: Border.all(color: Colors.white.withValues(alpha: .22)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final item in [(false, 'Arus kas'), (true, 'Pengeluaran')])
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => update(() => dashboardChartExpense = item.$1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: dashboardChartExpense == item.$1
                          ? const LinearGradient(
                              colors: [Color(0xFF65BFFF), Color(0xFF247FF5)],
                            )
                          : null,
                      boxShadow: dashboardChartExpense == item.$1
                          ? [
                              BoxShadow(
                                color: const Color(
                                  0xFF2578E9,
                                ).withValues(alpha: .18),
                                blurRadius: 8,
                              ),
                            ]
                          : null,
                    ),
                    child: Text(
                      item.$2,
                      style: TextStyle(
                        fontSize: 11,
                        color: dashboardChartExpense == item.$1
                            ? Colors.white
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassIcon(
              Icons.bar_chart_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            ),
            const SizedBox(width: 10),
            const Text(
              'Tren keuangan',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -.5,
              ),
            ),
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (box.maxWidth < 420) ...[
              title,
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: selector),
            ] else
              Row(
                children: [
                  Expanded(child: title),
                  selector,
                ],
              ),
            const SizedBox(height: 24),
            cashflowChart(expenseLine: dashboardChartExpense, compact: true),
          ],
        );
      },
    ),
  );
  Widget dashboardBudgets() {
    final planned = budgetTotal, used = expense;
    final ratio = planned <= 0 ? 0.0 : (used / planned).clamp(0.0, 1.0);
    final color = used > planned && planned > 0
        ? negative
        : Theme.of(context).colorScheme.primary;
    Widget legend(String title, int value, Color dot) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 5, right: 8),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    money(value, store.currency),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return section(
      periodType == 'Month' ? 'Budget bulanan' : 'Budget periode',
      action: dashboardLink('Lihat semua', () => go(4)),
      child: currentBudgets.isEmpty
          ? empty(
              'Mulai rencanakan pengeluaran Anda.',
              action: 'Buat budget',
              onPressed: () => budgetEditor(),
            )
          : Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 112,
                      height: 112,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          PieChart(
                            PieChartData(
                              startDegreeOffset: 270,
                              sectionsSpace: 0,
                              centerSpaceRadius: 43,
                              sections: [
                                if (ratio > 0)
                                  PieChartSectionData(
                                    value: ratio,
                                    color: color,
                                    radius: 14,
                                    showTitle: false,
                                  ),
                                if (ratio < 1)
                                  PieChartSectionData(
                                    value: 1 - ratio,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                    radius: 14,
                                    showTitle: false,
                                  ),
                              ],
                            ),
                          ),
                          Text(
                            planned > 0
                                ? '${(used / planned * 100).round()}%'
                                : '—',
                            style: const TextStyle(
                              fontSize: 23,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          legend('Terpakai', used, color),
                          legend(
                            'Sisa',
                            planned - used,
                            Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: .45),
                          ),
                          legend(
                            'Total budget',
                            planned,
                            Theme.of(context).colorScheme.onSurfaceVariant
                                .withValues(alpha: .25),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                for (final budget
                    in currentBudgets
                        .where((b) => b['category_id'] != null)
                        .take(2))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => go(4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  budget['name'],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Text(
                                money(budgetActual(budget), budget['currency']),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value:
                                  (budgetActual(budget) /
                                          math.max(
                                            1,
                                            integer(budget['amount']),
                                          ))
                                      .clamp(0, 1),
                              minHeight: 6,
                              color:
                                  budgetActual(budget) >
                                      integer(budget['amount'])
                                  ? negative
                                  : color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget dashboardCategories() {
    final values = <String, int>{};
    for (final tx in posted.where((t) => t['type'] == 'expense')) {
      final splits = store
          .rows('transaction_splits')
          .where((s) => s['transaction_id'] == tx['id']);
      final sign = tx['reversal_of'] == null ? 1 : -1;
      if (splits.isEmpty) {
        final name = store.name('categories', tx['category_id']);
        values[name] = (values[name] ?? 0) + integer(tx['amount']) * sign;
      } else {
        for (final split in splits) {
          final name = store.name('categories', split['category_id']);
          values[name] = (values[name] ?? 0) + integer(split['amount']) * sign;
        }
      }
    }
    final sorted = values.entries.where((v) => v.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final items = sorted.take(4).toList();
    if (sorted.length > 4) {
      items.add(
        MapEntry('Lainnya', sorted.skip(4).fold(0, (sum, e) => sum + e.value)),
      );
    }
    final total = items.fold(0, (sum, e) => sum + e.value);
    const colors = [
      Color(0xFF348AFF),
      Color(0xFF4AC79D),
      Color(0xFFF5C05D),
      Color(0xFFA67AF4),
      Color(0xFFAAB8CA),
    ];
    return section(
      'Ringkasan kategori',
      action: dashboardLink('Analisis', () => go(3)),
      child: items.isEmpty
          ? empty('Belum ada pengeluaran pada periode ini.')
          : LayoutBuilder(
              builder: (context, box) {
                final chart = SizedBox(
                  width: 144,
                  height: 144,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          centerSpaceRadius: 51,
                          startDegreeOffset: 270,
                          sectionsSpace: 1,
                          sections: [
                            for (var i = 0; i < items.length; i++)
                              PieChartSectionData(
                                value: items[i].value.toDouble(),
                                color: colors[i],
                                radius: 20,
                                showTitle: false,
                              ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            NumberFormat.compactCurrency(
                              locale: 'id',
                              symbol: 'Rp ',
                              decimalDigits: 1,
                            ).format(total),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Pengeluaran',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
                final legend = Column(
                  children: [
                    for (var i = 0; i < items.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 9,
                              height: 9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors[i],
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                items[i].key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${(items[i].value / total * 100).round()}%',
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              money(items[i].value, store.currency),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return box.maxWidth >= 420
                    ? Row(
                        children: [
                          chart,
                          const SizedBox(width: 20),
                          Expanded(child: legend),
                        ],
                      )
                    : Column(
                        children: [
                          Center(child: chart),
                          const SizedBox(height: 14),
                          legend,
                        ],
                      );
              },
            ),
    );
  }

  Widget dashboardUpcoming() {
    final recurring = store
        .rows('recurring_rules')
        .where((r) => r['active'] == true)
        .take(3)
        .toList();
    final debts = store
        .rows('debts')
        .where((r) => outstanding(r) > 0)
        .take(2)
        .toList();
    if (recurring.isEmpty && debts.isEmpty) {
      return section(
        'Rencana berikutnya',
        child: Row(
          children: [
            GlassIcon(
              Icons.event_available_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'Catat tagihan rutin agar rencana keuangan lebih terarah.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            IconButton(
              tooltip: 'Lihat transaksi berulang',
              onPressed: () => go(10),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      );
    }
    return section(
      'Akan datang',
      child: Column(
        children: [
          for (final rule in recurring)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: GlassIcon(
                Icons.event_repeat_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(rule['name']),
              subtitle: Text(dateLabel(rule['next_at'])),
              trailing: Text(
                money(
                  rule['payload_json']['amount'],
                  rule['payload_json']['currency'] ?? 'IDR',
                ),
              ),
            ),
          for (final debt in debts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: GlassIcon(
                Icons.credit_card_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(debt['name']),
              subtitle: Text(dateLabel(debt['due'])),
              trailing: Text(money(outstanding(debt), debt['currency'])),
            ),
        ],
      ),
    );
  }
}

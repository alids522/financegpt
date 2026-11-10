part of 'shell.dart';

extension _AccountStatements on _FinanceShellState {
  Future<void> accountStatement(FinanceRow account) => showDialog<void>(
    context: context,
    builder: (_) => AccountStatementDialog(store: store, account: account),
  );
}

Future<Uint8List> buildAccountStatementPdf(
  FinanceRow data,
  StatementRange range,
) async {
  final currency = data['currency'] as String;
  final rows = List<FinanceRow>.from(data['rows']);
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Inter.ttf'));
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: font, bold: font),
  );
  final ink = PdfColor.fromHex('#14263D'), blue = PdfColor.fromHex('#1978F8');
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(28),
      maxPages: 2000,
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'ADOETZ FINANCE',
                style: pw.TextStyle(fontSize: 18, color: blue),
              ),
              pw.Text(
                'E-STATEMENT',
                style: pw.TextStyle(fontSize: 14, color: ink),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            '${data['account_name']} · $currency',
            style: const pw.TextStyle(fontSize: 14),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${range.start} — ${range.end} (inklusif) · ${data['timezone']}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 12),
        ],
      ),
      footer: (c) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Dibuat ${dateLabel(data['generated_at'])} · ${data['row_count']} mutasi',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              '${c.pageNumber} / ${c.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
      ),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          color: PdfColor.fromHex('#EEF4FC'),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              for (final entry in [
                ('Saldo awal', 'opening_minor'),
                ('Total debit', 'debit_minor'),
                ('Total kredit', 'credit_minor'),
                ('Saldo akhir', 'closing_minor'),
              ])
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(entry.$1, style: const pw.TextStyle(fontSize: 9)),
                    pw.SizedBox(height: 5),
                    pw.Text(
                      money(data[entry.$2], currency),
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                  ],
                ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        if (rows.isEmpty)
          pw.Text('Tidak ada mutasi pada periode ini.')
        else
          pw.TableHelper.fromTextArray(
            headers: ['Tanggal', 'Keterangan', 'Debit', 'Kredit', 'Saldo'],
            data: [
              for (final row in rows)
                [
                  DateFormat(
                    'dd MMM yyyy HH:mm',
                    'id_ID',
                  ).format(localTime(row['posted_at'])),
                  '${row['description']}${(row['merchant'] ?? '').isEmpty ? '' : ' · ${row['merchant']}'}',
                  integer(row['debit_minor']) == 0
                      ? '—'
                      : money(row['debit_minor'], currency),
                  integer(row['credit_minor']) == 0
                      ? '—'
                      : money(row['credit_minor'], currency),
                  money(row['balance_minor'], currency),
                ],
            ],
            headerStyle: pw.TextStyle(fontSize: 9, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: ink),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(7),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            columnWidths: {
              0: const pw.FlexColumnWidth(1.3),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FlexColumnWidth(1.4),
              3: const pw.FlexColumnWidth(1.4),
              4: const pw.FlexColumnWidth(1.5),
            },
          ),
      ],
    ),
  );

  return doc.save();
}

class AccountStatementDialog extends StatefulWidget {
  final FinanceStore store;
  final FinanceRow account;
  const AccountStatementDialog({
    super.key,
    required this.store,
    required this.account,
  });
  @override
  State<AccountStatementDialog> createState() => _AccountStatementDialogState();
}

class _AccountStatementDialogState extends State<AccountStatementDialog> {
  late StatementRange range = StatementRange.month(
    financeNow().year,
    financeNow().month,
  );
  FinanceRow? statement;
  bool busy = false;
  String? error;
  String get currency => widget.account['currency'];
  Future<void> chooseMonth() async {
    var month = range.from.month;
    final year = TextEditingController(text: '${range.from.year}');
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, local) => AlertDialog(
          title: const Text('Pilih bulan'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: month,
                  decoration: const InputDecoration(labelText: 'Bulan'),
                  items: [
                    for (var m = 1; m <= 12; m++)
                      DropdownMenuItem(
                        value: m,
                        child: Text(
                          DateFormat('MMMM', 'id_ID').format(DateTime(2026, m)),
                        ),
                      ),
                  ],
                  onChanged: (v) => local(() => month = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Tahun'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Pilih'),
            ),
          ],
        ),
      ),
    );
    final selectedYear = int.tryParse(year.text);
    year.dispose();
    if (result != true || !mounted) return;
    if (selectedYear == null || selectedYear < 2000 || selectedYear > 2100) {
      setState(() => error = 'Tahun harus antara 2000–2100.');
      return;
    }
    setState(() {
      range = StatementRange.month(selectedYear, month);
      statement = null;
      error = null;
    });
  }

  Future<void> chooseCustom() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      initialDateRange: DateTimeRange(
        start: DateTime(range.from.year, range.from.month, range.from.day),
        end: DateTime(range.to.year, range.to.month, range.to.day),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        range = StatementRange(selected.start, selected.end);
        statement = null;
        error = null;
      });
    }
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = FinanceRow.from(
        await widget.store.api(
          'accounts/${widget.account['id']}/statement?start=${range.start}&end=${range.end}',
        ),
      );
      if (mounted) setState(() => statement = result);
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(String format) async {
    if (statement == null) {
      await load();
      if (statement == null) return;
    }
    final data = statement!;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rows = List<FinanceRow>.from(data['rows']);
      final filename =
          'estatement-${widget.account['id']}-${range.start}-${range.end}.$format';
      if (format == 'csv') {
        final records = <List<dynamic>>[
          ['Adoetz Finance E-statement', data['account_name'], currency],
          ['Periode', range.start, range.end],
          ['Saldo awal (minor units)', data['opening_minor']],
          ['Total debit (minor units)', data['debit_minor']],
          ['Total kredit (minor units)', data['credit_minor']],
          ['Saldo akhir (minor units)', data['closing_minor']],
          [],
          [
            'entry_id',
            'transaction_id',
            'date_time',
            'description',
            'merchant',
            'type',
            'debit_minor',
            'credit_minor',
            'balance_minor',
            'currency',
          ],
          for (final row in rows)
            [
              row['entry_id'],
              row['transaction_id'] ?? '',
              row['posted_at'],
              row['description'],
              row['merchant'],
              row['type'],
              row['debit_minor'],
              row['credit_minor'],
              row['balance_minor'],
              currency,
            ],
        ];
        final bytes = utf8.encode(encodeCsv(records));
        if (kIsWeb) {
          await FileSaver.instance.saveFile(
            name: filename.replaceAll('.csv', ''),
            fileExtension: 'csv',
            bytes: bytes,
            mimeType: MimeType.csv,
          );
        } else {
          await FilePicker.saveFile(
            fileName: filename,
            bytes: bytes,
            dialogTitle: 'Simpan e-statement CSV',
          );
        }
      } else {
        await Printing.sharePdf(
          bytes: await buildAccountStatementPdf(data, range),
          filename: filename,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900, maxHeight: 850),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'E-statement · ${widget.account['name']}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup e-statement',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : chooseMonth,
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Pilih bulan'),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : chooseCustom,
                  icon: const Icon(Icons.date_range),
                  label: const Text('Custom tanggal'),
                ),
                FilledButton(
                  onPressed: busy ? null : load,
                  child: const Text('Tampilkan mutasi'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${dateLabel(range.start)} — ${dateLabel(range.end)} · semua tanggal termasuk',
            ),
            const SizedBox(height: 12),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (statement != null) ...[
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 24,
                        runSpacing: 12,
                        children: [
                          for (final item in [
                            ('Saldo awal', 'opening_minor'),
                            ('Debit', 'debit_minor'),
                            ('Kredit', 'credit_minor'),
                            ('Saldo akhir', 'closing_minor'),
                          ])
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.$1,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                Text(
                                  money(statement![item.$2], currency),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${statement!['row_count']} mutasi · preview 15 baris pertama; file berisi seluruh mutasi.',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      for (final row in List<FinanceRow>.from(
                        statement!['rows'],
                      ).take(15))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            row['description'],
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${dateLabel(row['posted_at'])} · saldo ${money(row['balance_minor'], currency)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Text(
                            integer(row['debit_minor']) > 0
                                ? '−${money(row['debit_minor'], currency)}'
                                : '+${money(row['credit_minor'], currency)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if (integer(statement!['row_count']) == 0)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Tidak ada mutasi pada periode ini.'),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => export('pdf'),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Ekspor PDF'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => export('csv'),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Ekspor CSV'),
                  ),
                ],
              ),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Pilih bulan (tanggal 1 sampai akhir bulan) atau tentukan rentang tanggal sendiri, lalu tampilkan mutasi.',
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

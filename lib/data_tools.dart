part of 'shell.dart';

const csvHeaders = [
  'transaction_id',
  'date_time',
  'type',
  'amount',
  'currency',
  'account',
  'destination_account',
  'category',
  'subcategory',
  'merchant',
  'description',
  'tags',
  'status',
  'source_ref',
];

extension _FinanceDataTools on _FinanceShellState {
  Widget dataPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Import & Export',
        'Data Anda tetap portabel, di web dan mobile.',
      ),
      responsive([
        section(
          'Import data',
          subtitle: 'CSV atau laporan PDF digital · maksimal 10 MB',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih file, petakan kolom, periksa duplikasi, lalu konfirmasi. Tidak ada transaksi yang disimpan sebelum Anda meninjau preview.',
                style: TextStyle(height: 1.7),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: importFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Pilih CSV / PDF'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: downloadSample,
                child: const Text('Unduh contoh CSV'),
              ),
              const SizedBox(height: 12),
              const Text(
                'PDF hasil scan membutuhkan OCR dan belum didukung pada rilis awal.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        section(
          'Export laporan',
          subtitle: 'Mengikuti periode dan filter transaksi aktif',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${filteredTransactions.length} transaksi · ${period.label}',
                style: const TextStyle(height: 1.7),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => exportData(filteredTransactions),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export CSV / PDF'),
              ),
              const SizedBox(height: 20),
              const Text(
                'CSV menyimpan ID stabil dan nominal minor units. PDF berisi ringkasan, tabel transaksi, budget, dan asumsi forecast.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
            ],
          ),
        ),
      ], min: 330),
      const SizedBox(height: 24),
      section(
        'Riwayat pekerjaan',
        child: Column(
          children: [
            ...store
                .rows('import_jobs')
                .reversed
                .take(10)
                .map(
                  (j) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_upload_outlined),
                    title: Text('Import ${j['format']} · ${j['status']}'),
                    subtitle: Text(
                      '${dateLabel(j['created_at'])} · ${jsonEncode(j['totals_json'] ?? {})}',
                    ),
                  ),
                ),
            ...store
                .rows('export_jobs')
                .reversed
                .take(10)
                .map(
                  (j) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.file_download_outlined),
                    title: Text('Export ${j['format']} · ${j['status']}'),
                    subtitle: Text(dateLabel(j['created_at'])),
                  ),
                ),
            if (store.rows('import_jobs').isEmpty &&
                store.rows('export_jobs').isEmpty)
              empty('Belum ada pekerjaan import/export.'),
          ],
        ),
      ),
    ],
  );
  List<List<dynamic>> csvRows(List<FinanceRow> rows) => [
    csvHeaders,
    ...rows.map(
      (t) => [
        t['id'],
        t['effective_at'],
        t['type'],
        t['amount'],
        t['currency'],
        store.name('accounts', t['account_id']),
        t['destination_account_id'] == null
            ? ''
            : store.name('accounts', t['destination_account_id']),
        store.name('categories', t['category_id']),
        '',
        t['merchant'],
        t['description'],
        (t['tags'] as List? ?? []).join('|'),
        t['status'],
        t['source_ref'] ?? '',
      ],
    ),
  ];
  Future<void> downloadSample() async {
    await FileSaver.instance.saveFile(
      name: 'finance-tracker-template',
      fileExtension: 'csv',
      mimeType: MimeType.csv,
      bytes: Uint8List.fromList(
        utf8.encode(
          encodeCsv([
            csvHeaders,
            [
              '',
              DateTime.now().toUtc().toIso8601String(),
              'expense',
              '35000',
              'IDR',
              store.rows('accounts').firstOrNull?['name'] ?? 'Cash',
              '',
              'Makanan & Minuman',
              '',
              'Warung',
              'Makan siang',
              'makan',
              'posted',
              'sample-001',
            ],
          ]),
        ),
      ),
    );
    toast('Contoh CSV diunduh.');
  }

  Future<void> exportData(List<FinanceRow> input) async {
    final snapshot = input.map((t) => FinanceRow.from(t)).toList();
    final v = await recordDialog('Export laporan', [
      const Field(
        'format',
        'Format',
        options: {'csv': 'CSV · row records', 'pdf': 'PDF · laporan'},
      ),
      Field(
        'dataset',
        'Dataset',
        options: {
          'transactions': 'Transaksi + ringkasan',
          'budget': 'Budget vs Actual',
          'forecast': 'Forecast + asumsi',
        },
      ),
    ], saveLabel: 'Buat file');
    if (v == null) return;
    await run(() async {
      final jobId = uuid.v4();
      await store.db.from('export_jobs').insert({
        'id': jobId,
        'user_id': store.uid,
        'type': v['dataset'],
        'format': v['format'],
        'filter_snapshot': {
          'period_start': period.start.toIso8601String(),
          'period_end': period.end.toIso8601String(),
          'transaction_ids': snapshot.map((t) => t['id']).toList(),
        },
        'status': 'processing',
      });
      try {
        Uint8List bytes;
        if (v['format'] == 'csv') {
          final rows = v['dataset'] == 'budget'
              ? <List<dynamic>>[
                  ['budget', 'currency', 'planned', 'actual', 'remaining'],
                  ...currentBudgets.map(
                    (b) => [
                      b['name'],
                      b['currency'],
                      b['amount'],
                      budgetActual(b),
                      integer(b['amount']) - budgetActual(b),
                    ],
                  ),
                ]
              : v['dataset'] == 'forecast'
              ? <List<dynamic>>[
                  [
                    'method',
                    'model_version',
                    'actual',
                    'scheduled',
                    'forecast',
                    'projected_variance',
                    'elapsed_days',
                    'total_days',
                  ],
                  [
                    model,
                    'v1',
                    forecast.actual,
                    forecast.scheduled,
                    forecast.estimate,
                    forecast.projectedVariance,
                    forecast.elapsed,
                    forecast.days,
                  ],
                ]
              : csvRows(snapshot);
          bytes = Uint8List.fromList(utf8.encode(encodeCsv(rows)));
        } else {
          final font = pw.Font.ttf(
            await rootBundle.load('assets/fonts/Inter.ttf'),
          );
          final doc = pw.Document(
            theme: pw.ThemeData.withFont(base: font, bold: font),
          );
          final reportIncome = sumType(
                'income',
                snapshot.where((t) => t['status'] == 'posted').toList(),
              ),
              reportExpense = sumType(
                'expense',
                snapshot.where((t) => t['status'] == 'posted').toList(),
              );
          doc.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              header: (c) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'FINANCE TRACKER',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.blueGrey700,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Laporan keuangan',
                    style: pw.TextStyle(fontSize: 22),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    '${period.label} · ${store.currency}',
                    style: const pw.TextStyle(fontSize: 10),
                  ),
                  pw.Divider(),
                ],
              ),
              footer: (c) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                  pw.Text(
                    '${c.pageNumber} / ${c.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ],
              ),
              build: (c) => [
                pw.Text(
                  'Pemasukan ${money(reportIncome, store.currency)}   Pengeluaran ${money(reportExpense, store.currency)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Arus kas bersih ${money(reportIncome - reportExpense, store.currency)} · ${snapshot.length} transaksi',
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  headers: [
                    'Tanggal',
                    'Tipe',
                    'Deskripsi',
                    'Akun',
                    'Nominal',
                    'Status',
                  ],
                  data: snapshot
                      .map(
                        (t) => [
                          DateFormat(
                            'yyyy-MM-dd',
                          ).format(localTime(t['effective_at'])),
                          t['type'],
                          t['description'],
                          store.name('accounts', t['account_id']),
                          money(t['amount'], t['currency']),
                          t['status'],
                        ],
                      )
                      .toList(),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerStyle: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey200,
                  ),
                  cellAlignment: pw.Alignment.centerLeft,
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.2),
                    1: const pw.FlexColumnWidth(.9),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(1.2),
                    4: const pw.FlexColumnWidth(1.5),
                    5: const pw.FlexColumnWidth(.8),
                  },
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Budget vs Actual',
                  style: const pw.TextStyle(fontSize: 14),
                ),
                pw.SizedBox(height: 8),
                pw.TableHelper.fromTextArray(
                  headers: ['Budget', 'Rencana', 'Actual', 'Sisa'],
                  data: currentBudgets
                      .map(
                        (b) => [
                          b['name'],
                          money(b['amount'], b['currency']),
                          money(budgetActual(b), b['currency']),
                          money(
                            integer(b['amount']) - budgetActual(b),
                            b['currency'],
                          ),
                        ],
                      )
                      .toList(),
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerStyle: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 20),
                pw.Text(
                  'Forecast ${model}_v1: ${money(forecast.estimate, store.currency)}',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Confidence rendah. ${forecast.elapsed}/${forecast.days} hari berjalan. Jadwal diketahui ${money(scheduled, store.currency)}. Metode dasar deterministik; bukan akurasi historis terkalibrasi. Transfer internal dikecualikan dari pemasukan dan pengeluaran.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          );
          bytes = await doc.save();
        }
        final path = '${store.uid}/exports/$jobId.${v['format']}';
        await store.client.storage
            .from('financegpt-private')
            .uploadBinary(
              path,
              bytes,
              fileOptions: FileOptions(
                contentType: v['format'] == 'csv'
                    ? 'text/csv'
                    : 'application/pdf',
              ),
            );
        await store.db
            .from('export_jobs')
            .update({
              'status': 'completed',
              'output_path': path,
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(hours: 24))
                  .toIso8601String(),
            })
            .eq('id', jobId);
        if (v['format'] == 'pdf') {
          await Printing.sharePdf(
            bytes: bytes,
            filename: 'finance-tracker-report.pdf',
          );
        } else {
          await FileSaver.instance.saveFile(
            name:
                'finance-tracker-${DateFormat('yyyyMMdd').format(DateTime.now())}',
            fileExtension: 'csv',
            bytes: bytes,
            mimeType: MimeType.csv,
          );
        }
      } catch (e) {
        await store.db
            .from('export_jobs')
            .update({'status': 'failed'})
            .eq('id', jobId);
        rethrow;
      } finally {
        await store.refresh();
      }
    }, success: 'File export selesai.');
  }

  Future<void> importFile() async {
    try {
      if (store.rows('accounts').isEmpty) {
        toast('Tambahkan akun tujuan import terlebih dahulu.');
        return;
      }
      final f = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'pdf'],
        withData: true,
      );
      if (f == null) return;
      final file = f.files.single;
      if (file.size > 10485760) throw Exception('Ukuran file maksimal 10 MB.');
      List<List<String>> parsed;
      String rawText = '';
      final pdf = file.extension?.toLowerCase() == 'pdf';
      if (pdf) {
        final extracted = await store.api(
          'imports/extract-pdf',
          method: 'POST',
          body: {'data': base64Encode(file.bytes!)},
        );
        rawText = extracted['text'];
        if (rawText.trim().length < 15) {
          throw Exception(
            'PDF ini tidak mempunyai teks yang dapat diekstrak. Scan membutuhkan OCR; gunakan CSV atau PDF digital.',
          );
        }
        final candidate = <List<String>>[];
        for (final line in rawText.split(RegExp(r'\r?\n'))) {
          final match = RegExp(
            r'(\d{4}-\d{2}-\d{2}|\d{2}/\d{2}/\d{4})\s+(.+?)\s+(-?[\d.,]+)\s*$',
          ).firstMatch(line.trim());
          if (match != null) {
            var d = match[1]!;
            if (d.contains('/')) {
              final p = d.split('/');
              d = '${p[2]}-${p[1]}-${p[0]}';
            }
            candidate.add([
              d,
              match[2]!,
              match[3]!.replaceAll('-', ''),
              'expense',
            ]);
          }
        }
        // An unfamiliar digital statement remains editable, with extracted text alongside preview.
        parsed = [
          ['date_time', 'description', 'amount', 'type'],
          ...candidate,
        ];
      } else {
        parsed = parseCsv(utf8.decode(file.bytes!, allowMalformed: true));
      }
      if (parsed.isEmpty) throw Exception('File kosong.');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (c) => ImportWizard(
          store: store,
          parsed: parsed,
          pdf: pdf,
          rawText: rawText,
        ),
      );
    } catch (e) {
      toast(readableError(e));
    }
  }
}

class ImportWizard extends StatefulWidget {
  final FinanceStore store;
  final List<List<String>> parsed;
  final bool pdf;
  final String rawText;
  const ImportWizard({
    super.key,
    required this.store,
    required this.parsed,
    required this.pdf,
    required this.rawText,
  });
  @override
  State<ImportWizard> createState() => _ImportWizardState();
}

class _ImportWizardState extends State<ImportWizard> {
  late final headers = widget.parsed.first;
  late final mapping = <String, int>{
    for (final key in csvHeaders) key: headers.indexOf(key),
  };
  late String account = widget.store.rows('accounts').first['id'];
  String? category;
  String disposition = 'skip';
  bool reviewed = false, busy = false;
  String? error;
  int step = 0;
  final jobId = uuid.v4();
  List<FinanceRow> preview = [];
  String cell(List<String> row, String key) {
    final i = mapping[key] ?? -1;
    return i >= 0 && i < row.length ? row[i].trim() : '';
  }

  void buildPreview() {
    preview = [];
    for (var i = 1; i < widget.parsed.length; i++) {
      final row = widget.parsed[i];
      try {
        final selectedAccount =
            widget.store
                .rows('accounts')
                .where((a) => a['name'] == cell(row, 'account'))
                .firstOrNull ??
            widget.store.rows('accounts').firstWhere((a) => a['id'] == account);
        final selectedCategory = widget.store
            .rows('categories')
            .where((c) => c['name'] == cell(row, 'category'))
            .firstOrNull;
        final date = DateTime.tryParse(cell(row, 'date_time'));
        if (date == null) throw Exception('Tanggal harus ISO 8601.');
        final amount = int.tryParse(cell(row, 'amount'));
        if (amount == null || amount <= 0) {
          throw Exception('Nominal harus integer minor units > 0.');
        }
        final type = cell(row, 'type').isEmpty ? 'expense' : cell(row, 'type');
        if (!['income', 'expense', 'transfer', 'adjustment'].contains(type)) {
          throw Exception('Tipe transaksi tidak valid.');
        }
        final duplicate = widget.store
            .rows('transactions')
            .where(
              (t) =>
                  t['id'] == cell(row, 'transaction_id') ||
                  (cell(row, 'source_ref').isNotEmpty &&
                      t['source_ref'] == cell(row, 'source_ref')) ||
                  (t['account_id'] == selectedAccount['id'] &&
                      integer(t['amount']) == amount &&
                      DateTime.parse(t['effective_at']).toUtc() ==
                          date.toUtc() &&
                      (t['description'] ?? '')
                              .toString()
                              .trim()
                              .toLowerCase() ==
                          cell(row, 'description').toLowerCase()),
            )
            .firstOrNull;
        final dest = widget.store
            .rows('accounts')
            .where((a) => a['name'] == cell(row, 'destination_account'))
            .firstOrNull;
        final p = <String, dynamic>{
          'type': type,
          'amount': amount,
          'currency': cell(row, 'currency').isEmpty
              ? selectedAccount['currency']
              : cell(row, 'currency'),
          'account_id': selectedAccount['id'],
          'destination_account_id': dest?['id'],
          'category_id': selectedCategory?['id'] ?? category,
          'effective_at': date.toUtc().toIso8601String(),
          'description': cell(row, 'description'),
          'merchant': cell(row, 'merchant'),
          'tags': cell(
            row,
            'tags',
          ).split('|').where((s) => s.isNotEmpty).toList(),
          'status': cell(row, 'status').isEmpty
              ? 'posted'
              : cell(row, 'status'),
          'source_ref': cell(row, 'source_ref').isEmpty
              ? null
              : cell(row, 'source_ref'),
        };
        String? validation;
        if (type != 'transfer' &&
            type != 'adjustment' &&
            p['category_id'] == null) {
          validation = 'Pilih kategori.';
        }
        if (type == 'transfer' && dest == null) {
          validation = 'Akun tujuan tidak ditemukan.';
        }
        if (p['currency'] != selectedAccount['currency']) {
          validation = 'Mata uang akun berbeda.';
        }
        preview.add({
          'line': i + 1,
          'payload': p,
          'duplicate': duplicate,
          'error': validation,
          'skip': false,
        });
      } catch (e) {
        preview.add({
          'line': i + 1,
          'error': readableError(e),
          'raw': row.join(' | '),
          'skip': false,
        });
      }
    }
  }

  Future<void> editRow(FinanceRow row) async {
    final p = FinanceRow.from(row['payload'] ?? {});
    final v = await showDialog<FinanceRow>(
      context: context,
      builder: (c) => RecordForm(
        title: 'Tinjau baris ${row['line']}',
        fields: [
          Field(
            'effective_at',
            'Tanggal ISO 8601',
            value: p['effective_at'] ?? DateTime.now().toIso8601String(),
          ),
          Field(
            'description',
            'Deskripsi',
            value: p['description'] ?? '',
            required: false,
          ),
          Field(
            'amount',
            'Nominal minor units',
            number: true,
            value: p['amount']?.toString() ?? '',
          ),
          Field(
            'type',
            'Tipe',
            value: p['type'] ?? 'expense',
            options: {
              'expense': 'Expense',
              'income': 'Income',
              'transfer': 'Transfer',
            },
          ),
          Field(
            'category_id',
            'Kategori',
            value: p['category_id'],
            options: {
              for (final c in widget.store.rows('categories'))
                c['id']: c['name'],
            },
          ),
        ],
      ),
    );
    if (v == null) return;
    try {
      DateTime.parse(v['effective_at']);
      setState(() {
        row['payload'] = {
          ...p,
          ...v,
          'amount': int.parse(v['amount']),
          'currency': p['currency'] ?? 'IDR',
          'account_id': p['account_id'] ?? account,
          'status': p['status'] ?? 'posted',
        };
        row['error'] = null;
      });
    } catch (_) {
      setState(() => error = 'Tanggal atau nominal tidak valid.');
    }
  }

  Future<void> commit() async {
    if (!reviewed) return;
    final errors = preview.where(
      (r) => r['error'] != null && r['skip'] != true,
    );
    if (errors.isNotEmpty) {
      setState(
        () => error = 'Perbaiki atau lewati ${errors.length} baris bermasalah.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payloads = <FinanceRow>[];
      for (final r in preview) {
        if (r['skip'] == true) continue;
        final p = FinanceRow.from(r['payload']);
        if (r['duplicate'] != null) {
          if (disposition == 'skip') continue;
          if (disposition == 'replace') {
            p['id'] = r['duplicate']['id'];
            p['expected_version'] = r['duplicate']['row_version'];
          }
        }
        payloads.add(p);
      }
      await widget.store.db.from('import_jobs').upsert({
        'id': jobId,
        'user_id': widget.store.uid,
        'format': widget.pdf ? 'pdf' : 'csv',
        'status': 'processing',
        'mapping_json': mapping,
      });
      // Retry each completed chunk with the same key. Failed chunks never partially commit.
      for (var i = 0; i < payloads.length; i += 250) {
        await widget.store.db.rpc(
          'confirm_import',
          params: {
            'payloads': payloads.sublist(i, math.min(i + 250, payloads.length)),
            'idempotency_key': 'import:$jobId:$i',
          },
        );
      }
      await widget.store.db
          .from('import_jobs')
          .update({
            'status': 'completed',
            'totals_json': {
              'saved': payloads.length,
              'skipped': preview.length - payloads.length,
            },
          })
          .eq('id', jobId);
      await widget.store.refresh();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${payloads.length} transaksi berhasil diimpor.'),
          ),
        );
      }
    } catch (e) {
      await widget.store.db
          .from('import_jobs')
          .update({'status': 'failed'})
          .eq('id', jobId);
      if (mounted) {
        setState(() {
          error = readableError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 850),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    step == 0 ? '1. Petakan kolom' : '2. Tinjau & konfirmasi',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Tutup',
                  onPressed: busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (step == 0) ...[
                    const Text(
                      'Nominal menggunakan integer minor units: IDR 35.000 = 35000, USD 35,00 = 3500.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: account,
                      decoration: const InputDecoration(
                        labelText: 'Akun default',
                      ),
                      items: widget.store
                          .rows('accounts')
                          .map(
                            (a) => DropdownMenuItem<String>(
                              value: a['id'],
                              child: Text(a['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => account = v!),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: const InputDecoration(
                        labelText: 'Kategori default',
                      ),
                      items: widget.store
                          .rows('categories')
                          .map(
                            (a) => DropdownMenuItem<String>(
                              value: a['id'],
                              child: Text(a['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => category = v),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children:
                          [
                                'date_time',
                                'amount',
                                'type',
                                'description',
                                'account',
                                'destination_account',
                                'category',
                                'currency',
                                'merchant',
                                'tags',
                                'status',
                                'source_ref',
                                'transaction_id',
                              ]
                              .map(
                                (key) => SizedBox(
                                  width: 250,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: mapping[key] ?? -1,
                                    decoration: InputDecoration(labelText: key),
                                    items: [
                                      const DropdownMenuItem(
                                        value: -1,
                                        child: Text('Tidak dipetakan'),
                                      ),
                                      ...List.generate(
                                        headers.length,
                                        (i) => DropdownMenuItem(
                                          value: i,
                                          child: Text(
                                            headers[i],
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (v) => mapping[key] = v!,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                    if (widget.pdf) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Teks hasil ekstraksi · periksa struktur dan nominal',
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        widget.rawText.length > 12000
                            ? widget.rawText.substring(0, 12000)
                            : widget.rawText,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ] else ...[
                    Text(
                      '${preview.length} baris · ${preview.where((r) => r['duplicate'] != null).length} duplikat · ${preview.where((r) => r['error'] != null).length} perlu perbaikan',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: disposition,
                      decoration: const InputDecoration(
                        labelText: 'Penanganan duplikat',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'skip',
                          child: Text('Lewati duplikat'),
                        ),
                        DropdownMenuItem(
                          value: 'replace',
                          child: Text(
                            'Ganti transaksi lama (dengan jurnal koreksi)',
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'create',
                          child: Text('Tetap buat transaksi baru'),
                        ),
                      ],
                      onChanged: (v) => setState(() => disposition = v!),
                    ),
                    const SizedBox(height: 16),
                    for (final row in preview)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Checkbox(
                          value: row['skip'] != true,
                          onChanged: (v) =>
                              setState(() => row['skip'] = v != true),
                        ),
                        title: Text(
                          'Baris ${row['line']}: ${row['payload']?['description'] ?? row['raw'] ?? ''}',
                          maxLines: 2,
                        ),
                        subtitle: Text(
                          row['error'] ??
                              '${row['payload']?['effective_at']} · ${row['payload']?['amount']} · ${row['duplicate'] != null ? 'DUPLIKAT' : 'Valid'}',
                          style: TextStyle(
                            color: row['error'] != null
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Edit hasil ekstraksi',
                          onPressed: () => editRow(row),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                        ),
                      ),
                    if (preview.isEmpty) ...[
                      const Text(
                        'Format PDF belum dikenali. Tambahkan baris yang telah Anda periksa dari teks ekstraksi.',
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final row = <String, dynamic>{
                            'line': preview.length + 1,
                            'error': 'Perlu ditinjau',
                          };
                          await editRow(row);
                          if (row['payload'] != null) {
                            setState(() => preview.add(row));
                          }
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah baris'),
                      ),
                    ],
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: reviewed,
                      onChanged: (v) => setState(() => reviewed = v!),
                      title: Text(
                        widget.pdf
                            ? 'Saya sudah memeriksa teks PDF, kategori, tanggal, dan semua nominal.'
                            : 'Saya sudah memeriksa mapping, nominal, serta duplikasi.',
                      ),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => step == 0
                            ? Navigator.pop(context)
                            : setState(() => step = 0),
                  child: Text(step == 0 ? 'Batal' : 'Kembali'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: busy
                      ? null
                      : step == 0
                      ? () {
                          buildPreview();
                          setState(() => step = 1);
                        }
                      : reviewed && preview.isNotEmpty
                      ? commit
                      : null,
                  child: Text(
                    busy
                        ? 'Mengimpor…'
                        : step == 0
                        ? 'Lihat preview'
                        : 'Konfirmasi import',
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

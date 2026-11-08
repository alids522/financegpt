part of 'shell.dart';

class Field {
  final String key, label;
  final String? value;
  final Map<String, String>? options;
  final bool required, number, secret, date;
  const Field(
    this.key,
    this.label, {
    this.value,
    this.options,
    this.required = true,
    this.number = false,
    this.secret = false,
    this.date = false,
  });
}

class RecordForm extends StatefulWidget {
  final String title, saveLabel;
  final List<Field> fields;
  const RecordForm({
    super.key,
    required this.title,
    required this.fields,
    this.saveLabel = 'Simpan',
  });
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final form = GlobalKey<FormState>();
  late final controls = {
    for (final f in widget.fields)
      f.key: TextEditingController(
        text: f.value ?? (f.options?.keys.firstOrNull ?? ''),
      ),
  };
  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 500,
      child: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: widget.fields
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            initialValue:
                                f.options!.containsKey(controls[f.key]!.text)
                                ? controls[f.key]!.text
                                : f.options!.keys.first,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: f.options!.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => controls[f.key]!.text = v!,
                            validator: (v) => f.required && (v ?? '').isEmpty
                                ? 'Pilih ${f.label.toLowerCase()}.'
                                : null,
                          )
                        : TextFormField(
                            controller: controls[f.key],
                            obscureText: f.secret,
                            readOnly: f.date,
                            keyboardType: f.number
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText: f.label,
                              suffixIcon: f.date
                                  ? const Icon(Icons.calendar_today_outlined)
                                  : null,
                            ),
                            onTap: f.date
                                ? () async {
                                    final d = await showDatePicker(
                                      context: context,
                                      firstDate: DateTime(2000),
                                      lastDate: DateTime(2100),
                                      initialDate:
                                          DateTime.tryParse(
                                            controls[f.key]!.text,
                                          ) ??
                                          DateTime.now(),
                                    );
                                    if (d != null) {
                                      controls[f.key]!.text = DateFormat(
                                        'yyyy-MM-dd',
                                      ).format(d);
                                    }
                                  }
                                : null,
                            validator: (v) {
                              if (f.required && (v ?? '').trim().isEmpty) {
                                return 'Field ini wajib diisi.';
                              }
                              if (f.number && v!.isNotEmpty) {
                                try {
                                  parseMoney(v);
                                } catch (_) {
                                  return 'Nominal tidak valid.';
                                }
                              }
                              return null;
                            },
                          ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, {
              for (final e in controls.entries) e.key: e.value.text.trim(),
            });
          }
        },
        child: Text(widget.saveLabel),
      ),
    ],
  );
}

extension _FinanceEditors on _FinanceShellState {
  Future<FinanceRow?> recordDialog(
    String title,
    List<Field> fields, {
    String saveLabel = 'Simpan',
  }) => showDialog<FinanceRow>(
    context: context,
    barrierDismissible: false,
    builder: (c) =>
        RecordForm(title: title, fields: fields, saveLabel: saveLabel),
  );
  Future<void> transactionEditor({
    FinanceRow? existing,
    FinanceRow? prefill,
  }) async {
    if (store.rows('accounts').where((a) => a['status'] == 'active').isEmpty) {
      toast('Tambahkan akun atau dompet terlebih dahulu.');
      await accountEditor();
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) =>
          TransactionEditor(store: store, existing: existing, prefill: prefill),
    );
  }

  Future<void> transactionDetail(FinanceRow t) async {
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          t['description']?.toString().isNotEmpty == true
              ? t['description']
              : 'Detail transaksi',
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  money(t['amount'], t['currency']),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '${t['type']} · ${t['status']}\n${store.name('accounts', t['account_id'])}${t['destination_account_id'] != null ? ' → ${store.name('accounts', t['destination_account_id'])}' : ''}\n${store.name('categories', t['category_id'])}\n${dateLabel(t['effective_at'])}\nMerchant: ${t['merchant'] ?? '—'}\nTags: ${(t['tags'] as List? ?? []).join(', ')}\nCatatan: ${t['notes'] ?? ''}\nSumber: ${t['source']} · Versi ${t['row_version']}',
                  style: const TextStyle(height: 1.8),
                ),
                if ((t['custom_fields'] as Map? ?? {}).isNotEmpty)
                  Text('Custom fields: ${jsonEncode(t['custom_fields'])}'),
                for (final s
                    in store
                        .rows('transaction_splits')
                        .where((s) => s['transaction_id'] == t['id']))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(store.name('categories', s['category_id'])),
                    trailing: Text(money(s['amount'], t['currency'])),
                  ),
                if (t['attachment_path'] != null)
                  TextButton.icon(
                    onPressed: () => showAttachment(t),
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Lihat lampiran'),
                  ),
                const Divider(),
                const Text(
                  'Riwayat aktivitas',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ...store
                    .rows('agent_audit_logs')
                    .where((a) => a['safe_diff_json']?['id'] == t['id'])
                    .map(
                      (a) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(a['event_type']),
                        subtitle: Text(
                          '${a['actor']} · ${dateLabel(a['occurred_at'])}',
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Tutup'),
          ),
          PopupMenuButton<String>(
            tooltip: 'Tindakan lainnya',
            itemBuilder: (c) => [
              const PopupMenuItem(value: 'duplicate', child: Text('Duplikat')),
              if (t['type'] != 'transfer' && t['status'] == 'posted')
                const PopupMenuItem(
                  value: 'refund',
                  child: Text('Refund / reversal'),
                ),
              PopupMenuItem(
                value: 'void',
                child: Text(
                  t['status'] == 'voided' ? 'Pulihkan' : 'Void transaksi',
                ),
              ),
              const PopupMenuItem(
                value: 'template',
                child: Text('Simpan sebagai template'),
              ),
            ],
            onSelected: (value) async {
              Navigator.pop(c);
              if (value == 'duplicate') {
                transactionEditor(
                  prefill: {...t}
                    ..remove('id')
                    ..remove('reversal_of'),
                );
              } else if (value == 'refund') {
                transactionEditor(
                  prefill: {
                    ...t,
                    'reversal_of': t['id'],
                    'description': 'Refund: ${t['description']}',
                    'effective_at': DateTime.now().toUtc().toIso8601String(),
                  }..remove('id'),
                );
              } else if (value == 'template') {
                final v = await recordDialog('Nama template', [
                  Field('name', 'Nama preset'),
                ]);
                if (v != null) {
                  run(
                    () => store.save('transaction_templates', {
                      'name': v['name'],
                      'payload_json': {...t}
                        ..remove('id')
                        ..remove('user_id'),
                    }),
                  );
                }
              } else if (await confirm(
                t['status'] == 'voided'
                    ? 'Pulihkan transaksi?'
                    : 'Void transaksi?',
                'Saldo dan actual akan dihitung ulang melalui jurnal pembalik.',
              )) {
                run(
                  () => store.saveTransaction({
                    ...t,
                    'expected_version': t['row_version'],
                    'status': t['status'] == 'voided' ? 'posted' : 'voided',
                  }, uuid.v4()),
                );
              }
            },
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              transactionEditor(existing: t);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Future<void> showAttachment(FinanceRow t) async {
    try {
      if (t['attachment_path'].toString().endsWith('.pdf')) {
        final bytes = await store.client.storage
            .from('financegpt-private')
            .download(t['attachment_path']);
        await Printing.layoutPdf(onLayout: (_) async => bytes);
        return;
      }
      final url = await store.client.storage
          .from('financegpt-private')
          .createSignedUrl(t['attachment_path'], 120);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (c) => Dialog(
          child: SizedBox(
            width: 800,
            height: 650,
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close),
                  ),
                ),
                Expanded(child: InteractiveViewer(child: Image.network(url))),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      toast(readableError(e));
    }
  }

  Future<void> accountEditor({FinanceRow? existing}) async {
    final v = await recordDialog(
      existing == null ? 'Tambah akun' : 'Edit akun',
      [
        Field('name', 'Nama akun', value: existing?['name']),
        if (existing == null) ...[
          const Field(
            'type',
            'Tipe akun',
            options: {
              'cash': 'Cash',
              'bank': 'Bank',
              'ewallet': 'E-wallet',
              'other': 'Other',
            },
          ),
          const Field(
            'currency',
            'Mata uang',
            options: {'IDR': 'IDR', 'USD': 'USD', 'EUR': 'EUR', 'SGD': 'SGD'},
          ),
          const Field(
            'opening_balance',
            'Saldo awal',
            value: '0',
            number: true,
          ),
        ],
        Field(
          'allow_negative',
          'Saldo negatif',
          value: existing?['allow_negative'] == false ? 'false' : 'true',
          options: {
            'true': 'Izinkan dengan peringatan',
            'false': 'Larang saldo negatif',
          },
        ),
      ],
    );
    if (v != null) {
      run(() async {
        if (existing == null) {
          await store.createAccount(
            {
              ...v,
              'opening_balance': parseMoney(
                v['opening_balance'],
                v['currency'],
              ),
            }..['allow_negative'] = v['allow_negative'] == 'true',
            uuid.v4(),
          );
        } else {
          await store.save('accounts', {
            'name': v['name'],
            'allow_negative': v['allow_negative'] == 'true',
          }, id: existing['id']);
        }
      });
    }
  }

  Future<void> budgetEditor({FinanceRow? existing}) async {
    final v = await recordDialog(
      existing == null ? 'Buat budget' : 'Edit budget',
      [
        Field('name', 'Nama budget', value: existing?['name']),
        Field(
          'category_id',
          'Kategori',
          value: existing?['category_id'] ?? '',
          options: {
            '': 'Global · semua pengeluaran',
            for (final c
                in store
                    .rows('categories')
                    .where(
                      (c) => c['type'] == 'expense' && c['archived'] != true,
                    ))
              c['id']: c['name'],
          },
          required: false,
        ),
        Field(
          'amount',
          'Nominal budget (${store.currency})',
          value: existing?['amount']?.toString(),
          number: true,
        ),
        Field(
          'period_start',
          'Mulai',
          value:
              existing?['period_start'] ??
              DateFormat('yyyy-MM-dd').format(period.start),
          date: true,
        ),
        Field(
          'period_end',
          'Selesai',
          value:
              existing?['period_end'] ??
              DateFormat(
                'yyyy-MM-dd',
              ).format(period.end.subtract(const Duration(days: 1))),
          date: true,
        ),
        Field(
          'cadence',
          'Periode',
          value: existing?['cadence'] ?? 'monthly',
          options: {
            'monthly': 'Bulanan',
            'weekly': 'Mingguan',
            'custom': 'Custom pay-cycle',
          },
        ),
        Field(
          'rollover',
          'Rollover',
          value: existing?['rollover'] ?? 'none',
          options: {
            'none': 'Tidak rollover',
            'remaining': 'Bawa sisa ke periode berikutnya',
          },
        ),
      ],
    );
    if (v != null) {
      run(
        () => store.save('budgets', {
          ...v,
          'category_id': v['category_id'] == '' ? null : v['category_id'],
          'amount': parseMoney(v['amount'], store.currency),
          'currency': store.currency,
          'row_version': integer(existing?['row_version'] ?? 0) + 1,
        }, id: existing?['id']),
      );
    }
  }

  Future<void> categoryEditor({FinanceRow? existing}) async {
    final v = await recordDialog('Kategori', [
      Field('name', 'Nama', value: existing?['name']),
      Field(
        'type',
        'Tipe',
        value: existing?['type'] ?? 'expense',
        options: {'expense': 'Pengeluaran', 'income': 'Pemasukan'},
      ),
      Field(
        'parent_id',
        'Kategori induk',
        value: existing?['parent_id'] ?? '',
        required: false,
        options: {
          '': 'Tanpa induk',
          for (final c
              in store
                  .rows('categories')
                  .where(
                    (c) => c['parent_id'] == null && c['id'] != existing?['id'],
                  ))
            c['id']: c['name'],
        },
      ),
      Field(
        'sort_order',
        'Urutan',
        value: '${existing?['sort_order'] ?? 0}',
        number: true,
      ),
    ]);
    if (v != null) {
      run(
        () => store.save('categories', {
          ...v,
          'parent_id': v['parent_id'] == '' ? null : v['parent_id'],
          'sort_order': int.parse(v['sort_order']),
        }, id: existing?['id']),
      );
    }
  }

  Future<void> goalEditor() async {
    final v = await recordDialog('Tujuan tabungan', [
      const Field('name', 'Nama tujuan'),
      const Field('target_amount', 'Target nominal', number: true),
      Field(
        'target_date',
        'Target tanggal',
        value: DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().add(const Duration(days: 365))),
        date: true,
      ),
      Field(
        'account_id',
        'Akun alokasi',
        required: false,
        options: {
          '': 'Tanpa akun khusus',
          for (final a in store.rows('accounts')) a['id']: a['name'],
        },
      ),
    ]);
    if (v != null) {
      run(
        () => store.save('savings_goals', {
          ...v,
          'target_amount': parseMoney(v['target_amount'], store.currency),
          'currency': store.currency,
          'account_id': v['account_id'] == '' ? null : v['account_id'],
        }),
      );
    }
  }

  Future<void> debtEditor() async {
    final v = await recordDialog('Utang / piutang', [
      const Field('name', 'Nama catatan'),
      const Field('counterparty', 'Pihak terkait'),
      const Field(
        'kind',
        'Tipe',
        options: {'debt': 'Utang', 'receivable': 'Piutang'},
      ),
      const Field('principal', 'Pokok', number: true),
      const Field('rate', 'Bunga (%)', value: '0', number: true),
      Field(
        'due',
        'Jatuh tempo',
        value: DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().add(const Duration(days: 30))),
        date: true,
      ),
    ]);
    if (v != null) {
      run(
        () => store.save('debts', {
          ...v,
          'principal': parseMoney(v['principal'], store.currency),
          'rate': num.parse(v['rate'].replaceAll(',', '.')),
          'currency': store.currency,
        }),
      );
    }
  }

  Future<void> debtPaymentEditor(FinanceRow d) async {
    final v = await recordDialog('Catat pembayaran', [
      Field(
        'principal_paid',
        'Pokok dibayar',
        number: true,
        value: outstanding(d).toString(),
      ),
      const Field('interest_paid', 'Bunga dibayar', number: true, value: '0'),
      Field(
        'transaction_id',
        'Hubungkan transaksi',
        required: false,
        options: {
          '': 'Catatan saja · belum ada posting kas',
          for (final t
              in store
                  .rows('transactions')
                  .where((t) => t['currency'] == d['currency']))
            t['id']:
                '${t['description']} · ${money(t['amount'], t['currency'])}',
        },
      ),
    ]);
    if (v == null) return;
    if (parseMoney(v['principal_paid'], d['currency']) > outstanding(d)) {
      toast('Pembayaran pokok melebihi sisa utang.');
      return;
    }
    run(
      () => store.save('debt_payments', {
        ...v,
        'debt_id': d['id'],
        'principal_paid': parseMoney(v['principal_paid'], d['currency']),
        'interest_paid': parseMoney(v['interest_paid'], d['currency']),
        'transaction_id': v['transaction_id'] == ''
            ? null
            : v['transaction_id'],
      }),
    );
  }

  Future<FinanceRow?> presetFields(String title) async {
    if (store.rows('accounts').isEmpty) {
      toast('Tambahkan akun terlebih dahulu.');
      return null;
    }
    final v = await recordDialog(title, [
      const Field('name', 'Nama preset'),
      const Field(
        'type',
        'Tipe',
        options: {'expense': 'Pengeluaran', 'income': 'Pemasukan'},
      ),
      const Field('amount', 'Nominal', number: true),
      Field(
        'account_id',
        'Akun',
        options: {
          for (final a
              in store.rows('accounts').where((a) => a['status'] == 'active'))
            a['id']: a['name'],
        },
      ),
      Field(
        'category_id',
        'Kategori',
        options: {
          for (final c
              in store.rows('categories').where((c) => c['archived'] != true))
            c['id']: '${c['name']} (${c['type']})',
        },
      ),
      const Field('description', 'Deskripsi', required: false),
    ]);
    if (v == null) return null;
    final account = store
        .rows('accounts')
        .firstWhere((a) => a['id'] == v['account_id']);
    return {
      ...v,
      'currency': account['currency'],
      'amount': parseMoney(v['amount'], account['currency']),
      'effective_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'posted',
    };
  }

  Future<void> templateEditor() async {
    final p = await presetFields('Template transaksi');
    if (p != null) {
      run(
        () => store.save('transaction_templates', {
          'name': p['name'],
          'payload_json': {...p}..remove('name'),
          'favourite': true,
        }),
      );
    }
  }

  Future<void> recurringEditor() async {
    final p = await presetFields('Transaksi berulang');
    if (p == null) return;
    final v = await recordDialog('Jadwal berulang', [
      const Field(
        'cadence',
        'Frekuensi',
        options: {
          'monthly': 'Bulanan',
          'weekly': 'Mingguan',
          'daily': 'Harian',
          'yearly': 'Tahunan',
        },
      ),
      Field(
        'next_at',
        'Mulai tanggal',
        value: DateFormat(
          'yyyy-MM-dd',
        ).format(DateTime.now().add(const Duration(days: 1))),
        date: true,
      ),
      const Field(
        'mode',
        'Mode',
        options: {
          'pending': 'Pending · tinjau nominal',
          'draft': 'Draft',
          'auto-post': 'Auto-post',
        },
      ),
    ]);
    if (v != null) {
      run(
        () => store.save('recurring_rules', {
          ...v,
          'name': p['name'],
          'next_at': DateTime.parse(v['next_at']).toUtc().toIso8601String(),
          'payload_json': {
            ...p,
            'tags': ['scheduled'],
          }..remove('name'),
        }),
      );
    }
  }

  Future<void> customFieldEditor() async {
    final v = await recordDialog('Custom field', [
      const Field('field_key', 'Nama field'),
      const Field(
        'field_type',
        'Tipe',
        options: {
          'text': 'Teks',
          'number': 'Angka',
          'date': 'Tanggal',
          'boolean': 'Ya / Tidak',
          'enum': 'Pilihan',
        },
      ),
      const Field(
        'options',
        'Pilihan dipisah koma (untuk enum)',
        required: false,
      ),
      const Field(
        'required',
        'Wajib diisi',
        options: {'false': 'Tidak', 'true': 'Ya'},
      ),
    ]);
    if (v != null) {
      run(
        () => store.save('custom_field_definitions', {
          'field_key': v['field_key'],
          'field_type': v['field_type'],
          'options_json': {
            'values': v['options']
                .toString()
                .split(',')
                .map((x) => x.trim())
                .where((x) => x.isNotEmpty)
                .toList(),
          },
          'required': v['required'] == 'true',
        }),
      );
    }
  }
}

class TransactionEditor extends StatefulWidget {
  final FinanceStore store;
  final FinanceRow? existing, prefill;
  const TransactionEditor({
    super.key,
    required this.store,
    this.existing,
    this.prefill,
  });
  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  final form = GlobalKey<FormState>();
  late final FinanceRow initial = {...?widget.prefill, ...?widget.existing};
  late String type = initial['type'] ?? 'expense',
      status = initial['status'] ?? 'posted',
      account =
          initial['account_id'] ??
          widget.store
              .rows('accounts')
              .where((a) => a['status'] == 'active')
              .first['id'];
  String? category, destination, attachment;
  late DateTime date =
      DateTime.tryParse(initial['effective_at'] ?? '')?.toLocal() ??
      DateTime.now();
  late final amountControl = TextEditingController(
    text: initial['amount'] == null
        ? ''
        : displayMinor(
            integer(initial['amount']),
            initial['currency'] ?? 'IDR',
          ),
  );
  late final description = TextEditingController(
        text: initial['description'] ?? '',
      ),
      merchant = TextEditingController(text: initial['merchant'] ?? ''),
      notes = TextEditingController(text: initial['notes'] ?? ''),
      tags = TextEditingController(
        text: (initial['tags'] as List? ?? []).join(', '),
      );
  final Map<String, TextEditingController> custom = {};
  final List<FinanceRow> splits = [];
  bool busy = false, dirty = false;
  String? error;
  String idem = uuid.v4(), lastPayload = '';
  String get currency => widget.store
      .rows('accounts')
      .firstWhere((a) => a['id'] == account)['currency'];
  String displayMinor(int n, String c) =>
      c == 'IDR' ? '$n' : '${n ~/ 100},${(n % 100).toString().padLeft(2, '0')}';
  @override
  void initState() {
    super.initState();
    category = initial['category_id'];
    destination = initial['destination_account_id'];
    attachment = initial['attachment_path'];
    for (final f in widget.store.rows('custom_field_definitions')) {
      custom[f['field_key']] = TextEditingController(
        text: initial['custom_fields']?[f['field_key']]?.toString() ?? '',
      );
    }
    splits.addAll(
      widget.store
          .rows('transaction_splits')
          .where((s) => s['transaction_id'] == widget.existing?['id'])
          .map((s) => {'category_id': s['category_id'], 'amount': s['amount']}),
    );
    for (final c in [
      amountControl,
      description,
      merchant,
      notes,
      tags,
      ...custom.values,
    ]) {
      c.addListener(() => dirty = true);
    }
  }

  @override
  void dispose() {
    for (final c in [
      amountControl,
      description,
      merchant,
      notes,
      tags,
      ...custom.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> close() async {
    if (busy) return;
    if (!dirty ||
        await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Buang perubahan?'),
                content: const Text('Perubahan transaksi belum disimpan.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Lanjut edit'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Buang perubahan'),
                  ),
                ],
              ),
            ) ==
            true) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> save({bool another = false}) async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final customValues = <String, dynamic>{};
      for (final f in widget.store.rows('custom_field_definitions')) {
        final value = custom[f['field_key']]!.text;
        customValues[f['field_key']] = switch (f['field_type']) {
          'number' => num.tryParse(value),
          'boolean' => value == 'true',
          _ => value,
        };
      }
      final payload = <String, dynamic>{
        'type': type,
        'status': status,
        'account_id': account,
        'destination_account_id': type == 'transfer' ? destination : null,
        'category_id': type == 'transfer' || type == 'adjustment'
            ? null
            : category,
        'amount': parseMoney(amountControl.text, currency),
        'currency': currency,
        'effective_at': date.toUtc().toIso8601String(),
        'merchant': merchant.text,
        'description': description.text,
        'notes': notes.text,
        'tags': tags.text
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList(),
        'custom_fields': customValues,
        'attachment_path': attachment,
        'splits': type == 'transfer' ? [] : splits,
        if (initial['reversal_of'] != null)
          'reversal_of': initial['reversal_of'],
        if (widget.existing != null) ...{
          'id': widget.existing!['id'],
          'expected_version': widget.existing!['row_version'],
        },
      };
      final serialized = jsonEncode(payload);
      if (lastPayload.isNotEmpty && lastPayload != serialized) idem = uuid.v4();
      lastPayload = serialized;
      await widget.store.saveTransaction(payload, idem);
      if (!mounted) return;
      if (another && widget.existing == null) {
        amountControl.clear();
        description.clear();
        notes.clear();
        splits.clear();
        idem = uuid.v4();
        lastPayload = '';
        dirty = false;
        setState(() => busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tersimpan. Siap untuk transaksi berikutnya.'),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          busy = false;
        });
      }
    }
  }

  Future<void> pickAttachment() async {
    try {
      final f = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (f == null) return;
      final file = f.files.single;
      if (file.size > 10485760) throw Exception('Maksimum lampiran 10 MB.');
      setState(() => busy = true);
      final path =
          '${widget.store.uid}/attachments/${uuid.v4()}.${file.extension}';
      await widget.store.client.storage
          .from('financegpt-private')
          .uploadBinary(
            path,
            file.bytes!,
            fileOptions: FileOptions(
              contentType: file.extension == 'pdf'
                  ? 'application/pdf'
                  : file.extension == 'png'
                  ? 'image/png'
                  : 'image/jpeg',
            ),
          );
      if (mounted) {
        setState(() {
          attachment = path;
          dirty = true;
          busy = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          busy = false;
        });
      }
    }
  }

  Widget field(Widget child) =>
      Padding(padding: const EdgeInsets.only(bottom: 16), child: child);
  @override
  Widget build(BuildContext context) {
    final accounts = widget.store
        .rows('accounts')
        .where((a) => a['status'] == 'active' || a['id'] == account)
        .toList();
    final cats = widget.store
        .rows('categories')
        .where((c) => c['type'] == type && c['archived'] != true)
        .toList();
    if (!cats.any((c) => c['id'] == category)) category = null;
    return PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) close();
      },
      child: Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? 'Tambah transaksi'
                            : 'Edit transaksi',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tutup',
                      onPressed: busy ? null : close,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        field(
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(
                                value: 'expense',
                                label: Text('Expense'),
                              ),
                              ButtonSegment(
                                value: 'income',
                                label: Text('Income'),
                              ),
                              ButtonSegment(
                                value: 'transfer',
                                label: Text('Transfer'),
                              ),
                            ],
                            selected: {type == 'adjustment' ? 'expense' : type},
                            onSelectionChanged: busy
                                ? null
                                : (s) => setState(() {
                                    type = s.first;
                                    category = null;
                                    dirty = true;
                                  }),
                          ),
                        ),
                        field(
                          TextFormField(
                            controller: amountControl,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                            decoration: InputDecoration(
                              labelText: 'Nominal',
                              prefixText: '$currency ',
                              helperText: currency == 'IDR'
                                  ? 'Rupiah penuh tanpa desimal.'
                                  : 'Gunakan koma untuk desimal.',
                            ),
                            validator: (v) {
                              try {
                                return parseMoney(v ?? '', currency) > 0
                                    ? null
                                    : 'Nominal harus lebih dari 0.';
                              } catch (e) {
                                return readableError(e);
                              }
                            },
                          ),
                        ),
                        field(
                          DropdownButtonFormField<String>(
                            initialValue: account,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: type == 'transfer'
                                  ? 'Dari akun'
                                  : 'Akun',
                            ),
                            items: accounts
                                .map(
                                  (a) => DropdownMenuItem<String>(
                                    value: a['id'],
                                    child: Text(
                                      '${a['name']} · ${a['currency']}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() {
                              account = v!;
                              dirty = true;
                            }),
                          ),
                        ),
                        if (type == 'transfer')
                          field(
                            DropdownButtonFormField<String>(
                              initialValue:
                                  accounts.any(
                                    (a) =>
                                        a['id'] == destination &&
                                        a['id'] != account &&
                                        a['currency'] == currency,
                                  )
                                  ? destination
                                  : null,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Ke akun',
                              ),
                              items: accounts
                                  .where(
                                    (a) =>
                                        a['id'] != account &&
                                        a['currency'] == currency,
                                  )
                                  .map(
                                    (a) => DropdownMenuItem<String>(
                                      value: a['id'],
                                      child: Text(a['name']),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                destination = v;
                                dirty = true;
                              }),
                              validator: (v) => v == null
                                  ? 'Pilih akun tujuan dengan mata uang sama.'
                                  : null,
                            ),
                          )
                        else
                          field(
                            DropdownButtonFormField<String>(
                              initialValue: category,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Kategori',
                              ),
                              items: cats
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['id'],
                                      child: Text(c['name']),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                category = v;
                                dirty = true;
                              }),
                              validator: (v) =>
                                  v == null && type != 'adjustment'
                                  ? 'Pilih kategori.'
                                  : null,
                            ),
                          ),
                        field(
                          OutlinedButton.icon(
                            onPressed: () async {
                              final d = await showDatePicker(
                                context: context,
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                                initialDate: date,
                              );
                              if (d == null || !context.mounted) return;
                              final time = await showTimePicker(
                                context: context,
                                initialTime: TimeOfDay.fromDateTime(date),
                              );
                              if (time != null) {
                                setState(() {
                                  date = DateTime(
                                    d.year,
                                    d.month,
                                    d.day,
                                    time.hour,
                                    time.minute,
                                  );
                                  dirty = true;
                                });
                              }
                            },
                            icon: const Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                            ),
                            label: Text(
                              DateFormat(
                                'dd MMM yyyy · HH:mm',
                                'id_ID',
                              ).format(date),
                            ),
                          ),
                        ),
                        field(
                          TextFormField(
                            controller: description,
                            decoration: const InputDecoration(
                              labelText: 'Deskripsi (opsional)',
                            ),
                          ),
                        ),
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          title: const Text(
                            'Detail tambahan',
                            style: TextStyle(fontSize: 14),
                          ),
                          children: [
                            field(
                              TextFormField(
                                controller: merchant,
                                decoration: const InputDecoration(
                                  labelText: 'Merchant / penerima',
                                ),
                              ),
                            ),
                            field(
                              TextFormField(
                                controller: notes,
                                maxLines: 2,
                                decoration: const InputDecoration(
                                  labelText: 'Catatan',
                                ),
                              ),
                            ),
                            field(
                              TextFormField(
                                controller: tags,
                                decoration: const InputDecoration(
                                  labelText: 'Tags',
                                  helperText: 'Pisahkan dengan koma.',
                                ),
                              ),
                            ),
                            field(
                              DropdownButtonFormField<String>(
                                initialValue: status,
                                decoration: const InputDecoration(
                                  labelText: 'Status',
                                ),
                                items: ['posted', 'pending', 'draft', 'voided']
                                    .map(
                                      (s) => DropdownMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  status = v!;
                                  dirty = true;
                                }),
                              ),
                            ),
                            for (final f in widget.store.rows(
                              'custom_field_definitions',
                            ))
                              field(
                                f['field_type'] == 'enum' ||
                                        f['field_type'] == 'boolean'
                                    ? DropdownButtonFormField<String>(
                                        initialValue:
                                            custom[f['field_key']]!.text.isEmpty
                                            ? null
                                            : custom[f['field_key']]!.text,
                                        decoration: InputDecoration(
                                          labelText: f['field_key'],
                                        ),
                                        items:
                                            (f['field_type'] == 'boolean'
                                                    ? ['true', 'false']
                                                    : (f['options_json']['values']
                                                              as List? ??
                                                          []))
                                                .map(
                                                  (v) =>
                                                      DropdownMenuItem<String>(
                                                        value: '$v',
                                                        child: Text('$v'),
                                                      ),
                                                )
                                                .toList(),
                                        onChanged: (v) {
                                          custom[f['field_key']]!.text =
                                              v ?? '';
                                        },
                                        validator: (v) =>
                                            f['required'] == true &&
                                                (v ?? '').isEmpty
                                            ? 'Wajib diisi.'
                                            : null,
                                      )
                                    : TextFormField(
                                        controller: custom[f['field_key']],
                                        keyboardType:
                                            f['field_type'] == 'number'
                                            ? TextInputType.number
                                            : TextInputType.text,
                                        decoration: InputDecoration(
                                          labelText: f['field_key'],
                                          helperText: f['field_type'] == 'date'
                                              ? 'Format YYYY-MM-DD'
                                              : null,
                                        ),
                                        validator: (v) {
                                          if (f['required'] == true &&
                                              (v ?? '').isEmpty) {
                                            return 'Wajib diisi.';
                                          }
                                          if (v!.isNotEmpty &&
                                              f['field_type'] == 'number' &&
                                              num.tryParse(v) == null) {
                                            return 'Angka tidak valid.';
                                          }
                                          if (v.isNotEmpty &&
                                              f['field_type'] == 'date' &&
                                              DateTime.tryParse(v) == null) {
                                            return 'Tanggal tidak valid.';
                                          }
                                          return null;
                                        },
                                      ),
                              ),
                            field(
                              OutlinedButton.icon(
                                onPressed: busy ? null : pickAttachment,
                                icon: const Icon(Icons.attach_file),
                                label: Text(
                                  attachment == null
                                      ? 'Lampirkan struk (PDF/JPG/PNG)'
                                      : 'Lampiran tersedia · ganti',
                                ),
                              ),
                            ),
                            if (type != 'transfer') ...[
                              for (var i = 0; i < splits.length; i++)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    widget.store.name(
                                      'categories',
                                      splits[i]['category_id'],
                                    ),
                                  ),
                                  subtitle: Text(
                                    money(splits[i]['amount'], currency),
                                  ),
                                  trailing: IconButton(
                                    tooltip: 'Hapus split',
                                    onPressed: () => setState(() {
                                      splits.removeAt(i);
                                      dirty = true;
                                    }),
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              TextButton.icon(
                                onPressed: () async {
                                  final v = await showDialog<FinanceRow>(
                                    context: context,
                                    builder: (c) => RecordForm(
                                      title: 'Split kategori',
                                      fields: [
                                        Field(
                                          'category_id',
                                          'Kategori',
                                          options: {
                                            for (final c in cats)
                                              c['id']: c['name'],
                                          },
                                        ),
                                        const Field(
                                          'amount',
                                          'Nominal',
                                          number: true,
                                        ),
                                      ],
                                    ),
                                  );
                                  if (v != null) {
                                    setState(() {
                                      splits.add({
                                        'category_id': v['category_id'],
                                        'amount': parseMoney(
                                          v['amount'],
                                          currency,
                                        ),
                                      });
                                      dirty = true;
                                    });
                                  }
                                },
                                icon: const Icon(Icons.call_split, size: 18),
                                label: const Text('Tambah split kategori'),
                              ),
                            ],
                          ],
                        ),
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
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy ? null : close,
                      child: const Text('Batal'),
                    ),
                    if (widget.existing == null)
                      OutlinedButton(
                        onPressed: busy ? null : () => save(another: true),
                        child: const Text('Simpan & tambah lagi'),
                      ),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Menyimpan…' : 'Simpan'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

part of 'shell.dart';

class FinanceAiPage extends StatefulWidget {
  final FinanceStore store;
  const FinanceAiPage({super.key, required this.store});
  @override
  State<FinanceAiPage> createState() => _FinanceAiPageState();
}

class _FinanceAiPageState extends State<FinanceAiPage> {
  final input = TextEditingController();
  List<FinanceRow> providers = [], chats = [], messages = [], actions = [];
  String? providerId, chatId, error;
  bool busy = false, loading = true;
  FinanceRow? attachment;
  String? retryKey;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final p = await widget.store.api('ai/providers');
      final c = await widget.store.api('ai/chats');
      if (!mounted) return;
      setState(() {
        providers = List<FinanceRow>.from(p['data']);
        chats = List<FinanceRow>.from(c['data']);
        providerId ??= providers.firstOrNull?['id'];
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          loading = false;
        });
      }
    }
  }

  Future<void> history(String id) async {
    final r = await widget.store.api('ai/chats/$id/messages');
    if (mounted) {
      setState(() {
        messages = List<FinanceRow>.from(r['data']).reversed.toList();
        actions = List<FinanceRow>.from(r['actions']);
        chatId = id;
      });
    }
  }

  Future<void> execute(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() => execute(() async {
    if (providerId == null) {
      throw Exception('Tambahkan provider AI terlebih dahulu.');
    }
    if (input.text.trim().isEmpty && attachment == null) return;
    if (chatId == null) {
      final c = await widget.store.api(
        'ai/chats',
        method: 'POST',
        body: {'provider_id': providerId},
      );
      chatId = c['id'];
    }
    retryKey ??= uuid.v4();
    await widget.store.api(
      'ai/chats/$chatId/send',
      method: 'POST',
      body: {
        'text': input.text,
        'request_key': retryKey,
        'attachment': attachment,
      },
    );
    if (!mounted) return;
    input.clear();
    retryKey = null;
    attachment = null;
    await history(chatId!);
    await load();
    await widget.store.refresh();
  });
  Future<void> pickFile() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'txt', 'csv'],
    );
    if (f == null || !mounted) return;
    if ((f.lengthSync() ?? 0) > 5 * 1024 * 1024) {
      setState(() => error = 'Pilih file maksimal 5 MB.');
      return;
    }
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => error = 'Pilih file maksimal 5 MB.');
      return;
    }
    setState(() {
      attachment = {'name': f.name, 'data': base64Encode(bytes)};
      retryKey = null;
    });
  }

  Future<void> providerEditor([FinanceRow? existing]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AiProviderDialog(store: widget.store, existing: existing),
    );
    await load();
  }

  Widget actionDetails(FinanceRow action) {
    const resources = {
      'transactions': 'Transaksi',
      'transfers': 'Transfer',
      'accounts': 'Akun',
      'categories': 'Kategori',
      'transaction-templates': 'Template transaksi',
      'transaction_templates': 'Template transaksi',
      'recurring': 'Transaksi berulang',
      'recurring_rules': 'Transaksi berulang',
      'savings-goals': 'Tujuan tabungan',
      'savings_goals': 'Tujuan tabungan',
      'goal-allocations': 'Alokasi tabungan',
      'goal_allocations': 'Alokasi tabungan',
      'debts': 'Utang / piutang',
      'debt-payments': 'Pembayaran utang',
      'debt_payments': 'Pembayaran utang',
      'budgets': 'Anggaran',
      'exports': 'Ekspor laporan',
      'imports': 'Import data',
    };
    final args = FinanceRow.from(action['args']);
    final tool = '${action['tool']}';
    final method =
        args['method'] ??
        (tool.startsWith('create_')
            ? 'POST'
            : tool.startsWith('update_')
            ? 'PATCH'
            : 'DELETE');
    final resource =
        args['path']?.toString().split('/').first ??
        tool.substring(tool.indexOf('_') + 1);
    final payload = FinanceRow.from(args['payload'] ?? {});
    final currency =
        payload['currency'] ??
        widget.store
            .rows('debts')
            .where((r) => r['id'] == payload['debt_id'])
            .firstOrNull?['currency'] ??
        widget.store
            .rows('savings_goals')
            .where((r) => r['id'] == payload['goal_id'])
            .firstOrNull?['currency'] ??
        widget.store.currency;
    const labels = {
      'name': 'Nama',
      'type': 'Jenis',
      'amount': 'Nominal',
      'amount_minor': 'Nominal',
      'principal': 'Pokok',
      'principal_paid': 'Pokok dibayar',
      'interest_paid': 'Bunga dibayar',
      'target_amount': 'Target',
      'target_date': 'Tanggal target',
      'due': 'Jatuh tempo',
      'effective_at': 'Tanggal transaksi',
      'next_at': 'Jadwal berikutnya',
      'end_at': 'Berakhir',
      'cadence': 'Pengulangan',
      'mode': 'Mode pencatatan',
      'active': 'Aktif',
      'account_id': 'Akun',
      'destination_account_id': 'Akun tujuan',
      'category_id': 'Kategori',
      'parent_id': 'Kategori induk',
      'goal_id': 'Tujuan tabungan',
      'debt_id': 'Utang / piutang',
      'transaction_id': 'Transaksi tertaut',
      'currency': 'Mata uang',
      'merchant': 'Toko / merchant',
      'description': 'Keterangan',
      'notes': 'Catatan',
      'reason': 'Alasan',
      'counterparty': 'Pihak terkait',
      'rate': 'Bunga (%)',
      'payload_json': 'Rincian transaksi',
      'favourite': 'Favorit',
      'archived': 'Diarsipkan',
      'tags': 'Tag',
      'splits': 'Pembagian kategori',
      'period_start': 'Awal periode',
      'period_end': 'Akhir periode',
      'default_budget': 'Anggaran default',
      'format': 'Format',
      'status': 'Status',
    };
    String show(String k, dynamic v, String unit) {
      if (v == null) return '—';
      if ([
        'amount',
        'amount_minor',
        'principal',
        'principal_paid',
        'interest_paid',
        'target_amount',
        'default_budget',
      ].contains(k)) {
        return money(v, unit);
      }
      final table = switch (k) {
        'account_id' || 'destination_account_id' => 'accounts',
        'category_id' || 'parent_id' => 'categories',
        'goal_id' => 'savings_goals',
        'debt_id' => 'debts',
        _ => null,
      };
      if (table != null) return widget.store.name(table, v);
      if (v is bool) return v ? 'Ya' : 'Tidak';
      if (v is Map) {
        return v.entries
            .where(
              (e) => ![
                'expected_version',
                'source_ref',
                'attachment_path',
                'user_id',
              ].contains(e.key),
            )
            .map(
              (e) =>
                  '${labels[e.key] ?? e.key.toString().replaceAll('_', ' ')}: ${show(e.key, e.value, (v['currency'] ?? unit).toString())}',
            )
            .join('\n');
      }
      if (v is List) return v.map((x) => show('item', x, unit)).join('\n');
      return {
            'expense': 'Pengeluaran',
            'income': 'Pemasukan',
            'transfer': 'Transfer',
            'posted': 'Tercatat',
            'draft': 'Draft',
            'pending': 'Menunggu',
            'daily': 'Harian',
            'weekly': 'Mingguan',
            'monthly': 'Bulanan',
            'yearly': 'Tahunan',
            'debt': 'Utang',
            'receivable': 'Piutang',
            'auto-post': 'Catat otomatis',
          }[v.toString()] ??
          v.toString();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${method == 'POST'
              ? 'Tambah'
              : method == 'PATCH'
              ? 'Ubah'
              : 'Hapus / nonaktifkan'} ${resources[resource] ?? resource}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        for (final e in payload.entries.where(
          (e) => ![
            'expected_version',
            'source_ref',
            'attachment_path',
            'user_id',
          ].contains(e.key),
        ))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SelectableText(
              '${labels[e.key] ?? e.key.replaceAll('_', ' ')}: ${show(e.key, e.value, currency.toString())}',
            ),
          ),
        if (payload['attachment_path'] != null)
          const Text('Struk terlampir', style: TextStyle(fontSize: 12)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const FinanceLogo(size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finance AI', style: theme.textTheme.headlineMedium),
                  const Text('Asisten keuangan pribadi · API key Anda sendiri'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Tambah provider',
              onPressed: busy ? null : () => providerEditor(),
              icon: const Icon(Icons.settings_suggest_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SelectableText(
              error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        if (providers.isEmpty && !loading)
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hubungkan AI pilihan Anda',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Anthropic, OpenAI-compatible, atau Gemini native. Pesan dan lampiran yang diperlukan dikirim ke provider pilihan Anda. API key disimpan terenkripsi di server.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => providerEditor(),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah provider'),
                ),
              ],
            ),
          ),
        if (providers.isNotEmpty) ...[
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey('$providerId:$chatId'),
                  initialValue: providerId,
                  decoration: const InputDecoration(
                    labelText: 'Provider / model',
                  ),
                  isExpanded: true,
                  items: providers
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['id'],
                          child: Text(
                            '${p['name']} · ${p['model']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          providerId = v;
                          chatId = null;
                          messages = [];
                          actions = [];
                          attachment = null;
                          retryKey = null;
                        }),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              chatId = null;
                              messages = [];
                              actions = [];
                              retryKey = null;
                            }),
                      icon: const Icon(Icons.add_comment_outlined),
                      label: const Text('Chat baru'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => providerEditor(
                              providers.firstWhere(
                                (p) => p['id'] == providerId,
                              ),
                            ),
                      child: const Text('Pengaturan provider'),
                    ),
                  ],
                ),
                if (chats
                    .where((c) => c['provider_id'] == providerId)
                    .isNotEmpty) ...[
                  const Divider(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: chats
                        .where((c) => c['provider_id'] == providerId)
                        .take(12)
                        .map(
                          (c) => InputChip(
                            label: Text(
                              c['title'],
                              overflow: TextOverflow.ellipsis,
                            ),
                            selected: c['id'] == chatId,
                            onPressed: busy
                                ? null
                                : () => execute(() => history(c['id'])),
                            onDeleted: busy
                                ? null
                                : () => execute(() async {
                                    final yes = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text(
                                          'Hapus riwayat chat?',
                                        ),
                                        content: const Text(
                                          'Riwayat, ringkasan, dan usulan AI di chat ini dihapus. Transaksi yang sudah tercatat tetap ada.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Batal'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Hapus'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (yes != true) return;
                                    await widget.store.api(
                                      'ai/chats/${c['id']}',
                                      method: 'DELETE',
                                    );
                                    if (chatId == c['id']) {
                                      chatId = null;
                                      messages = [];
                                      actions = [];
                                    }
                                    await load();
                                  }),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (messages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Tanyakan pengeluaran, rencanakan tabungan, atau unggah struk. AI memakai data milik Anda dan perubahan akan tampil untuk dikonfirmasi.',
              ),
            ),
          ...messages.map(
            (m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GlassPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m['role'] == 'user' ? 'Anda' : 'Adoetz Finance AI',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: m['role'] == 'user'
                            ? theme.colorScheme.primary
                            : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(m['content']),
                    if (m['usage_json']?['compacted'] == true) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Riwayat lama diringkas untuk menyesuaikan context model.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          ...actions
              .where((a) => a['status'] == 'pending')
              .map(
                (a) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: GlassPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Konfirmasi tindakan',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        actionDetails(a),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => execute(() async {
                                      await widget.store.api(
                                        'ai/actions/${a['id']}/reject',
                                        method: 'POST',
                                        body: {},
                                      );
                                      await history(chatId!);
                                    }),
                              child: const Text('Tolak'),
                            ),
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => execute(() async {
                                      await widget.store.api(
                                        'ai/actions/${a['id']}/approve',
                                        method: 'POST',
                                        body: {},
                                      );
                                      await history(chatId!);
                                      await widget.store.refresh();
                                    }),
                              child: const Text('Jalankan'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (attachment != null)
                  InputChip(
                    label: Text(attachment!['name']),
                    onDeleted: busy
                        ? null
                        : () => setState(() {
                            attachment = null;
                            retryKey = null;
                          }),
                  ),
                TextField(
                  controller: input,
                  enabled: !busy,
                  minLines: 2,
                  maxLines: 8,
                  maxLength: 16000,
                  onChanged: (_) => retryKey = null,
                  decoration: const InputDecoration(
                    hintText: 'Tulis pesan atau jelaskan struk yang diunggah…',
                    border: InputBorder.none,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Unggah struk / dokumen',
                      onPressed: busy ? null : pickFile,
                      icon: const Icon(Icons.attach_file),
                    ),
                    const Expanded(
                      child: Text(
                        'JPG, PNG, WEBP, PDF, TXT, CSV · maks. 5 MB',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: busy ? null : send,
                      icon: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_upward),
                      label: Text(busy ? 'Memproses…' : 'Kirim'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'AI dapat salah membaca. Periksa hasil dan konfirmasi tindakan. Saldo dan perhitungan tetap berasal dari ledger aplikasi.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class AiProviderDialog extends StatefulWidget {
  final FinanceStore store;
  final FinanceRow? existing;
  const AiProviderDialog({super.key, required this.store, this.existing});
  @override
  State<AiProviderDialog> createState() => _AiProviderDialogState();
}

class _AiProviderDialogState extends State<AiProviderDialog> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.existing?['name'] ?? 'AI saya',
  );
  late final base = TextEditingController(
    text: widget.existing?['base_url'] ?? 'https://api.openai.com/v1',
  );
  final secret = TextEditingController();
  late final model = TextEditingController(
    text: widget.existing?['model'] ?? '',
  );
  late final contextLimit = TextEditingController(
    text: '${widget.existing?['context_tokens'] ?? 32000}',
  );
  late final output = TextEditingController(
    text: '${widget.existing?['output_tokens'] ?? 2048}',
  );
  late String format = widget.existing?['format'] ?? 'openai';
  late String? id = widget.existing?['id'];
  late bool vision = widget.existing?['vision'] ?? false,
      tools = widget.existing?['tools'] ?? true,
      auto = widget.existing?['auto_record'] ?? false;
  bool busy = false;
  String? error, note;
  List<FinanceRow> models = [];
  @override
  void dispose() {
    for (final c in [name, base, secret, model, contextLimit, output]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) {
      throw Exception('Periksa isian provider.');
    }
    final p = <String, dynamic>{
      'name': name.text.trim(),
      'format': format,
      'base_url': base.text.trim(),
      'model': model.text.trim(),
      'context_tokens': int.parse(contextLimit.text),
      'output_tokens': int.parse(output.text),
      'vision': vision,
      'tools': tools,
      'auto_record': auto,
      if (secret.text.isNotEmpty) 'api_key': secret.text,
    };
    final r = await widget.store.api(
      'ai/providers${id == null ? '' : '/$id'}',
      method: id == null ? 'POST' : 'PATCH',
      body: p,
    );
    id = r['id'];
    secret.clear();
  }

  Future<void> run(Future<void> Function() fn) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      note = null;
    });
    try {
      await fn();
    } catch (e) {
      if (mounted) setState(() => error = readableError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Provider AI pribadi'),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pilih format endpoint, bukan merek model. API key tidak ditampilkan lagi setelah disimpan. Pesan/lampiran dikirim ke endpoint ini.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: format,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Format API'),
                items: const [
                  DropdownMenuItem(
                    value: 'openai',
                    child: Text('OpenAI-compatible · Chat Completions'),
                  ),
                  DropdownMenuItem(
                    value: 'anthropic',
                    child: Text('Anthropic · Messages'),
                  ),
                  DropdownMenuItem(
                    value: 'gemini',
                    child: Text('Gemini native · GenerateContent'),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        format = v!;
                        models = [];
                        base.text = switch (format) {
                          'anthropic' => 'https://api.anthropic.com/v1',
                          'gemini' =>
                            'https://generativelanguage.googleapis.com/v1beta',
                          _ => 'https://api.openai.com/v1',
                        };
                      }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Nama provider'),
                validator: (v) => v!.trim().isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: base,
                decoration: const InputDecoration(labelText: 'Base URL HTTPS'),
                validator: (v) => Uri.tryParse(v ?? '')?.scheme != 'https'
                    ? 'Gunakan HTTPS'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: secret,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: id == null ? 'API key' : 'API key baru (opsional)',
                ),
                validator: (v) =>
                    id == null && (v ?? '').isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: model,
                decoration: const InputDecoration(
                  labelText: 'Model ID (manual atau pilih dari daftar)',
                ),
              ),
              if (models.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Model dari provider',
                  ),
                  items: models
                      .map(
                        (m) => DropdownMenuItem<String>(
                          value: m['id'],
                          child: Text(m['id'], overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() {
                    final m = models.firstWhere((m) => m['id'] == v);
                    model.text = v!;
                    if (m['input_limit'] != null) {
                      contextLimit.text = '${m['input_limit']}';
                    }
                    if (m['output_limit'] != null &&
                        int.parse(output.text) > integer(m['output_limit'])) {
                      output.text = '${m['output_limit']}';
                    }
                  }),
                ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await save();
                        final r = await widget.store.api(
                          'ai/providers/$id/models',
                          method: 'POST',
                          body: {},
                        );
                        if (mounted) {
                          setState(() {
                            models = List<FinanceRow>.from(r['data']);
                            note =
                                'Daftar model diperbarui. Kemampuan gambar/tool belum otomatis terverifikasi.';
                          });
                        }
                      }),
                icon: const Icon(Icons.refresh),
                label: const Text('Simpan & ambil daftar model'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: contextLimit,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Batas context (token)',
                      ),
                      validator: (v) => int.tryParse(v ?? '') == null
                          ? 'Angka wajib diisi'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: output,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maks. output token',
                      ),
                      validator: (v) => int.tryParse(v ?? '') == null
                          ? 'Angka wajib diisi'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Gunakan batas resmi model/gateway. Jika metadata tidak tersedia, nilai ini adalah konfigurasi Anda, bukan hasil deteksi.',
                style: TextStyle(fontSize: 11),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Model mendukung gambar'),
                subtitle: const Text('Aktifkan hanya untuk model vision.'),
                value: vision,
                onChanged: (v) => setState(() => vision = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tool calling / kendali fungsi app'),
                value: tools,
                onChanged: (v) => setState(() => tools = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Otomatis catat struk yang lengkap'),
                subtitle: const Text(
                  'Opt-in. Angka harus cocok, akun/kategori jelas, dan lolos pemeriksaan server. Selain itu perlu konfirmasi.',
                ),
                value: auto,
                onChanged: (v) => setState(() => auto = v),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        await save();
                        final r = await widget.store.api(
                          'ai/providers/$id/test',
                          method: 'POST',
                          body: {},
                        );
                        if (mounted) {
                          setState(
                            () => note =
                                'Koneksi berhasil. Tool calling: ${r['tools_verified'] == true ? 'terverifikasi' : 'belum terverifikasi'}. Gambar belum diuji.',
                          );
                        }
                      }),
                child: const Text('Simpan & uji koneksi (memakai kuota API)'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(note!),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (id != null)
        TextButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  final yes = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Hapus koneksi AI?'),
                      content: const Text(
                        'Key tersimpan dan seluruh chat provider ini dihapus. Struk yang sudah menjadi lampiran transaksi tetap disimpan. API key di layanan provider tidak dicabut.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Hapus'),
                        ),
                      ],
                    ),
                  );
                  if (yes != true) return;
                  await widget.store.api('ai/providers/$id', method: 'DELETE');
                  if (context.mounted) Navigator.pop(context);
                }),
          child: const Text('Hapus koneksi'),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Tutup'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () => run(() async {
                await save();
                if (context.mounted) Navigator.pop(context);
              }),
        child: Text(busy ? 'Menyimpan…' : 'Simpan'),
      ),
    ],
  );
}

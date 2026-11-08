part of 'shell.dart';

class FormPreferencesDialog extends StatefulWidget {
  final FinanceStore store;
  const FormPreferencesDialog({super.key, required this.store});
  @override
  State<FormPreferencesDialog> createState() => _FormPreferencesDialogState();
}

class _FormPreferencesDialogState extends State<FormPreferencesDialog> {
  static const labels = {
    'description': 'Deskripsi',
    'merchant': 'Merchant / penerima',
    'notes': 'Catatan',
    'tags': 'Tags',
  };
  late final FinanceRow prefs = FinanceRow.from(
    widget.store.profile['settings_json']?['transaction_form'] ?? {},
  );
  late final List<String> order = [
    ...List<String>.from(
      prefs['order'] ?? ['description', 'merchant', 'notes', 'tags'],
    ).where(labels.containsKey),
    ...labels.keys.where(
      (k) =>
          !(prefs['order'] as List? ??
                  ['description', 'merchant', 'notes', 'tags'])
              .contains(k),
    ),
  ];
  late final Set<String> hidden = Set<String>.from(prefs['hidden'] ?? []),
      requiredFields = Set<String>.from(prefs['required'] ?? []);
  late final controls = {
    for (final key in labels.keys)
      key: TextEditingController(text: prefs['defaults']?[key] ?? ''),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.store.db
          .from('profiles')
          .update({
            'settings_json': {
              ...?widget.store.profile['settings_json'],
              'transaction_form': {
                'order': order,
                'hidden': hidden.toList(),
                'required': requiredFields.toList(),
                'defaults': {
                  for (final e in controls.entries) e.key: e.value.text,
                },
                'updated_at': DateTime.now().toUtc().toIso8601String(),
              },
            },
          })
          .eq('user_id', widget.store.uid);
      await widget.store.refresh();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          error = readableError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Atur form transaksi'),
    content: SizedBox(
      width: 540,
      height: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nominal, akun, kategori, dan tanggal selalu tersedia. Geser field atau gunakan tombol urutan.',
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ReorderableListView(
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) => setState(() {
                final field = order.removeAt(from);
                order.insert(to, field);
              }),
              children: [
                for (var i = 0; i < order.length; i++)
                  Padding(
                    key: ValueKey(order[i]),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: !hidden.contains(order[i]),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      hidden.remove(order[i]);
                                    } else {
                                      hidden.add(order[i]);
                                      requiredFields.remove(order[i]);
                                    }
                                  }),
                                ),
                                Expanded(child: Text(labels[order[i]]!)),
                                IconButton(
                                  tooltip: 'Pindah ke atas',
                                  onPressed: i == 0
                                      ? null
                                      : () => setState(() {
                                          final key = order.removeAt(i);
                                          order.insert(i - 1, key);
                                        }),
                                  icon: const Icon(
                                    Icons.arrow_upward,
                                    size: 18,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Pindah ke bawah',
                                  onPressed: i == order.length - 1
                                      ? null
                                      : () => setState(() {
                                          final key = order.removeAt(i);
                                          order.insert(i + 1, key);
                                        }),
                                  icon: const Icon(
                                    Icons.arrow_downward,
                                    size: 18,
                                  ),
                                ),
                                ReorderableDragStartListener(
                                  index: i,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8),
                                    child: Icon(Icons.drag_indicator, size: 18),
                                  ),
                                ),
                              ],
                            ),
                            TextField(
                              controller: controls[order[i]],
                              decoration: const InputDecoration(
                                labelText: 'Nilai default (opsional)',
                              ),
                            ),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: requiredFields.contains(order[i]),
                              title: const Text(
                                'Wajib diisi untuk transaksi baru',
                              ),
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  requiredFields.add(order[i]);
                                  hidden.remove(order[i]);
                                } else {
                                  requiredFields.remove(order[i]);
                                }
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? 'Menyimpan…' : 'Simpan pengaturan'),
      ),
    ],
  );
}

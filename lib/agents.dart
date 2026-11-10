part of 'shell.dart';

const agentScopes = [
  'accounts:read',
  'transactions:read',
  'transactions:create',
  'transactions:update',
  'transactions:delete',
  'categories:read',
  'categories:write',
  'templates:read',
  'templates:write',
  'recurring:read',
  'recurring:write',
  'goals:read',
  'goals:write',
  'debts:read',
  'debts:write',
  'budgets:read',
  'budgets:write',
  'forecasts:read',
  'forecasts:simulate',
  'analytics:read',
  'reports:export',
];

extension _FinanceAgents on _FinanceShellState {
  Widget agentsPage() {
    final approvals = store
        .rows('agent_pending_actions')
        .where((a) => a['status'] == 'pending')
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        pageHeading(
          'API & AI Agents',
          'Izin terbatas. Perubahan transparan. Kendali tetap di Anda.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  if (await confirm(
                    'Pause semua agent?',
                    'Semua request berikutnya akan ditolak sampai agent diaktifkan kembali.',
                  )) {
                    run(() async {
                      await store.db
                          .from('agent_connections')
                          .update({'status': 'paused'})
                          .eq('user_id', store.uid)
                          .eq('status', 'active');
                      await store.refresh();
                    });
                  }
                },
                icon: const Icon(Icons.pause_circle_outline),
                label: const Text('Emergency pause'),
              ),
              FilledButton.icon(
                onPressed: connectAgent,
                icon: const Icon(Icons.add_link),
                label: const Text('Generate token'),
              ),
            ],
          ),
        ),
        section(
          'Endpoint & autentikasi',
          subtitle: 'Token pribadi · REST API dan MCP Streamable HTTP',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'REST API',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SelectableText('$apiUrl/api/v1'),
              const SizedBox(height: 12),
              const Text(
                'MCP endpoint',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SelectableText('$apiUrl/mcp'),
              const SizedBox(height: 12),
              const Text(
                'Buat token di aplikasi, lalu gunakan Authorization: Bearer TOKEN untuk REST API maupun MCP. Token hanya ditampilkan sekali. Atur izin dan batas untuk setiap token; hanya data pemilik token yang dapat diakses.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '$apiUrl/mcp'));
                  toast('Endpoint disalin.');
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Salin MCP endpoint'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        section(
          'Token API & MCP',
          child:
              store
                  .rows('agent_connections')
                  .where((a) => '${a['oauth_client_id']}'.startsWith('pat:'))
                  .isEmpty
              ? empty('Belum ada token. Tekan Generate token untuk membuatnya.')
              : Column(
                  children: store
                      .rows('agent_connections')
                      .where(
                        (a) => '${a['oauth_client_id']}'.startsWith('pat:'),
                      )
                      .map(
                        (a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.hub_outlined),
                          title: Text(a['display_name']),
                          subtitle: Text(tokenCaption(a)),
                          trailing: Wrap(
                            children: [
                              IconButton(
                                tooltip: 'Atur izin dan batas',
                                onPressed: a['status'] == 'revoked'
                                    ? null
                                    : () => agentPolicy(a),
                                icon: const Icon(Icons.tune),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'revoke' &&
                                      !await confirm(
                                        'Cabut akses agent?',
                                        'Token yang belum kedaluwarsa juga akan ditolak pada request berikutnya.',
                                      )) {
                                    return;
                                  }
                                  if (v == 'revoke') {
                                    final token = store
                                        .rows('personal_tokens')
                                        .where(
                                          (t) => t['connection_id'] == a['id'],
                                        )
                                        .firstOrNull;
                                    if (token != null) {
                                      await run(() async {
                                        await store.api(
                                          'tokens/${token['id']}',
                                          method: 'DELETE',
                                        );
                                        await store.refresh();
                                      });
                                    }
                                    return;
                                  }
                                  run(
                                    () => store.save('agent_connections', {
                                      'status': v == 'revoke'
                                          ? 'revoked'
                                          : a['status'] == 'active'
                                          ? 'paused'
                                          : 'active',
                                      if (v == 'revoke')
                                        'revoked_at': DateTime.now()
                                            .toUtc()
                                            .toIso8601String(),
                                    }, id: a['id']),
                                  );
                                },
                                itemBuilder: (c) => [
                                  PopupMenuItem(
                                    value: 'pause',
                                    enabled: a['status'] != 'revoked',
                                    child: Text(
                                      a['status'] == 'active'
                                          ? 'Pause'
                                          : 'Aktifkan',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'revoke',
                                    child: Text('Revoke'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 20),
        section(
          'Pending approvals',
          subtitle: 'Hanya Anda dapat menyetujui. Proposal berlaku 10 menit.',
          child: approvals.isEmpty
              ? empty('Tidak ada permintaan yang menunggu approval.')
              : Column(
                  children: approvals
                      .map(
                        (a) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  store
                                          .rows('agent_connections')
                                          .where(
                                            (c) =>
                                                c['id'] == a['connection_id'],
                                          )
                                          .firstOrNull?['display_name'] ??
                                      'Agent',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${a['operation']} · ${money(a['payload_json']['amount'] ?? 0, a['payload_json']['currency'] ?? 'IDR')}',
                                ),
                                Text(
                                  '${store.name('accounts', a['payload_json']['account_id'])} · ${a['payload_json']['description'] ?? ''}',
                                ),
                                Text(
                                  'Kedaluwarsa ${DateFormat('HH:mm').format(DateTime.parse(a['expires_at']).toLocal())}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  title: const Text(
                                    'Lihat proposal',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                  children: [
                                    SelectableText(
                                      const JsonEncoder.withIndent(
                                        '  ',
                                      ).convert(a['payload_json']),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () => approveAction(a, false),
                                      child: const Text('Tolak'),
                                    ),
                                    FilledButton(
                                      onPressed: () => approveAction(a, true),
                                      child: const Text('Setujui perubahan'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
        const SizedBox(height: 20),
        section(
          'Activity & audit',
          subtitle: 'Riwayat append-only · tanpa password atau token',
          child: store.rows('agent_audit_logs').isEmpty
              ? empty('Belum ada aktivitas.')
              : Column(
                  children: store
                      .rows('agent_audit_logs')
                      .reversed
                      .take(30)
                      .map(
                        (a) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            a['outcome'] == 'ok'
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 20,
                          ),
                          title: Text(a['event_type']),
                          subtitle: Text(
                            '${a['actor']} · ${dateLabel(a['occurred_at'])}',
                          ),
                          trailing: Text(
                            a['outcome'] ?? '',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }

  String tokenCaption(FinanceRow connection) {
    final token = store
        .rows('personal_tokens')
        .where((t) => t['connection_id'] == connection['id'])
        .firstOrNull;
    return token == null
        ? connection['status']
        : '${token['prefix']}… · ${token['status']} · berlaku s.d. ${dateLabel(token['expires_at'])}';
  }

  Future<void> connectAgent() async {
    final values = await recordDialog('Generate token pribadi', [
      const Field('name', 'Nama token', value: 'Integrasi saya'),
      const Field(
        'days',
        'Masa berlaku',
        value: '90',
        options: {
          '7': '7 hari',
          '30': '30 hari',
          '90': '90 hari',
          '365': '1 tahun',
        },
      ),
    ], saveLabel: 'Generate token');
    if (values == null) return;
    await run(() async {
      final result = FinanceRow.from(
        await store.api(
          'tokens',
          method: 'POST',
          body: {
            'name': values['name'],
            'expires_in_days': int.parse(values['days']),
          },
        ),
      );
      if (!mounted) return;
      update(() => saving = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Simpan token Anda'),
          content: SizedBox(
            width: 500,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Token hanya ditampilkan sekali. Izin awal hanya baca; aktifkan izin tulis melalui pengaturan token bila diperlukan.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  result['token'],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 16),
                Text('Berlaku s.d. ${dateLabel(result['expires_at'])}'),
                const SizedBox(height: 8),
                const Text(
                  'REST API dan MCP: Authorization: Bearer TOKEN',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: result['token']));
                if (mounted) toast('Token disalin.');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Salin token'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Sudah disimpan'),
            ),
          ],
        ),
      );
      await store.refresh();
    }, success: 'Token dibuat. Atur izin dan batas melalui ikon pengaturan.');
  }

  Future<void> agentPolicy(FinanceRow a) async {
    final permissions = {
      for (final p
          in store
              .rows('agent_permissions')
              .where((p) => p['connection_id'] == a['id']))
        p['permission']: p['enabled'] == true,
    };
    final policy = store
        .rows('agent_policies')
        .where((p) => p['connection_id'] == a['id'])
        .firstOrNull;
    final limits = FinanceRow.from(policy?['limits_json'] ?? {});
    final create = TextEditingController(
          text: '${limits['create_limit'] ?? 1000000}',
        ),
        edit = TextEditingController(text: '${limits['edit_limit'] ?? 250000}'),
        daily = TextEditingController(
          text: '${limits['daily_cap'] ?? 5000000}',
        );
    var always = policy?['approval_mode'] == 'always';
    final allowedAccounts = (policy?['account_allowlist'] as List? ?? [])
        .map((x) => '$x')
        .toSet();
    final allowedCategories = (policy?['category_allowlist'] as List? ?? [])
        .map((x) => '$x')
        .toSet();
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, local) => AlertDialog(
          title: Text('Izin · ${a['display_name']}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Admin dan pengubahan izin tidak pernah dapat diakses oleh agent.',
                  ),
                  const SizedBox(height: 12),
                  for (final scope in agentScopes)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(scope, style: const TextStyle(fontSize: 13)),
                      value: permissions[scope] ?? false,
                      onChanged: (v) => local(() => permissions[scope] = v),
                    ),
                  const Divider(),
                  TextField(
                    controller: create,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Batas create otomatis (IDR)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: edit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Batas selisih edit otomatis (IDR)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: daily,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Batas nominal harian (IDR)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Selalu minta approval'),
                    value: always,
                    onChanged: (v) => local(() => always = v),
                  ),
                  ExpansionTile(
                    title: const Text('Batasi akun'),
                    subtitle: const Text(
                      'Kosong berarti semua akun milik Anda.',
                    ),
                    children: store
                        .rows('accounts')
                        .map(
                          (x) => CheckboxListTile(
                            title: Text(x['name']),
                            value: allowedAccounts.contains(x['id']),
                            onChanged: (v) => local(() {
                              if (v == true) {
                                allowedAccounts.add(x['id']);
                              } else {
                                allowedAccounts.remove(x['id']);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  ExpansionTile(
                    title: const Text('Batasi kategori'),
                    subtitle: const Text(
                      'Kosong berarti semua kategori milik Anda.',
                    ),
                    children: store
                        .rows('categories')
                        .map(
                          (x) => CheckboxListTile(
                            title: Text(x['name']),
                            value: allowedCategories.contains(x['id']),
                            onChanged: (v) => local(() {
                              if (v == true) {
                                allowedCategories.add(x['id']);
                              } else {
                                allowedCategories.remove(x['id']);
                              }
                            }),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Simpan izin'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final c = int.tryParse(create.text),
          e = int.tryParse(edit.text),
          d = int.tryParse(daily.text);
      if (c == null || e == null || d == null || c < 0 || e < 0 || d < 0) {
        toast('Batas nominal harus integer positif atau nol.');
        return;
      }
      await run(() async {
        await store.api(
          'agents/connections/${a['id']}/policy',
          method: 'POST',
          body: {
            'permissions': permissions,
            'limits': {
              'create_limit': c,
              'edit_limit': e,
              'daily_cap': d,
              'hourly_cap': 30,
            },
            'approval_mode': always ? 'always' : 'risk',
            'account_allowlist': allowedAccounts.toList(),
            'category_allowlist': allowedCategories.toList(),
          },
        );
        await store.refresh();
      });
    }
    create.dispose();
    edit.dispose();
    daily.dispose();
  }

  Future<void> approveAction(FinanceRow a, bool approve) async {
    if (approve &&
        !await confirm(
          'Setujui perubahan agent?',
          '${a['operation']}\nNominal ${money(a['payload_json']['amount'] ?? 0, a['payload_json']['currency'] ?? 'IDR')}\n${a['payload_json']['description'] ?? ''}',
        )) {
      return;
    }
    run(() async {
      await store.db.rpc(
        'resolve_approval',
        params: {'action_id': a['id'], 'approve': approve},
      );
      await store.refresh();
    });
  }

  Future<void> loadAdmin() async {
    await run(() async {
      if (page == 14) {
        final result = await store.api(
          'admin/users?search=${Uri.encodeQueryComponent(adminSearch)}',
        );
        update(() => adminUsers = (result['data'] as List).cast<FinanceRow>());
      } else {
        final result = await store.api('admin/audit');
        update(() => adminLogs = (result['data'] as List).cast<FinanceRow>());
      }
    }, success: '');
  }

  Widget usersPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'User Management',
        'Hanya metadata akun. Data keuangan tetap privat.',
      ),
      section(
        'Users',
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'Cari username atau email',
                prefixIcon: Icon(Icons.search),
              ),
              onSubmitted: (v) {
                adminSearch = v;
                loadAdmin();
              },
            ),
            const SizedBox(height: 16),
            if (adminUsers.isEmpty)
              empty('Tidak ada user yang sesuai.')
            else
              for (final u in adminUsers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(u['username_normalized']),
                  subtitle: Text(
                    '${u['email']}\n${u['status']} · ${u['role']} · ${dateLabel(u['created_at'])}',
                  ),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) => adminAction(u, v),
                    itemBuilder: (c) => [
                      PopupMenuItem(
                        value: u['status'] == 'active'
                            ? 'suspend'
                            : 'reactivate',
                        child: Text(
                          u['status'] == 'active' ? 'Suspend' : 'Reactivate',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'reset-password',
                        child: Text('Reset password sementara'),
                      ),
                      const PopupMenuItem(
                        value: 'force-logout',
                        child: Text('Force logout'),
                      ),
                      const PopupMenuItem(
                        value: 'change-role',
                        child: Text('Ubah role'),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    ],
  );
  Future<void> adminAction(FinanceRow u, String action) async {
    final fields = [
      const Field('reason', 'Alasan tindakan'),
      if (action == 'reset-password')
        const Field('identity_proof', 'Referensi verifikasi identitas'),
      if (action == 'change-role')
        Field(
          'role',
          'Role',
          value: u['role'],
          options: {'user': 'User', 'admin': 'Administrator'},
        ),
    ];
    final v = await recordDialog(
      'Konfirmasi $action · ${u['username_normalized']}',
      fields,
      saveLabel: 'Lakukan tindakan',
    );
    if (v == null) return;
    if (!await confirm(
      'Konfirmasi tindakan admin',
      'Target: ${u['username_normalized']}\nTindakan: $action\nAlasan: ${v['reason']}',
    )) {
      return;
    }
    run(() async {
      final result = await store.api(
        'admin/users/${u['user_id']}/$action',
        method: 'POST',
        body: v,
      );
      if (result['temporary_password'] != null && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (c) => AlertDialog(
            title: const Text('Password sementara'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ditampilkan sekali. Sampaikan melalui proses verifikasi identitas yang disetujui.',
                ),
                const SizedBox(height: 16),
                SelectableText(
                  result['temporary_password'],
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 12),
                const Text('User wajib mengganti password setelah login.'),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Selesai'),
              ),
            ],
          ),
        );
      }
      await loadAdmin();
    });
  }

  Widget adminAuditPage() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      pageHeading(
        'Admin Audit Logs',
        'Jejak tindakan admin yang tidak dapat dihapus dari aplikasi.',
      ),
      section(
        'Audit trail',
        child: adminLogs.isEmpty
            ? empty('Belum ada tindakan admin.')
            : Column(
                children: adminLogs
                    .map(
                      (a) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.policy_outlined),
                        title: Text(a['action']),
                        subtitle: Text(
                          '${a['reason']}\n${dateLabel(a['timestamp'])} · ${a['target_user_id']}',
                        ),
                        isThreeLine: true,
                        trailing: Text(a['result']?['status'] ?? 'ok'),
                      ),
                    )
                    .toList(),
              ),
      ),
    ],
  );
}

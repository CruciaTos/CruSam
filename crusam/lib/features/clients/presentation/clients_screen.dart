// lib/features/clients/presentation/clients_screen.dart
//
// Client address book. Saved clients live in the `clients` table (shared
// with the CruSam MCP server via crusam_core's ClientStore). Clients that so
// far only appear on invoices are listed too and can be saved in one click.

import 'package:crusam_core/crusam_core.dart' show ClientModel, ClientStore, UiEventStore;
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/sync/db_change_watcher.dart';
import '../../../shared/widgets/claude_highlight.dart';
import '../../../data/db/database_helper.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _Entry {
  final ClientModel client;
  final bool saved;
  final int invoiceCount;
  const _Entry(this.client, this.saved, this.invoiceCount);
}

class _ClientsScreenState extends State<ClientsScreen>
    with ReloadOnDbChange, ClaudeListFocus {
  List<_Entry> _entries = [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void onDbChanged() => _load(silent: true);

  @override
  List<String> get claudeKeys =>
      [for (final e in _visible) UiEventStore.clientFocus(e.client.id ?? 0)];

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await DatabaseHelper.instance.database;
      await ClientStore.ensureTable(db);
      final saved = await ClientStore.listSaved(db);
      final history = await ClientStore.fromInvoices(db);
      final counts = {
        for (final (c, n) in history) c.name.trim().toLowerCase(): n,
      };
      final savedNames = saved.map((c) => c.name.trim().toLowerCase()).toSet();
      setState(() {
        _entries = [
          for (final c in saved)
            _Entry(c, true, counts[c.name.trim().toLowerCase()] ?? 0),
          for (final (c, n) in history)
            if (!savedNames.contains(c.name.trim().toLowerCase()))
              _Entry(c, false, n),
        ];
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_Entry> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _entries;
    return _entries
        .where((e) =>
            e.client.name.toLowerCase().contains(q) ||
            e.client.gstin.toLowerCase().contains(q) ||
            e.client.address.toLowerCase().contains(q))
        .toList();
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : null,
    ));
  }

  Future<void> _edit({_Entry? entry}) async {
    final result = await showDialog<ClientModel>(
      context: context,
      builder: (_) => _ClientDialog(initial: entry?.client),
    );
    if (result == null) return;
    try {
      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now().toUtc().toIso8601String();
      final existing = await ClientStore.getByName(db, result.name);
      final editingId = entry != null && entry.saved ? entry.client.id : null;
      if (existing != null && existing.id != editingId) {
        _snack('A client named "${existing.name}" already exists.', error: true);
        return;
      }
      if (editingId != null) {
        await ClientStore.update(db, editingId, {
          'name': result.name,
          'address': result.address,
          'gstin': result.gstin,
          'email': result.email,
          'updated_at': now,
        });
        _snack('Client updated');
      } else {
        await ClientStore.insert(
          db,
          ClientModel(
            name: result.name,
            address: result.address,
            gstin: result.gstin,
            email: result.email,
            createdAt: now,
            updatedAt: now,
          ),
        );
        _snack('Client saved');
      }
      await _load();
    } catch (e) {
      _snack('Could not save client: $e', error: true);
    }
  }

  Future<void> _delete(_Entry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove client'),
        content: Text('Remove "${entry.client.name}" from the address book? '
            'Invoices that use this client are not changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    final db = await DatabaseHelper.instance.database;
    await ClientStore.softDelete(db, entry.client.id!, DateTime.now().toUtc().toIso8601String());
    _snack('Client removed');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _visible;
    return Scaffold(
      backgroundColor: AppColors.slate50,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Clients',
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.slate900)),
                ),
                FilledButton.icon(
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Add client'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Saved clients, plus clients used on past invoices that are not saved yet.',
              style: TextStyle(color: AppColors.slate500),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search by name, GSTIN or address',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text('Could not load clients: $_error'))
                      : items.isEmpty
                          ? const Center(
                              child: Text('No clients yet.',
                                  style: TextStyle(color: AppColors.slate500)))
                          : ListView.separated(
                              controller: claudeScroll,
                              itemCount: items.length,
                              separatorBuilder: (context, index) => const SizedBox(height: 8),
                              itemBuilder: (_, i) => ClaudeHighlight(
                                focusKey: UiEventStore.clientFocus(items[i].client.id ?? 0),
                                borderRadius: BorderRadius.circular(10),
                                child: _tile(items[i]),
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(_Entry e) {
    final c = e.client;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slate200),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: e.saved ? AppColors.indigo50 : AppColors.slate100,
          child: Icon(e.saved ? Icons.business : Icons.history,
              color: e.saved ? AppColors.indigo600 : AppColors.slate500),
        ),
        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (c.gstin.isNotEmpty) 'GSTIN ${c.gstin}',
            if (c.address.isNotEmpty) c.address,
            if (c.email.isNotEmpty) c.email,
            '${e.invoiceCount} invoice${e.invoiceCount == 1 ? '' : 's'}',
            if (!e.saved) 'not saved',
          ].join('  ·  '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: e.saved
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _edit(entry: e)),
                IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(e)),
              ])
            : TextButton.icon(
                onPressed: () => _edit(entry: e),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save'),
              ),
      ),
    );
  }
}

class _ClientDialog extends StatefulWidget {
  final ClientModel? initial;
  const _ClientDialog({this.initial});

  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _address = TextEditingController(text: widget.initial?.address ?? '');
  late final _gstin = TextEditingController(text: widget.initial?.gstin ?? '');
  late final _email = TextEditingController(text: widget.initial?.email ?? '');

  @override
  void dispose() {
    for (final c in [_name, _address, _gstin, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration deco(String label) =>
        InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true);
    return AlertDialog(
      title: Text(widget.initial?.id == null ? 'Save client' : 'Edit client'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              decoration: deco('Name *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _address, decoration: deco('Address'), maxLines: 2),
            const SizedBox(height: 12),
            TextFormField(
              controller: _gstin,
              decoration: deco('GSTIN'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _email, decoration: deco('Email')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(
              context,
              ClientModel(
                id: widget.initial?.id,
                name: _name.text.trim(),
                address: _address.text.trim(),
                gstin: _gstin.text.trim().toUpperCase(),
                email: _email.text.trim(),
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

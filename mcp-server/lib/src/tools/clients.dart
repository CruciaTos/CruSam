import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';
import 'shared.dart';

/// Clients (invoice recipients). "saved" clients live in the clients table;
/// "invoice_history" clients are names that only appear on past invoices.
class ClientTools extends ToolGroup {
  final ToolContext ctx;
  ClientTools(this.ctx);

  @override
  List<ToolDef> get tools => [_find, _list, _create, _update, _delete];

  static final _fields = {
    'name': Schema.string(description: 'Client name as it should appear on invoices, e.g. "M/s Acme Pvt. Ltd.".'),
    'address': Schema.string(description: 'Billing address.'),
    'gstin': Schema.string(description: '15-character GSTIN.'),
    'email': Schema.string(description: 'Email for sending invoices.'),
  };

  late final _find = ToolDef(
    Tool(
      name: 'find_clients',
      description: 'Fuzzy search clients by name, GSTIN or address (handles '
          'typos and partial names). Covers saved clients and clients used on '
          'past invoices. Use before create_invoice; pass the exact returned '
          'name (or saved id) to create_invoice.',
      annotations: readOnlyTool('Find clients'),
      inputSchema: Schema.object(properties: {
        'query': Schema.string(description: 'Name, part of a name, or GSTIN.'),
        'limit': Schema.int(description: '1-20, default 5.'),
      }, required: ['query']),
    ),
    (a) async {
      a.rejectUnknown(['query', 'limit']);
      final q = a.str('query', required: true, maxLength: 300);
      final limit = a.integer('limit', min: 1, max: 20) ?? 5;
      a.check();
      final known = await knownClients(ctx.db);
      final ql = q!.toLowerCase();
      final scored = <(int, double)>[];
      for (var i = 0; i < known.length; i++) {
        final c = known[i].client;
        var s = FuzzyName.score(q, c.name);
        if (c.gstin.toLowerCase() == ql) s = 1;
        if (c.name.toLowerCase().contains(ql) && s < 0.9) s = 0.9;
        if (c.address.toLowerCase().contains(ql) && s < 0.6) s = 0.6;
        if (s >= 0.45) scored.add((i, s));
      }
      scored.sort((x, y) => y.$2.compareTo(x.$2));
      return {
        'query': q,
        'matches': [
          for (final (i, s) in scored.take(limit))
            {
              ...clientJson(known[i].client,
                  source: known[i].source, invoices: known[i].invoices),
              'score': s,
            },
        ],
        if (scored.isEmpty)
          'hint': 'No match. If this is a new client, confirm the details '
              'with the user, then call create_client.',
      };
    },
  );

  late final _list = ToolDef(
    Tool(
      name: 'list_clients',
      description: 'All known clients (saved + seen on invoices) with invoice counts.',
      annotations: readOnlyTool('List clients'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      final known = await knownClients(ctx.db);
      return {
        'count': known.length,
        'clients': [
          for (final k in known)
            clientJson(k.client, source: k.source, invoices: k.invoices),
        ],
      };
    },
  );

  late final _create = ToolDef(
    Tool(
      name: 'create_client',
      description: 'Save a new client. Only call after the user explicitly '
          'confirmed this is a new client (not a misspelling of an existing '
          'one). Refuses names that closely match an existing client unless '
          'allow_similar=true.',
      annotations: writeTool('Create client'),
      inputSchema: Schema.object(properties: {
        ..._fields,
        'allow_similar': Schema.bool(
            description: 'Set true only if the user confirmed a similarly '
                'named existing client is a different company.'),
      }, required: ['name']),
    ),
    (a) async {
      a.rejectUnknown(['name', 'address', 'gstin', 'email', 'allow_similar']);
      final c = _readClient(a, requireName: true);
      final allowSimilar = a.boolean('allow_similar');
      a.check();
      final known = await knownClients(ctx.db);
      final warnings = <String>[];
      for (final k in known) {
        if (k.source == 'saved' &&
            k.client.name.toLowerCase() == c.name.toLowerCase()) {
          throw ToolError('A saved client named "${k.client.name}" already '
              'exists (id ${k.client.id}). Use update_client to change it.');
        }
      }
      final similar = known.where((k) =>
          k.client.name.toLowerCase() != c.name.toLowerCase() &&
          FuzzyName.score(c.name, k.client.name) >= 0.8);
      if (similar.isNotEmpty && !allowSimilar) {
        throw ToolError('Refused: "${c.name}" is very similar to existing '
            '${similar.map((k) => '"${k.client.name}"').join(', ')}. If it is '
            'the same client, use that name. If the user confirms it is '
            'different, retry with allow_similar=true.');
      }
      if (c.gstin.isNotEmpty && !gstinPattern.hasMatch(c.gstin)) {
        warnings.add('GSTIN "${c.gstin}" does not look like a valid 15-character GSTIN.');
      }
      final now = ctx.nowUtcIso();
      final id = await ctx.store.write((txn) => ClientStore.insert(
          txn,
          ClientModel(
              name: c.name,
              address: c.address,
              gstin: c.gstin,
              email: c.email,
              createdAt: now,
              updatedAt: now)));
      final saved = await ClientStore.getById(ctx.db, id);
      return {
        'created': true,
        'client': clientJson(saved!),
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
    },
  );

  late final _update = ToolDef(
    Tool(
      name: 'update_client',
      description: 'Change a saved client\'s details. Does not change past '
          'invoices (each invoice keeps its own copy of the client details).',
      annotations: writeTool('Update client', idempotent: true),
      inputSchema: Schema.object(
          properties: {'id': Schema.int(description: 'Saved client id.'), ..._fields},
          required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'name', 'address', 'gstin', 'email']);
      final id = a.integer('id', required: true, min: 1);
      final fields = <String, Object?>{};
      for (final k in ['name', 'address', 'gstin', 'email']) {
        if (a.has(k)) {
          final v = a.str(k, required: k == 'name', allowEmpty: k != 'name');
          if (v != null) fields[k] = k == 'gstin' ? v.toUpperCase() : v;
        }
      }
      if (fields.isEmpty) a.errors.add('Pass at least one of name, address, gstin, email.');
      a.check();
      if (await ClientStore.getById(ctx.db, id!) == null) {
        throw ToolError('No saved client with id $id.');
      }
      fields['updated_at'] = ctx.nowUtcIso();
      await ctx.store.write((txn) => ClientStore.update(txn, id, fields));
      return {'updated': true, 'client': clientJson((await ClientStore.getById(ctx.db, id))!)};
    },
  );

  late final _delete = ToolDef(
    Tool(
      name: 'delete_client',
      description: 'Remove a saved client from the address book (soft '
          'delete). Past invoices are not affected. Requires confirm=true.',
      annotations: writeTool('Delete client', destructive: true, idempotent: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Saved client id.'),
        'confirm': confirmSchema(),
      }, required: ['id', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'confirm']);
      final id = a.integer('id', required: true, min: 1);
      requireConfirm(a, 'delete this client');
      a.check();
      final c = await ClientStore.getById(ctx.db, id!);
      if (c == null) throw ToolError('No saved client with id $id.');
      await ctx.store.write((txn) => ClientStore.softDelete(txn, id, ctx.nowUtcIso()));
      return {'deleted': true, 'client': clientJson(c)};
    },
  );

  ClientModel _readClient(Args a, {required bool requireName}) => ClientModel(
        name: a.str('name', required: requireName, maxLength: 300) ?? '',
        address: a.str('address', allowEmpty: true, maxLength: 1000) ?? '',
        gstin: (a.str('gstin', allowEmpty: true, maxLength: 20) ?? '').toUpperCase(),
        email: a.str('email', allowEmpty: true, maxLength: 300) ?? '',
      );
}

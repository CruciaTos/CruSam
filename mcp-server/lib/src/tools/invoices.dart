import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';
import 'shared.dart';

/// Invoices = the app's "vouchers": a tax invoice whose line items are
/// employees paid for a period (plus the bank details used for the bank
/// disbursement sheet). Totals: base = sum(rows), CGST 9% + SGST 9%,
/// final rounded to the nearest rupee.
class InvoiceTools extends ToolGroup {
  final ToolContext ctx;
  InvoiceTools(this.ctx);

  static const _rowFields = [
    'employee_id', 'employee_name', 'amount', 'from_date', 'to_date'
  ];
  static const _headerFields = [
    'title', 'date', 'dept_code', 'item_description', 'bill_no', 'po_no',
    'client_id', 'client_name', 'client_address', 'client_gstin', 'client_email',
  ];

  @override
  List<ToolDef> get tools => [_list, _get, _create, _update, _delete];

  // ── Schemas ────────────────────────────────────────────────────────────────

  static final _rowSchema = Schema.object(
    description: 'One line item: an employee billed for a period.',
    properties: {
      'employee_id': Schema.int(
          description: 'CruSam employee id from find_employees / '
              'match_employees. Bank details are copied from the employee record.'),
      'employee_name': Schema.string(
          description: 'Only when the person is not in CruSam and '
              'allow_unlinked_employees is true. Otherwise omit.'),
      'amount': Schema.num(
          description: 'Amount in rupees as a JSON number (e.g. 19222), '
              'before tax. No quotes, commas or currency symbols.'),
      'from_date': isoDateSchema('Period start.'),
      'to_date': isoDateSchema('Period end (on or after from_date).'),
    },
    required: ['amount', 'from_date', 'to_date'],
  );

  static Map<String, Schema> _headerProps({required bool forUpdate}) => {
        'title': Schema.string(
            description: 'Voucher title shown in the app (required by the app). '
                '${forUpdate ? '' : 'If the source has none, ask the user; a PO-based title such as "PO 700042550" is a reasonable suggestion.'}'),
        'date': isoDateSchema('Invoice date.'),
        'dept_code': Schema.string(
            description: 'Department code: one of ${AppDefaults.deptCodes.join(', ')}. '
                '${forUpdate ? '' : 'Defaults to ${AppDefaults.deptCodes.first} if omitted (the app default).'}'),
        'item_description': Schema.string(
            description: 'Invoice item description. See get_app_overview for the '
                'standard ones. ${forUpdate ? '' : 'Defaults to the app default (the first standard description).'}'),
        'bill_no': Schema.string(
            description: 'Invoice / bill number. The app has no automatic '
                'numbering; leave empty if the source has none.'),
        'po_no': Schema.string(description: 'Purchase order number, e.g. 700042550.'),
        'client_id': Schema.int(description: 'Saved client id from find_clients.'),
        'client_name': Schema.string(
            description: 'Exact name of a known client (saved or used on a past '
                'invoice). Unknown names are refused: use find_clients, and '
                'create_client only after the user confirms a new client.'),
        'client_address': Schema.string(description: 'Overrides the client address on this invoice only.'),
        'client_gstin': Schema.string(description: 'Overrides the client GSTIN on this invoice only.'),
        'client_email': Schema.string(description: 'Overrides the client email on this invoice only.'),
        'rows': Schema.list(
            description: forUpdate
                ? 'If given, REPLACES all line items.'
                : 'Line items, at least one.',
            items: _rowSchema),
        'allow_unlinked_employees': Schema.bool(
            description: 'Allow rows with employee_name but no employee_id '
                '(no bank details). Default false.'),
        'dry_run': Schema.bool(
            description: 'true = validate and return exactly what would be '
                'saved (totals, duplicates) without writing. false = write. '
                'Always do a dry run first and show it to the user.'),
        'allow_duplicate': Schema.bool(
            description: 'Set true only if the user confirmed that a flagged '
                'duplicate is intentional. Default false.'),
      };

  // ── list_invoices ──────────────────────────────────────────────────────────

  late final _list = ToolDef(
    Tool(
      name: 'list_invoices',
      description: 'Search saved invoices (newest first). Use to review '
          'invoices or check for duplicates before creating one. Returns a '
          'compact summary per invoice; call get_invoice for line items.',
      annotations: readOnlyTool('List invoices'),
      inputSchema: Schema.object(properties: {
        'client': Schema.string(description: 'Substring of client name or GSTIN.'),
        'date_from': isoDateSchema('Invoice date on/after.'),
        'date_to': isoDateSchema('Invoice date on/before.'),
        'status': Schema.string(description: 'saved or draft.'),
        'bill_no': Schema.string(description: 'Exact bill/invoice number.'),
        'po_no': Schema.string(description: 'Exact PO number.'),
        'employee': Schema.string(description: 'Substring of an employee name on any line.'),
        'include_deleted': Schema.bool(description: 'Include deleted invoices. Default false.'),
        'limit': Schema.int(description: '1-200, default 50.'),
        'offset': Schema.int(description: 'For paging, default 0.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['client', 'date_from', 'date_to', 'status', 'bill_no',
          'po_no', 'employee', 'include_deleted', 'limit', 'offset']);
      final f = InvoiceFilter(
        client: a.str('client'),
        dateFrom: a.date('date_from'),
        dateTo: a.date('date_to'),
        status: a.oneOf('status', ['saved', 'draft']),
        billNo: a.str('bill_no'),
        poNo: a.str('po_no'),
        employee: a.str('employee'),
        includeDeleted: a.boolean('include_deleted'),
        limit: a.integer('limit', min: 1, max: 200) ?? 50,
        offset: a.integer('offset', min: 0) ?? 0,
      );
      a.check();
      final (items, total) = await VoucherStore.search(ctx.db, f);
      return {
        'total_matches': total,
        'returned': items.length,
        'invoices': [for (final v in items) invoiceSummary(v)],
      };
    },
  );

  // ── get_invoice ────────────────────────────────────────────────────────────

  late final _get = ToolDef(
    Tool(
      name: 'get_invoice',
      description: 'Full details of one invoice: header, client, totals and '
          'every line item with bank details.',
      annotations: readOnlyTool('Get invoice'),
      inputSchema: Schema.object(
          properties: {'id': Schema.int(description: 'Invoice id.')},
          required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id']);
      final id = a.integer('id', required: true, min: 1);
      a.check();
      final v = await VoucherStore.getById(ctx.db, id!, includeDeleted: true);
      if (v == null) throw ToolError('No invoice with id $id.');
      return invoiceDetail(v, withBank: true);
    },
  );

  // ── create_invoice ─────────────────────────────────────────────────────────

  late final _create = ToolDef(
    Tool(
      name: 'create_invoice',
      description: 'Create one invoice exactly as the app\'s Voucher Builder '
          'saves it (same totals, tax, status and fields).\n'
          'Workflow: 1) resolve every employee with match_employees and the '
          'client with find_clients; 2) call with dry_run=true and show the '
          'user the rows and totals; 3) after the user confirms, call again '
          'with dry_run=false and identical data.\n'
          'Refuses (unless allow_duplicate=true) when an invoice with the same '
          'bill_no, or the same client + date + final total, already exists.',
      annotations: writeTool('Create invoice'),
      inputSchema: Schema.object(
        properties: _headerProps(forUpdate: false),
        required: ['title', 'date', 'rows', 'dry_run'],
      ),
    ),
    (a) async {
      a.rejectUnknown([..._headerFields, 'rows', 'allow_unlinked_employees',
          'dry_run', 'allow_duplicate']);
      final dryRun = a.boolean('dry_run', required: true);
      final allowDup = a.boolean('allow_duplicate');
      final defaults = <String>[];
      final title = a.str('title', required: true, maxLength: 200);
      final date = a.date('date', required: true);
      var dept = a.oneOf('dept_code', AppDefaults.deptCodes);
      if (!a.has('dept_code')) {
        dept = AppDefaults.deptCodes.first;
        defaults.add('dept_code=$dept');
      }
      var item = a.str('item_description', maxLength: 500);
      if (item == null || item.isEmpty) {
        item = AppDefaults.itemDescriptions.first;
        defaults.add('item_description="$item"');
      }
      final billNo = a.str('bill_no', allowEmpty: true, maxLength: 100) ?? '';
      final poNo = a.str('po_no', allowEmpty: true, maxLength: 100) ?? '';
      final rowArgs = a.objects('rows', required: true, minItems: 1);
      final allowUnlinked = a.boolean('allow_unlinked_employees');
      final client = await resolveClient(ctx.db, a);
      final rows = rowArgs == null
          ? null
          : await _buildRows(ctx.db, a, rowArgs, dept ?? '', allowUnlinked);
      a.check();

      final draft = VoucherModel(
        title: title!,
        date: date!,
        deptCode: dept!,
        itemDescription: item,
        billNo: billNo,
        poNo: poNo,
        clientName: client!.name,
        clientAddress: client.address,
        clientGstin: client.gstin,
        clientEmail: client.email,
        rows: rows!.rows,
      );
      return _saveFlow(
        draft: draft,
        existingId: null,
        dryRun: dryRun,
        allowDuplicate: allowDup,
        warnings: [...client.warnings, ...rows.warnings],
        defaults: defaults,
      );
    },
  );

  // ── update_invoice ─────────────────────────────────────────────────────────

  late final _update = ToolDef(
    Tool(
      name: 'update_invoice',
      description: 'Change an existing invoice. Only the fields you pass '
          'change; passing rows replaces ALL line items. Totals are '
          'recomputed. Use dry_run=true first and confirm with the user. '
          'If the invoice is open in the app\'s Voucher Builder, saving there '
          'afterwards would overwrite this change.',
      annotations: writeTool('Update invoice', destructive: true),
      inputSchema: Schema.object(
        properties: {
          'id': Schema.int(description: 'Invoice id.'),
          ..._headerProps(forUpdate: true),
        },
        required: ['id', 'dry_run'],
      ),
    ),
    (a) async {
      a.rejectUnknown(['id', ..._headerFields, 'rows',
          'allow_unlinked_employees', 'dry_run', 'allow_duplicate']);
      final id = a.integer('id', required: true, min: 1);
      final dryRun = a.boolean('dry_run', required: true);
      final allowDup = a.boolean('allow_duplicate');
      a.check();
      final existing = await VoucherStore.getById(ctx.db, id!);
      if (existing == null) throw ToolError('No (non-deleted) invoice with id $id.');

      final title = a.has('title') ? a.str('title', required: true, maxLength: 200) : null;
      final date = a.has('date') ? a.date('date', required: true) : null;
      final dept = a.has('dept_code') ? a.oneOf('dept_code', AppDefaults.deptCodes, required: true) : null;
      final item = a.has('item_description') ? a.str('item_description', required: true, maxLength: 500) : null;
      final billNo = a.has('bill_no') ? a.str('bill_no', allowEmpty: true, maxLength: 100) : null;
      final poNo = a.has('po_no') ? a.str('po_no', allowEmpty: true, maxLength: 100) : null;
      final clientChanged = a.has('client_id') || a.has('client_name') ||
          a.has('client_address') || a.has('client_gstin') || a.has('client_email');
      final client = clientChanged
          ? await resolveClient(ctx.db, a, fallbackName: existing.clientName)
          : null;
      final rowArgs = a.has('rows') ? a.objects('rows', minItems: 1) : null;
      final rows = rowArgs == null
          ? null
          : await _buildRows(ctx.db, a, rowArgs, dept ?? existing.deptCode,
              a.boolean('allow_unlinked_employees'));
      a.check();

      var draft = existing.copyWith(
        title: title,
        date: date,
        deptCode: dept,
        itemDescription: item,
        billNo: billNo,
        poNo: poNo,
        clientName: client?.name,
        clientAddress: client?.address,
        clientGstin: client?.gstin,
        clientEmail: client?.email,
        rows: rows?.rows,
      );
      if (dept != null && rows == null) {
        // Rows carry the voucher's dept code (set when the row was added).
        draft = draft.copyWith(
            rows: [for (final r in draft.rows) r.copyWith(deptCode: dept)]);
      }
      return _saveFlow(
        draft: draft,
        existingId: id,
        dryRun: dryRun,
        allowDuplicate: allowDup,
        warnings: [...?client?.warnings, ...?rows?.warnings],
        defaults: const [],
      );
    },
  );

  // ── delete_invoice ─────────────────────────────────────────────────────────

  late final _delete = ToolDef(
    Tool(
      name: 'delete_invoice',
      description: 'Delete an invoice the same way the app does (soft delete: '
          'hidden everywhere, row kept with is_deleted=1). Requires '
          'confirm=true after the user explicitly approves.',
      annotations: writeTool('Delete invoice', destructive: true, idempotent: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Invoice id.'),
        'confirm': confirmSchema(),
      }, required: ['id', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'confirm']);
      final id = a.integer('id', required: true, min: 1);
      requireConfirm(a, 'delete this invoice');
      a.check();
      final existing = await VoucherStore.getById(ctx.db, id!);
      if (existing == null) throw ToolError('No (non-deleted) invoice with id $id.');
      await ctx.store.write((txn) =>
          VoucherStore.softDelete(txn, id, ctx.nowUtcIso(), ctx.userEmail));
      return {'deleted': true, 'invoice': invoiceSummary(existing)};
    },
  );

  // ── Shared create/update logic ─────────────────────────────────────────────

  Future<({List<VoucherRowModel> rows, List<String> warnings})?> _buildRows(
    DatabaseExecutor db,
    Args a,
    List<Map<String, Object?>> rowArgs,
    String deptCode,
    bool allowUnlinked,
  ) async {
    final config = await ctx.companyConfig(db);
    final rows = <VoucherRowModel>[];
    final warnings = <String>[];
    final seenEmployees = <int, int>{};
    final base = ctx.clock().microsecondsSinceEpoch;
    for (var i = 0; i < rowArgs.length; i++) {
      final r = a.nested(rowArgs[i], 'rows[$i]');
      r.rejectUnknown(_rowFields);
      final empId = r.integer('employee_id', min: 1);
      final name = r.str('employee_name', maxLength: 200);
      final amount = r.money('amount', required: true);
      final from = r.date('from_date', required: true);
      final to = r.date('to_date', required: true);
      if (from != null && to != null && to.compareTo(from) < 0) {
        a.errors.add('rows[$i]: to_date $to is before from_date $from.');
      }
      var row = VoucherFactory.blankRow(
          rowId: '${base + i}', deptCode: deptCode, config: config);
      if (empId != null) {
        final m = await EmployeeStore.getRow(db, empId);
        if (m == null) {
          a.errors.add('rows[$i].employee_id: no active employee with id '
              '$empId. Use match_employees to find the right id.');
          continue;
        }
        final emp = EmployeeModel.fromMap(m);
        row = VoucherFactory.applyEmployee(row, emp);
        if (name != null && name.isNotEmpty &&
            FuzzyName.score(name, emp.name) < 0.6) {
          warnings.add('rows[$i]: employee_name "$name" does not look like '
              'employee $empId "${emp.name}". The employee record was used.');
        }
        if (emp.accountNumber.trim().isEmpty || emp.ifscCode.trim().isEmpty) {
          warnings.add('rows[$i]: ${emp.name} has no bank account/IFSC on '
              'file, so the bank sheet will be incomplete.');
        }
        final prev = seenEmployees[empId];
        if (prev != null) {
          warnings.add('rows[$i]: ${emp.name} also appears in rows[$prev].');
        } else {
          seenEmployees[empId] = i;
        }
      } else if (name != null && name.isNotEmpty) {
        if (!allowUnlinked) {
          a.errors.add('rows[$i]: employee_id is required. "$name" was given '
              'without an id: call match_employees to resolve it, or set '
              'allow_unlinked_employees=true if the user confirmed this '
              'person is not in CruSam.');
          continue;
        }
        row = row.copyWith(employeeName: name);
        warnings.add('rows[$i]: "$name" is not linked to an employee record '
            '(no bank details).');
      } else {
        a.errors.add('rows[$i]: employee_id is required.');
        continue;
      }
      if (amount != null && from != null && to != null) {
        rows.add(row.copyWith(amount: amount, fromDate: from, toDate: to));
      }
    }
    return (rows: rows, warnings: warnings);
  }

  Future<Map<String, Object?>> _saveFlow({
    required VoucherModel draft,
    required int? existingId,
    required bool dryRun,
    required bool allowDuplicate,
    required List<String> warnings,
    required List<String> defaults,
  }) async {
    final nowUtc = ctx.nowUtcIso();
    final prepared = VoucherFactory.prepareForSave(
      draft,
      nowUtcIso: nowUtc,
      userEmail: ctx.userEmail,
      newCloudId: ctx.newUuid,
    );

    Future<List<DuplicateMatch>> dupes(DatabaseExecutor db) =>
        VoucherStore.findDuplicates(
          db,
          billNo: prepared.billNo,
          clientName: prepared.clientName,
          date: prepared.date,
          finalTotal: prepared.finalTotal,
          excludeId: existingId,
        );

    final poWarnings = <String>[];
    if (prepared.poNo.trim().isNotEmpty) {
      final (samePo, _) = await VoucherStore.search(
          ctx.db, InvoiceFilter(poNo: prepared.poNo, limit: 20));
      final others = samePo.where((v) => v.id != existingId).toList();
      if (others.isNotEmpty) {
        poWarnings.add('PO ${prepared.poNo} is already used on invoice(s) '
            '${others.map((v) => '#${v.id} (${v.date}, ₹${v.finalTotal.toStringAsFixed(0)})').join(', ')}. '
            'That can be normal for a PO billed in parts; check it is not a re-entry.');
      }
    }

    Map<String, Object?> body(List<DuplicateMatch> d, {int? id}) => {
          'dry_run': dryRun,
          if (!dryRun) (existingId == null ? 'created' : 'updated'): true,
          'invoice': invoiceDetail(id == null ? prepared : prepared.copyWith(id: id),
              withBank: false),
          'invoice_number': prepared.billNo.isEmpty ? null : prepared.billNo,
          if (d.isNotEmpty) 'duplicates': [for (final x in d) x.toJson()],
          if (defaults.isNotEmpty) 'defaults_applied': defaults,
          if (warnings.isNotEmpty || poWarnings.isNotEmpty)
            'warnings': [...warnings, ...poWarnings],
          if (!dryRun)
            'note': 'Saved. The CruSam app, if open, shows it within a '
                'second or two.',
        };

    if (dryRun) {
      final d = await dupes(ctx.db);
      final res = body(d);
      if (d.isNotEmpty && !allowDuplicate) {
        res['would_be_refused'] = 'Possible duplicate. Saving with '
            'dry_run=false will fail unless allow_duplicate=true.';
      }
      return res;
    }

    return ctx.store.write((txn) async {
      // Re-check inside the write transaction so a concurrent save can't slip in.
      final d = await dupes(txn);
      if (d.isNotEmpty && !allowDuplicate) {
        throw ToolError('Refused: this looks like a duplicate of '
            '${d.map((x) => 'invoice #${x.id} (${x.reason}; bill_no "${x.billNo}", '
                '${x.clientName}, ${x.date}, ₹${x.finalTotal.toStringAsFixed(2)})').join('; ')}. '
            'Nothing was saved. If the user confirms it is intentional, retry '
            'with allow_duplicate=true.');
      }
      int id;
      if (existingId == null) {
        id = await VoucherStore.insertWithRows(txn, prepared);
      } else {
        id = existingId;
        await VoucherStore.updateWithRows(txn, id, prepared);
      }
      return body(d, id: id);
    });
  }
}

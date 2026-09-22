import 'package:crusam_core/crusam_core.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../tool_kit.dart';

// ── Output shapes ─────────────────────────────────────────────────────────────

Map<String, Object?> invoiceSummary(VoucherModel v) => {
      'id': v.id,
      'title': v.title,
      'date': v.date,
      'bill_no': v.billNo,
      'po_no': v.poNo,
      'client_name': v.clientName,
      'dept_code': v.deptCode,
      'row_count': v.rows.length,
      'final_total': v.finalTotal,
      'status': v.status.name,
      if (v.isDeleted) 'deleted': true,
    };

Map<String, Object?> invoiceDetail(VoucherModel v, {required bool withBank}) => {
      if (v.id != null) 'id': v.id,
      'title': v.title,
      'date': v.date,
      'bill_no': v.billNo,
      'po_no': v.poNo,
      'dept_code': v.deptCode,
      'item_description': v.itemDescription,
      'status': v.status.name,
      'client': {
        'name': v.clientName,
        'address': v.clientAddress,
        'gstin': v.clientGstin,
        'email': v.clientEmail,
      },
      'totals': {
        'base_total': v.baseTotal,
        'cgst_9pct': v.cgst,
        'sgst_9pct': v.sgst,
        'total_tax': v.totalTax,
        'round_off': v.roundOff,
        'final_total': v.finalTotal,
      },
      'row_count': v.rows.length,
      'rows': [
        for (final r in v.rows)
          {
            'employee_id': int.tryParse(r.employeeId),
            'employee_name': r.employeeName,
            'amount': r.amount,
            'from_date': r.fromDate,
            'to_date': r.toDate,
            if (withBank) ...{
              'ifsc': r.ifscCode,
              'account': r.accountNumber,
              'bank': r.bankDetails,
              'branch': r.branch,
            },
          },
      ],
      if (v.createdBy.isNotEmpty) 'created_by': v.createdBy,
      if (v.isDeleted) 'deleted_at': v.deletedAt,
    };

Map<String, Object?> clientJson(ClientModel c, {String? source, int? invoices}) => {
      if (c.id != null) 'id': c.id,
      'name': c.name,
      'address': c.address,
      'gstin': c.gstin,
      'email': c.email,
      if (source != null) 'source': source,
      if (invoices != null) 'invoice_count': invoices,
    };

// ── Client resolution ─────────────────────────────────────────────────────────

class ResolvedClient {
  final String name, address, gstin, email;
  final List<String> warnings;
  ResolvedClient(this.name, this.address, this.gstin, this.email, this.warnings);
}

Future<bool> clientsTableExists(DatabaseExecutor db) async => (await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name='clients'"))
    .isNotEmpty;

/// All known clients: saved ones first, then ones only seen on invoices.
Future<List<({ClientModel client, String source, int invoices})>> knownClients(
    DatabaseExecutor db) async {
  final out = <({ClientModel client, String source, int invoices})>[];
  final seen = <String>{};
  final history = await ClientStore.fromInvoices(db);
  final counts = {
    for (final (c, n) in history) c.name.trim().toLowerCase(): n,
  };
  if (await clientsTableExists(db)) {
    for (final c in await ClientStore.listSaved(db)) {
      final key = c.name.trim().toLowerCase();
      seen.add(key);
      out.add((client: c, source: 'saved', invoices: counts[key] ?? 0));
    }
  }
  for (final (c, n) in history) {
    if (seen.add(c.name.trim().toLowerCase())) {
      out.add((client: c, source: 'invoice_history', invoices: n));
    }
  }
  return out;
}

/// Resolves the client for an invoice from client_id / client_name (+
/// optional per-invoice overrides). Unknown names are refused so new clients
/// are always created explicitly.
Future<ResolvedClient?> resolveClient(DatabaseExecutor db, Args a,
    {String? fallbackName}) async {
  final warnings = <String>[];
  final id = a.integer('client_id', min: 1);
  final name = a.str('client_name', maxLength: 300);
  final address = a.has('client_address') ? a.str('client_address', allowEmpty: true, maxLength: 1000) : null;
  final gstin = a.has('client_gstin') ? a.str('client_gstin', allowEmpty: true, maxLength: 20)?.toUpperCase() : null;
  final email = a.has('client_email') ? a.str('client_email', allowEmpty: true, maxLength: 300) : null;
  if (gstin != null && gstin.isNotEmpty && !gstinPattern.hasMatch(gstin)) {
    warnings.add('client_gstin "$gstin" does not look like a valid 15-character GSTIN.');
  }

  ClientModel? base;
  if (id != null) {
    base = await clientsTableExists(db) ? await ClientStore.getById(db, id) : null;
    if (base == null) {
      a.errors.add('client_id: no saved client with id $id. Use find_clients.');
      return null;
    }
    if (name != null && name.isNotEmpty &&
        name.toLowerCase() != base.name.toLowerCase()) {
      a.errors.add('client_name "$name" does not match client_id $id '
          '("${base.name}"). Pass only one of them.');
      return null;
    }
  } else {
    final wanted = (name == null || name.isEmpty) ? fallbackName : name;
    if (wanted == null || wanted.isEmpty) {
      a.errors.add('client_name or client_id: required. Use find_clients to '
          'look up the client.');
      return null;
    }
    final known = await knownClients(db);
    for (final k in known) {
      if (k.client.name.trim().toLowerCase() == wanted.trim().toLowerCase()) {
        base = k.client;
        break;
      }
    }
    if (base == null) {
      final ranked = FuzzyName.rank(
          wanted, [for (final k in known) k.client.name], minScore: 0.4, limit: 3);
      a.errors.add('client_name: "$wanted" is not a known client. '
          '${ranked.isEmpty ? '' : 'Closest: ${ranked.map((r) => '"${known[r.$1].client.name}"').join(', ')}. '}'
          'If it is one of these, pass that exact name. If it is genuinely new, '
          'ask the user to confirm and call create_client first.');
      return null;
    }
  }
  for (final (field, given, stored) in [
    ('client_address', address, base.address),
    ('client_gstin', gstin, base.gstin),
    ('client_email', email, base.email),
  ]) {
    if (given != null && stored.isNotEmpty && given != stored) {
      warnings.add('$field overridden for this invoice only '
          '(saved value: "$stored").');
    }
  }
  return ResolvedClient(
    base.name,
    address ?? base.address,
    gstin ?? base.gstin,
    email ?? base.email,
    warnings,
  );
}

final gstinPattern = RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][A-Z\d]Z[A-Z\d]$');

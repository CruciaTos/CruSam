import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';

/// App overview + company settings, salary formula settings and the invoice
/// item-description list (Settings / Salary Formula screens).
class SettingsTools extends ToolGroup {
  final ToolContext ctx;
  SettingsTools(this.ctx);

  @override
  List<ToolDef> get tools => [
        _overview,
        _getCompany,
        _updateCompany,
        _getFormula,
        _updateFormula,
        _listItems,
        _addItem,
        _deleteItem,
      ];

  static const _companyFields = {
    'company_name': 'Company name on invoices.',
    'address': 'Company address.',
    'gstin': 'Company GSTIN.',
    'pan': 'Company PAN.',
    'jurisdiction': 'Jurisdiction city.',
    'declaration_text': 'Declaration printed on invoices.',
    'bank_name': 'Company bank name (debit bank for bank sheets).',
    'branch': 'Company bank branch.',
    'account_no': 'Company account number (debit account on invoice rows).',
    'ifsc_code': 'Company bank IFSC.',
    'phone': 'Phone number.',
  };

  // name → (description, max)
  static const _formulaFields = {
    'pf_rate': ('Employee PF rate as a fraction (0.12 = 12%).', 1.0),
    'pf_basic_threshold': ('Earned basic at/above which PF is the flat cap.', 1e7),
    'pf_cap_amount': ('Flat PF once basic reaches the threshold.', 1e6),
    'esic_rate': ('Employee ESIC rate as a fraction (0.0075 = 0.75%).', 1.0),
    'esic_gross_threshold': ('Full gross above which ESIC does not apply.', 1e7),
    'pt_female_threshold': ('Female: no PT below this earned gross.', 1e7),
    'pt_male_tier1_threshold': ('Male: no PT below this earned gross.', 1e7),
    'pt_male_tier2_threshold': ('Male: tier-2 PT between tier1 and this.', 1e7),
    'pt_male_tier2_amount': ('Male tier-2 PT amount.', 1e5),
    'pt_standard_amount': ('Standard PT (non-February).', 1e5),
    'pt_feb_amount': ('February PT.', 1e5),
    'employer_pf_rate': ('Employer PF rate for Attachment A (0.13 = 13%).', 1.0),
    'employer_esic_rate': ('Employer ESIC rate for Attachment A (0.0325).', 1.0),
    'attachment_b_per_employee': ('Attachment B amount per active employee.', 1e6),
  };

  late final _overview = ToolDef(
    Tool(
      name: 'get_app_overview',
      description: 'Start here. What CruSam contains (record counts), '
          'business conventions (tax rates, department codes, standard item '
          'descriptions, default client), company details and server mode.',
      annotations: readOnlyTool('App overview'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      final db = ctx.db;
      Future<int> count(String sql) async =>
          (await db.rawQuery(sql)).first.values.first as int;
      final cfg = await ctx.companyConfig(db);
      final hasSnapshots = await ctx.store.hasTable(SalarySnapshotStore.tableSnapshots);
      return {
        'app': 'CruSam (Aarti Enterprises): employees, tax invoices billed per '
            'employee, salary statements/slips/bills, disbursements.',
        'server': {
          'database': ctx.store.config.dbPath,
          'writable': ctx.store.writable,
          if (ctx.store.config.readOnly) 'mode': 'read-only',
          if (ctx.store.schemaProblems.isNotEmpty)
            'schema_problems': ctx.store.schemaProblems,
          'user': ctx.userEmail,
        },
        'counts': {
          'employees': await count(
              'SELECT COUNT(*) FROM employees WHERE is_deleted = 0 OR is_deleted IS NULL'),
          'invoices': await count(
              'SELECT COUNT(*) FROM vouchers WHERE is_deleted = 0 OR is_deleted IS NULL'),
          'saved_salary_months': hasSnapshots
              ? await count('SELECT COUNT(*) FROM ${SalarySnapshotStore.tableSnapshots}')
              : 0,
        },
        'conventions': {
          'invoice_tax': 'CGST 9% + SGST 9% on the sum of row amounts; final '
              'total rounded to the nearest rupee.',
          'invoice_rows': 'Each row = one employee, amount and period; bank '
              'details copied from the employee.',
          'invoice_numbering': 'None automatic: bill_no is free text.',
          'dates': 'All tool dates are YYYY-MM-DD.',
          'dept_codes': AppDefaults.deptCodes,
          'employee_codes': EmployeeStore.codes,
          'standard_item_descriptions': AppDefaults.itemDescriptions,
          'default_client': AppDefaults.defaultClientName,
        },
        'company': _companyJson(cfg),
      };
    },
  );

  late final _getCompany = ToolDef(
    Tool(
      name: 'get_company_settings',
      description: 'Company details used on invoices and bank sheets.',
      annotations: readOnlyTool('Get company settings'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      return _companyJson(await ctx.companyConfig(ctx.db));
    },
  );

  late final _updateCompany = ToolDef(
    Tool(
      name: 'update_company_settings',
      description: 'Change company details (only fields passed). Affects '
          'invoices created afterwards (e.g. debit account on new rows) and '
          'all future PDFs.',
      annotations: writeTool('Update company settings', idempotent: true),
      inputSchema: Schema.object(properties: {
        for (final e in _companyFields.entries)
          e.key: Schema.string(description: e.value),
      }),
    ),
    (a) async {
      a.rejectUnknown(_companyFields.keys);
      final fields = <String, Object?>{};
      for (final k in _companyFields.keys) {
        if (a.has(k)) {
          final v = a.str(k, allowEmpty: true, maxLength: 2000);
          if (v != null) fields[k] = v;
        }
      }
      if (fields.isEmpty) a.errors.add('Pass at least one field to change.');
      a.check();
      await ctx.store.write((txn) => _upsertFirstRow(txn, 'company_config', fields));
      return {'updated': fields.keys.toList(), 'company': _companyJson(await ctx.companyConfig(ctx.db))};
    },
  );

  late final _getFormula = ToolDef(
    Tool(
      name: 'get_salary_formula_settings',
      description: 'PF / ESIC / Professional Tax / employer contribution '
          'constants used by every salary calculation.',
      annotations: readOnlyTool('Get salary formula'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      return (await _formula(ctx.db)).toMap()..remove('id');
    },
  );

  late final _updateFormula = ToolDef(
    Tool(
      name: 'update_salary_formula_settings',
      description: 'Change salary formula constants (only fields passed). '
          'Rates are fractions (0.12 = 12%). Affects all future salary '
          'calculations; saved salary months keep their stored numbers.',
      annotations: writeTool('Update salary formula', idempotent: true),
      inputSchema: Schema.object(properties: {
        for (final e in _formulaFields.entries)
          e.key: Schema.num(description: e.value.$1),
      }),
    ),
    (a) async {
      a.rejectUnknown(_formulaFields.keys);
      final fields = <String, Object?>{};
      for (final e in _formulaFields.entries) {
        if (a.has(e.key)) {
          final v = a.number(e.key, max: e.value.$2);
          if (v != null) fields[e.key] = v;
        }
      }
      if (fields.isEmpty) a.errors.add('Pass at least one field to change.');
      a.check();
      final before = (await _formula(ctx.db)).toMap();
      await ctx.store.write((txn) async {
        // Same as the app: make sure the single row exists with all
        // defaults, then change only the requested columns.
        final rows = await txn.query('salary_formula_config', columns: ['id'], limit: 1);
        if (rows.isEmpty) {
          await txn.insert('salary_formula_config', const SalaryFormulaConfigModel().toMap());
        }
        await _upsertFirstRow(txn, 'salary_formula_config', fields);
      });
      return {
        'changes': {
          for (final k in fields.keys) k: {'from': before[k], 'to': fields[k]},
        },
      };
    },
  );

  late final _listItems = ToolDef(
    Tool(
      name: 'list_item_descriptions',
      description: 'Invoice item descriptions offered in the Voucher Builder '
          '(built-in + custom).',
      annotations: readOnlyTool('List item descriptions'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      final rows = await ctx.db.query('item_descriptions', orderBy: 'id ASC');
      return {
        'items': [
          for (final r in rows)
            {'id': r['id'], 'text': r['text'], 'custom': r['is_custom'] == 1},
        ],
      };
    },
  );

  late final _addItem = ToolDef(
    Tool(
      name: 'add_item_description',
      description: 'Add a custom invoice item description to the dropdown list.',
      annotations: writeTool('Add item description'),
      inputSchema: Schema.object(
          properties: {'text': Schema.string(description: 'Description text.')},
          required: ['text']),
    ),
    (a) async {
      a.rejectUnknown(['text']);
      final text = a.str('text', required: true, maxLength: 500);
      a.check();
      final exists = await ctx.db.query('item_descriptions',
          where: 'LOWER(TRIM(text)) = ?', whereArgs: [text!.toLowerCase()], limit: 1);
      if (exists.isNotEmpty) {
        throw ToolError('That description already exists (id ${exists.first['id']}).');
      }
      final id = await ctx.store.write((txn) =>
          txn.insert('item_descriptions', {'text': text, 'is_custom': 1}));
      return {'created': true, 'id': id, 'text': text};
    },
  );

  late final _deleteItem = ToolDef(
    Tool(
      name: 'delete_item_description',
      description: 'Remove a custom item description (built-in ones cannot be '
          'removed). Existing invoices keep their text. Requires confirm=true.',
      annotations: writeTool('Delete item description', destructive: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Item description id.'),
        'confirm': confirmSchema(),
      }, required: ['id', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'confirm']);
      final id = a.integer('id', required: true, min: 1);
      requireConfirm(a, 'delete this item description');
      a.check();
      final rows = await ctx.db.query('item_descriptions', where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw ToolError('No item description with id $id.');
      if (rows.first['is_custom'] != 1) {
        throw ToolError('Item description $id is built-in and cannot be removed.');
      }
      await ctx.store.write((txn) => txn.delete('item_descriptions', where: 'id = ?', whereArgs: [id]));
      return {'deleted': true, 'id': id, 'text': rows.first['text']};
    },
  );

  static Map<String, Object?> _companyJson(CompanyConfigModel c) =>
      c.toMap()..remove('id');

  static Future<SalaryFormulaConfigModel> _formula(DatabaseExecutor db) async {
    final rows = await db.query('salary_formula_config', limit: 1);
    return rows.isEmpty
        ? const SalaryFormulaConfigModel()
        : SalaryFormulaConfigModel.fromMap(rows.first);
  }

  static Future<void> _upsertFirstRow(
      DatabaseExecutor db, String table, Map<String, Object?> fields) async {
    final existing = await db.query(table, columns: ['id'], limit: 1);
    if (existing.isEmpty) {
      await db.insert(table, fields);
    } else {
      await db.update(table, fields, where: 'id=?', whereArgs: [existing.first['id']]);
    }
  }
}

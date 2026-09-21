import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';

/// Salary module: calculate a month from attendance (same formulas as the
/// Employee Salary / Statement screens), save it as a "saved salary" month,
/// browse saved months, analytics, and bank disbursement records.
class SalaryTools extends ToolGroup {
  final ToolContext ctx;
  SalaryTools(this.ctx);

  @override
  List<ToolDef> get tools =>
      [_calculate, _listSaved, _getSaved, _rename, _deleteSaved, _analytics,
       _listDisb, _getDisb];

  static const _codesWithAll = ['All', ...EmployeeStore.codes];

  Future<SalaryFormulaConfigModel> _formula(DatabaseExecutor db) async {
    final rows = await db.query('salary_formula_config', limit: 1);
    return rows.isEmpty
        ? const SalaryFormulaConfigModel()
        : SalaryFormulaConfigModel.fromMap(rows.first);
  }

  Future<void> _requireSnapshots() async {
    if (!await ctx.store.hasTable(SalarySnapshotStore.tableSnapshots)) {
      throw const ToolError('No saved salary months yet (open the Saved '
          'Salary screen in the app once to initialise its tables).');
    }
  }

  static Map<String, Object?> _employeeLine(SalarySnapshotEmployeeData e) => {
        'employee_id': e.employeeId,
        'name': e.employeeName,
        'code': e.code,
        'days': e.days,
        'earned_basic': e.earnedBasic,
        'earned_other': e.earnedOther,
        'earned_gross': e.earnedGross,
        'pf': e.pf,
        'esic': e.esic,
        'pt': e.pt,
        'msw': e.msw,
        'total_deduction': e.totalDeduction,
        'net_salary': e.netSalary,
      };

  /// Billing totals from stored per-employee data (for saved months).
  static Map<String, Object?> _totalsFromData(
      List<SalarySnapshotEmployeeData> data, SalaryMath math, String code) {
    final f = code == 'All' ? data : data.where((e) => e.code == code).toList();
    double basic = 0, gross = 0, esicGross = 0, net = 0, ded = 0;
    var active = 0;
    for (final e in f) {
      if (e.days > 0) active++;
      basic += e.earnedBasic;
      gross += e.earnedGross;
      if (math.esicApplicable(e.grossSalary)) esicGross += e.earnedGross;
      net += e.netSalary;
      ded += e.totalDeduction;
    }
    final aPf = math.employerPf(basic), aEsic = math.employerEsic(esicGross);
    final aSub = gross + aPf + aEsic, aTotal = aSub.ceilToDouble();
    final b = math.attachmentBTotal(active);
    return {
      'active_employee_count': active,
      'total_earned_gross': gross,
      'total_deductions': ded,
      'total_net_salary': net,
      'attachment_a_pf': aPf,
      'attachment_a_esic': aEsic,
      'attachment_a_total': aTotal,
      'attachment_b_total': b,
      'invoice_total': aTotal + b,
    };
  }

  // ── calculate_salary_month ──────────────────────────────────────────────────

  late final _calculate = ToolDef(
    Tool(
      name: 'calculate_salary_month',
      description: 'Calculate salaries for a month from attendance (days '
          'worked) with the app\'s PF/ESIC/PT/MSW formulas, and the salary '
          'bill totals (Attachment A + B). With save=true it is stored as '
          'that month\'s "Saved Salary" (as the Save button in the app does); '
          'an existing saved month is only replaced with overwrite=true. '
          'Attendance must use employee ids (resolve names with match_employees).',
      annotations: writeTool('Calculate salary month'),
      inputSchema: Schema.object(properties: {
        'month': Schema.int(description: '1-12.'),
        'year': Schema.int(description: 'e.g. 2026.'),
        'attendance': Schema.list(
          description: 'Days worked per employee.',
          items: Schema.object(properties: {
            'employee_id': Schema.int(),
            'days': Schema.int(description: '0 to days in month.'),
          }, required: ['employee_id', 'days']),
        ),
        'default_days': Schema.int(
            description: 'Days for employees not listed in attendance. '
                'Default 0 (not worked).'),
        'company_code': Schema.string(
            description: 'Bill totals for: All (default), ${EmployeeStore.codes.join(', ')}.'),
        'apply_msw': Schema.bool(description: 'Apply MSW (June/December only). Default true.'),
        'msw_amount': Schema.num(description: 'MSW per employee. Default 6.'),
        'include_employees': Schema.bool(
            description: 'Return per-employee lines (worked days > 0). Default true.'),
        'save': Schema.bool(description: 'Save as the month\'s Saved Salary. Default false.'),
        'overwrite': Schema.bool(description: 'Allow replacing an existing saved month.'),
        'snapshot_name': Schema.string(description: 'Name, default "<Month> <year>".'),
        'bill_no': Schema.string(description: 'Salary bill number (default AE/-/25-26).'),
        'po_no': Schema.string(description: 'PO number (default "-").'),
        'bill_date': isoDateSchema('Salary bill date (default today).'),
        'client_name': Schema.string(description: 'Bill client (default the app default client).'),
        'client_address': Schema.string(),
        'client_gstin': Schema.string(),
        'dept_code': Schema.string(),
        'item_description': Schema.string(description: 'Default "Manpower Supply Charges".'),
      }, required: ['month', 'year']),
    ),
    (a) async {
      a.rejectUnknown(['month', 'year', 'attendance', 'default_days',
          'company_code', 'apply_msw', 'msw_amount', 'include_employees',
          'save', 'overwrite', 'snapshot_name', 'bill_no', 'po_no',
          'bill_date', 'client_name', 'client_address', 'client_gstin',
          'dept_code', 'item_description']);
      final month = a.integer('month', required: true, min: 1, max: 12);
      final year = a.integer('year', required: true, min: 2000, max: 2100);
      final input = SalaryMonthInput(
        month: month ?? 1,
        year: year ?? 2000,
        applyMsw: a.boolean('apply_msw', defaultValue: true),
        mswAmount: a.money('msw_amount', allowZero: true, max: 10000) ?? AppDefaults.mswAmount,
      );
      final maxDays = input.totalDays;
      final defaultDays = a.integer('default_days', min: 0, max: maxDays) ?? 0;
      final att = a.objects('attendance', maxItems: 1000) ?? const [];
      final code = a.oneOf('company_code', _codesWithAll) ?? 'All';
      final includeEmployees = a.boolean('include_employees', defaultValue: true);
      final save = a.boolean('save');
      final overwrite = a.boolean('overwrite');

      final employees = (await EmployeeStore.listActive(ctx.db))
          .where((e) => e.name.trim().isNotEmpty)
          .toList();
      final byId = {for (final e in employees) e.id!: e};
      final days = <int, int>{};
      for (var i = 0; i < att.length; i++) {
        final r = a.nested(att[i], 'attendance[$i]');
        r.rejectUnknown(['employee_id', 'days']);
        final id = r.integer('employee_id', required: true, min: 1);
        final d = r.integer('days', required: true, min: 0, max: maxDays);
        if (id == null || d == null) continue;
        if (!byId.containsKey(id)) {
          a.errors.add('attendance[$i].employee_id: no active employee $id.');
        } else if (days.containsKey(id)) {
          a.errors.add('attendance[$i]: employee $id is listed twice.');
        } else {
          days[id] = d;
        }
      }
      a.check();

      final cfg = await _formula(ctx.db);
      final calc = SalaryMonthCalculator(cfg);
      int daysFor(int id) => days[id] ?? defaultDays;
      final data = calc.employeesData(employees, daysFor, input);
      final totals = calc.billingTotals(employees, daysFor, input, companyCode: code);
      final monthName = SalaryMonthSnapshotModel(
              snapshotKey: '', snapshotName: '', month: input.month, year: input.year, payload: '')
          .monthName;

      final result = <String, Object?>{
        'period': '$monthName ${input.year}',
        'days_in_month': maxDays,
        'msw_applied': input.isMsw,
        'company_code': code,
        'totals': totals.toJson(),
        if (includeEmployees)
          'employees': [
            for (final e in data)
              if (e.days > 0 && (code == 'All' || e.code == code)) _employeeLine(e),
          ],
      };
      if (!save) return {...result, 'saved': false};

      await _requireSnapshots();
      final existing = await SalarySnapshotStore.getByPeriod(ctx.db, input.month, input.year);
      if (existing != null && !overwrite) {
        throw ToolError('A saved salary for $monthName ${input.year} already '
            'exists (id ${existing.id}, "${existing.snapshotName}"). Nothing was '
            'saved. Retry with overwrite=true if the user wants to replace it.');
      }
      final m = a.nested(a.raw, '');
      final payload = SalarySnapshotPayload(
        month: input.month,
        year: input.year,
        dateIso: m.date('bill_date') ?? ctx.clock().toIso8601String().split('T').first,
        poNo: m.str('po_no') ?? AppDefaults.salaryPoNo,
        billNo: m.str('bill_no') ?? AppDefaults.salaryBillNo,
        clientName: m.str('client_name') ?? AppDefaults.defaultClientName,
        clientAddr: m.str('client_address') ?? AppDefaults.defaultClientAddress,
        clientGstin: m.str('client_gstin') ?? AppDefaults.defaultClientGstin,
        deptCode: m.oneOf('dept_code', AppDefaults.deptCodes) ?? '',
        selectedCompanyCode: code,
        itemDescription: m.str('item_description') ?? AppDefaults.salaryItemDescription,
        employees: data,
      );
      final name = m.str('snapshot_name', maxLength: 200);
      a.check();
      final id = await ctx.store.write((txn) => SalarySnapshotStore.save(txn,
          snapshotName: (name == null || name.isEmpty) ? '$monthName ${input.year}' : name,
          payload: payload,
          nowIso: ctx.nowLocalIso()));
      return {
        ...result,
        'saved': true,
        'saved_salary_id': id,
        if (existing != null) 'replaced_previous': true,
        'note': 'If the app is open, reload it from the Saved Salary screen.',
      };
    },
  );

  // ── Saved months ────────────────────────────────────────────────────────────

  late final _listSaved = ToolDef(
    Tool(
      name: 'list_saved_salary_months',
      description: 'Saved salary months (newest first) with employee count '
          'and total net payroll.',
      annotations: readOnlyTool('List saved salary months'),
      inputSchema: Schema.object(properties: {}),
    ),
    (a) async {
      a.rejectUnknown([]);
      a.check();
      if (!await ctx.store.hasTable(SalarySnapshotStore.tableSnapshots)) {
        return {'saved_months': []};
      }
      final list = await SalarySnapshotStore.list(ctx.db);
      return {
        'saved_months': [
          for (final s in list) _savedSummary(s),
        ],
      };
    },
  );

  Map<String, Object?> _savedSummary(SalaryMonthSnapshotModel s) {
    var count = 0;
    var net = 0.0;
    try {
      final p = SalarySnapshotPayload.decode(s.payload);
      count = p.employees.where((e) => e.days > 0).length;
      net = p.employees.fold(0.0, (t, e) => t + e.netSalary);
    } catch (_) {}
    return {
      'id': s.id,
      'name': s.snapshotName,
      'month': s.month,
      'year': s.year,
      'employees_worked': count,
      'total_net_salary': net,
      'updated_at': s.updatedAt,
    };
  }

  late final _getSaved = ToolDef(
    Tool(
      name: 'get_saved_salary_month',
      description: 'One saved salary month: bill metadata, totals '
          '(Attachment A/B, net payroll) and per-employee lines. Look up by '
          'id, or by month + year.',
      annotations: readOnlyTool('Get saved salary month'),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(),
        'month': Schema.int(),
        'year': Schema.int(),
        'include_employees': Schema.bool(description: 'Default true.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['id', 'month', 'year', 'include_employees']);
      final id = a.integer('id', min: 1);
      final month = a.integer('month', min: 1, max: 12);
      final year = a.integer('year', min: 2000, max: 2100);
      final include = a.boolean('include_employees', defaultValue: true);
      if (id == null && (month == null || year == null)) {
        a.errors.add('Pass id, or both month and year.');
      }
      a.check();
      await _requireSnapshots();
      final s = id != null
          ? await SalarySnapshotStore.get(ctx.db, id)
          : await SalarySnapshotStore.getByPeriod(ctx.db, month!, year!);
      if (s == null) throw const ToolError('No such saved salary month.');
      final p = SalarySnapshotPayload.decode(s.payload);
      final math = SalaryMath(await _formula(ctx.db));
      return {
        ..._savedSummary(s),
        'bill': {
          'date': p.dateIso,
          'bill_no': p.billNo,
          'po_no': p.poNo,
          'client_name': p.clientName,
          'client_address': p.clientAddr,
          'client_gstin': p.clientGstin,
          'dept_code': p.deptCode,
          'company_code': p.selectedCompanyCode,
          'item_description': p.itemDescription,
        },
        'totals': _totalsFromData(p.employees, math, p.selectedCompanyCode),
        if (include)
          'employees': [for (final e in p.employees) if (e.days > 0) _employeeLine(e)],
      };
    },
  );

  late final _rename = ToolDef(
    Tool(
      name: 'rename_saved_salary_month',
      description: 'Rename a saved salary month.',
      annotations: writeTool('Rename saved salary month', idempotent: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(),
        'name': Schema.string(),
      }, required: ['id', 'name']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'name']);
      final id = a.integer('id', required: true, min: 1);
      final name = a.str('name', required: true, maxLength: 200);
      a.check();
      await _requireSnapshots();
      if (await SalarySnapshotStore.get(ctx.db, id!) == null) {
        throw ToolError('No saved salary month with id $id.');
      }
      await ctx.store.write(
          (txn) => SalarySnapshotStore.rename(txn, id, name!, ctx.nowLocalIso()));
      return {'renamed': true, 'id': id, 'name': name};
    },
  );

  late final _deleteSaved = ToolDef(
    Tool(
      name: 'delete_saved_salary_month',
      description: 'Permanently delete a saved salary month (the app deletes '
          'these permanently too). Requires confirm=true.',
      annotations: writeTool('Delete saved salary month', destructive: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(),
        'confirm': confirmSchema(),
      }, required: ['id', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'confirm']);
      final id = a.integer('id', required: true, min: 1);
      requireConfirm(a, 'permanently delete this saved salary month');
      a.check();
      await _requireSnapshots();
      final s = await SalarySnapshotStore.get(ctx.db, id!);
      if (s == null) throw ToolError('No saved salary month with id $id.');
      await ctx.store.write((txn) => SalarySnapshotStore.delete(txn, id));
      return {'deleted': true, 'saved_month': _savedSummary(s)};
    },
  );

  // ── Analytics ───────────────────────────────────────────────────────────────

  static final _ym = RegExp(r'^(\d{4})-(\d{2})$');

  late final _analytics = ToolDef(
    Tool(
      name: 'salary_analytics',
      description: 'Totals across saved salary months: per month or per '
          'employee (gross, deductions by type, net, days).',
      annotations: readOnlyTool('Salary analytics'),
      inputSchema: Schema.object(properties: {
        'from': Schema.string(description: 'First month, YYYY-MM.'),
        'to': Schema.string(description: 'Last month, YYYY-MM.'),
        'group_by': Schema.string(description: 'month (default) or employee.'),
        'employee_id': Schema.int(description: 'Only this employee.'),
        'code': Schema.string(description: 'Only this company code.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['from', 'to', 'group_by', 'employee_id', 'code']);
      int? ym(String k) {
        final s = a.str(k);
        if (s == null) return null;
        final m = _ym.firstMatch(s);
        if (m == null || int.parse(m[2]!) < 1 || int.parse(m[2]!) > 12) {
          a.errors.add('$k: "$s" must be YYYY-MM, e.g. 2026-04.');
          return null;
        }
        return int.parse(m[1]!) * 100 + int.parse(m[2]!);
      }
      final from = ym('from'), to = ym('to');
      final group = a.oneOf('group_by', ['month', 'employee']) ?? 'month';
      final emp = a.integer('employee_id', min: 1);
      final code = a.oneOf('code', EmployeeStore.codes);
      a.check();
      if (!await ctx.store.hasTable(SalarySnapshotStore.tableEmployees)) {
        return {'rows': []};
      }
      final where = <String>['attendance > 0'];
      final args = <Object?>[];
      if (from != null) { where.add('(year * 100 + month) >= ?'); args.add(from); }
      if (to != null) { where.add('(year * 100 + month) <= ?'); args.add(to); }
      if (emp != null) { where.add('employee_id = ?'); args.add(emp); }
      if (code != null) { where.add('code = ?'); args.add(code); }
      final key = group == 'month'
          ? "year, month"
          : "employee_id, employee_name";
      final rows = await ctx.db.rawQuery('''
        SELECT $key, COUNT(*) AS lines, SUM(attendance) AS days,
               SUM(gross_salary) AS earned_gross, SUM(pf) AS pf, SUM(esic) AS esic,
               SUM(pt) AS pt, SUM(msw) AS msw, SUM(deductions) AS deductions,
               SUM(net_salary) AS net_salary
        FROM ${SalarySnapshotStore.tableEmployees}
        WHERE ${where.join(' AND ')}
        GROUP BY $key
        ORDER BY ${group == 'month' ? 'year, month' : 'employee_name'}''', args);
      return {
        'group_by': group,
        'rows': [
          for (final r in rows)
            {
              for (final e in r.entries)
                e.key == 'lines' && group == 'month' ? 'employees' : e.key: e.value,
            },
        ],
      };
    },
  );

  // ── Disbursements (read-only; created by the app's bank-sheet export) ───────

  late final _listDisb = ToolDef(
    Tool(
      name: 'list_salary_disbursements',
      description: 'Salary bank disbursement batches (created in the app when '
          'the disbursement bank sheet is exported).',
      annotations: readOnlyTool('List salary disbursements'),
      inputSchema: Schema.object(properties: {
        'month': Schema.int(),
        'year': Schema.int(),
        'status': Schema.string(),
      }),
    ),
    (a) async {
      a.rejectUnknown(['month', 'year', 'status']);
      final month = a.integer('month', min: 1, max: 12);
      final year = a.integer('year', min: 2000, max: 2100);
      final status = a.str('status');
      a.check();
      if (!await ctx.store.hasTable('salary_disbursements')) return {'disbursements': []};
      final where = <String>[], args = <Object?>[];
      if (month != null) { where.add('d.month = ?'); args.add(month); }
      if (year != null) { where.add('d.year = ?'); args.add(year); }
      if (status != null && status.isNotEmpty) { where.add('d.status = ?'); args.add(status); }
      final rows = await ctx.db.rawQuery('''
        SELECT d.id, d.reference_no, d.month, d.year, d.dept_code, d.status,
               d.generated_at, d.exported_at, d.disbursed_at,
               COUNT(i.id) AS items, COALESCE(SUM(i.amount), 0) AS total_amount
        FROM salary_disbursements d
        LEFT JOIN salary_disbursement_items i ON i.disbursement_id = d.id
        ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
        GROUP BY d.id ORDER BY d.year DESC, d.month DESC, d.id DESC''', args);
      return {'disbursements': rows};
    },
  );

  late final _getDisb = ToolDef(
    Tool(
      name: 'get_salary_disbursement',
      description: 'One disbursement batch with every payment line.',
      annotations: readOnlyTool('Get salary disbursement'),
      inputSchema: Schema.object(
          properties: {'id': Schema.int()}, required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id']);
      final id = a.integer('id', required: true, min: 1);
      a.check();
      if (!await ctx.store.hasTable('salary_disbursements')) {
        throw const ToolError('No disbursements exist yet.');
      }
      final d = await ctx.db.query('salary_disbursements', where: 'id = ?', whereArgs: [id]);
      if (d.isEmpty) throw ToolError('No disbursement with id $id.');
      final items = await ctx.db.query('salary_disbursement_items',
          columns: ['employee_id', 'employee_name', 'amount', 'bank_name',
              'account_number', 'ifsc_code', 'branch', 'status'],
          where: 'disbursement_id = ?', whereArgs: [id], orderBy: 'id');
      return {...d.first, 'items': items};
    },
  );
}

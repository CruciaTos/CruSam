import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';

class EmployeeTools extends ToolGroup {
  final ToolContext ctx;
  EmployeeTools(this.ctx);

  @override
  List<ToolDef> get tools =>
      [_match, _find, _list, _get, _create, _update, _delete];

  static final _ifsc = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

  static Map<String, Object?> employeeJson(EmployeeModel e, {bool full = false}) => {
        'id': e.id,
        'name': e.name,
        'code': e.code,
        if (full) ...{
          'sr_no': e.srNo,
          'gender': e.gender,
          'pf_no': e.pfNo,
          'uan_no': e.uanNo,
          'zone': e.zone,
          'date_of_joining': e.dateOfJoining,
          'basic_charges': e.basicCharges,
          'other_charges': e.otherCharges,
          'gross_salary': e.grossSalary,
          'aarti_ac_no': e.aartiAcNo,
          'bank': {
            'ifsc': e.ifscCode,
            'account': e.accountNumber,
            'bank': e.bankDetails,
            'branch': e.branch,
            'sb_code': e.sbCode,
          },
        } else ...{
          'bank': e.bankDetails,
          'has_bank_account': e.accountNumber.trim().isNotEmpty,
        },
      };

  static final Map<String, Schema> _fields = {
    'name': Schema.string(description: 'Full name.'),
    'code': Schema.string(description: 'Company code: one of ${EmployeeStore.codes.join(', ')}.'),
    'gender': Schema.string(description: 'M or F (affects Professional Tax).'),
    'sr_no': Schema.int(description: 'Serial number used for ordering.'),
    'pf_no': Schema.string(description: 'PF number.'),
    'uan_no': Schema.string(description: 'UAN number.'),
    'ifsc_code': Schema.string(description: 'Bank IFSC, e.g. SBIN0001234.'),
    'account_number': Schema.string(description: 'Bank account number (string, keep leading zeros).'),
    'bank_details': Schema.string(description: 'Bank name, e.g. "State Bank Of India".'),
    'branch': Schema.string(description: 'Bank branch / place.'),
    'sb_code': Schema.string(description: 'S/B code, usually 10.'),
    'aarti_ac_no': Schema.string(description: 'Aarti account number.'),
    'zone': Schema.string(description: 'Zone, e.g. East.'),
    'date_of_joining': isoDateSchema('Date of joining.'),
    'basic_charges': Schema.num(description: 'Monthly basic (rupees).'),
    'other_charges': Schema.num(description: 'Monthly other charges (rupees).'),
  };

  late final _match = ToolDef(
    Tool(
      name: 'match_employees',
      description: 'Resolve many names at once (e.g. every row read from an '
          'invoice image) to employee ids. Tolerates handwriting errors, '
          'initials ("P.V. Lokesh"), abbreviations ("Mohd") and joined words. '
          'Each result has the best candidates with scores; "confident" means '
          'the top score is >= 0.8 and clearly ahead of the next. Show '
          'non-confident matches to the user before using them.',
      annotations: readOnlyTool('Match employee names'),
      inputSchema: Schema.object(properties: {
        'names': Schema.list(items: Schema.string(), description: 'Names as written.'),
        'candidates': Schema.int(description: 'Candidates per name, 1-5, default 3.'),
      }, required: ['names']),
    ),
    (a) async {
      a.rejectUnknown(['names', 'candidates']);
      final names = a.strings('names', required: true, minItems: 1, maxItems: 200);
      final k = a.integer('candidates', min: 1, max: 5) ?? 3;
      a.check();
      final emps = (await EmployeeStore.listActive(ctx.db))
          .where((e) => e.name.trim().isNotEmpty)
          .toList();
      final pool = [for (final e in emps) e.name];
      var unresolved = 0;
      final results = <Map<String, Object?>>[];
      for (var i = 0; i < names!.length; i++) {
        final ranked = FuzzyName.rank(names[i], pool, minScore: 0.45, limit: k);
        final top = ranked.isEmpty ? 0.0 : ranked.first.$2;
        final second = ranked.length > 1 ? ranked[1].$2 : 0.0;
        final confident = top >= 0.8 && top - second >= 0.15;
        if (!confident) unresolved++;
        results.add({
          'index': i,
          'input': names[i],
          'confident': confident,
          'candidates': [
            for (final (idx, s) in ranked)
              {...employeeJson(emps[idx]), 'score': s},
          ],
        });
      }
      return {
        'results': results,
        'needs_review': unresolved,
      };
    },
  );

  late final _find = ToolDef(
    Tool(
      name: 'find_employees',
      description: 'Fuzzy search one employee by name, PF/UAN number or '
          'account number. Returns id, code and bank summary.',
      annotations: readOnlyTool('Find employees'),
      inputSchema: Schema.object(properties: {
        'query': Schema.string(description: 'Name (or part), PF/UAN or account number.'),
        'code': Schema.string(description: 'Only this company code.'),
        'limit': Schema.int(description: '1-50, default 10.'),
      }, required: ['query']),
    ),
    (a) async {
      a.rejectUnknown(['query', 'code', 'limit']);
      final q = a.str('query', required: true);
      final code = a.oneOf('code', EmployeeStore.codes);
      final limit = a.integer('limit', min: 1, max: 50) ?? 10;
      a.check();
      final ql = q!.toLowerCase();
      final emps = (await EmployeeStore.listActive(ctx.db))
          .where((e) => code == null || e.code == code)
          .toList();
      final scored = <(EmployeeModel, double)>[];
      for (final e in emps) {
        var s = FuzzyName.score(q, e.name);
        final ids = [e.pfNo, e.uanNo, e.accountNumber].map((x) => x.toLowerCase());
        if (ids.any((x) => x.isNotEmpty && x == ql)) s = 1;
        if (e.name.toLowerCase().contains(ql) && s < 0.9) s = 0.9;
        if (s >= 0.45) scored.add((e, s));
      }
      scored.sort((x, y) => y.$2.compareTo(x.$2));
      return {
        'matches': [
          for (final (e, s) in scored.take(limit)) {...employeeJson(e), 'score': s},
        ],
      };
    },
  );

  late final _list = ToolDef(
    Tool(
      name: 'list_employees',
      description: 'List active employees (ordered by serial number), '
          'optionally by company code. Set full=true for salary and bank fields.',
      annotations: readOnlyTool('List employees'),
      inputSchema: Schema.object(properties: {
        'code': Schema.string(description: 'Company code filter.'),
        'full': Schema.bool(description: 'Include all fields. Default false.'),
        'limit': Schema.int(description: '1-500, default 200.'),
        'offset': Schema.int(description: 'Default 0.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['code', 'full', 'limit', 'offset']);
      final code = a.oneOf('code', EmployeeStore.codes);
      final full = a.boolean('full');
      final limit = a.integer('limit', min: 1, max: 500) ?? 200;
      final offset = a.integer('offset', min: 0) ?? 0;
      a.check();
      final emps = (await EmployeeStore.listActive(ctx.db))
          .where((e) => code == null || e.code == code)
          .toList();
      return {
        'total': emps.length,
        'employees': [
          for (final e in emps.skip(offset).take(limit)) employeeJson(e, full: full),
        ],
      };
    },
  );

  late final _get = ToolDef(
    Tool(
      name: 'get_employee',
      description: 'All fields of one employee, including bank and salary details.',
      annotations: readOnlyTool('Get employee'),
      inputSchema: Schema.object(
          properties: {'id': Schema.int(description: 'Employee id.')},
          required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id']);
      final id = a.integer('id', required: true, min: 1);
      a.check();
      final m = await EmployeeStore.getRow(ctx.db, id!, includeDeleted: true);
      if (m == null) throw ToolError('No employee with id $id.');
      return {
        ...employeeJson(EmployeeModel.fromMap(m), full: true),
        if (m['is_deleted'] == 1) 'deleted': true,
      };
    },
  );

  late final _create = ToolDef(
    Tool(
      name: 'create_employee',
      description: 'Add an employee, as the Employee form does (name and code '
          'required). Refuses likely duplicates (same name, PF, UAN or account) '
          'unless allow_duplicate=true. Use dry_run=true to preview.',
      annotations: writeTool('Create employee'),
      inputSchema: Schema.object(properties: {
        ..._fields,
        'dry_run': Schema.bool(description: 'Preview without saving. Default false.'),
        'allow_duplicate': Schema.bool(description: 'Default false.'),
      }, required: ['name', 'code']),
    ),
    (a) async {
      a.rejectUnknown([..._fields.keys, 'dry_run', 'allow_duplicate']);
      final emp = _apply(a, const EmployeeModel(name: ''), creating: true);
      final dryRun = a.boolean('dry_run');
      final allowDup = a.boolean('allow_duplicate');
      a.check();
      final dupes = await _duplicates(emp, excludeId: null);
      if (dupes.isNotEmpty && !allowDup && !dryRun) {
        throw ToolError('Refused: possible duplicate of '
            '${dupes.map((d) => '#${d.$1.id} ${d.$1.name} (${d.$2})').join('; ')}. '
            'Nothing was saved. Retry with allow_duplicate=true if the user confirms.');
      }
      final warnings = _warnings(emp);
      if (dryRun) {
        return {
          'dry_run': true,
          'employee': employeeJson(emp, full: true),
          if (dupes.isNotEmpty)
            'duplicates': [for (final d in dupes) {'id': d.$1.id, 'name': d.$1.name, 'reason': d.$2}],
          if (warnings.isNotEmpty) 'warnings': warnings,
        };
      }
      final now = ctx.nowUtcIso();
      final id = await ctx.store.write((txn) => EmployeeStore.insert(
          txn,
          EmployeeStore.formRow(emp,
              cloudId: ctx.newUuid(), createdAt: now, nowUtcIso: now)));
      return {
        'created': true,
        'employee': employeeJson(emp.copyWith(id: id), full: true),
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
    },
  );

  late final _update = ToolDef(
    Tool(
      name: 'update_employee',
      description: 'Change fields of an employee (only the fields you pass). '
          'Changing basic/other charges affects future salary calculations, '
          'not saved salary months or past invoices.',
      annotations: writeTool('Update employee', idempotent: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Employee id.'),
        ..._fields,
        'dry_run': Schema.bool(description: 'Preview without saving. Default false.'),
      }, required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id', ..._fields.keys, 'dry_run']);
      final id = a.integer('id', required: true, min: 1);
      final dryRun = a.boolean('dry_run');
      a.check();
      final m = await EmployeeStore.getRow(ctx.db, id!);
      if (m == null) throw ToolError('No active employee with id $id.');
      final before = EmployeeModel.fromMap(m);
      final after = _apply(a, before, creating: false);
      if (!_fields.keys.any(a.has)) a.errors.add('Pass at least one field to change.');
      a.check();
      final changes = <String, Object?>{};
      final b = employeeJson(before, full: true), c = employeeJson(after, full: true);
      for (final k in c.keys) {
        if ('${b[k]}' != '${c[k]}') changes[k] = {'from': b[k], 'to': c[k]};
      }
      if (!dryRun) {
        final now = ctx.nowUtcIso();
        await ctx.store.write((txn) => EmployeeStore.update(
            txn,
            id,
            EmployeeStore.formRow(after,
                cloudId: (m['cloud_id'] as String?)?.isNotEmpty == true
                    ? m['cloud_id'] as String
                    : ctx.newUuid(),
                createdAt: (m['created_at'] as String?) ?? now,
                nowUtcIso: now)));
      }
      return {
        'dry_run': dryRun,
        if (!dryRun) 'updated': true,
        'employee_id': id,
        'changes': changes,
        if (_warnings(after).isNotEmpty) 'warnings': _warnings(after),
      };
    },
  );

  late final _delete = ToolDef(
    Tool(
      name: 'delete_employee',
      description: 'Delete an employee as the app does (soft delete). Past '
          'invoices and saved salary months keep their copies. Requires confirm=true.',
      annotations: writeTool('Delete employee', destructive: true, idempotent: true),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Employee id.'),
        'confirm': confirmSchema(),
      }, required: ['id', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'confirm']);
      final id = a.integer('id', required: true, min: 1);
      requireConfirm(a, 'delete this employee');
      a.check();
      final m = await EmployeeStore.getRow(ctx.db, id!);
      if (m == null) throw ToolError('No active employee with id $id.');
      await ctx.store.write((txn) => EmployeeStore.softDelete(txn, id, ctx.nowUtcIso()));
      return {'deleted': true, 'employee': employeeJson(EmployeeModel.fromMap(m))};
    },
  );

  EmployeeModel _apply(Args a, EmployeeModel e, {required bool creating}) {
    String? s(String k, {bool req = false}) =>
        a.has(k) || req ? a.str(k, required: req, allowEmpty: !req, maxLength: 300) : null;
    final name = s('name', req: creating);
    final code = a.has('code') || creating
        ? a.oneOf('code', EmployeeStore.codes, required: true)
        : null;
    final gender = a.has('gender') ? a.oneOf('gender', ['M', 'F'], required: true) : null;
    final doj = a.has('date_of_joining') ? a.date('date_of_joining', required: true) : null;
    return e.copyWith(
      name: name,
      code: code,
      gender: gender ?? (creating ? 'M' : null),
      srNo: a.integer('sr_no', min: 0),
      pfNo: s('pf_no'),
      uanNo: s('uan_no'),
      ifscCode: s('ifsc_code')?.toUpperCase(),
      accountNumber: s('account_number'),
      bankDetails: s('bank_details'),
      branch: s('branch'),
      sbCode: s('sb_code'),
      aartiAcNo: s('aarti_ac_no'),
      zone: s('zone'),
      dateOfJoining: doj == null ? null : EmployeeStore.joiningDateForDb(doj),
      basicCharges: a.money('basic_charges', allowZero: true, max: 5000000),
      otherCharges: a.money('other_charges', allowZero: true, max: 1000000),
    );
  }

  List<String> _warnings(EmployeeModel e) => [
        if (e.ifscCode.isNotEmpty && !_ifsc.hasMatch(e.ifscCode))
          'IFSC "${e.ifscCode}" does not look valid (expected 4 letters, 0, 6 characters).',
        if (e.accountNumber.isEmpty) 'No bank account number: bank sheets will be incomplete.',
        if (e.basicCharges == 0 && e.otherCharges == 0)
          'Basic and other charges are 0: salary calculations will be 0.',
      ];

  Future<List<(EmployeeModel, String)>> _duplicates(EmployeeModel e,
      {required int? excludeId}) async {
    final out = <(EmployeeModel, String)>[];
    String n(String s) => s.trim().toLowerCase();
    for (final x in await EmployeeStore.listActive(ctx.db)) {
      if (x.id == excludeId) continue;
      final reasons = [
        if (n(x.name) == n(e.name)) 'same name',
        if (n(e.pfNo).length > 3 && n(x.pfNo) == n(e.pfNo)) 'same PF no',
        if (n(e.uanNo).length > 3 && n(x.uanNo) == n(e.uanNo)) 'same UAN',
        if (n(e.accountNumber).length > 3 && n(x.accountNumber) == n(e.accountNumber))
          'same account number',
      ];
      if (reasons.isNotEmpty) out.add((x, reasons.join(', ')));
    }
    return out;
  }
}

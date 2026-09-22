import 'dart:typed_data';

import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';

import '../context.dart';
import '../db.dart';
import '../exports/export_env.dart';
import '../exports/salary_period.dart';
import '../exports/xlsx_sheets.dart';
import '../tool_kit.dart';

/// PDF / Excel exports and salary disbursement batches. PDFs are generated
/// by the same crusam_core code the app uses; files are saved to the
/// folders set on the app's Export Paths card (or output_dir).
class DocumentTools extends ToolGroup {
  final ToolContext ctx;
  final ExportEnv env;
  DocumentTools(this.ctx, this.env);

  @override
  List<ToolDef> get tools =>
      [_invoiceDocs, _salaryDocs, _createDisb, _exportDisb];

  static const _invoiceKinds = ['invoice_pdf', 'bank_disbursement_pdf', 'bank_disbursement_excel'];
  static const _salaryKinds = [
    'final_bill_pdf', 'salary_invoice_pdf', 'attachment_a_pdf', 'attachment_b_pdf',
    'statement_pdf', 'statement_excel', 'slips_pdf',
  ];

  static final _outputDir = Schema.string(
      description: 'Optional folder to save into. Default: the folders set in '
          'the app (Profile → Export Paths), else Downloads.');

  Future<CompanyConfigModel> _config() => ctx.companyConfig(ctx.db);

  String _stamp() {
    final n = ctx.clock();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }

  // ── Invoices ────────────────────────────────────────────────────────────────

  late final _invoiceDocs = ToolDef(
    Tool(
      name: 'export_invoice_documents',
      description: 'Create files for a saved invoice, exactly as the app\'s '
          'export buttons do: invoice_pdf (tax invoice + expenses statement), '
          'bank_disbursement_pdf, bank_disbursement_excel. Returns the saved '
          'file paths.',
      annotations: writeTool('Export invoice documents', idempotent: false),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Invoice id.'),
        'documents': Schema.list(
            items: Schema.string(),
            description: 'Any of ${_invoiceKinds.join(', ')}. Default: invoice_pdf.'),
        'output_dir': _outputDir,
      }, required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'documents', 'output_dir']);
      final id = a.integer('id', required: true, min: 1);
      final kinds = _kinds(a, _invoiceKinds, ['invoice_pdf']);
      final out = a.str('output_dir');
      a.check();
      final v = await VoucherStore.getById(ctx.db, id!);
      if (v == null) throw ToolError('No (non-deleted) invoice with id $id.');
      final config = await _config();
      final files = <Map<String, Object?>>[];
      for (final k in kinds) {
        switch (k) {
          case 'invoice_pdf':
            final bytes = await WidgetPdfExportService.buildInvoiceBundleBytes(
                voucher: v, config: config);
            files.add(await _save(k, bytes, ExportPathTarget.taxInvoice, out,
                '${v.billNo.isEmpty ? 'tax_invoice_voucher_${ExportHooks.slug('')}' : ExportHooks.slug(v.billNo)}.pdf'));
          case 'bank_disbursement_pdf':
            final bytes = await WidgetPdfExportService.buildBankDisbursementBytes(
                voucher: v, config: config);
            files.add(await _save(k, bytes, ExportPathTarget.general, out,
                'bank_disbursement_${ExportHooks.slug(v.billNo)}.pdf'));
          case 'bank_disbursement_excel':
            final title = (v.title.trim().isEmpty ? 'voucher' : v.title)
                .replaceAll(RegExp(r'[<>:"/\\|?*]'), '')
                .replaceAll(' ', '_');
            files.add(await _save(k, voucherBankSheet(v, config),
                ExportPathTarget.bankDisbursementExcel, out,
                'bank_disbursement_${title}_${_stamp()}.xlsx'));
        }
      }
      return {'invoice_id': id, 'files': files};
    },
  );

  // ── Salary documents ────────────────────────────────────────────────────────

  late final _salaryDocs = ToolDef(
    Tool(
      name: 'export_salary_documents',
      description: 'Create salary documents for a SAVED salary month, as the '
          'app does after loading that month: final_bill_pdf (salary invoice '
          '+ attachment A + attachment B + statement), salary_invoice_pdf, '
          'attachment_a_pdf, attachment_b_pdf, statement_pdf, '
          'statement_excel, slips_pdf (two per page, employees who worked). '
          'Attendance and bill details come from the saved month; employee '
          'salaries and formula settings are the current ones. Returns file paths.',
      annotations: writeTool('Export salary documents'),
      inputSchema: Schema.object(properties: {
        'month': Schema.int(description: '1-12.'),
        'year': Schema.int(),
        'documents': Schema.list(
            items: Schema.string(),
            description: 'Any of ${_salaryKinds.join(', ')}. Default: final_bill_pdf.'),
        'company_code': Schema.string(
            description: 'All or ${EmployeeStore.codes.join('/')}. Default: the one saved with the month.'),
        'output_dir': _outputDir,
      }, required: ['month', 'year']),
    ),
    (a) async {
      a.rejectUnknown(['month', 'year', 'documents', 'company_code', 'output_dir']);
      final month = a.integer('month', required: true, min: 1, max: 12);
      final year = a.integer('year', required: true, min: 2000, max: 2100);
      final kinds = _kinds(a, _salaryKinds, ['final_bill_pdf']);
      final code = a.oneOf('company_code', ['All', ...EmployeeStore.codes]);
      final out = a.str('output_dir');
      a.check();
      final sp = await SalaryPeriod.load(ctx.db, month!, year!, companyCode: code);
      SalaryFormulaEngine.configProvider = () => sp.formula;
      final config = await _config();
      final t = sp.totals;
      final header = sp.header;
      final slug = ExportHooks.slug(sp.payload.billNo);
      final monthLower = sp.monthName.toLowerCase();

      PdfInvoiceSpec invoice() => SalaryBillPdfService.salaryInvoiceSpec(
          header: header, itemDescription: sp.itemDescription,
          invoiceBaseAmount: t.invoiceTotal);
      PdfInvoiceSpec attA() => SalaryBillPdfService.attachmentASpec(
          header: header, itemDescription: sp.attachmentADescription,
          itemAmount: t.totalEarnedGross, pfAmount: t.attachmentAPf,
          esicAmount: t.attachmentAEsic);
      PdfInvoiceSpec attB() => SalaryBillPdfService.attachmentBSpec(
          header: header, itemDescription: sp.attachmentBDescription,
          employeeCount: t.activeEmployeeCount);
      final statementDays = {
        for (final e in sp.employees)
          if (e.id != null) e.id!: sp.daysMap[e.id] ?? 0,
      };

      final files = <Map<String, Object?>>[];
      for (final k in kinds) {
        switch (k) {
          case 'final_bill_pdf':
            final bytes = await SalaryBillPdfService.buildBytes(
              config: config,
              pages: [invoice(), attA(), attB()],
              statement: SalaryStatementInput(
                employees: sp.employees, monthName: sp.monthName, year: sp.year,
                isMsw: sp.isMsw, mswAmount: sp.mswAmount, isFeb: sp.isFeb,
                daysMap: statementDays, daysInMonth: sp.daysInMonth,
              ),
              departmentCode: sp.departmentCode,
              title: 'final_invoice_$slug',
            );
            files.add(await _save(k, bytes, ExportPathTarget.salary, out, 'final_invoice_$slug.pdf'));
          case 'salary_invoice_pdf' || 'attachment_a_pdf' || 'attachment_b_pdf':
            final (spec, name) = switch (k) {
              'salary_invoice_pdf' => (invoice(), 'salary_invoice_$slug'),
              'attachment_a_pdf' => (attA(), 'attachment_a_$slug'),
              _ => (attB(), 'attachment_b_$slug'),
            };
            final bytes = await SalaryBillPdfService.buildBytes(
                config: config, pages: [spec], title: name);
            files.add(await _save(k, bytes, ExportPathTarget.salary, out, '$name.pdf'));
          case 'statement_pdf':
            final bytes = await SalaryStatementPdfService.buildSalaryStatementBytes(
              config: config, employees: sp.employees, monthName: sp.monthName,
              year: sp.year, isMsw: sp.isMsw, mswAmount: sp.mswAmount,
              isFeb: sp.isFeb, daysMap: statementDays, daysInMonth: sp.daysInMonth,
              columnWidths: env.statementColumnWidths(),
              departmentCode: sp.departmentCode,
            );
            files.add(await _save(k, bytes, ExportPathTarget.salary, out,
                'salary_statement_${monthLower}_${sp.year}.pdf'));
          case 'statement_excel':
            final bytes = salaryStatementSheet(
              config: config, employees: sp.employees, monthName: sp.monthName,
              year: sp.year, isMsw: sp.isMsw, mswAmount: sp.mswAmount,
              isFeb: sp.isFeb, daysMap: statementDays, daysInMonth: sp.daysInMonth,
            );
            files.add(await _save(k, bytes, ExportPathTarget.salaryStatementExcel, out,
                'Salary_Statement_${sp.monthName}_${sp.year}.xlsx'));
          case 'slips_pdf':
            final worked = sp.workedEmployees;
            if (worked.isEmpty) {
              files.add({'document': k, 'skipped': 'no employee worked in this month'});
              continue;
            }
            final bytes = await SalaryPdfExportService.buildSalarySlipsBytes(
              config: config, employees: worked, monthName: sp.monthName,
              year: sp.year, daysInMonth: sp.daysInMonth, isMsw: sp.isMsw,
              isFeb: sp.isFeb, daysMap: sp.daysMap, mswAmount: sp.mswAmount,
            );
            files.add(await _save(k, bytes, ExportPathTarget.salary, out,
                'salary_slips_${monthLower}_${sp.year}.pdf'));
        }
      }
      return {
        'period': sp.periodLabel,
        'company_code': sp.companyCode,
        'invoice_total': t.invoiceTotal,
        'files': files,
      };
    },
  );

  // ── Salary disbursement batches ────────────────────────────────────────────

  late final _createDisb = ToolDef(
    Tool(
      name: 'create_salary_disbursement',
      description: 'Create a salary bank-disbursement batch for a SAVED salary '
          'month and its bank Excel sheet, as the Disbursement screen\'s '
          'Generate button does. Candidates: employees with a positive net '
          'salary and bank details. dry_run=true lists the candidates and '
          'amounts; dry_run=false saves the batch and writes the Excel file. '
          'Employees already in an earlier batch for the month are reported.',
      annotations: writeTool('Create salary disbursement'),
      inputSchema: Schema.object(properties: {
        'month': Schema.int(),
        'year': Schema.int(),
        'employee_ids': Schema.list(
            items: Schema.int(),
            description: 'Only these candidates. Default: all candidates.'),
        'dry_run': Schema.bool(description: 'Required. Preview first.'),
        'output_dir': _outputDir,
      }, required: ['month', 'year', 'dry_run']),
    ),
    (a) async {
      a.rejectUnknown(['month', 'year', 'employee_ids', 'dry_run', 'output_dir']);
      final month = a.integer('month', required: true, min: 1, max: 12);
      final year = a.integer('year', required: true, min: 2000, max: 2100);
      final dryRun = a.boolean('dry_run', required: true);
      final idsRaw = a.raw['employee_ids'];
      if (idsRaw != null && (idsRaw is! List || idsRaw.any((e) => e is! int))) {
        a.errors.add('employee_ids: must be an array of integer employee ids.');
      }
      final out = a.str('output_dir');
      a.check();
      final sp = await SalaryPeriod.load(ctx.db, month!, year!, companyCode: 'All');
      final calc = SalaryMonthCalculator(sp.formula);
      final input = SalaryMonthInput(
          month: month, year: year, applyMsw: sp.isMsw, mswAmount: sp.mswAmount);

      // Same rules as SalaryDisbursementService.buildCandidateItems.
      final candidates = <SalaryDisbursementItemModel>[];
      for (final e in sp.allEmployees) {
        final days = sp.daysMap[e.id] ?? 0;
        if (days == 0) continue;
        final eg = e.grossSalary * days / sp.daysInMonth;
        final eb = e.basicCharges * days / sp.daysInMonth;
        final m = calc.math;
        final net = eg - m.pf(eb) - m.esic(fullGrossSalary: e.grossSalary, earnedGross: eg) -
            (input.isMsw ? input.mswAmount : 0) -
            m.pt(earnedGross: eg, isFemale: e.gender.toUpperCase() == 'F', isFeb: input.isFeb);
        if (net <= 0) continue;
        if (e.accountNumber.trim().isEmpty || e.ifscCode.trim().isEmpty) continue;
        candidates.add(SalaryDisbursementItemModel(
          disbursementId: 0, employeeId: e.id!, employeeName: e.name,
          bankName: e.bankDetails, accountNumber: e.accountNumber,
          ifscCode: e.ifscCode, amount: net.roundToDouble(), sbCode: '10',
          branch: e.branch,
        ));
      }
      candidates.sort((x, y) =>
          x.employeeName.trim().toLowerCase().compareTo(y.employeeName.trim().toLowerCase()));

      var items = candidates;
      if (idsRaw is List) {
        final wanted = idsRaw.cast<int>().toSet();
        final missing = wanted.difference(candidates.map((c) => c.employeeId).toSet());
        if (missing.isNotEmpty) {
          throw ToolError('Not disbursement candidates for ${sp.periodLabel}: '
              '${missing.join(', ')} (no attendance, net ≤ 0, or missing bank '
              'details). Run with dry_run=true to see the candidates.');
        }
        items = candidates.where((c) => wanted.contains(c.employeeId)).toList();
      }
      if (items.isEmpty) throw ToolError('No disbursement candidates for ${sp.periodLabel}.');

      final already = (await ctx.db.rawQuery('''
        SELECT DISTINCT i.employee_id FROM salary_disbursement_items i
        JOIN salary_disbursements d ON d.id = i.disbursement_id
        WHERE d.month = ? AND d.year = ? AND d.status IN ('generated','exported')''',
          [month, year])).map((r) => r['employee_id'] as int).toSet();

      final total = items.fold(0.0, (s, i) => s + i.amount);
      final preview = {
        'period': sp.periodLabel,
        'employee_count': items.length,
        'total_amount': total,
        'items': [
          for (final i in items)
            {
              'employee_id': i.employeeId, 'name': i.employeeName, 'amount': i.amount,
              'bank': i.bankName, 'ifsc': i.ifscCode,
              if (already.contains(i.employeeId)) 'already_disbursed_this_month': true,
            },
        ],
      };
      if (dryRun) return {'dry_run': true, ...preview};

      final nowLocal = ctx.clock().toLocal().toIso8601String();
      final batch = SalaryDisbursementModel(
        month: month, year: year, deptCode: sp.monthName,
        status: SalaryDisbursementStatus.generated, generatedAt: nowLocal,
      );
      final id = await ctx.store.write((txn) async {
        final id = await txn.insert('salary_disbursements',
            batch.toDbMap()..['created_at'] = nowLocal..['updated_at'] = nowLocal);
        for (final i in items) {
          await txn.insert('salary_disbursement_items',
              i.copyWith(disbursementId: id).toDbMap()..['created_at'] = nowLocal);
        }
        return id;
      });
      final file = await _writeDisbursementExcel(id, out);
      return {'dry_run': false, 'created': true, 'disbursement_id': id, ...preview, 'file': file};
    },
  );

  late final _exportDisb = ToolDef(
    Tool(
      name: 'export_salary_disbursement_excel',
      description: 'Write the bank Excel sheet again for an existing salary '
          'disbursement batch (see list_salary_disbursements).',
      annotations: writeTool('Export salary disbursement Excel'),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'Disbursement batch id.'),
        'output_dir': _outputDir,
      }, required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id', 'output_dir']);
      final id = a.integer('id', required: true, min: 1);
      final out = a.str('output_dir');
      a.check();
      return {'disbursement_id': id, 'file': await _writeDisbursementExcel(id!, out)};
    },
  );

  /// Writes the sheet and marks the batch exported (as the app does).
  Future<Map<String, Object?>> _writeDisbursementExcel(int id, String? out) async {
    final rows = await ctx.db.query('salary_disbursements', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw ToolError('No disbursement batch with id $id.');
    final d = SalaryDisbursementModel.fromDbMap(rows.first);
    final items = (await ctx.db.query('salary_disbursement_items',
            where: 'disbursement_id = ?', whereArgs: [id], orderBy: 'id'))
        .map(SalaryDisbursementItemModel.fromDbMap)
        .toList();
    if (items.isEmpty) throw ToolError('Disbursement batch $id has no items.');
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
        'August', 'September', 'October', 'November', 'December'];
    final monthName = months[d.month - 1];
    final bytes = salaryDisbursementSheet(d, items, await _config(), monthName);
    final file = await _save('salary_disbursement_excel', bytes,
        ExportPathTarget.bankDisbursementExcel, out,
        'Salary_Disbursement_${monthName}_${d.year}.xlsx');
    final now = ctx.clock().toLocal().toIso8601String();
    await ctx.store.write((txn) => txn.update(
        'salary_disbursements',
        {'status': SalaryDisbursementStatus.exported.name, 'exported_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id]));
    return file;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<String> _kinds(Args a, List<String> allowed, List<String> dflt) {
    final list = a.strings('documents', minItems: 1, maxItems: allowed.length);
    if (list == null) return dflt;
    final bad = list.where((k) => !allowed.contains(k)).toList();
    if (bad.isNotEmpty) {
      a.errors.add('documents: unknown ${bad.join(', ')}. Use any of ${allowed.join(', ')}.');
    }
    return list.toSet().toList();
  }

  Future<Map<String, Object?>> _save(String kind, List<int> bytes,
      ExportPathTarget target, String? out, String fileName) async {
    if (bytes.isEmpty) throw ToolError('$kind: generated file was empty.');
    final dir = env.folderFor(target, override: out);
    final path = await env.save(bytes is Uint8List ? bytes : Uint8List.fromList(bytes), dir, fileName);
    return {'document': kind, 'path': path, 'size_kb': (bytes.length / 1024).round()};
  }
}

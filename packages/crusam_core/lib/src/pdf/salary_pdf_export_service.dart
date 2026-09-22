// lib/features/salary/services/salary_pdf_export_service.dart
//
// Salary Slips — two per A4 portrait sheet, separated by a cut line. Each
// slip is built from PdfHouseStyle (letterhead, title, tables, signature,
// page footer), the same house style as every other document.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../export/export_hooks.dart';
import '../models/company_config_model.dart';
import '../models/employee_model.dart';
import 'pdf_house_style.dart';
import '../salary/salary_formula_engine.dart';

class SalaryPdfExportService {
  SalaryPdfExportService._();

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportSalarySlips({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required int                 daysInMonth,
    required bool                isMsw,
    required bool                isFeb,
    pw.EdgeInsets?               margins,
    Map<int, int>?               daysMap,
    double?                      mswAmount,
  }) async {
    final bytes = await buildSalarySlipsBytes(
      config: config,
      employees: employees,
      monthName: monthName,
      year: year,
      daysInMonth: daysInMonth,
      isMsw: isMsw,
      isFeb: isFeb,
      margins: margins,
      daysMap: daysMap,
      mswAmount: mswAmount,
    );
    await ExportHooks.savePdf(
      bytes,
      fileName: 'salary_slips_${monthName.toLowerCase()}_$year',
      target: ExportPathTarget.salary,
    );
  }

  /// Bytes only, no disk write — for email sending and on-screen preview.
  static Future<Uint8List> buildSalarySlipsBytes({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required int                 daysInMonth,
    required bool                isMsw,
    required bool                isFeb,
    pw.EdgeInsets?               margins,
    Map<int, int>?               daysMap,
    double?                      mswAmount,
  }) async {
    await PdfHouseStyle.ensureLoaded();
    final m = margins ?? await PdfHouseStyle.savedMargins();
    // Attendance and MSW default to the app's live salary data.
    final int Function(int) days = daysMap != null
        ? (id) => daysMap[id] ?? 0
        : ExportHooks.liveSalaryDaysFor;
    final msw = mswAmount ?? ExportHooks.liveMswAmount();
    final doc = PdfHouseStyle.newDocument(
        title: 'Salary Slips $monthName $year');

    _SlipCalc calc(EmployeeModel e) => _calc(
        emp: e, daysFor: days, daysInMonth: daysInMonth,
        isMsw: isMsw, isFeb: isFeb, mswAmount: msw);

    final width =
        PdfHouseStyle.formatFor(PdfPageKind.invoice).width - m.left - m.right;

    for (int i = 0; i < employees.length; i += 2) {
      final first = employees[i];
      final second = i + 1 < employees.length ? employees[i + 1] : null;
      final c1 = calc(first);
      final c2 = second != null ? calc(second) : null;

      doc.addPage(PdfHouseStyle.portraitPage(
        margins: m,
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              child: _slip(config, first, c1, monthName, year, width),
            ),
            _cutLine(),
            pw.Expanded(
              child: second != null
                  ? _slip(config, second, c2!, monthName, year, width)
                  : pw.SizedBox(),
            ),
          ],
        ),
      ));
    }

    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    return bytes;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ONE SLIP (half a page)
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _slip(
    CompanyConfigModel config,
    EmployeeModel emp,
    _SlipCalc calc,
    String monthName,
    int year,
    double width,
  ) {
    final t = PdfHouseStyle.text;
    final money = PdfHouseStyle.money;

    pw.Widget detail(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: 72, child: pw.Text(label, style: t())),
              pw.Text(':  ', style: t()),
              pw.Expanded(
                  child: pw.Text(value.isEmpty ? '-' : value,
                      style: t(bold: true))),
            ],
          ),
        );

    return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          PdfHouseStyle.heading(
            config,
            headerHeight: PdfHouseStyle.compactHeaderHeight,
            title: 'Salary Slip',
            subtitle: 'For the month of $monthName $year',
          ),

          // ── Employee details ──
          pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfHouseStyle.ink, width: PdfHouseStyle.rule)),
            child: pw.Table(
              border: const pw.TableBorder(
                  verticalInside: PdfHouseStyle.hairSide),
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(children: [
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Column(children: [
                      detail('Employee Name', _sanitize(emp.name)),
                      detail('Dept / Code', emp.code),
                      detail('Designation', 'Technician'),
                      detail('PF No.', emp.pfNo),
                      detail('UAN No.', emp.uanNo),
                    ]),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Column(children: [
                      detail('Bank Name', _sanitize(emp.bankDetails)),
                      detail('Account No.', emp.accountNumber),
                      detail('IFSC Code', emp.ifscCode),
                    ]),
                  ),
                ]),
              ],
            ),
          ),
          pw.SizedBox(height: 6),

          // ── Earnings & deductions ──
          PdfHouseStyle.dataTable(
            width: width,
            columns: const [
              PdfTableColumn('EARNINGS', 60),
              PdfTableColumn('AMOUNT (₹)', 20, align: pw.TextAlign.right),
              PdfTableColumn('DEDUCTIONS', 60),
              PdfTableColumn('AMOUNT (₹)', 20, align: pw.TextAlign.right),
            ],
            rows: [
              ['Basic Salary', money(calc.eBasic),
               'Provident Fund (12%)', money(calc.pf)],
              ['Other Allowances', money(calc.eOther),
               'ESIC (0.75%)', money(calc.esic)],
              ['', '', 'MSW', money(calc.msw)],
              ['', '', 'Professional Tax', money(calc.pt)],
            ],
            totalRow: [
              'Gross Salary (Earned)', money(calc.eGross),
              'Total Deductions', money(calc.totalDeductions),
            ],
          ),
          pw.SizedBox(height: 6),

          // ── Net pay ──
          pw.Container(
            decoration: pw.BoxDecoration(
                border: pw.Border.all(
                    color: PdfHouseStyle.ink, width: PdfHouseStyle.rule)),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('NET SALARY PAYABLE',
                        style: t(size: 9, bold: true, letterSpacing: 0.7)),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Gross Earned (${money(calc.eGross)}) - '
                      'Deductions (${money(calc.totalDeductions)})',
                      style: t(size: 6.5),
                    ),
                  ],
                ),
                pw.Text('₹ ${money(calc.netPay)}',
                    style: t(size: 11, bold: true)),
              ],
            ),
          ),

          pw.Spacer(),
          PdfHouseStyle.signOff(config),
        ],
    );
  }

  static pw.Widget _cutLine() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 8),
        child: pw.Container(
          height: 0,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(
                color: PdfColors.grey600,
                width: PdfHouseStyle.hairline,
                style: pw.BorderStyle.dashed,
              ),
            ),
          ),
        ),
      );

  // ── Calculation helper (unchanged) ─────────────────────────────────────────

  static _SlipCalc _calc({
    required EmployeeModel      emp,
    required int Function(int) daysFor,
    required int                daysInMonth,
    required bool               isMsw,
    required bool               isFeb,
    required double             mswAmount,
  }) {
    final days   = daysFor(emp.id ?? 0);
    final eB     = daysInMonth == 0 ? 0.0 : emp.basicCharges * days / daysInMonth;
    final eO     = daysInMonth == 0 ? 0.0 : emp.otherCharges * days / daysInMonth;
    final eG     = eB + eO;
    final pf     = SalaryFormulaEngine.pf(eB);
    final esic   = SalaryFormulaEngine.esic(
      fullGrossSalary: emp.grossSalary,
      earnedGross: eG,
    );
    final msw    = isMsw ? mswAmount : 0.0;
    final pt     = SalaryFormulaEngine.pt(
      earnedGross: eG,
      isFemale: emp.gender.toUpperCase() == 'F',
      isFeb: isFeb,
    );
    return _SlipCalc(
        days: days, eBasic: eB, eOther: eO, pf: pf, esic: esic, msw: msw, pt: pt);
  }

  static String _sanitize(String t) => t.replaceAll('−', '-');
}

// ── Calculation value object (unchanged) ──────────────────────────────────────
class _SlipCalc {
  final int    days;
  final double eBasic, eOther, pf, esic, msw, pt;

  _SlipCalc({
    required this.days,   required this.eBasic, required this.eOther,
    required this.pf,     required this.esic,   required this.msw,
    required this.pt,
  });

  double get eGross          => eBasic + eOther;
  double get totalDeductions => pf + esic + msw + pt;
  double get netPay          => eGross - totalDeductions;
}

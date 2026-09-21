// lib/features/salary/services/salary_bill_pdf_service.dart
//
// Salary Invoice, Attachment A and Attachment B — the three invoice-format
// salary documents — plus the finalised bundle (invoice + both attachments
// + salary statement). Every page is built by PdfHouseStyle, the same
// layout the Tax Invoice uses; only the figures differ.

import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../export/export_hooks.dart';
import '../models/company_config_model.dart';
import '../models/employee_model.dart';
import 'pdf_house_style.dart';
import '../salary/salary_formula_engine.dart';
import 'salary_statement_pdf_service.dart';

/// Bill header shared by all three salary invoice pages.
class SalaryBillHeader {
  final String billNo;
  final String date;
  final String poNo;
  final String customerName;
  final String customerAddress;
  final String customerGst;
  final String departmentCode;

  /// e.g. "March 2026" — shown in the subject line.
  final String period;

  const SalaryBillHeader({
    required this.billNo,
    required this.date,
    required this.poNo,
    required this.customerName,
    required this.customerAddress,
    required this.customerGst,
    this.departmentCode = '',
    required this.period,
  });
}

/// Inputs for the salary statement pages appended to the finalised bundle.
class SalaryStatementInput {
  final List<EmployeeModel> employees;
  final String monthName;
  final int year;
  final bool isMsw;
  final double mswAmount;
  final bool isFeb;
  final Map<int, int> daysMap;
  final int daysInMonth;
  final Map<int, double> columnWidths;

  const SalaryStatementInput({
    required this.employees,
    required this.monthName,
    required this.year,
    required this.isMsw,
    required this.mswAmount,
    required this.isFeb,
    required this.daysMap,
    required this.daysInMonth,
    this.columnWidths = const {},
  });
}

class SalaryBillPdfService {
  SalaryBillPdfService._();

  /// 0.13 → "13", 0.0325 → "3.25".
  static String _percent(double rate) {
    final s = (rate * 100).toStringAsFixed(2);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE SPECS
  // ══════════════════════════════════════════════════════════════════════════

  static PdfInvoiceSpec salaryInvoiceSpec({
    required SalaryBillHeader header,
    required String itemDescription,
    required double invoiceBaseAmount,
  }) {
    final money = PdfHouseStyle.money;
    final cgst = invoiceBaseAmount * 0.09;
    final sgst = invoiceBaseAmount * 0.09;
    final totalTax = cgst + sgst;
    final rawTotal = invoiceBaseAmount + totalTax;
    final finalTotal = rawTotal.roundToDouble();
    final roundOff = finalTotal - rawTotal;

    return _spec(
      header: header,
      title: 'Salary Invoice',
      description: itemDescription,
      amount: money(invoiceBaseAmount),
      totals: [
        PdfInvoiceTotal('Total amount before Tax', money(invoiceBaseAmount)),
        PdfInvoiceTotal('Add : CGST 9%', money(cgst)),
        PdfInvoiceTotal('Add : SGST 9%', money(sgst)),
        PdfInvoiceTotal('Total Tax Amount', money(totalTax), bold: true),
        PdfInvoiceTotal(
            'Round Up', '${roundOff >= 0 ? '+' : ''}${money(roundOff)}'),
      ],
      grandTotal:
          PdfInvoiceTotal('Total amount after Tax', '₹ ${money(finalTotal)}'),
      amountInWords: finalTotal,
    );
  }

  static PdfInvoiceSpec attachmentASpec({
    required SalaryBillHeader header,
    required String itemDescription,
    required double itemAmount,
    required double pfAmount,
    required double esicAmount,
  }) {
    final money = PdfHouseStyle.money;
    final cfg = SalaryFormulaEngine.config;
    final subtotal = itemAmount + pfAmount + esicAmount;
    // Same rounding as SalaryStateController.attachmentATotal, so this page
    // shows exactly the amount carried into the Salary Invoice.
    final total = subtotal.ceilToDouble();
    final roundOff = total - subtotal;

    return _spec(
      header: header,
      title: 'Attachment A',
      description: itemDescription,
      amount: money(itemAmount),
      totals: [
        PdfInvoiceTotal('P.F : ${_percent(cfg.employerPfRate)} %',
            money(pfAmount),
            note: '(Total Basic Salary)'),
        PdfInvoiceTotal('ESIC : ${_percent(cfg.employerEsicRate)} %',
            money(esicAmount),
            note: '(Total Gross Salary of Eligibles)'),
        PdfInvoiceTotal(
            'Round Up', '${roundOff >= 0 ? '+' : ''}${money(roundOff)}'),
      ],
      grandTotal: PdfInvoiceTotal('Total Amount', '₹ ${money(total)}'),
      amountInWords: total,
    );
  }

  static PdfInvoiceSpec attachmentBSpec({
    required SalaryBillHeader header,
    required String itemDescription,
    required int employeeCount,
  }) {
    final money = PdfHouseStyle.money;
    final rate = SalaryFormulaEngine.config.attachmentBPerEmployee;
    final total = SalaryFormulaEngine.attachmentBTotal(employeeCount);

    return _spec(
      header: header,
      title: 'Attachment B',
      description: itemDescription,
      qty: employeeCount > 0 ? '$employeeCount' : '-',
      rate: money(rate),
      amount: money(total),
      totals: const [],
      grandTotal: PdfInvoiceTotal('Total Amount', '₹ ${money(total)}'),
      amountInWords: total,
    );
  }

  static PdfInvoiceSpec _spec({
    required SalaryBillHeader header,
    required String title,
    required String description,
    String qty = '',
    String rate = '',
    required String amount,
    required List<PdfInvoiceTotal> totals,
    required PdfInvoiceTotal grandTotal,
    required double amountInWords,
  }) =>
      PdfInvoiceSpec(
        title: title,
        clientName: header.customerName,
        clientAddress: header.customerAddress,
        clientGstin: header.customerGst,
        billNo: header.billNo,
        date: header.date,
        poNo: header.poNo,
        deptCode: header.departmentCode,
        subject: header.period.trim().isEmpty
            ? ''
            : 'For the month of ${header.period}',
        description: description,
        qty: qty,
        rate: rate,
        amount: amount,
        totals: totals,
        grandTotal: grandTotal,
        amountInWords: amountInWords,
      );

  // ══════════════════════════════════════════════════════════════════════════
  // DOCUMENTS
  // ══════════════════════════════════════════════════════════════════════════

  /// Any sequence of invoice pages, optionally followed by salary statement
  /// pages, as one PDF. Margins default to the saved setting.
  static Future<Uint8List> buildBytes({
    required CompanyConfigModel config,
    required List<PdfInvoiceSpec> pages,
    SalaryStatementInput? statement,
    String? departmentCode,
    pw.EdgeInsets? margins,
    String? title,
  }) async {
    await PdfHouseStyle.ensureLoaded();
    final m = margins ?? await PdfHouseStyle.savedMargins();
    final doc = PdfHouseStyle.newDocument(title: title);

    for (final spec in pages) {
      PdfHouseStyle.addInvoicePage(doc, config: config, margins: m, spec: spec);
    }
    if (statement != null) {
      doc.addPage(SalaryStatementPdfService.statementPages(
        config: config,
        margins: m,
        employees: statement.employees,
        monthName: statement.monthName,
        year: statement.year,
        isMsw: statement.isMsw,
        mswAmount: statement.mswAmount,
        isFeb: statement.isFeb,
        daysMap: statement.daysMap,
        daysInMonth: statement.daysInMonth,
        columnWidths: statement.columnWidths,
        departmentCode: departmentCode ?? '',
      ));
    }

    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    return bytes;
  }

  /// Builds and saves to the Salary folder as `<fileName>.pdf`.
  static Future<void> export({
    required CompanyConfigModel config,
    required List<PdfInvoiceSpec> pages,
    SalaryStatementInput? statement,
    String? departmentCode,
    pw.EdgeInsets? margins,
    required String fileName,
  }) async {
    final bytes = await buildBytes(
      config: config,
      pages: pages,
      statement: statement,
      departmentCode: departmentCode,
      margins: margins,
      title: fileName,
    );
    await ExportHooks.savePdf(bytes,
        fileName: fileName, target: ExportPathTarget.salary);
  }
}

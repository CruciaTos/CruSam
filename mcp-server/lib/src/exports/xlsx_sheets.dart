// Excel documents rendered with the pure-Dart `excel` package. The app
// renders the same sheets with Syncfusion XlsIO, which needs Flutter; the
// layouts below follow the app's services cell for cell:
//   • Bank disbursement (voucher)  – crusam/lib/features/vouchers/services/excel_export_service.dart
//   • Salary statement             – crusam/lib/features/salary/services/salary_statement_excel_export_service.dart
//   • Salary disbursement          – crusam/lib/features/salary/services/salary_disbursement_service.dart
// Not reproduced: Excel print-area / fit-to-page settings.

import 'package:crusam_core/crusam_core.dart';
import 'package:excel/excel.dart' as x;

/// Minimal 1-based cell writer over the excel package.
class _Sheet {
  final x.Excel book;
  final x.Sheet sheet;
  _Sheet._(this.book, this.sheet);

  factory _Sheet(String name) {
    final book = x.Excel.createExcel();
    final defaultName = book.getDefaultSheet()!;
    book.rename(defaultName, name);
    return _Sheet._(book, book[name]);
  }

  static final _thin = x.Border(borderStyle: x.BorderStyle.Thin);

  x.CellIndex _i(int row, int col) =>
      x.CellIndex.indexByColumnRow(columnIndex: col - 1, rowIndex: row - 1);

  void width(int col, double w) => sheet.setColumnWidth(col - 1, w);
  void height(int row, double h) => sheet.setRowHeight(row - 1, h);

  void set(
    int row,
    int col,
    Object? value, {
    bool bold = false,
    int? fontSize,
    x.HorizontalAlign align = x.HorizontalAlign.Center,
    bool border = false,
    String? numFmt,
    String? background,
    String? fontColor,
    bool wrap = false,
  }) {
    final cell = sheet.cell(_i(row, col));
    cell.value = switch (value) {
      null => x.TextCellValue(''),
      int v => x.IntCellValue(v),
      double v => x.DoubleCellValue(v),
      _Formula f => x.FormulaCellValue(f.text),
      _ => x.TextCellValue(value.toString()),
    };
    cell.cellStyle = x.CellStyle(
      bold: bold,
      fontSize: fontSize,
      horizontalAlign: align,
      verticalAlign: x.VerticalAlign.Center,
      textWrapping: wrap ? x.TextWrapping.WrapText : null,
      backgroundColorHex: background == null
          ? x.ExcelColor.none
          : x.ExcelColor.fromHexString(background),
      fontColorHex: fontColor == null
          ? x.ExcelColor.black
          : x.ExcelColor.fromHexString(fontColor),
      leftBorder: border ? _thin : null,
      rightBorder: border ? _thin : null,
      topBorder: border ? _thin : null,
      bottomBorder: border ? _thin : null,
      numberFormat: numFmt == null
          ? x.NumFormat.standard_0
          : x.NumFormat.custom(formatCode: numFmt),
    );
  }

  void merge(int row, int fromCol, int toCol) =>
      sheet.merge(_i(row, fromCol), _i(row, toCol));

  List<int> encode() => book.encode()!;
}

class _Formula {
  final String text;
  const _Formula(this.text);
}

String _colLetter(int index) {
  var result = '';
  var n = index;
  while (n > 0) {
    final rem = (n - 1) % 26;
    result = String.fromCharCode(65 + rem) + result;
    n = (n - 1) ~/ 26;
  }
  return result;
}

String _safeSheetName(String s) => s.replaceAll(RegExp(r'[/\\?\*:\[\]]'), '-');

// ══════════════════════════════════════════════════════════════════════════════
// Bank sheet (shared layout of the voucher and salary disbursement sheets)
// ══════════════════════════════════════════════════════════════════════════════

class BankSheetRow {
  final double amount;
  final String ifsc, creditAccount, code, beneficiary, place, bankDetails;
  const BankSheetRow(this.amount, this.ifsc, this.creditAccount, this.code,
      this.beneficiary, this.place, this.bankDetails);
}

const _dataStart = 2; // column B (column A is a narrow blank margin)

List<int> _bankSheet({
  required String sheetName,
  required String title,
  required String deptCode,
  required String placeHeader,
  required String amountFormat,
  required List<BankSheetRow> rows,
  required CompanyConfigModel config,
  required double total,
  required double toOther,
  required double toIdbi,
}) {
  final s = _Sheet(_safeSheetName(sheetName));
  const widths = [3.0, 22.0, 20.0, 14.0, 20.0, 10.0, 22.0, 29.0, 25.0];
  for (var i = 0; i < widths.length; i++) {
    s.width(i + 1, widths[i]);
  }

  // Title (row 2) across Amount..Place, dept code over Bank Details.
  s.set(2, _dataStart, title, bold: true, fontSize: 12, align: x.HorizontalAlign.Left);
  s.merge(2, _dataStart, _dataStart + 5);
  s.set(2, _dataStart + 7, deptCode, bold: true, fontSize: 12, align: x.HorizontalAlign.Right);

  final headers = ['Amount', 'Debit A/C no.', 'IFSC', 'Credit A/c no.', 'Code',
      'Beneficiary', placeHeader, 'Bank Details'];
  for (var i = 0; i < headers.length; i++) {
    s.set(4, _dataStart + i, headers[i], bold: true, border: true);
  }

  var row = 5;
  for (final r in rows) {
    final values = <Object?>[r.amount, config.accountNo, r.ifsc, r.creditAccount,
        r.code, r.beneficiary, r.place, r.bankDetails];
    for (var i = 0; i < values.length; i++) {
      s.set(row, _dataStart + i, values[i],
          border: true, numFmt: i == 0 ? amountFormat : null);
    }
    row++;
  }
  final lastDataRow = row - 1;

  // Total row (one blank row after the data, like the app).
  final totalRow = row + 1;
  final amountCol = _colLetter(_dataStart);
  s.set(totalRow, _dataStart,
      rows.isEmpty ? 0 : _Formula('SUM(${amountCol}5:$amountCol$lastDataRow)'),
      bold: true, border: true, numFmt: amountFormat);
  s.set(totalRow, _dataStart + 1, numberToWords(total), border: true);
  s.merge(totalRow, _dataStart + 1, _dataStart + 3);

  // Bank transfer split box.
  var r = totalRow + 2;
  final valueCol = _dataStart + 3;
  s.set(r, _dataStart, 'BANK TRANSFER SPLIT', bold: true, fontSize: 11,
      align: x.HorizontalAlign.Left, border: true);
  s.merge(r, _dataStart, valueCol);
  r++;
  for (final (label, value) in [
    ('From IDBI to Other Bank', toOther),
    ('From IDBI to IDBI Bank', toIdbi),
  ]) {
    s.set(r, _dataStart, label, fontSize: 11, align: x.HorizontalAlign.Left, border: true);
    s.set(r, valueCol, value, fontSize: 11, align: x.HorizontalAlign.Right,
        border: true, numFmt: '#,##0.00');
    r++;
  }
  r += 2;
  s.set(r, _dataStart, 'Total Base Amount', bold: true, fontSize: 12,
      align: x.HorizontalAlign.Left, border: true);
  s.set(r, valueCol, total, bold: true, fontSize: 12,
      align: x.HorizontalAlign.Right, border: true, numFmt: '#,##0.00');
  return s.encode();
}

bool _isCompanyBank(String ifsc, String bankName, CompanyConfigModel config) {
  final c = config.ifscCode.trim().toUpperCase();
  final prefix = c.length >= 4
      ? c.substring(0, 4)
      : (config.bankName.toLowerCase().contains('idbi') ? 'IBKL' : c);
  return (prefix.isNotEmpty && ifsc.trim().toUpperCase().startsWith(prefix)) ||
      bankName.trim().toLowerCase().contains('idbi');
}

/// Bank disbursement sheet for an invoice (voucher).
List<int> voucherBankSheet(VoucherModel v, CompanyConfigModel config) {
  final rows = [...v.rows]..sort((a, b) {
      if (a.fromDate.isEmpty && b.fromDate.isEmpty) return 0;
      if (a.fromDate.isEmpty) return 1;
      if (b.fromDate.isEmpty) return -1;
      return a.fromDate.compareTo(b.fromDate);
    });
  double toIdbi = 0, toOther = 0;
  for (final r in rows) {
    if (_isCompanyBank(r.ifscCode, r.bankDetails, config)) {
      toIdbi += r.amount;
    } else {
      toOther += r.amount;
    }
  }
  return _bankSheet(
    sheetName: 'Bill-Data-${v.deptCode}',
    title: '${config.companyName} : ${v.title.isEmpty ? 'Expenses Statement' : v.title}',
    deptCode: v.deptCode,
    placeHeader: 'Place',
    amountFormat: '#,##0.00',
    rows: [
      for (final r in rows)
        BankSheetRow(r.amount, r.ifscCode, r.accountNumber, r.sbCode,
            r.employeeName, r.branch, r.bankDetails),
    ],
    config: config,
    total: v.baseTotal,
    toOther: toOther,
    toIdbi: toIdbi,
  );
}

/// Salary disbursement bank sheet for a batch.
List<int> salaryDisbursementSheet(
  SalaryDisbursementModel d,
  List<SalaryDisbursementItemModel> items,
  CompanyConfigModel config,
  String monthName,
) {
  double total = 0, toIdbi = 0, toOther = 0;
  for (final i in items) {
    total += i.amount;
    if (_isCompanyBank(i.ifscCode, i.bankName, config)) {
      toIdbi += i.amount;
    } else {
      toOther += i.amount;
    }
  }
  return _bankSheet(
    sheetName: 'Salary-Disb-${d.deptCode}',
    title: '${config.companyName} : Salary Disbursement — $monthName ${d.year}',
    deptCode: d.deptCode,
    placeHeader: 'Branch',
    amountFormat: '#,##0',
    rows: [
      for (final i in items)
        BankSheetRow(i.amount, i.ifscCode, i.accountNumber, '10',
            i.employeeName, i.branch, i.bankName),
    ],
    config: config,
    total: total,
    toOther: toOther,
    toIdbi: toIdbi,
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// Salary statement
// ══════════════════════════════════════════════════════════════════════════════

List<int> salaryStatementSheet({
  required CompanyConfigModel config,
  required List<EmployeeModel> employees,
  required String monthName,
  required int year,
  required bool isMsw,
  required double mswAmount,
  required bool isFeb,
  required Map<int, int> daysMap,
  required int daysInMonth,
}) {
  const widths = [6.0, 24.0, 14.0, 16.0, 8.0, 8.0, 14.0, 18.0, 12.0, 12.0,
      10.0, 12.0, 10.0, 8.0, 8.0, 8.0, 12.0, 12.0];
  const headers = ['Sr. No', 'Name', 'PF No.', 'UAN No.', 'Code', 'Zone',
      'IFSC', 'Account No.', 'Basic', 'Other', 'Arrears', 'Gross',
      'PF', 'MSW', 'ESIC P', 'P Tax', 'Total Ded.', 'Net Salary'];
  final s = _Sheet('Salary Statement');
  for (var i = 0; i < widths.length; i++) {
    s.width(i + 1, widths[i]);
  }
  s.set(1, 1,
      '${config.companyName}\nSALARY STATEMENT FOR THE MONTH OF ${monthName.toUpperCase()} $year',
      bold: true, fontSize: 14, wrap: true);
  s.merge(1, 1, headers.length);
  s.height(1, 30);
  for (var i = 0; i < headers.length; i++) {
    s.set(2, i + 1, headers[i], bold: true, border: true, background: '#E3E8F4', wrap: true);
  }
  s.height(2, 36);

  final sorted = [...employees]..sort((a, b) {
      final c = a.code.trim().toLowerCase().compareTo(b.code.trim().toLowerCase());
      return c != 0 ? c : a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase());
    });
  const left = x.HorizontalAlign.Left, right = x.HorizontalAlign.Right;
  double sBasic = 0, sOther = 0, sGross = 0, sNet = 0;
  int sPf = 0, sMsw = 0, sEsic = 0, sPt = 0, sTd = 0;
  var row = 3;
  for (var idx = 0; idx < sorted.length; idx++) {
    final e = sorted[idx];
    final days = daysMap[e.id] ?? 0;
    final has = days > 0 && daysInMonth > 0;
    final eb = has ? e.basicCharges * days / daysInMonth : 0.0;
    final eo = has ? e.otherCharges * days / daysInMonth : 0.0;
    final eg = has ? e.grossSalary * days / daysInMonth : 0.0;
    final pf = days > 0 ? SalaryFormulaEngine.pf(eb).round() : 0;
    final esic = SalaryFormulaEngine.esic(fullGrossSalary: e.grossSalary, earnedGross: eg).round();
    final msw = isMsw ? mswAmount.round() : 0;
    final pt = SalaryFormulaEngine.pt(
            earnedGross: eg, isFemale: e.gender.toUpperCase() == 'F', isFeb: isFeb)
        .round();
    final td = pf + esic + msw + pt;
    final net = days > 0 ? eg - td : 0.0;
    sBasic += eb; sOther += eo; sGross += eg; sPf += pf; sMsw += msw;
    sEsic += esic; sPt += pt; sTd += td; sNet += net;

    final grey = days > 0 ? null : '#BBBBBB';
    final cells = <(Object?, x.HorizontalAlign, String?)>[
      ('${idx + 1}', x.HorizontalAlign.Center, null),
      (e.name, left, null), (e.pfNo, left, null), (e.uanNo, left, null),
      (e.code, x.HorizontalAlign.Center, null), (e.zone, x.HorizontalAlign.Center, null),
      (e.ifscCode, left, null), (e.accountNumber, left, null),
      (eb, right, '#,##0'), (eo, right, '#,##0'), (0, x.HorizontalAlign.Center, '#,##0'),
      (eg, right, '#,##0'), (days > 0 ? pf : 0, right, '#,##0'),
      (days > 0 ? msw : 0, x.HorizontalAlign.Center, '#,##0'),
      (days > 0 ? esic : 0, x.HorizontalAlign.Center, '#,##0'),
      (days > 0 ? pt : 0, x.HorizontalAlign.Center, '#,##0'),
      (days > 0 ? td : 0, right, '#,##0'), (net, right, '#,##0'),
    ];
    for (var c = 0; c < cells.length; c++) {
      s.set(row, c + 1, cells[c].$1, align: cells[c].$2, numFmt: cells[c].$3,
          border: true, fontColor: c >= 8 ? grey : null);
    }
    row++;
  }
  final totals = <(Object?, x.HorizontalAlign)>[
    ('TOTAL :-', left), for (var i = 0; i < 7; i++) ('', left),
    (sBasic, right), (sOther, right), (0, x.HorizontalAlign.Center), (sGross, right),
    (sPf, right), (sMsw, x.HorizontalAlign.Center), (sEsic, x.HorizontalAlign.Center),
    (sPt, x.HorizontalAlign.Center), (sTd, right), (sNet, right),
  ];
  for (var c = 0; c < totals.length; c++) {
    s.set(row, c + 1, totals[c].$1, align: totals[c].$2, bold: true, border: true,
        background: '#D6DCF5', numFmt: totals[c].$1 is num ? '#,##0' : null);
  }
  return s.encode();
}

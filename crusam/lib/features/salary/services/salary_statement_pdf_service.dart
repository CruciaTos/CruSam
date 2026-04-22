// lib/features/salary/services/salary_statement_pdf_service.dart
//
// Builds the Salary Statement PDF directly using the pdf/widgets (pw) package.
// Column widths are scaled proportionally so the table fills the full usable
// A4-landscape width — matching the on-screen SalaryStatementPreview exactly.

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../widgets/salary_statement_preview.dart';

class SalaryStatementPdfService {
  SalaryStatementPdfService._();

  // ── Asset / font cache ─────────────────────────────────────────────────────
  static pw.Font? _regular;
  static pw.Font? _bold;
  static pw.MemoryImage? _logo;

  // ── Palette (mirrors _SalaryTable constants) ───────────────────────────────
  static const _black  = PdfColor.fromInt(0xFF000000);
  static const _hdrBg  = PdfColor.fromInt(0xFFE3E8F4);
  static const _totBg  = PdfColor.fromInt(0xFFD6DCF5);
  static const _altBg  = PdfColor.fromInt(0xFFF8FAFC);
  static const _green  = PdfColor.fromInt(0xFF1A6B2F);
  static const _grey   = PdfColor.fromInt(0xFFBBBBBB);

  // ── Layout constants ───────────────────────────────────────────────────────
  static const int    _rowsPerPage = 32;
  static const double _marginPt    = 14.0;

  // A4 landscape width in pt = 841.89; usable after 14pt margins each side:
  static const double _pageAvailableWidth = 841.89 - 2 * _marginPt; // 813.89

  // ── Init ───────────────────────────────────────────────────────────────────
  static Future<void> _init() async {
    _regular ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    _bold    ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
    _logo    ??= await _tryImg('assets/images/aarti_logo.png');
  }

  static Future<pw.MemoryImage?> _tryImg(String path) async {
    try {
      final d = await rootBundle.load(path);
      return pw.MemoryImage(d.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  // ── Text style helper ──────────────────────────────────────────────────────
  static pw.TextStyle _ts({
    double size = 7.0,
    bool bold = false,
    PdfColor? color,
  }) =>
      pw.TextStyle(
        font:       bold ? _bold : _regular,
        fontBold:   _bold,
        fontFallback: [_regular!],
        fontSize:   size,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color:      color ?? _black,
      );

  // ── Scale column widths to fill page exactly ───────────────────────────────
  //
  // Takes the user-supplied (or default) column widths from
  // SalaryStatementPreview.defaultColumnWidths, totals them, then scales
  // every column uniformly so the sum equals _pageAvailableWidth.
  // This is the key step that eliminates the gap seen in the screenshot PDF.
  static Map<int, double> _scaledWidths(Map<int, double> userWidths) {
    double total = 0;
    final effective = <int, double>{};
    for (int i = 0; i <= 17; i++) {
      final w = userWidths[i] ??
          SalaryStatementPreview.defaultColumnWidths[i]!;
      effective[i] = w;
      total += w;
    }
    if (total == 0) return effective;
    final scale = _pageAvailableWidth / total;
    return effective.map((k, v) => MapEntry(k, v * scale));
  }

  // ── Per-employee payroll helpers ───────────────────────────────────────────
  static int _days(EmployeeModel e, Map<int, int> daysMap) =>
      daysMap[e.id ?? -1] ?? 0;

  static double _earnedBasic(EmployeeModel e, int days, int dim) {
    if (days == 0 || dim == 0) return 0;
    return e.basicCharges * days / dim;
  }

  static double _earnedGross(EmployeeModel e, int days, int dim) {
    if (days == 0 || dim == 0) return 0;
    return e.grossSalary * days / dim;
  }

  static int _pf(EmployeeModel e, int days, int dim) {
    final eb = _earnedBasic(e, days, dim);
    return eb == 0 ? 0 : (eb * 0.12).round();
  }

  static int _esic(EmployeeModel e, int days, int dim) {
    if (e.grossSalary >= 21000) return 0;
    final eg = _earnedGross(e, days, dim);
    return eg == 0 ? 0 : (eg * 0.0075).ceil();
  }

  static int _msw(bool isMsw) => isMsw ? 6 : 0;

  static int _pt(EmployeeModel e, int days, int dim, bool isFeb) {
    final eg = _earnedGross(e, days, dim);
    if (eg == 0) return 0;
    final female = e.gender.toUpperCase() == 'F';
    if (female) return eg < 25000 ? 0 : (isFeb ? 300 : 200);
    if (eg < 7500)  return 0;
    if (eg < 10000) return 175;
    return isFeb ? 300 : 200;
  }

  static int _totalDed(EmployeeModel e, int days, int dim, bool isMsw, bool isFeb) =>
      _pf(e, days, dim) + _esic(e, days, dim) + _msw(isMsw) + _pt(e, days, dim, isFeb);

  static double _net(EmployeeModel e, int days, int dim, bool isMsw, bool isFeb) {
    final eg = _earnedGross(e, days, dim);
    return eg == 0 ? 0 : eg - _totalDed(e, days, dim, isMsw, isFeb);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  static Future<void> exportSalaryStatement({
    required CompanyConfigModel  config,
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    required bool                isMsw,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    Map<int, double>             columnWidths = const {},
  }) async {
    await _init();

    // Sort: department code then name (mirrors ExcelExportService._deptThenName)
    final sorted = List<EmployeeModel>.from(employees)
      ..sort((a, b) {
        final c = a.code.trim().toLowerCase()
            .compareTo(b.code.trim().toLowerCase());
        if (c != 0) return c;
        return a.name.trim().toLowerCase()
            .compareTo(b.name.trim().toLowerCase());
      });

    final scaled = _scaledWidths(columnWidths);

    // ── Grand totals (computed over ALL employees, not per-page slice) ────────
    double sumBasic = 0, sumOther = 0, sumGross = 0, sumNet = 0;
    int    sumPf = 0, sumMswAcc = 0, sumEsic = 0, sumPt = 0, sumTd = 0;
    for (final e in sorted) {
      final d = _days(e, daysMap);
      sumBasic    += e.basicCharges;
      sumOther    += e.otherCharges;
      sumGross    += e.grossSalary;
      sumPf       += _pf(e, d, daysInMonth);
      sumMswAcc   += _msw(isMsw);
      sumEsic     += _esic(e, d, daysInMonth);
      sumPt       += _pt(e, d, daysInMonth, isFeb);
      sumTd       += _totalDed(e, d, daysInMonth, isMsw, isFeb);
      sumNet      += _net(e, d, daysInMonth, isMsw, isFeb);
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular!, bold: _bold!),
    );

    final int total     = sorted.length;
    final int pageCount = total == 0 ? 1 : ((total + _rowsPerPage - 1) ~/ _rowsPerPage);

    for (int p = 0; p < pageCount; p++) {
      final start  = p * _rowsPerPage;
      final end    = (start + _rowsPerPage).clamp(0, total);
      final slice  = total == 0 ? <EmployeeModel>[] : sorted.sublist(start, end);
      final isLast = end >= total;

      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin:     const pw.EdgeInsets.all(_marginPt),
        build: (ctx) => _buildPage(
          config:     config,
          slice:      slice,
          startIndex: start,
          showTotals: isLast,
          monthName:  monthName,
          year:       year,
          isMsw:      isMsw,
          isFeb:      isFeb,
          daysMap:    daysMap,
          daysInMonth: daysInMonth,
          scaled:     scaled,
          sumBasic:   sumBasic,
          sumOther:   sumOther,
          sumGross:   sumGross,
          sumPf:      sumPf,
          sumMsw:     sumMswAcc,
          sumEsic:    sumEsic,
          sumPt:      sumPt,
          sumTd:      sumTd,
          sumNet:     sumNet,
        ),
      ));
    }

    // Updated call – target parameter removed
    await _saveAndShare(
      doc,
      'salary_statement_${monthName.toLowerCase()}_$year',
      'Salary Statement',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PAGE LAYOUT
  // ══════════════════════════════════════════════════════════════════════════

  static pw.Widget _buildPage({
    required CompanyConfigModel  config,
    required List<EmployeeModel> slice,
    required int                 startIndex,
    required bool                showTotals,
    required String              monthName,
    required int                 year,
    required bool                isMsw,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    required Map<int, double>    scaled,
    required double sumBasic, required double sumOther, required double sumGross,
    required int    sumPf,    required int    sumMsw,   required int    sumEsic,
    required int    sumPt,    required int    sumTd,    required double sumNet,
  }) =>
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(config, monthName, year),
          pw.SizedBox(height: 6),
          _table(
            slice:      slice,
            startIndex: startIndex,
            showTotals: showTotals,
            isMsw:      isMsw,
            isFeb:      isFeb,
            daysMap:    daysMap,
            daysInMonth: daysInMonth,
            scaled:     scaled,
            sumBasic:   sumBasic,
            sumOther:   sumOther,
            sumGross:   sumGross,
            sumPf:      sumPf,
            sumMsw:     sumMsw,
            sumEsic:    sumEsic,
            sumPt:      sumPt,
            sumTd:      sumTd,
            sumNet:     sumNet,
          ),
        ],
      );

  // ── Page header ────────────────────────────────────────────────────────────
  static pw.Widget _header(
    CompanyConfigModel config,
    String monthName,
    int    year,
  ) =>
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (_logo != null)
            pw.SizedBox(
              width: 70,
              height: 42,
              child: pw.Image(_logo!, fit: pw.BoxFit.contain),
            )
          else
            pw.SizedBox(width: 70, height: 42),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              mainAxisAlignment:  pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  config.companyName.isNotEmpty
                      ? config.companyName
                      : 'Aarti Enterprises',
                  style:     _ts(size: 11, bold: true),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  'SALARY STATEMENT FOR THE MONTH OF '
                  '${monthName.toUpperCase()} $year',
                  style:     _ts(size: 8, bold: true),
                  textAlign: pw.TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      );

  // ── Table ──────────────────────────────────────────────────────────────────
  static pw.Widget _table({
    required List<EmployeeModel> slice,
    required int                 startIndex,
    required bool                showTotals,
    required bool                isMsw,
    required bool                isFeb,
    required Map<int, int>       daysMap,
    required int                 daysInMonth,
    required Map<int, double>    scaled,
    required double sumBasic, required double sumOther, required double sumGross,
    required int    sumPf,    required int    sumMsw,   required int    sumEsic,
    required int    sumPt,    required int    sumTd,    required double sumNet,
  }) {
    // Column widths map for pw.Table
    final cw = <int, pw.TableColumnWidth>{
      for (int i = 0; i <= 17; i++) i: pw.FixedColumnWidth(scaled[i]!)
    };

    // Header labels — match SalaryStatementPreview column labels
    const headers = [
      'Sr.\nNo.',
      'Name of\nTechnician',
      'PF NO.',
      'UAN NO.',
      'Code',
      'Zone',
      'IFSC code',
      'Account\nnumber',
      'Basic',
      'Other',
      'Incr.\nArrs.',
      'Gross\nSalary',
      'PF',
      'MSW',
      'ESIC\nP',
      'P Tax',
      'Total\nDed.',
      'Net Salary',
    ];

    final tableRows = <pw.TableRow>[
      // ── Header row ──────────────────────────────────────────────────────────
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _hdrBg),
        children: headers
            .map((h) => _hdrCell(h))
            .toList(),
      ),
    ];

    // ── Data rows ──────────────────────────────────────────────────────────────
    for (int i = 0; i < slice.length; i++) {
      final e          = slice[i];
      final globalIdx  = startIndex + i;
      final d          = _days(e, daysMap);
      final hasDays    = d > 0;

      final pf         = _pf(e, d, daysInMonth);
      final esic       = _esic(e, d, daysInMonth);
      final mswVal     = _msw(isMsw);
      final pt         = _pt(e, d, daysInMonth, isFeb);
      final td         = _totalDed(e, d, daysInMonth, isMsw, isFeb);
      final net        = _net(e, d, daysInMonth, isMsw, isFeb);

      final rowBg = globalIdx.isOdd ? _altBg : PdfColors.white;

      tableRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(color: rowBg),
        children: [
          _dc('${globalIdx + 1}', center: true),
          _dc(e.name,          left: true,  size: 6.5),
          _dc(e.pfNo,          left: true,  size: 6.0),
          _dc(e.uanNo,         left: true,  size: 6.0),
          _dc(e.code,          center: true),
          _dc(e.zone,          center: true),
          _dc(e.ifscCode,      left: true,  size: 6.0),
          _dc(e.accountNumber, left: true,  size: 6.0),
          _dc(_n(e.basicCharges), right: true),
          _dc(_n(e.otherCharges), right: true),
          _dc('0',             center: true),
          _dc(_n(e.grossSalary), right: true, bold: true),
          hasDays
              ? _dc('$pf',    right: true)
              : _dc('0',      right: true, color: _grey),
          hasDays
              ? _dc('$mswVal', center: true)
              : _dc('0',       center: true, color: _grey),
          hasDays
              ? _dc(esic == 0 ? '0' : '$esic', center: true)
              : _dc('0', center: true, color: _grey),
          hasDays
              ? _dc('$pt',  center: true)
              : _dc('0',    center: true, color: _grey),
          hasDays
              ? _dc('$td',  right: true, bold: true)
              : _dc('0',    right: true, color: _grey),
          hasDays
              ? _dc(_n(net), right: true, color: _green, bold: true)
              : _dc('0',     right: true, color: _grey),
        ],
      ));
    }

    // ── Totals row (last page only) ────────────────────────────────────────────
    if (showTotals) {
      tableRows.add(pw.TableRow(
        decoration: const pw.BoxDecoration(color: _totBg),
        children: [
          _tc('TOTAL :-', left: true),
          _tc(''), _tc(''), _tc(''), _tc(''),
          _tc(''), _tc(''), _tc(''),
          _tc(_n(sumBasic)),
          _tc(_n(sumOther)),
          _tc('0', center: true),
          _tc(_n(sumGross)),
          _tc('$sumPf'),
          _tc('$sumMsw',  center: true),
          _tc('$sumEsic', center: true),
          _tc('$sumPt',   center: true),
          _tc('$sumTd'),
          _tc(_n(sumNet), color: _green),
        ],
      ));
    }

    return pw.Table(
      border:       pw.TableBorder.all(color: _black, width: 0.5),
      columnWidths: cw,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: tableRows,
    );
  }

  // ── Cell helpers ──────────────────────────────────────────────────────────

  /// Header cell — bold, centered, wraps on \n.
  static pw.Widget _hdrCell(String t) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Text(
          t,
          textAlign: pw.TextAlign.center,
          style: _ts(size: 6.5, bold: true),
        ),
      );

  /// Data cell.
  static pw.Widget _dc(
    String t, {
    bool       center = false,
    bool       right  = false,
    bool       left   = false,
    bool       bold   = false,
    double     size   = 7.0,
    PdfColor?  color,
  }) {
    final ta = left
        ? pw.TextAlign.left
        : center
            ? pw.TextAlign.center
            : right
                ? pw.TextAlign.right
                : pw.TextAlign.left;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: pw.Text(
        t,
        textAlign: ta,
        style: _ts(size: size, bold: bold, color: color),
      ),
    );
  }

  /// Totals row cell.
  static pw.Widget _tc(
    String t, {
    bool      center = false,
    bool      left   = false,
    PdfColor? color,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: pw.Text(
          t,
          textAlign: left
              ? pw.TextAlign.left
              : center
                  ? pw.TextAlign.center
                  : pw.TextAlign.right,
          style: _ts(size: 7, bold: true, color: color),
        ),
      );

  static String _n(double v) => v.toStringAsFixed(0);

  // ── Save + Share (PATCH APPLIED) ──────────────────────────────────────────

  /// Prevents overwriting existing files.
  static Future<String> _uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;
    final dot  = basePath.lastIndexOf('.');
    final base = dot == -1 ? basePath : basePath.substring(0, dot);
    final ext  = dot == -1 ? '' : basePath.substring(dot);
    var counter = 1;
    while (true) {
      final candidate = '$base($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }

  /// Saves the PDF silently to disk — no share popup.
  static Future<void> _saveAndShare(
    pw.Document doc,
    String      slug,
    String      subject,   // kept for API compatibility — unused
  ) async {
    final bytes = await doc.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final dir      = await _outputDir();
    final basePath = '${dir.path}${Platform.pathSeparator}$slug.pdf';
    final path     = await _uniquePath(basePath);
    // Task 4: save silently — no Share.shareXFiles call
    await File(path).writeAsBytes(bytes, flush: true);
  }

  /// Determines the output directory:
  /// 1. Salary-specific path (if set)
  /// 2. General PDF path (if set)
  /// 3. System Downloads folder
  /// 4. Application documents directory
  static Future<Directory> _outputDir() async {
    final prefs = ExportPreferencesNotifier.instance;

    // Task 3: check salary-specific path first
    if (prefs.salaryPdfPath.isNotEmpty) {
      final dir = Directory(prefs.salaryPdfPath);
      if (await dir.exists()) return dir;
    }

    // Fall back to general PDF path
    if (prefs.pdfPath.isNotEmpty) {
      final dir = Directory(prefs.pdfPath);
      if (await dir.exists()) return dir;
    }

    // System default
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }
}
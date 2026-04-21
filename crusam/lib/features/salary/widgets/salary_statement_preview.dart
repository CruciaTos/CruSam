import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';

/// Landscape A4 salary statement preview.
///
/// Deductions (PF, MSW, ESIC, PT) and Net Salary are calculated from
/// **prorated (earned)** values based on days present from [daysMap].
/// If an employee has zero days entered, all deduction columns and
/// Net Salary show 0 (greyed out).
///
/// Basic / Other / Gross columns always show full-month structure values.
/// Column widths are fully configurable via [columnWidths].
///
/// Column index map (18 columns total):
///  0  Sr. No        1  Name           2  PF NO.         3  UAN NO.
///  4  Code          5  Zone           6  IFSC           7  Account Number
///  8  Basic         9  Other         10  Arrears        11  Gross
/// 12  PF            13  MSW           14  ESIC P        15  P Tax
/// 16  Total Ded.    17  Net Salary

class SalaryStatementPreview extends StatelessWidget {
  // ── Page dimensions (landscape A4) ────────────────────────────────────────
  static const double pageWidth  = 1122.5;
  static const double pageHeight = 793.7;
  static const int    _rowsPerPage = 32;

  // ── Default column widths ─────────────────────────────────────────────────
  static const Map<int, double> defaultColumnWidths = {
    0:  26,   // Sr. No
    1:  124,  // Name
    2:  84,   // PF NO.
    3:  92,   // UAN NO.
    4:  30,   // Code
    5:  38,   // Zone
    6:  74,   // IFSC
    7:  104,  // Account Number
    8:  50,   // Basic
    9:  50,   // Other
    10: 38,   // Arrears
    11: 54,   // Gross
    12: 36,   // PF
    13: 30,   // MSW
    14: 30,   // ESIC P
    15: 36,   // P Tax
    16: 50,   // Total Ded.
    17: 56,   // Net Salary
  };

  static const List<String> columnLabels = [
    'Sr. No', 'Name', 'PF No.', 'UAN No.', 'Code', 'Zone', 'IFSC',
    'Account No.', 'Basic', 'Other', 'Arrears', 'Gross',
    'PF', 'MSW', 'ESIC P', 'P Tax', 'Total Ded.', 'Net Salary',
  ];

  final CompanyConfigModel  config;
  final EdgeInsets          margins;
  final List<EmployeeModel> employees;
  final String              monthName;
  final int                 year;
  final bool                isMsw;
  final bool                isFeb;

  /// Maps employee ID → days present.  Absent / 0 → deductions all 0.
  final Map<int, int> daysMap;

  /// Total calendar days in the selected month (e.g. 31 for March).
  final int daysInMonth;

  /// Override individual column widths by index (0–17).
  final Map<int, double> columnWidths;

  const SalaryStatementPreview({
    super.key,
    required this.config,
    this.margins      = const EdgeInsets.all(14),
    required this.employees,
    required this.monthName,
    required this.year,
    this.isMsw        = false,
    this.isFeb        = false,
    this.daysMap      = const {},
    this.daysInMonth  = 0,
    this.columnWidths = const {},
  });

  // ── Per-employee helpers ──────────────────────────────────────────────────

  int _days(EmployeeModel e) => daysMap[e.id ?? -1] ?? 0;

  double _earnedBasic(EmployeeModel e) {
    final d = _days(e);
    if (d == 0 || daysInMonth == 0) return 0;
    return e.basicCharges * d / daysInMonth;
  }

  double _earnedGross(EmployeeModel e) {
    final d = _days(e);
    if (d == 0 || daysInMonth == 0) return 0;
    return e.grossSalary * d / daysInMonth;
  }

  int _pf(EmployeeModel e) {
    final eb = _earnedBasic(e);
    return eb == 0 ? 0 : (eb * 0.12).round();
  }

  int _esicInt(EmployeeModel e) {
    if (e.grossSalary >= 21000) return 0;
    final eg = _earnedGross(e);
    return eg == 0 ? 0 : (eg * 0.0075).ceil();
  }

  int _msw() => isMsw ? 6 : 0;

  int _pt(EmployeeModel e) {
    final eg = _earnedGross(e);
    if (eg == 0) return 0;
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale) return eg < 25000 ? 0 : (isFeb ? 300 : 200);
    if (eg < 7500)  return 0;
    if (eg < 10000) return 175;
    return isFeb ? 300 : 200;
  }

  int _totalDed(EmployeeModel e) => _pf(e) + _esicInt(e) + _msw() + _pt(e);

  double _net(EmployeeModel e) {
    final eg = _earnedGross(e);
    return eg == 0 ? 0 : eg - _totalDed(e);
  }

  // ── Effective column-width map (now 0–17) ─────────────────────────────────
  Map<int, TableColumnWidth> _colWidths() {
    final result = <int, TableColumnWidth>{};
    for (int i = 0; i <= 17; i++) {
      result[i] = FixedColumnWidth(columnWidths[i] ?? defaultColumnWidths[i]!);
    }
    return result;
  }

  // ── Static builder for PdfExportService ───────────────────────────────────

  static List<Widget> buildPdfPages({
    required CompanyConfigModel  config,
    EdgeInsets                   margins      = const EdgeInsets.all(14),
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    bool                         isMsw        = false,
    bool                         isFeb        = false,
    Map<int, int>                daysMap      = const {},
    int                          daysInMonth  = 0,
    Map<int, double>             columnWidths = const {},
  }) {
    final preview = SalaryStatementPreview(
      config:       config,
      margins:      margins,
      employees:    employees,
      monthName:    monthName,
      year:         year,
      isMsw:        isMsw,
      isFeb:        isFeb,
      daysMap:      daysMap,
      daysInMonth:  daysInMonth,
      columnWidths: columnWidths,
    );
    if (employees.isEmpty) {
      return [preview._buildPage(slice: const [], startIndex: 0, showTotals: true)];
    }
    final pages = <Widget>[];
    for (int i = 0; i < employees.length; i += _rowsPerPage) {
      final end = (i + _rowsPerPage).clamp(0, employees.length);
      pages.add(preview._buildPage(
        slice:      employees.sublist(i, end),
        startIndex: i,
        showTotals: end >= employees.length,
      ));
    }
    return pages;
  }

  // ── Widget build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final pages = buildPdfPages(
      config:       config,
      margins:      margins,
      employees:    employees,
      monthName:    monthName,
      year:         year,
      isMsw:        isMsw,
      isFeb:        isFeb,
      daysMap:      daysMap,
      daysInMonth:  daysInMonth,
      columnWidths: columnWidths,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < pages.length; i++) ...[
          Align(alignment: Alignment.topCenter, child: pages[i]),
          if (i != pages.length - 1) const SizedBox(height: 24),
        ],
      ],
    );
  }

  // ── Single A4 landscape page ──────────────────────────────────────────────

  Widget _buildPage({
    required List<EmployeeModel> slice,
    required int                 startIndex,
    required bool                showTotals,
  }) {
    return Container(
      width:        pageWidth,
      height:       pageHeight,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: margins,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page header ────────────────────────────────────────────
            _PageHeader(
              config:    config,
              monthName: monthName,
              year:      year,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _SalaryTable(
                slice:      slice,
                startIndex: startIndex,
                showTotals: showTotals,
                preview:    this,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Page header (unchanged) ───────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final CompanyConfigModel config;
  final String monthName;
  final int    year;

  const _PageHeader({
    required this.config,
    required this.monthName,
    required this.year,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Logo
        SizedBox(
          width: 90,
          height: 50,
          child: Image.asset(
            'assets/images/aarti_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const SizedBox(width: 12),
        // Title block
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                config.companyName.isNotEmpty
                    ? config.companyName
                    : 'Aarti Enterprises',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                'SALARY STATEMENT FOR THE MONTH OF '
                '${monthName.toUpperCase()} $year',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SalaryTable — StatelessWidget
// The table is horizontally centered within the available space.
// ══════════════════════════════════════════════════════════════════════════════

class _SalaryTable extends StatelessWidget {
  final List<EmployeeModel>    slice;
  final int                    startIndex;
  final bool                   showTotals;
  final SalaryStatementPreview preview;

  const _SalaryTable({
    required this.slice,
    required this.startIndex,
    required this.showTotals,
    required this.preview,
  });

  static const _hdrBg   = Color(0xFFE3E8F4);
  static const _totBg   = Color(0xFFD6DCF5);
  static const _altBg   = Color(0xFFF8FAFC);
  static const _green   = Color(0xFF1A6B2F);

  static const _hStyle = TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold,  color: Colors.black);
  static const _dStyle = TextStyle(fontSize: 7.5, fontWeight: FontWeight.normal, color: Colors.black);
  static const _dBold  = TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold,  color: Colors.black);
  static const _netStyle  = TextStyle(fontSize: 7.5, fontWeight: FontWeight.bold,  color: _green);
  static const _zeroStyle = TextStyle(fontSize: 7.5, fontWeight: FontWeight.normal, color: Color(0xFFBBBBBB));
  static const _monoStyle = TextStyle(fontSize: 6.5, fontWeight: FontWeight.normal, color: Colors.black, fontFamily: 'monospace');

  double _totalTableWidth() {
    double total = 0;
    for (int i = 0; i <= 17; i++) {
      total += preview.columnWidths[i] ?? SalaryStatementPreview.defaultColumnWidths[i]!;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final totalWidth = _totalTableWidth();

    // Grand totals
    double sumBasic = 0, sumOther = 0, sumGross = 0, sumNet = 0;
    int    sumPf = 0, sumMsw = 0, sumEsicP = 0, sumPt = 0, sumTd = 0;

    for (final e in preview.employees) {
      sumBasic       += e.basicCharges;
      sumOther       += e.otherCharges;
      sumGross       += e.grossSalary;
      sumPf          += preview._pf(e);
      sumMsw         += preview._msw();
      sumEsicP       += preview._esicInt(e);
      sumPt          += preview._pt(e);
      sumTd          += preview._totalDed(e);
      sumNet         += preview._net(e);
    }

    return Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: totalWidth,
        child: Table(
          border:       TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: preview._colWidths(),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [

            // ── Header ────────────────────────────────────────────────────────
            TableRow(
              decoration: const BoxDecoration(color: _hdrBg),
              children: [
                _h('Sr.\nNo.'),
                _h('Name of Technician', left: true),
                _h('PF NO.'),
                _h('UAN NO.'),
                _h('Code'),
                _h('Zone'),
                _h('IFSC code'),
                _h('Account\nnumber'),
                _h('Basic'),
                _h('Other'),
                _h('Increment\nArrs.'),
                _h('Gross\nSalary'),
                _h('PF'),
                _h('MSW'),
                _h('ESIC\nP'),
                _h('P Tax1'),
                _h('Total\nDed.'),
                _h('Net Salary'),
              ],
            ),

            // ── Data rows ─────────────────────────────────────────────────────
            ...slice.asMap().entries.map((entry) {
              final globalIdx   = startIndex + entry.key;
              final e           = entry.value;
              final hasDays     = (preview.daysMap[e.id ?? -1] ?? 0) > 0;
              final pf          = preview._pf(e);
              final eP          = preview._esicInt(e);
              final msw         = preview._msw();
              final pt          = preview._pt(e);
              final td          = preview._totalDed(e);
              final net         = preview._net(e);

              return TableRow(
                decoration: BoxDecoration(
                    color: globalIdx.isOdd ? _altBg : Colors.white),
                children: [
                  _d('${globalIdx + 1}', center: true),
                  _d(e.name, left: true,
                      style: const TextStyle(fontSize: 7.0, color: Colors.black)),
                  _mono(e.pfNo),
                  _mono(e.uanNo),
                  _d(e.code,  center: true),
                  _d(e.zone,  center: true),
                  _mono(e.ifscCode),
                  _mono(e.accountNumber),
                  _d(_n(e.basicCharges), right: true),
                  _d(_n(e.otherCharges), right: true),
                  _d('0', center: true),
                  _d(_n(e.grossSalary),  right: true, style: _dBold),

                  // ── Deduction columns: prorated or zero ───────────────────
                  hasDays
                      ? _d('$pf',  right: true)
                      : _d('0',    right: true, style: _zeroStyle),
                  hasDays
                      ? _d('$msw', center: true)
                      : _d('0',    center: true, style: _zeroStyle),
                  hasDays
                      ? _d(eP == 0 ? '0' : '$eP', center: true)
                      : _d('0', center: true, style: _zeroStyle),
                  hasDays
                      ? _d('$pt', center: true)
                      : _d('0',   center: true, style: _zeroStyle),
                  hasDays
                      ? _d('$td', right: true, style: _dBold)
                      : _d('0',   right: true, style: _zeroStyle),
                  hasDays
                      ? _d(_n(net), right: true, style: _netStyle)
                      : _d('0',    right: true, style: _zeroStyle),
                ],
              );
            }),

            // ── Totals row (last page only) ────────────────────────────────────
            if (showTotals)
              TableRow(
                decoration: const BoxDecoration(color: _totBg),
                children: [
                  _t('TOTAL :-', span: true),
                  _t(''), _t(''), _t(''), _t(''),
                  _t(''), _t(''), _t(''),
                  _t(_n(sumBasic)),
                  _t(_n(sumOther)),
                  _t('0',           center: true),
                  _t(_n(sumGross)),
                  _t('$sumPf'),
                  _t('$sumMsw',   center: true),
                  _t('$sumEsicP', center: true),
                  _t('$sumPt',    center: true),
                  _t('$sumTd'),
                  _t(_n(sumNet),  color: _green),
                ],
              ),
          ],
        ),
      ),
    );
  }

  // ── Cell helpers ──────────────────────────────────────────────────────────

  static Widget _h(String t, {bool left = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Text(t,
            textAlign: left ? TextAlign.left : TextAlign.center,
            style:     _hStyle,
            maxLines:  2,
            overflow:  TextOverflow.ellipsis),
      );

  static Widget _d(
    String t, {
    bool       center = false,
    bool       right  = false,
    bool       left   = false,
    TextStyle? style,
  }) {
    final ta = left   ? TextAlign.left
             : center ? TextAlign.center
             : right  ? TextAlign.right
             :          TextAlign.left;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Text(t,
          textAlign: ta,
          style:     style ?? _dStyle,
          maxLines:  1,
          overflow:  TextOverflow.ellipsis),
    );
  }

  static Widget _mono(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Text(t,
            style:    _monoStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      );

  static Widget _t(
    String t, {
    bool   center = false,
    bool   span   = false,
    Color? color,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Text(
          t,
          textAlign: span   ? TextAlign.left
                   : center ? TextAlign.center
                   :          TextAlign.right,
          style: TextStyle(
            fontSize:   7.5,
            fontWeight: FontWeight.bold,
            color:      color ?? Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );

  static String _n(double v) => v.toStringAsFixed(0);
}
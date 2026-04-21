import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';

/// Landscape A4 salary statement preview.
/// Mirrors the PDF format: company header + full salary table with all
/// statutory deductions (PF, MSW, ESIC, PT) and totals row.
///
/// [_SalaryTable] is a StatefulWidget so its ScrollController has a stable
/// lifecycle and is never created inside build() — fixes the
/// "ScrollController has no ScrollPosition attached" crash.
class SalaryStatementPreview extends StatelessWidget {
  // ── Page dimensions (landscape A4) ────────────────────────────────────────
  static const double pageWidth    = 1122.5;
  static const double pageHeight   = 793.7;
  static const int    _rowsPerPage = 32;

  final CompanyConfigModel  config;
  final EdgeInsets          margins;
  final List<EmployeeModel> employees;
  final String              monthName;
  final int                 year;
  final bool                isMsw;
  final bool                isFeb;

  const SalaryStatementPreview({
    super.key,
    required this.config,
    this.margins   = const EdgeInsets.all(14),
    required this.employees,
    required this.monthName,
    required this.year,
    this.isMsw     = false,
    this.isFeb     = false,
  });

  // ── Statutory helpers (full-month, non-prorated) ───────────────────────────

  static int _pf(EmployeeModel e) => (e.basicCharges * 0.12).round();

  static double _esicDecimal(EmployeeModel e) =>
      e.grossSalary < 21000 ? e.grossSalary * 0.0075 : 0.0;

  static int _esicInt(EmployeeModel e) =>
      e.grossSalary < 21000 ? (e.grossSalary * 0.0075).ceil() : 0;

  static int _msw(bool isMsw) => isMsw ? 6 : 0;

  static int _pt(EmployeeModel e, bool isFeb) {
    final g        = e.grossSalary;
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale)  return g < 25000 ? 0 : (isFeb ? 300 : 200);
    if (g < 7500)  return 0;
    if (g < 10000) return 175;
    return isFeb ? 300 : 200;
  }

  static int _totalDed(EmployeeModel e, bool isMsw, bool isFeb) =>
      _pf(e) + _esicInt(e) + _msw(isMsw) + _pt(e, isFeb);

  static double _net(EmployeeModel e, bool isMsw, bool isFeb) =>
      e.grossSalary - _totalDed(e, isMsw, isFeb);

  // ── Static builder for PdfExportService ───────────────────────────────────

  static List<Widget> buildPdfPages({
    required CompanyConfigModel  config,
    EdgeInsets                   margins   = const EdgeInsets.all(14),
    required List<EmployeeModel> employees,
    required String              monthName,
    required int                 year,
    bool                         isMsw     = false,
    bool                         isFeb     = false,
  }) {
    final preview = SalaryStatementPreview(
      config: config, margins: margins, employees: employees,
      monthName: monthName, year: year, isMsw: isMsw, isFeb: isFeb,
    );
    if (employees.isEmpty) {
      return [preview._buildPage(
          slice: const [], startIndex: 0, showTotals: true)];
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
      config: config, margins: margins, employees: employees,
      monthName: monthName, year: year, isMsw: isMsw, isFeb: isFeb,
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
          BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: margins,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                '${config.companyName.toUpperCase()} — Salary Statement for the Month of '
                '${monthName.toUpperCase()} - $year',
                style: const TextStyle(
                  fontSize:      9.5,
                  fontWeight:    FontWeight.w900,
                  color:         Color(0xFF1A1A1A),
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 6),

            // _SalaryTable is StatefulWidget — owns its ScrollController.
            Expanded(
              child: _SalaryTable(
                slice:        slice,
                startIndex:   startIndex,
                showTotals:   showTotals,
                allEmployees: employees,
                isMsw:        isMsw,
                isFeb:        isFeb,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _SalaryTable
//
// Must be StatefulWidget so _hScroll is created once in initState() and
// disposed in dispose(). Creating a ScrollController inside build() causes
// "ScrollController has no ScrollPosition attached" because the controller
// is re-instantiated on every rebuild before the Scrollbar can attach.
// ══════════════════════════════════════════════════════════════════════════════

class _SalaryTable extends StatefulWidget {
  final List<EmployeeModel> slice;
  final List<EmployeeModel> allEmployees;
  final int                 startIndex;
  final bool                showTotals;
  final bool                isMsw;
  final bool                isFeb;

  const _SalaryTable({
    required this.slice,
    required this.allEmployees,
    required this.startIndex,
    required this.showTotals,
    required this.isMsw,
    required this.isFeb,
  });

  @override
  State<_SalaryTable> createState() => _SalaryTableState();
}

class _SalaryTableState extends State<_SalaryTable> {
  late final ScrollController _hScroll;

  @override
  void initState() {
    super.initState();
    _hScroll = ScrollController(); // created once, stable lifecycle
  }

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  // ── Column widths ─────────────────────────────────────────────────────────
  static const Map<int, TableColumnWidth> _cw = {
    0:  FixedColumnWidth(26),   // Sr. No
    1:  FixedColumnWidth(124),  // Name
    2:  FixedColumnWidth(84),   // PF NO.
    3:  FixedColumnWidth(92),   // UAN NO.
    4:  FixedColumnWidth(30),   // Code
    5:  FixedColumnWidth(38),   // Zone
    6:  FixedColumnWidth(74),   // IFSC
    7:  FixedColumnWidth(104),  // Account number
    8:  FixedColumnWidth(50),   // Basic
    9:  FixedColumnWidth(50),   // Other
    10: FixedColumnWidth(38),   // Arrears
    11: FixedColumnWidth(54),   // Gross
    12: FixedColumnWidth(36),   // PF
    13: FixedColumnWidth(30),   // MSW
    14: FixedColumnWidth(48),   // ESIC1
    15: FixedColumnWidth(30),   // ESIC P
    16: FixedColumnWidth(36),   // P Tax
    17: FixedColumnWidth(50),   // Total Ded.
    18: FixedColumnWidth(56),   // Net Salary
  };

  static const _hdrBg    = Color(0xFFE3E8F4);
  static const _totBg    = Color(0xFFD6DCF5);
  static const _altBg    = Color(0xFFF8FAFC);
  static const _green    = Color(0xFF1A6B2F);

  static const _hStyle = TextStyle(
      fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.black);
  static const _dStyle = TextStyle(
      fontSize: 7.5, fontWeight: FontWeight.normal, color: Colors.black);
  static const _dBold  = TextStyle(
      fontSize: 7.5, fontWeight: FontWeight.bold, color: Colors.black);
  static const _netStyle = TextStyle(
      fontSize: 7.5, fontWeight: FontWeight.bold, color: _green);
  static const _monoStyle = TextStyle(
      fontSize: 6.5, fontWeight: FontWeight.normal,
      color: Colors.black, fontFamily: 'monospace');

  @override
  Widget build(BuildContext context) {
    // Grand totals across ALL employees (not just this page's slice)
    double sumBasic = 0, sumOther = 0, sumGross = 0,
           sumEsic1 = 0, sumNet   = 0;
    int    sumPf = 0, sumMsw = 0, sumEsicP = 0,
           sumPt = 0, sumTd  = 0;

    for (final e in widget.allEmployees) {
      sumBasic  += e.basicCharges;
      sumOther  += e.otherCharges;
      sumGross  += e.grossSalary;
      sumPf     += SalaryStatementPreview._pf(e);
      sumMsw    += SalaryStatementPreview._msw(widget.isMsw);
      sumEsic1  += SalaryStatementPreview._esicDecimal(e);
      sumEsicP  += SalaryStatementPreview._esicInt(e);
      sumPt     += SalaryStatementPreview._pt(e, widget.isFeb);
      sumTd     += SalaryStatementPreview._totalDed(
          e, widget.isMsw, widget.isFeb);
      sumNet    += SalaryStatementPreview._net(
          e, widget.isMsw, widget.isFeb);
    }

    return Scrollbar(
      controller:      _hScroll, // same instance every build
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller:      _hScroll,
        scrollDirection: Axis.horizontal,
        child: Table(
          border:       TableBorder.all(color: Colors.black, width: 0.5),
          columnWidths: _cw,
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Header
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
                _h('ESIC1'),
                _h('ESIC\nP'),
                _h('P Tax1'),
                _h('Total\nDed.'),
                _h('Net Salary'),
              ],
            ),

            // Data rows
            ...widget.slice.asMap().entries.map((entry) {
              final globalIdx = widget.startIndex + entry.key;
              final e   = entry.value;
              final pf  = SalaryStatementPreview._pf(e);
              final e1  = SalaryStatementPreview._esicDecimal(e);
              final eP  = SalaryStatementPreview._esicInt(e);
              final msw = SalaryStatementPreview._msw(widget.isMsw);
              final pt  = SalaryStatementPreview._pt(e, widget.isFeb);
              final td  = SalaryStatementPreview._totalDed(
                  e, widget.isMsw, widget.isFeb);
              final net = SalaryStatementPreview._net(
                  e, widget.isMsw, widget.isFeb);

              return TableRow(
                decoration: BoxDecoration(
                    color: globalIdx.isOdd ? _altBg : Colors.white),
                children: [
                  _d('${globalIdx + 1}',  center: true),
                  _d(e.name,              left: true,
                      style: const TextStyle(
                          fontSize: 7.0, color: Colors.black)),
                  _mono(e.pfNo),
                  _mono(e.uanNo),
                  _d(e.code,              center: true),
                  _d(e.zone,              center: true),
                  _mono(e.ifscCode),
                  _mono(e.accountNumber),
                  _d(_n(e.basicCharges),  right: true),
                  _d(_n(e.otherCharges),  right: true),
                  _d('0',                 center: true),
                  _d(_n(e.grossSalary),   right: true, style: _dBold),
                  _d('$pf',               right: true),
                  _d('$msw',              center: true),
                  _d(e1 == 0 ? '0.00' : e1.toStringAsFixed(2),
                      right: true),
                  _d(eP == 0 ? '0' : '$eP', center: true),
                  _d('$pt',               center: true),
                  _d('$td',               right: true, style: _dBold),
                  _d(_n(net),             right: true, style: _netStyle),
                ],
              );
            }),

            // Totals row (last page only)
            if (widget.showTotals)
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
                  _t('$sumMsw',     center: true),
                  _t(sumEsic1.toStringAsFixed(0)),
                  _t('$sumEsicP',   center: true),
                  _t('$sumPt',      center: true),
                  _t('$sumTd'),
                  _t(_n(sumNet),    color: _green),
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
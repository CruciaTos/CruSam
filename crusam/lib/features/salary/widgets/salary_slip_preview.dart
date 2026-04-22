import 'package:flutter/material.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../../features/salary/notifier/salary_data_notifier.dart';

/// A4 Salary Slip Preview — mirrors a standard payslip format.
/// Designed to be reused across company codes (F&B, I&L, etc.)
/// once categorisation is introduced.
class SalarySlipPreview extends StatelessWidget {
  static const double a4Width = 793.7;
  static const double a4Height = 1122.5;

  // ---------- Configurable Header Height ----------
  // Reduced so two slips fit on one A4 page.
  static const double headerHeight = 72.0;
  // ------------------------------------------------

  final CompanyConfigModel config;
  final EdgeInsets margins;
  final double pageHeight; // New: allows half-height for paired pages

  // ── Placeholder data ────────────────────────────────────────────────────────
  final String employeeName;
  final String employeeCode;
  final String designation;
  final String department;
  final String pfNo;
  final String uanNo;
  final String bankName;
  final String accountNo;
  final String ifscCode;
  final String month;
  final String year;
  final int daysInMonth;
  final int daysPresent;
  final double basicSalary;
  final double otherAllowances;
  final double pfDeduction;
  final double esicDeduction;
  final double mswDeduction;
  final double ptDeduction;

  const SalarySlipPreview({
    super.key,
    required this.config,
    this.margins = const EdgeInsets.all(24),
    this.pageHeight = a4Height, // default full A4
    this.employeeName = 'Employee Name',
    this.employeeCode = '',
    this.designation = 'Technician',
    this.department = 'Food & Beverage',
    this.pfNo = 'MH/212395/XXXX',
    this.uanNo = '10XXXXXXXXXXX',
    this.bankName = 'State Bank Of India',
    this.accountNo = 'XXXXXXXXXXXXXXX',
    this.ifscCode = 'SBIN0000XXX',
    this.month = 'March',
    this.year = '2026',
    this.daysInMonth = 31,
    this.daysPresent = 31,
    this.basicSalary = 0,
    this.otherAllowances = 0,
    this.pfDeduction = 0,
    this.esicDeduction = 0,
    this.mswDeduction = 0,
    this.ptDeduction = 0,
  });

  // ── Derived values ─────────────────────────────────────────────────────────
  double get _earnedBasic =>
      daysInMonth == 0 ? 0 : basicSalary * daysPresent / daysInMonth;

  double get _earnedOther =>
      daysInMonth == 0 ? 0 : otherAllowances * daysPresent / daysInMonth;

  double get _grossEarned => _earnedBasic + _earnedOther;
  double get _totalDeductions =>
      pfDeduction + esicDeduction + mswDeduction + ptDeduction;
  double get _netPay => _grossEarned - _totalDeductions;

  // ── Palette ───────────────────────────────────────────────────────────────
  static const _black = Color(0xFF000000);
  static const _green = Color(0xFF1A6B2F);
  static const _hdrBg = Color(0xFFE3E8F4);
  static const _altBg = Color(0xFFF8FAFC);
  static const _netBg = Color(0xFFD6DCF5);

  static const _bSide = BorderSide(color: _black, width: 0.75);

  // Compact body style — slightly smaller for half-page fit
  static const _body = TextStyle(fontSize: 8.5, color: _black, height: 1.4);

  // ── Static builder for PDF pages (now uses paired pages) ────────────────────
  static List<Widget> buildPdfPages({
    required CompanyConfigModel config,
    required List<EmployeeModel> employees,
    required int Function(int employeeId) getDays,
    required String monthName,
    required int year,
    required int daysInMonth,
    required bool isMsw,
    required bool isFeb,
    EdgeInsets margins = const EdgeInsets.all(24),
  }) {
    final pages = <Widget>[];
    for (int i = 0; i < employees.length; i += 2) {
      final first = employees[i];
      final second = (i + 1 < employees.length) ? employees[i + 1] : null;
      pages.add(
        SalarySlipPairPage(
          employees: [first, if (second != null) second],
          config: config,
          getDays: getDays,
          month: monthName,
          year: year.toString(),
          daysInMonth: daysInMonth,
          isMsw: isMsw,
          isFeb: isFeb,
        ),
      );
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) =>
      Center(child: _buildPage(width: a4Width, height: pageHeight));

  Widget _buildPage({required double width, required double height}) =>
      Container(
        width: width,
        height: height,
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: margins,
          child: DefaultTextStyle(
            style: _body,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(),
                const SizedBox(height: 4),  // was 6
                _divider(1.0),
                const SizedBox(height: 6),  // was 10
                _centreLabel('SALARY SLIP'),
                const SizedBox(height: 2),  // was 4
                _centreSubLabel('For the Month of $month $year'),
                const SizedBox(height: 8),  // was 12
                _employeeDetails(),
                const SizedBox(height: 8),  // was 12
                _earningsAndDeductions(),
                const SizedBox(height: 8),  // was 12
                _netPayBlock(),
                const SizedBox(height: 8),  // was 16
                _footer(),
              ],
            ),
          ),
        ),
      );

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _logo(), // Left: aarti_logo.png
          const SizedBox(width: 20),
          Expanded(child: _letterheadImage()), // Right: letterhead.png
        ],
      );

  Widget _logo() => SizedBox(
        width: 120,   // was 140
        height: headerHeight,
        child: Image.asset(
          'assets/images/aarti_logo.png',
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const _FallbackLogo(),
        ),
      );

  Widget _letterheadImage() => SizedBox(
        height: headerHeight,
        child: Image.asset(
          'assets/images/letterhead.png',
          fit: BoxFit.contain,
          alignment: Alignment.centerRight,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
        ),
      );

  Widget _divider(double t) => Divider(color: _black, thickness: t, height: 4);

  Widget _centreLabel(String text) => Center(
        child: Text(
          text,
          style: _body.copyWith(
            fontSize: 11,       // was 14
            fontWeight: FontWeight.w900,
            decoration: TextDecoration.underline,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _centreSubLabel(String text) => Center(
        child: Text(
          text,
          style: _body.copyWith(
            fontSize: 9,        // was 10
            fontWeight: FontWeight.w700,
            color: _green,
          ),
        ),
      );

  // ── Employee Details Block ────────────────────────────────────────────────
  Widget _employeeDetails() => Container(
        decoration: BoxDecoration(
          border: Border.all(color: _black, width: 0.75),
        ),
        child: Column(
          children: [
            // Header row
            Container(
              color: _hdrBg,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // was 10/6
              width: double.infinity,
              child: Text(
                'Employee Details',
                style: _body.copyWith(fontWeight: FontWeight.w800, fontSize: 9),
              ),
            ),
            const Divider(color: _black, height: 0.75, thickness: 0.75),
            // Two-column detail grid
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6), // was 8
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('Employee Name', employeeName),
                          _detailRow(
                              'Department / Code', '$department ($employeeCode)'),
                          _detailRow('Designation', designation),
                          _detailRow('PF No.', pfNo),
                          _detailRow('UAN No.', uanNo),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 0.75, color: _black),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6), // was 8
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow('Bank Name', bankName),
                          _detailRow('Account No.', accountNo),
                          _detailRow('IFSC Code', ifscCode),
                          _detailRow('Days in Month', daysInMonth.toString()),
                          _detailRow('Days Present', daysPresent.toString()),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3), // was 4
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 95,  // was 100
              child: Text(
                label,
                style: _body.copyWith(color: const Color(0xFF475569)),
              ),
            ),
            Text(':  ', style: _body),
            Expanded(
              child: Text(
                value,
                style: _body.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  // ── Earnings & Deductions Table ───────────────────────────────────────────
  Widget _earningsAndDeductions() => Container(
        decoration: BoxDecoration(
          border: Border.all(color: _black, width: 0.75),
        ),
        child: Column(
          children: [
            // Column headers
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _colHeader('EARNINGS', flex: 60),
                  Container(width: 0.75, color: _black),
                  _colHeader('AMOUNT (₹)', flex: 20, center: true),
                  Container(width: 0.75, color: _black),
                  _colHeader('DEDUCTIONS', flex: 60),
                  Container(width: 0.75, color: _black),
                  _colHeader('AMOUNT (₹)', flex: 20, center: true),
                ],
              ),
            ),
            const Divider(color: _black, height: 0.75, thickness: 0.75),
            // Data rows
            ..._buildEarningsDeductionRows(),
            const Divider(color: _black, height: 0.75, thickness: 0.75),
            // Sub-totals
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _subTotalCell('Gross Salary (Earned)', flex: 60),
                  Container(width: 0.75, color: _black),
                  _subTotalAmount(
                    _grossEarned.toStringAsFixed(2),
                    flex: 20,
                  ),
                  Container(width: 0.75, color: _black),
                  _subTotalCell('Total Deductions', flex: 60),
                  Container(width: 0.75, color: _black),
                  _subTotalAmount(
                    _totalDeductions.toStringAsFixed(2),
                    flex: 20,
                    red: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  List<Widget> _buildEarningsDeductionRows() {
    final earnings = [
      ('Basic Salary (Full)', basicSalary.toStringAsFixed(2)),
      ('Other Allowances (Full)', otherAllowances.toStringAsFixed(2)),
      ('Earned Basic', _earnedBasic.toStringAsFixed(2)),
      ('Earned Allowances', _earnedOther.toStringAsFixed(2)),
    ];
    final deductions = <(String, String, bool)>[
      ('Provident Fund (12%)', pfDeduction.toStringAsFixed(2), false),
      ('ESIC (0.75%)', esicDeduction.toStringAsFixed(2), false),
      ('MSW', mswDeduction.toStringAsFixed(2), false),
      ('Professional Tax', ptDeduction.toStringAsFixed(2), false),
    ];

    final maxRows = earnings.length > deductions.length
        ? earnings.length
        : deductions.length;

    return List.generate(maxRows, (i) {
      final hasEarning = i < earnings.length;
      final hasDeduction = i < deductions.length;
      final isAlt = i.isOdd;

      return Container(
        color: isAlt ? _altBg : Colors.white,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Earning label
              Expanded(
                flex: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), // was 5
                  child: Text(
                    hasEarning ? earnings[i].$1 : '',
                    style: _body,
                  ),
                ),
              ),
              Container(width: 0.75, color: _black),
              // Earning amount
              Expanded(
                flex: 20,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), // was 5
                  child: Text(
                    hasEarning ? earnings[i].$2 : '',
                    textAlign: TextAlign.right,
                    style: _body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Container(width: 0.75, color: _black),
              // Deduction label
              Expanded(
                flex: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), // was 5
                  child: Text(
                    hasDeduction ? deductions[i].$1 : '',
                    style: _body,
                  ),
                ),
              ),
              Container(width: 0.75, color: _black),
              // Deduction amount
              Expanded(
                flex: 20,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), // was 5
                  child: Text(
                    hasDeduction ? deductions[i].$2 : '',
                    textAlign: TextAlign.right,
                    style: _body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasDeduction ? Colors.red.shade700 : _black,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _colHeader(String text, {required int flex, bool center = false}) =>
      Expanded(
        flex: flex,
        child: Container(
          color: _hdrBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // was 6
          child: Text(
            text,
            textAlign: center ? TextAlign.center : TextAlign.left,
            style: _body.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 8.0,  // was 8.5
            ),
          ),
        ),
      );

  Widget _subTotalCell(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Container(
          color: _hdrBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // was 6
          child: Text(
            text,
            style: _body.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );

  Widget _subTotalAmount(String amount, {required int flex, bool red = false}) =>
      Expanded(
        flex: flex,
        child: Container(
          color: _hdrBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // was 6
          child: Text(
            amount,
            textAlign: TextAlign.right,
            style: _body.copyWith(
              fontWeight: FontWeight.w700,
              color: red ? Colors.red.shade700 : _green,
            ),
          ),
        ),
      );

  // ── Net Pay Block ─────────────────────────────────────────────────────────
  Widget _netPayBlock() => Container(
        decoration: BoxDecoration(
          color: _netBg,
          border: Border.all(color: _black, width: 0.75),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // was 12/10
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NET SALARY PAYABLE',
                    style: _body.copyWith(
                      fontSize: 10,   // was 12
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Gross Earned (${_grossEarned.toStringAsFixed(2)}) − Total Deductions (${_totalDeductions.toStringAsFixed(2)})',
                    style: _body.copyWith(
                      fontSize: 7.5,  // was 8
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '₹ ${_netPay.toStringAsFixed(2)}',
              style: _body.copyWith(
                fontSize: 14,   // was 18
                fontWeight: FontWeight.w900,
                color: _green,
              ),
            ),
          ],
        ),
      );

  // ── Footer ────────────────────────────────────────────────────────────────
  Widget _footer() => Column(
        children: [
          const Divider(color: _black, thickness: 0.5),
          const SizedBox(height: 4), // was 6
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [],
                ),
              ),
              const SizedBox(width: 40),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/aarti_signature.png',
                    height: 48,   // was 60
                    
                
                    ),
                ],
              ),
            ],
          ),
        ],
      );
}

// ── Fallback logo ──────────────────────────────────────────────────────────────
class _FallbackLogo extends StatelessWidget {
  const _FallbackLogo();

  @override
  Widget build(BuildContext context) => Container(
        width: 100,   // was 110
        height: SalarySlipPreview.headerHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(46),
          border: Border.all(color: const Color(0xFF1A237E), width: 3),
          color: const Color(0xFF1A237E),
        ),
        alignment: Alignment.center,
        child: const Text(
          'Aarti\nEnterprises',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 9.5,  // was 10
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

/// Widget that displays two salary slips stacked vertically on one A4 page.
class SalarySlipPairPage extends StatelessWidget {
  final List<EmployeeModel> employees; // exactly 2, or 1 with placeholder
  final CompanyConfigModel config;
  final int Function(int employeeId) getDays;
  final String month;
  final String year;
  final int daysInMonth;
  final bool isMsw;
  final bool isFeb;

  const SalarySlipPairPage({
    super.key,
    required this.employees,
    required this.config,
    required this.getDays,
    required this.month,
    required this.year,
    required this.daysInMonth,
    required this.isMsw,
    required this.isFeb,
  }) : assert(employees.length <= 2, 'At most two employees per page');

  @override
  Widget build(BuildContext context) {
    final first = employees.isNotEmpty ? employees[0] : null;
    final second = employees.length > 1 ? employees[1] : null;

    return Container(
      width: SalarySlipPreview.a4Width,
      height: SalarySlipPreview.a4Height,
      color: Colors.white,
      child: Column(
        children: [
          if (first != null)
            Expanded(
              child: _buildSlip(first),
            ),
          if (second != null)
            Expanded(
              child: _buildSlip(second),
            ),
          if (second == null)
            const Spacer(), // empty half if only one slip
        ],
      ),
    );
  }

  Widget _buildSlip(EmployeeModel emp) {
    final days = getDays(emp.id ?? 0);
    final total = daysInMonth;

    // Earnings
    final eBasic = total == 0 ? 0.0 : emp.basicCharges * days / total;
    final eOther = total == 0 ? 0.0 : emp.otherCharges * days / total;
    final eGross = eBasic + eOther;

    // Deductions
    final pf = (eBasic * 0.12).roundToDouble();
    final esicApplicable = emp.grossSalary >= 21000;
    final esic = esicApplicable ? (eGross * 0.0075).ceilToDouble() : 0.0;
    final msw = isMsw ? 6.0 : 0.0;
    final isFemale = emp.gender.toUpperCase() == 'F';
    double pt;
    if (isFemale) {
      pt = eGross < 25000 ? 0 : (isFeb ? 300 : 200);
    } else {
      if (eGross < 7500) {
        pt = 0;
      } else if (eGross < 10000) pt = 175;
      else                     pt = isFeb ? 300 : 200;
    }

    return SalarySlipPreview(
      config: config,
      pageHeight: SalarySlipPreview.a4Height / 2, // half height
      margins: const EdgeInsets.symmetric(horizontal: 24, vertical: 10), // was vertical:12
      employeeName: emp.name,
      employeeCode: emp.code,
      department: _codeToDept(emp.code),
      pfNo: emp.pfNo,
      uanNo: emp.uanNo,
      bankName: emp.bankDetails,
      accountNo: emp.accountNumber,
      ifscCode: emp.ifscCode,
      month: month,
      year: year,
      daysInMonth: total,
      daysPresent: days,
      basicSalary: emp.basicCharges,
      otherAllowances: emp.otherCharges,
      pfDeduction: pf,
      esicDeduction: esic,
      mswDeduction: msw,
      ptDeduction: pt,
    );
  }

  static String _codeToDept(String code) => switch (code.toUpperCase()) {
        'F&B' => 'Food & Beverage',
        'I&L' => 'Infrastructure & Logistics',
        'P&S' => 'Projects & Services',
        'A&P' => 'Administration & Projects',
        _ => code,
      };
}
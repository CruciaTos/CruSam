import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';

class SalaryEntryTable extends StatelessWidget {
  final List<EmployeeModel> employees;
  final int month;
  final int year;
  final int totalDays;
  final bool isMsw;
  final bool isFeb;
  final Map<int, TextEditingController> daysCtrls;
  final Map<int, FocusNode> daysFocusNodes;
  final VoidCallback onDaysChanged;
  final String monthName;

  final double totalsBarGap;
  final double totalsBarHPadding;
  final double totalsBarTopPadding;
  final double totalsBarBottomPadding;

  const SalaryEntryTable({
    super.key,
    required this.employees,
    required this.month,
    required this.year,
    required this.totalDays,
    required this.isMsw,
    required this.isFeb,
    required this.daysCtrls,
    required this.daysFocusNodes,
    required this.onDaysChanged,
    required this.monthName,
    this.totalsBarGap = 8,
    this.totalsBarHPadding = 0,
    this.totalsBarTopPadding = 10,
    this.totalsBarBottomPadding = 10,
  });

  // ── Calculations ────────────────────────────────────────────────────────────
  int _days(EmployeeModel e) {
    final ctrl = daysCtrls[e.id!];
    return (int.tryParse(ctrl?.text ?? '') ?? 0).clamp(0, totalDays);
  }

  double _earnedBasic(EmployeeModel e) =>
      totalDays == 0 ? 0 : e.basicCharges * _days(e) / totalDays;

  double _earnedOther(EmployeeModel e) =>
      totalDays == 0 ? 0 : e.otherCharges * _days(e) / totalDays;

  double _earnedGross(EmployeeModel e) => _earnedBasic(e) + _earnedOther(e);

  int _pf(EmployeeModel e) => (_earnedBasic(e) * 0.12).round();

  bool _esicApplicable(EmployeeModel e) => e.grossSalary > 21000;

  int _esic(EmployeeModel e) {
    if (!_esicApplicable(e)) return 0;
    return (_earnedGross(e) * 0.0075).ceil();
  }

  int _msw() => isMsw ? 6 : 0;

  int _pt(EmployeeModel e) {
    final g = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale) {
      if (g < 25000) return 0;
      return isFeb ? 300 : 200;
    } else {
      if (g < 7500) return 0;
      if (g < 10000) return 175;
      return isFeb ? 300 : 200;
    }
  }

  int _td(EmployeeModel e) => _pf(e) + _esic(e) + _msw() + _pt(e);
  double _net(EmployeeModel e) => _earnedGross(e) - _td(e);

  // ── Focus navigation ────────────────────────────────────────────────────────
  void _focusNextEmployee(EmployeeModel current) {
    final idx = employees.indexOf(current);
    if (idx >= 0 && idx < employees.length - 1) {
      final nextId = employees[idx + 1].id;
      if (nextId != null) daysFocusNodes[nextId]?.requestFocus();
    }
  }

  // ── Column widths ───────────────────────────────────────────────────────────
  Map<int, TableColumnWidth> _colWidths() {
    final cols = <double>[
      48.0,   // Sr.
      240.0,  // Name
      55.0,   // Gender
      100.0,  // Basic
      100.0,  // Other
      110.0,  // Gross (full)
      80.0,   // Days Present
      110.0,  // Earned Gross
      80.0,   // PF
      if (isMsw) 72.0, // MSW – conditional
      100.0,  // ESIC
      80.0,   // PT
      95.0,   // TD
      110.0,  // Net Salary
    ];
    return {for (int i = 0; i < cols.length; i++) i: FixedColumnWidth(cols[i])};
  }

  double get _totalTableWidth {
    return _colWidths().values
        .map((w) => (w as FixedColumnWidth).value)
        .fold(0.0, (a, b) => a + b);
  }

  // ── Headers ──────────────────────────────────────────────────────────────────
  List<Widget> _headers() {
    final labels = [
      'Sr.', 'Name', 'Gender',
      'Basic', 'Other', 'Gross',
      'Days\nPresent', 'Earned\nGross',
      'Provident\n Fund(12%)',
      if (isMsw) 'MSW\n(₹6)',
      'ESIC\n(0.75%)',
      'Prof.\nTax',
      'Total\nDeductions',
      'Net\nSalary',
    ];
    return labels.map((l) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Text(l,
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(color: AppColors.slate400)),
    )).toList();
  }

  // ── Data rows ────────────────────────────────────────────────────────────────
  TableRow _dataRow(EmployeeModel e, int idx) {
    final bg = idx.isEven ? AppColors.white : const Color(0xFFF8FAFC);
    final pf = _pf(e);
    final esic = _esic(e);
    final msw = _msw();
    final pt = _pt(e);
    final td = _td(e);
    final net = _net(e);
    final earned = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';

    return TableRow(
      decoration: BoxDecoration(
        color: bg,
        border: const Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      children: [
        // Sr. No.
        _cTxt(e.srNo == 0 ? '—' : e.srNo.toString()),
        // Name
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Text(e.name,
                style: AppTextStyles.bodyMedium,
                overflow: TextOverflow.ellipsis),
          ),
        ),
        // Gender badge
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isFemale
                  ? const Color(0xFFFCE7F3)
                  : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isFemale ? 'F' : 'M',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isFemale ? const Color(0xFFBE185D) : AppColors.blue600,
              ),
            ),
          ),
        ),
        _cNum(e.basicCharges),
        _cNum(e.otherCharges),
        _cNum(e.grossSalary, bold: true),
        // Days input — empty by default, Enter moves to next row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Align(
            alignment: Alignment.center,
            child: _DaysField(
              key: ValueKey('d_${e.id}_${month}_$year'),
              controller: daysCtrls[e.id!]!,
              focusNode: daysFocusNodes[e.id],
              max: totalDays,
              onChanged: (_) => onDaysChanged(),
              onSubmitted: () => _focusNextEmployee(e),
            ),
          ),
        ),
        _cNum(earned, bold: true, color: AppColors.indigo600),
        _cDeduction(pf),
        if (isMsw) _cDeduction(msw, color: AppColors.amber700),
        _esicApplicable(e)
            ? _cDeduction(esic)
            : _cBadge('N/A', AppColors.slate300),
        pt == 0
            ? _cBadge('—', AppColors.slate300)
            : _cDeduction(pt),
        // TD cell (red background)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFFFF1F1),
          child: Center(
            child: Text(
              td == 0 ? '—' : '₹$td',
              style: AppTextStyles.bodySemi.copyWith(
                  color: Colors.red.shade700, fontSize: 12),
            ),
          ),
        ),
        // Net cell (green background)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFF0FDF4),
          child: Center(
            child: Text(
              net <= 0 ? '—' : '₹${net.toStringAsFixed(0)}',
              style: AppTextStyles.bodySemi.copyWith(
                  color: AppColors.emerald700, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Totals bar ──────────────────────────────────────────────────────────────
  Widget _totalsBar(double totalWidth) {
    final totalPf = employees.fold(0, (s, e) => s + _pf(e));
    final totalEsic = employees.fold(0, (s, e) => s + _esic(e));
    final totalMsw = isMsw ? employees.length * 6 : 0;
    final totalPt = employees.fold(0, (s, e) => s + _pt(e));
    final totalTd = employees.fold(0, (s, e) => s + _td(e));
    final totalNet = employees.fold(0.0, (s, e) => s + _net(e));
    final totalEarned = employees.fold(0.0, (s, e) => s + _earnedGross(e));

    final content = SizedBox(
      width: totalWidth,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16,
          totalsBarTopPadding,
          16,
          totalsBarBottomPadding,
        ),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Wrap(
          spacing: 24,
          runSpacing: 6,
          children: [
            _chip('Earned Gross', ' ₹${totalEarned.toStringAsFixed(0)}', AppColors.indigo400),
            _chip('Total PF', ' ₹$totalPf', AppColors.slate400),
            if (isMsw) _chip('Total MSW', ' ₹$totalMsw', AppColors.amber700),
            _chip('Total ESIC', ' ₹$totalEsic', AppColors.slate400),
            _chip('Total PT', ' ₹$totalPt', AppColors.slate400),
            _chip('Total T.D.', ' ₹$totalTd', Colors.redAccent),
            _chip('Net Payable', ' ₹${totalNet.toStringAsFixed(0)}', AppColors.emerald700),
          ],
        ),
      ),
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: content,
    );
  }

  static Widget _chip(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ', style: AppTextStyles.body.copyWith(color: AppColors.slate500)),
      Text(value, style: AppTextStyles.bodyMedium.copyWith(color: color, fontSize: 14)),
    ],
  );

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final totalWidth = _totalTableWidth;
    final hScroll = ScrollController();
    final vScroll = ScrollController();

    return Column(
      children: [
        _totalsBar(totalWidth),
        SizedBox(height: totalsBarGap),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              child: Scrollbar(
                controller: hScroll,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: hScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalWidth,
                    child: Scrollbar(
                      controller: vScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: vScroll,
                        child: Table(
                          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                          columnWidths: _colWidths(),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(color: AppColors.slate900),
                              children: _headers(),
                            ),
                            ...employees.asMap().entries.map(
                              (entry) => _dataRow(entry.value, entry.key),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Cell helpers ────────────────────────────────────────────────────────────
  static Widget _cTxt(String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(
      child: Text(t, textAlign: TextAlign.center, style: AppTextStyles.body),
    ),
  );

  static Widget _cNum(double v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(
      child: Text(
        v == 0 ? '—' : '₹${v.toStringAsFixed(0)}',
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(
          fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
          color: color ?? AppColors.slate700,
          fontSize: 12,
        ),
      ),
    ),
  );

  static Widget _cDeduction(int v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(
      child: Text(
        v == 0 ? '—' : '₹$v',
        textAlign: TextAlign.center,
        style: AppTextStyles.body.copyWith(
          color: color ?? Colors.red.shade400,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );

  static Widget _cBadge(String label, Color color) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
    ),
  );
}

// ── Days input field ───────────────────────────────────────────────────────────
class _DaysField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final int max;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  const _DaysField({
    super.key,
    required this.controller,
    this.focusNode,
    required this.max,
    required this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    width: 70,
    child: TextField(
      controller: controller,
      focusNode: focusNode,
      textAlign: TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _MaxValueFormatter(),   // ← updated: no argument, 2‑digit limit only
      ],
      style: AppTextStyles.input.copyWith(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: '0',
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.slate300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: AppColors.indigo500, width: 1.5),
        ),
      ),
      onChanged: onChanged,
      onSubmitted: (value) {
        final v = int.tryParse(value) ?? 0;
        if (v > max) {
          controller.clear();   // reset to empty
          onChanged('');        // trigger recalculation → shows — in row
        }
        onSubmitted?.call();    // always move focus to next employee
      },
    ),
  );
}

// ── Max value formatter (2‑digit limit only) ──────────────────────────────────
class _MaxValueFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > 2) return oldValue; // 2‑digit limit only
    return newValue;
  }
}
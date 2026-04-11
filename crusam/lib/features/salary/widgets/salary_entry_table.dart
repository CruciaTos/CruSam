import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';

class SalaryEntryTable extends StatelessWidget {
  final List<EmployeeModel>            employees;
  final int                            month;
  final int                            year;
  final int                            totalDays;
  final bool                           isMsw;
  final bool                           isFeb;
  final Map<int, TextEditingController> daysCtrls;
  final VoidCallback                   onDaysChanged;
  final String                         monthName;

  const SalaryEntryTable({
    super.key,
    required this.employees,
    required this.month,
    required this.year,
    required this.totalDays,
    required this.isMsw,
    required this.isFeb,
    required this.daysCtrls,
    required this.onDaysChanged,
    required this.monthName,
  });

  // ── Calculations ────────────────────────────────────────────────────────────
  int _days(EmployeeModel e) {
    final ctrl = daysCtrls[e.id!];
    return (int.tryParse(ctrl?.text ?? '') ?? totalDays).clamp(0, totalDays);
  }

  double _earnedBasic(EmployeeModel e) =>
      totalDays == 0 ? 0 : e.basicCharges * _days(e) / totalDays;

  double _earnedOther(EmployeeModel e) =>
      totalDays == 0 ? 0 : e.otherCharges * _days(e) / totalDays;

  double _earnedGross(EmployeeModel e) => _earnedBasic(e) + _earnedOther(e);

  /// PF = 12% of earned basic, round normally
  int _pf(EmployeeModel e) => (_earnedBasic(e) * 0.12).round();

  /// ESIC: applicable only if contracted gross > 21000
  /// Rate = 0.75% of earned gross, ALWAYS ceiling (round up even at 0.1)
  bool _esicApplicable(EmployeeModel e) => e.grossSalary > 21000;

  int _esic(EmployeeModel e) {
    if (!_esicApplicable(e)) return 0;
    return (_earnedGross(e) * 0.0075).ceil();
  }

  /// MSW = ₹6 per employee, only June & December
  int _msw() => isMsw ? 6 : 0;

  /// Professional Tax (Maharashtra slab)
  /// Male   : <7500→0 | 7500-9999→175 | ≥10000→200 (300 in Feb)
  /// Female : <25000→0 | ≥25000→200 (300 in Feb)
  int _pt(EmployeeModel e) {
    final g        = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale) {
      if (g < 25000) return 0;
      return isFeb ? 300 : 200;
    } else {
      if (g < 7500)  return 0;
      if (g < 10000) return 175;
      return isFeb ? 300 : 200;
    }
  }

  int    _td(EmployeeModel e)  => _pf(e) + _esic(e) + _msw() + _pt(e);
  double _net(EmployeeModel e) => _earnedGross(e) - _td(e);

  // ── Column widths ──────────────────────────────────────────────────────────
  Map<int, TableColumnWidth> _colWidths() {
    final cols = [
      40.0,   // Sr
      190.0,  // Name
      44.0,   // Gender
      85.0,   // Basic (contracted)
      85.0,   // Other (contracted)
      90.0,   // Gross (contracted)
      72.0,   // Days input
      95.0,   // Earned Gross
      72.0,   // PF
      if (isMsw) 60.0, // MSW
      90.0,   // ESIC
      72.0,   // PT
      85.0,   // TD
      95.0,   // Net
    ];
    return {for (var i = 0; i < cols.length; i++) i: FixedColumnWidth(cols[i])};
  }

  // ── Headers ────────────────────────────────────────────────────────────────
  List<Widget> _headers() {
    final labels = [
      'Sr.', 'Name', 'Gender',
      'Basic', 'Other', 'Gross\n(full)',
      'Days\nPresent', 'Earned\nGross',
      'PF\n12%',
      if (isMsw) 'MSW\n₹6',
      'ESIC\n0.75%',
      'Prof.\nTax',
      'T.D.',
      'Net\nSalary',
    ];
    return labels.map((l) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      child: Text(l,
          textAlign: TextAlign.center,
          style: AppTextStyles.label.copyWith(color: AppColors.slate400)),
    )).toList();
  }

  // ── Data rows ──────────────────────────────────────────────────────────────
  TableRow _dataRow(EmployeeModel e, int idx) {
    final bg       = idx.isEven ? AppColors.white : const Color(0xFFF8FAFC);
    final pf       = _pf(e);
    final esic     = _esic(e);
    final msw      = _msw();
    final pt       = _pt(e);
    final td       = _td(e);
    final net      = _net(e);
    final earned   = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';

    return TableRow(
      decoration: BoxDecoration(
        color: bg,
        border: const Border(bottom: BorderSide(color: AppColors.slate100)),
      ),
      children: [
        _cTxt(e.srNo == 0 ? '—' : e.srNo.toString(), center: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(e.name,
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.ellipsis),
        ),
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
                color: isFemale
                    ? const Color(0xFFBE185D)
                    : AppColors.blue600,
              ),
            ),
          ),
        ),
        _cNum(e.basicCharges),
        _cNum(e.otherCharges),
        _cNum(e.grossSalary, bold: true),
        // Days present — editable input
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: _DaysField(
            key: ValueKey('d_${e.id}_${month}_$year'),
            controller: daysCtrls[e.id!]!,
            max: totalDays,
            onChanged: (_) => onDaysChanged(),
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
        // Total Deductions — red tint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFFFF1F1),
          child: Text(
            td == 0 ? '—' : '₹$td',
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySemi.copyWith(
                color: Colors.red.shade700, fontSize: 12),
          ),
        ),
        // Net — green tint
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFF0FDF4),
          child: Text(
            net <= 0 ? '—' : '₹${net.toStringAsFixed(0)}',
            textAlign: TextAlign.right,
            style: AppTextStyles.bodySemi.copyWith(
                color: AppColors.emerald700, fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ── Totals footer ──────────────────────────────────────────────────────────
  Widget _totalsFooter() {
    final totalPf     = employees.fold(0, (s, e) => s + _pf(e));
    final totalEsic   = employees.fold(0, (s, e) => s + _esic(e));
    final totalMsw    = isMsw ? employees.length * 6 : 0;
    final totalPt     = employees.fold(0, (s, e) => s + _pt(e));
    final totalTd     = employees.fold(0, (s, e) => s + _td(e));
    final totalNet    = employees.fold(0.0, (s, e) => s + _net(e));
    final totalEarned = employees.fold(0.0, (s, e) => s + _earnedGross(e));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.slate900,
        border: Border(top: BorderSide(color: AppColors.slate700)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 6,
        children: [
          _chip('Earned Gross', '₹${totalEarned.toStringAsFixed(0)}', AppColors.indigo400),
          _chip('Total PF',     '₹$totalPf',  AppColors.slate400),
          if (isMsw) _chip('Total MSW', '₹$totalMsw', AppColors.amber700),
          _chip('Total ESIC',   '₹$totalEsic', AppColors.slate400),
          _chip('Total PT',     '₹$totalPt',  AppColors.slate400),
          _chip('Total T.D.',   '₹$totalTd',  Colors.redAccent),
          _chip('Net Payable',  '₹${totalNet.toStringAsFixed(0)}', AppColors.emerald700),
        ],
      ),
    );
  }

  static Widget _chip(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ', style: AppTextStyles.small.copyWith(color: AppColors.slate500)),
      Text(value, style: AppTextStyles.bodyMedium.copyWith(color: color, fontSize: 13)),
    ],
  );

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hScroll = ScrollController();
    final vScroll = ScrollController();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Column(children: [
          // Info bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.slate50,
            child: Row(children: [
              Text('$monthName $year  •  $totalDays days in month',
                  style: AppTextStyles.bodyMedium),
              const Spacer(),
              Text('${employees.length} employees', style: AppTextStyles.small),
            ]),
          ),
          const Divider(height: 1, color: AppColors.slate200),
          // Table
          Expanded(
            child: Scrollbar(
              controller: hScroll,
              thumbVisibility: true,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: hScroll,
                scrollDirection: Axis.horizontal,
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
          _totalsFooter(),
        ]),
      ),
    );
  }

  // ── Cell helpers ───────────────────────────────────────────────────────────
  static Widget _cTxt(String t, {bool center = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(t,
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: AppTextStyles.body),
  );

  static Widget _cNum(double v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(
      v == 0 ? '—' : '₹${v.toStringAsFixed(0)}',
      textAlign: TextAlign.right,
      style: AppTextStyles.body.copyWith(
        fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
        color: color ?? AppColors.slate700,
        fontSize: 12,
      ),
    ),
  );

  static Widget _cDeduction(int v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Text(
      v == 0 ? '—' : '₹$v',
      textAlign: TextAlign.right,
      style: AppTextStyles.body.copyWith(
        color: color ?? Colors.red.shade400,
        fontSize: 12,
        fontWeight: FontWeight.w500,
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
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    ),
  );
}

// ── Days input field ───────────────────────────────────────────────────────────
class _DaysField extends StatelessWidget {
  final TextEditingController controller;
  final int                   max;
  final ValueChanged<String>  onChanged;

  const _DaysField({
    super.key,
    required this.controller,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 32,
    child: TextField(
      controller: controller,
      textAlign: TextAlign.center,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        _MaxValueFormatter(max),
      ],
      style: AppTextStyles.input.copyWith(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: max.toString(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
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
    ),
  );
}

class _MaxValueFormatter extends TextInputFormatter {
  final int max;
  const _MaxValueFormatter(this.max);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue n) {
    final v = int.tryParse(n.text);
    if (v != null && v > max) {
      final s = max.toString();
      return TextEditingValue(
          text: s, selection: TextSelection.collapsed(offset: s.length));
    }
    return n;
  }
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';

class SalaryEntryTable extends StatefulWidget {
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

  @override
  State<SalaryEntryTable> createState() => _SalaryEntryTableState();
}

class _SalaryEntryTableState extends State<SalaryEntryTable> {
  late final ScrollController _hScrollController;
  late final ScrollController _vScrollController;

  @override
  void initState() {
    super.initState();
    _hScrollController = ScrollController();
    _vScrollController = ScrollController();
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    _vScrollController.dispose();
    super.dispose();
  }

  // ── Sorted employees (alphabetically by name) ────────────────────────────────
  List<EmployeeModel> get _sortedEmployees {
    final sorted = List<EmployeeModel>.from(widget.employees);
    sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return sorted;
  }

  // ── Calculations ─────────────────────────────────────────────────────────────
  int _days(EmployeeModel e) {
    final ctrl = widget.daysCtrls[e.id!];
    return (int.tryParse(ctrl?.text ?? '') ?? 0).clamp(0, widget.totalDays);
  }

  double _earnedBasic(EmployeeModel e) =>
      widget.totalDays == 0 ? 0 : e.basicCharges * _days(e) / widget.totalDays;

  double _earnedOther(EmployeeModel e) =>
      widget.totalDays == 0 ? 0 : e.otherCharges * _days(e) / widget.totalDays;

  double _earnedGross(EmployeeModel e) => _earnedBasic(e) + _earnedOther(e);

  int _pf(EmployeeModel e) => (_earnedBasic(e) * 0.12).round();

  bool _esicApplicable(EmployeeModel e) => e.grossSalary >= 21000;

  int _esic(EmployeeModel e) {
    if (!_esicApplicable(e)) return 0;
    return (_earnedGross(e) * 0.0075).ceil();
  }

  int _msw() => widget.isMsw ? 6 : 0;

  int _pt(EmployeeModel e) {
    final g = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale) {
      if (g < 25000) return 0;
      return widget.isFeb ? 300 : 200;
    } else {
      if (g < 7500) return 0;
      if (g < 10000) return 175;
      return widget.isFeb ? 300 : 200;
    }
  }

  int _td(EmployeeModel e) => _pf(e) + _esic(e) + _msw() + _pt(e);
  double _net(EmployeeModel e) => _earnedGross(e) - _td(e);

  void _focusNextEmployee(EmployeeModel current) {
    final sorted = _sortedEmployees;
    final idx = sorted.indexOf(current);
    if (idx >= 0 && idx < sorted.length - 1) {
      final nextId = sorted[idx + 1].id;
      if (nextId != null) widget.daysFocusNodes[nextId]?.requestFocus();
    }
  }

  // ── Column widths: fixed Name + flexible rest ────────────────────────────────
  Map<int, TableColumnWidth> _colWidths() {
    // Column indices:
    // 0: Sr.   1: Name   2: Gender   3: Basic   4: Other   5: Gross
    // 6: Days  7: Earned Gross   8: PF   9: MSW (optional)  10/9: ESIC
    // 11/10: PT   12/11: Total Deductions   13/12: Net Salary
    final nameColIndex = 1;
    final int totalCols = widget.isMsw ? 14 : 13;

    final Map<int, TableColumnWidth> widths = {};
    for (int i = 0; i < totalCols; i++) {
      if (i == nameColIndex) {
        // Fixed width for Name – reduced to 300
        widths[i] = const FixedColumnWidth(300.0);
      } else {
        // Flexible columns – share remaining space proportionally
        double flex;
        if (i == 0) {
          flex = 0.5; // Sr.
        } else if (i == 2) {
          flex = 0.7; // Gender – increased from 0.6
        } else if (i == 3 || i == 4 || i == 5) {
          flex = 1.0; // Basic / Other / Gross
        } else if (i == 6) {
          flex = 0.8; // Days
        } else if (i == 7) {
          flex = 1.0; // Earned Gross
        } else if (i == 8) {
          flex = 1.0; // PF
        } else if (widget.isMsw && i == 9) {
          flex = 0.8; // MSW
        } else if ((widget.isMsw && i == 10) || (!widget.isMsw && i == 9)) {
          flex = 0.9; // ESIC
        } else if ((widget.isMsw && i == 11) || (!widget.isMsw && i == 10)) {
          flex = 0.8; // PT
        } else if ((widget.isMsw && i == 12) || (!widget.isMsw && i == 11)) {
          flex = 1.0; // Total Deductions
        } else if ((widget.isMsw && i == 13) || (!widget.isMsw && i == 12)) {
          flex = 1.0; // Net Salary
        } else {
          flex = 1.0;
        }
        widths[i] = FlexColumnWidth(flex);
      }
    }
    return widths;
  }

  // ── Headers ───────────────────────────────────────────────────────────────────
  List<Widget> _headers() {
    final labels = [
      'Sr.', 'Name', 'Gender',
      'Basic', 'Other', 'Gross',
      'Days\nPresent', 'Earned\nGross',
      'Provident\nFund (12%)',
      if (widget.isMsw) 'MSW\n(₹6)',
      'ESIC\n(0.75%)',
      'Prof.\nTax',
      'Total\nDeductions',
      'Net\nSalary',
    ];
    return labels.asMap().entries.map((entry) {
      final idx = entry.key;
      final label = entry.value;
      final isNameColumn = (idx == 1); // Name is index 1

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        alignment: isNameColumn ? Alignment.centerLeft : Alignment.center,
        child: Text(
          label,
          textAlign: isNameColumn ? TextAlign.left : TextAlign.center,
          style: AppTextStyles.label.copyWith(color: AppColors.slate400),
        ),
      );
    }).toList();
  }

  // ── Data row ──────────────────────────────────────────────────────────────────
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
        _cTxt((idx + 1).toString()),
        // Name cell – left aligned
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              e.name,
              style: AppTextStyles.bodyMedium,
              overflow: TextOverflow.visible,
              softWrap: false,
            ),
          ),
        ),
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              isFemale ? 'F' : 'M',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: isFemale ? const Color(0xFFBE185D) : AppColors.blue600),
            ),
          ),
        ),
        _cNum(e.basicCharges),
        _cNum(e.otherCharges),
        _cNum(e.grossSalary, bold: true),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Align(
            alignment: Alignment.center,
            child: _DaysField(
              key: ValueKey('d_${e.id}_${widget.month}_${widget.year}'),
              controller: widget.daysCtrls[e.id!]!,
              focusNode: widget.daysFocusNodes[e.id],
              max: widget.totalDays,
              onChanged: (_) => widget.onDaysChanged(),
              onSubmitted: () => _focusNextEmployee(e),
            ),
          ),
        ),
        _cNum(earned, bold: true, color: AppColors.indigo600),
        _cDeduction(pf),
        if (widget.isMsw) _cDeduction(msw, color: AppColors.amber700),
        _esicApplicable(e) ? _cDeduction(esic) : _cBadge('N/A', AppColors.slate300),
        pt == 0 ? _cBadge('—', AppColors.slate300) : _cDeduction(pt),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFFFF1F1),
          child: Center(
            child: Text(td == 0 ? '—' : '₹$td',
                style: AppTextStyles.bodySemi.copyWith(color: Colors.red.shade700, fontSize: 12)),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          color: const Color(0xFFF0FDF4),
          child: Center(
            child: Text(net <= 0 ? '—' : '₹${net.toStringAsFixed(0)}',
                style: AppTextStyles.bodySemi.copyWith(color: AppColors.emerald700, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  // ── Totals bar (exact layout as specified) ───────────────────────────────────
  Widget _totalsBar(double availableWidth, List<EmployeeModel> employees) {
    final totalBasic = employees.fold(0.0, (s, e) => s + e.basicCharges);
    final totalOther = employees.fold(0.0, (s, e) => s + e.otherCharges);
    final totalGrossFull = totalBasic + totalOther;
    final totalPf = employees.fold(0, (s, e) => s + _pf(e));
    final totalEsic = employees.fold(0, (s, e) => s + _esic(e));
    final totalMsw = widget.isMsw ? employees.length * 6 : 0;
    final totalPt = employees.fold(0, (s, e) => s + _pt(e));
    final totalTd = employees.fold(0, (s, e) => s + _td(e));
    final totalNet = employees.fold(0.0, (s, e) => s + _net(e));

    return SizedBox(
      width: availableWidth,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          16, widget.totalsBarTopPadding, 16, widget.totalsBarBottomPadding,
        ),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top row
            Row(
              children: [
                // Left: Total Gross
                _chip('Total Gross', '₹${totalGrossFull.toStringAsFixed(0)}', AppColors.indigo400),
                const Spacer(),
                // Centered group: Basic | Other
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chip('Total Basic', '₹${totalBasic.toStringAsFixed(0)}', AppColors.indigo400),
                    _separator(),
                    _chip('Total Other', '₹${totalOther.toStringAsFixed(0)}', AppColors.indigo400),
                  ],
                ),
                const Spacer(),
                // Right: Net Payable
                _chip('Net Payable', '₹${totalNet.toStringAsFixed(0)}', const Color.fromARGB(255, 12, 186, 47)),
              ],
            ),
            const SizedBox(height: 8),
            // Bottom row
            Row(
              children: [
                // Left: Total Deductions
                _chip('Total Deductions', '₹$totalTd', Colors.redAccent),
                const Spacer(),
                // Centered group: PF | ESIC | PT
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _chip('Total PF', '₹$totalPf', Colors.redAccent),
                    _separator(),
                    _chip('Total ESIC', '₹$totalEsic', Colors.redAccent),
                    _separator(),
                    _chip('Total PT', '₹$totalPt', Colors.redAccent),
                  ],
                ),
                const Spacer(),
                // Right: MSW (if applicable)
                if (widget.isMsw)
                  _chip('Total MSW', '₹$totalMsw', AppColors.amber700)
                else
                  const SizedBox(width: 100),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final employees = _sortedEmployees;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        return Column(
          children: [
            _totalsBar(availableWidth, employees),
            SizedBox(height: widget.totalsBarGap),
            Expanded(
              child: Container(
                width: availableWidth,
                decoration: BoxDecoration(
                  color: AppColors.white,
                  border: Border.all(
                      color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  child: Scrollbar(
                    controller: _hScrollController,
                    thumbVisibility: true,
                    notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                    child: SingleChildScrollView(
                      controller: _hScrollController,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: availableWidth,
                          maxWidth: double.infinity,
                        ),
                        child: Scrollbar(
                          controller: _vScrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _vScrollController,
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
      },
    );
  }

  // ── Static helpers ────────────────────────────────────────────────────────────
  static Widget _separator() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text('|', style: AppTextStyles.body.copyWith(color: AppColors.slate500)),
  );

  static Widget _chip(String label, String value, Color color, {TextStyle? labelStyle, TextStyle? valueStyle}) {
    final lStyle = labelStyle ??
        AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 16);
    final vStyle = valueStyle ??
        AppTextStyles.bodyMedium.copyWith(color: color, fontSize: 16);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: lStyle),
        Text(value, style: vStyle),
      ],
    );
  }

  static Widget _cTxt(String t) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(child: Text(t, textAlign: TextAlign.center, style: AppTextStyles.body)),
  );

  static Widget _cNum(double v, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(
      child: Text(v == 0 ? '—' : '₹${v.toStringAsFixed(0)}',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: color ?? AppColors.slate700, fontSize: 12)),
    ),
  );

  static Widget _cDeduction(int v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    child: Center(
      child: Text(v == 0 ? '—' : '₹$v',
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(
              color: color ?? Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.w500)),
    ),
  );

  static Widget _cBadge(String label, Color color) => Center(
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w600)),
    ),
  );
}

// ── Days input field with focus‑out validation ─────────────────────────────────
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
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          final val = int.tryParse(controller.text) ?? 0;
          if (val > max) {
            controller.clear();
            onChanged('');
          }
        }
      },
      child: SizedBox(
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
            _MaxValueFormatter(),
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
          onSubmitted: (_) => onSubmitted?.call(),
        ),
      ),
    );
  }
}

class _MaxValueFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > 2) return oldValue;
    return newValue;
  }
}
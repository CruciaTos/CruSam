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
    this.totalsBarGap            = 8,
    this.totalsBarHPadding       = 0,
    this.totalsBarTopPadding     = 10,
    this.totalsBarBottomPadding  = 10,
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
    final g        = _earnedGross(e);
    final isFemale = e.gender.toUpperCase() == 'F';
    if (isFemale) {
      if (g < 25000) return 0;
      return widget.isFeb ? 300 : 200;
    } else {
      if (g < 7500)       return 0;
      if (g < 10000)      return 175;
      return widget.isFeb ? 300 : 200;
    }
  }

  int    _td(EmployeeModel e) => _pf(e) + _esic(e) + _msw() + _pt(e);
  double _net(EmployeeModel e) => _earnedGross(e) - _td(e);

  void _focusNextEmployee(EmployeeModel current) {
    final sorted = _sortedEmployees;
    final idx = sorted.indexOf(current);
    if (idx >= 0 && idx < sorted.length - 1) {
      final nextId = sorted[idx + 1].id;
      if (nextId != null) widget.daysFocusNodes[nextId]?.requestFocus();
    }
  }

  // ── Column widths ─────────────────────────────────────────────────────────────
  Map<int, TableColumnWidth> _colWidths() {
    final cols = <double>[
      48.0, 240.0, 55.0, 100.0, 100.0, 110.0, 80.0, 110.0, 80.0,
      if (widget.isMsw) 72.0,
      100.0, 80.0, 95.0, 110.0,
    ];
    return {for (int i = 0; i < cols.length; i++) i: FixedColumnWidth(cols[i])};
  }

  double get _totalTableWidth => _colWidths().values
      .map((w) => (w as FixedColumnWidth).value)
      .fold(0.0, (a, b) => a + b);

  // ── Headers ───────────────────────────────────────────────────────────────────
  List<Widget> _headers() {
    final labels = [
      'Sr.', 'Name', 'Gender',
      'Basic', 'Other', 'Gross',
      'Days\nPresent', 'Earned\nGross',
      'Provident\n Fund(12%)',
      if (widget.isMsw) 'MSW\n(₹6)',
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

  // ── Data row ──────────────────────────────────────────────────────────────────
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
        _cTxt((idx + 1).toString()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Text(e.name, style: AppTextStyles.bodyMedium, overflow: TextOverflow.ellipsis),
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
              focusNode:  widget.daysFocusNodes[e.id],
              max:        widget.totalDays,
              onChanged:  (_) => widget.onDaysChanged(),
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

  // ── Totals bar ────────────────────────────────────────────────────────────────
  Widget _totalsBar(double availableWidth, List<EmployeeModel> employees) {
    final totalBasic     = employees.fold(0.0, (s, e) => s + e.basicCharges);
    final totalOther     = employees.fold(0.0, (s, e) => s + e.otherCharges);
    final totalGrossFull = totalBasic + totalOther;
    final totalPf        = employees.fold(0,   (s, e) => s + _pf(e));
    final totalEsic      = employees.fold(0,   (s, e) => s + _esic(e));
    final totalMsw       = widget.isMsw ? employees.length * 6 : 0;
    final totalPt        = employees.fold(0,   (s, e) => s + _pt(e));
    final totalTd        = employees.fold(0,   (s, e) => s + _td(e));
    final totalNet       = employees.fold(0.0, (s, e) => s + _net(e));

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
            // Top row: Gross/Basic/Other  |  Net Payable
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 0,
                    runSpacing: 4,
                    children: [
                      _chip('Total Gross', '₹${totalGrossFull.toStringAsFixed(0)}',
                          AppColors.indigo400,
                          labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate500, fontSize: 16),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.indigo400, fontSize: 16)),
                      _separator(),
                      _chip('Total Basic', '₹${totalBasic.toStringAsFixed(0)}',
                          AppColors.indigo400,
                          labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.indigo400, fontSize: 10)),
                      _separator(),
                      _chip('Total Other', '₹${totalOther.toStringAsFixed(0)}',
                          AppColors.indigo400,
                          labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.indigo400, fontSize: 10)),
                    ],
                  ),
                ),
                _chip('Net Payable', '₹${totalNet.toStringAsFixed(0)}',
                    AppColors.emerald700,
                    labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate500, fontSize: 16),
                    valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.emerald700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            // Bottom row: Deductions
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 0,
                    runSpacing: 4,
                    children: [
                      _chip('Total Deductions ', '₹$totalTd', Colors.redAccent,
                          labelStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate500, fontSize: 16),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.redAccent, fontSize: 16)),
                      _separator(),
                      _chip('Total PF', '₹$totalPf', AppColors.slate400,
                          labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate400, fontSize: 10)),
                      _separator(),
                      if (widget.isMsw) ...[
                        _chip('Total MSW', '₹$totalMsw', AppColors.amber700,
                            labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                            valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.amber700, fontSize: 10)),
                        _separator(),
                      ],
                      _chip('Total ESIC', '₹$totalEsic', AppColors.slate400,
                          labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate400, fontSize: 10)),
                      _separator(),
                      _chip('Total PT', '₹$totalPt', AppColors.slate400,
                          labelStyle: AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: 10),
                          valueStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.slate400, fontSize: 10)),
                    ],
                  ),
                ),
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
    final employees = _sortedEmployees; // Use sorted list
    final totalWidth = _totalTableWidth;

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
                      child: SizedBox(
                        width: totalWidth,
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

  static Widget _chip(String label, String value, Color color,
      {TextStyle? labelStyle, TextStyle? valueStyle, double fontSize = 14}) {
    final lStyle = labelStyle ??
        AppTextStyles.body.copyWith(color: AppColors.slate500, fontSize: fontSize);
    final vStyle = valueStyle ??
        AppTextStyles.bodyMedium.copyWith(color: color, fontSize: fontSize);
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

// ── Days input field ───────────────────────────────────────────────────────────
class _DaysField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode?            focusNode;
  final int                   max;
  final ValueChanged<String>  onChanged;
  final VoidCallback?         onSubmitted;

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
    height: 32, width: 70,
    child: TextField(
      controller:       controller,
      focusNode:        focusNode,
      textAlign:        TextAlign.center,
      textAlignVertical: TextAlignVertical.center,
      keyboardType:     TextInputType.number,
      textInputAction:  TextInputAction.next,
      inputFormatters:  [FilteringTextInputFormatter.digitsOnly, _MaxValueFormatter()],
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
          controller.clear();
          onChanged('');
        }
        onSubmitted?.call();
      },
    ),
  );
}

class _MaxValueFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.length > 2) return oldValue;
    return newValue;
  }
}
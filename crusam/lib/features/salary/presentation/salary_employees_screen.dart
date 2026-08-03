// crusam/lib/features/salary/presentation/salary_employees_screen.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/employee_model.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import 'package:crusam/features/salary/notifier/salary_snapshot_notifier.dart';
import '../widgets/salary_entry_table.dart';
import '../widgets/shared_salary_widget.dart';

// ── Shared control sizing so the button / dropdown / MSW panel match exactly ──
const double _kControlHeight = 46.0;
const double _kControlRadius = 12.0;
final List<BoxShadow> _kControlShadow = [
  BoxShadow(
    color: Colors.black.withOpacity(0.18),
    blurRadius: 10,
    offset: const Offset(0, 3),
  ),
];

class SalaryEmployeesScreen extends StatefulWidget {
  const SalaryEmployeesScreen({super.key});
  @override
  State<SalaryEmployeesScreen> createState() => _SalaryEmployeesScreenState();
}

class _SalaryEmployeesScreenState extends State<SalaryEmployeesScreen> {
  final _ctrl = SalaryStateController.instance;
  final _snapshotNotifier = SalarySnapshotNotifier.instance;

  final Map<int, FocusNode> _daysFocusNodes = {};

  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_syncFocusNodes);
    _ctrl.loadEmployees();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_syncFocusNodes);
    for (final f in _daysFocusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes() {
    if (!mounted) return;
    final liveIds =
        _ctrl.employees.where((e) => e.id != null).map((e) => e.id!).toSet();

    final staleIds =
        _daysFocusNodes.keys.where((id) => !liveIds.contains(id)).toList();
    for (final id in staleIds) {
      _daysFocusNodes.remove(id)?.dispose();
    }

    for (final id in liveIds) {
      _daysFocusNodes[id] ??= FocusNode();
    }

    setState(() {});
  }

  // ── Month change ─────────────────────────────────────────────────────────
  void _onMonthChange(int month) {
    final n = SalaryDataNotifier.instance;
    final year = n.year;
    final newTotal = DateTime(year, month + 1, 0).day;
    final liveIds =
        _ctrl.employees.where((e) => e.id != null).map((e) => e.id!).toSet();
    for (final id in liveIds) {
      final c = n.getOrCreateController(id);
      final v = int.tryParse(c.text) ?? 0;
      if (v > newTotal) c.text = newTotal.toString();
    }
    n.setMonthYear(month, year);
  }

  Future<void> _onSaveCurrentMonth() async {
    final n = SalaryDataNotifier.instance;
    final defaultName = _snapshotNotifier.defaultNameFor(n.month, n.year);
    final name = await _promptForName(
      title: 'Save Current Month',
      initialValue: defaultName,
      confirmLabel: 'Save',
    );
    if (name == null) return;
    final ok = await _snapshotNotifier.saveCurrentMonth(name: name);
    _showSnack(
      ok
          ? 'Saved Salary recorded for ${n.periodLabel}.'
          : 'Save failed: ${_snapshotNotifier.error}',
      isError: !ok,
    );
  }

  Future<String?> _promptForName({
    required String title,
    required String initialValue,
    required String confirmLabel,
  }) {
    final ctrl = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(title),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Saved Salary name',
              ),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                child: Text(confirmLabel),
              ),
            ],
          ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  List<EmployeeModel> get _displayEmployees => _ctrl.filteredEmployees;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      _ctrl,
      SalaryDataNotifier.instance,
      _snapshotNotifier,
    ]),
    builder: (context, _) {
      final n = SalaryDataNotifier.instance;
      final employees = _displayEmployees;
      final code = _ctrl.selectedCompanyCode;
      final title =
          code == 'All' ? 'Employee Salary' : 'Employee Salary - $code';

      final daysCtrls = {
        for (final e in employees)
          if (e.id != null) e.id!: n.getOrCreateController(e.id!),
      };

      final isViewingSavedSalary = _snapshotNotifier.isViewingSavedSalary;

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          children: [
            if (isViewingSavedSalary) ...[
              SavedSalaryIndicatorBanner(
                periodLabel: _snapshotNotifier.activeSavedSalaryLabel,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            _Toolbar(
              title: title,
              month: n.month,
              months: _months,
              isMsw: n.isMsw,
              isMswEligibleMonth: n.isMswEligibleMonth,
              applyMsw: n.applyMsw,
              mswAmount: n.mswAmount,
              isFeb: n.isFeb,
              codes: const ['F&B', 'I&L', 'P&S', 'A&P'],
              selectedCode: _ctrl.selectedCompanyCode,
              onMonthChanged: _onMonthChange,
              onCodeChanged: (c) => _ctrl.setCompanyCode(c),
              onSaveTap: _onSaveCurrentMonth,
              onApplyMswChanged: n.setApplyMsw,
              onMswAmountChanged: n.setMswAmount,
              isSaving: _snapshotNotifier.isSaving,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_ctrl.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (employees.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.people_outline,
                        size: 48,
                        color: AppColors.slate300,
                      ),
                      const SizedBox(height: 12),
                      Text('No employees found.', style: AppTextStyles.small),
                      const SizedBox(height: 8),
                      Text(
                        'Add employees in Employee Master Data first.',
                        style: AppTextStyles.small.copyWith(
                          color: AppColors.slate400,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: SalaryEntryTable(
                  employees: employees,
                  month: n.month,
                  year: n.year,
                  totalDays: n.totalDays,
                  isMsw: n.isMsw,
                  mswAmount: n.mswAmount,
                  isFeb: n.isFeb,
                  daysCtrls: daysCtrls,
                  daysFocusNodes: _daysFocusNodes,
                  onDaysChanged: () => setState(() {}),
                  monthName: n.monthName,
                ),
              ),
          ],
        ),
      );
    },
  );
}

// ─── Smooth Month Dropdown ────────────────────────────────────────────────────
class SmoothDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) display;
  final ValueChanged<T> onChanged;
  final double width;
  final int maxVisibleItems;
  final double height;

  const SmoothDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.display,
    required this.onChanged,
    required this.width,
    this.maxVisibleItems = 4,
    this.height = _kControlHeight,
  });

  @override
  Widget build(BuildContext context) {
    const double menuItemHeight = 46.0;
    final double maxHeight = maxVisibleItems * menuItemHeight;

    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      offset: Offset(0, height + 8),
      color: const Color(0xFF1E293B),
      elevation: 8,
      shadowColor: Colors.black.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_kControlRadius),
        side: BorderSide(color: AppColors.slate400.withOpacity(0.25)),
      ),
      constraints: BoxConstraints(minWidth: width, maxHeight: maxHeight),
      itemBuilder: (context) {
        return items.map((item) {
          final bool isSelected = item == value;
          return PopupMenuItem<T>(
            value: item,
            height: menuItemHeight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  display(item),
                  style: AppTextStyles.input.copyWith(
                    color: isSelected ? Colors.white : AppColors.slate300,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_rounded, size: 16, color: AppColors.indigo400),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        width: width,
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(_kControlRadius),
          border: Border.all(color: AppColors.slate400.withOpacity(0.35)),
          boxShadow: _kControlShadow,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                display(value),
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.input.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.expand_more_rounded,
              color: AppColors.indigo400,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Toolbar ──────────────────────────────────────────────────────────────────
class _Toolbar extends StatefulWidget {
  final String title;
  final int month;
  final List<String> months;
  final bool isMsw;
  final bool isMswEligibleMonth;
  final bool applyMsw;
  final double mswAmount;
  final bool isFeb;
  final List<String> codes;
  final String selectedCode;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onSaveTap;
  final ValueChanged<bool> onApplyMswChanged;
  final ValueChanged<double> onMswAmountChanged;
  final bool isSaving;

  const _Toolbar({
    required this.title,
    required this.month,
    required this.months,
    required this.isMsw,
    required this.isMswEligibleMonth,
    required this.applyMsw,
    required this.mswAmount,
    required this.isFeb,
    required this.codes,
    required this.selectedCode,
    required this.onMonthChanged,
    required this.onCodeChanged,
    required this.onSaveTap,
    required this.onApplyMswChanged,
    required this.onMswAmountChanged,
    this.isSaving = false,
  });

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final TextEditingController _mswAmountCtrl;

  @override
  void initState() {
    super.initState();
    _mswAmountCtrl = TextEditingController(
      text: widget.mswAmount.toStringAsFixed(0),
    );
  }

  @override
  void didUpdateWidget(covariant _Toolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mswAmount != widget.mswAmount &&
        _mswAmountCtrl.text != widget.mswAmount.toStringAsFixed(0)) {
      _mswAmountCtrl.text = widget.mswAmount.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _mswAmountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(widget.title, style: AppTextStyles.h3.copyWith(color: Colors.white)),
            const Spacer(),
            // ── Save Current Month button ────
            Container(
              height: _kControlHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kControlRadius),
                boxShadow: _kControlShadow,
              ),
              child: ElevatedButton.icon(
                onPressed: widget.isSaving ? null : widget.onSaveTap,
                icon: widget.isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined, size: 17),
                label: Text(
                  widget.isSaving ? 'Saving…' : 'Save Current Month',
                  style: AppTextStyles.input.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo600,
                  disabledBackgroundColor: AppColors.indigo600.withOpacity(0.55),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, _kControlHeight),
                  maximumSize: const Size(double.infinity, _kControlHeight),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_kControlRadius),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            SmoothDropdown<int>(
              value: widget.month,
              items: List.generate(12, (i) => i + 1),
              display: (m) => widget.months[m - 1],
              onChanged: widget.onMonthChanged,
              width: 150,
              maxVisibleItems: 4,
              height: _kControlHeight,
            ),
          ],
        ),
        if (widget.isMswEligibleMonth) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              // ── MSW panel with inline-editable amount ──
              Container(
                height: _kControlHeight,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(_kControlRadius),
                  border: Border.all(color: AppColors.slate400.withOpacity(0.35)),
                  boxShadow: _kControlShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: widget.applyMsw,
                        onChanged: (v) => widget.onApplyMswChanged(v ?? false),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -4,
                        ),
                        activeColor: AppColors.indigo600,
                        side: BorderSide(color: AppColors.slate400),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Apply MSW',
                      style: AppTextStyles.input.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      width: 1,
                      height: 20,
                      color: AppColors.slate400.withOpacity(0.3),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      '₹',
                      style: AppTextStyles.input.copyWith(
                        color: widget.applyMsw
                            ? AppColors.slate300
                            : AppColors.slate400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ── Input field with bigger height & moved up further ──
                    SizedBox(
                      width: 100,
                      height: 56, // Increased height to make the input box bigger
                      child: Transform.translate(
                        // 🔧 UPDATED POSITION: Moved up more (dy decreased from 8 to 4)
                        offset: const Offset(0, 4), 
                        child: TextField(
                          controller: _mswAmountCtrl,
                          enabled: widget.applyMsw,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: AppTextStyles.input.copyWith(
                            color: Colors.black,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          textAlignVertical: TextAlignVertical.center,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            isDense: true,
                            // Adjusted padding to center text nicely within the bigger box
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(_kControlRadius),
                              borderSide: const BorderSide(color: AppColors.indigo600, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(_kControlRadius),
                              borderSide: const BorderSide(color: AppColors.indigo600, width: 1.5),
                            ),
                            disabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(_kControlRadius),
                              borderSide: BorderSide(color: AppColors.slate400, width: 1.5),
                            ),
                          ),
                          onChanged: (v) {
                            final parsed = double.tryParse(v);
                            if (parsed != null) widget.onMswAmountChanged(parsed);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (widget.isFeb) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              _badge(
                'February — PT ₹300 for eligible',
                AppColors.indigo50,
                AppColors.indigo600,
              ),
            ],
          ),
        ],
        if (widget.codes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _chip('All', widget.selectedCode == 'All', () => widget.onCodeChanged('All')),
                ...widget.codes.map(
                  (c) => _chip(c, widget.selectedCode == c, () => widget.onCodeChanged(c)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static Widget _chip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.indigo600 : const Color(0xFF1E293B),
          border: Border.all(
            color: active ? AppColors.indigo600 : AppColors.slate400,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.slate400,
          ),
        ),
      ),
    ),
  );

  static Widget _badge(String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg),
    ),
  );
}
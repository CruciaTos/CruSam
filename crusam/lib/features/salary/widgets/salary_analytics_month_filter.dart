// lib/features/salary/widgets/salary_analytics_month_filter.dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/utils/financial_year_utils.dart';
import '../notifier/salary_analytics_notifier.dart';

class SalaryAnalyticsMonthFilter extends StatelessWidget {
  final SalaryAnalyticsNotifier notifier;

  const SalaryAnalyticsMonthFilter({super.key, required this.notifier});

  Future<void> _openCustomPicker(BuildContext context) async {
    final selected = await showDialog<List<MonthYear>>(
      context: context,
      builder: (ctx) => _CustomMonthPickerDialog(
        availableMonths: notifier.availableMonths,
        initiallySelected: notifier.selectedMonths.toSet(),
      ),
    );
    if (selected != null) await notifier.setCustomMonths(selected);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip(
          label: 'This FY (${FinancialYearUtils.thisFinancialYearLabel()})',
          active: notifier.preset == SalaryAnalyticsFilterPreset.thisFinancialYear,
          onTap: () => notifier.selectPreset(SalaryAnalyticsFilterPreset.thisFinancialYear),
        ),
        _chip(
          label: 'Last FY (${FinancialYearUtils.lastFinancialYearLabel()})',
          active: notifier.preset == SalaryAnalyticsFilterPreset.lastFinancialYear,
          onTap: () => notifier.selectPreset(SalaryAnalyticsFilterPreset.lastFinancialYear),
        ),
        _chip(
          label: 'This Calendar Year',
          active: notifier.preset == SalaryAnalyticsFilterPreset.thisCalendarYear,
          onTap: () => notifier.selectPreset(SalaryAnalyticsFilterPreset.thisCalendarYear),
        ),
        _chip(
          label: notifier.preset == SalaryAnalyticsFilterPreset.custom
              ? 'Custom (${notifier.selectedMonths.length} months)'
              : 'Custom…',
          active: notifier.preset == SalaryAnalyticsFilterPreset.custom,
          icon: Icons.tune,
          onTap: () => _openCustomPicker(context),
        ),
      ],
    );
  }

  Widget _chip({
    required String label,
    required bool active,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.indigo600 : AppColors.slate800,
          border: Border.all(color: active ? AppColors.indigo600 : AppColors.slate600),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: active ? Colors.white : AppColors.slate400),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.slate400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomMonthPickerDialog extends StatefulWidget {
  final List<MonthYear> availableMonths;
  final Set<MonthYear> initiallySelected;

  const _CustomMonthPickerDialog({
    required this.availableMonths,
    required this.initiallySelected,
  });

  @override
  State<_CustomMonthPickerDialog> createState() => _CustomMonthPickerDialogState();
}

class _CustomMonthPickerDialogState extends State<_CustomMonthPickerDialog> {
  late Set<MonthYear> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initiallySelected};
  }

  @override
  Widget build(BuildContext context) {
    final months = [...widget.availableMonths]
      ..sort((a, b) => b.sortKey.compareTo(a.sortKey));

    return AlertDialog(
      title: const Text('Select Months'),
      content: SizedBox(
        width: 360,
        height: 420,
        child: months.isEmpty
            ? const Center(child: Text('No Saved Salaries available yet.'))
            : ListView.builder(
                itemCount: months.length,
                itemBuilder: (ctx, i) {
                  final m = months[i];
                  final checked = _selected.contains(m);
                  return CheckboxListTile(
                    value: checked,
                    title: Text(m.label),
                    dense: true,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(m);
                      } else {
                        _selected.remove(m);
                      }
                    }),
                  );
                },
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _selected.isEmpty ? null : () => Navigator.pop(context, _selected.toList()),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
// lib/features/salary/widgets/shared_salary_widgets.dart
//
// Shared UI primitives used across salary screens to avoid duplication.
// ─ SalaryMonthBadge    — month/year pill badge
// ─ SalaryCodeFilter    — dept-code chip row
// ─ SalaryMarginSection — PDF margin input block
// ─ SalaryFlagBadge     — coloured info badge (MSW / Feb PT notices)

import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/margin_settings_model.dart';
import 'package:crusam/features/vouchers/notifiers/margin_settings_notifier.dart';

// ── Month / Year badge ─────────────────────────────────────────────────────────

class SalaryMonthBadge extends StatelessWidget {
  final String monthName;
  final int    year;

  const SalaryMonthBadge({
    super.key,
    required this.monthName,
    required this.year,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.slate800,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 13,
            color: AppColors.slate400,
          ),
          const SizedBox(width: 5),
          Text(
            '$monthName $year',
            style: AppTextStyles.small.copyWith(
              color: AppColors.slate300,
              fontWeight: FontWeight.w500,
            ),
          ),
        ]),
      );
}

// ── Department code filter chips ───────────────────────────────────────────────

class SalaryCodeFilter extends StatelessWidget {
  final List<String>         codes;
  final String               selected; // 'All' or a dept code
  final void Function(String?) onChanged; // null → treat as 'All'

  const SalaryCodeFilter({
    super.key,
    required this.codes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _chip('All', null),
          ...codes.map((c) => _chip(c, c)),
        ]),
      );

  Widget _chip(String label, String? value) {
    final active = selected == (value ?? 'All');
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.indigo600 : AppColors.slate800,
            border: Border.all(
              color: active ? AppColors.indigo600 : AppColors.slate600,
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
  }
}

// ── PDF Margin adjustment section ──────────────────────────────────────────────

class SalaryMarginSection extends StatefulWidget {
  final MarginSettingsNotifier notifier;

  const SalaryMarginSection({super.key, required this.notifier});

  @override
  State<SalaryMarginSection> createState() => _SalaryMarginSectionState();
}

class _SalaryMarginSectionState extends State<SalaryMarginSection> {
  late final TextEditingController _top;
  late final TextEditingController _bottom;
  late final TextEditingController _left;
  late final TextEditingController _right;

  @override
  void initState() {
    super.initState();
    final s = widget.notifier.settings;
    _top    = TextEditingController(text: s.top.toStringAsFixed(0));
    _bottom = TextEditingController(text: s.bottom.toStringAsFixed(0));
    _left   = TextEditingController(text: s.left.toStringAsFixed(0));
    _right  = TextEditingController(text: s.right.toStringAsFixed(0));
    widget.notifier.addListener(_sync);
  }

  void _sync() {
    if (!mounted) return;
    final s = widget.notifier.settings;
    _top.text    = s.top.toStringAsFixed(0);
    _bottom.text = s.bottom.toStringAsFixed(0);
    _left.text   = s.left.toStringAsFixed(0);
    _right.text  = s.right.toStringAsFixed(0);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_sync);
    _top.dispose();
    _bottom.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _apply() => widget.notifier.update(MarginSettings(
        top:    double.tryParse(_top.text)    ?? 24,
        bottom: double.tryParse(_bottom.text) ?? 24,
        left:   double.tryParse(_left.text)   ?? 24,
        right:  double.tryParse(_right.text)  ?? 24,
      ));

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PDF Margins (px)',
            style: AppTextStyles.label.copyWith(color: AppColors.slate500),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _marginField('Top',    _top)),
            const SizedBox(width: 6),
            Expanded(child: _marginField('Bottom', _bottom)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _marginField('Left',  _left)),
            const SizedBox(width: 6),
            Expanded(child: _marginField('Right', _right)),
          ]),
        ],
      );

  Widget _marginField(String label, TextEditingController ctrl) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.small),
          const SizedBox(height: 3),
          SizedBox(
            height: 32,
            child: TextField(
              controller: ctrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.input,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'px',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              ),
              onChanged: (_) => _apply(),
            ),
          ),
        ],
      );
}

// ── Coloured info / flag badge ─────────────────────────────────────────────────

class SalaryFlagBadge extends StatelessWidget {
  final String label;
  final Color  bg;
  final Color  fg;

  const SalaryFlagBadge({
    super.key,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
}
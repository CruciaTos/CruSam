// lib/shared/widgets/output_format_picker.dart
//
// Chip row letting the user toggle which file format(s) an email should
// attach — PDF, Excel, or both. At least one format always stays selected;
// tapping the last active chip is a no-op, so every caller (Invoices,
// Salary Statement, Disbursement) gets that guarantee for free instead of
// validating an empty selection itself. See output-format-selector
// blueprint §3.1.
//
// Styled directly off the app's own design tokens (AppColors/AppSpacing/
// AppTextStyles) rather than a default Material FilterChip, to match the
// flat, minimal look used throughout the rest of the app's dialogs.

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../models/output_format.dart';

class OutputFormatPicker extends StatelessWidget {
  final Set<OutputFormat> selected;
  final ValueChanged<Set<OutputFormat>> onChanged;

  /// Which formats can be picked at all — e.g. `{OutputFormat.excel}` for
  /// Disbursement, where no PDF generator exists. Defaults to both.
  final Set<OutputFormat> available;

  const OutputFormatPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.available = const {OutputFormat.pdf, OutputFormat.excel},
  });

  void _toggle(OutputFormat format) {
    final isSelected = selected.contains(format);
    // Refuse to drop the last remaining format — callers never have to
    // handle an empty selection coming back out of this widget.
    if (isSelected && selected.length <= 1) return;

    final next = Set<OutputFormat>.from(selected);
    isSelected ? next.remove(format) : next.add(format);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (final format in available)
          _FormatChip(
            format: format,
            isSelected: selected.contains(format),
            onTap: () => _toggle(format),
          ),
      ],
    );
  }
}

class _FormatChip extends StatelessWidget {
  final OutputFormat format;
  final bool isSelected;
  final VoidCallback onTap;

  const _FormatChip({
    required this.format,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.indigo50 : AppColors.surface,
          border: Border.all(
            color: isSelected ? AppColors.indigo500 : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              format.icon,
              size: 16,
              color: isSelected ? AppColors.indigo600 : AppColors.slate500,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              format.label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isSelected ? AppColors.indigo700 : AppColors.slate600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
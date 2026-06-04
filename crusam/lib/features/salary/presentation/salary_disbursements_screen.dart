// lib/features/salary/presentation/salary_disbursements_screen.dart

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/full_screen_loader.dart';
import '../models/salary_disbursement_model.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_disbursement_notifier.dart';
import '../widgets/shared_salary_widgets.dart';

class SalaryDisbursementsScreen extends StatefulWidget {
  const SalaryDisbursementsScreen({super.key});

  @override
  State<SalaryDisbursementsScreen> createState() =>
      _SalaryDisbursementsScreenState();
}

class _SalaryDisbursementsScreenState
    extends State<SalaryDisbursementsScreen> {
  final _notifier = SalaryDisbursementNotifier.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.load();
    });
  }

  // ── Generate + Export (one tap) ────────────────────────────────────────────

  Future<void> _onGenerate() async {
    if (_notifier.selectedCount == 0) {
      _showSnack('Select at least one employee first.');
      return;
    }

    showLoader(context, message: 'Generating & exporting salary disbursement…');
    try {
      final n    = SalaryDataNotifier.instance;
      final path = await _notifier.generateDisbursement(
        deptCode: n.monthName,
      );
      if (!mounted) return;
      if (path != null) {
        _showSnack('Saved: $path');
      } else {
        _showSnack('Failed to generate disbursement.', isError: true);
      }
    } finally {
      if (mounted) hideLoader(context);
    }
  }

  // ── Re-export from history ─────────────────────────────────────────────────

  Future<void> _onExportExcel(SalaryDisbursementModel disbursement) async {
    showLoader(context, message: 'Exporting Excel…');
    try {
      final path = await _notifier.exportDisbursementExcel(disbursement);
      if (!mounted) return;
      if (path != null) {
        _showSnack('Saved: $path');
      } else {
        _showSnack('Export failed.', isError: true);
      }
    } finally {
      if (mounted) hideLoader(context);
    }
  }

  Future<void> _onDelete(SalaryDisbursementModel disbursement) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Delete Disbursement'),
        content: const Text('Delete this batch? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _notifier.deleteDisbursement(disbursement.id!);
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red.shade700 : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_notifier, SalaryDataNotifier.instance]),
      builder: (ctx, _) {
        final n        = SalaryDataNotifier.instance;
        final notifier = _notifier;

        return Padding(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Toolbar ──────────────────────────────────────────────
              _Toolbar(
                monthName:     n.monthName,
                year:          n.year,
                selectedCount: notifier.selectedCount,
                totalSelected: notifier.selectedTotal,
                isGenerating:  notifier.isGenerating,
                isLoading:     notifier.isLoading,
                onGenerate:    _onGenerate,
                onRefresh:     () => notifier.load(forceReload: true),
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Error ─────────────────────────────────────────────────
              if (notifier.error.isNotEmpty)
                Container(
                  margin:   const EdgeInsets.only(bottom: AppSpacing.md),
                  padding:  const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.red.shade50,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border:       Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(notifier.error,
                      style: TextStyle(color: Colors.red.shade800)),
                ),

              // ── Body ─────────────────────────────────────────────────
              Expanded(
                child: notifier.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left: candidates table
                          Expanded(
                            flex: 3,
                            child: _CandidatesPanel(
                              notifier:   notifier,
                              onGenerate: _onGenerate,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          // Right: history
                          Expanded(
                            flex: 2,
                            child: _HistoryPanel(
                              history:  notifier.history,
                              onExport: _onExportExcel,
                              onDelete: _onDelete,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _Toolbar
// ══════════════════════════════════════════════════════════════════════════════

class _Toolbar extends StatelessWidget {
  final String monthName;
  final int    year;
  final int    selectedCount;
  final double totalSelected;
  final bool   isGenerating;
  final bool   isLoading;
  final VoidCallback onGenerate;
  final VoidCallback onRefresh;

  const _Toolbar({
    required this.monthName,
    required this.year,
    required this.selectedCount,
    required this.totalSelected,
    required this.isGenerating,
    required this.isLoading,
    required this.onGenerate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Salary Disbursement', style: AppTextStyles.h3),
        const SizedBox(width: AppSpacing.md),
        SalaryMonthBadge(monthName: monthName, year: year),
        const Spacer(),
        if (selectedCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.indigo600.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.indigo600.withValues(alpha: 0.3)),
            ),
            child: Text(
              '$selectedCount selected  ·  ₹${totalSelected.toStringAsFixed(0)}',
              style: AppTextStyles.small.copyWith(
                color:      AppColors.indigo400,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        IconButton(
          icon:    const Icon(Icons.refresh, size: 18, color: AppColors.slate400),
          tooltip: 'Refresh',
          onPressed: isLoading ? null : onRefresh,
        ),
        const SizedBox(width: 4),
        isGenerating
            ? const SizedBox(
                width:  24,
                height: 24,
                child:  CircularProgressIndicator(strokeWidth: 2))
            : ElevatedButton.icon(
                onPressed: selectedCount > 0 ? onGenerate : null,
                icon:  const Icon(Icons.account_balance_outlined, size: 16),
                label: const Text('Generate & Export'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.indigo600,
                  foregroundColor: Colors.white,
                ),
              ),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _CandidatesPanel — the main selection table
// ══════════════════════════════════════════════════════════════════════════════

class _CandidatesPanel extends StatelessWidget {
  final SalaryDisbursementNotifier notifier;
  final VoidCallback                onGenerate;

  const _CandidatesPanel({
    required this.notifier,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = notifier.candidates;

    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        border:       Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Table header ────────────────────────────────────────────
          _TableHeader(
            allSelected: notifier.allSelected,
            onSelectAll: notifier.allSelected
                ? notifier.deselectAll
                : notifier.selectAll,
          ),
          // ── Rows ────────────────────────────────────────────────────
          if (candidates.isEmpty)
            const _EmptyState()
          else
            Expanded(
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: candidates.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.slate100),
                itemBuilder: (ctx, i) {
                  final item = candidates[i];
                  return _CandidateRow(
                    item:       item,
                    isSelected: notifier.isEmployeeSelected(item.employeeId),
                    onToggle:   () => notifier.toggleEmployee(item.employeeId),
                  );
                },
              ),
            ),
          // ── Totals bar ───────────────────────────────────────────────
          if (candidates.isNotEmpty)
            _TotalsBar(
              totalAll:      candidates.fold(0.0, (s, c) => s + c.amount),
              totalSelected: notifier.selectedTotal,
              selectedCount: notifier.selectedCount,
              totalCount:    candidates.length,
            ),
        ],
      ),
    );
  }
}

// ── Table header row ──────────────────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final bool         allSelected;
  final VoidCallback onSelectAll;

  const _TableHeader({
    required this.allSelected,
    required this.onSelectAll,
  });

  static const _labels = [
    '',               // checkbox column
    'Beneficiary Name',
    'Bank Name',
    'Account Number',
    'IFSC',
    'Amount (₹)',
    'Status',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radius - 1)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Checkbox(
              value:       allSelected,
              onChanged:   (_) => onSelectAll(),
              activeColor: AppColors.indigo500,
              side:        const BorderSide(color: AppColors.slate500),
            ),
          ),
          ..._labels.skip(1).map((lbl) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 12),
                  child: Text(lbl,
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.slate400)),
                ),
              )),
        ],
      ),
    );
  }
}

// ── Single candidate row (always interactive) ────────────────────────────────

class _CandidateRow extends StatelessWidget {
  final SalaryDisbursementItemModel item;
  final bool         isSelected;
  final VoidCallback onToggle;

  const _CandidateRow({
    required this.item,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: isSelected
            ? AppColors.indigo600.withValues(alpha: 0.06)
            : Colors.transparent,
        child: Row(
          children: [
            SizedBox(
              width: 48,
              child: Checkbox(
                value:       isSelected,
                onChanged:   (_) => onToggle(),
                activeColor: AppColors.indigo500,
              ),
            ),
            Expanded(child: _cell(item.employeeName,  bold: true)),
            Expanded(child: _cell(item.bankName.isEmpty ? '—' : item.bankName)),
            Expanded(child: _cell(item.accountNumber, mono: true)),
            Expanded(child: _cell(item.ifscCode,      mono: true)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                child: Text(
                  '₹${item.amount.toStringAsFixed(2)}',
                  style: AppTextStyles.bodySemi.copyWith(
                    color:      AppColors.emerald700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 12),
                child: _StatusBadge(status: item.status),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _cell(String text,
      {bool bold = false, bool mono = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          text,
          style: AppTextStyles.body.copyWith(
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            fontFamily: mono ? 'monospace' : null,
            fontSize:   13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

// ── Totals bar ────────────────────────────────────────────────────────────────

class _TotalsBar extends StatelessWidget {
  final double totalAll;
  final double totalSelected;
  final int    selectedCount;
  final int    totalCount;

  const _TotalsBar({
    required this.totalAll,
    required this.totalSelected,
    required this.selectedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:  AppColors.slate900,
        border: const Border(top: BorderSide(color: AppColors.slate700)),
        borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(AppSpacing.radius - 1)),
      ),
      child: Row(
        children: [
          _chip('Total Employees', '$totalCount', AppColors.slate400),
          const SizedBox(width: 24),
          _chip('Total Payable',
              '₹${totalAll.toStringAsFixed(0)}', AppColors.indigo400),
          const Spacer(),
          if (selectedCount > 0) ...[
            _chip('Selected', '$selectedCount', AppColors.amber100),
            const SizedBox(width: 16),
            _chip('Selected Amount',
                '₹${totalSelected.toStringAsFixed(0)}', AppColors.emerald700),
          ],
        ],
      ),
    );
  }

  static Widget _chip(String label, String value, Color color) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ',
              style: AppTextStyles.small
                  .copyWith(color: AppColors.slate500, fontSize: 13)),
          Text(value,
              style: AppTextStyles.small.copyWith(
                  color:      color,
                  fontWeight: FontWeight.w700,
                  fontSize:   13)),
        ],
      );
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 48, color: AppColors.slate300),
              const SizedBox(height: 12),
              Text('No eligible employees',
                  style: AppTextStyles.h4
                      .copyWith(color: AppColors.slate400)),
              const SizedBox(height: 6),
              Text(
                'Enter days worked in the Employees tab first,\n'
                'then come back here.',
                style:     AppTextStyles.small,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// _HistoryPanel — right panel showing past disbursement batches
// ══════════════════════════════════════════════════════════════════════════════

class _HistoryPanel extends StatelessWidget {
  final List<SalaryDisbursementModel>          history;
  final void Function(SalaryDisbursementModel) onExport;
  final void Function(SalaryDisbursementModel) onDelete;

  const _HistoryPanel({
    required this.history,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        Colors.white,
        border:       Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color:        AppColors.slate900,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radius - 1)),
            ),
            child: Text('Disbursement History',
                style: AppTextStyles.bodyMedium
                    .copyWith(fontWeight: FontWeight.w600)),
          ),
          history.isEmpty
              ? const Expanded(
                  child: Center(
                    child: Text('No disbursements yet.',
                        style: TextStyle(color: AppColors.slate400)),
                  ),
                )
              : Expanded(
                  child: ListView.separated(
                    padding:          EdgeInsets.zero,
                    itemCount:        history.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.slate100),
                    itemBuilder: (ctx, i) => _HistoryCard(
                      disbursement: history[i],
                      onExport:     () => onExport(history[i]),
                      onDelete:     () => onDelete(history[i]),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final SalaryDisbursementModel disbursement;
  final VoidCallback             onExport;
  final VoidCallback             onDelete;

  const _HistoryCard({
    required this.disbursement,
    required this.onExport,
    required this.onDelete,
  });

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  Widget build(BuildContext context) {
    final month = _monthNames[(disbursement.month - 1).clamp(0, 11)];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$month ${disbursement.year}',
                  style: AppTextStyles.bodySemi.copyWith(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              _StatusBadge(status: disbursement.status),
            ],
          ),
          const SizedBox(height: 4),
          if (disbursement.exportedAt != null)
            Text(
              'Exported ${disbursement.exportedAt!.split('T').first}',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionBtn(
                icon:  Icons.table_chart_outlined,
                label: 'Export Excel',
                color: Colors.green.shade700,
                onTap: onExport,
              ),
              const Spacer(),
              _ActionBtn(
                icon:  Icons.delete_outline,
                label: 'Delete',
                color: Colors.red,
                onTap: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final Color        color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize:   12,
                    color:      color,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

// ── Status badge shared by candidates and history ─────────────────────────────

class _StatusBadge extends StatelessWidget {
  final SalaryDisbursementStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      SalaryDisbursementStatus.pending   => (AppColors.amber100,   AppColors.amber700),
      SalaryDisbursementStatus.generated => (AppColors.indigo50,   AppColors.indigo600),
      SalaryDisbursementStatus.exported  => (AppColors.emerald100, AppColors.emerald700),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.label.toUpperCase(),
        style: TextStyle(
          fontSize:   10,
          fontWeight: FontWeight.w700,
          color:      fg,
        ),
      ),
    );
  }
}
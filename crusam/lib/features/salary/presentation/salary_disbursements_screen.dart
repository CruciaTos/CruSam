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

  // ── Generate + Export ──────────────────────────────────────────────────────

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.load();
    });
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
              // ── Toolbar ────────────────────────────────────────────────
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

              // ── Error ───────────────────────────────────────────────────
              if (notifier.error.isNotEmpty)
                Container(
                  margin:  const EdgeInsets.only(bottom: AppSpacing.md),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.red.shade50,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                    border:       Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(notifier.error,
                      style: TextStyle(color: Colors.red.shade800)),
                ),

              // ── Body ────────────────────────────────────────────────────
              Expanded(
                child: notifier.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── Left pane: history + selection controls ──────
                          SizedBox(
                            width: 288,
                            child: Container(
                              color: Colors.grey[200],
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: _LeftPane(
                                notifier:  notifier,
                                onGenerate: _onGenerate,
                                onExport:  _onExportExcel,
                                onDelete:  _onDelete,
                              ),
                            ),
                          ),

                          // ── Divider ──────────────────────────────────────
                          Container(
                            width: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            color: AppColors.slate200,
                          ),

                          // ── Right pane: disbursement preview table ────────
                          Expanded(
                            child: _PreviewPane(notifier: notifier),
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
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
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
// _LeftPane  — selection controls + history
// ══════════════════════════════════════════════════════════════════════════════

class _LeftPane extends StatelessWidget {
  final SalaryDisbursementNotifier notifier;
  final VoidCallback onGenerate;
  final void Function(SalaryDisbursementModel) onExport;
  final void Function(SalaryDisbursementModel) onDelete;

  const _LeftPane({
    required this.notifier,
    required this.onGenerate,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = notifier.candidates;
    final allSelected = notifier.allSelected;

    return ListView(
      children: [
        // ── Section: Selection Summary ─────────────────────────────────────
        Text('Selection', style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.md),

        // Select all / deselect all row
        Row(
          children: [
            Checkbox(
              value: allSelected,
              tristate: !allSelected && notifier.selectedCount > 0,
              onChanged: (_) =>
                  allSelected ? notifier.deselectAll() : notifier.selectAll(),
              activeColor: AppColors.indigo500,
              side: const BorderSide(color: AppColors.slate500),
            ),
            Expanded(
              child: Text(
                allSelected
                    ? 'All selected'
                    : notifier.selectedCount == 0
                        ? 'None selected'
                        : '${notifier.selectedCount} of ${candidates.length} selected',
                style: AppTextStyles.small.copyWith(color: AppColors.slate300),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),

        // Employee chips list (scrollable within the pane)
        if (candidates.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No eligible employees.\nEnter days in the Employees tab first.',
              style: AppTextStyles.small.copyWith(color: AppColors.slate400),
              textAlign: TextAlign.center,
            ),
          )
        else
          ...candidates.map((item) {
            final isSelected = notifier.isEmployeeSelected(item.employeeId);
            return _EmployeeChip(
              item:       item,
              isSelected: isSelected,
              onToggle:   () => notifier.toggleEmployee(item.employeeId),
            );
          }),

        const SizedBox(height: AppSpacing.md),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),

        // ── Totals summary ─────────────────────────────────────────────────
        Text('Summary',
            style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
        const SizedBox(height: AppSpacing.sm),
        _summaryRow(
          'Total Employees',
          '${candidates.length}',
          AppColors.indigo400,
        ),
        _summaryRow(
          'Total Payable',
          '₹${candidates.fold(0.0, (s, c) => s + c.amount).toStringAsFixed(0)}',
          AppColors.indigo400,
        ),
        if (notifier.selectedCount > 0) ...[
          const SizedBox(height: 4),
          _summaryRow(
            'Selected',
            '${notifier.selectedCount}',
            AppColors.amber700,
          ),
          _summaryRow(
            'Selected Amount',
            '₹${notifier.selectedTotal.toStringAsFixed(0)}',
            AppColors.emerald700,
            bold: true,
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
        const Divider(),
        const SizedBox(height: AppSpacing.sm),

        // ── Disbursement History ───────────────────────────────────────────
        Text('Disbursement History', style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.md),

        if (notifier.history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No disbursements yet.',
              style: AppTextStyles.small.copyWith(color: AppColors.slate400),
            ),
          )
        else
          ...notifier.history.map((d) => _HistoryCard(
                disbursement: d,
                onExport:     () => onExport(d),
                onDelete:     () => onDelete(d),
              )),
      ],
    );
  }

  static Widget _summaryRow(String label, String value, Color color,
      {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.small),
            Text(value,
                style: AppTextStyles.small.copyWith(
                  color:      color,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  fontSize:   bold ? 13 : 12,
                )),
          ],
        ),
      );
}

// ── Employee selection chip ────────────────────────────────────────────────────

class _EmployeeChip extends StatelessWidget {
  final SalaryDisbursementItemModel item;
  final bool         isSelected;
  final VoidCallback onToggle;

  const _EmployeeChip({
    required this.item,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        margin:  const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.indigo600.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppColors.indigo600.withValues(alpha: 0.35)
                : AppColors.slate700,
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value:     isSelected,
              onChanged: (_) => onToggle(),
              activeColor: AppColors.indigo500,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.employeeName,
                    style: AppTextStyles.small.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: isSelected
                          ? AppColors.indigo400
                          : AppColors.slate300,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    item.bankName.isEmpty ? '—' : item.bankName,
                    style: AppTextStyles.small.copyWith(
                      fontSize: 10,
                      color: AppColors.slate500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              '₹${item.amount.toStringAsFixed(0)}',
              style: AppTextStyles.small.copyWith(
                color:      AppColors.emerald700,
                fontWeight: FontWeight.w700,
                fontSize:   12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── History card ──────────────────────────────────────────────────────────────

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

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border:       Border.all(color: AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '$month ${disbursement.year}',
                style: AppTextStyles.small.copyWith(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
            _StatusBadge(status: disbursement.status),
          ]),
          if (disbursement.exportedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              'Exported ${disbursement.exportedAt!.split('T').first}',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
          ],
          const SizedBox(height: 6),
          Row(children: [
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
          ]),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _PreviewPane  — live preview table matching Excel column layout exactly
// ══════════════════════════════════════════════════════════════════════════════

class _PreviewPane extends StatelessWidget {
  final SalaryDisbursementNotifier notifier;

  const _PreviewPane({required this.notifier});

  // Excel column widths (from SalaryDisbursementService) mapped to flex values
  // Amount(22) | Debit A/C(20) | IFSC(14) | Credit A/C(20) | Code(10) |
  // Beneficiary(22) | Branch(29) | Bank Details(25)
  static const _colFlex = [22, 20, 14, 20, 10, 22, 29, 25];

  static const _headers = [
    'Amount',
    'Debit A/C No.',
    'IFSC',
    'Credit A/c No.',
    'Code',
    'Beneficiary',
    'Branch',
    'Bank Details',
  ];

  static const _scrollbarTheme = ScrollbarThemeData(
    thickness: WidgetStatePropertyAll(6),
    radius: Radius.circular(4),
    thumbColor: WidgetStatePropertyAll(AppColors.indigo500),
    trackColor: WidgetStatePropertyAll(Color(0x26536DFE)),
    trackBorderColor: WidgetStatePropertyAll(Colors.transparent),
  );

  @override
  Widget build(BuildContext context) {
    final candidates = notifier.candidates;
    final config     = notifier.config;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Hint bar ──────────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.slate800,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Row(children: [
            const Icon(Icons.table_chart_outlined,
                size: 13, color: AppColors.slate400),
            const SizedBox(width: 6),
            Text(
              'Preview matches Excel export layout exactly  ·  Selected rows highlighted',
              style: AppTextStyles.small.copyWith(color: AppColors.slate400),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.sm),

        // ── Table ─────────────────────────────────────────────────────────
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0D1424),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              border: Border.all(color: AppColors.slate700, width: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              child: Column(
                children: [
                  // Header row
                  _PreviewHeader(colFlex: _colFlex, headers: _headers),

                  // Data rows
                  if (candidates.isEmpty)
                    const Expanded(
                      child: Center(
                        child: _EmptyPreview(),
                      ),
                    )
                  else
                    Expanded(
                      child: ScrollbarTheme(
                        data: _scrollbarTheme,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: candidates.length + 1, // +1 for total row
                            separatorBuilder: (_, __) => const Divider(
                                height: 1, color: AppColors.slate800),
                            itemBuilder: (ctx, i) {
                              if (i == candidates.length) {
                                // Total row
                                return _TotalRow(
                                  colFlex:   _colFlex,
                                  total:     candidates.fold(
                                      0.0, (s, c) => s + c.amount),
                                  selectedTotal: notifier.selectedTotal,
                                  selectedCount: notifier.selectedCount,
                                  totalCount: candidates.length,
                                );
                              }
                              final item       = candidates[i];
                              final isSelected = notifier.isEmployeeSelected(
                                  item.employeeId);
                              return _PreviewRow(
                                item:         item,
                                colFlex:      _colFlex,
                                isSelected:   isSelected,
                                debitAccount: config.accountNo,
                                rowIndex:     i,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Preview header ─────────────────────────────────────────────────────────────

class _PreviewHeader extends StatelessWidget {
  final List<int>    colFlex;
  final List<String> headers;

  const _PreviewHeader({required this.colFlex, required this.headers});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.slate900,
        border: Border(bottom: BorderSide(color: AppColors.slate700)),
      ),
      child: Row(
        children: List.generate(headers.length, (i) {
          final isFirst = i == 0;
          final isAmount = i == 0;
          return Expanded(
            flex: colFlex[i],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: i > 0
                  ? const BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: AppColors.slate800, width: 0.5)))
                  : null,
              alignment:
                  isAmount ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                headers[i],
                style: AppTextStyles.label.copyWith(
                  color:    AppColors.slate400,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Preview data row ───────────────────────────────────────────────────────────

class _PreviewRow extends StatelessWidget {
  final SalaryDisbursementItemModel item;
  final List<int>  colFlex;
  final bool       isSelected;
  final String     debitAccount;
  final int        rowIndex;

  const _PreviewRow({
    required this.item,
    required this.colFlex,
    required this.isSelected,
    required this.debitAccount,
    required this.rowIndex,
  });

  // Matches Excel column order exactly:
  // Amount | Debit A/C | IFSC | Credit A/C | Code | Beneficiary | Branch | Bank Details
  List<String> get _cells => [
    '₹${item.amount.toStringAsFixed(2)}',  // Amount
    debitAccount,                           // Debit A/C (config.accountNo)
    item.ifscCode,                          // IFSC
    item.accountNumber,                     // Credit A/C
    '10',                                   // Code (always 10)
    item.employeeName,                      // Beneficiary
    item.branch,                            // Branch
    item.bankName.isEmpty ? '—' : item.bankName, // Bank Details
  ];

  @override
  Widget build(BuildContext context) {
    final cells  = _cells;
    final rowBg  = isSelected
        ? AppColors.indigo600.withValues(alpha: 0.10)
        : rowIndex.isEven
            ? const Color(0xFF0D1424)
            : const Color(0xFF111827);

    return Container(
      color: rowBg,
      child: Row(
        children: List.generate(cells.length, (i) {
          final isAmount = i == 0;
          final isMono   = i == 1 || i == 2 || i == 3; // account/ifsc
          final isBene   = i == 5;

          return Expanded(
            flex: colFlex[i],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: i > 0
                  ? BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: AppColors.slate800, width: 0.5)))
                  : null,
              alignment:
                  isAmount ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                cells[i],
                style: AppTextStyles.body.copyWith(
                  fontSize:   isAmount ? 12 : 11,
                  fontWeight: isAmount || isBene
                      ? FontWeight.w600
                      : FontWeight.w400,
                  color: isAmount
                      ? AppColors.emerald700
                      : isBene
                          ? (isSelected
                              ? AppColors.indigo400
                              : AppColors.slate200)
                          : AppColors.slate400,
                  fontFamily: isMono ? 'monospace' : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Total row ─────────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final List<int> colFlex;
  final double    total;
  final double    selectedTotal;
  final int       selectedCount;
  final int       totalCount;

  const _TotalRow({
    required this.colFlex,
    required this.total,
    required this.selectedTotal,
    required this.selectedCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    // 8 columns — put total in col 0, "TOTAL" label in col 5 (Beneficiary)
    // put selected amount in col 0 context below
    final cells = List<String>.filled(8, '');
    cells[0] = '₹${total.toStringAsFixed(2)}';
    cells[5] = 'TOTAL ($totalCount employees)';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.slate900,
        border: Border(top: BorderSide(color: AppColors.slate700)),
      ),
      child: Row(
        children: List.generate(8, (i) {
          final isAmount = i == 0;
          final isBene   = i == 5;
          return Expanded(
            flex: colFlex[i],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              decoration: i > 0
                  ? const BoxDecoration(
                      border: Border(
                          left: BorderSide(
                              color: AppColors.slate700, width: 0.5)))
                  : null,
              alignment:
                  isAmount ? Alignment.centerRight : Alignment.centerLeft,
              child: cells[i].isEmpty
                  ? null
                  : Text(
                      cells[i],
                      style: AppTextStyles.small.copyWith(
                        fontSize:   isAmount ? 12 : 11,
                        fontWeight: FontWeight.w700,
                        color: isAmount
                            ? AppColors.indigo400
                            : AppColors.slate500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Empty preview ─────────────────────────────────────────────────────────────

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              size: 48, color: AppColors.slate600),
          const SizedBox(height: 12),
          Text('No eligible employees',
              style:
                  AppTextStyles.h4.copyWith(color: AppColors.slate500)),
          const SizedBox(height: 6),
          Text(
            'Enter days worked in the Employees tab first,\nthen come back here.',
            style:     AppTextStyles.small.copyWith(color: AppColors.slate600),
            textAlign: TextAlign.center,
          ),
        ],
      );
}

// ── Shared widgets ────────────────────────────────────────────────────────────

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
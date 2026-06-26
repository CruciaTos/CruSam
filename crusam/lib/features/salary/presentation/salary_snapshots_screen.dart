// crusam/lib/features/salary/presentation/salary_snapshots_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_snapshot_notifier.dart';
import '../widgets/send_salary_document_dialog.dart';

class SalarySnapshotsScreen extends StatefulWidget {
  const SalarySnapshotsScreen({super.key});

  @override
  State<SalarySnapshotsScreen> createState() => _SalarySnapshotsScreenState();
}

class _SalarySnapshotsScreenState extends State<SalarySnapshotsScreen> {
  final _notifier = SalarySnapshotNotifier.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.loadSnapshotList();
    });
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

  Future<void> _onLoad(SavedSalarySummary summary) async {
    final snapshot = summary.snapshot;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Load Saved Salary'),
            content: Text(
              'Switching to "${summary.periodLabel}" will make it your active '
              'salary period — the Employee Salary screen and all calculations '
              'will reflect this data. Continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.indigo600,
                ),
                child: const Text('Load'),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await _notifier.loadMonth(snapshot.id!);
    if (!mounted) return;
    if (ok) {
      context.go('/salary-employees');
    } else {
      _showSnack('Load failed: ${_notifier.error}', isError: true);
    }
  }

  // ── Send ──────────────────────────────────────────────────────────────
  // SendSalaryDocumentDialog reads the live SalaryDataNotifier/
  // SalaryStateController singletons (same as the dedicated Salary Bills/
  // Slips screens do for their own exports), so this period needs to be
  // the active one before the dialog opens. If it already is, skip
  // straight to the dialog; otherwise confirm the switch first — same
  // pattern as "Load", since it's the same underlying side effect.
  Future<void> _onSend(SavedSalarySummary summary) async {
    final snapshot = summary.snapshot;
    final alreadyActive = _notifier.activeSnapshot?.id == snapshot.id;

    if (!alreadyActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              title: const Text('Load Before Sending'),
              content: Text(
                'To email documents for "${summary.periodLabel}", it needs '
                'to become your active salary period first — the Employee '
                'Salary screen and all calculations will reflect this data. '
                'Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.indigo600,
                  ),
                  child: const Text('Load & Continue'),
                ),
              ],
            ),
      );
      if (confirmed != true || !mounted) return;

      final ok = await _notifier.loadMonth(snapshot.id!);
      if (!mounted) return;
      if (!ok) {
        _showSnack('Load failed: ${_notifier.error}', isError: true);
        return;
      }
    }

    if (!mounted) return;
    await SendSalaryDocumentDialog.show(context, summary: summary);
  }

  Future<void> _onRename(SavedSalarySummary summary) async {
    final snapshot = summary.snapshot;
    final name = await _promptForName(
      title: 'Rename Saved Salary',
      initialValue: snapshot.snapshotName,
      confirmLabel: 'Rename',
    );
    if (name == null) return;
    await _notifier.renameSnapshot(snapshot.id!, name);
  }

  Future<void> _onDelete(SavedSalarySummary summary) async {
    final snapshot = summary.snapshot;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Saved Salary'),
            content: Text(
              'Delete the saved salary for "${summary.periodLabel}"? '
              'This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    await _notifier.deleteSnapshot(snapshot.id!);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          final summaries = _notifier.summaries;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('All Saved Periods', style: AppTextStyles.h3),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.refresh,
                        size: 18,
                        color: AppColors.slate400,
                      ),
                      tooltip: 'Refresh',
                      onPressed:
                          _notifier.isLoading
                              ? null
                              : () => _notifier.loadSnapshotList(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                if (_notifier.error.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _notifier.error,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),
                Expanded(
                  child:
                      _notifier.isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : summaries.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                            itemCount: summaries.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 8),
                            itemBuilder:
                                (ctx, i) => _SavedSalaryCard(
                                  summary: summaries[i],
                                  isActive:
                                      _notifier.activeSnapshot?.id ==
                                      summaries[i].snapshot.id,
                                  onLoad: () => _onLoad(summaries[i]),
                                  onRename: () => _onRename(summaries[i]),
                                  onDelete: () => _onDelete(summaries[i]),
                                ),
                          ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SavedSalaryCard extends StatelessWidget {
  final SavedSalarySummary summary;
  final bool isActive;
  final VoidCallback onLoad;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SavedSalaryCard({
    required this.summary,
    required this.isActive,
    required this.onLoad,
    required this.onRename,
    required this.onDelete,
  });

  static final _savedAtFormat = DateFormat('MMM d, yyyy · h:mm a');
  static final _payrollFormat = NumberFormat('#,##0');

  @override
  Widget build(BuildContext context) {
    final snapshot = summary.snapshot;
    final periodLabel = summary.periodLabel;
    final hasCustomName =
        snapshot.snapshotName.trim().isNotEmpty &&
        snapshot.snapshotName.trim() != periodLabel;
    final savedAt = DateTime.tryParse(snapshot.updatedAt);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(
          color: isActive ? AppColors.indigo400 : AppColors.slate200,
          width: isActive ? 1.4 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.indigo50,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: AppColors.indigo600,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(
                      periodLabel,
                      style: AppTextStyles.bodySemi.copyWith(fontSize: 14),
                    ),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.indigo600,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    if (hasCustomName)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.slate100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          snapshot.snapshotName,
                          style: AppTextStyles.small.copyWith(
                            color: AppColors.slate600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  savedAt != null
                      ? 'Saved ${_savedAtFormat.format(savedAt)}'
                      : 'Save time unknown',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.slate500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${summary.employeeCount} employee'
                  '${summary.employeeCount == 1 ? '' : 's'}  ·  '
                  '₹${_payrollFormat.format(summary.totalPayroll)} total payroll',
                  style: AppTextStyles.small.copyWith(
                    color: AppColors.slate600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.file_open_outlined,
              size: 18,
              color: AppColors.indigo600,
            ),
            tooltip: 'Load Saved Salary',
            onPressed: onLoad,
          ),
          IconButton(
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: AppColors.slate500,
            ),
            tooltip: 'Rename',
            onPressed: onRename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            tooltip: 'Delete',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.calendar_month_outlined,
          size: 48,
          color: AppColors.slate300,
        ),
        const SizedBox(height: 12),
        Text('No saved salary periods yet.', style: AppTextStyles.small),
      ],
    ),
  );
}
// crusam/lib/features/salary/presentation/salary_snapshots_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/salary_snapshot_model.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_snapshot_notifier.dart';

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

  Future<void> _onSaveCurrentMonth() async {
    final n = SalaryDataNotifier.instance;
    final defaultName = _notifier.defaultNameFor(n.month, n.year);
    final name = await _promptForName(
      title: 'Save Current Month',
      initialValue: defaultName,
      confirmLabel: 'Save',
    );
    if (name == null) return;
    final ok = await _notifier.saveCurrentMonth(name: name);
    _showSnack(
      ok ? 'Snapshot saved.' : 'Save failed: ${_notifier.error}',
      isError: !ok,
    );
  }

  Future<void> _onLoad(SalaryMonthSnapshotModel snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Load Month'),
            content: Text(
              'Loading "${snapshot.snapshotName}" will replace the current '
              'salary screen state. Continue?',
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

  Future<void> _onRename(SalaryMonthSnapshotModel snapshot) async {
    final name = await _promptForName(
      title: 'Rename Snapshot',
      initialValue: snapshot.snapshotName,
      confirmLabel: 'Rename',
    );
    if (name == null) return;
    await _notifier.renameSnapshot(snapshot.id!, name);
  }

  Future<void> _onDelete(SalaryMonthSnapshotModel snapshot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete Snapshot'),
            content: Text(
              'Delete "${snapshot.snapshotName}"? This cannot be undone.',
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
                labelText: 'Snapshot name',
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
      appBar: AppBar(
        title: const Text('Salary Snapshots'),
        backgroundColor: AppColors.slate900,
        foregroundColor: Colors.white,
      ),
      body: ListenableBuilder(
        listenable: _notifier,
        builder: (context, _) {
          final snapshots = _notifier.snapshots;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Saved Months', style: AppTextStyles.h3),
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
                    const SizedBox(width: 4),
                    _notifier.isSaving
                        ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : ElevatedButton.icon(
                          onPressed: _onSaveCurrentMonth,
                          icon: const Icon(Icons.save_outlined, size: 16),
                          label: const Text('Save Current Month'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.indigo600,
                            foregroundColor: Colors.white,
                          ),
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
                          : snapshots.isEmpty
                          ? _EmptyState(onSave: _onSaveCurrentMonth)
                          : ListView.separated(
                            itemCount: snapshots.length,
                            separatorBuilder:
                                (_, __) => const SizedBox(height: 8),
                            itemBuilder:
                                (ctx, i) => _SnapshotCard(
                                  snapshot: snapshots[i],
                                  onLoad: () => _onLoad(snapshots[i]),
                                  onRename: () => _onRename(snapshots[i]),
                                  onDelete: () => _onDelete(snapshots[i]),
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

class _SnapshotCard extends StatelessWidget {
  final SalaryMonthSnapshotModel snapshot;
  final VoidCallback onLoad;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SnapshotCard({
    required this.snapshot,
    required this.onLoad,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      border: Border.all(color: AppColors.slate200),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
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
              Text(
                snapshot.snapshotName,
                style: AppTextStyles.bodySemi.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                '${snapshot.monthName} ${snapshot.year}  ·  Updated '
                '${snapshot.updatedAt.split('T').first}',
                style: AppTextStyles.small.copyWith(color: AppColors.slate500),
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
          tooltip: 'Load Month',
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onSave;
  const _EmptyState({required this.onSave});

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
        Text('No saved months yet.', style: AppTextStyles.small),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save_outlined, size: 16),
          label: const Text('Save Current Month'),
        ),
      ],
    ),
  );
}

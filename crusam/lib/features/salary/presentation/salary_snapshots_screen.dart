// crusam/lib/features/salary/presentation/salary_snapshots_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../notifier/salary_snapshot_notifier.dart';
import '../widgets/send_salary_dialog.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens — same as the redesigned Invoices & Settings screens
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsBadge = TextStyle(
    fontFamily   : fxcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 11,
    letterSpacing: 2.0,
    color        : badgeFg,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );

  static const double radius   = 6.0;
  static const double cRadius  = 10.0;
  static const double padH     = 18.0;
  static const double padV     = 16.0;
}

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
      builder: (ctx) => AlertDialog(
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

  void _onSend(SavedSalarySummary summary) {
    SendSalaryDialog.show(context, summary: summary);
  }

  Future<void> _onDelete(SavedSalarySummary summary) async {
    final snapshot = summary.snapshot;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
      builder: (ctx) => AlertDialog(
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
    return ListenableBuilder(
      listenable: _notifier,
      builder: (context, _) {
        final summaries = _notifier.summaries;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header bar ──────────────────────────────────────────
                _SalariesHeader(
                  isLoading: _notifier.isLoading,
                  onRefresh: () => _notifier.loadSnapshotList(),
                ),

                const SizedBox(height: 16),

                if (_notifier.error.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(_Tok.radius),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _notifier.error,
                      style: TextStyle(color: Colors.red.shade800),
                    ),
                  ),

                Expanded(
                  child: _notifier.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : summaries.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                              itemCount: summaries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (ctx, i) => _SavedSalaryCard(
                                summary: summaries[i],
                                isActive:
                                    _notifier.activeSnapshot?.id ==
                                    summaries[i].snapshot.id,
                                onLoad: () => _onLoad(summaries[i]),
                                onSend: () => _onSend(summaries[i]),
                                onRename: () => _onRename(summaries[i]),
                                onDelete: () => _onDelete(summaries[i]),
                              ),
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Header bar (matching Invoices / Settings) ────────────────────────────────
class _SalariesHeader extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onRefresh;

  const _SalariesHeader({required this.isLoading, required this.onRefresh});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: _Tok.padH),
        decoration: BoxDecoration(
          color: _Tok.surfaceAlt,
          border: const Border(bottom: BorderSide(color: _Tok.divider)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(_Tok.cRadius),
            topRight: Radius.circular(_Tok.cRadius),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _Tok.ink,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.calendar_month_outlined,
                color: Colors.white,
                size: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text('SAVED SALARIES', style: _Tok.tsCardTitle),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: _Tok.inkLight),
              tooltip: 'Refresh',
              onPressed: isLoading ? null : onRefresh,
            ),
          ],
        ),
      );
}

// ── Salary card (re‑themed with indigo palette and Noto fonts) ───────────────
class _SavedSalaryCard extends StatelessWidget {
  final SavedSalarySummary summary;
  final bool isActive;
  final VoidCallback onLoad;
  final VoidCallback onSend;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _SavedSalaryCard({
    required this.summary,
    required this.isActive,
    required this.onLoad,
    required this.onSend,
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
      margin: EdgeInsets.zero, // spacing handled by ListView separator
      decoration: BoxDecoration(
        color: _Tok.surface,           // solid white card
        border: Border.all(
          color: isActive ? _Tok.inkLight : _Tok.border,
          width: isActive ? 1.4 : 1,
        ),
        borderRadius: BorderRadius.circular(_Tok.cRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(_Tok.padV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top row: icon, period info, badges ───────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _Tok.surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.calendar_month_outlined,
                    size: 18,
                    color: _Tok.inkLight,
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
                            style: _Tok.tsInput.copyWith(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _Tok.ink,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: _Tok.tsBadge.copyWith(
                                  fontSize: 9,
                                  letterSpacing: 1.5,
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
                                color: _Tok.border.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                snapshot.snapshotName,
                                style: _Tok.tsMeta.copyWith(
                                  color: _Tok.inkMuted,
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
                        style: _Tok.tsMeta,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${summary.employeeCount} employee'
                        '${summary.employeeCount == 1 ? '' : 's'}  ·  '
                        '₹${_payrollFormat.format(summary.totalPayroll)} total payroll',
                        style: _Tok.tsMeta.copyWith(
                          fontWeight: FontWeight.w600,
                          color: _Tok.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Action buttons ──────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: Icons.file_open_outlined,
                  label: 'Load',
                  color: _Tok.inkLight,
                  onPressed: onLoad,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.send_outlined,
                  label: 'Send',
                  color: _Tok.inkLight,
                  onPressed: onSend,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Rename',
                  color: _Tok.inkLight,
                  onPressed: onRename,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: Colors.red.shade700,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable action button (matches Invoices) ────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: _Tok.tsLabel.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Empty state ──────────────────────────────────────────────────────────────
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
              color: _Tok.inkMuted.withOpacity(0.4),
            ),
            const SizedBox(height: 12),
            Text(
              'No saved salary periods yet.',
              style: _Tok.tsMeta.copyWith(fontSize: 13),
            ),
          ],
        ),
      );
}
// crusam/lib/core/ai/services/batch_sync_manager.dart
//
// Manages a queue of employee changes derived from an uploaded file.
// Changes are presented one-by-one; each requires explicit user confirmation
// before the corresponding tool action is executed.

import 'dart:convert';

import 'package:crusam/core/ai/services/employee_verification_service.dart';
import 'package:crusam/core/ai/services/file_extraction_service.dart';

// ── Change types ──────────────────────────────────────────────────────────────

enum BatchChangeKind { add, update, delete }

class PendingBatchChange {
  PendingBatchChange({
    required this.kind,
    required this.actionJson,
    required this.displayTitle,
    required this.displayDetails,
    this.isProcessed = false,
    this.wasSkipped = false,
  });

  final BatchChangeKind kind;
  final String actionJson;       // JSON string ready for AiToolExecutor
  final String displayTitle;     // e.g. "Add Rajesh Kumar"
  final String displayDetails;   // bullet list of fields being changed
  bool isProcessed;
  bool wasSkipped;

  String get emoji {
    switch (kind) {
      case BatchChangeKind.add:    return '➕';
      case BatchChangeKind.update: return '✏️';
      case BatchChangeKind.delete: return '🗑️';
    }
  }
}

// ── Result ────────────────────────────────────────────────────────────────────

class BatchSyncProgress {
  const BatchSyncProgress({
    required this.total,
    required this.processed,
    required this.skipped,
    required this.current,
  });

  final int total;
  final int processed;
  final int skipped;
  final PendingBatchChange? current; // null means queue is exhausted

  bool get isDone => current == null;
  int get remaining => total - processed - skipped;

  String get summaryLine =>
      'Progress: $processed done, $skipped skipped, $remaining remaining of $total changes.';
}

// ── Manager ───────────────────────────────────────────────────────────────────

class BatchSyncManager {
  BatchSyncManager._();

  static final BatchSyncManager instance = BatchSyncManager._();

  List<PendingBatchChange> _queue = [];
  int _index = 0;
  String _sourceFileName = '';
  DateTime? _startedAt;

  // ── Queue access ────────────────────────────────────────────────────────────

  bool get hasActiveQueue => _queue.isNotEmpty && _index < _queue.length;
  int get queueLength => _queue.length;
  String get sourceFileName => _sourceFileName;
  DateTime? get startedAt => _startedAt;

  /// The change currently waiting for user confirmation.
  PendingBatchChange? get current =>
      _index < _queue.length ? _queue[_index] : null;

  BatchSyncProgress get progress => BatchSyncProgress(
        total: _queue.length,
        processed: _queue.where((c) => c.isProcessed).length,
        skipped: _queue.where((c) => c.wasSkipped).length,
        current: current,
      );

  // ── Build queue from verification result ────────────────────────────────────

  /// Populate the queue from a completed [EmployeeVerificationResult].
  /// Clears any existing queue first.
  void buildFromVerification(
    EmployeeVerificationResult result,
    String fileName,
  ) {
    _queue = [];
    _index = 0;
    _sourceFileName = fileName;
    _startedAt = DateTime.now();

    // Additions
    for (final record in result.additions) {
      _queue.add(PendingBatchChange(
        kind: BatchChangeKind.add,
        actionJson: jsonEncode({
          'action': 'add_employee',
          'name': record.name,
          'pfNo': record.pfNo,
          'uanNo': record.uanNo,
          'code': record.code,
        }),
        displayTitle: 'Add employee: ${record.name}',
        displayDetails: [
          if (record.pfNo.isNotEmpty) '- PF No: ${record.pfNo}',
          if (record.uanNo.isNotEmpty) '- UAN No: ${record.uanNo}',
          if (record.code.isNotEmpty) '- Code: ${record.code}',
        ].join('\n'),
      ));
    }

    // Updates
    for (final match in result.updates) {
      final emp = match.appEmployee;
      // Build action JSON with only changed fields
      final payload = <String, dynamic>{
        'action': 'update_employee',
        'employeeId': emp.id,
      };
      for (final change in match.fieldChanges) {
        payload[change.field] = change.fileValue;
      }

      final detailLines = match.fieldChanges.map((c) =>
          '- ${c.field}: "${c.appValue}" → "${c.fileValue}"').join('\n');

      _queue.add(PendingBatchChange(
        kind: BatchChangeKind.update,
        actionJson: jsonEncode(payload),
        displayTitle: 'Update employee: ${emp.name} (ID ${emp.id})',
        displayDetails: detailLines,
      ));
    }

    // Deletions (only add if file had reliable keys — avoid accidental deletes)
    for (final emp in result.deletions) {
      _queue.add(PendingBatchChange(
        kind: BatchChangeKind.delete,
        actionJson: jsonEncode({
          'action': 'delete_employee',
          'employeeId': emp.id,
          'name': emp.name,
        }),
        displayTitle: 'Delete employee: ${emp.name} (ID ${emp.id})',
        displayDetails: [
          if (emp.pfNo.isNotEmpty) '- PF No: ${emp.pfNo}',
          if (emp.uanNo.isNotEmpty) '- UAN No: ${emp.uanNo}',
        ].join('\n'),
      ));
    }
  }

  // ── Navigation ──────────────────────────────────────────────────────────────

  /// Mark current item as processed and advance the index.
  void markProcessed() {
    if (_index < _queue.length) {
      _queue[_index].isProcessed = true;
      _index++;
    }
  }

  /// Skip the current item without executing it.
  void skip() {
    if (_index < _queue.length) {
      _queue[_index].wasSkipped = true;
      _index++;
    }
  }

  /// Clear the queue (task complete or cancelled).
  void clear() {
    _queue = [];
    _index = 0;
    _sourceFileName = '';
    _startedAt = null;
  }

  // ── Chat message helpers ─────────────────────────────────────────────────────

  /// Human-readable card for the current pending change.
  /// Shown in the chat bubble so the user knows what they're confirming.
  String currentChangeCard() {
    final item = current;
    if (item == null) return 'All changes have been processed.';

    final prog = progress;
    final header = '${item.emoji} **${item.displayTitle}**';
    final details = item.displayDetails.isNotEmpty
        ? '\n${item.displayDetails}'
        : '';
    final footer =
        '\n\n_Change ${_index + 1} of ${prog.total}  ·  ${prog.remaining - 1} more after this._';

    return '$header$details$footer';
  }

  /// Summary shown after the entire queue is exhausted.
  String completionSummary() {
    final done = _queue.where((c) => c.isProcessed).length;
    final skipped = _queue.where((c) => c.wasSkipped).length;
    return '✅ Sync complete from **$_sourceFileName**\n'
        '- Applied: $done change${done == 1 ? '' : 's'}\n'
        '- Skipped: $skipped change${skipped == 1 ? '' : 's'}';
  }
}
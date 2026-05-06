// crusam/lib/core/ai/services/autonomous_sync_service.dart
//
// Runs ALL pending batch changes without per-step confirmation.
// Designed for long-running syncs — uses an isolate-friendly async loop
// so the UI stays responsive even for 500+ employee records.
//
// Usage:
//   final service = AutonomousSyncService.instance;
//   await service.runSync(
//     result: verificationResult,
//     fileName: 'salary_april.xlsx',
//     onProgress: (progress) { /* update UI */ },
//     onComplete: (summary) { /* show summary */ },
//   );

import 'dart:async';

import 'package:crusam/core/ai/services/employee_verification_service.dart';
import 'package:crusam/core/ai/services/batch_sync_manager.dart';
import 'package:crusam/core/ai/tools/ai_tool_executor.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';
import 'package:flutter/foundation.dart';

// ── Progress model ─────────────────────────────────────────────────────────

class SyncProgressEvent {
  const SyncProgressEvent({
    required this.current,
    required this.total,
    required this.currentName,
    required this.kind,
    required this.phase, // 'processing' | 'done' | 'error' | 'skipped'
    this.error,
  });

  final int current;
  final int total;
  final String currentName;
  final BatchChangeKind kind;
  final String phase;
  final String? error;

  double get percent => total == 0 ? 0 : current / total;

  String get statusLine {
    final kindLabel = switch (kind) {
      BatchChangeKind.add    => 'Adding',
      BatchChangeKind.update => 'Updating',
      BatchChangeKind.delete => 'Deleting',
    };
    return '$kindLabel $currentName ($current/$total)';
  }
}

// ── Summary model ──────────────────────────────────────────────────────────

class SyncSummary {
  const SyncSummary({
    required this.added,
    required this.updated,
    required this.deleted,
    required this.failed,
    required this.skipped,
    required this.duration,
    required this.fileName,
    this.errors = const [],
  });

  final int added;
  final int updated;
  final int deleted;
  final int failed;
  final int skipped;
  final Duration duration;
  final String fileName;
  final List<String> errors;

  int get total => added + updated + deleted + failed + skipped;

  String get chatMessage {
    final buf = StringBuffer();
    buf.writeln('✅ **Autonomous Sync Complete** — `$fileName`');
    buf.writeln('');
    buf.writeln('| Action | Count |');
    buf.writeln('|--------|-------|');
    buf.writeln('| ➕ Added | $added |');
    buf.writeln('| ✏️ Updated | $updated |');
    buf.writeln('| 🗑️ Deleted | $deleted |');
    if (skipped > 0) buf.writeln('| ⏭️ Skipped | $skipped |');
    if (failed > 0)  buf.writeln('| ❌ Failed | $failed |');
    buf.writeln('');
    buf.writeln('_Time taken: ${duration.inSeconds}s_');
    if (errors.isNotEmpty) {
      buf.writeln('');
      buf.writeln('**Errors:**');
      for (final e in errors.take(5)) {
        buf.writeln('- $e');
      }
      if (errors.length > 5) {
        buf.writeln('- …and ${errors.length - 5} more.');
      }
    }
    return buf.toString().trim();
  }
}

// ── Service ────────────────────────────────────────────────────────────────

class AutonomousSyncService {
  AutonomousSyncService._();
  static final AutonomousSyncService instance = AutonomousSyncService._();

  bool _running = false;
  bool _cancelRequested = false;

  bool get isRunning => _running;

  /// Request cancellation of the in-progress sync.
  void cancel() => _cancelRequested = true;

  // ── Main entry point ─────────────────────────────────────────────────────

  /// Runs ALL changes from [result] autonomously.
  ///
  /// [skipDeletes] — safety flag: if true, deletion changes are skipped
  ///                 (recommended for first run so you don't accidentally
  ///                  delete employees that were merely absent from the file).
  ///
  /// [onProgress]  — called for every change, useful for live progress UI.
  /// [onComplete]  — called when all changes are done (or sync is cancelled).
  Future<SyncSummary> runSync({
    required EmployeeVerificationResult result,
    required String fileName,
    bool skipDeletes = true,
    void Function(SyncProgressEvent)? onProgress,
    void Function(SyncSummary)? onComplete,
  }) async {
    if (_running) {
      throw StateError('A sync is already in progress.');
    }

    _running = true;
    _cancelRequested = false;

    // Build the same queue that BatchSyncManager uses, but we execute it here
    // instead of waiting for per-step confirmation.
    final manager = BatchSyncManager.instance;
    manager.buildFromVerification(result, fileName);

    int added = 0, updated = 0, deleted = 0, failed = 0, skipped = 0;
    final errors = <String>[];
    final startTime = DateTime.now();

    final total = manager.queueLength;
    int index = 0;

    while (manager.hasActiveQueue) {
      if (_cancelRequested) break;

      final change = manager.current!;
      index++;

      onProgress?.call(SyncProgressEvent(
        current: index,
        total: total,
        currentName: change.displayTitle,
        kind: change.kind,
        phase: 'processing',
      ));

      // Skip deletes if the safety flag is set
      if (change.kind == BatchChangeKind.delete && skipDeletes) {
        manager.skip();
        skipped++;
        continue;
      }

      try {
        final result = await AiToolExecutor.instance.executeBatch(
          [change.actionJson],
          employeeNotifier: EmployeeNotifier.instance,
          voucherNotifier: VoucherNotifier.instance,
        );

        if (result is AiToolSuccess) {
          manager.markProcessed();
          switch (change.kind) {
            case BatchChangeKind.add:    added++;   break;
            case BatchChangeKind.update: updated++; break;
            case BatchChangeKind.delete: deleted++; break;
          }
        } else if (result is AiToolFailure) {
          manager.skip();
          failed++;
          errors.add('${change.displayTitle}: ${(result as AiToolFailure).reason}');
        }
      } catch (e) {
        manager.skip();
        failed++;
        errors.add('${change.displayTitle}: $e');
        debugPrint('AutonomousSyncService: error on ${change.displayTitle}: $e');
      }

      // Yield to the event loop every 10 items so the UI doesn't freeze
      if (index % 10 == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    _running = false;
    _cancelRequested = false;

    final summary = SyncSummary(
      added: added,
      updated: updated,
      deleted: deleted,
      failed: failed,
      skipped: skipped,
      duration: DateTime.now().difference(startTime),
      fileName: fileName,
      errors: errors,
    );

    onComplete?.call(summary);
    return summary;
  }
}
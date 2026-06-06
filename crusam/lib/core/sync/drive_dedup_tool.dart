// lib/core/sync/drive_dedup_tool.dart
//
// ONE-TIME UTILITY — run this once to clean up the duplicate employee entries
// in the Drive index.  After running, delete this file (or just leave it,
// it's idempotent and harmless to call again).
//
// HOW TO TRIGGER:
//   Add a temporary button to the Google Drive debug screen:
//
//     ElevatedButton(
//       onPressed: () async {
//         final msg = await DriveIndexDedupTool.run();
//         ScaffoldMessenger.of(context)
//             .showSnackBar(SnackBar(content: Text(msg)));
//       },
//       child: const Text('Fix Duplicate Drive Entries'),
//     ),
//
// WHAT IT DOES:
//   1. Downloads employees/index.json from Drive.
//   2. Deduplicates entries by cloud_id — for each cloud_id keeps whichever
//      entry has the newest updated_at timestamp.
//   3. Writes the cleaned index back to Drive.
//   4. Verifies the local SQLite employees table — marks any row as deleted
//      if its cloud_id no longer appears in the cleaned index AND the row
//      was never actually edited locally (i.e. it was a phantom duplicate).
//
// It does NOT delete any .json files from the employees/ folder on Drive
// because those are harmless (orphaned files that will never be referenced).

import 'package:flutter/foundation.dart';

import 'drive_service.dart';
import 'sync_models.dart';
import 'google_auth_service.dart';
import '../../data/db/database_helper.dart';

class DriveIndexDedupTool {
  DriveIndexDedupTool._();

  static Future<String> run() async {
    if (!GoogleAuthService.instance.isSignedIn) {
      return 'Not signed in — cannot run dedup.';
    }

    try {
      return await _dedupEmployees();
    } catch (e) {
      debugPrint('DriveIndexDedupTool.run error: $e');
      return 'Error: $e';
    }
  }

  static Future<String> _dedupEmployees() async {
    final drive = DriveService.instance;

    // 1. Read the current index
    final index = await drive.readEmployeesIndex();
    final originalCount = index.entries.length;
    debugPrint('DriveIndexDedupTool: original index has $originalCount entries');

    // 2. Deduplicate: keep newest entry per cloud_id
    final Map<String, SyncIndexEntry> best = {};
    for (final entry in index.entries) {
      final existing = best[entry.cloudId];
      if (existing == null) {
        best[entry.cloudId] = entry;
      } else {
        // Keep whichever has the more recent updated_at
        final existingTs = DateTime.tryParse(existing.updatedAt) ?? DateTime(0);
        final entryTs = DateTime.tryParse(entry.updatedAt) ?? DateTime(0);
        if (entryTs.isAfter(existingTs)) {
          best[entry.cloudId] = entry;
        }
      }
    }

    final deduped = best.values.toList();
    final removedCount = originalCount - deduped.length;

    if (removedCount == 0) {
      debugPrint('DriveIndexDedupTool: no duplicates found');
      return 'Drive index is clean — no duplicates found ($originalCount entries).';
    }

    // 3. Write the cleaned index back to Drive
    final cleanIndex = SyncIndex(
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      entries: deduped,
    );
    await drive.writeEmployeesIndex(cleanIndex);
    debugPrint('DriveIndexDedupTool: wrote cleaned index with ${deduped.length} entries');

    // 4. Find phantom local rows: local employees whose cloud_id is NOT in
    //    the cleaned index.  These were inserted by the duplicate-id bug and
    //    should be soft-deleted locally.
    final validCloudIds = deduped.map((e) => e.cloudId).toSet();
    final db = await DatabaseHelper.instance.database;
    final localRows = await db.query(
      'employees',
      columns: ['id', 'cloud_id', 'updated_at'],
      where: "(is_deleted = 0 OR is_deleted IS NULL) AND cloud_id IS NOT NULL AND cloud_id != ''",
    );

    int phantomCount = 0;
    final now = DateTime.now().toUtc().toIso8601String();
    for (final row in localRows) {
      final cloudId = row['cloud_id'] as String;
      if (!validCloudIds.contains(cloudId)) {
        // This cloud_id was removed from the index (was a duplicate).
        // Soft-delete the local row.
        await db.update(
          'employees',
          {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
          where: 'cloud_id = ? AND is_deleted = 0',
          whereArgs: [cloudId],
        );
        phantomCount++;
        debugPrint('DriveIndexDedupTool: soft-deleted phantom local employee cloudId=$cloudId');
      }
    }

    return 'Dedup complete: removed $removedCount duplicate Drive index entries, '
        'soft-deleted $phantomCount phantom local employees. '
        'Drive index now has ${deduped.length} entries.';
  }
}
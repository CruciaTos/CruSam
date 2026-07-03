// lib/core/migration/data_migration_service.dart
//
// Phase 2 — one-time migration for existing installations.
//
// Supersedes the two ad hoc AppPaths.migrateLegacyFileIfNeeded() calls that
// used to live in main.dart with a single, marker-gated, logged migration
// pass. Must run at startup, before anything (DatabaseHelper,
// SemanticIndexRepository, ...) opens aarti.db.
//
// ── What "legacy" means here (Phase 0 audit) ──────────────────────────────
//
//   Pre-fix builds resolved aarti.db (and semantic_index.db, its sibling AI
//   index) via sqflite_common_ffi's default getDatabasesPath(), which falls
//   back to Directory.current — the install folder for a normally-launched
//   crusam.exe. That folder is wiped on every reinstall/update, which is
//   the root cause of the data-loss bug this migration exists to fix.
//   See AppPaths.dart for the full writeup and the Phase 1 fix (a stable,
//   per-user directory resolved via path_provider).
//
// ── What this does, once, per install ─────────────────────────────────────
//
//   1. If aarti.db already exists in the new canonical directory
//      (AppPaths.directory), do nothing — either already migrated, or a
//      fresh install that never had legacy data to begin with.
//   2. Otherwise, look for aarti.db (and semantic_index.db) in the legacy
//      directory. Anything found is COPIED — never moved — into the new
//      canonical directory. Copying means a failure mid-way leaves the
//      original untouched and safe to retry on the next launch.
//   3. Once the pass completes without error (whether or not there was
//      anything to copy), write migration_v1_complete.marker into the
//      canonical directory so this never scans the legacy directory again.
//   4. Legacy files are left exactly where they were. Deleting them is
//      deliberately out of scope for this release — see runIfNeeded's doc.
//   5. Every substantive attempt (found/not found, copied/failed, full
//      paths) is appended to migration.log in the canonical directory, so
//      a non-technical user can be asked to send a single file if their
//      data doesn't show up after an update.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../storage/app_paths.dart';

class DataMigrationService {
  DataMigrationService._();

  static const String _markerFileName = 'migration_v1_complete.marker';
  static const String _logFileName = 'migration.log';

  /// The file whose presence in the new canonical directory gates the
  /// entire migration (step 1). Checked and copied explicitly, separately
  /// from [_siblingFileNames], because it's the signal, not just one more
  /// item in a list.
  static const String _databaseFileName = 'aarti.db';

  /// Everything else identified in the Phase 0/Phase 1 audit that also
  /// needs to be carried forward alongside aarti.db. Add future
  /// locally-written data files here rather than hardcoding another call
  /// site — each one only gets copied if [_databaseFileName] itself needed
  /// migrating in the first place.
  static const List<String> _siblingFileNames = ['semantic_index.db'];

  /// Runs the one-time legacy-data migration if (and only if) it hasn't
  /// already run successfully on this install. Safe to call on every
  /// startup — after the first successful pass, every subsequent call
  /// returns immediately after a single file existence check.
  ///
  /// Must be called before any code opens aarti.db (see main.dart) —
  /// otherwise sqflite may create a fresh, empty database at the new
  /// canonical path before this ever gets a chance to copy the old one in,
  /// which would make step 1 below think migration is unnecessary.
  ///
  /// [legacyDir] defaults to Directory.current (the pre-fix location, i.e.
  /// the install folder for a normally-launched exe). Overridable for
  /// tests.
  static Future<void> runIfNeeded({Directory? legacyDir}) async {
    final legacy = legacyDir ?? Directory.current;
    final Directory newDir;
    try {
      newDir = await AppPaths.directory;
    } catch (e) {
      // Can't even resolve the canonical directory — nothing safe to do.
      // Legacy files are untouched either way, so this is non-fatal; the
      // app will retry on the next launch.
      debugPrint('DataMigrationService: could not resolve AppPaths.directory: $e');
      return;
    }

    final newDbFile = File(p.join(newDir.path, _databaseFileName));
    final markerFile = File(p.join(newDir.path, _markerFileName));

    // ── 1. Fast path: already migrated, or already a Phase-1-era fresh
    //      install. No I/O beyond these two existence checks, and
    //      deliberately no log write here — this runs on every single app
    //      launch forever, and shouldn't grow a log file on every open.
    if (await newDbFile.exists()) return;
    if (await markerFile.exists()) return;

    // From here on we're doing a real (first-ever) migration pass, so it's
    // worth logging.
    final log = <String>[];
    void logLine(String line) {
      log.add('[${DateTime.now().toIso8601String()}] $line');
      debugPrint('DataMigrationService: $line');
    }

    try {
      logLine('Starting one-time migration check.');
      logLine('Legacy dir    : ${legacy.path}');
      logLine('Canonical dir : ${newDir.path}');

      final legacyDbFile = File(p.join(legacy.path, _databaseFileName));
      final legacyDbExists = await legacyDbFile.exists();

      if (!legacyDbExists) {
        // Genuinely fresh install — no legacy data anywhere to carry
        // forward. Record that and mark done so we don't re-scan the
        // legacy directory on every future launch.
        logLine('$_databaseFileName not found at legacy location — nothing to migrate.');
        await _writeMarker(markerFile, logLine);
        return;
      }

      logLine('$_databaseFileName found at legacy location (${await legacyDbFile.length()} bytes).');

      var allSucceeded = true;

      allSucceeded &= await _copyOne(
        source: legacyDbFile,
        destination: newDbFile,
        logLine: logLine,
      );

      for (final name in _siblingFileNames) {
        final source = File(p.join(legacy.path, name));
        final destination = File(p.join(newDir.path, name));
        allSucceeded &= await _copyOne(
          source: source,
          destination: destination,
          logLine: logLine,
        );
      }

      if (allSucceeded) {
        logLine('Migration complete.');
        await _writeMarker(markerFile, logLine);
      } else {
        // Do NOT write the marker — leave this retryable on next launch.
        // The files that did copy successfully are skipped next time via
        // their own "destination already exists" check in _copyOne, so a
        // retry only redoes the part that actually failed.
        logLine('Migration incomplete — marker NOT written, will retry on next launch.');
      }
    } catch (e, st) {
      // Never let a migration failure block app startup. Worst case here
      // is the user is no worse off than before this feature existed, and
      // the legacy files are still sitting there, untouched, for a retry.
      logLine('Migration failed with an unexpected error: $e');
      debugPrint('DataMigrationService: $st');
    } finally {
      await _appendLog(newDir, log);
    }
  }

  /// Copies [source] to [destination] if [destination] doesn't already
  /// exist and [source] does. Returns false only on an actual copy
  /// failure — a missing source or an already-present destination are both
  /// "nothing to do" and count as success so they don't block the marker
  /// write.
  static Future<bool> _copyOne({
    required File source,
    required File destination,
    required void Function(String) logLine,
  }) async {
    final name = p.basename(destination.path);
    try {
      if (await destination.exists()) {
        logLine('$name: already present in canonical dir, skipped.');
        return true;
      }
      if (!await source.exists()) {
        logLine('$name: not found at legacy location, nothing to copy.');
        return true;
      }

      await source.copy(destination.path);
      final size = await destination.length();
      logLine('Copied $name: ${source.path} -> ${destination.path} ($size bytes).');
      return true;
    } catch (e) {
      logLine('FAILED copying $name (${source.path} -> ${destination.path}): $e');
      return false;
    }
  }

  static Future<void> _writeMarker(
    File markerFile,
    void Function(String) logLine,
  ) async {
    try {
      await markerFile.writeAsString(
        'Migration v1 completed at ${DateTime.now().toIso8601String()}\n',
      );
    } catch (e) {
      // Non-fatal: if aarti.db was actually copied, the step-1 fast path
      // will short-circuit future launches anyway even without the
      // marker. Only the "genuinely fresh install" case would end up
      // re-checking the legacy dir on every launch — harmless, just not
      // free.
      logLine('Could not write marker file (non-fatal): $e');
    }
  }

  static Future<void> _appendLog(Directory newDir, List<String> lines) async {
    if (lines.isEmpty) return;
    try {
      final logFile = File(p.join(newDir.path, _logFileName));
      final sink = logFile.openWrite(mode: FileMode.append);
      for (final line in lines) {
        sink.writeln(line);
      }
      await sink.flush();
      await sink.close();
    } catch (_) {
      // If we can't write the log, there's nothing more we can safely do
      // here — the migration outcome above already stands on its own.
    }
  }
}
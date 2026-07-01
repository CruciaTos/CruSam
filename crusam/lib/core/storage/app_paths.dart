// lib/core/storage/app_paths.dart
//
// Centralized resolver for where CruSam's own persistent local data lives
// on desktop (Windows/Linux/macOS), plus a diagnostic snapshot helper
// (AppStorageInfo) for the Profile screen's "Data Storage Location" card.
//
// ── The problem ──────────────────────────────────────────────────────────
//
//   sqflite_common_ffi's getDatabasesPath() has what its own maintainer
//   calls a "lame implementation" on desktop: unless overridden, it
//   defaults to Directory.current — which, for a normally-launched .exe,
//   IS the install folder. Any file written there is lost the moment the
//   app is replaced or updated in place.
//
// ── The fix ──────────────────────────────────────────────────────────────
//
//   Resolve a stable, per-user, OS-correct directory via path_provider's
//   getApplicationSupportDirectory() instead, cache it (so we only hit the
//   platform channel once), and expose helpers so call sites don’t reinvent
//   path‑joining and directory creation.
//
//   Typical resolved locations (subject to the app’s own bundle identity):
//     Windows: C:\Users\<user>\AppData\Roaming\…\CruSam
//     Linux:   ~/.local/share/crusam/CruSam
//     macOS:   ~/Library/Application Support/crusam/CruSam
//
// ── Diagnostic snapshot ──────────────────────────────────────────────────
//
//   AppPaths.resolveStorageInfo() returns an AppStorageInfo object that
//   contains the exact file paths for aarti.db and semantic_index.db, their
//   sizes, modification dates, and the executable’s location. This is used
//   by the DataLocationCard to show the full, copyable paths.
//
// ── Legacy migration ─────────────────────────────────────────────────────
//
//   Call migrateLegacyFileIfNeeded() once at startup to copy any existing
//   database files from the old install‑folder location into the new safe
//   directory. It never overwrites or deletes anything.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// ─── Stat info for a single file ──────────────────────────────────────────

class AppFileInfo {
  const AppFileInfo({
    required this.path,
    required this.exists,
    this.sizeBytes,
    this.lastModified,
  });

  final String path;
  final bool exists;
  final int? sizeBytes;
  final DateTime? lastModified;

  String get sizeLabel {
    final bytes = sizeBytes;
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}

// ─── Snapshot of every storage location CruSam currently touches ──────────

class AppStorageInfo {
  const AppStorageInfo({
    required this.databaseDirectory,
    required this.database,
    required this.semanticIndex,
    required this.executableDirectory,
  });

  /// The folder where CruSam’s databases live (now obtained from
  /// AppPaths.directory, i.e. the fixed per-user application support folder).
  final String databaseDirectory;

  final AppFileInfo database;
  final AppFileInfo semanticIndex;

  /// Folder crusam.exe is running from — never where user data belongs.
  final String executableDirectory;

  String toDiagnosticText() => '''
CruSam Storage Diagnostic
--------------------------------
Database folder : $databaseDirectory
Database file    : ${database.path}
                    (${database.exists ? "${database.sizeLabel}, updated ${database.lastModified}" : "not created yet"})
AI index file     : ${semanticIndex.path}
                    (${semanticIndex.exists ? "${semanticIndex.sizeLabel}, updated ${semanticIndex.lastModified}" : "not created yet"})
Program folder   : $executableDirectory
''';
}

// ─── Centralised path resolver ────────────────────────────────────────────

class AppPaths {
  AppPaths._();

  /// Fixed subfolder name under the platform's application-support directory.
  static const String _appFolderName = 'CruSam';

  static Directory? _cachedDir;
  static Future<Directory>? _resolving;

  /// The directory all persistent CruSam data should live under.
  ///
  /// Resolved once and cached — safe to call repeatedly from anywhere.
  static Future<Directory> get directory async {
    final cached = _cachedDir;
    if (cached != null) return cached;

    return _resolving ??= _resolve().then((dir) {
      _cachedDir = dir;
      _resolving = null;
      return dir;
    });
  }

  static Future<Directory> _resolve() async {
    Directory base;
    try {
      base = await getApplicationSupportDirectory();
    } catch (e) {
      debugPrint(
        'AppPaths: getApplicationSupportDirectory failed, '
        'falling back to documents directory: $e',
      );
      base = await getApplicationDocumentsDirectory();
    }

    final dir = Directory(p.join(base.path, _appFolderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Full absolute path to a named file/folder inside the app data
  /// directory, e.g. `await AppPaths.childPath('aarti.db')`.
  static Future<String> childPath(String name) async {
    final dir = await directory;
    return p.join(dir.path, name);
  }

  // ── One-time legacy-location migration ──────────────────────────────────

  /// Copies [fileName] from [legacyDir] into the new app-data directory if,
  /// and only if, it doesn't already exist at the new location.
  static Future<void> migrateLegacyFileIfNeeded({
    required Directory legacyDir,
    required String fileName,
  }) async {
    try {
      final newPath = await childPath(fileName);
      final newFile = File(newPath);
      if (await newFile.exists()) return;

      final oldFile = File(p.join(legacyDir.path, fileName));
      if (!await oldFile.exists()) return;

      await oldFile.copy(newPath);
      debugPrint(
        'AppPaths: migrated $fileName from ${legacyDir.path} to $newPath',
      );
    } catch (e) {
      debugPrint('AppPaths: migration of $fileName failed (non-fatal): $e');
    }
  }

  // ── Diagnostic snapshot (used by DataLocationCard) ─────────────────────

  /// Returns a live snapshot of CruSam’s storage locations, including the
  /// exact paths to aarti.db and semantic_index.db, their sizes, and the
  /// program folder. Safe to call repeatedly — does not create or move files.
  static Future<AppStorageInfo> resolveStorageInfo() async {
    final dbDir = (await directory).path;

    final dbPath = p.join(dbDir, 'aarti.db');
    final indexPath = p.join(dbDir, 'semantic_index.db');
    final executableDir = File(Platform.resolvedExecutable).parent.path;

    return AppStorageInfo(
      databaseDirectory: dbDir,
      database: _statFile(dbPath),
      semanticIndex: _statFile(indexPath),
      executableDirectory: executableDir,
    );
  }

  static AppFileInfo _statFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) {
        return AppFileInfo(path: path, exists: false);
      }
      final stat = file.statSync();
      return AppFileInfo(
        path: path,
        exists: true,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } catch (_) {
      return AppFileInfo(path: path, exists: false);
    }
  }
}
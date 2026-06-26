// updater/bin/main.dart
//
// External updater for Crusam on Windows.

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const _protectedSegments = <String>{
  'AppData',
  'appdata',
  'Documents',
  'documents',
  'Roaming',
  'roaming',
};

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    _log('Usage: updater.exe <zip_path> <app_exe_path> [new_version]');
    exit(1);
  }

  final zipPath = args[0];
  final appExePath = args[1];
  // Optional 3rd arg: the new version string (e.g. "1.0.1"), passed by the
  // Flutter app so the updater can write installed_version.txt after success.
  final newVersion = args.length >= 3 ? args[2].trim() : null;

  final appDir = p.dirname(appExePath);
  final appExeName = p.basename(appExePath);

  _log('Crusam Updater starting…');
  _log('ZIP     : $zipPath');
  _log('App     : $appExePath');
  _log('Dir     : $appDir');
  if (newVersion != null) _log('Version : $newVersion');

  _log('Waiting for main app to exit…');
  await _waitForProcessExit(appExeName);
  _log('Main app has exited.');

  _log('Extracting update…');
  final success = await _extractZip(zipPath, appDir);
  if (!success) {
    _log('ERROR: Extraction failed. Aborting.');
    exit(2);
  }
  _log('Extraction complete.');

  // ── Write the installed version so the app knows what it's running ───────
  // This is the single source of truth for "current version" after an update.
  // The Flutter app reads this file on startup instead of relying solely on
  // PackageInfo.fromPlatform(), which can return a stale value when the PE
  // resources haven't been refreshed yet (e.g. the ZIP had a nested folder
  // and crusam.exe wasn't replaced in place).
  if (newVersion != null && newVersion.isNotEmpty) {
    try {
      final versionFile =
          File(p.join(appDir, 'installed_version.txt'));
      versionFile.writeAsStringSync(newVersion);
      _log('Wrote installed_version.txt → $newVersion');
    } catch (e) {
      // Non-fatal — the app falls back to PackageInfo if the file is absent.
      _log('WARNING: Could not write installed_version.txt: $e');
    }
  }

  try {
    File(zipPath).deleteSync();
    _log('Cleaned up temporary ZIP.');
  } catch (_) {
    // Non-fatal.
  }

  _log('Restarting app…');
  await _restartApp(appExePath);

  _log('Done.');
  exit(0);
}

// ── Process helpers ───────────────────────────────────────────────────────

Future<void> _waitForProcessExit(String exeName) async {
  for (var i = 0; i < 120; i++) {
    if (!_isProcessRunning(exeName)) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  _log('WARNING: Timed out waiting for app exit. Proceeding anyway.');
}

bool _isProcessRunning(String exeName) {
  try {
    final result = Process.runSync(
      'tasklist',
      ['/FI', 'IMAGENAME eq $exeName', '/NH'],
      stdoutEncoding: const SystemEncoding(),
    );
    final output = result.stdout as String;
    return output.toLowerCase().contains(exeName.toLowerCase());
  } catch (_) {
    return false;
  }
}

// ── ZIP extraction ────────────────────────────────────────────────────────

/// Detects a single common top-level directory shared by every entry in the
/// archive (e.g. a ZIP created by right-clicking a folder on Windows or by
/// GitHub Actions that wraps everything in "Release/").
///
/// Returns the prefix string (e.g. "Release/") if ALL entries share one,
/// or null if any entry is at the root or if there are multiple top-level dirs.
String? _findCommonPrefix(Archive archive) {
  String? prefix;
  for (final file in archive) {
    // Normalise to forward slashes for consistent splitting.
    final name = file.name.replaceAll(r'\', '/');
    final slash = name.indexOf('/');
    if (slash < 0) {
      // This entry is at the root level — no common prefix possible.
      return null;
    }
    final top = name.substring(0, slash + 1); // e.g. "Release/"
    if (prefix == null) {
      prefix = top;
    } else if (prefix != top) {
      return null; // Multiple different top-level dirs — don't strip.
    }
  }
  return prefix; // null if archive was empty
}

Future<bool> _extractZip(String zipPath, String destinationDir) async {
  try {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Auto-detect whether the ZIP wraps everything in one top-level folder.
    // If so, strip that prefix so files land directly in destinationDir.
    // This handles both structures:
    //   ✓  crusam.exe          → appDir/crusam.exe
    //   ✓  Release/crusam.exe  → appDir/crusam.exe  (prefix stripped)
    final prefix = _findCommonPrefix(archive);
    if (prefix != null) {
      _log('  Detected ZIP prefix "$prefix" — stripping for extraction.');
    }

    for (final file in archive) {
      // Normalise separators.
      var entryName = file.name.replaceAll(r'\', '/');

      // Strip common prefix if every entry shares one.
      if (prefix != null) {
        if (!entryName.startsWith(prefix)) continue;
        entryName = entryName.substring(prefix.length);
        if (entryName.isEmpty) continue; // The directory entry itself.
      }

      if (_containsProtectedSegment(entryName)) {
        _log('  SKIP (protected): $entryName');
        continue;
      }

      final outPath = p.normalize(p.join(destinationDir, entryName));

      if (!p.isWithin(destinationDir, outPath) &&
          outPath != destinationDir) {
        _log('  SKIP (path traversal attempt): $entryName');
        continue;
      }

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        _log('  WRITE: $entryName');
      } else {
        await Directory(outPath).create(recursive: true);
      }
    }
    return true;
  } catch (e) {
    _log('  Exception during extraction: $e');
    return false;
  }
}

bool _containsProtectedSegment(String archivePath) {
  final segments = p.split(archivePath.replaceAll('/', p.separator));
  for (final seg in segments) {
    if (_protectedSegments.contains(seg)) return true;
  }
  return false;
}

// ── App restart ───────────────────────────────────────────────────────────

Future<void> _restartApp(String appExePath) async {
  try {
    await Process.start(
      appExePath,
      const [],
      // Explicitly set the working directory to the app folder so that
      // relative paths (e.g. sqflite current-dir databases) resolve the
      // same way they did before the update.
      workingDirectory: p.dirname(appExePath),
      mode: ProcessStartMode.detached,
    );
  } catch (e) {
    _log('WARNING: Could not restart app automatically: $e');
    _log('Please start $appExePath manually.');
  }
}

// ── Logging ───────────────────────────────────────────────────────────────

void _log(String message) {
  final now = DateTime.now();
  final ts =
      '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  print('[$ts] $message');

  try {
    final logFile = File(
      p.join(p.dirname(Platform.resolvedExecutable), 'updater.log'),
    );
    logFile.writeAsStringSync(
      '[$ts] $message\n',
      mode: FileMode.append,
    );
  } catch (_) {
    // Non-fatal if log cannot be written.
  }
}
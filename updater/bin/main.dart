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
    _log('Usage: updater.exe <zip_path> <app_exe_path>');
    exit(1);
  }

  final zipPath = args[0];
  final appExePath = args[1];
  final appDir = p.dirname(appExePath);
  final appExeName = p.basename(appExePath);

  _log('Crusam Updater starting…');
  _log('ZIP  : $zipPath');
  _log('App  : $appExePath');
  _log('Dir  : $appDir');

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

Future<bool> _extractZip(String zipPath, String destinationDir) async {
  try {
    final bytes = File(zipPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (_containsProtectedSegment(file.name)) {
        _log('  SKIP (protected): ${file.name}');
        continue;
      }

      final outPath = p.join(destinationDir, file.name);

      if (!p.isWithin(destinationDir, outPath) && outPath != destinationDir) {
        _log('  SKIP (path traversal attempt): ${file.name}');
        continue;
      }

      if (file.isFile) {
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);
        _log('  WRITE: ${file.name}');
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
  final segments = p.split(archivePath.replaceAll('\\', '/'));
  for (final seg in segments) {
    if (_protectedSegments.contains(seg)) return true;
  }
  return false;
}

Future<void> _restartApp(String appExePath) async {
  try {
    await Process.start(
      appExePath,
      const [],
      mode: ProcessStartMode.detached,
    );
  } catch (e) {
    _log('WARNING: Could not restart app automatically: $e');
    _log('Please start $appExePath manually.');
  }
}

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
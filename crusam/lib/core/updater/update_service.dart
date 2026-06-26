// lib/core/updater/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';
import 'version_constants.dart';

class UpdateService {
  UpdateService._();

  /// Returns the current installed version.
  ///
  /// Priority order:
  ///   1. `installed_version.txt` written by updater.exe after a successful
  ///      in-place update.  This is the most reliable source because it's
  ///      written at the moment the new files land on disk.
  ///   2. `PackageInfo.fromPlatform()` — reads the PE version resources baked
  ///      into the running executable at compile time.  Accurate for fresh
  ///      installs; can be stale if the updater extracted files into a
  ///      subdirectory and crusam.exe was not actually replaced in-place.
  static Future<String> getCurrentVersion() async {
    if (Platform.isWindows) {
      final installed = await _readInstalledVersionFile();
      if (installed != null) return installed;
    }
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// Reads the version written by updater.exe to `<appDir>/installed_version.txt`.
  /// Returns null if the file doesn't exist or can't be read.
  static Future<String?> _readInstalledVersionFile() async {
    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final file =
          File('$appDir${Platform.pathSeparator}installed_version.txt');
      if (!file.existsSync()) return null;
      final version = file.readAsStringSync().trim();
      return version.isEmpty ? null : version;
    } catch (_) {
      return null;
    }
  }

  /// Throws on any network / parse error so the notifier's catch block fires.
  static Future<UpdateInfo> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();

    final response = await http
        .get(Uri.parse(kLatestJsonUrl))
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final latestVersion = (data['version'] as String).trim();
    final message =
        (data['message'] as String?) ?? 'A new version is available.';
    final force = (data['force'] as bool?) ?? false;
    final downloadUrl = (data['download_url'] as String).trim();

    if (!downloadUrl.startsWith('https://') &&
        !downloadUrl.startsWith('http://')) {
      throw Exception(
          'Invalid download_url in latest.json: "$downloadUrl"\n'
          'It must start with https:// and point to the actual .zip asset.\n'
          'Example: https://github.com/CruciaTos/Crusam_RELEASE-VERSION'
          '/releases/download/v$latestVersion/crusam_v$latestVersion.zip');
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      updateAvailable: _isNewer(latestVersion, currentVersion),
      message: message,
      force: force,
      downloadUrl: downloadUrl,
    );
  }

  /// Returns the local zip path on success.
  /// Throws a descriptive [Exception] on any failure so the notifier can
  /// surface the real reason to the user instead of a generic message.
  static Future<String> downloadUpdate(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final tmpDir = await getTemporaryDirectory();
      final zipPath =
          '${tmpDir.path}${Platform.pathSeparator}crusam_update.zip';

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
            'Download server returned ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      var received = 0;

      final file = File(zipPath);
      final sink = file.openWrite();

      try {
        await for (final chunk in streamedResponse.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (contentLength > 0) {
            onProgress(received / contentLength);
          }
        }
      } finally {
        await sink.close();
      }

      final written = await file.length();
      if (written == 0) {
        throw Exception('Downloaded file is empty — the URL may be invalid.');
      }

      return zipPath;
    } catch (e) {
      throw Exception('Download failed: $e');
    } finally {
      client.close();
    }
  }

  /// Launches updater.exe and exits the main process.
  ///
  /// [newVersion] is passed to updater.exe as a 3rd argument so it can write
  /// `installed_version.txt` after extraction — this is what fixes the
  /// "version stays at 1.0.0 after update" issue.
  ///
  /// Returns `null` on success (process calls exit(0) so we never return).
  /// Returns a non-null error string that the UI can display on any failure.
  static Future<String?> launchUpdaterAndExit(
    String zipPath,
    String newVersion,
  ) async {
    try {
      if (!Platform.isWindows) {
        return 'Auto-update is only supported on Windows.';
      }

      final appDir = File(Platform.resolvedExecutable).parent.path;
      final updaterPath = '$appDir${Platform.pathSeparator}updater.exe';

      if (!File(updaterPath).existsSync()) {
        return 'updater.exe not found in $appDir. '
            'Please reinstall the application or update manually.';
      }

      final zipFile = File(zipPath);
      if (!zipFile.existsSync() || zipFile.lengthSync() == 0) {
        return 'Update package is missing or empty ($zipPath).';
      }

      await Process.start(
        updaterPath,
        // 3rd arg is the new version — updater writes it to
        // installed_version.txt after a successful extraction.
        [zipPath, Platform.resolvedExecutable, newVersion],
        workingDirectory: appDir,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      exit(0);
    } catch (e) {
      return 'Failed to launch updater: $e';
    }
  }

  static bool _isNewer(String candidate, String current) {
    final c = _parse(candidate);
    final cur = _parse(current);
    for (var i = 0; i < 3; i++) {
      if (c[i] > cur[i]) return true;
      if (c[i] < cur[i]) return false;
    }
    return false;
  }

  static List<int> _parse(String version) {
    final parts = version.split('.');
    return List<int>.generate(
      3,
      (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0,
    );
  }
}
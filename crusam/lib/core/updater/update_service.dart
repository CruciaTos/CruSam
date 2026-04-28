// lib/core/update/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';
import 'version_constants.dart';

class UpdateService {
  UpdateService._();

  /// Returns the current app version from the compiled binary at runtime.
  /// Always accurate even after updater.exe replaces the binary.
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
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
  /// Returns `null` on success (process calls exit(0) so we never return).
  /// Returns a non-null error string that the UI can display on any failure.
  static Future<String?> launchUpdaterAndExit(String zipPath) async {
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
        [zipPath, Platform.resolvedExecutable],
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
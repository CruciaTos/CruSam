// lib/core/update/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'update_model.dart';
import 'version_constants.dart';

class UpdateService {
  UpdateService._();

  /// Throws on any network / parse error so the notifier's catch block fires.
  static Future<UpdateInfo> checkForUpdate() async {
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
    final downloadUrl = data['download_url'] as String;

    return UpdateInfo(
      currentVersion: kAppVersion,
      latestVersion: latestVersion,
      updateAvailable: _isNewer(latestVersion, kAppVersion),
      message: message,
      force: force,
      downloadUrl: downloadUrl,
    );
  }

  /// Returns the local zip path on success, null on failure.
  /// Always closes the http client.
  static Future<String?> downloadUpdate(
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

      if (streamedResponse.statusCode != 200) return null;

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

      return zipPath;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  static Future<bool> launchUpdaterAndExit(String zipPath) async {
    try {
      if (!Platform.isWindows) {
        throw Exception('Auto-update is only supported on Windows.');
      }

      final appDir = File(Platform.resolvedExecutable).parent.path;
      final updaterPath = '$appDir${Platform.pathSeparator}updater.exe';

      if (!File(updaterPath).existsSync()) return false;

      await Process.start(
        updaterPath,
        [zipPath, Platform.resolvedExecutable],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 500));
      exit(0);
    } catch (_) {
      return false;
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
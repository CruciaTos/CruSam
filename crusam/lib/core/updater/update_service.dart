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
  ///   1. `PackageInfo.fromPlatform()` — reads the PE version resources baked
  ///      into the running executable at compile time. This is sourced
  ///      directly from `pubspec.yaml`'s `version:` field via Flutter's
  ///      Windows build tooling (see RELEASE.md), making it the primary,
  ///      single-source-of-truth signal for "what version is this build".
  ///   2. `installed_version.txt` written by updater.exe after a successful
  ///      in-place update — kept ONLY as a temporary compatibility fallback
  ///      for installs updated by an older build of updater.exe. It is only
  ///      consulted if PackageInfo reports an empty version, which should
  ///      not happen on a properly built release. Do not treat this file as
  ///      a version source for new code; it is scheduled for removal once
  ///      all installs are confirmed to be on a clean, pubspec-sourced build.
  static Future<String> getCurrentVersion() async {
    final info = await PackageInfo.fromPlatform();
    final packageVersion = info.version.trim();
    if (packageVersion.isNotEmpty) {
      return packageVersion;
    }

    if (Platform.isWindows) {
      final installed = await _readInstalledVersionFile();
      if (installed != null) return installed;
    }

    return packageVersion;
  }

  /// Reads the version written by updater.exe to `<appDir>/installed_version.txt`.
  /// Temporary compatibility fallback only — see [getCurrentVersion].
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

  /// Checks GitHub Releases for the latest published Crusam release.
  ///
  /// This never throws. If GitHub is unreachable, no release has been
  /// published yet, the release has no matching installer asset, or the
  /// response can't be parsed, this returns a graceful "no update
  /// information available" [UpdateInfo] (`updateAvailable: false`) instead
  /// of crashing or surfacing an error banner to the user.
  static Future<UpdateInfo> checkForUpdate() async {
    final currentVersion = await getCurrentVersion();
    final release = await _fetchLatestRelease();

    if (release == null) {
      return _noUpdateInfo(currentVersion);
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: release.version,
      updateAvailable: _isNewer(release.version, currentVersion),
      message: release.message,
      // GitHub Releases has no concept of a "force this update" flag — that
      // was only ever a manually-set field in the old latest.json. Forced
      // updates aren't supported by this source; a future phase could
      // encode that signal in the release itself (e.g. a tag/title marker
      // or a required-version file) if it's needed again.
      force: false,
      downloadUrl: release.downloadUrl,
    );
  }

  /// [UpdateInfo] used whenever release information couldn't be obtained.
  /// `latestVersion` is set to `currentVersion` so nothing downstream
  /// mistakenly reports an update as available.
  static UpdateInfo _noUpdateInfo(String currentVersion) {
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      updateAvailable: false,
      message: 'No update information available.',
      force: false,
      downloadUrl: '',
    );
  }

  /// Fetches and parses the latest GitHub release, extracting the version
  /// (from `tag_name`) and the installer download URL (from `assets[]`).
  ///
  /// Returns `null` — never throws — if anything goes wrong: network
  /// failure, non-200 response (including 404 when no release exists yet),
  /// malformed JSON, a missing/empty `tag_name`, or no asset matching the
  /// installer naming convention.
  static Future<_LatestRelease?> _fetchLatestRelease() async {
    try {
      final response = await http.get(
        Uri.parse(kLatestReleaseApiUrl),
        headers: const {
          // GitHub requires a User-Agent on API requests; omitting it can
          // result in a 403 even for unauthenticated public endpoints.
          'User-Agent': '$kGitHubRepoName-app',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;

      final tagName = (decoded['tag_name'] as String?)?.trim();
      if (tagName == null || tagName.isEmpty) return null;
      final version = _stripLeadingV(tagName);
      if (version.isEmpty) return null;

      final assets = decoded['assets'];
      if (assets is! List) return null;

      String? downloadUrl;
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) continue;
        final name = asset['name'] as String?;
        final url = asset['browser_download_url'] as String?;
        if (name == null || url == null) continue;
        if (_isInstallerAsset(name)) {
          downloadUrl = url;
          break;
        }
      }
      if (downloadUrl == null) return null;

      return _LatestRelease(
        version: version,
        downloadUrl: downloadUrl,
        // Release notes (`body`) can be long, markdown-formatted, or
        // absent — not suitable to drop straight into the compact update
        // dialog, so a short fixed message is used instead.
        message: 'A new version is available.',
      );
    } catch (_) {
      return null;
    }
  }

  /// Strips a single optional leading "v"/"V" from a release tag.
  /// `v1.1.0` -> `1.1.0`; `1.1.0` -> `1.1.0`.
  static String _stripLeadingV(String tagName) {
    if (tagName.isEmpty) return tagName;
    final first = tagName[0];
    return (first == 'v' || first == 'V') ? tagName.substring(1) : tagName;
  }

  /// Matches the release asset that is the actual Windows installer,
  /// e.g. `CruSam-Setup-1.2.0.exe`. Explicitly excludes GitHub's
  /// auto-generated source archives and anything else that isn't the
  /// installer executable.
  static bool _isInstallerAsset(String assetName) {
    final lower = assetName.toLowerCase();
    if (lower.endsWith('.zip') || lower.endsWith('.tar.gz')) return false;
    return assetName.startsWith(kInstallerAssetPrefix) &&
        lower.endsWith(kInstallerAssetExtension);
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

/// Minimal internal holder for the parts of a GitHub release that
/// [UpdateService] cares about. Not exported — [UpdateInfo] remains the
/// public shape callers work with.
class _LatestRelease {
  const _LatestRelease({
    required this.version,
    required this.downloadUrl,
    required this.message,
  });

  final String version;
  final String downloadUrl;
  final String message;
}
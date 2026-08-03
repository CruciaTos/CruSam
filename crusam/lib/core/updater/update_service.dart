// lib/core/updater/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  /// Downloads the installer EXE referenced by [downloadUrl] (the
  /// `CruSam-Setup-{version}.exe` asset from Phase 4's GitHub Releases
  /// lookup) into [getTemporaryDirectory], preserving its original
  /// filename, and returns the local path on success.
  ///
  /// Replaces the old ZIP download — there is no extraction step anymore;
  /// the file saved here is handed directly to
  /// [launchUpdaterAndExit], which runs it as a real Inno Setup installer.
  ///
  /// Throws a descriptive [Exception] on any failure so the notifier can
  /// surface the real reason to the user instead of a generic message.
  static Future<String> downloadUpdate(
    String downloadUrl,
    void Function(double progress) onProgress,
  ) async {
    final client = http.Client();
    try {
      final tmpDir = await getTemporaryDirectory();
      final fileName = _installerFileNameFrom(downloadUrl);
      final installerPath =
          '${tmpDir.path}${Platform.pathSeparator}$fileName';

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode != 200) {
        throw Exception(
            'Download server returned ${streamedResponse.statusCode}');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      var received = 0;

      final file = File(installerPath);
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

      // Checksum verification extension point — see
      // _verifyChecksumIfAvailable for details. Currently a no-op for every
      // real release because the pipeline doesn't publish a checksum asset
      // yet, so behavior here is unchanged from before this method existed.
      await _verifyChecksumIfAvailable(client, downloadUrl, file);

      return installerPath;
    } catch (e) {
      throw Exception('Download failed: $e');
    } finally {
      client.close();
    }
  }

  /// Derives the on-disk filename for the downloaded installer from
  /// [downloadUrl], preserving the original asset filename (e.g.
  /// `CruSam-Setup-1.2.0.exe`) instead of a generic hardcoded name — the
  /// installer's own name is what Windows/Inno Setup will show in any
  /// UAC-less "Open File" prompts and logs, so keeping it intact matters.
  ///
  /// GitHub release asset download URLs always end in the asset's literal
  /// filename, so this only falls back to a synthesized name if that ever
  /// stops being true (e.g. a malformed URL).
  static String _installerFileNameFrom(String downloadUrl) {
    final segments = Uri.parse(downloadUrl).pathSegments;
    final last = segments.isNotEmpty ? segments.last.trim() : '';
    if (last.isNotEmpty) return last;
    return '$kInstallerAssetPrefix'
        '${DateTime.now().millisecondsSinceEpoch}'
        '$kInstallerAssetExtension';
  }

  /// Best-effort SHA-256 verification against a sibling
  /// `<installer-filename>.sha256` release asset, if the release publishes
  /// one.
  ///
  /// This is a clean extension point, not a hard requirement yet: neither
  /// build_release.ps1 nor crusam_installer.iss currently produces a
  /// checksum file alongside the installer, so `$downloadUrl.sha256` 404s
  /// for every release today and this silently returns without altering
  /// [downloadUpdate]'s behavior at all. The moment the release pipeline
  /// starts publishing that sibling asset (a plain-text file containing the
  /// 64-character hex SHA-256 digest, with or without a trailing filename
  /// in the usual `sha256sum` output style), verification switches on
  /// automatically: the downloaded installer is hashed and compared, and a
  /// mismatch deletes the file and throws so a corrupted or tampered
  /// installer is never handed to [launchUpdaterAndExit].
  static Future<void> _verifyChecksumIfAvailable(
    http.Client client,
    String downloadUrl,
    File installerFile,
  ) async {
    String expectedHex;
    try {
      final checksumResponse = await client
          .get(Uri.parse('$downloadUrl.sha256'))
          .timeout(const Duration(seconds: 10));

      if (checksumResponse.statusCode != 200) return;

      final match =
          RegExp(r'[0-9a-fA-F]{64}').firstMatch(checksumResponse.body);
      if (match == null) return;

      expectedHex = match.group(0)!.toLowerCase();
    } catch (_) {
      // No checksum asset published (or transiently unreachable) — treated
      // as "checksum support not implemented for this release", not as an
      // error. Existing releases without a .sha256 asset must keep working
      // exactly as they do today.
      return;
    }

    final bytes = await installerFile.readAsBytes();
    final actualHex = sha256.convert(bytes).toString();

    if (actualHex != expectedHex) {
      try {
        await installerFile.delete();
      } catch (_) {
        // Best-effort cleanup only; the exception below is what matters.
      }
      throw Exception(
        'Checksum verification failed — the downloaded installer does not '
        'match the published SHA-256 digest. Update aborted.',
      );
    }
  }

  /// Launches the downloaded installer silently and exits the app.
  ///
  /// Replaces the old ZIP + updater.exe workflow now that GitHub Releases
  /// publishes a real Inno Setup installer (Phase 4/5). [installerPath] is
  /// the local path returned by [downloadUpdate].
  ///
  /// `/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-` run the installer
  /// fully unattended — no wizard pages, no message boxes, no forced
  /// reboot, no "This will install..." confirmation prompt. Inno Setup's
  /// native CloseApplications (see crusam_installer.iss) closes the
  /// currently-running crusam.exe before copying files over it, and its
  /// [Run] section's `skipifnotsilent` entry relaunches crusam.exe once the
  /// silent install finishes — so nothing further is required here once
  /// the installer process has been started.
  ///
  /// [newVersion] is intentionally unused here: unlike the old updater.exe,
  /// this installer embeds the real version at build time (VersionInfoVersion
  /// in crusam_installer.iss, sourced from pubspec.yaml — see RELEASE.md),
  /// so the relaunched crusam.exe reports the new version directly via
  /// `PackageInfo.fromPlatform()` in [getCurrentVersion] with no file to
  /// write. The parameter is kept only so this method's signature keeps
  /// matching the call in UpdateNotifier.downloadAndInstall(), which is out
  /// of scope for this phase.
  ///
  /// Returns `null` on success — the process calls `exit(0)`, so callers
  /// never actually observe that return value. Returns a non-null error
  /// string that the UI can display on any failure.
  static Future<String?> launchUpdaterAndExit(
    String installerPath,
    String newVersion,
  ) async {
    try {
      if (!Platform.isWindows) {
        return 'Auto-update is only supported on Windows.';
      }

      final installerFile = File(installerPath);
      if (!installerFile.existsSync() || installerFile.lengthSync() == 0) {
        return 'Update installer is missing or empty ($installerPath).';
      }

      await Process.start(
        installerPath,
        const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-'],
        workingDirectory: installerFile.parent.path,
        mode: ProcessStartMode.detached,
        runInShell: false,
      );

      await Future<void>.delayed(const Duration(milliseconds: 1500));
      exit(0);
    } catch (e) {
      return 'Failed to launch installer: $e';
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
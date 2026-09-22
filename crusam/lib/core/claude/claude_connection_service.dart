// lib/core/claude/claude_connection_service.dart
//
// Connecting CruSam to Claude Desktop in one click.
//
// Release builds ship the CruSam MCP server next to crusam.exe
// (claude-server\bin\server.exe, built by installer\build_release.ps1).
// Connecting copies it to a per-version folder under %LOCALAPPDATA% and adds
// a "crusam" entry to Claude Desktop's claude_desktop_config.json pointing at
// that copy. (The Microsoft Store build of Claude Desktop can't open .mcpb
// extension files, so this doesn't rely on them.)
//
// Why a copy: Claude Desktop keeps server.exe running, and a running exe is
// locked, so an app update could not replace it in the install folder. Each
// app version gets its own folder instead; updates switch the config to the
// new one automatically and Claude picks it up the next time it starts.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../updater/update_service.dart';

class ClaudeConnection {
  /// Claude Desktop has been run on this computer (its data folder exists).
  final bool claudeInstalled;

  /// Version of the CruSam server Claude is set up with by this app, or null.
  final String? connectedVersion;

  /// A "crusam" entry this app didn't make (a developer's hand setup).
  final bool manualSetup;

  /// This build ships the server (false for debug builds).
  final bool canConnect;

  final String appVersion;

  const ClaudeConnection({
    required this.claudeInstalled,
    required this.connectedVersion,
    required this.manualSetup,
    required this.canConnect,
    required this.appVersion,
  });

  bool get connected => manualSetup || connectedVersion != null;
  bool get upToDate => manualSetup || connectedVersion == appVersion;

  /// Worth offering the one-click connect.
  bool get needsAction => claudeInstalled && canConnect && !connected;
}

class ConnectResult {
  final bool ok;
  final String? error;

  /// Claude Desktop is running and must restart to load CruSam.
  final bool claudeRunning;
  const ConnectResult({required this.ok, this.error, this.claudeRunning = false});
}

class ClaudeConnectionService {
  ClaudeConnectionService._();

  static const serverName = 'crusam';
  static const downloadUrl = 'https://claude.ai/download';

  static String get _bundledDir =>
      p.join(p.dirname(Platform.resolvedExecutable), 'claude-server');

  /// %LOCALAPPDATA%\CruSam\claude-server — one sub-folder per app version.
  static String get _managedRoot =>
      p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'CruSam', 'claude-server');

  static Future<String> _appVersion() async {
    try {
      return (await UpdateService.getCurrentVersion()).split('+').first;
    } catch (_) {
      return ''; // e.g. no version info (tests); nothing to compare then
    }
  }

  static Future<ClaudeConnection> check() async {
    var installed = false;
    String? version;
    var manual = false;
    for (final dir in _claudeDataDirs()) {
      if (!dir.existsSync()) continue;
      installed = true;
      final command = _configuredCommand(dir);
      if (command == null) continue;
      final v = _managedVersionOf(command);
      if (v != null) {
        version ??= v;
      } else {
        manual = true;
      }
    }
    return ClaudeConnection(
      claudeInstalled: installed,
      connectedVersion: version,
      manualSetup: manual && version == null,
      canConnect: File(p.join(_bundledDir, 'bin', 'server.exe')).existsSync(),
      appVersion: await _appVersion(),
    );
  }

  /// Sets Claude Desktop up with this version's server.
  static Future<ConnectResult> connect() async {
    try {
      final version = await _appVersion();
      if (version.isEmpty) {
        return const ConnectResult(ok: false, error: "Couldn't read CruSam's version.");
      }
      final exe = await _installServer(version);
      final dirs = _claudeDataDirs().where((d) => d.existsSync()).toList();
      if (dirs.isEmpty) {
        return const ConnectResult(ok: false, error: 'Claude Desktop is not installed.');
      }
      for (final dir in dirs) {
        _writeConfig(dir, exe);
      }
      _removeOldServers(version);
      return ConnectResult(ok: true, claudeRunning: await isClaudeRunning());
    } catch (e) {
      debugPrint('ClaudeConnectionService.connect: $e');
      return ConnectResult(ok: false, error: '$e');
    }
  }

  /// At start-up: after an app update, move Claude to the new server. Claude
  /// keeps using the old one until it next starts, so nothing is interrupted.
  static Future<void> keepUpToDate() async {
    try {
      final s = await check();
      if (s.connectedVersion != null && !s.upToDate && s.canConnect) {
        await connect();
      }
    } catch (e) {
      debugPrint('ClaudeConnectionService.keepUpToDate: $e');
    }
  }

  // ── Claude Desktop process ────────────────────────────────────────────────

  /// Claude Desktop only: Claude Code's CLI is also called claude.exe, so
  /// processes are matched by install folder, never by name alone.
  static const _desktopFilter =
      r"Get-Process claude -ErrorAction SilentlyContinue | Where-Object { "
      r"$_.Path -like '*\WindowsApps\Claude_*' -or $_.Path -like '*\AnthropicClaude\*' }";

  static Future<bool> isClaudeRunning() async {
    try {
      final r = await Process.run('powershell',
          ['-NoProfile', '-Command', '($_desktopFilter | Measure-Object).Count']);
      return (int.tryParse('${r.stdout}'.trim()) ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> restartClaude() async {
    try {
      await Process.run('powershell',
          ['-NoProfile', '-Command', '$_desktopFilter | Stop-Process -Force']);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    } catch (e) {
      debugPrint('ClaudeConnectionService.restartClaude: $e');
    }
    await openClaude();
  }

  static Future<void> openClaude() async {
    try {
      final family = _storeFamily();
      if (family != null) {
        await Process.run('explorer.exe', ['shell:AppsFolder\\$family!Claude']);
        return;
      }
      final exe = p.join(Platform.environment['LOCALAPPDATA'] ?? '', 'AnthropicClaude', 'claude.exe');
      if (File(exe).existsSync()) {
        await Process.start(exe, const [], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint('ClaudeConnectionService.openClaude: $e');
    }
  }

  static Future<void> openDownloadPage() async {
    try {
      await Process.run('cmd', ['/c', 'start', '', downloadUrl]);
    } catch (e) {
      debugPrint('ClaudeConnectionService.openDownloadPage: $e');
    }
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  /// Copies the bundled server to its version folder (once). Returns server.exe.
  static Future<String> _installServer(String version) async {
    final dest = Directory(p.join(_managedRoot, version));
    final exe = p.join(dest.path, 'bin', 'server.exe');
    if (File(exe).existsSync()) return exe;
    final src = Directory(_bundledDir);
    if (!src.existsSync()) throw StateError('This build does not include the Claude server.');
    final tmp = Directory('${dest.path}.partial');
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    for (final e in src.listSync(recursive: true)) {
      if (e is! File) continue;
      final to = File(p.join(tmp.path, p.relative(e.path, from: src.path)));
      to.parent.createSync(recursive: true);
      e.copySync(to.path);
    }
    tmp.renameSync(dest.path);
    return exe;
  }

  /// Deletes other versions' copies; one Claude still runs stays (locked).
  static void _removeOldServers(String keep) {
    final root = Directory(_managedRoot);
    if (!root.existsSync()) return;
    for (final d in root.listSync().whereType<Directory>()) {
      if (p.basename(d.path) == keep) continue;
      try {
        d.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  static void _writeConfig(Directory claudeDir, String exe) {
    final f = File(p.join(claudeDir.path, 'claude_desktop_config.json'));
    Map<String, dynamic> json = {};
    if (f.existsSync()) {
      final text = f.readAsStringSync();
      if (text.trim().isNotEmpty) {
        // Throws on a broken file: better to stop than overwrite it.
        json = jsonDecode(text) as Map<String, dynamic>;
      }
      final backup = File('${f.path}.bak-crusam');
      if (!backup.existsSync()) backup.writeAsStringSync(text);
    }
    final servers = (json['mcpServers'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    // No env: the server finds the CruSam app's own database by itself.
    servers[serverName] = {'command': exe, 'args': <String>[], 'env': <String, String>{}};
    json['mcpServers'] = servers;
    f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
  }

  static String? _configuredCommand(Directory claudeDir) {
    try {
      final f = File(p.join(claudeDir.path, 'claude_desktop_config.json'));
      if (!f.existsSync()) return null;
      final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final entry = (json['mcpServers'] as Map?)?[serverName] as Map?;
      return entry?['command'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// "1.4.1" when [command] is one of this app's server copies, else null.
  static String? _managedVersionOf(String command) {
    final root = p.normalize(_managedRoot).toLowerCase();
    final exe = p.normalize(command).toLowerCase();
    if (!p.isWithin(root, exe) || !File(command).existsSync()) return null;
    return p.split(p.relative(p.normalize(command), from: p.normalize(_managedRoot))).first;
  }

  /// Claude Desktop's data folders: %APPDATA%\Claude for the regular
  /// installer, a sandboxed copy of it for the Microsoft Store app.
  static List<Directory> _claudeDataDirs() {
    final dirs = <Directory>[];
    final roaming = Platform.environment['APPDATA'];
    if (roaming != null) dirs.add(Directory(p.join(roaming, 'Claude')));
    final local = Platform.environment['LOCALAPPDATA'];
    final family = _storeFamily();
    if (local != null && family != null) {
      dirs.add(Directory(p.join(local, 'Packages', family, 'LocalCache', 'Roaming', 'Claude')));
    }
    return dirs;
  }

  /// The Microsoft Store package family, e.g. "Claude_pzs8sxrjxfjjc".
  static String? _storeFamily() {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null) return null;
    try {
      for (final e in Directory(p.join(local, 'Packages')).listSync(followLinks: false)) {
        final name = p.basename(e.path);
        if (e is Directory && name.startsWith('Claude_')) return name;
      }
    } catch (_) {}
    return null;
  }
}

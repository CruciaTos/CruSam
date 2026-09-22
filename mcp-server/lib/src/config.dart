import 'dart:io';

import 'package:path/path.dart' as p;

/// Server settings, read from environment variables (set in
/// claude_desktop_config.json) so nothing is hard-coded.
class ServerConfig {
  /// Absolute path to the CruSam SQLite database (aarti.db or a copy).
  final String dbPath;

  /// Recorded in created_by / updated_by on records the server writes.
  final String userEmail;

  /// Optional log file. Logs always go to stderr as well; never to stdout.
  final String? logFile;

  /// When true every write tool refuses to run.
  final bool readOnly;

  /// Where a consistent copy of the database is written before the first
  /// write of each server session.
  final String backupDir;

  /// How many of those backups to keep.
  final int backupKeep;

  const ServerConfig({
    required this.dbPath,
    required this.userEmail,
    required this.logFile,
    required this.readOnly,
    required this.backupDir,
    required this.backupKeep,
  });

  /// Where the CruSam app keeps its database for the current Windows user
  /// (path_provider's application-support dir, see crusam/lib/core/storage/app_paths.dart).
  static String? defaultDbPath(Map<String, String> env) {
    final appData = env['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    return p.join(appData, 'com.cructiatus', 'crusam', 'CruSam', 'aarti.db');
  }

  /// Treats empty values and unsubstituted "${...}" placeholders (from a
  /// Claude Desktop extension setting left blank) as unset.
  static String? _setting(Map<String, String> e, String key) {
    final v = e[key]?.trim();
    if (v == null || v.isEmpty || v.startsWith(r'${')) return null;
    return v;
  }

  static ServerConfig fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    var db = _setting(e, 'CRUSAM_DB_PATH') ?? '';
    if (db.isEmpty) {
      final auto = defaultDbPath(e);
      if (auto == null || !File(auto).existsSync()) {
        throw ConfigError('CruSam database not found'
            '${auto == null ? '' : ' at the default location "$auto"'}. '
            'Open the CruSam app once on this computer so it creates its '
            'database, or set the database path in the extension settings '
            '(CRUSAM_DB_PATH).');
      }
      db = auto;
    }
    if (!p.isAbsolute(db)) {
      throw ConfigError('CRUSAM_DB_PATH must be an absolute path, got "$db".');
    }
    if (!File(db).existsSync()) {
      throw ConfigError('CRUSAM_DB_PATH points to "$db", which does not exist. '
          'The server never creates a new database.');
    }
    final readOnly = const {'1', 'true', 'yes'}
        .contains(_setting(e, 'CRUSAM_READ_ONLY')?.toLowerCase());
    final backupDir = _setting(e, 'CRUSAM_BACKUP_DIR') ??
        p.join(p.dirname(db), 'mcp_backups');
    final keep = int.tryParse(_setting(e, 'CRUSAM_BACKUP_KEEP') ?? '') ?? 10;
    return ServerConfig(
      dbPath: p.normalize(db),
      userEmail: _setting(e, 'CRUSAM_USER_EMAIL')?.toLowerCase() ?? 'claude-mcp',
      logFile: _setting(e, 'CRUSAM_LOG_FILE'),
      readOnly: readOnly,
      backupDir: backupDir,
      backupKeep: keep < 1 ? 1 : keep,
    );
  }
}

class ConfigError implements Exception {
  final String message;
  const ConfigError(this.message);
  @override
  String toString() => message;
}

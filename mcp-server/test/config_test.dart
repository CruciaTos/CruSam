import 'dart:io';

import 'package:crusam_mcp/server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory appData;
  late String dbPath;

  setUp(() {
    appData = Directory.systemTemp.createTempSync('crusam_cfg_');
    dbPath = p.join(appData.path, 'com.cructiatus', 'crusam', 'CruSam', 'aarti.db');
  });
  tearDown(() => appData.deleteSync(recursive: true));

  test('finds the app database automatically when no path is set', () {
    File(dbPath)..createSync(recursive: true);
    for (final blank in [null, '', r'${user_config.db_path}']) {
      final c = ServerConfig.fromEnvironment({
        'APPDATA': appData.path,
        if (blank != null) 'CRUSAM_DB_PATH': blank,
        'CRUSAM_READ_ONLY': 'false',
        'CRUSAM_USER_EMAIL': '',
      });
      expect(c.dbPath, p.normalize(dbPath));
      expect(c.readOnly, isFalse);
      expect(c.userEmail, 'claude-mcp');
      expect(c.backupDir, p.join(p.dirname(p.normalize(dbPath)), 'mcp_backups'));
    }
  });

  test('explains what to do when the app has never been run', () {
    expect(
      () => ServerConfig.fromEnvironment({'APPDATA': appData.path}),
      throwsA(isA<ConfigError>().having(
          (e) => e.message, 'message', contains('Open the CruSam app once'))),
    );
  });

  test('an explicit path wins and extension booleans are understood', () {
    final other = File(p.join(appData.path, 'copy.db'))..createSync();
    final c = ServerConfig.fromEnvironment({
      'APPDATA': appData.path,
      'CRUSAM_DB_PATH': other.path,
      'CRUSAM_READ_ONLY': 'true',
    });
    expect(c.dbPath, p.normalize(other.path));
    expect(c.readOnly, isTrue);
  });
}

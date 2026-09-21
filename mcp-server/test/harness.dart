import 'dart:convert';
import 'dart:io';

import 'package:crusam_mcp/server.dart';
import 'package:crusam_mcp/src/tool_kit.dart';
import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

/// Source database for tests: a COPY of the real data (never the real file).
/// Each test works on its own throwaway copy of this copy.
String sourceDbPath() =>
    Platform.environment['CRUSAM_TEST_DB'] ??
    p.join(Directory.current.path, 'dev-data', 'aarti_dev.db');

bool get hasSourceDb => File(sourceDbPath()).existsSync();

const skipReason = 'No test database. Copy aarti.db to '
    'mcp-server/dev-data/aarti_dev.db (see README) or set CRUSAM_TEST_DB.';

class Harness {
  final Directory dir;
  final CrusamDb store;
  final ToolContext ctx;
  final Map<String, ToolDef> tools;

  Harness._(this.dir, this.store, this.ctx, this.tools);

  static Future<Harness> open({bool readOnly = false}) async {
    final real = p.normalize(p.join(Platform.environment['APPDATA'] ?? '',
        'com.cructiatus', 'crusam', 'CruSam', 'aarti.db'));
    if (p.equals(p.normalize(sourceDbPath()), real)) {
      throw StateError('Refusing to run tests against the real database.');
    }
    final dir = Directory.systemTemp.createTempSync('crusam_mcp_test_');
    final db = p.join(dir.path, 'aarti_test.db');
    File(sourceDbPath()).copySync(db);
    final config = ServerConfig.fromEnvironment({
      'CRUSAM_DB_PATH': db,
      'CRUSAM_USER_EMAIL': 'tester@example.com',
      'CRUSAM_BACKUP_DIR': p.join(dir.path, 'backups'),
      if (readOnly) 'CRUSAM_READ_ONLY': 'true',
    });
    final store = await CrusamDb.open(config);
    var n = 0;
    final ctx = ToolContext(store,
        clock: () => DateTime.utc(2026, 9, 22, 10, 30),
        newUuid: () => 'test-uuid-${n++}');
    final tools = {
      // Exports without output_dir land in the temp folder, never Downloads.
      for (final g in buildToolGroups(ctx,
          exportEnv: ExportEnv(store.db, {
            ...Platform.environment,
            'CRUSAM_EXPORT_DIR': (Directory(p.join(dir.path, 'default-exports'))..createSync()).path,
          })..install()))
        for (final t in g.tools) t.tool.name: t,
    };
    return Harness._(dir, store, ctx, tools);
  }

  /// Calls a tool the way the MCP server does. Returns (isError, body) where
  /// body is decoded JSON on success, or the error text.
  Future<(bool, dynamic)> call(String name, Map<String, Object?> args) async {
    final def = tools[name] ?? (throw ArgumentError('no tool $name'));
    final res = await runTool(def, CallToolRequest(name: name, arguments: args),
        (n, e, st) => throw StateError('$n crashed: $e\n$st'));
    final text = (res.content.first as TextContent).text;
    final isError = res.isError ?? false;
    return (isError, isError ? text : jsonDecode(text));
  }

  Future<Map<String, dynamic>> ok(String name, Map<String, Object?> args) async {
    final (err, body) = await call(name, args);
    if (err) throw StateError('$name failed: $body');
    return body as Map<String, dynamic>;
  }

  Future<String> fails(String name, Map<String, Object?> args) async {
    final (err, body) = await call(name, args);
    if (!err) throw StateError('$name unexpectedly succeeded: $body');
    return body as String;
  }

  Future<int> count(String table, [String where = '1=1']) async =>
      (await store.db.rawQuery('SELECT COUNT(*) AS n FROM $table WHERE $where'))
          .first['n'] as int;

  Future<int> employeeId(String name) async {
    final r = await store.db.query('employees',
        where: 'name = ? AND (is_deleted = 0 OR is_deleted IS NULL)',
        whereArgs: [name]);
    return r.first['id'] as int;
  }

  Future<void> close() async {
    await store.close();
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

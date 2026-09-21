import 'dart:io';

import 'package:crusam_core/crusam_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'config.dart';
import 'log.dart';

/// Schema version written by the CruSam app (DatabaseHelper openDatabase
/// version). Writes are refused against any other version.
const supportedSchemaVersion = 6;

const _requiredColumns = {
  'vouchers': [
    'id', 'title', 'dept_code', 'bill_no', 'po_no', 'item_description',
    'client_name', 'client_address', 'client_gstin', 'client_email',
    'base_total', 'cgst', 'sgst', 'total_tax', 'raw_total', 'round_off',
    'final_total', 'status', 'cloud_id', 'created_by', 'updated_by',
    'is_deleted', 'deleted_at', 'created_at', 'updated_at',
  ],
  'voucher_rows': [
    'voucher_id', 'employee_id', 'employee_name', 'amount', 'from_date',
    'to_date', 'ifsc_code', 'credit_account', 'sb_code', 'bank_detail',
    'place', 'dept_code', 'debit_account', 'debit_account_name',
  ],
  'employees': ['id', 'name', 'code', 'basic_charges', 'other_charges',
      'gross_salary', 'gender', 'cloud_id', 'is_deleted'],
  'company_config': ['company_name', 'account_no'],
};

class ToolError implements Exception {
  final String message;
  const ToolError(this.message);
  @override
  String toString() => message;
}

/// The one connection this server holds. Never runs the app's migrations.
class CrusamDb {
  final ServerConfig config;
  final Database db;
  final int schemaVersion;
  final List<String> schemaProblems;
  bool _backedUp = false;

  CrusamDb._(this.config, this.db, this.schemaVersion, this.schemaProblems);

  static Future<CrusamDb> open(ServerConfig config) async {
    sqfliteFfiInit();
    // No-isolate factory: all SQLite work stays on this isolate, so nothing
    // can bypass the stderr-only logging.
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      config.dbPath,
      options: OpenDatabaseOptions(singleInstance: true),
    );
    // Wait up to 5 s for the app's write lock instead of failing at once.
    await db.rawQuery('PRAGMA busy_timeout = 5000');
    await db.rawQuery('PRAGMA foreign_keys = ON');

    final version =
        (await db.rawQuery('PRAGMA user_version')).first.values.first as int;
    final problems = <String>[];
    if (version != supportedSchemaVersion) {
      problems.add('database schema version is $version, this server '
          'supports $supportedSchemaVersion');
    }
    for (final entry in _requiredColumns.entries) {
      final cols = (await db.rawQuery('PRAGMA table_info(${entry.key})'))
          .map((c) => c['name'] as String)
          .toSet();
      if (cols.isEmpty) {
        problems.add('table ${entry.key} is missing');
        continue;
      }
      final missing = entry.value.where((c) => !cols.contains(c)).toList();
      if (missing.isNotEmpty) {
        problems.add('table ${entry.key} is missing columns $missing');
      }
    }
    if (problems.isNotEmpty) {
      Log.warn('Schema check failed; writes disabled: ${problems.join('; ')}');
    } else if (!config.readOnly) {
      // Additive, idempotent: the address-book table used by client tools.
      await ClientStore.ensureTable(db);
      await EmailOutboxStore.ensureTable(db);
    }
    Log.info('Opened ${config.dbPath} (schema v$version, '
        '${config.readOnly ? 'read-only' : 'read-write'})');
    return CrusamDb._(config, db, version, problems);
  }

  bool get writable => !config.readOnly && schemaProblems.isEmpty;

  Future<bool> hasTable(String name) async => (await db.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", [name]))
      .isNotEmpty;

  /// Runs [action] in one BEGIN IMMEDIATE transaction. Takes a backup first
  /// (once per session).
  Future<T> write<T>(Future<T> Function(Transaction txn) action) async {
    if (config.readOnly) {
      throw const ToolError('The server is running read-only '
          '(CRUSAM_READ_ONLY is set). No changes were made.');
    }
    if (schemaProblems.isNotEmpty) {
      throw ToolError('Writes are disabled because the database schema does '
          'not match what this server expects: ${schemaProblems.join('; ')}. '
          'Update the MCP server to match the app version.');
    }
    await _backupOnce();
    try {
      return await db.transaction(action);
    } on DatabaseException catch (e) {
      if (e.toString().contains('database is locked') ||
          e.toString().contains('SQLITE_BUSY')) {
        throw const ToolError('The database is busy (the CruSam app is '
            'writing). Nothing was changed; retry in a few seconds.');
      }
      rethrow;
    }
  }

  Future<void> _backupOnce() async {
    if (_backedUp) return;
    final dir = Directory(config.backupDir)..createSync(recursive: true);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-')
        .substring(0, 19);
    final dest = p.join(dir.path, 'aarti_mcp_backup_$ts.db');
    // VACUUM INTO produces a transactionally consistent copy even while the
    // app has the file open.
    await db.execute('VACUUM INTO ?', [dest]);
    _backedUp = true;
    Log.info('Backup written: $dest');

    final backups = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('aarti_mcp_backup_'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    for (final old in backups.skip(config.backupKeep)) {
      old.deleteSync();
    }
  }

  Future<void> close() => db.close();
}

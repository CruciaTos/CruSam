import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../core/sync/sync_models.dart';
import '../../core/sync/google_auth_service.dart';
import '../models/employee_model.dart';
import '../models/margin_settings_model.dart';
import '../models/voucher_column_widths_model.dart';
import '../models/bank_column_widths_model.dart';
import '../seeds/employee_seed_data.dart';
import "package:crusam/core/sync/drive_service.dart";

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;
  static const _employeeSeedMasterReplacementMigrationKey =
      'employee_seed_master_replacement_v1';

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    final path = '${await getDatabasesPath()}/aarti.db';
    return openDatabase(
      path,
      version: 6,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, v) async {
        await _createTables(db);
        await _seedCompanyConfig(db);
      },
      onUpgrade: (db, old, v) async {
        await _migrate(db);
      },
      onOpen: (db) async {
        await _migrate(db);
        await _seedCompanyConfig(db);
      },
    );
  }

  Future<void> _migrate(Database db) async {
    await _createTables(db);

    await _ensureColumn(db, 'vouchers', 'bill_no', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'po_no', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'item_description', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_name', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_address', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_gstin', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'cloud_id', 'TEXT');
    await _ensureUniqueIndex(db, 'idx_vouchers_cloud_id', 'vouchers', 'cloud_id');
    await _ensureColumn(db, 'vouchers', 'created_by', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'updated_by', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'is_deleted', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'vouchers', 'deleted_at', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'synced_at', 'TEXT');
    await _ensureColumn(db, 'voucher_rows', 'employee_id', 'TEXT');
    await _ensureColumn(db, 'employees', 'basic_charges', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'employees', 'other_charges', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'employees', 'gross_salary', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'employees', 'gender', "TEXT DEFAULT 'M'");
    await _ensureColumn(db, 'employees', 'cloud_id', 'TEXT');
    await _ensureUniqueIndex(db, 'idx_employees_cloud_id', 'employees', 'cloud_id');
    await _ensureColumn(db, 'employees', 'is_deleted', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'employees', 'deleted_at', 'TEXT');
    await _ensureColumn(db, 'employees', 'synced_at', 'TEXT');
    await _ensureColumn(db, 'pdf_settings', 'voucher_col_widths', 'TEXT');
    await _ensureColumn(db, 'pdf_settings', 'bank_col_widths', 'TEXT');

    await _normalizeEmployeeCodes(db);

    // Keep legacy seed backfills only until the one-time master replacement has
    // run. After that, user/Drive employee edits must remain the source of truth.
    final seedMasterReplacementComplete = await _isMigrationComplete(
      db,
      _employeeSeedMasterReplacementMigrationKey,
    );
    if (!seedMasterReplacementComplete) {
      await _backfillEmployeeCharges(db);
    }
  }

  String _normalizeEmployeeCodeValue(dynamic value) {
    final code = (value?.toString() ?? '').trim();
    final upper = code.toUpperCase();
    if (upper == 'AP' || upper == 'A&P') return 'A&P';
    return code;
  }

  Map<String, dynamic> _normalizeEmployeeData(Map<String, dynamic> data) {
    final normalized = Map<String, dynamic>.from(data);
    if (normalized.containsKey('code')) {
      normalized['code'] = _normalizeEmployeeCodeValue(normalized['code']);
    }
    return normalized;
  }

  Map<String, dynamic> _seedEmployeePayload(
    Map<String, dynamic> seed,
    String now,
  ) {
    final basic = (seed['basic_charges'] as num?)?.toDouble() ?? 0;
    final other = (seed['other_charges'] as num?)?.toDouble() ?? 0;
    return _normalizeEmployeeData({
      ...seed,
      'basic_charges': basic,
      'other_charges': other,
      'gross_salary': basic + other,
      'gender': (seed['gender'] as String?) ?? 'M',
      'is_deleted': 0,
      'deleted_at': null,
      'updated_at': now,
      'synced_at': null,
    });
  }

  Future<void> _normalizeEmployeeCodes(Database db) async {
    await db.rawUpdate(
      "UPDATE employees SET code = 'A&P' WHERE UPPER(TRIM(code)) IN ('AP', 'A&P')",
    );
  }

  String _employeeSeedKey(Map<String, dynamic> employee) {
    String normalized(dynamic value) => (value?.toString() ?? '').trim().toLowerCase();

    final pfNo = normalized(employee['pf_no']);
    if (pfNo.isNotEmpty && pfNo != '-' && !pfNo.endsWith('/')) {
      return 'pf:$pfNo';
    }

    final uanNo = normalized(employee['uan_no']);
    if (uanNo.isNotEmpty && uanNo != '-') {
      return 'uan:$uanNo';
    }

    final name = normalized(employee['name']);
    final accountNumber = normalized(employee['account_number']);
    return 'na:$name|$accountNumber';
  }

  Future<void> _ensureSeedEmployees(Database db) async {
    final existingEmployees = await db.query(
      'employees',
      columns: ['pf_no', 'uan_no', 'name', 'account_number'],
    );

    final existingKeys = existingEmployees.map(_employeeSeedKey).toSet();
    final batch = db.batch();
    var hasInserts = false;

    for (final employee in kEmployeeSeedData) {
      final key = _employeeSeedKey(employee);
      if (existingKeys.contains(key)) continue;

      existingKeys.add(key);
      hasInserts = true;
      batch.insert(
        'employees',
        employee,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    if (hasInserts) {
      await batch.commit(noResult: true);
    }
  }

  Future<bool> _isMigrationComplete(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'app_migrations',
      columns: ['key'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _markMigrationComplete(
    DatabaseExecutor db,
    String key,
    String now,
  ) async {
    await db.insert(
      'app_migrations',
      {'key': key, 'completed_at': now},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// One-time migration that makes [kEmployeeSeedData] the employee master list.
  ///
  /// This intentionally runs only once per local database. It refreshes seed
  /// employees, soft-deletes non-seed employees, and marks changed rows as
  /// needing sync. After the migration marker is written, future launches will
  /// not overwrite user/Drive edits with seed data again.
  Future<bool> applyOneTimeEmployeeSeedMasterReplacement() async {
    final db = await database;
    if (await _isMigrationComplete(
      db,
      _employeeSeedMasterReplacementMigrationKey,
    )) {
      return false;
    }

    final now = DateTime.now().toUtc().toIso8601String();

    await db.transaction((txn) async {
      final existingEmployees = await txn.query('employees');
      final existingByKey = <String, Map<String, dynamic>>{};
      final seedMatchedExistingIds = <int>{};

      for (final employee in existingEmployees) {
        existingByKey.putIfAbsent(_employeeSeedKey(employee), () => employee);
      }

      final seedKeys = <String>{};

      for (final seed in kEmployeeSeedData) {
        final key = _employeeSeedKey(seed);
        seedKeys.add(key);

        final existing = existingByKey[key];
        final payload = _seedEmployeePayload(seed, now);

        if (existing == null) {
          await txn.insert(
            'employees',
            {
              ...payload,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          continue;
        }

        final existingId = existing['id'] as int?;
        if (existingId != null) seedMatchedExistingIds.add(existingId);

        await txn.update(
          'employees',
          payload,
          where: 'id = ?',
          whereArgs: [existingId],
        );
      }

      for (final employee in existingEmployees) {
        final id = employee['id'] as int?;
        final isDeleted = ((employee['is_deleted'] as num?)?.toInt() ?? 0) == 1;
        if (isDeleted || (id != null && seedMatchedExistingIds.contains(id))) {
          continue;
        }

        await txn.update(
          'employees',
          {
            'is_deleted': 1,
            'deleted_at': now,
            'updated_at': now,
            'synced_at': null,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }

      await _markMigrationComplete(
        txn,
        _employeeSeedMasterReplacementMigrationKey,
        now,
      );
    });

    return true;
  }

  /// Updates basic_charges and other_charges for existing employees that have
  /// 0 values, by matching against the seed data via PF number or UAN number.
  /// This fixes DBs created before charges were stored in the seed.
  Future<void> _backfillEmployeeCharges(Database db) async {
    for (final seed in kEmployeeSeedData) {
      final basic = (seed['basic_charges'] as num?)?.toDouble() ?? 0;
      final other = (seed['other_charges'] as num?)?.toDouble() ?? 0;
      if (basic == 0 && other == 0) continue;

      final gross = basic + other;
      final pfNo  = (seed['pf_no']  as String? ?? '').trim();
      final uanNo = (seed['uan_no'] as String? ?? '').trim();

      // Match by PF number (skip incomplete ones like 'MH/212395/' with no suffix)
      if (pfNo.isNotEmpty && !pfNo.endsWith('/') && pfNo.length > 12) {
        await db.rawUpdate(
          'UPDATE employees SET basic_charges=?, other_charges=?, gross_salary=? '
          'WHERE pf_no=? AND (basic_charges IS NULL OR basic_charges=0)',
          [basic, other, gross, pfNo],
        );
      }

      // Match by UAN number as fallback
      if (uanNo.isNotEmpty) {
        await db.rawUpdate(
          'UPDATE employees SET basic_charges=?, other_charges=?, gross_salary=? '
          'WHERE uan_no=? AND (basic_charges IS NULL OR basic_charges=0)',
          [basic, other, gross, uanNo],
        );
      }
    }
  }

  DateTime _parseUtcDateTime(String? value) {
    if (value == null || value.isEmpty) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    try {
      return DateTime.parse(value).toUtc();
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
  }

  Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    final exists = cols.any((c) => c['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  Future<void> _ensureUniqueIndex(
    Database db,
    String indexName,
    String table,
    String column,
  ) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS $indexName ON $table($column)',
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS employees(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sr_no INTEGER, name TEXT, pf_no TEXT, uan_no TEXT, code TEXT,
      ifsc_code TEXT, account_number TEXT, aarti_ac_no TEXT, sb_code TEXT,
      bank_details TEXT, branch TEXT, zone TEXT, date_of_joining TEXT,
      basic_charges REAL DEFAULT 0,
      other_charges REAL DEFAULT 0,
      gross_salary REAL DEFAULT 0,
      gender TEXT DEFAULT 'M',
      cloud_id TEXT UNIQUE,
      is_deleted INTEGER DEFAULT 0,
      deleted_at TEXT,
      synced_at TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP)''');

    await db.execute(
      '''CREATE TABLE IF NOT EXISTS company_config(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_name TEXT, address TEXT, gstin TEXT, pan TEXT,
      jurisdiction TEXT, declaration_text TEXT,
      bank_name TEXT, branch TEXT, account_no TEXT, ifsc_code TEXT, phone TEXT)''',
    );

    await db.execute('''CREATE TABLE IF NOT EXISTS vouchers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT, description TEXT, dept_code TEXT,
      bill_no TEXT, po_no TEXT, item_description TEXT,
      client_name TEXT, client_address TEXT, client_gstin TEXT,
      base_total REAL, cgst REAL, sgst REAL, total_tax REAL,
      raw_total REAL, round_off REAL, final_total REAL, total_in_words TEXT,
      status TEXT DEFAULT 'draft',
      cloud_id TEXT UNIQUE,
      created_by TEXT,
      updated_by TEXT,
      is_deleted INTEGER DEFAULT 0,
      deleted_at TEXT,
      synced_at TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS voucher_rows(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      voucher_id INTEGER, employee_name TEXT, amount REAL,
      from_date TEXT, to_date TEXT, ifsc_code TEXT, credit_account TEXT,
      sb_code TEXT, bank_detail TEXT, place TEXT, dept_code TEXT,
      debit_account TEXT, debit_account_name TEXT,
      FOREIGN KEY(voucher_id) REFERENCES vouchers(id) ON DELETE CASCADE)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS voucher_draft(
      id INTEGER PRIMARY KEY CHECK (id = 1),
      title TEXT, dept_code TEXT, date TEXT,
      bill_no TEXT, po_no TEXT, item_description TEXT,
      client_name TEXT, client_address TEXT, client_gstin TEXT,
      base_total REAL, cgst REAL, sgst REAL, total_tax REAL,
      round_off REAL, final_total REAL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS voucher_draft_rows(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      employee_id TEXT, employee_name TEXT, amount REAL,
      from_date TEXT, to_date TEXT, ifsc_code TEXT,
      credit_account TEXT, sb_code TEXT, bank_detail TEXT,
      place TEXT, dept_code TEXT,
      debit_account TEXT, debit_account_name TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS pdf_settings(
      id INTEGER PRIMARY KEY CHECK (id = 1),
      margin_top REAL DEFAULT 24,
      margin_bottom REAL DEFAULT 24,
      margin_left REAL DEFAULT 24,
      margin_right REAL DEFAULT 24,
      voucher_col_widths TEXT,
      bank_col_widths TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS users(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      full_name TEXT,
      first_name TEXT,
      last_name TEXT,
      username TEXT,
      email TEXT UNIQUE,
      phone TEXT,
      alt_email TEXT,
      dob TEXT,
      gender TEXT,
      pronouns TEXT,
      avatar_path TEXT,
      auth_provider TEXT DEFAULT 'manual',
      password_hash TEXT,
      created_at TEXT
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS item_descriptions(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      text TEXT NOT NULL,
      is_custom INTEGER DEFAULT 0
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS auth_session(
      id INTEGER PRIMARY KEY CHECK (id = 1),
      user_id INTEGER,
      FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS sync_pending(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      cloud_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload TEXT NOT NULL,
      local_updated_at TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )''');

    await db.execute('''CREATE TABLE IF NOT EXISTS app_migrations(
      key TEXT PRIMARY KEY,
      completed_at TEXT NOT NULL
    )''');
  }

  Future<void> _seedCompanyConfig(Database db) async {
    final rows = await db.query('company_config', columns: ['id'], limit: 1);
    if (rows.isEmpty) {
      await db.insert('company_config', {
        'company_name': 'AARTI ENTERPRISES',
        'address':
            'Dahisar Preeti Co-op Hsg. Soc., Shop No. 5, Opp. Janseva Bank, Maratha Colony, W. S. Road, Dahisar (E), Mumbai - 400 068.',
        'gstin': '27AAQFA5248L2ZW',
        'pan': 'AAQFA5248L',
        'jurisdiction': 'Mumbai',
        'declaration_text':
            'Certified that particulars given above are true and correct.',
        'bank_name': 'IDBI Bank Ltd.',
        'branch': 'Dahisar - East',
        'account_no': '0680651100000338',
        'ifsc_code': 'IBKL0000680',
        'phone': '28282906',
      });
    }

    final descRows = await db.query(
      'item_descriptions',
      columns: ['id'],
      limit: 1,
    );
    if (descRows.isEmpty) {
      for (final d in [
        'Local and outstation travelling expenses with daily allowance including mobile expenses and material.',
        'Service Charges for the month of',
        'Manpower Supply Charges',
        'Maintenance Services',
        'Consultancy Fees',
      ]) {
        await db.insert('item_descriptions', {'text': d, 'is_custom': 0});
      }
    }

    // Keep the old safety seed only until the one-time master replacement has
    // run. After that migration, user/Drive edits must not be overwritten or
    // reinserted from the seed on future launches.
    final seedMasterReplacementComplete = await _isMigrationComplete(
      db,
      _employeeSeedMasterReplacementMigrationKey,
    );
    if (!seedMasterReplacementComplete) {
      await _ensureSeedEmployees(db);
    }
  }

  // ── New sync helpers ──────────────────────────────────────────────────────

  /// Called by SyncManager bootstrap to stamp a cloud_id onto a local employee
  /// that was created before sync was set up.
  Future<void> assignCloudId(int localId, String cloudId, String now) async {
    await (await database).update(
      'employees',
      {
        'cloud_id': cloudId,
        'updated_at': now,
        'created_at': now, // safe: only runs when created_at may be null
        'synced_at': now,
      },
      where: 'id = ? AND (cloud_id IS NULL OR cloud_id = "")',
      whereArgs: [localId],
    );
  }

  /// Called by SyncManager pull: marks a local employee deleted when the Drive
  /// index says it has been soft-deleted on another device.
  Future<void> softDeleteByCloudId(String cloudId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (await database).update(
      'employees',
      {
        'is_deleted': 1,
        'deleted_at': now,
        'updated_at': now,
      },
      where: 'cloud_id = ? AND is_deleted = 0',
      whereArgs: [cloudId],
    );
  }

  Future<Map<String, dynamic>?> getEmployeeById(int id) async {
    final rows = await (await database).query(
      'employees',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ── Employees ─────────────────────────────────────────────────────────────

  Future<int> insertEmployee(Map<String, dynamic> data) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    final normalized = _normalizeEmployeeData(data);
    normalized['created_at'] ??= now;
    normalized['updated_at'] = now;

    final id = await db.insert('employees', normalized);

    // Enqueue sync if the row already has a cloud_id (e.g. restored from Drive)
    final cloudId = normalized['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty) {
      final inserted = await getEmployeeById(id);
      if (inserted != null) {
        await SyncManager.instance.pushEmployeeChange(
          cloudId: cloudId,
          operation: 'create',
          employeeDbRow: inserted,
        );
      }
    }
    // If cloud_id is absent the bootstrap will assign one on next startup sync.

    return id;
  }

  Future<void> insertEmployeesBulk(List<EmployeeModel> employees) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final e in employees) {
        await txn.insert(
          'employees',
          _normalizeEmployeeData(e.toMap()),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async =>
      (await database).query(
        'employees',
        where: 'is_deleted = 0 OR is_deleted IS NULL',
        orderBy: 'sr_no ASC',
      );

  /// Returns all active employees that already have a cloud_id.
  /// Used by [SyncManager._enqueueAllEmployeesForPush] to re-push every
  /// record to Drive on every app launch.
  Future<List<Map<String, dynamic>>> getAllSyncedEmployees() async =>
      (await database).query(
        'employees',
        where:
            '(is_deleted = 0 OR is_deleted IS NULL) AND cloud_id IS NOT NULL AND cloud_id != ""',
        orderBy: 'sr_no ASC',
      );

  Future<List<Map<String, dynamic>>> getDeletedSyncedEmployees() async =>
      (await database).query(
        'employees',
        where: 'is_deleted = 1 AND cloud_id IS NOT NULL AND cloud_id != ""',
        orderBy: 'updated_at ASC',
      );

  Future<List<Map<String, dynamic>>> searchEmployees(String q) async =>
      (await database).query(
        'employees',
        where: 'name LIKE ? OR pf_no LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
      );

  Future<int> updateEmployee(int id, Map<String, dynamic> data) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    final normalized = _normalizeEmployeeData(data);
    normalized['updated_at'] = now;

    final affected =
        await db.update('employees', normalized, where: 'id=?', whereArgs: [id]);

    // Fetch the updated row to get cloud_id (may have been set by a prior sync)
    final updated = await getEmployeeById(id);
    final cloudId = updated?['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty && updated != null) {
      await SyncManager.instance.pushEmployeeChange(
        cloudId: cloudId,
        operation: 'update',
        employeeDbRow: updated,
      );
    }

    return affected;
  }

  Future<int> deleteEmployee(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();

    final row = await getEmployeeById(id);
    if (row == null) return 0;

    final affected = await db.update(
      'employees',
      {'is_deleted': 1, 'deleted_at': now, 'updated_at': now},
      where: 'id=?',
      whereArgs: [id],
    );

    final cloudId = row['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty) {
      // Re-fetch to get the tombstone values
      final tombstone = await getEmployeeById(id);
      if (tombstone != null) {
        await SyncManager.instance.pushEmployeeChange(
          cloudId: cloudId,
          operation: 'delete',
          employeeDbRow: tombstone,
        );
      }
    }

    return affected;
  }

  // --- Vouchers ---
  String get _currentGoogleEmail =>
      GoogleAuthService.instance.userEmail?.trim().toLowerCase() ?? 'unknown';

  Future<int> insertVoucher(Map<String, dynamic> data) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = Map<String, dynamic>.from(data);
    payload['created_at'] ??= now;
    payload['updated_at'] = payload['updated_at'] ?? now;
    payload['created_by'] ??= _currentGoogleEmail;
    payload['updated_by'] ??= _currentGoogleEmail;
    payload['is_deleted'] ??= 0;
    return db.insert('vouchers', payload);
  }

  Future<Map<String, dynamic>?> getVoucherById(int id) async {
    final rows = await (await database).query(
      'vouchers',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> updateVoucherWithRows(
    int voucherId,
    Map<String, dynamic> voucherData,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final payload = Map<String, dynamic>.from(voucherData)
      ..remove('id')
      ..['updated_at'] = now
      ..['updated_by'] = _currentGoogleEmail;

    await db.transaction((txn) async {
      final updated = await txn.update(
        'vouchers',
        payload,
        where: 'id=?',
        whereArgs: [voucherId],
      );
      if (updated == 0) {
        throw StateError('Voucher $voucherId not found');
      }

      await txn.delete(
        'voucher_rows',
        where: 'voucher_id=?',
        whereArgs: [voucherId],
      );

      for (final row in rows) {
        await txn.insert('voucher_rows', row);
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllVouchers() async =>
      (await database).query(
        'vouchers',
        where: 'is_deleted = 0 OR is_deleted IS NULL',
        orderBy: 'id DESC',
      );

  Future<List<Map<String, dynamic>>> getAllSyncedVouchers() async =>
      (await database).query(
        'vouchers',
        where:
            '(is_deleted = 0 OR is_deleted IS NULL) AND cloud_id IS NOT NULL AND cloud_id != ""',
        orderBy: 'id DESC',
      );

  Future<int> insertVoucherRow(Map<String, dynamic> data) async =>
      (await database).insert('voucher_rows', data);

  Future<List<Map<String, dynamic>>> getRowsByVoucherId(int id) async =>
      (await database).query(
        'voucher_rows',
        where: 'voucher_id=?',
        whereArgs: [id],
      );

  Future<void> deleteVoucherRows(int voucherId) async => (await database)
      .delete('voucher_rows', where: 'voucher_id=?', whereArgs: [voucherId]);

  Future<void> deleteVoucher(int id) async {
    final db = await database;
    final now = DateTime.now().toUtc().toIso8601String();
    final row = await getVoucherById(id);
    if (row == null) return;
    await db.update(
      'vouchers',
      {
        'is_deleted': 1,
        'deleted_at': now,
        'updated_at': now,
        'updated_by': _currentGoogleEmail,
      },
      where: 'id=?',
      whereArgs: [id],
    );

    final cloudId = row['cloud_id'] as String?;
    if (cloudId != null && cloudId.isNotEmpty) {
      final tombstone = await getVoucherById(id);
      if (tombstone != null) {
        await SyncManager.instance.pushInvoiceChange(
          cloudId: cloudId,
          operation: 'delete',
          invoiceDbRow: tombstone,
        );
      }
    }
  }

  Future<void> assignVoucherCloudId(
    int localId,
    String cloudId,
    String now,
    String createdBy,
    String updatedBy,
  ) async {
    await (await database).rawUpdate('''
      UPDATE vouchers
      SET cloud_id = ?,
          created_by = CASE
            WHEN created_by IS NULL OR TRIM(created_by) = '' THEN ?
            ELSE created_by
          END,
          updated_by = CASE
            WHEN updated_by IS NULL OR TRIM(updated_by) = '' THEN ?
            ELSE updated_by
          END,
          created_at = CASE
            WHEN created_at IS NULL OR TRIM(created_at) = '' THEN ?
            ELSE created_at
          END,
          updated_at = ?,
          synced_at = ?
      WHERE id = ? AND (cloud_id IS NULL OR cloud_id = '')
    ''', [cloudId, createdBy, updatedBy, now, now, now, localId]);
  }

  Future<void> softDeleteVoucherByCloudId(String cloudId) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await (await database).update(
      'vouchers',
      {
        'is_deleted': 1,
        'deleted_at': now,
        'updated_at': now,
      },
      where: 'cloud_id = ? AND is_deleted = 0',
      whereArgs: [cloudId],
    );
  }

  Future<void> saveDraft(
    Map<String, dynamic> header,
    List<Map<String, dynamic>> rows,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert(
        'voucher_draft',
        header,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete('voucher_draft_rows');
      for (final row in rows) {
        await txn.insert('voucher_draft_rows', row);
      }
    });
  }

  Future<Map<String, dynamic>?> getDraftHeader() async {
    final rows = await (await database).query(
      'voucher_draft',
      where: 'id=1',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> getDraftRows() async =>
      (await database).query('voucher_draft_rows');

  Future<void> clearDraft() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('voucher_draft');
      await txn.delete('voucher_draft_rows');
    });
  }

  // --- Company Config ---
  Future<Map<String, dynamic>?> getCompanyConfig() async {
    final rows = await (await database).query('company_config', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveCompanyConfig(Map<String, dynamic> data) async {
    final db = await database;
    final existing = await db.query(
      'company_config',
      columns: ['id'],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('company_config', data);
    } else {
      await db.update(
        'company_config',
        data,
        where: 'id=?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  // --- PDF / margin settings ---
  Future<MarginSettings> getMarginSettings() async {
    final rows = await (await database).query(
      'pdf_settings',
      where: 'id=1',
      limit: 1,
    );
    if (rows.isEmpty) return const MarginSettings();
    return MarginSettings.fromMap(rows.first);
  }

  Future<void> saveMarginSettings(MarginSettings s) async {
    final db = await database;
    await _ensurePdfSettingsRow(db);
    await db.update('pdf_settings', s.toMap(), where: 'id=1');
  }

  // --- Voucher Column Widths ---
  Future<VoucherColumnWidthsSettings> getVoucherColumnWidths() async {
    final rows = await (await database).query(
      'pdf_settings',
      where: 'id=1',
      limit: 1,
    );
    if (rows.isEmpty) return const VoucherColumnWidthsSettings();
    final json = rows.first['voucher_col_widths'] as String?;
    if (json == null || json.isEmpty) return const VoucherColumnWidthsSettings();
    return VoucherColumnWidthsSettings.fromJson(json);
  }

  Future<void> saveVoucherColumnWidths(VoucherColumnWidthsSettings s) async {
    final db = await database;
    await _ensurePdfSettingsRow(db);
    await db.update('pdf_settings', {'voucher_col_widths': s.toJson()}, where: 'id=1');
  }

  // --- Bank Column Widths ---
  Future<BankColumnWidthsSettings> getBankColumnWidths() async {
    final rows = await (await database).query(
      'pdf_settings',
      where: 'id=1',
      limit: 1,
    );
    if (rows.isEmpty) return const BankColumnWidthsSettings();
    final json = rows.first['bank_col_widths'] as String?;
    if (json == null || json.isEmpty) return const BankColumnWidthsSettings();
    return BankColumnWidthsSettings.fromJson(json);
  }

  Future<void> saveBankColumnWidths(BankColumnWidthsSettings s) async {
    final db = await database;
    await _ensurePdfSettingsRow(db);
    await db.update('pdf_settings', {'bank_col_widths': s.toJson()}, where: 'id=1');
  }

  Future<void> _ensurePdfSettingsRow(Database db) async {
    final rows = await db.query('pdf_settings', where: 'id=1', limit: 1);
    if (rows.isEmpty) await db.insert('pdf_settings', {'id': 1});
  }

  // --- Item Descriptions ---
  Future<List<Map<String, dynamic>>> getItemDescriptions() async =>
      (await database).query('item_descriptions', orderBy: 'id ASC');

  Future<int> insertItemDescription(String text) async => (await database)
      .insert('item_descriptions', {'text': text, 'is_custom': 1});

  Future<void> deleteItemDescription(int id) async => (await database).delete(
    'item_descriptions',
    where: 'id=?',
    whereArgs: [id],
  );

  // --- Users / Auth ---
  Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final rows = await (await database).query(
      'users',
      where: 'LOWER(email)=?',
      whereArgs: [email.trim().toLowerCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getUserById(int id) async {
    final rows = await (await database).query(
      'users',
      where: 'id=?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> insertUser(Map<String, dynamic> data) async =>
      (await database).insert('users', data);

  Future<int> updateUser(int id, Map<String, dynamic> data) async =>
      (await database).update('users', data, where: 'id=?', whereArgs: [id]);

  Future<int?> getSessionUserId() async {
    final rows = await (await database).query(
      'auth_session',
      where: 'id=1',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['user_id'] as int?;
  }

  Future<void> setSessionUserId(int? userId) async {
    final db = await database;
    if (userId == null) {
      await db.delete('auth_session', where: 'id=1');
      return;
    }
    await db.insert('auth_session', {
      'id': 1,
      'user_id': userId,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- Sync Methods ---
  Future<int> addPendingSync(SyncPendingEntry entry) async {
    return (await database).insert('sync_pending', {
      'entity_type': entry.entityType,
      'cloud_id': entry.cloudId,
      'operation': entry.operation,
      'payload': jsonEncode(entry.payload),
      'local_updated_at': entry.localUpdatedAt,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncs() async {
    return (await database).query(
      'sync_pending',
      orderBy: 'created_at ASC',
    );
  }

  Future<int> removePendingSync(int id) async {
    return (await database).delete(
      'sync_pending',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<Map<String, dynamic>?> getEmployeeByCloudId(String cloudId) async {
    final rows = await (await database).query(
      'employees',
      where: 'cloud_id=?',
      whereArgs: [cloudId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> getVoucherByCloudId(String cloudId) async {
    final rows = await (await database).query(
      'vouchers',
      where: 'cloud_id=?',
      whereArgs: [cloudId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> upsertEmployeeFromCloud(Map<String, dynamic> data) async {
    final db = await database;
    final cloudId = data['cloud_id'] as String?;
    if (cloudId == null || cloudId.isEmpty) {
      return 0;
    }

    final existing = await getEmployeeByCloudId(cloudId);
    final cloudUpdatedAt = _parseUtcDateTime(data['updated_at'] as String?);
    final insertData = Map<String, dynamic>.from(data);
    insertData['created_at'] = (insertData['created_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    insertData['updated_at'] = (insertData['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();

    if (existing == null) {
      return await db.insert('employees', insertData);
    }

    final localUpdatedAt = _parseUtcDateTime(existing['updated_at'] as String?);
    if (cloudUpdatedAt.isAfter(localUpdatedAt)) {
      final normalized = _normalizeEmployeeData(insertData);
      normalized['updated_at'] = cloudUpdatedAt.toIso8601String();
      normalized['created_at'] =
          (normalized['created_at'] as String?) ??
              (existing['created_at'] as String?) ??
              DateTime.now().toUtc().toIso8601String();
      return await db.update(
        'employees',
        normalized,
        where: 'cloud_id=?',
        whereArgs: [cloudId],
      );
    }

    return 0;
  }

  Future<int> upsertVoucherFromCloud(Map<String, dynamic> data) async {
    final db = await database;
    final cloudId = data['cloud_id'] as String?;
    if (cloudId == null || cloudId.isEmpty) return 0;

    final rows = ((data['rows'] as List<dynamic>?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final header = Map<String, dynamic>.from(data)..remove('rows');
    header['is_deleted'] = _boolToInt(header['is_deleted']);
    header['created_at'] = (header['created_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    header['updated_at'] = (header['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();

    final existing = await getVoucherByCloudId(cloudId);
    final cloudUpdatedAt = _parseUtcDateTime(header['updated_at'] as String?);

    if (existing == null) {
      return await db.transaction((txn) async {
        final id = await txn.insert('vouchers', header);
        for (final row in rows) {
          await txn.insert('voucher_rows', _invoiceRowToDb(row, id));
        }
        return id;
      });
    }

    final localUpdatedAt = _parseUtcDateTime(existing['updated_at'] as String?);
    if (!cloudUpdatedAt.isAfter(localUpdatedAt)) return 0;

    final localId = existing['id'] as int;
    return await db.transaction((txn) async {
      await txn.update(
        'vouchers',
        header..remove('id'),
        where: 'cloud_id=?',
        whereArgs: [cloudId],
      );
      await txn.delete('voucher_rows', where: 'voucher_id=?', whereArgs: [localId]);
      for (final row in rows) {
        await txn.insert('voucher_rows', _invoiceRowToDb(row, localId));
      }
      return localId;
    });
  }

  int _boolToInt(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toInt() == 0 ? 0 : 1;
    if (value is String) return value == 'true' || value == '1' ? 1 : 0;
    return 0;
  }

  Map<String, dynamic> _invoiceRowToDb(Map<String, dynamic> row, int voucherId) => {
        'voucher_id': voucherId,
        'employee_id': row['employee_id']?.toString() ?? '',
        'employee_name': row['employee_name']?.toString() ?? '',
        'amount': (row['amount'] as num?)?.toDouble() ?? 0,
        'from_date': row['from_date']?.toString() ?? '',
        'to_date': row['to_date']?.toString() ?? '',
        'ifsc_code': row['ifsc_code']?.toString() ?? '',
        'credit_account': row['credit_account']?.toString() ?? '',
        'sb_code': row['sb_code']?.toString() ?? '10',
        'bank_detail': row['bank_detail']?.toString() ?? '',
        'place': row['place']?.toString() ?? '',
        'dept_code': row['dept_code']?.toString() ?? '',
        'debit_account': row['debit_account']?.toString() ?? '',
        'debit_account_name': row['debit_account_name']?.toString() ?? '',
      };
}
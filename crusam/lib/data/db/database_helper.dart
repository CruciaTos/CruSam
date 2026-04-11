import 'package:sqflite/sqflite.dart';
import '../models/employee_model.dart';
import '../models/margin_settings_model.dart';
import '../models/voucher_column_widths_model.dart';
import '../models/bank_column_widths_model.dart';
import '../seeds/employee_seed_data.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    final path = '${await getDatabasesPath()}/aarti.db';
    return openDatabase(
      path,
      version: 3,
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

    // Existing DBs may have older vouchers schema; ensure missing columns are added.
    await _ensureColumn(db, 'vouchers', 'bill_no', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'po_no', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'item_description', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_name', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_address', 'TEXT');
    await _ensureColumn(db, 'vouchers', 'client_gstin', 'TEXT');
    await _ensureColumn(db, 'voucher_rows', 'employee_id', 'TEXT');
    await _ensureColumn(db, 'employees', 'basic_charges', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'employees', 'other_charges', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'employees', 'gross_salary', 'REAL DEFAULT 0');
    await _ensureColumn(db, 'pdf_settings', 'voucher_col_widths', 'TEXT');
    await _ensureColumn(db, 'pdf_settings', 'bank_col_widths', 'TEXT');
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

  Future<void> _createTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS employees(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sr_no INTEGER, name TEXT, pf_no TEXT, uan_no TEXT, code TEXT,
      ifsc_code TEXT, account_number TEXT, aarti_ac_no TEXT, sb_code TEXT,
      bank_details TEXT, branch TEXT, zone TEXT, date_of_joining TEXT,
      basic_charges REAL DEFAULT 0,
      other_charges REAL DEFAULT 0,
      gross_salary REAL DEFAULT 0,
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

    // Seed employees once if table is empty
    final empRows = await db.query('employees', columns: ['id'], limit: 1);
    if (empRows.isEmpty) {
      final batch = db.batch();
      for (final e in kEmployeeSeedData) {
        batch.insert(
          'employees',
          e,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
    }
  }

  // --- Employees ---
  Future<int> insertEmployee(Map<String, dynamic> data) async =>
      (await database).insert('employees', data);

  Future<void> insertEmployeesBulk(List<EmployeeModel> employees) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final e in employees) {
        await txn.insert(
          'employees',
          e.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async =>
      (await database).query('employees', orderBy: 'sr_no ASC');

  Future<List<Map<String, dynamic>>> searchEmployees(String q) async =>
      (await database).query(
        'employees',
        where: 'name LIKE ? OR pf_no LIKE ?',
        whereArgs: ['%$q%', '%$q%'],
      );

  Future<int> updateEmployee(int id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    return (await database).update(
      'employees',
      data,
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<int> deleteEmployee(int id) async =>
      (await database).delete('employees', where: 'id=?', whereArgs: [id]);

  // --- Vouchers ---
  Future<int> insertVoucher(Map<String, dynamic> data) async =>
      (await database).insert('vouchers', data);

  Future<List<Map<String, dynamic>>> getAllVouchers() async =>
      (await database).query('vouchers', orderBy: 'id DESC');

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
    await db.delete('voucher_rows', where: 'voucher_id=?', whereArgs: [id]);
    await db.delete('vouchers', where: 'id=?', whereArgs: [id]);
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

  // --- Private helper for pdf_settings row ---
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
}
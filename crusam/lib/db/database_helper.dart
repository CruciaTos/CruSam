import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._internal();

  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  Future<Database> get database async {
    _database ??= await initDB();
    return _database!;
  }

  Future<Database> initDB() async {
    final databasesPath = await getDatabasesPath();
    final dbPath = '$databasesPath/crusam.db';

    _database = await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db, version);
        await _ensureCompanyConfigSeed(db);
      },
      onOpen: (db) async {
        await _createTables(db, 1);
        await _ensureCompanyConfigSeed(db);
      },
    );

    return _database!;
  }

  Future<void> _createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS employees (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sr_no INTEGER,
        name TEXT,
        pf_no TEXT,
        uan_no TEXT,
        code TEXT,
        ifsc_code TEXT,
        account_number TEXT,
        aarti_ac_no TEXT,
        sb_code TEXT,
        bank_details TEXT,
        branch TEXT,
        zone TEXT,
        date_of_joining TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS company_config (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT,
        address TEXT,
        gstin TEXT,
        pan TEXT,
        jurisdiction TEXT,
        declaration_text TEXT,
        bank_name TEXT,
        branch TEXT,
        account_no TEXT,
        ifsc_code TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        email TEXT,
        auth_type TEXT,
        password_hash TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS vouchers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        description TEXT,
        dept_code TEXT,
        base_total REAL,
        cgst REAL,
        sgst REAL,
        total_tax REAL,
        raw_total REAL,
        round_off REAL,
        final_total REAL,
        total_in_words TEXT,
        transfer_amount REAL,
        clearance_amount REAL,
        status TEXT,
        created_by INTEGER,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS voucher_rows (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_id INTEGER,
        employee_name TEXT,
        amount REAL,
        from_date TEXT,
        to_date TEXT,
        ifsc_code TEXT,
        credit_account TEXT,
        sb_code TEXT,
        bank_detail TEXT,
        place TEXT,
        dept_code TEXT,
        debit_account TEXT,
        debit_account_name TEXT,
        overridden INTEGER DEFAULT 0,
        FOREIGN KEY (voucher_id) REFERENCES vouchers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        voucher_id INTEGER,
        bill_no TEXT,
        date TEXT,
        po_no TEXT,
        item_description TEXT,
        base_amount REAL,
        cgst REAL,
        sgst REAL,
        total_tax REAL,
        round_off REAL,
        final_total REAL,
        amount_in_words TEXT,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (voucher_id) REFERENCES vouchers(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        voucher_id INTEGER,
        action TEXT,
        timestamp TEXT DEFAULT CURRENT_TIMESTAMP,
        notes TEXT
      )
    ''');
  }

  Future<void> _ensureCompanyConfigSeed(Database db) async {
    final existing = await db.query(
      'company_config',
      columns: ['id'],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('company_config', {
        'company_name': '',
        'address': '',
        'gstin': '',
        'pan': '',
        'jurisdiction': '',
        'declaration_text': '',
        'bank_name': '',
        'branch': '',
        'account_no': '',
        'ifsc_code': '',
      });
    }
  }

  Future<int> insertEmployee(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('employees', data);
  }

  Future<List<Map<String, dynamic>>> getAllEmployees() async {
    final db = await database;
    return db.query('employees', orderBy: 'id DESC');
  }

  Future<int> updateEmployee(int id, Map<String, dynamic> data) async {
    final db = await database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update(
      'employees',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteEmployee(int id) async {
    final db = await database;
    return db.delete(
      'employees',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> searchEmployeesByName(String query) async {
    final db = await database;
    return db.query(
      'employees',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
  }

  Future<int> insertVoucher(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('vouchers', data);
  }

  Future<int> insertVoucherRow(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('voucher_rows', data);
  }

  Future<Map<String, dynamic>?> getVoucherById(int id) async {
    final db = await database;
    final result = await db.query(
      'vouchers',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return result.first;
  }

  Future<List<Map<String, dynamic>>> getRowsByVoucherId(int id) async {
    final db = await database;
    return db.query(
      'voucher_rows',
      where: 'voucher_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
  }

  Future<int> updateVoucher(int id, Map<String, dynamic> data) async {
    final db = await database;
    data['updated_at'] = DateTime.now().toIso8601String();
    return db.update(
      'vouchers',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteVoucherRows(int voucherId) async {
    final db = await database;
    return db.delete(
      'voucher_rows',
      where: 'voucher_id = ?',
      whereArgs: [voucherId],
    );
  }

  Future<int> insertAuditLog(Map<String, dynamic> data) async {
    final db = await database;
    return db.insert('audit_log', data);
  }
}
import 'package:sqflite/sqflite.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final instance = DatabaseHelper._();
  static Database? _db;

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    final path = '${await getDatabasesPath()}/aarti.db';
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate:  (db, v) async { await _createTables(db); await _seedCompanyConfig(db); },
      onUpgrade: (db, old, v) async { await _createTables(db); },
      onOpen:    (db) async { await _createTables(db); await _seedCompanyConfig(db); },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS employees(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sr_no INTEGER, name TEXT, pf_no TEXT, uan_no TEXT, code TEXT,
      ifsc_code TEXT, account_number TEXT, aarti_ac_no TEXT, sb_code TEXT,
      bank_details TEXT, branch TEXT, zone TEXT, date_of_joining TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS company_config(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_name TEXT, address TEXT, gstin TEXT, pan TEXT,
      jurisdiction TEXT, declaration_text TEXT,
      bank_name TEXT, branch TEXT, account_no TEXT, ifsc_code TEXT, phone TEXT)''');

    await db.execute('''CREATE TABLE IF NOT EXISTS vouchers(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT, description TEXT, dept_code TEXT,
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
      FOREIGN KEY(voucher_id) REFERENCES vouchers(id))''');
  }

  Future<void> _seedCompanyConfig(Database db) async {
    final rows = await db.query('company_config', columns: ['id'], limit: 1);
    if (rows.isEmpty) {
      await db.insert('company_config', {
        'company_name': 'AARTI ENTERPRISES',
        'address': 'Dahisar Preeti Co-op Hsg. Soc., Shop No. 5, Opp. Janseva Bank, Maratha Colony, W. S. Road, Dahisar (E), Mumbai - 400 068.',
        'gstin': '27AAQFA5248L2ZW', 'pan': 'AAQFA5248L', 'jurisdiction': 'Mumbai',
        'declaration_text': 'Certified that particulars given above are true and correct.',
        'bank_name': 'IDBI Bank Ltd.', 'branch': 'Dahisar - East',
        'account_no': '0680651100000338', 'ifsc_code': 'IBKL0000680', 'phone': '28282906',
      });
    }
  }

  // --- Employees ---
  Future<int> insertEmployee(Map<String, dynamic> data) async =>
      (await database).insert('employees', data);

  Future<List<Map<String, dynamic>>> getAllEmployees() async =>
      (await database).query('employees', orderBy: 'sr_no ASC');

  Future<List<Map<String, dynamic>>> searchEmployees(String q) async =>
      (await database).query('employees',
          where: 'name LIKE ? OR pf_no LIKE ?', whereArgs: ['%$q%', '%$q%']);

  Future<int> updateEmployee(int id, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    return (await database).update('employees', data, where: 'id=?', whereArgs: [id]);
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
      (await database).query('voucher_rows', where: 'voucher_id=?', whereArgs: [id]);

  Future<void> deleteVoucherRows(int voucherId) async =>
      (await database).delete('voucher_rows', where: 'voucher_id=?', whereArgs: [voucherId]);

  // --- Company Config ---
  Future<Map<String, dynamic>?> getCompanyConfig() async {
    final rows = await (await database).query('company_config', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveCompanyConfig(Map<String, dynamic> data) async {
    final db = await database;
    final existing = await db.query('company_config', columns: ['id'], limit: 1);
    if (existing.isEmpty) {
      await db.insert('company_config', data);
    } else {
      await db.update('company_config', data,
          where: 'id=?', whereArgs: [existing.first['id']]);
    }
  }
}
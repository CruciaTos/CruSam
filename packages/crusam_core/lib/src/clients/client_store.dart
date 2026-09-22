// Clients (invoice recipients). Historically a client existed only as the
// four client_* text columns on each invoice; the `clients` table is a new,
// additive address book. Nothing in the existing schema references it.

import 'package:sqflite_common/sqlite_api.dart';

class ClientModel {
  final int? id;
  final String name;
  final String address;
  final String gstin;
  final String email;
  final String createdAt;
  final String updatedAt;

  const ClientModel({
    this.id,
    required this.name,
    this.address = '',
    this.gstin = '',
    this.email = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  factory ClientModel.fromDbMap(Map<String, Object?> m) => ClientModel(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        address: (m['address'] as String?) ?? '',
        gstin: (m['gstin'] as String?) ?? '',
        email: (m['email'] as String?) ?? '',
        createdAt: (m['created_at'] as String?) ?? '',
        updatedAt: (m['updated_at'] as String?) ?? '',
      );

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'name': name,
        'address': address,
        'gstin': gstin,
        'email': email,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

class ClientStore {
  ClientStore._();

  static const createTableSql = '''CREATE TABLE IF NOT EXISTS clients(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      address TEXT NOT NULL DEFAULT '',
      gstin TEXT NOT NULL DEFAULT '',
      email TEXT NOT NULL DEFAULT '',
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at TEXT,
      updated_at TEXT)''';

  static const createIndexSql =
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_name '
      'ON clients(name COLLATE NOCASE) WHERE is_deleted = 0';

  static Future<void> ensureTable(DatabaseExecutor db) async {
    await db.execute(createTableSql);
    await db.execute(createIndexSql);
  }

  static Future<List<ClientModel>> listSaved(DatabaseExecutor db) async {
    final rows = await db.query('clients',
        where: 'is_deleted = 0', orderBy: 'name COLLATE NOCASE');
    return rows.map(ClientModel.fromDbMap).toList();
  }

  static Future<ClientModel?> getById(DatabaseExecutor db, int id) async {
    final rows = await db.query('clients',
        where: 'id = ? AND is_deleted = 0', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ClientModel.fromDbMap(rows.first);
  }

  static Future<ClientModel?> getByName(DatabaseExecutor db, String name) async {
    final rows = await db.query('clients',
        where: 'LOWER(TRIM(name)) = ? AND is_deleted = 0',
        whereArgs: [name.trim().toLowerCase()],
        limit: 1);
    return rows.isEmpty ? null : ClientModel.fromDbMap(rows.first);
  }

  static Future<int> insert(DatabaseExecutor db, ClientModel c) =>
      db.insert('clients', c.toDbMap()..remove('id'));

  static Future<int> update(DatabaseExecutor db, int id, Map<String, Object?> fields) =>
      db.update('clients', fields, where: 'id = ? AND is_deleted = 0', whereArgs: [id]);

  static Future<bool> softDelete(DatabaseExecutor db, int id, String nowUtcIso) async =>
      await db.update('clients', {'is_deleted': 1, 'updated_at': nowUtcIso},
          where: 'id = ? AND is_deleted = 0', whereArgs: [id]) >
      0;

  /// Distinct clients that appear on past invoices (most recent details win),
  /// with how many invoices use them.
  static Future<List<(ClientModel, int)>> fromInvoices(DatabaseExecutor db) async {
    final rows = await db.rawQuery('''
      SELECT client_name, client_address, client_gstin, client_email,
             COUNT(*) AS n, MAX(created_at) AS last_used
      FROM vouchers
      WHERE (is_deleted = 0 OR is_deleted IS NULL)
        AND TRIM(COALESCE(client_name, '')) != ''
      GROUP BY LOWER(TRIM(client_name))
      ORDER BY last_used DESC''');
    return [
      for (final r in rows)
        (
          ClientModel(
            name: ((r['client_name'] as String?) ?? '').trim(),
            address: (r['client_address'] as String?) ?? '',
            gstin: (r['client_gstin'] as String?) ?? '',
            email: (r['client_email'] as String?) ?? '',
          ),
          r['n'] as int,
        ),
    ];
  }
}

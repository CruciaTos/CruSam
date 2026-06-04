// lib/data/db/migrations/salary_disbursement_migration.dart
//
// Adds two tables that track salary disbursement batches.
//
// salary_disbursements      — one record per disbursement batch/run
// salary_disbursement_items — one record per employee in a batch
//
// Add these to DatabaseHelper._onCreate / onUpgrade at the appropriate
// schema version.

class SalaryDisbursementMigration {
  static const String createSalaryDisbursements = '''
    CREATE TABLE IF NOT EXISTS salary_disbursements (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      month         INTEGER NOT NULL,
      year          INTEGER NOT NULL,
      dept_code     TEXT    NOT NULL DEFAULT 'All',
      status        TEXT    NOT NULL DEFAULT 'pending',
      generated_at  TEXT,
      exported_at   TEXT,
      created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
      updated_at    TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ''';

  static const String createSalaryDisbursementItems = '''
    CREATE TABLE IF NOT EXISTS salary_disbursement_items (
      id                    INTEGER PRIMARY KEY AUTOINCREMENT,
      disbursement_id       INTEGER NOT NULL REFERENCES salary_disbursements(id) ON DELETE CASCADE,
      employee_id           INTEGER NOT NULL,
      employee_name         TEXT    NOT NULL DEFAULT '',
      bank_name             TEXT    NOT NULL DEFAULT '',
      account_number        TEXT    NOT NULL DEFAULT '',
      ifsc_code             TEXT    NOT NULL DEFAULT '',
      amount                REAL    NOT NULL DEFAULT 0,
      sb_code               TEXT    NOT NULL DEFAULT '',
      branch                TEXT    NOT NULL DEFAULT '',
      salary_statement_id   INTEGER,
      status                TEXT    NOT NULL DEFAULT 'pending',
      created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ''';

  static const String createIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_sdisb_status ON salary_disbursements(status);
    CREATE INDEX IF NOT EXISTS idx_sdisb_month_year ON salary_disbursements(month, year);
    CREATE INDEX IF NOT EXISTS idx_sdisb_items_disbursement ON salary_disbursement_items(disbursement_id);
    CREATE INDEX IF NOT EXISTS idx_sdisb_items_employee ON salary_disbursement_items(employee_id)
  ''';

  // ── Add to DatabaseHelper.onUpgrade at version N ─────────────────────────
  static Future<void> migrate(dynamic db) async {
    await db.execute(createSalaryDisbursements);
    await db.execute(createSalaryDisbursementItems);
    for (final stmt
        in createIndexes.split(';').where((s) => s.trim().isNotEmpty)) {
      await db.execute('${stmt.trim()};');
    }
  }

  // ── Upgrade path for existing installs that have the old schema ───────────
  //
  // Call this in onUpgrade when migrating FROM a version that had the old
  // salary_disbursements table (with reference_no / disbursed_at columns).
  // SQLite does not support DROP COLUMN before version 3.35; the safest
  // approach is a table rename + recreate.
  static Future<void> migrateFromV1(dynamic db) async {
    // Rename old tables out of the way
    await db.execute(
        'ALTER TABLE salary_disbursements RENAME TO salary_disbursements_old');
    await db.execute(
        'ALTER TABLE salary_disbursement_items RENAME TO salary_disbursement_items_old');

    // Create fresh tables with the new schema
    await db.execute(createSalaryDisbursements);
    await db.execute(createSalaryDisbursementItems);

    // Copy rows — map old columns to new ones (drop reference_no, disbursed_at)
    await db.execute('''
      INSERT INTO salary_disbursements
        (id, month, year, dept_code, status, generated_at, exported_at,
         created_at, updated_at)
      SELECT
        id, month, year, dept_code, status, generated_at, exported_at,
        created_at, updated_at
      FROM salary_disbursements_old
    ''');

    await db.execute('''
      INSERT INTO salary_disbursement_items
        (id, disbursement_id, employee_id, employee_name, bank_name,
         account_number, ifsc_code, amount, sb_code, branch,
         salary_statement_id, status, created_at)
      SELECT
        id, disbursement_id, employee_id, employee_name, bank_name,
        account_number, ifsc_code, amount,
        COALESCE(sb_code, ''), COALESCE(branch, ''),
        salary_statement_id, status, created_at
      FROM salary_disbursement_items_old
    ''');

    // Drop old tables
    await db.execute('DROP TABLE salary_disbursement_items_old');
    await db.execute('DROP TABLE salary_disbursements_old');

    // Recreate indexes
    for (final stmt
        in createIndexes.split(';').where((s) => s.trim().isNotEmpty)) {
      await db.execute('${stmt.trim()};');
    }
  }
}
// lib/data/db/migrations/salary_disbursement_migration.dart
//
// Adds two tables that mirror the conceptual structure used by invoice
// disbursements (which are tracked via the vouchers table).
//
// salary_disbursements  — one record per disbursement batch/run
// salary_disbursement_items — one record per employee in a batch
//
// Add these to DatabaseHelper._onCreate / onUpgrade at the appropriate
// schema version.

class SalaryDisbursementMigration {
  static const String createSalaryDisbursements = '''
    CREATE TABLE IF NOT EXISTS salary_disbursements (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      reference_no  TEXT    NOT NULL DEFAULT '',
      month         INTEGER NOT NULL,
      year          INTEGER NOT NULL,
      dept_code     TEXT    NOT NULL DEFAULT 'All',
      status        TEXT    NOT NULL DEFAULT 'pending',
      generated_at  TEXT,
      exported_at   TEXT,
      disbursed_at  TEXT,
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
      salary_statement_id   INTEGER,
      status                TEXT    NOT NULL DEFAULT 'pending',
      created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
    )
  ''';

  static const String createIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_sdisb_status ON salary_disbursements(status);
    CREATE INDEX IF NOT EXISTS idx_sdisb_month_year ON salary_disbursements(month, year);
    CREATE INDEX IF NOT EXISTS idx_sdisb_items_disbursement ON salary_disbursement_items(disbursement_id);
    CREATE INDEX IF NOT EXISTS idx_sdisb_items_employee ON salary_disbursement_items(employee_id);
  ''';

  // ── Add to DatabaseHelper.onUpgrade at version N ─────────────────────────
  static Future<void> migrate(dynamic db) async {
    await db.execute(createSalaryDisbursements);
    await db.execute(createSalaryDisbursementItems);
    for (final stmt in createIndexes.split(';').where((s) => s.trim().isNotEmpty)) {
      await db.execute('${stmt.trim()};');
    }
  }
}
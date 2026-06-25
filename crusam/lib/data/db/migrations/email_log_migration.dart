// lib/data/db/migrations/email_log_migration.dart
//
// Tracks every email send attempt for any document the app generates.
// One generic table covers all phases — entity_type distinguishes them:
//   'invoice'           — Phase 1 (saved tax invoices)
//   'salary_slip'       — later phase
//   'bank_disbursement' — later phase
//   ...etc, as each output type gets wired up to Gmail sending.
//
// Add this to DatabaseHelper._createTables (table creation is idempotent
// via CREATE TABLE IF NOT EXISTS, matching the pattern used everywhere
// else in this file).

class EmailLogMigration {
  static const String createEmailLog = '''
    CREATE TABLE IF NOT EXISTS email_log (
      id               INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type      TEXT    NOT NULL,
      entity_id        INTEGER NOT NULL,
      recipient_to     TEXT    NOT NULL,
      recipient_cc     TEXT    NOT NULL DEFAULT '',
      subject          TEXT    NOT NULL,
      status           TEXT    NOT NULL DEFAULT 'pending',
      gmail_message_id TEXT,
      gmail_thread_id  TEXT,
      error_message    TEXT,
      sent_by          TEXT    NOT NULL DEFAULT '',
      attempted_at     TEXT    NOT NULL DEFAULT (datetime('now')),
      sent_at          TEXT
    )
  ''';

  static const String createIndexes = '''
    CREATE INDEX IF NOT EXISTS idx_email_log_entity ON email_log(entity_type, entity_id);
    CREATE INDEX IF NOT EXISTS idx_email_log_status ON email_log(status)
  ''';

  // ── Call from DatabaseHelper._createTables ───────────────────────────────
  static Future<void> migrate(dynamic db) async {
    await db.execute(createEmailLog);
    for (final stmt
        in createIndexes.split(';').where((s) => s.trim().isNotEmpty)) {
      await db.execute('${stmt.trim()};');
    }
  }
}

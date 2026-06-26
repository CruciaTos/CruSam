// lib/data/db/email_log_repository.dart
//
// Drop-in extension on DatabaseHelper, same convention as
// salary_disbursement_repository.dart. Covers every document type that
// gets wired up to Gmail sending — entity_type/entity_id distinguish them.

import 'database_helper.dart';
import '../models/email_log_model.dart';

extension EmailLogRepository on DatabaseHelper {
  // ── Create a pending row right before attempting a send ──────────────────
  // Insert first, then update to sent/failed — so even a crash mid-send
  // leaves a trace instead of silently losing the attempt.

  Future<int> insertEmailLog(EmailLogModel log) async {
    final db  = await database;
    final map = log.toDbMap()
      ..['attempted_at'] = DateTime.now().toIso8601String();
    return db.insert('email_log', map);
  }

  Future<void> markEmailSent({
    required int    id,
    required String gmailMessageId,
    String?         gmailThreadId,
  }) async {
    final db = await database;
    await db.update(
      'email_log',
      {
        'status':           EmailLogStatus.sent.name,
        'gmail_message_id': gmailMessageId,
        'gmail_thread_id':  gmailThreadId,
        'sent_at':          DateTime.now().toIso8601String(),
        'error_message':    null,
      },
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markEmailFailed({
    required int    id,
    required String errorMessage,
  }) async {
    final db = await database;
    await db.update(
      'email_log',
      {
        'status':        EmailLogStatus.failed.name,
        'error_message': errorMessage,
      },
      where:     'id = ?',
      whereArgs: [id],
    );
  }

  // ── History for a given document, most recent first ──────────────────────
  // e.g. getEmailLogsFor('invoice', voucher.id) to show "Sent ✓ to x on date"
  // and to detect "this was already sent — send again?" before a resend.

  Future<List<EmailLogModel>> getEmailLogsFor(
    String entityType,
    int    entityId,
  ) async {
    final db   = await database;
    final rows = await db.query(
      'email_log',
      where:     'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy:   'id DESC',
    );
    return rows.map(EmailLogModel.fromDbMap).toList();
  }

  Future<EmailLogModel?> getLatestSentEmailLogFor(
    String entityType,
    int    entityId,
  ) async {
    final db   = await database;
    final rows = await db.query(
      'email_log',
      where:     "entity_type = ? AND entity_id = ? AND status = 'sent'",
      whereArgs: [entityType, entityId],
      orderBy:   'id DESC',
      limit:     1,
    );
    return rows.isEmpty ? null : EmailLogModel.fromDbMap(rows.first);
  }

  // ── Batch version — latest 'sent' row per entity, for list views ─────────
  // e.g. show "Sent ✓ to x on date" on every invoice card in one query
  // instead of one query per card.

  Future<Map<int, EmailLogModel>> getLatestSentEmailLogsByType(
    String entityType,
  ) async {
    final db   = await database;
    final rows = await db.query(
      'email_log',
      where:     "entity_type = ? AND status = 'sent'",
      whereArgs: [entityType],
      orderBy:   'id DESC',
    );
    final result = <int, EmailLogModel>{};
    for (final row in rows) {
      final log = EmailLogModel.fromDbMap(row);
      // Rows are newest-first, so the first one seen per entity_id wins.
      result.putIfAbsent(log.entityId, () => log);
    }
    return result;
  }

  // ── Distinct prior recipients, most-recently-used first ───────────────────
  // Powers the "To" autocomplete dropdown in SendInvoiceDialog — every
  // address that's already been successfully emailed at least once for
  // [entityType], deduped, newest use first, capped at [limit].
  //
  // Dedupe happens in Dart rather than via SQL DISTINCT because SQLite
  // rejects "SELECT DISTINCT col ... ORDER BY id" when id isn't part of
  // the selected columns — ordering by recency needs id, so we fetch
  // ordered rows and dedupe by hand instead.

  Future<List<String>> getDistinctSentRecipientEmails({
    String entityType = 'invoice',
    int    limit = 25,
  }) async {
    final db   = await database;
    final rows = await db.query(
      'email_log',
      columns:   ['recipient_to'],
      where:     "entity_type = ? AND status = 'sent'",
      whereArgs: [entityType],
      orderBy:   'id DESC',
    );
    final seen = <String>{};
    final result = <String>[];
    for (final row in rows) {
      final email = ((row['recipient_to'] as String?) ?? '').trim();
      if (email.isEmpty || seen.contains(email)) continue;
      seen.add(email);
      result.add(email);
      if (result.length >= limit) break;
    }
    return result;
  }
}
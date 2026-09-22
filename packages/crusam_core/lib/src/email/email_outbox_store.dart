// Email outbox. The MCP server cannot send Gmail itself — the Gmail sign-in
// (token + OAuth client) lives inside the app — so Claude queues an email
// here and the running app sends it with its connected account, logging the
// attempt in email_log exactly like the Send dialogs do. New, additive
// table; nothing in the existing schema references it.
//
// Lifecycle: queued → sending → sent | failed; queued → cancelled.

import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

class OutboxStatus {
  OutboxStatus._();
  static const queued = 'queued';
  static const sending = 'sending';
  static const sent = 'sent';
  static const failed = 'failed';
  static const cancelled = 'cancelled';
  static const all = [queued, sending, sent, failed, cancelled];
}

class OutboxEmail {
  final int? id;
  final String entityType;
  final int entityId;
  final String to;
  final String cc;
  final String subject;
  final String body;

  /// Absolute paths of the files to attach (read when the email is sent).
  final List<String> attachments;
  final String status;
  final int? emailLogId;
  final String? errorMessage;
  final String requestedBy;
  final String createdAt;
  final String updatedAt;
  final String? sentAt;

  const OutboxEmail({
    this.id,
    required this.entityType,
    required this.entityId,
    required this.to,
    this.cc = '',
    required this.subject,
    required this.body,
    required this.attachments,
    this.status = OutboxStatus.queued,
    this.emailLogId,
    this.errorMessage,
    this.requestedBy = '',
    this.createdAt = '',
    this.updatedAt = '',
    this.sentAt,
  });

  factory OutboxEmail.fromDbMap(Map<String, Object?> m) => OutboxEmail(
        id: m['id'] as int?,
        entityType: (m['entity_type'] as String?) ?? '',
        entityId: (m['entity_id'] as int?) ?? 0,
        to: (m['recipient_to'] as String?) ?? '',
        cc: (m['recipient_cc'] as String?) ?? '',
        subject: (m['subject'] as String?) ?? '',
        body: (m['body'] as String?) ?? '',
        attachments: [
          for (final a in (jsonDecode((m['attachments'] as String?) ?? '[]') as List))
            '$a'
        ],
        status: (m['status'] as String?) ?? OutboxStatus.queued,
        emailLogId: m['email_log_id'] as int?,
        errorMessage: m['error_message'] as String?,
        requestedBy: (m['requested_by'] as String?) ?? '',
        createdAt: (m['created_at'] as String?) ?? '',
        updatedAt: (m['updated_at'] as String?) ?? '',
        sentAt: m['sent_at'] as String?,
      );

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'entity_type': entityType,
        'entity_id': entityId,
        'recipient_to': to,
        'recipient_cc': cc,
        'subject': subject,
        'body': body,
        'attachments': jsonEncode(attachments),
        'status': status,
        'email_log_id': emailLogId,
        'error_message': errorMessage,
        'requested_by': requestedBy,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'sent_at': sentAt,
      };

  /// email_log.attachment_formats value ("pdf", "excel" or "pdf,excel").
  String get attachmentFormats {
    final kinds = <String>{
      for (final a in attachments)
        a.toLowerCase().endsWith('.pdf') ? 'pdf' : 'excel',
    };
    return kinds.join(',');
  }
}

class EmailOutboxStore {
  EmailOutboxStore._();

  static const table = 'email_outbox';

  static const createTableSql = '''CREATE TABLE IF NOT EXISTS email_outbox(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL DEFAULT 0,
      recipient_to TEXT NOT NULL,
      recipient_cc TEXT NOT NULL DEFAULT '',
      subject TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '',
      attachments TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL DEFAULT 'queued',
      email_log_id INTEGER,
      error_message TEXT,
      requested_by TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sent_at TEXT)''';

  static Future<void> ensureTable(DatabaseExecutor db) async {
    await db.execute(createTableSql);
    await db.execute('CREATE INDEX IF NOT EXISTS idx_email_outbox_status '
        'ON email_outbox(status)');
  }

  static Future<int> insert(DatabaseExecutor db, OutboxEmail e) =>
      db.insert(table, e.toDbMap()..remove('id'));

  static Future<OutboxEmail?> getById(DatabaseExecutor db, int id) async {
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : OutboxEmail.fromDbMap(rows.first);
  }

  static Future<List<OutboxEmail>> list(DatabaseExecutor db,
      {String? status, int limit = 50}) async {
    final rows = await db.query(table,
        where: status == null ? null : 'status = ?',
        whereArgs: status == null ? null : [status],
        orderBy: 'id DESC',
        limit: limit);
    return rows.map(OutboxEmail.fromDbMap).toList();
  }

  /// Oldest queued emails first.
  static Future<List<OutboxEmail>> queued(DatabaseExecutor db) async {
    final rows = await db.query(table,
        where: 'status = ?', whereArgs: [OutboxStatus.queued], orderBy: 'id');
    return rows.map(OutboxEmail.fromDbMap).toList();
  }

  /// Moves [id] from [from] to [to] only if it is still in [from]. Returns
  /// false when another process got there first — the guard that keeps an
  /// email from being sent twice or cancelled mid-send.
  static Future<bool> transition(DatabaseExecutor db, int id, String from,
      String to, String now,
      {int? emailLogId, String? error, String? sentAt}) async {
    final n = await db.update(
      table,
      {
        'status': to,
        'updated_at': now,
        if (emailLogId != null) 'email_log_id': emailLogId,
        if (error != null) 'error_message': error,
        if (sentAt != null) 'sent_at': sentAt,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [id, from],
    );
    return n == 1;
  }

  /// Emails stuck in `sending` (the app closed mid-send) are marked failed —
  /// never re-sent automatically, because Gmail may already have sent them.
  static Future<int> failInterrupted(DatabaseExecutor db, String now) =>
      db.update(
        table,
        {
          'status': OutboxStatus.failed,
          'updated_at': now,
          'error_message': 'Interrupted while sending (the app closed). Check '
              'the Gmail Sent folder before queueing it again.',
        },
        where: 'status = ?',
        whereArgs: [OutboxStatus.sending],
      );
}

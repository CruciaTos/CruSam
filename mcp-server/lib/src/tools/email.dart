import 'dart:io';

import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';
import 'package:path/path.dart' as p;

import '../context.dart';
import '../db.dart';
import '../tool_kit.dart';

/// Sending email. The server never talks to Gmail: it queues the email in
/// the `email_outbox` table and the CruSam app — while open and connected to
/// Gmail in Profile — sends it and records the result in the email log.
class EmailTools extends ToolGroup {
  final ToolContext ctx;
  EmailTools(this.ctx);

  @override
  List<ToolDef> get tools => [_queue, _outbox, _cancel];

  /// entity_type values, as the app's Send dialogs log them, and what
  /// entity_id means for each.
  static const _entityTypes = {
    'invoice': 'invoice id',
    'salary_slip': 'saved salary month id',
    'salary_bill_export': 'saved salary month id',
    'salary_bill_final': 'saved salary month id',
    'salary_statement': 'saved salary month id',
    'salary_disbursement': 'disbursement batch id',
    'other': '0',
  };

  static const _maxAttachmentBytes = 20 * 1024 * 1024;
  static final _emailRe = RegExp(r'^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$');

  late final _queue = ToolDef(
    Tool(
      name: 'send_email',
      description: 'Email files (from the export_* tools) through the Gmail '
          'account connected in the CruSam app. The email is queued and the '
          'app sends it within about 30 seconds while it is open and '
          'connected to Gmail (Profile); follow up with list_email_outbox. '
          'For invoices, subject/body default to the app\'s wording and "to" '
          'to the invoice\'s client email. Show the user recipients, subject, '
          'body and attachments and get explicit approval before calling. '
          'Refuses if the same document was already emailed unless '
          'allow_resend=true.',
      annotations: writeTool('Send email', idempotent: false),
      inputSchema: Schema.object(properties: {
        'entity_type': Schema.string(
            description: 'What is being sent: ${_entityTypes.entries.map((e) => '${e.key} (entity_id = ${e.value})').join(', ')}.'),
        'entity_id': Schema.int(description: 'See entity_type.'),
        'to': Schema.string(description: 'Recipient address(es), comma-separated.'),
        'cc': Schema.string(description: 'Optional CC address(es), comma-separated.'),
        'subject': Schema.string(),
        'body': Schema.string(description: 'Plain-text body.'),
        'attachment_paths': Schema.list(
            items: Schema.string(),
            description: 'Absolute paths of .pdf / .xlsx files, usually the '
                '"path" values returned by the export tools.'),
        'allow_resend': Schema.bool(description: 'Send even if already emailed.'),
        'confirm': confirmSchema(),
      }, required: ['entity_type', 'attachment_paths', 'confirm']),
    ),
    (a) async {
      a.rejectUnknown(['entity_type', 'entity_id', 'to', 'cc', 'subject', 'body',
          'attachment_paths', 'allow_resend', 'confirm']);
      final type = a.oneOf('entity_type', _entityTypes.keys.toList(), required: true);
      final entityId = a.integer('entity_id', min: 0) ?? 0;
      var to = a.str('to', maxLength: 2000);
      final cc = a.str('cc', maxLength: 2000) ?? '';
      var subject = a.str('subject', maxLength: 500);
      var body = a.str('body', allowEmpty: true, maxLength: 20000);
      final paths = a.strings('attachment_paths', required: true, minItems: 1, maxItems: 10);
      final allowResend = a.boolean('allow_resend');
      if (a.raw['confirm'] != true) {
        a.errors.add('confirm: must be true to send an email. Show the user the '
            'recipients, subject, body and attachments and get their approval first.');
      }
      if (type != null && type != 'other' && entityId == 0) {
        a.errors.add('entity_id: required for entity_type $type (${_entityTypes[type]}).');
      }
      a.check();

      // Invoice defaults — the same text the app's Send Invoice dialog fills in.
      if (type == 'invoice') {
        final v = await VoucherStore.getById(ctx.db, entityId);
        if (v == null) throw ToolError('No (non-deleted) invoice with id $entityId.');
        final company = (await ctx.companyConfig(ctx.db)).companyName;
        to ??= v.clientEmail.trim().isEmpty ? null : v.clientEmail.trim();
        subject ??= 'Tax Invoice${v.billNo.isNotEmpty ? ' ${v.billNo}' : ''} — $company';
        body ??= 'Dear Sir,\n\n'
            'Please find attached the tax invoice'
            '${v.billNo.isNotEmpty ? ' (Bill No. ${v.billNo})' : ''} '
            'for an amount of Rs. ${v.finalTotal.toStringAsFixed(2)}.\n\n'
            'Regards,\nBharat Boridkar';
      }

      final problems = <String>[];
      if (to == null || to.trim().isEmpty) {
        problems.add('to: required (the invoice has no client email).');
      } else {
        problems.addAll(_badAddresses('to', to));
      }
      problems.addAll(_badAddresses('cc', cc));
      if (subject == null || subject.trim().isEmpty) problems.add('subject: required.');
      if (body == null) problems.add('body: required.');

      final files = <String>[];
      var total = 0;
      for (final raw in paths!) {
        final path = p.normalize(raw.trim());
        final ext = p.extension(path).toLowerCase();
        if (!p.isAbsolute(path)) {
          problems.add('attachment_paths: "$raw" is not an absolute path.');
        } else if (ext != '.pdf' && ext != '.xlsx') {
          problems.add('attachment_paths: "$raw" — only .pdf and .xlsx files can be sent.');
        } else if (!File(path).existsSync()) {
          problems.add('attachment_paths: "$raw" does not exist.');
        } else {
          total += File(path).lengthSync();
          files.add(path);
        }
      }
      if (total > _maxAttachmentBytes) {
        problems.add('attachment_paths: attachments total '
            '${(total / 1024 / 1024).toStringAsFixed(1)} MB; Gmail allows about 20 MB.');
      }
      if (problems.isNotEmpty) throw ToolError(problems.join('\n'));

      if (!allowResend && type != 'other') {
        final prior = await _priorSend(type!, entityId);
        if (prior != null) {
          throw ToolError('This $type was already emailed to '
              '${prior['recipient_to']} on ${prior['sent_at'] ?? prior['attempted_at']}'
              '${prior['source'] == 'outbox' ? ' (still queued)' : ''}. Ask the '
              'user; resend only with allow_resend=true.');
        }
      }

      final now = ctx.nowUtcIso();
      final email = OutboxEmail(
        entityType: type!,
        entityId: entityId,
        to: to!.trim(),
        cc: cc.trim(),
        subject: subject!.trim(),
        body: body!,
        attachments: files,
        requestedBy: 'Claude${ctx.userEmail.isEmpty ? '' : ' (${ctx.userEmail})'}',
        createdAt: now,
        updatedAt: now,
      );
      final id = await ctx.store.write((txn) async {
        await EmailOutboxStore.ensureTable(txn);
        return EmailOutboxStore.insert(txn, email);
      });
      return {
        'outbox_id': id,
        'status': OutboxStatus.queued,
        'to': email.to,
        if (email.cc.isNotEmpty) 'cc': email.cc,
        'subject': email.subject,
        'attachments': [for (final f in files) p.basename(f)],
        'note': 'Queued. The CruSam app sends it within ~30 s while it is open '
            'and connected to Gmail (Profile). Check with list_email_outbox.',
      };
    },
  );

  late final _outbox = ToolDef(
    Tool(
      name: 'list_email_outbox',
      description: 'Emails queued with send_email, newest first, with status '
          '(queued / sending / sent / failed / cancelled) and any error. An '
          'email stays "queued" until the app is open and connected to Gmail.',
      annotations: readOnlyTool('List email outbox'),
      inputSchema: Schema.object(properties: {
        'status': Schema.string(description: OutboxStatus.all.join(', ')),
        'limit': Schema.int(description: '1-200, default 20.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['status', 'limit']);
      final status = a.oneOf('status', OutboxStatus.all);
      final limit = a.integer('limit', min: 1, max: 200) ?? 20;
      a.check();
      if (!await ctx.store.hasTable(EmailOutboxStore.table)) return {'emails': []};
      final list = await EmailOutboxStore.list(ctx.db, status: status, limit: limit);
      return {
        'emails': [
          for (final e in list)
            {
              'id': e.id, 'status': e.status, 'entity_type': e.entityType,
              'entity_id': e.entityId, 'to': e.to, if (e.cc.isNotEmpty) 'cc': e.cc,
              'subject': e.subject,
              'attachments': [for (final f in e.attachments) p.basename(f)],
              'queued_at': e.createdAt,
              if (e.sentAt != null) 'sent_at': e.sentAt,
              if (e.errorMessage != null) 'error': e.errorMessage,
              if (e.emailLogId != null) 'email_log_id': e.emailLogId,
            },
        ],
      };
    },
  );

  late final _cancel = ToolDef(
    Tool(
      name: 'cancel_email',
      description: 'Cancel an email that send_email queued, if the app has '
          'not started sending it yet.',
      annotations: writeTool('Cancel queued email'),
      inputSchema: Schema.object(properties: {
        'id': Schema.int(description: 'outbox_id from send_email.'),
      }, required: ['id']),
    ),
    (a) async {
      a.rejectUnknown(['id']);
      final id = a.integer('id', required: true, min: 1);
      a.check();
      if (!await ctx.store.hasTable(EmailOutboxStore.table)) {
        throw ToolError('No queued email with id $id.');
      }
      final ok = await ctx.store.write((txn) => EmailOutboxStore.transition(
          txn, id!, OutboxStatus.queued, OutboxStatus.cancelled, ctx.nowUtcIso()));
      if (!ok) {
        final e = await EmailOutboxStore.getById(ctx.db, id!);
        throw ToolError(e == null
            ? 'No queued email with id $id.'
            : 'Email $id is already ${e.status}; it can no longer be cancelled.');
      }
      return {'id': id, 'status': OutboxStatus.cancelled};
    },
  );

  List<String> _badAddresses(String field, String list) => [
        for (final addr in list.split(RegExp(r'[,;]')).map((s) => s.trim()))
          if (addr.isNotEmpty && !_emailRe.hasMatch(addr))
            '$field: "$addr" is not a valid email address.',
      ];

  /// Latest successful send from the email log, else a pending outbox email.
  Future<Map<String, Object?>?> _priorSend(String type, int id) async {
    if (await ctx.store.hasTable('email_log')) {
      final r = await ctx.db.query('email_log',
          where: "entity_type = ? AND entity_id = ? AND status = 'sent'",
          whereArgs: [type, id],
          orderBy: 'id DESC',
          limit: 1);
      if (r.isNotEmpty) return {...r.first, 'source': 'log'};
    }
    if (await ctx.store.hasTable(EmailOutboxStore.table)) {
      final r = await ctx.db.query(EmailOutboxStore.table,
          where: 'entity_type = ? AND entity_id = ? AND status IN (?, ?)',
          whereArgs: [type, id, OutboxStatus.queued, OutboxStatus.sending],
          orderBy: 'id DESC',
          limit: 1);
      if (r.isNotEmpty) {
        return {'recipient_to': r.first['recipient_to'],
            'attempted_at': r.first['created_at'], 'source': 'outbox'};
      }
    }
    return null;
  }
}

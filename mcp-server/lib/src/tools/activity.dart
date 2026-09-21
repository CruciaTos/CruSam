import 'package:dart_mcp/server.dart';

import '../context.dart';
import '../tool_kit.dart';

/// History of emails the app sent (invoices, salary documents, disbursements).
class ActivityTools extends ToolGroup {
  final ToolContext ctx;
  ActivityTools(this.ctx);

  @override
  List<ToolDef> get tools => [_emailLog];

  late final _emailLog = ToolDef(
    Tool(
      name: 'list_email_log',
      description: 'Emails sent from CruSam, newest first: what was sent '
          '(entity type + id, e.g. invoice 12), to whom, subject, formats, '
          'status (sent/failed/pending) and any error. Use to answer "did we '
          'already email invoice X?".',
      annotations: readOnlyTool('List email log'),
      inputSchema: Schema.object(properties: {
        'entity_type': Schema.string(description: 'e.g. invoice, salary_bill, salary_slips, disbursement.'),
        'entity_id': Schema.int(description: 'Id of the invoice / batch.'),
        'status': Schema.string(description: 'sent, failed or pending.'),
        'recipient': Schema.string(description: 'Substring of the To/CC address.'),
        'limit': Schema.int(description: '1-200, default 50.'),
      }),
    ),
    (a) async {
      a.rejectUnknown(['entity_type', 'entity_id', 'status', 'recipient', 'limit']);
      final type = a.str('entity_type');
      final id = a.integer('entity_id', min: 0);
      final status = a.oneOf('status', ['sent', 'failed', 'pending']);
      final recipient = a.str('recipient');
      final limit = a.integer('limit', min: 1, max: 200) ?? 50;
      a.check();
      if (!await ctx.store.hasTable('email_log')) return {'emails': []};
      final where = <String>[], args = <Object?>[];
      if (type != null && type.isNotEmpty) { where.add('entity_type = ?'); args.add(type); }
      if (id != null) { where.add('entity_id = ?'); args.add(id); }
      if (status != null) { where.add('status = ?'); args.add(status); }
      if (recipient != null && recipient.isNotEmpty) {
        where.add('(LOWER(recipient_to) LIKE ? OR LOWER(recipient_cc) LIKE ?)');
        final q = '%${recipient.toLowerCase()}%';
        args.addAll([q, q]);
      }
      final rows = await ctx.db.query('email_log',
          where: where.isEmpty ? null : where.join(' AND '),
          whereArgs: args,
          orderBy: 'attempted_at DESC, id DESC',
          limit: limit);
      return {'emails': rows};
    },
  );
}

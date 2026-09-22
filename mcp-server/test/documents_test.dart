import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'harness.dart';

/// Document exports always go to a temp folder (output_dir), never to the
/// app's export folders or Downloads.
void main() {
  late Harness h;
  late String out;
  setUp(() async {
    h = await Harness.open();
    out = p.join(h.dir.path, 'exports');
  });
  tearDown(() async => h.close());

  void expectFiles(List files, int n) {
    expect(files, hasLength(n));
    for (final f in files) {
      final path = f['path'] as String;
      expect(p.isWithin(out, path), isTrue, reason: path);
      expect(File(path).lengthSync(), greaterThan(1000), reason: path);
    }
  }

  test('export_invoice_documents writes PDF and Excel files', () async {
    final list = (await h.ok('list_invoices', {'limit': 1}))['invoices'] as List;
    if (list.isEmpty) return markTestSkipped('no invoices in test DB');
    final r = await h.ok('export_invoice_documents', {
      'id': list.first['id'],
      'documents': ['invoice_pdf', 'bank_disbursement_pdf', 'bank_disbursement_excel'],
      'output_dir': out,
    });
    expectFiles(r['files'] as List, 3);
  });

  test('export_invoice_documents rejects unknown document kinds', () async {
    final e = await h.fails('export_invoice_documents',
        {'id': 1, 'documents': ['receipt'], 'output_dir': out});
    expect(e, contains('documents'));
  });

  test('salary documents and disbursement for a saved month', () async {
    final saved = (await h.ok('list_saved_salary_months', {}))['saved_months'] as List;
    if (saved.isEmpty) return markTestSkipped('no saved salary months in test DB');
    final month = saved.first['month'], year = saved.first['year'];

    final docs = await h.ok('export_salary_documents', {
      'month': month,
      'year': year,
      'documents': ['final_bill_pdf', 'statement_excel', 'slips_pdf'],
      'output_dir': out,
    });
    expectFiles(docs['files'] as List, 3);

    final before = await h.count('salary_disbursements');
    final preview = await h.ok('create_salary_disbursement',
        {'month': month, 'year': year, 'dry_run': true, 'output_dir': out});
    expect(preview['dry_run'], isTrue);
    expect(await h.count('salary_disbursements'), before);
    if (preview['employee_count'] == 0) {
      return markTestSkipped('no disbursement candidates');
    }

    final made = await h.ok('create_salary_disbursement',
        {'month': month, 'year': year, 'dry_run': false, 'output_dir': out});
    expect(await h.count('salary_disbursements'), before + 1);
    final again = await h.ok('export_salary_disbursement_excel',
        {'id': made['disbursement_id'], 'output_dir': out});
    expectFiles([made['file'], again['file']], 2);
  });

  group('send_email', () {
    Future<(int, String)> invoiceWithPdf() async {
      final list = (await h.ok('list_invoices', {'limit': 1}))['invoices'] as List;
      final id = list.first['id'] as int;
      final r = await h.ok('export_invoice_documents', {'id': id, 'output_dir': out});
      return (id, (r['files'] as List).first['path'] as String);
    }

    test('queues with the app wording for invoices; cancel; list', () async {
      final (id, pdf) = await invoiceWithPdf();
      final q = await h.ok('send_email', {
        'entity_type': 'invoice', 'entity_id': id, 'to': 'client@example.com',
        'attachment_paths': [pdf], 'confirm': true,
      });
      expect(q['status'], 'queued');
      expect(q['subject'], startsWith('Tax Invoice'));
      final row = (await h.store.db.query('email_outbox')).single;
      expect(row['body'], contains('Please find attached the tax invoice'));
      expect(row['requested_by'], contains('Claude'));

      // A second send of the same invoice is refused while one is queued.
      expect(await h.fails('send_email', {
        'entity_type': 'invoice', 'entity_id': id, 'to': 'client@example.com',
        'attachment_paths': [pdf], 'confirm': true,
      }), contains('allow_resend'));

      await h.ok('cancel_email', {'id': q['outbox_id']});
      expect(await h.fails('cancel_email', {'id': q['outbox_id']}), contains('cancelled'));
      final listed = (await h.ok('list_email_outbox', {}))['emails'] as List;
      expect(listed.single['status'], 'cancelled');
    });

    test('validation: confirm, addresses, attachment types', () async {
      final (id, pdf) = await invoiceWithPdf();
      final e = await h.fails('send_email', {
        'entity_type': 'invoice', 'entity_id': id, 'to': 'not-an-email',
        'attachment_paths': [pdf], 'confirm': true,
      });
      expect(e, contains('not a valid email'));
      expect(await h.fails('send_email', {
        'entity_type': 'invoice', 'entity_id': id, 'to': 'a@b.com',
        'attachment_paths': [pdf],
      }), contains('confirm'));
      expect(await h.fails('send_email', {
        'entity_type': 'other', 'to': 'a@b.com', 'subject': 's', 'body': 'b',
        'attachment_paths': [h.store.config.dbPath], 'confirm': true,
      }), contains('only .pdf and .xlsx'));
      expect(await h.count('email_outbox'), 0);
    });
  });

  test('list_email_log answers with a list', () async {
    final r = await h.ok('list_email_log', {'limit': 5});
    expect(r['emails'], isA<List>());
  });
}

import 'dart:io';

import 'package:crusam_core/crusam_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

const client = 'M/s Diversey India Hygiene Private Ltd.';

void main() {
  late Harness h;

  setUp(() async => h = await Harness.open());
  tearDown(() async => h.close());

  /// Page 1 of the handwritten PO 700042550 list (user's reference image).
  Future<List<Map<String, Object?>>> pageOneRows() async {
    Future<Map<String, Object?>> row(String name, num amount, String from, String to) async =>
        {'employee_id': await h.employeeId(name), 'amount': amount, 'from_date': from, 'to_date': to};
    return [
      await row('Pankaj Kumar', 19222, '2026-04-01', '2026-04-30'),
      await row('Tarun Arora', 6562, '2026-05-01', '2026-05-15'),
      await row('Mitu Gouda', 17040, '2026-05-21', '2026-05-30'),
      await row('Shailesh Kumar Patil', 8290, '2026-05-21', '2026-05-30'),
      await row('Mohammed Anas Shaikh', 7300, '2026-05-21', '2026-05-30'),
      await row('Darshankumar S K', 19960, '2026-05-16', '2026-05-31'),
      await row('V Karthick Kumar', 24595, '2026-05-16', '2026-05-31'),
      await row('Marimuthu S', 9742, '2026-05-16', '2026-05-31'),
      await row('Rajesh Kumar Rawlo', 6569, '2026-05-21', '2026-05-31'),
      await row('Nitin Sharma', 7674, '2026-05-16', '2026-05-29'),
    ];
  }

  Future<Map<String, Object?>> baseArgs({bool dryRun = true}) async => {
        'title': 'PO 700042550',
        'date': '2031-06-01',
        'po_no': '700042550',
        'bill_no': 'AE/101/26-27',
        'client_name': client,
        'dept_code': 'F&B',
        'rows': await pageOneRows(),
        'dry_run': dryRun,
      };

  group('happy path', () {
    test('creates the invoice with app-identical totals and rows', () async {
      final before = await h.count('vouchers');
      final res = await h.ok('create_invoice', await baseArgs(dryRun: false));

      expect(res['created'], isTrue);
      expect(res['invoice_number'], 'AE/101/26-27');
      final inv = res['invoice'] as Map;
      final id = inv['id'] as int;
      expect(await h.count('vouchers'), before + 1);
      expect(await h.count('voucher_rows', 'voucher_id = $id'), 10);

      // 126954 base; 9% + 9%; rounded to the rupee.
      final totals = inv['totals'] as Map;
      expect(totals['base_total'], 126954);
      expect(totals['cgst_9pct'], 11425.86);
      expect(totals['sgst_9pct'], 11425.86);
      expect(totals['final_total'], 149806);
      expect(totals['round_off'], 0.28);

      // Stored header matches what the shared factory produces.
      final header = (await h.store.db.query('vouchers', where: 'id = $id')).first;
      final expected = InvoiceTotals.fromAmounts(
          (await pageOneRows()).map((r) => (r['amount'] as num).toDouble()));
      expect(header['base_total'], expected.baseTotal);
      expect(header['cgst'], expected.cgst);
      expect(header['final_total'], expected.finalTotal);
      expect(header['round_off'], expected.roundOff);
      expect(header['raw_total'], expected.baseTotal + expected.totalTax);
      expect(header['status'], 'saved');
      expect(header['created_at'], '2031-06-01T00:00:00.000Z');
      expect(header['created_by'], 'tester@example.com');
      expect(header['cloud_id'], startsWith('test-uuid-'));
      expect(header['client_gstin'], '27AABCC1597Q1Z2');
      expect(header['is_deleted'], 0);

      // Rows carry the employee's bank details and the company debit account.
      final pankajId = await h.employeeId('Pankaj Kumar');
      final emp = (await h.store.db.query('employees', where: 'id = $pankajId')).first;
      final row = (await h.store.db.query('voucher_rows',
              where: 'voucher_id = $id AND employee_id = ?', whereArgs: ['$pankajId']))
          .first;
      expect(row['employee_name'], 'Pankaj Kumar');
      expect(row['ifsc_code'], emp['ifsc_code']);
      expect(row['credit_account'], emp['account_number']);
      expect(row['from_date'], '2026-04-01');
      expect(row['dept_code'], 'F&B');
      expect(row['debit_account'], '0680651100000338');

      // Reading it back the way the app does gives the invoice date.
      final got = await h.ok('get_invoice', {'id': id});
      expect(got['date'], '2031-06-01');
      expect((got['rows'] as List).length, 10);
    });

    test('applies app defaults and reports them', () async {
      final args = await baseArgs()..remove('dept_code');
      final res = await h.ok('create_invoice', args);
      expect(res['invoice']['dept_code'], 'I&L');
      expect((res['defaults_applied'] as List).join(), contains('dept_code=I&L'));
    });

    test('takes one backup before the first write', () async {
      await h.ok('create_invoice', await baseArgs(dryRun: false));
      final backups = Directory('${h.dir.path}/backups').listSync();
      expect(backups, hasLength(1));
    });
  });

  group('dry run', () {
    test('returns the computed invoice without writing anything', () async {
      final before = await h.count('vouchers');
      final beforeRows = await h.count('voucher_rows');
      final res = await h.ok('create_invoice', await baseArgs());
      expect(res['dry_run'], isTrue);
      expect(res.containsKey('created'), isFalse);
      expect(res['invoice']['totals']['final_total'], 149806);
      expect(res['invoice']['row_count'], 10);
      expect(await h.count('vouchers'), before);
      expect(await h.count('voucher_rows'), beforeRows);
      expect(Directory('${h.dir.path}/backups').existsSync(), isFalse);
    });

    test('dry run then real run produce the same invoice', () async {
      final dry = await h.ok('create_invoice', await baseArgs());
      final real = await h.ok('create_invoice', await baseArgs(dryRun: false));
      final d = Map.of(dry['invoice'] as Map), r = Map.of(real['invoice'] as Map)..remove('id');
      expect(r, d);
    });
  });

  group('validation', () {
    test('rejects ambiguous dates, string amounts and bad periods together', () async {
      final args = await baseArgs();
      final rows = args['rows'] as List;
      args['date'] = '03/04/2026';
      rows[0] = <String, Object?>{...rows[0] as Map<String, Object?>, 'amount': '7,674'};
      rows[1] = <String, Object?>{...rows[1] as Map<String, Object?>, 'from_date': '1.5.26'};
      rows[2] = <String, Object?>{...rows[2] as Map<String, Object?>, 'from_date': '2026-05-30', 'to_date': '2026-05-21'};
      final msg = await h.fails('create_invoice', args);
      expect(msg, contains('date: "03/04/2026" is not an ISO 8601 date'));
      expect(msg, contains('rows[0].amount: must be a JSON number, got string "7,674"'));
      expect(msg, contains('rows[1].from_date: "1.5.26" is not an ISO 8601 date'));
      expect(msg, contains('rows[2]: to_date 2026-05-21 is before from_date 2026-05-30'));
    });

    test('rejects impossible dates, zero amounts and too many decimals', () async {
      final args = await baseArgs();
      final rows = args['rows'] as List;
      args['date'] = '2026-02-30';
      rows[0] = <String, Object?>{...rows[0] as Map<String, Object?>, 'amount': 0};
      rows[1] = <String, Object?>{...rows[1] as Map<String, Object?>, 'amount': 10.555};
      final msg = await h.fails('create_invoice', args);
      expect(msg, contains('2026-02-30 is not a real calendar date'));
      expect(msg, contains('rows[0].amount: must be > 0'));
      expect(msg, contains('rows[1].amount: at most 2 decimal places'));
    });

    test('requires title, date, rows and dry_run', () async {
      final msg = await h.fails('create_invoice', {'client_name': client});
      for (final f in ['title', 'date', 'rows', 'dry_run']) {
        expect(msg, contains('$f: required'));
      }
    });

    test('refuses unknown clients and suggests close matches', () async {
      final args = await baseArgs()..['client_name'] = 'Diversey India';
      final msg = await h.fails('create_invoice', args);
      expect(msg, contains('"Diversey India" is not a known client'));
      expect(msg, contains(client));
      expect(msg, contains('create_client'));
    });

    test('refuses unknown employee ids and unlinked names', () async {
      final args = await baseArgs();
      final rows = args['rows'] as List;
      rows[0] = <String, Object?>{...rows[0] as Map<String, Object?>, 'employee_id': 999999};
      rows[1] = {'employee_name': 'Some Stranger', 'amount': 100,
          'from_date': '2026-05-01', 'to_date': '2026-05-02'};
      final msg = await h.fails('create_invoice', args);
      expect(msg, contains('rows[0].employee_id: no active employee with id 999999'));
      expect(msg, contains('"Some Stranger" was given without an id'));
    });

    test('allows unlinked names only when explicitly permitted', () async {
      final args = await baseArgs();
      (args['rows'] as List)[0] = {'employee_name': 'Some Stranger', 'amount': 100,
          'from_date': '2026-05-01', 'to_date': '2026-05-02'};
      args['allow_unlinked_employees'] = true;
      final res = await h.ok('create_invoice', args);
      expect((res['warnings'] as List).join(), contains('not linked'));
    });

    test('accepts a PO number sent as a JSON number', () async {
      final res = await h.ok('create_invoice', {...await baseArgs(), 'po_no': 700042550});
      expect(res['invoice']['po_no'], '700042550');
    });

    test('rejects unknown fields and bad dept codes', () async {
      final args = await baseArgs()
        ..['tax_rate'] = 5
        ..['dept_code'] = 'XYZ';
      final msg = await h.fails('create_invoice', args);
      expect(msg, contains('unknown field(s) tax_rate'));
      expect(msg, contains('dept_code: "XYZ" is not allowed'));
    });

    test('nothing is written when validation fails', () async {
      final before = await h.count('vouchers');
      await h.fails('create_invoice', {...await baseArgs(dryRun: false), 'date': 'tomorrow'});
      expect(await h.count('vouchers'), before);
    });
  });

  group('duplicates', () {
    test('same bill number is refused unless allow_duplicate', () async {
      await h.ok('create_invoice', await baseArgs(dryRun: false));
      final before = await h.count('vouchers');

      final other = await baseArgs(dryRun: false)
        ..['date'] = '2031-07-01'
        ..['rows'] = [(await pageOneRows()).first];
      final msg = await h.fails('create_invoice', other);
      expect(msg, contains('Refused'));
      expect(msg, contains('same bill_no'));
      expect(await h.count('vouchers'), before);

      final res = await h.ok('create_invoice', {...other, 'allow_duplicate': true});
      expect(res['created'], isTrue);
      expect(await h.count('vouchers'), before + 1);
    });

    test('same client, date and total is refused even without bill number', () async {
      final args = await baseArgs(dryRun: false)..remove('bill_no');
      await h.ok('create_invoice', args);
      final msg = await h.fails('create_invoice', {...args, 'title': 'Another title'});
      expect(msg, contains('same client, date and final_total'));
    });

    test('dry run reports the duplicate and that it would be refused', () async {
      await h.ok('create_invoice', await baseArgs(dryRun: false));
      final res = await h.ok('create_invoice', await baseArgs());
      expect(res['duplicates'], isNotEmpty);
      expect(res['would_be_refused'], isNotNull);
    });

    test('a deleted invoice no longer counts as a duplicate', () async {
      final first = await h.ok('create_invoice', await baseArgs(dryRun: false));
      await h.ok('delete_invoice', {'id': first['invoice']['id'], 'confirm': true});
      final res = await h.ok('create_invoice', await baseArgs(dryRun: false));
      expect(res['created'], isTrue);
    });

    test('reusing a PO number is only a warning', () async {
      await h.ok('create_invoice', await baseArgs(dryRun: false));
      final res = await h.ok('create_invoice', {
        ...await baseArgs(),
        'bill_no': 'AE/102/26-27',
        'date': '2031-06-15',
      });
      expect(res['duplicates'], isNull);
      expect((res['warnings'] as List).join(), contains('PO 700042550 is already used'));
    });
  });

  test('read-only mode refuses writes', () async {
    final ro = await Harness.open(readOnly: true);
    try {
      final msg = await ro.fails('create_invoice', {
        ...await baseArgs(dryRun: false),
        'rows': [
          {'employee_id': await ro.employeeId('Nitin Sharma'), 'amount': 10,
              'from_date': '2026-05-01', 'to_date': '2026-05-02'}
        ],
      });
      expect(msg, contains('read-only'));
    } finally {
      await ro.close();
    }
  });
}

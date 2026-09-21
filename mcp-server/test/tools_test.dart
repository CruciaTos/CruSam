import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart' show JsonType;
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.open());
  tearDown(() async => h.close());

  group('clients', () {
    test('find_clients tolerates typos and covers invoice history', () async {
      final r = await h.ok('find_clients', {'query': 'diversy india'});
      expect((r['matches'] as List).first['name'],
          'M/s Diversey India Hygiene Private Ltd.');
    });

    test('create_client, then usable by create_invoice', () async {
      final c = await h.ok('create_client', {
        'name': 'Acme Foods Pvt. Ltd.',
        'address': 'Pune',
        'gstin': '27AAACA1234B1Z5',
      });
      expect(c['client']['id'], isA<int>());
      final inv = await h.ok('create_invoice', {
        'title': 'T',
        'date': '2026-06-01',
        'client_id': c['client']['id'],
        'rows': [
          {'employee_id': await h.employeeId('Nitin Sharma'), 'amount': 1000,
              'from_date': '2026-05-01', 'to_date': '2026-05-31'}
        ],
        'dry_run': true,
      });
      expect(inv['invoice']['client']['gstin'], '27AAACA1234B1Z5');
    });

    test('create_client refuses near-duplicates unless allow_similar', () async {
      final msg = await h.fails('create_client', {'name': 'M/s Diversey India Hygiene Pvt Ltd'});
      expect(msg, contains('very similar'));
      final ok = await h.ok('create_client',
          {'name': 'M/s Diversey India Hygiene Pvt Ltd', 'allow_similar': true});
      expect(ok['created'], isTrue);
    });

    test('delete_client requires confirm', () async {
      final c = await h.ok('create_client', {'name': 'Zeta Traders'});
      final msg = await h.fails('delete_client', {'id': c['client']['id']});
      expect(msg, contains('confirm: must be true'));
      await h.ok('delete_client', {'id': c['client']['id'], 'confirm': true});
      expect((await h.ok('find_clients', {'query': 'Zeta Traders'}))['matches'], isEmpty);
    });
  });

  group('employees', () {
    test('match_employees resolves the handwritten names from the image', () async {
      final names = {
        'Hasan Lodi': 'Hasandongri Lodi',
        'P.V. Lokesh': 'Pacharla Venkata Lokesh',
        'Bangi chandrashekhar': 'Bangi Chandra Sekhar',
        'Kanubai Hussan Valli': 'Kanubaigari Husan Valli',
        'Rajeshkumar Raulo': 'Rajesh Kumar Rawlo',
        'Mohd. Anas': 'Mohammed Anas Shaikh',
        'V.Karthickumar': 'V Karthick Kumar',
        'Akash Das': 'Aakash Das',
      };
      final r = await h.ok('match_employees', {'names': names.keys.toList()});
      for (final res in r['results'] as List) {
        expect((res['candidates'] as List).first['name'], names[res['input']],
            reason: res['input'] as String);
        expect(res['confident'], isTrue, reason: res['input'] as String);
      }
    });

    test('create / update / delete employee', () async {
      final c = await h.ok('create_employee', {
        'name': 'Test Person',
        'code': 'I&L',
        'gender': 'F',
        'ifsc_code': 'sbin0001234',
        'account_number': '00123',
        'date_of_joining': '2026-01-15',
        'basic_charges': 15000,
        'other_charges': 500,
      });
      final id = c['employee']['id'] as int;
      final row = (await h.store.db.query('employees', where: 'id = $id')).first;
      expect(row['ifsc_code'], 'SBIN0001234');
      expect(row['date_of_joining'], '15/01/2026');
      expect(row['gross_salary'], 15500);
      expect(row['is_deleted'], 0);

      final u = await h.ok('update_employee', {'id': id, 'basic_charges': 16000});
      expect(u['changes'], contains('basic_charges'));
      expect((await h.store.db.query('employees', where: 'id = $id')).first['gross_salary'], 16500);

      expect(await h.fails('create_employee', {'name': 'Test Person', 'code': 'I&L'}),
          contains('possible duplicate'));
      await h.ok('delete_employee', {'id': id, 'confirm': true});
      expect(await h.count('employees', 'id = $id AND is_deleted = 1'), 1);
    });

    test('create_employee validates code and gender', () async {
      final msg = await h.fails('create_employee', {'name': 'X', 'code': 'ZZ', 'gender': 'Q'});
      expect(msg, contains('code: "ZZ" is not allowed'));
      expect(msg, contains('gender: "Q" is not allowed'));
    });
  });

  group('invoices', () {
    Future<int> make() async => (await h.ok('create_invoice', {
          'title': 'Base',
          'date': '2026-06-01',
          'client_name': 'M/s Diversey India Hygiene Private Ltd.',
          'rows': [
            {'employee_id': await h.employeeId('Nitin Sharma'), 'amount': 1000,
                'from_date': '2026-05-01', 'to_date': '2026-05-31'}
          ],
          'dry_run': false,
        }))['invoice']['id'] as int;

    test('update_invoice recomputes totals and moves the date', () async {
      final id = await make();
      final dry = await h.ok('update_invoice', {'id': id, 'date': '2026-06-05',
          'rows': [
            {'employee_id': await h.employeeId('Tarun Arora'), 'amount': 2000,
                'from_date': '2026-05-01', 'to_date': '2026-05-15'}
          ], 'dry_run': true});
      expect(dry['invoice']['totals']['final_total'], 2360);
      expect((await h.ok('get_invoice', {'id': id}))['totals']['final_total'], 1180);

      await h.ok('update_invoice', {'id': id, 'date': '2026-06-05',
          'rows': [
            {'employee_id': await h.employeeId('Tarun Arora'), 'amount': 2000,
                'from_date': '2026-05-01', 'to_date': '2026-05-15'}
          ], 'dry_run': false});
      final got = await h.ok('get_invoice', {'id': id});
      expect(got['date'], '2026-06-05');
      expect(got['totals']['final_total'], 2360);
      expect((got['rows'] as List).single['employee_name'], 'Tarun Arora');
      expect(await h.count('voucher_rows', 'voucher_id = $id'), 1);
    });

    test('update_invoice with only a title keeps rows and cloud id', () async {
      final id = await make();
      final before = (await h.store.db.query('vouchers', where: 'id = $id')).first;
      await h.ok('update_invoice', {'id': id, 'title': 'Renamed', 'dry_run': false});
      final after = (await h.store.db.query('vouchers', where: 'id = $id')).first;
      expect(after['title'], 'Renamed');
      expect(after['cloud_id'], before['cloud_id']);
      expect(after['created_at'], before['created_at']);
      expect(await h.count('voucher_rows', 'voucher_id = $id'), 1);
    });

    test('list_invoices filters by PO, date and employee', () async {
      final id = await make();
      await h.ok('update_invoice', {'id': id, 'po_no': 'PO-9', 'dry_run': false});
      final r = await h.ok('list_invoices',
          {'po_no': 'po-9', 'date_from': '2026-06-01', 'date_to': '2026-06-01', 'employee': 'nitin'});
      expect((r['invoices'] as List).single['id'], id);
      expect((await h.ok('list_invoices', {'date_from': '2026-06-02', 'po_no': 'PO-9'}))['invoices'], isEmpty);
    });

    test('delete_invoice soft-deletes like the app', () async {
      final id = await make();
      expect(await h.fails('delete_invoice', {'id': id, 'confirm': false}), contains('confirm'));
      await h.ok('delete_invoice', {'id': id, 'confirm': true});
      final row = (await h.store.db.query('vouchers', where: 'id = $id')).first;
      expect(row['is_deleted'], 1);
      expect(row['updated_by'], 'tester@example.com');
      expect(await h.fails('delete_invoice', {'id': id, 'confirm': true}), contains('No (non-deleted)'));
    });
  });

  group('salary', () {
    test('recomputing a saved month from its attendance reproduces the app numbers', () async {
      final saved = (await h.ok('list_saved_salary_months', {}))['saved_months'] as List;
      if (saved.isEmpty) return markTestSkipped('no saved salary months in test DB');
      final snap = await SalarySnapshotStore.get(h.store.db, saved.first['id'] as int);
      final payload = SalarySnapshotPayload.decode(snap!.payload);
      final active = {
        for (final e in await EmployeeStore.listActive(h.store.db)) e.id: e,
      };
      // Only employees whose master salary is unchanged since the save.
      final comparable = payload.employees.where((e) {
        final now = active[e.employeeId];
        return e.days > 0 && now != null &&
            now.basicCharges == e.basicCharges && now.otherCharges == e.otherCharges &&
            now.name == e.employeeName;
      }).toList();
      if (comparable.isEmpty) return markTestSkipped('no comparable employees');

      // The newest saved month was computed with the default formula
      // constants; the formula settings may have been edited since.
      final defaults = const SalaryFormulaConfigModel().toMap()..remove('id');
      await h.ok('update_salary_formula_settings', defaults);

      final r = await h.ok('calculate_salary_month', {
        'month': payload.month,
        'year': payload.year,
        'attendance': [
          for (final e in payload.employees)
            if (active.containsKey(e.employeeId))
              {'employee_id': e.employeeId, 'days': e.days},
        ],
      });
      final lines = {for (final l in r['employees'] as List) l['employee_id']: l};
      for (final e in comparable) {
        final l = lines[e.employeeId];
        expect(l['net_salary'], closeTo(e.netSalary, 0.01), reason: e.employeeName);
        expect(l['pf'], e.pf, reason: e.employeeName);
        expect(l['esic'], e.esic, reason: e.employeeName);
        expect(l['pt'], e.pt, reason: e.employeeName);
      }
    });

    test('save=true stores a snapshot; overwrite needs explicit consent', () async {
      final id = await h.employeeId('Nitin Sharma');
      final args = {
        'month': 3, 'year': 2031,
        'attendance': [{'employee_id': id, 'days': 31}],
        'save': true,
      };
      final r = await h.ok('calculate_salary_month', args);
      expect(r['saved'], isTrue);
      expect(await h.fails('calculate_salary_month', args), contains('already exists'));
      final again = await h.ok('calculate_salary_month', {...args, 'overwrite': true});
      expect(again['replaced_previous'], isTrue);

      final got = await h.ok('get_saved_salary_month', {'month': 3, 'year': 2031});
      expect((got['employees'] as List).single['employee_id'], id);
      expect(await h.count('salary_month_employees', 'snapshot_id = ${got['id']}'),
          greaterThan(1)); // one flattened row per employee, as the app does
    });

    test('attendance validation', () async {
      final msg = await h.fails('calculate_salary_month', {
        'month': 2, 'year': 2026,
        'attendance': [{'employee_id': 999999, 'days': 3}, {'employee_id': 1, 'days': 29}],
      });
      expect(msg, contains('no active employee 999999'));
      expect(msg, contains('attendance[1].days: must be between 0 and 28'));
    });
  });

  group('settings', () {
    test('company and formula settings round-trip', () async {
      await h.ok('update_company_settings', {'phone': '12345'});
      expect((await h.ok('get_company_settings', {}))['phone'], '12345');
      final r = await h.ok('update_salary_formula_settings', {'pf_rate': 0.1});
      expect(r['changes']['pf_rate']['to'], 0.1);
      expect(await h.fails('update_salary_formula_settings', {'pf_rate': 5}),
          contains('between 0.0 and 1.0'));
    });

    test('item descriptions: add, reject duplicates, protect built-ins', () async {
      final a = await h.ok('add_item_description', {'text': 'Housekeeping charges'});
      expect(await h.fails('add_item_description', {'text': 'housekeeping charges'}),
          contains('already exists'));
      final items = (await h.ok('list_item_descriptions', {}))['items'] as List;
      final builtIn = items.firstWhere((i) => i['custom'] == false);
      expect(await h.fails('delete_item_description', {'id': builtIn['id'], 'confirm': true}),
          contains('built-in'));
      await h.ok('delete_item_description', {'id': a['id'], 'confirm': true});
    });
  });

  test('every tool has a description and an object input schema', () {
    for (final t in h.tools.values) {
      expect(t.tool.description, isNotEmpty, reason: t.tool.name);
      expect(t.tool.inputSchema.type, JsonType.object, reason: t.tool.name);
    }
  });
}

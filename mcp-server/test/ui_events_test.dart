import 'package:crusam_core/crusam_core.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.open()..recordUiEvents = true);
  tearDown(() async => h.close());

  Future<List<UiEvent>> events() => UiEventStore.after(h.store.db, 0);

  test('update_employee opens employees, highlights the row, names the change', () async {
    final id = await h.employeeId('Nitin Sharma');
    await h.ok('update_employee', {'id': id, 'basic_charges': 17000});
    final e = (await events()).single;
    expect(e.route, '/employees');
    expect(e.focus, UiEventStore.employeeFocus(id));
    expect(e.message, startsWith('Updated Nitin Sharma: basic charges'));
    expect(e.message, contains('→ 17000'));
    expect(e.dataChanged, isTrue);
  });

  test('reads and dry runs are shown but flagged as not changing data', () async {
    await h.ok('list_invoices', {});
    await h.ok('update_employee',
        {'id': await h.employeeId('Nitin Sharma'), 'basic_charges': 17000, 'dry_run': true});
    final list = await events();
    expect(list.map((e) => e.route), ['/invoices', '/employees']);
    expect(list.map((e) => e.dataChanged), [false, false]);
    expect(list.last.message, startsWith('Previewing changes to Nitin Sharma'));
  });

  test('create_invoice highlights the new invoice', () async {
    final r = await h.ok('create_invoice', {
      'title': 'T',
      'date': '2026-06-01',
      'client_name': 'M/s Diversey India Hygiene Private Ltd.',
      'rows': [
        {'employee_id': await h.employeeId('Nitin Sharma'), 'amount': 1000,
            'from_date': '2026-05-01', 'to_date': '2026-05-31'}
      ],
      'dry_run': false,
    });
    final e = (await events()).single;
    expect(e.route, '/invoices');
    expect(e.focus, UiEventStore.invoiceFocus(r['invoice']['id'] as int));
    expect(e.message, startsWith('Created invoice'));
  });

  test('failed calls record nothing', () async {
    await h.fails('update_employee', {'id': 999999, 'basic_charges': 1});
    expect(await events(), isEmpty);
  });

  test('show_in_app records exactly its own event', () async {
    await h.ok('show_in_app', {
      'screen': 'saved_salary',
      'message': 'Here is May',
      'month': 5,
      'year': 2026,
    });
    final e = (await events()).single;
    expect(e.route, '/saved-salary');
    expect(e.focus, UiEventStore.salaryMonthFocus(5, 2026));
    expect(e.message, 'Here is May');
    expect(e.dataChanged, isFalse);
  });

  test('show_in_app rejects unknown screens', () async {
    final msg = await h.fails('show_in_app', {'screen': 'voucher_builder', 'message': 'x'});
    expect(msg, contains('not allowed'));
  });

  test('old events are pruned', () async {
    for (var i = 0; i < UiEventStore.keep + 5; i++) {
      await UiEventStore.add(h.store.db, UiEvent(message: '$i', createdAt: 'now'));
    }
    final list = await events();
    expect(list, hasLength(UiEventStore.keep));
    expect(list.last.message, '${UiEventStore.keep + 4}');
  });

  test('without the hook (read-only tests, old callers) nothing is recorded', () async {
    h.recordUiEvents = false;
    await h.ok('list_invoices', {});
    expect(await events(), isEmpty);
  });

  test('export_salary_documents walks through each document on the salary screens', () async {
    final saved = (await h.ok('list_saved_salary_months', {}))['saved_months'] as List;
    if (saved.isEmpty) return markTestSkipped('no saved salary months in test DB');
    final month = saved.first['month'] as int, year = saved.first['year'] as int;
    final before = await UiEventStore.lastId(h.store.db);
    await h.ok('export_salary_documents', {
      'month': month,
      'year': year,
      'documents': ['final_bill_pdf', 'statement_excel', 'slips_pdf'],
      'output_dir': h.dir.path,
    });
    final list = await UiEventStore.after(h.store.db, before);
    // statement_excel shares the statement screen with the final bill's last step.
    expect(list.map((e) => e.route), [
      '/salary-invoice', '/salary-attachment-a', '/salary-attachment-b',
      '/salary-statement', '/salary-slips',
    ]);
    expect(list.map((e) => e.period).toSet(), {UiEventStore.period(month, year)});
    expect(list.first.message, startsWith('Creating the final bill: salary invoice for'));
  });

  test('show_in_app on a salary screen needs the saved month', () async {
    final msg = await h.fails('show_in_app', {'screen': 'salary_slips', 'message': 'x'});
    expect(msg, contains('required for salary_slips'));
    await h.ok('show_in_app',
        {'screen': 'salary_slips', 'message': 'May slips', 'month': 5, 'year': 2026});
    final e = (await events()).single;
    expect(e.route, '/salary-slips');
    expect(e.period, '2026-5');
    expect(UiEventStore.parsePeriod(e.period), (5, 2026));
  });

  test('ensureTable adds period to a table from before it existed', () async {
    await h.store.db.execute('DROP TABLE ui_events');
    await h.store.db.execute('''CREATE TABLE ui_events(id INTEGER PRIMARY KEY AUTOINCREMENT,
        route TEXT NOT NULL DEFAULT '', focus TEXT NOT NULL DEFAULT '',
        message TEXT NOT NULL DEFAULT '', data_changed INTEGER NOT NULL DEFAULT 0,
        tool TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL)''');
    await UiEventStore.ensureTable(h.store.db);
    await UiEventStore.add(h.store.db, const UiEvent(message: 'm', period: '2026-5', createdAt: 'now'));
    expect((await events()).single.period, '2026-5');
  });
}

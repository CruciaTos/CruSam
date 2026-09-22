import 'package:crusam_mcp/server.dart';
import 'package:test/test.dart';

import 'harness.dart';

void main() {
  final today = DateTime(2026, 9, 22);
  final workflows = buildWorkflows();

  test('five workflows with unique names, titles and descriptions', () {
    expect(workflows.map((w) => w.name).toSet(), {
      'invoices_from_image', 'salary_from_attendance', 'month_end',
      'email_invoice', 'whats_pending',
    });
    for (final w in workflows) {
      expect(w.prompt.description, isNotEmpty, reason: w.name);
    }
  });

  test('every tool a workflow mentions exists', () async {
    final h = await Harness.open();
    addTearDown(h.close);
    for (final w in workflows) {
      final text = w.build(WorkflowArgs({}, today));
      for (final m in RegExp(r'`([a-z_]+)`').allMatches(text)) {
        final name = m.group(1)!;
        if (name == 'email_invoice') continue; // a workflow, not a tool
        expect(h.tools, contains(name), reason: '${w.name} mentions $name');
      }
    }
  }, skip: hasSourceDb ? false : skipReason);

  test('arguments: month names, defaults and bad values', () {
    String build(String name, Map<String, Object?> args) =>
        workflows.firstWhere((w) => w.name == name).build(WorkflowArgs(args, today));

    expect(build('month_end', {'month': 'sept', 'year': '2026'}), contains('September 2026'));
    expect(build('month_end', {'month': '13'}), contains('ask me which month'));
    expect(build('salary_from_attendance', {'month': '8'}), contains('August 2026'));
    expect(build('whats_pending', {}), contains('2026-09-01 to 2026-09-30'));
    expect(build('whats_pending', {'month': 'feb', 'year': '2028'}),
        contains('2028-02-01 to 2028-02-29'));
    final inv = build('invoices_from_image', {'po_no': '700042550'});
    expect(inv, contains('PO number: 700042550'));
    expect(inv, contains('2026-09-22 (today)'));
    expect(build('email_invoice', {'invoice': 'AE-1', 'include_bank_sheet': 'Yes'}),
        contains('bank_disbursement_excel'));
  });
}

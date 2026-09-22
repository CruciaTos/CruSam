import 'package:crusam_core/crusam_core.dart';
import 'package:dart_mcp/server.dart';

import '../context.dart';
import '../tool_kit.dart';
import '../ui_events.dart';

/// Showing things in the running CruSam app. Every other tool already opens
/// its own screen; this one is for pointing the user at something while
/// explaining (e.g. "here is March's saved salary").
class AppTools extends ToolGroup {
  final ToolContext ctx;
  AppTools(this.ctx);

  @override
  List<ToolDef> get tools => [_show];

  late final _show = ToolDef(
    Tool(
      name: 'show_in_app',
      description: 'Open a screen in the CruSam app (if it is open with '
          '"Follow Claude" on) and optionally highlight one item, with a '
          'one-line note of what you are doing. Tool calls already show '
          'their own screen; use this only to point the user at something '
          'while explaining. Changes no data.',
      annotations: readOnlyTool('Show in app'),
      inputSchema: Schema.object(properties: {
        'screen': Schema.string(description: 'One of: ${appScreens.keys.join(', ')}.'),
        'message': Schema.string(
            description: 'Shown in the app\'s activity banner, e.g. '
                '"Checking March attendance". Keep it short.'),
        'employee_id': Schema.int(description: 'Highlight on employees.'),
        'invoice_id': Schema.int(description: 'Highlight on invoices.'),
        'client_id': Schema.int(description: 'Highlight on clients.'),
        'disbursement_id': Schema.int(description: 'Highlight on disbursements.'),
        'month': Schema.int(
            description: 'With year: the saved salary month. Required for '
                '${salaryScreens.keys.join(', ')} (shown there); highlighted on saved_salary.'),
        'year': Schema.int(),
      }, required: ['screen', 'message']),
    ),
    (a) async {
      a.rejectUnknown(['screen', 'message', 'employee_id', 'invoice_id',
          'client_id', 'disbursement_id', 'month', 'year']);
      final screen = a.oneOf('screen', appScreens.keys.toList(), required: true);
      final message = a.str('message', required: true, maxLength: 200);
      final emp = a.integer('employee_id', min: 1);
      final inv = a.integer('invoice_id', min: 1);
      final cli = a.integer('client_id', min: 1);
      final disb = a.integer('disbursement_id', min: 1);
      final month = a.integer('month', min: 1, max: 12);
      final year = a.integer('year', min: 2000, max: 2100);
      if ((month == null) != (year == null)) {
        a.errors.add('month and year go together.');
      }
      final isSalary = salaryScreens.containsKey(screen);
      if (isSalary && month == null) {
        a.errors.add('month and year: required for $screen (the saved month to show).');
      }
      a.check();
      if (!ctx.store.writable) {
        return {'shown': false, 'reason': 'The server is read-only.'};
      }
      final focus = emp != null
          ? UiEventStore.employeeFocus(emp)
          : inv != null
              ? UiEventStore.invoiceFocus(inv)
              : cli != null
                  ? UiEventStore.clientFocus(cli)
                  : disb != null
                      ? UiEventStore.disbursementFocus(disb)
                      : month != null
                          ? UiEventStore.salaryMonthFocus(month, year!)
                          : '';
      await UiEventStore.ensureTable(ctx.db);
      await UiEventStore.add(
          ctx.db,
          UiEvent(
            route: appScreens[screen]!,
            focus: isSalary ? '' : focus,
            period: isSalary ? UiEventStore.period(month!, year!) : '',
            message: message!,
            tool: 'show_in_app',
            createdAt: ctx.nowUtcIso(),
          ));
      return {
        'shown': true,
        'screen': screen,
        'note': 'Shown if the CruSam app is open with Follow Claude on.',
      };
    },
  );
}

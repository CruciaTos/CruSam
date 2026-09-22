import 'package:crusam_core/crusam_core.dart';

import 'context.dart';
import 'log.dart';
import 'tool_kit.dart';

/// App screens a UI event can open (the app's go_router paths).
const appScreens = {
  'dashboard': '/dashboard',
  'employees': '/employees',
  'invoices': '/invoices',
  'clients': '/clients',
  'company_settings': '/settings',
  'salary_formula': '/salary-formula-settings',
  'saved_salary': '/saved-salary',
  'salary_analytics': '/salary-analytics',
  'disbursements': '/salary-disburse',
  ...salaryScreens,
};

/// Salary screens show the app's live month, so an event opening one also
/// names the saved month to show there (UiEvent.period); the app parks the
/// user's own month meanwhile.
const salaryScreens = {
  'salary_employees': '/salary-employees',
  'salary_slips': '/salary-slips',
  'salary_invoice': '/salary-invoice',
  'attachment_a': '/salary-attachment-a',
  'attachment_b': '/salary-attachment-b',
  'salary_statement': '/salary-statement',
};

/// Screen and label for each export_salary_documents kind. The final bill is
/// the four documents in order, so the user sees each one.
const _salaryDocSteps = {
  'final_bill_pdf': [
    ('/salary-invoice', 'final bill: salary invoice'),
    ('/salary-attachment-a', 'final bill: Attachment A'),
    ('/salary-attachment-b', 'final bill: Attachment B'),
    ('/salary-statement', 'final bill: salary statement'),
  ],
  'salary_invoice_pdf': [('/salary-invoice', 'salary invoice PDF')],
  'attachment_a_pdf': [('/salary-attachment-a', 'Attachment A PDF')],
  'attachment_b_pdf': [('/salary-attachment-b', 'Attachment B PDF')],
  'statement_pdf': [('/salary-statement', 'salary statement PDF')],
  'statement_excel': [('/salary-statement', 'salary statement Excel')],
  'slips_pdf': [('/salary-slips', 'salary slips PDF')],
};

/// Records, after each successful tool call, what the CruSam app should show
/// so the user can watch Claude work ("Follow Claude" in the app). Never
/// fails the tool: a UI event is a nicety.
class UiEvents {
  final ToolContext ctx;
  UiEvents(this.ctx);

  bool _tableReady = false;

  Future<void> record(ToolDef def, Args args, Map<String, Object?> result) async {
    if (!ctx.store.writable) return;
    try {
      final events = await describe(def, args.raw, result);
      if (events.isEmpty) return;
      // Not through store.write: no backup/transaction for a UI hint.
      if (!_tableReady) {
        await UiEventStore.ensureTable(ctx.db);
        _tableReady = true;
      }
      for (final e in events) {
        await UiEventStore.add(ctx.db, e);
      }
    } catch (e, st) {
      Log.error('UI event for ${def.tool.name} failed', e, st);
    }
  }

  /// The steps to show for one call (usually one; none for calls not worth
  /// showing).
  Future<List<UiEvent>> describe(
      ToolDef def, Map<String, Object?> a, Map<String, Object?> r) async {
    if (def.tool.name == 'export_salary_documents') return _salaryDocs(a);
    final e = await _describeOne(def, a, r);
    return e == null ? const [] : [e];
  }

  List<UiEvent> _salaryDocs(Map<String, Object?> a) {
    final month = _int(a['month']), year = _int(a['year']);
    if (month == null || year == null) return const [];
    final kinds = (a['documents'] as List?)?.map((d) => '$d') ?? const ['final_bill_pdf'];
    final steps = [for (final k in kinds) ...?_salaryDocSteps[k]];
    return [
      for (var n = 0; n < steps.length; n++)
        // Two Excel/PDF kinds can share a screen; show it once.
        if (n == 0 || steps[n].$1 != steps[n - 1].$1)
          UiEvent(
            route: steps[n].$1,
            period: UiEventStore.period(month, year),
            message: 'Creating the ${steps[n].$2} for ${_period(month, year)}',
            tool: 'export_salary_documents',
            createdAt: ctx.nowUtcIso(),
          ),
    ];
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

  Future<UiEvent?> _describeOne(
      ToolDef def, Map<String, Object?> a, Map<String, Object?> r) async {
    final name = def.tool.name;
    final dryRun = a['dry_run'] == true || r['dry_run'] == true;
    final changed = def.tool.toolAnnotations?.readOnlyHint != true && !dryRun;

    UiEvent ev(String message,
            {String route = '', String focus = '', String period = '', bool? dataChanged}) =>
        UiEvent(
          route: route,
          focus: focus,
          period: period,
          message: message,
          dataChanged: dataChanged ?? changed,
          tool: name,
          createdAt: ctx.nowUtcIso(),
        );

    Map<String, Object?> m(Object? v) =>
        v is Map ? v.cast<String, Object?>() : const {};
    const i = _int;
    String per(int? month, int? year) =>
        month == null || year == null ? '' : UiEventStore.period(month, year);
    String q(Object? v) => v == null ? '' : ' for "$v"';

    const emp = '/employees', inv = '/invoices', cli = '/clients';
    const saved = '/saved-salary', disb = '/salary-disburse';

    switch (name) {
      // ── Overview & settings ──────────────────────────────────────────────
      case 'get_app_overview':
        return ev('Looking over the business overview', route: '/dashboard');
      case 'get_company_settings':
        return ev('Checking company settings', route: '/settings');
      case 'update_company_settings':
        final fields = (r['updated'] as List?)?.join(', ') ?? '';
        return ev('Updated company settings: $fields', route: '/settings');
      case 'get_salary_formula_settings':
        return ev('Checking PF / ESIC / PT settings', route: '/salary-formula-settings');
      case 'update_salary_formula_settings':
        return ev('Updated salary formula: ${_changes(m(r['changes']))}',
            route: '/salary-formula-settings');
      case 'add_item_description':
        return ev('Added an invoice item description');
      case 'delete_item_description':
        return ev('Removed an invoice item description');

      // ── Clients ──────────────────────────────────────────────────────────
      case 'find_clients':
        return ev('Searching clients${q(a['query'])}', route: cli);
      case 'list_clients':
        return ev('Looking through clients', route: cli);
      case 'create_client' || 'update_client' || 'delete_client':
        final c = m(r['client']);
        final verb = name == 'create_client'
            ? 'Added'
            : name == 'update_client' ? 'Updated' : 'Deleted';
        final id = i(c['id']);
        return ev('$verb client ${c['name'] ?? ''}', route: cli,
            focus: id != null && name != 'delete_client' ? UiEventStore.clientFocus(id) : '');

      // ── Employees ────────────────────────────────────────────────────────
      case 'match_employees':
        final n = (a['names'] as List?)?.length ?? 0;
        return ev('Matching $n name${n == 1 ? '' : 's'} to employees', route: emp);
      case 'find_employees':
        return ev('Searching employees${q(a['query'])}', route: emp);
      case 'list_employees':
        return ev('Looking through employees', route: emp);
      case 'get_employee':
        final id = i(a['id']);
        return ev('Looking at ${m(r['employee'])['name'] ?? r['name'] ?? 'an employee'}',
            route: emp, focus: id == null ? '' : UiEventStore.employeeFocus(id));
      case 'create_employee':
        final e = m(r['employee']);
        final id = i(e['id']);
        return ev(dryRun ? 'Checking new employee ${e['name']}' : 'Added employee ${e['name']}',
            route: emp, focus: id == null || dryRun ? '' : UiEventStore.employeeFocus(id));
      case 'update_employee':
        final id = i(r['employee_id']) ?? i(a['id']);
        final who = id == null ? 'employee' : await _employeeName(id);
        final what = _changes(m(r['changes']));
        return ev(dryRun ? 'Previewing changes to $who: $what' : 'Updated $who: $what',
            route: emp, focus: id == null ? '' : UiEventStore.employeeFocus(id));
      case 'delete_employee':
        return ev('Deleted employee ${m(r['employee'])['name'] ?? ''}', route: emp);

      // ── Invoices ─────────────────────────────────────────────────────────
      case 'list_invoices':
        return ev('Looking through invoices', route: inv);
      case 'get_invoice' || 'export_invoice_documents':
        final id = i(a['id']) ?? i(r['invoice_id']);
        final label = id == null ? 'an invoice' : await _invoiceLabel(id);
        return ev(name == 'get_invoice' ? 'Looking at $label' : 'Created the PDF for $label',
            route: inv, focus: id == null ? '' : UiEventStore.invoiceFocus(id));
      case 'create_invoice' || 'update_invoice':
        final v = m(r['invoice']);
        final id = i(v['id']);
        final label = _invoiceText(v);
        final message = dryRun
            ? (name == 'create_invoice' ? 'Drafting $label' : 'Previewing changes to $label')
            : (name == 'create_invoice' ? 'Created $label' : 'Updated $label');
        return ev(message, route: inv,
            focus: id == null ? '' : UiEventStore.invoiceFocus(id));
      case 'delete_invoice':
        return ev('Deleted ${_invoiceText(m(r['invoice']))}', route: inv);

      // ── Salary ───────────────────────────────────────────────────────────
      case 'calculate_salary_month':
        final month = i(a['month']), year = i(a['year']);
        final period = _period(month, year);
        if (r['saved'] == true && month != null && year != null) {
          return ev('Saved salaries for $period', route: '/salary-employees',
              period: per(month, year));
        }
        // Not saved: there is nothing the app could show yet.
        return ev('Calculating salaries for $period', dataChanged: false);
      case 'list_saved_salary_months':
        return ev('Looking through saved salary months', route: saved);
      case 'get_saved_salary_month' || 'rename_saved_salary_month' || 'delete_saved_salary_month':
        final s = name == 'delete_saved_salary_month' ? m(r['saved_month']) : r;
        final month = i(s['month']), year = i(s['year']);
        final period = s['name'] ?? _period(month, year);
        final message = switch (name) {
          'get_saved_salary_month' => 'Looking at saved salary $period',
          'rename_saved_salary_month' => 'Renamed saved salary to ${r['name']}',
          _ => 'Deleted saved salary $period',
        };
        if (name == 'get_saved_salary_month') {
          return ev(message, route: '/salary-statement', period: per(month, year));
        }
        return ev(message, route: saved,
            focus: month != null && year != null && name != 'delete_saved_salary_month'
                ? UiEventStore.salaryMonthFocus(month, year)
                : '');
      case 'salary_analytics':
        return ev('Analysing salaries', route: '/salary-analytics');
      case 'list_salary_disbursements':
        return ev('Looking through bank disbursements', route: disb);
      case 'get_salary_disbursement' || 'export_salary_disbursement_excel':
        final id = i(a['id']);
        return ev(name == 'get_salary_disbursement'
                ? 'Looking at bank disbursement #$id'
                : 'Created the bank sheet for disbursement #$id',
            route: disb,
            focus: id == null ? '' : UiEventStore.disbursementFocus(id),
            period: per(i(r['month']), i(r['year'])),
            dataChanged: false);
      case 'create_salary_disbursement':
        final month = i(a['month']), year = i(a['year']);
        final period = _period(month, year);
        final id = i(r['disbursement_id']);
        return ev(dryRun ? 'Checking bank disbursement for $period' : 'Created bank disbursement for $period',
            route: disb,
            focus: id == null ? '' : UiEventStore.disbursementFocus(id),
            period: per(month, year));

      // ── Email ────────────────────────────────────────────────────────────
      case 'send_email':
        return ev('Queued email to ${r['to']}: ${r['subject']}');
      case 'cancel_email':
        return ev('Cancelled queued email #${r['id']}');

      case 'show_in_app':
        return null; // records its own event
    }
    // Anything else: only worth a line if it changed data.
    return changed ? ev(def.tool.toolAnnotations?.title ?? name) : null;
  }

  static const _months = ['January', 'February', 'March', 'April', 'May',
      'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  static String _period(int? month, int? year) =>
      month == null || year == null || month < 1 || month > 12
          ? 'the month'
          : '${_months[month - 1]} $year';

  /// "basic charges 15000 → 16000, gross salary …" from a `changes` map.
  static String _changes(Map<String, Object?> changes) {
    if (changes.isEmpty) return 'no changes';
    String fmt(Object? v) => v is double && v == v.roundToDouble() ? '${v.toInt()}' : '$v';
    final parts = [
      for (final e in changes.entries)
        if (e.value is Map)
          '${e.key.replaceAll('_', ' ')} ${fmt((e.value as Map)['from'])} → ${fmt((e.value as Map)['to'])}'
        else
          e.key.replaceAll('_', ' '),
    ];
    return parts.length <= 3 ? parts.join(', ') : '${parts.take(3).join(', ')} +${parts.length - 3} more';
  }

  static String _invoiceText(Map<String, Object?> v) {
    final bill = '${v['bill_no'] ?? ''}'.trim();
    final id = v['id'];
    final name = bill.isNotEmpty ? 'invoice $bill' : (id != null ? 'invoice #$id' : 'an invoice');
    final client = '${v['client_name'] ?? m2(v['client'])['name'] ?? ''}'.trim();
    return client.isEmpty || client == 'null' ? name : '$name for $client';
  }

  static Map<String, Object?> m2(Object? v) =>
      v is Map ? v.cast<String, Object?>() : const {};

  Future<String> _employeeName(int id) async {
    final row = await EmployeeStore.getRow(ctx.db, id);
    return (row?['name'] as String?)?.trim().isNotEmpty == true
        ? row!['name'] as String
        : 'employee #$id';
  }

  Future<String> _invoiceLabel(int id) async {
    final v = await VoucherStore.getById(ctx.db, id);
    return v == null
        ? 'invoice #$id'
        : _invoiceText({'id': id, 'bill_no': v.billNo, 'client_name': v.clientName});
  }
}

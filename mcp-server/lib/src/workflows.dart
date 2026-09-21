import 'package:dart_mcp/server.dart';

/// Ready-made workflows, offered to Claude Desktop as MCP prompts (the "+"
/// menu → CruSam). Each one expands into step-by-step instructions that use
/// the tools, with a stop for the user's approval before anything is saved,
/// exported to someone or emailed.
class Workflow {
  final Prompt prompt;
  final String Function(WorkflowArgs args) build;
  const Workflow(this.prompt, this.build);

  String get name => prompt.name;
}

/// Prompt arguments (always strings in MCP) with forgiving parsing: a bad
/// or missing value is never an error, the text just tells Claude to ask.
class WorkflowArgs {
  final Map<String, String> _values;
  final DateTime today;

  WorkflowArgs(Map<String, Object?>? raw, this.today)
      : _values = {
          for (final e in (raw ?? const {}).entries)
            if (e.value != null && '${e.value}'.trim().isNotEmpty)
              e.key: '${e.value}'.trim(),
        };

  String? operator [](String key) => _values[key];

  /// "September 2026", from `month` (1-12 or a month name) and `year`.
  /// Null when not given or not understood.
  ({int month, int year, String label})? period() {
    final m = _parseMonth(_values['month']);
    if (m == null) return null;
    final y = int.tryParse(_values['year'] ?? '') ?? today.year;
    if (y < 2000 || y > 2100) return null;
    return (month: m, year: y, label: '${_months[m - 1]} $y');
  }

  static int? _parseMonth(String? s) {
    if (s == null) return null;
    final n = int.tryParse(s);
    if (n != null) return n >= 1 && n <= 12 ? n : null;
    final lower = s.toLowerCase();
    for (var i = 0; i < 12; i++) {
      if (lower.length >= 3 && _months[i].toLowerCase().startsWith(lower)) return i + 1;
    }
    return null;
  }
}

const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December'];

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

PromptArgument _monthArg({bool required = false}) => PromptArgument(
    name: 'month', title: 'Month',
    description: 'Month number or name, e.g. 9 or September.', required: required);
PromptArgument _yearArg() => PromptArgument(
    name: 'year', title: 'Year', description: 'e.g. 2026. Default: this year.');

const _approvalRule = 'Never save, overwrite, delete or send anything without my '
    'explicit "yes" to the exact preview you showed me.';

List<Workflow> buildWorkflows() => [
      Workflow(
        Prompt(
          name: 'invoices_from_image',
          title: 'Invoices from a handwritten list',
          description: 'Attach a photo of a PO list (names, amounts, periods). '
              'Claude reads it, matches employees, previews the invoice and '
              'saves it after you approve.',
          arguments: [
            PromptArgument(name: 'po_no', title: 'PO number',
                description: 'Optional. Taken from the image if left empty.'),
            PromptArgument(name: 'invoice_date', title: 'Invoice date',
                description: 'Optional, YYYY-MM-DD. Default: today.'),
            PromptArgument(name: 'bill_no', title: 'Bill number',
                description: 'Optional, e.g. AE - 25-26(4).'),
          ],
        ),
        (a) => '''
Create a CruSam invoice from the handwritten list in the image I'm attaching.
If no image is attached to this message, ask me for it and stop.

${a['po_no'] != null ? 'PO number: ${a['po_no']}.' : 'PO number: read it from the image; ask if there is none.'}
Invoice date: ${a['invoice_date'] ?? '${_iso(a.today)} (today)'}.
${a['bill_no'] != null ? 'Bill number: ${a['bill_no']}.' : 'Bill number: ask me (leave it empty if I have none).'}

Steps:
1. Read every row: employee name, amount, period. "—n—", "do" or a ditto mark
   means "same period as the row above". Periods like "1.5/15.5.26" are
   day.month.year: 2026-05-01 to 2026-05-15. Show me the rows as a table
   and ask me to confirm your reading before going on, pointing out anything
   you are unsure of.
2. Call `match_employees` once with all names. For any match that isn't
   confident, show me the candidates and let me choose.
3. The client is the app's default unless I say otherwise; check it with
   `find_clients`.
4. Put all rows on one invoice unless I say otherwise. Call `create_invoice`
   with dry_run=true and show me: rows, base total, CGST 9%, SGST 9%, final
   total, and every warning or possible duplicate.
5. Only after my approval call `create_invoice` with dry_run=false. Never set
   allow_duplicate unless I tell you to.
6. Offer to create the invoice PDF (`export_invoice_documents`) and to email
   it (the `email_invoice` steps).

$_approvalRule''',
      ),
      Workflow(
        Prompt(
          name: 'salary_from_attendance',
          title: 'Salary month from attendance sheet',
          description: 'Attach a photo of the attendance sheet. Claude reads '
              'days worked, calculates the month with the app\'s formulas, and '
              'saves it after you approve.',
          arguments: [_monthArg(required: true), _yearArg()],
        ),
        (a) {
          final p = a.period();
          return '''
Calculate the CruSam salary month from the attendance sheet in the image I'm
attaching. If no image is attached to this message, ask me for it and stop.

Month: ${p?.label ?? 'not clear from what I entered; ask me which month and year'}.

Steps:
1. Read every row: employee name and days worked. Show me the list as a table
   and ask me to confirm it, pointing out anything you are unsure of.
2. Call `match_employees` once with all names; let me choose where a match
   isn't confident.
3. Ask me what to do with active employees who are not on the sheet
   (normally 0 days).
4. Call `list_saved_salary_months` and tell me if this month is already saved.
5. Call `calculate_salary_month` with save=false and the attendance
   (employee ids + days). Show me: each employee's days, gross and net
   salary, and the bill totals (Attachment A, Attachment B, invoice total).
   Point out anything unusual: days above the days in the month, 0 days, or
   someone missing bank details.
6. Ask me for the salary bill number, PO number and bill date.
7. Only after my approval call `calculate_salary_month` again with save=true
   and those details. Use overwrite=true only if I agreed to replace an
   existing saved month.
8. Offer to continue with the month-end steps (documents, disbursement,
   emails).

$_approvalRule''';
        },
      ),
      Workflow(
        Prompt(
          name: 'month_end',
          title: 'Month-end: salary documents, disbursement, emails',
          description: 'For a saved salary month: create the final bill, '
              'statement and slips, the bank disbursement sheet, and email '
              'them, each step after you approve.',
          arguments: [
            _monthArg(required: true),
            _yearArg(),
            PromptArgument(name: 'email_to', title: 'Email bill to',
                description: 'Optional. Recipient of the salary bill; asked if empty.'),
          ],
        ),
        (a) {
          final p = a.period();
          return '''
Do the CruSam month-end for ${p?.label ?? 'the month I choose (ask me which month and year)'}.

Steps (one at a time, tell me the result of each):
1. `get_saved_salary_month` for the month. If it isn't saved, stop and
   suggest the salary_from_attendance workflow. Otherwise show me the bill
   number, PO, date, employees worked and the invoice total.
2. `export_salary_documents` with documents final_bill_pdf, statement_excel
   and slips_pdf. List the files created.
3. `create_salary_disbursement` with dry_run=true. Show me the number of
   employees, the total, anyone already paid in an earlier batch, and
   employees who worked but are missing bank details. After my approval, run
   it with dry_run=false and give me the Excel file path.
4. Emails, each shown to me in full (to, cc, subject, body, attachments) and
   sent only after my approval, with `send_email`:
   - the final salary bill PDF to ${a['email_to'] ?? 'the client (ask me for the address)'},
     entity_type salary_bill_final, entity_id = the saved month id;
   - ask me whether the disbursement sheet should be emailed too (for
     example to the bank), entity_type salary_disbursement, entity_id = the
     batch id.
5. About 30 seconds after queueing, check `list_email_outbox` and tell me
   whether the app sent them. If they are still queued, remind me the CruSam
   app must be open with Gmail connected in Profile.
6. Finish with a short checklist of what was done and where the files are.

$_approvalRule''';
        },
      ),
      Workflow(
        Prompt(
          name: 'email_invoice',
          title: 'Email an invoice',
          description: 'Find an invoice by bill number, PO or id, create its '
              'PDF and email it through the app\'s Gmail after you approve.',
          arguments: [
            PromptArgument(name: 'invoice', title: 'Invoice', required: true,
                description: 'Bill number, PO number or invoice id.'),
            PromptArgument(name: 'to', title: 'Send to',
                description: 'Optional. Default: the client email on the invoice.'),
            PromptArgument(name: 'include_bank_sheet', title: 'Attach bank sheet?',
                description: 'yes to also attach the bank disbursement Excel.'),
          ],
        ),
        (a) => '''
Email a CruSam invoice: ${a['invoice'] ?? '(ask me which invoice)'}.

Steps:
1. Find it: try `list_invoices` with bill_no, then po_no; if it's a number
   that matches neither, try `get_invoice` with it as the id. If several
   invoices match, list them and let me pick.
2. Check `list_email_log` (entity_type invoice, entity_id = its id) and tell
   me if it was already emailed, to whom and when.
3. `export_invoice_documents` with documents invoice_pdf${(a['include_bank_sheet'] ?? '').toLowerCase().startsWith('y') ? ' and bank_disbursement_excel' : ''}.
4. Show me the draft: to ${a['to'] ?? '(the client email on the invoice; ask me if there is none)'},
   subject, body (the app's standard wording unless I change it) and the
   attachments.
5. After my approval, `send_email` with entity_type invoice. Use
   allow_resend=true only if I confirmed sending it again.
6. About 30 seconds later check `list_email_outbox` and tell me whether the
   app sent it. If it is still queued, remind me the CruSam app must be open
   with Gmail connected in Profile.

$_approvalRule''',
      ),
      Workflow(
        Prompt(
          name: 'whats_pending',
          title: 'What\'s pending this month',
          description: 'Read-only checklist for a month: invoices, saved '
              'salary, disbursement, emails sent or stuck. Changes nothing.',
          arguments: [
            PromptArgument(name: 'month', title: 'Month',
                description: 'Month number or name. Default: this month.'),
            _yearArg(),
          ],
        ),
        (a) {
          final p = a.period() ??
              (month: a.today.month, year: a.today.year,
                  label: '${_months[a.today.month - 1]} ${a.today.year}');
          final from = DateTime(p.year, p.month, 1);
          final to = DateTime(p.year, p.month + 1, 0);
          return '''
Give me a status check of CruSam for ${p.label} (${_iso(from)} to ${_iso(to)}).
Only read; don't change anything.

Check:
1. Invoices dated in the month (`list_invoices` with date_from/date_to):
   how many, total billed, and which are still drafts.
2. Which of those invoices were emailed (`list_email_log`, entity_type
   invoice) and which were not.
3. Salary: is the month saved (`list_saved_salary_months`)? If so, its
   invoice total and employees worked.
4. Disbursement: is there a batch for the month (`list_salary_disbursements`),
   and was its Excel exported?
5. Email problems: anything in `list_email_outbox` that is failed or still
   queued, with the error.

Answer with a short checklist (done / not done) followed by the next steps
you suggest, most urgent first.''';
        },
      ),
    ];

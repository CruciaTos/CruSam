import 'package:dart_mcp/server.dart';
import 'package:stream_channel/stream_channel.dart';

import 'src/context.dart';
import 'src/log.dart';
import 'src/tool_kit.dart';
import 'src/exports/export_env.dart';
import 'src/tools/activity.dart';
import 'src/tools/clients.dart';
import 'src/tools/documents.dart';
import 'src/tools/email.dart';
import 'src/tools/employees.dart';
import 'src/tools/invoices.dart';
import 'src/tools/salary.dart';
import 'src/tools/settings.dart';
import 'src/workflows.dart';

export 'src/config.dart';
export 'src/context.dart';
export 'src/db.dart';
export 'src/exports/export_env.dart';
export 'src/log.dart';
export 'src/workflows.dart';

const serverVersion = '1.2.0';

/// All tool groups. To add capabilities (notes, follow-ups, …) write a new
/// ToolGroup in lib/src/tools/ and add it here.
List<ToolGroup> buildToolGroups(ToolContext ctx, {ExportEnv? exportEnv}) {
  final env = exportEnv ?? (ExportEnv(ctx.db)..install());
  return [
    SettingsTools(ctx),
    ClientTools(ctx),
    EmployeeTools(ctx),
    InvoiceTools(ctx),
    SalaryTools(ctx),
    DocumentTools(ctx, env),
    ActivityTools(ctx),
    EmailTools(ctx),
  ];
}

const _instructions = '''
CruSam is the user's local business app (Aarti Enterprises): employees, tax
invoices billed per employee, and salaries. Call get_app_overview first.
Ready-made workflows are available as prompts (invoices_from_image,
salary_from_attendance, month_end, email_invoice, whats_pending).

Creating invoices from an image or list:
1. Read every row yourself (name, amount, period). A line like "—n—" or "do"
   means "same period as the row above".
2. Convert dates to YYYY-MM-DD. Handwritten "1.5/15.5.26" means
   2026-05-01 to 2026-05-15 (day.month.year, Indian format). If a date is
   ambiguous, ask.
3. Resolve names with match_employees (one call for all rows) and the client
   with find_clients. Show the user any non-confident match.
4. create_invoice with dry_run=true, show rows + totals + warnings, and wait
   for the user's go-ahead before dry_run=false.
Emailing documents: create the files with an export_* tool, then send_email
with the returned paths. The CruSam app sends it through its connected Gmail
account; check list_email_outbox afterwards.
Never create clients, delete anything, send email, or set allow_duplicate /
overwrite / allow_resend / confirm without the user's explicit approval.
''';

base class CrusamMcpServer extends MCPServer with ToolsSupport, PromptsSupport {
  CrusamMcpServer(StreamChannel<String> channel, ToolContext ctx)
      : super.fromStreamChannel(
          channel,
          implementation: Implementation(name: 'crusam', version: serverVersion),
          instructions: _instructions,
        ) {
    for (final group in buildToolGroups(ctx)) {
      for (final def in group.tools) {
        registerTool(
          def.tool,
          (request) => runTool(def, request, (name, e, st) {
            Log.error('Tool $name crashed', e, st);
          }),
          // Arguments are validated by each tool with field-specific messages.
          validateArguments: false,
        );
      }
    }
    for (final w in buildWorkflows()) {
      addPrompt(w.prompt, (request) => GetPromptResult(
            description: w.prompt.description,
            messages: [
              PromptMessage(
                role: Role.user,
                content: TextContent(
                    text: w.build(WorkflowArgs(request.arguments, ctx.clock()))),
              ),
            ],
          ));
    }
  }
}

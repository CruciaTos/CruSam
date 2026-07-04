// lib/features/salary/widgets/send_disbursement_dialog.dart
//
// Compose-and-send dialog for emailing a disbursement batch's Excel sheet.
// Opened from SalaryDisbursementsScreen's "Send Email" action on a history
// card (the Disbursement screen's own entry point — see
// output-format-selector blueprint §4.3.A; the Saved Salary dropdown's
// "Disbursement" entry, §4.3.B, reuses the same build/send path via
// SalaryEmailExportService.buildDisbursementExcel).
//
// Modeled closely on SendInvoiceDialog (same To/Cc/Subject/Body/
// prior-send-notice/resend-confirmation shape), but simpler: there's only
// one possible format here — no PDF generator exists for disbursements —
// so unlike Invoices and Salary Statement, no OutputFormatPicker is shown.
// A locked chip that can't be unchecked would just be a tap that does
// nothing; a plain "Attached as" line says the same thing for free.

import 'package:flutter/material.dart';

import '../../../core/email/gmail_service.dart';
import '../../../core/email/email_suggestions_cache.dart';
import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/db/email_log_repository.dart';
import '../../../data/models/email_log_model.dart';
import '../../../shared/models/output_format.dart';
import '../models/salary_disbursement_model.dart';
import '../services/salary_email_export_service.dart';

class SendDisbursementDialog extends StatefulWidget {
  final SalaryDisbursementModel disbursement;

  const SendDisbursementDialog({super.key, required this.disbursement});

  static Future<void> show(
    BuildContext context, {
    required SalaryDisbursementModel disbursement,
  }) =>
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SendDisbursementDialog(disbursement: disbursement),
      );

  @override
  State<SendDisbursementDialog> createState() =>
      _SendDisbursementDialogState();
}

class _SendDisbursementDialogState extends State<SendDisbursementDialog> {
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late final TextEditingController _toCtrl;
  late final TextEditingController _ccCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  bool           _sending = false;
  String?        _error;
  EmailLogModel? _alreadySentLog;
  bool           _confirmedResend = false;
  List<String>   _suggestions = const [];

  String get _periodLabel {
    final month = _monthNames[(widget.disbursement.month - 1).clamp(0, 11)];
    return '$month ${widget.disbursement.year}';
  }

  @override
  void initState() {
    super.initState();

    _toCtrl = TextEditingController();
    _ccCtrl = TextEditingController();
    _subjectCtrl =
        TextEditingController(text: 'Salary Disbursement — $_periodLabel');
    _bodyCtrl = TextEditingController(
      text: 'Dear Sir,\n\n'
          'Please find attached the salary disbursement sheet for '
          '$_periodLabel.\n\n'
          'Regards,\nBharat Boridkar',
    );

    _checkPriorSends();
    _loadSuggestions();
  }

  // Cached app-wide, defensive against DB errors internally — this can't
  // throw, but the extra try/catch here is a second, cheap safety net so a
  // suggestions hiccup can never affect the rest of the dialog either way.
  Future<void> _loadSuggestions() async {
    try {
      final emails = await EmailSuggestionsCache.instance.load();
      if (mounted) setState(() => _suggestions = emails);
    } catch (_) {
      // Suggestions are a convenience, not a requirement — fail silently.
    }
  }

  Future<void> _checkPriorSends() async {
    final id = widget.disbursement.id;
    if (id == null) return;
    final log = await DatabaseHelper.instance.getLatestSentEmailLogFor(
      SalaryDocumentType.disbursement.entityType,
      id,
    );
    if (mounted) setState(() => _alreadySentLog = log);
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  bool get _needsResendConfirmation =>
      _alreadySentLog != null && !_confirmedResend;

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  Future<void> _send() async {
    final disbursementId = widget.disbursement.id;
    if (disbursementId == null) {
      setState(() => _error = "This disbursement hasn't been saved yet.");
      return;
    }

    final to = _toCtrl.text.trim();
    if (to.isEmpty || !_looksLikeEmail(to)) {
      setState(() => _error = 'Enter a valid recipient email address.');
      return;
    }

    if (!GoogleAuthService.instance.isSignedIn) {
      setState(() => _error =
          'Not connected to Gmail — connect an account in Profile first.');
      return;
    }

    // Resend confirmation is a two-tap pattern: first tap just flips the
    // button to "Send Again" and re-renders the warning; second tap sends.
    if (_needsResendConfirmation) {
      setState(() => _confirmedResend = true);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    int? logId;
    try {
      // 1. Log the attempt before doing anything that can fail.
      logId = await DatabaseHelper.instance.insertEmailLog(EmailLogModel(
        entityType: SalaryDocumentType.disbursement.entityType,
        entityId: disbursementId,
        recipientTo: to,
        recipientCc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        sentBy: GoogleAuthService.instance.userEmail ?? '',
        attachmentFormats: OutputFormat.excel.name,
      ));

      // 2. Re-export bytes for this batch's existing Excel sheet — never
      //    generates a new batch, just reads the same file the screen's own
      //    "Export Excel" button produces (also marks it exported, same as
      //    that button does).
      final doc = await SalaryEmailExportService.buildDisbursementExcel(
        widget.disbursement,
      );
      if (doc == null) {
        throw Exception('Excel export returned no data.');
      }

      // 3. Send.
      final messageId = await GmailService.instance.sendAttachmentsEmail(
        to: to,
        cc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        bodyText: _bodyCtrl.text,
        attachments: [doc],
      );

      // 4. Mark sent.
      await DatabaseHelper.instance.markEmailSent(
        id: logId,
        gmailMessageId: messageId,
      );
      EmailSuggestionsCache.instance.noteUsed(to);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Disbursement emailed to $to')),
      );
    } catch (e) {
      if (logId != null) {
        await DatabaseHelper.instance.markEmailFailed(
          id: logId,
          errorMessage: e.toString(),
        );
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = GoogleAuthService.instance.isSignedIn;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send Disbursement by Email',
                            style: AppTextStyles.h4),
                        const SizedBox(height: 2),
                        Text(_periodLabel, style: AppTextStyles.small),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed:
                        _sending ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              if (!connected) const _Notice(
                text: 'No Gmail account connected — go to Profile to '
                    'connect one before sending.',
              ),

              if (_alreadySentLog != null) ...[
                _Notice(
                  text: 'Already emailed to ${_alreadySentLog!.recipientTo}'
                      '${_alreadySentLog!.sentAt != null ? " on ${_alreadySentLog!.sentAt!.split('T').first}" : ""}.',
                ),
              ],

              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _toCtrl,
                enabled: !_sending,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'To',
                  suffixIcon: _suggestions.isEmpty
                      ? null
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.arrow_drop_down),
                          tooltip: 'Previously used emails',
                          enabled: !_sending,
                          itemBuilder: (context) => _suggestions
                              .map((e) => PopupMenuItem<String>(
                                    value: e,
                                    child: Text(e,
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onSelected: (email) =>
                              setState(() => _toCtrl.text = email),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _ccCtrl,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Cc (optional)'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _subjectCtrl,
                enabled: !_sending,
                decoration: const InputDecoration(labelText: 'Subject'),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _bodyCtrl,
                enabled: !_sending,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Only one possible format here — no picker, just a plain
              // statement of what goes out. See file header.
              Row(
                children: [
                  const Icon(Icons.table_chart_outlined,
                      size: 16, color: AppColors.slate500),
                  const SizedBox(width: 6),
                  Text(
                    'Attached as Excel',
                    style: AppTextStyles.small
                        .copyWith(color: AppColors.slate600),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style:
                      AppTextStyles.small.copyWith(color: Colors.red.shade700),
                ),
              ],

              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _sending ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton.icon(
                    onPressed: (_sending || !connected) ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 16),
                    label: Text(_needsResendConfirmation && !_sending
                        ? 'Send Again'
                        : 'Send'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.amber100,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Text(
          text,
          style: AppTextStyles.small.copyWith(color: AppColors.amber700),
        ),
      );
}
// lib/features/vouchers/widgets/send_invoice_dialog.dart
//
// Compose-and-send dialog for emailing a saved invoice. Opened from
// InvoicePreviewDialog's "Send Email" button.
//
// Flow: validate → log a 'pending' email_log row → build tax-invoice-only
// PDF bytes (no internal voucher page, no disk write) → send via Gmail →
// mark the log row sent/failed. The pending row is inserted *before* the
// PDF/send work so a crash mid-send still leaves a trace instead of
// silently losing the attempt.

import 'package:flutter/material.dart';

import '../../../core/email/gmail_service.dart';
import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/db/email_log_repository.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/email_log_model.dart';
import '../../../data/models/voucher_model.dart';
import '../services/pdf_export_service.dart';

class SendInvoiceDialog extends StatefulWidget {
  final VoucherModel       voucher;
  final CompanyConfigModel config;
  final EdgeInsets         taxInvoiceMargins;

  const SendInvoiceDialog({
    super.key,
    required this.voucher,
    required this.config,
    required this.taxInvoiceMargins,
  });

  static Future<void> show(
    BuildContext context, {
    required VoucherModel       voucher,
    required CompanyConfigModel config,
    required EdgeInsets         taxInvoiceMargins,
  }) =>
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SendInvoiceDialog(
          voucher: voucher,
          config: config,
          taxInvoiceMargins: taxInvoiceMargins,
        ),
      );

  @override
  State<SendInvoiceDialog> createState() => _SendInvoiceDialogState();
}

class _SendInvoiceDialogState extends State<SendInvoiceDialog> {
  late final TextEditingController _toCtrl;
  late final TextEditingController _ccCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  bool           _sending = false;
  String?        _error;
  EmailLogModel? _alreadySentLog;
  bool           _confirmedResend = false;

  @override
  void initState() {
    super.initState();
    final v = widget.voucher;

    _toCtrl = TextEditingController(text: v.clientEmail);
    _ccCtrl = TextEditingController();
    _subjectCtrl = TextEditingController(
      text: 'Tax Invoice'
          '${v.billNo.isNotEmpty ? " ${v.billNo}" : ""}'
          ' — ${widget.config.companyName}',
    );
    _bodyCtrl = TextEditingController(
      text: 'Dear ${v.clientName.isNotEmpty ? v.clientName : "Sir/Madam"},\n\n'
          'Please find attached the tax invoice'
          '${v.billNo.isNotEmpty ? " (Bill No. ${v.billNo})" : ""} '
          'for an amount of Rs. ${v.finalTotal.toStringAsFixed(2)}.\n\n'
          'Regards,\nBharat Boridkar',
    );

    _checkPriorSends();
  }

  Future<void> _checkPriorSends() async {
    final id = widget.voucher.id;
    if (id == null) return;
    final log =
        await DatabaseHelper.instance.getLatestSentEmailLogFor('invoice', id);
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
    final voucherId = widget.voucher.id;
    if (voucherId == null) {
      setState(() => _error = "This invoice hasn't been saved yet.");
      return;
    }

    final to = _toCtrl.text.trim();
    if (to.isEmpty || !_looksLikeEmail(to)) {
      setState(() => _error = 'Enter a valid recipient email address.');
      return;
    }

    if (!GoogleAuthService.instance.isSignedIn) {
      setState(() => _error =
          'Not connected to Gmail — connect an account in Settings first.');
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
        entityType: 'invoice',
        entityId: voucherId,
        recipientTo: to,
        recipientCc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        sentBy: GoogleAuthService.instance.userEmail ?? '',
      ));

      // 2. Build the client-facing PDF — tax invoice only, in memory.
      //    NOTE: always uses the screenshot-based PdfExportService path,
      //    which is also today's default ('useWidgetPdfForInvoiceVoucher'
      //    is false out of the box). If that toggle ever flips to true by
      //    default, WidgetPdfExportService needs an equivalent
      //    tax-invoice-only bytes-only method before this should switch.
      final pdfBytes = await PdfExportService.buildTaxInvoiceBytes(
        context: context,
        voucher: widget.voucher,
        config: widget.config,
        taxInvoiceMargins: widget.taxInvoiceMargins,
      );

      // 3. Send.
      final slug = widget.voucher.billNo.isEmpty
          ? 'invoice'
          : widget.voucher.billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      final messageId = await GmailService.instance.sendPdfEmail(
        to: to,
        cc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        bodyText: _bodyCtrl.text,
        pdfBytes: pdfBytes,
        attachmentFilename: 'tax_invoice_$slug.pdf',
      );

      // 4. Mark sent.
      await DatabaseHelper.instance.markEmailSent(
        id: logId,
        gmailMessageId: messageId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice emailed to $to')),
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
                    child: Text('Send Invoice by Email',
                        style: AppTextStyles.h4),
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
                text: 'No Gmail account connected — go to Settings to '
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
                decoration: const InputDecoration(labelText: 'To'),
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

              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: AppTextStyles.small.copyWith(color: Colors.red.shade700),
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
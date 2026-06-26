// lib/features/salary/widgets/send_salary_document_dialog.dart
//
// Compose-and-send dialog for emailing a document generated from a saved
// salary period. Opened from the Saved Salary screen's "Send" action.
//
// Precondition: the caller must already have made [summary]'s period the
// active salary context (SalarySnapshotNotifier.loadMonth) before showing
// this — every SalaryEmailExportService builder reads the live
// SalaryDataNotifier/SalaryStateController singletons, same as the
// dedicated Salary Bills/Slips screens do for their own exports.
//
// Disbursement is deliberately not offered here — disbursement batches
// aren't children of a salary snapshot the way the other four document
// types are; they're created and reviewed on the dedicated Disbursements
// screen, which is where sending one should be wired up instead.
//
// Flow mirrors SendInvoiceDialog: validate → log a 'pending' email_log row
// → build the document bytes (no disk write) → send via Gmail → mark the
// log row sent/failed.

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
import '../../vouchers/notifiers/margin_settings_notifier.dart';
import '../notifier/salary_data_notifier.dart';
import '../notifier/salary_snapshot_notifier.dart';
import '../notifier/salary_state_controller.dart';
import '../services/salary_email_export_service.dart';

class SendSalaryDocumentDialog extends StatefulWidget {
  final SavedSalarySummary summary;

  const SendSalaryDocumentDialog({super.key, required this.summary});

  static Future<void> show(
    BuildContext context, {
    required SavedSalarySummary summary,
  }) =>
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SendSalaryDocumentDialog(summary: summary),
      );

  @override
  State<SendSalaryDocumentDialog> createState() =>
      _SendSalaryDocumentDialogState();
}

class _SendSalaryDocumentDialogState extends State<SendSalaryDocumentDialog> {
  late final TextEditingController _toCtrl;
  late final TextEditingController _ccCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _bodyCtrl;

  static const _sendableTypes = [
    SalaryDocumentType.salarySlips,
    SalaryDocumentType.salaryBillExport,
    SalaryDocumentType.salaryBillFinal,
    SalaryDocumentType.salaryStatement,
  ];

  SalaryDocumentType _docType = SalaryDocumentType.salarySlips;
  String             _deptCode = 'All';
  CompanyConfigModel _config = const CompanyConfigModel();
  List<String>       _priorEmails = [];
  bool               _bootstrapping = true;
  bool               _sending = false;
  String?            _error;

  @override
  void initState() {
    super.initState();
    _toCtrl = TextEditingController();
    _ccCtrl = TextEditingController();
    _subjectCtrl = TextEditingController();
    _bodyCtrl = TextEditingController();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
    if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);
    _applyTemplate();
    await _loadPriorEmails();
    if (mounted) setState(() => _bootstrapping = false);
  }

  Future<void> _loadPriorEmails() async {
    final emails = await DatabaseHelper.instance
        .getDistinctSentRecipientEmails(entityType: _docType.entityType);
    if (mounted) setState(() => _priorEmails = emails);
  }

  void _applyTemplate() {
    final n = SalaryDataNotifier.instance;
    _subjectCtrl.text =
        '${_docType.label} — ${n.monthName} ${n.year} — ${_config.companyName}';
    _bodyCtrl.text = 'Dear Sir/Madam,\n\n'
        'Please find attached the ${_docType.label.toLowerCase()} for '
        '${n.monthName} ${n.year}.\n\n'
        'Regards,\n${_config.companyName}';
  }

  Future<void> _onDocTypeChanged(SalaryDocumentType? type) async {
    if (type == null || type == _docType) return;
    setState(() {
      _docType = type;
      if (!type.usesDepartmentFilter) _deptCode = 'All';
    });
    _applyTemplate();
    await _loadPriorEmails();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  Future<void> _send() async {
    final snapshotId = widget.summary.snapshot.id;
    if (snapshotId == null) {
      setState(() => _error = "This saved salary period doesn't have an id.");
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

    setState(() {
      _sending = true;
      _error = null;
    });

    int? logId;
    try {
      // 1. Log the attempt before doing anything that can fail.
      logId = await DatabaseHelper.instance.insertEmailLog(EmailLogModel(
        entityType: _docType.entityType,
        entityId: snapshotId,
        recipientTo: to,
        recipientCc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        sentBy: GoogleAuthService.instance.userEmail ?? '',
      ));

      // 2. Build the document — same generators the dedicated salary
      //    screens use for their own exports, just routed to bytes.
      final doc = await _buildDocument();

      // 3. Send.
      final messageId = await GmailService.instance.sendAttachmentEmail(
        to: to,
        cc: _ccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        bodyText: _bodyCtrl.text,
        attachmentBytes: doc.bytes,
        attachmentFilename: doc.filename,
        mimeType: doc.mimeType,
      );

      // 4. Mark sent.
      await DatabaseHelper.instance.markEmailSent(
        id: logId,
        gmailMessageId: messageId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_docType.label} emailed to $to')),
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

  Future<SalaryDocumentBytes> _buildDocument() async {
    switch (_docType) {
      case SalaryDocumentType.salarySlips:
        return SalaryEmailExportService.buildSalarySlips(
          config: _config,
          deptCode: _deptCode,
        );
      case SalaryDocumentType.salaryStatement:
        return SalaryEmailExportService.buildSalaryStatement(
          config: _config,
          deptCode: _deptCode,
        );
      case SalaryDocumentType.salaryBillExport:
      case SalaryDocumentType.salaryBillFinal:
        final marginNotifier = MarginSettingsNotifier();
        await marginNotifier.load();
        final margins = EdgeInsets.fromLTRB(
          marginNotifier.settings.left,
          marginNotifier.settings.top,
          marginNotifier.settings.right,
          marginNotifier.settings.bottom,
        );
        return SalaryEmailExportService.buildSalaryBill(
          context: context,
          config: _config,
          margins: margins,
          deptCode: _deptCode,
          finalised: _docType == SalaryDocumentType.salaryBillFinal,
        );
      case SalaryDocumentType.disbursement:
        // Not offered in this dialog's dropdown — see file header.
        throw Exception(
            'Disbursement sending isn\'t available here — send it from '
            'the Disbursements screen.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = GoogleAuthService.instance.isSignedIn;
    final deptCodes = ['All', ...SalaryStateController.instance.companyCodes];

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _bootstrapping
              ? const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Send Salary Document',
                              style: AppTextStyles.h4),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _sending
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    Text(
                      widget.summary.periodLabel,
                      style: AppTextStyles.small
                          .copyWith(color: AppColors.slate500),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    if (!connected) const _SalaryDialogNotice(
                      text: 'No Gmail account connected — go to Profile to '
                          'connect one before sending.',
                    ),

                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<SalaryDocumentType>(
                      value: _docType,
                      decoration: const InputDecoration(labelText: 'Document'),
                      items: _sendableTypes
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.label),
                              ))
                          .toList(),
                      onChanged: _sending ? null : _onDocTypeChanged,
                    ),

                    if (_docType.usesDepartmentFilter) ...[
                      const SizedBox(height: AppSpacing.sm),
                      DropdownButtonFormField<String>(
                        value: _deptCode,
                        decoration:
                            const InputDecoration(labelText: 'Department'),
                        items: deptCodes
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: _sending
                            ? null
                            : (c) => setState(() => _deptCode = c ?? 'All'),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.sm),
                    Autocomplete<String>(
                      textEditingController: _toCtrl,
                      optionsBuilder: (TextEditingValue value) {
                        final q = value.text.trim().toLowerCase();
                        if (q.isEmpty) return _priorEmails;
                        return _priorEmails
                            .where((e) => e.toLowerCase().contains(q));
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onFieldSubmitted) =>
                              TextField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: !_sending,
                        decoration: InputDecoration(
                          labelText: 'To',
                          helperText: _priorEmails.isNotEmpty
                              ? 'Tap the field to pick a previous recipient'
                              : null,
                          helperMaxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextField(
                      controller: _ccCtrl,
                      enabled: !_sending,
                      decoration:
                          const InputDecoration(labelText: 'Cc (optional)'),
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
                        style: AppTextStyles.small
                            .copyWith(color: Colors.red.shade700),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _sending
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        ElevatedButton.icon(
                          onPressed:
                              (_sending || !connected) ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send, size: 16),
                          label: const Text('Send'),
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

class _SalaryDialogNotice extends StatelessWidget {
  final String text;
  const _SalaryDialogNotice({required this.text});

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
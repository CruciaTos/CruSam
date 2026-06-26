// lib/features/salary/widgets/send_salary_dialog.dart
//
// Compose-and-send dialog for emailing salary documents from the Saved
// Salary screen. The user picks a document type (Salary Slips, Salary Bill,
// or Salary Statement) and an optional department code filter, fills in
// recipient / subject / body, and sends via Gmail.
//
// Flow:
//  1. Dialog opens → decodes snapshot payload for dept codes, loads
//     company config and margin settings from the DB.
//  2. User fills in the form.
//  3. On Send → log a pending email_log row → silently load the snapshot
//     into live state so SalaryEmailExportService can read the right period's
//     data → build document bytes → send via GmailService → mark sent/failed.
//
// Disbursement (Excel) is intentionally excluded here: it requires an
// existing disbursement batch entity that is not part of the snapshot. Use
// the Disbursement screen's own email flow for that.

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
import '../../../data/models/margin_settings_model.dart';
import '../models/salary_snapshot_model.dart';
import '../notifier/salary_snapshot_notifier.dart';
import '../notifier/salary_state_controller.dart';
import '../services/salary_email_export_service.dart';
import '../../vouchers/notifiers/margin_settings_notifier.dart';

class SendSalaryDialog extends StatefulWidget {
  final SavedSalarySummary summary;

  const SendSalaryDialog({super.key, required this.summary});

  /// Show from any BuildContext — owns its own Navigator pop/snackbar.
  static Future<void> show(
    BuildContext context, {
    required SavedSalarySummary summary,
  }) =>
      showDialog(
        context: context,
        barrierColor: Colors.black54,
        builder: (_) => SendSalaryDialog(summary: summary),
      );

  @override
  State<SendSalaryDialog> createState() => _SendSalaryDialogState();
}

class _SendSalaryDialogState extends State<SendSalaryDialog> {
  // ── Form controllers ──────────────────────────────────────────────────────
  final _toCtrl      = TextEditingController();
  final _ccCtrl      = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl    = TextEditingController();

  // ── Selection state ───────────────────────────────────────────────────────
  SalaryDocumentType _docType     = SalaryDocumentType.salarySlips;
  List<String>       _deptCodes   = const ['All'];
  String             _selectedDept = 'All';

  // ── Async state ───────────────────────────────────────────────────────────
  bool           _initialising    = true;
  bool           _sending         = false;
  String?        _error;
  EmailLogModel? _alreadySentLog;
  bool           _confirmedResend = false;

  // ── Resources ─────────────────────────────────────────────────────────────
  CompanyConfigModel _config  = const CompanyConfigModel();
  MarginSettings     _margins = const MarginSettings();

  // ── Document types shown in the dropdown (disbursement excluded) ──────────
  static final _docTypeOptions = SalaryDocumentType.values
      .where((t) => t != SalaryDocumentType.disbursement)
      .toList();

  @override
  void initState() {
    super.initState();
    _subjectCtrl.text = _buildSubject();
    _bodyCtrl.text    = _buildBody();
    _initialise();
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  // ── Async initialisation ──────────────────────────────────────────────────

  Future<void> _initialise() async {
    try {
      // 1. Decode payload to extract dept codes — no live state needed yet.
      final payload = SalarySnapshotPayload.decode(
          widget.summary.snapshot.payload);
      final codes = payload.employees
          .map((e) => e.code.trim())
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      // 2. Load company config from DB.
      final configMap = await DatabaseHelper.instance.getCompanyConfig();
      final config = configMap != null
          ? CompanyConfigModel.fromMap(configMap)
          : const CompanyConfigModel();

      // 3. Load margin settings from DB.
      final marginNotifier = MarginSettingsNotifier();
      await marginNotifier.load();
      final margins = marginNotifier.settings;
      marginNotifier.dispose();

      if (!mounted) return;

      final allDepts = ['All', ...codes];
      // Pre-select the sole dept code when there is only one.
      final selected = codes.length == 1 ? codes.first : 'All';

      setState(() {
        _deptCodes    = allDepts;
        _selectedDept = selected;
        _config       = config;
        _margins      = margins;
      });

      // Refresh subject/body now we have the real company name + dept.
      _refreshAutoFill();

      // 4. Check whether this document type has already been emailed.
      await _checkPriorSends();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _initialising = false);
    }
  }

  Future<void> _checkPriorSends() async {
    final id = widget.summary.snapshot.id;
    if (id == null) return;
    final log = await DatabaseHelper.instance
        .getLatestSentEmailLogFor(_docType.entityType, id);
    if (mounted) setState(() => _alreadySentLog = log);
  }

  // ── Auto-fill helpers ─────────────────────────────────────────────────────

  String _buildSubject() {
    final period     = widget.summary.periodLabel;
    final deptSuffix = _selectedDept == 'All' ? '' : ' — $_selectedDept';
    return '${_docType.label}$deptSuffix — $period';
  }

  String _buildBody() {
    final period = widget.summary.periodLabel;
    return 'Dear Sir/Madam,\n\n'
        'Please find attached the ${_docType.label.toLowerCase()} '
        'for $period.\n\n'
        'Regards,\n${_config.companyName}';
  }

  void _refreshAutoFill() {
    _subjectCtrl.text = _buildSubject();
    _bodyCtrl.text    = _buildBody();
  }

  // ── Validation ────────────────────────────────────────────────────────────

  static bool _looksLikeEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);

  bool get _needsResendConfirmation =>
      _alreadySentLog != null && !_confirmedResend;

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final snapshotId = widget.summary.snapshot.id;
    if (snapshotId == null) {
      setState(() => _error = 'This saved salary has no ID — cannot send.');
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

    // Two-tap resend pattern: first tap shows "Send Again", second tap sends.
    if (_needsResendConfirmation) {
      setState(() => _confirmedResend = true);
      return;
    }

    setState(() {
      _sending = true;
      _error   = null;
    });

    int? logId;
    try {
      // 1. Log the attempt before anything that can fail, so even a crash
      //    mid-send leaves a trace rather than silently losing the attempt.
      logId = await DatabaseHelper.instance.insertEmailLog(EmailLogModel(
        entityType:  _docType.entityType,
        entityId:    snapshotId,
        recipientTo: to,
        recipientCc: _ccCtrl.text.trim(),
        subject:     _subjectCtrl.text.trim(),
        sentBy:      GoogleAuthService.instance.userEmail ?? '',
      ));

      // 2. Ensure employees are loaded and the correct snapshot period is
      //    active in the live SalaryDataNotifier / SalaryStateController —
      //    SalaryEmailExportService reads both singletons.
      if (SalaryStateController.instance.employees.isEmpty) {
        await SalaryStateController.instance.loadEmployees();
      }
      final loaded =
          await SalarySnapshotNotifier.instance.loadMonth(snapshotId);
      if (!mounted) return;
      if (!loaded) {
        throw Exception('Could not load saved salary data: '
            '${SalarySnapshotNotifier.instance.error}');
      }

      // 3. Build the document bytes.
      final doc = await _buildDocument();
      if (doc == null) {
        throw Exception('Document generation returned no data.');
      }

      // 4. Send via Gmail.
      final messageId = await GmailService.instance.sendAttachmentEmail(
        to:                 to,
        cc:                 _ccCtrl.text.trim(),
        subject:            _subjectCtrl.text.trim(),
        bodyText:           _bodyCtrl.text,
        attachmentBytes:    doc.bytes,
        attachmentFilename: doc.filename,
        mimeType:           doc.mimeType,
      );

      // 5. Mark the log row as sent.
      await DatabaseHelper.instance.markEmailSent(
        id:             logId,
        gmailMessageId: messageId,
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_docType.label} emailed to $to'),
        ),
      );
    } catch (e) {
      if (logId != null) {
        await DatabaseHelper.instance.markEmailFailed(
          id:           logId,
          errorMessage: e.toString(),
        );
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error   = e.toString();
      });
    }
  }

  /// Delegates to SalaryEmailExportService based on the selected document
  /// type. buildSalaryBill needs the dialog's BuildContext for off-screen
  /// widget screenshot rendering.
  Future<SalaryDocumentBytes?> _buildDocument() {
    final margins = EdgeInsets.fromLTRB(
      _margins.left,
      _margins.top,
      _margins.right,
      _margins.bottom,
    );

    switch (_docType) {
      case SalaryDocumentType.salarySlips:
        return SalaryEmailExportService.buildSalarySlips(
          config:   _config,
          deptCode: _selectedDept,
        );

      case SalaryDocumentType.salaryStatement:
        return SalaryEmailExportService.buildSalaryStatement(
          config:   _config,
          deptCode: _selectedDept,
        );

      case SalaryDocumentType.salaryBillExport:
        return SalaryEmailExportService.buildSalaryBill(
          context:   context,
          config:    _config,
          margins:   margins,
          deptCode:  _selectedDept,
          finalised: false,
        );

      case SalaryDocumentType.salaryBillFinal:
        return SalaryEmailExportService.buildSalaryBill(
          context:   context,
          config:    _config,
          margins:   margins,
          deptCode:  _selectedDept,
          finalised: true,
        );

      case SalaryDocumentType.disbursement:
        // Disbursement requires a batch entity — excluded from this dialog.
        throw UnsupportedError(
            'Use the Disbursement screen to email disbursement files.');
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _initialising ? _buildLoading() : _buildForm(),
        ),
      ),
    );
  }

  // ── Loading state ─────────────────────────────────────────────────────────

  Widget _buildLoading() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: AppSpacing.xl),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text(
              'Loading salary data…',
              style: AppTextStyles.small,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      );

  // ── Form ──────────────────────────────────────────────────────────────────

  Widget _buildForm() {
    final connected = GoogleAuthService.instance.isSignedIn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: AppSpacing.sm),

        // ── Notices ────────────────────────────────────────────────────────
        if (!connected)
          _Notice(
            icon:  Icons.warning_amber_outlined,
            color: AppColors.amber700,
            bg:    AppColors.amber100,
            text:  'No Gmail account connected — go to Profile → '
                   'Email Sending to connect one.',
          ),

        if (_alreadySentLog != null)
          _Notice(
            icon:  Icons.check_circle_outline,
            color: AppColors.emerald700,
            bg:    AppColors.emerald50,
            text:  'Already sent ${_docType.label} to '
                   '${_alreadySentLog!.recipientTo}'
                   '${_alreadySentLog!.sentAt != null
                       ? " on ${_alreadySentLog!.sentAt!.split('T').first}"
                       : ""}.',
          ),

        const SizedBox(height: AppSpacing.xs),

        // ── Document type ──────────────────────────────────────────────────
        _FieldLabel('Document type'),
        const SizedBox(height: AppSpacing.xs),
        DropdownButtonFormField<SalaryDocumentType>(
          value: _docType,
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          items: _docTypeOptions
              .map(
                (t) => DropdownMenuItem(
                  value: t,
                  child: Text(t.label, style: const TextStyle(fontSize: 13)),
                ),
              )
              .toList(),
          onChanged: _sending
              ? null
              : (t) {
                  if (t == null) return;
                  setState(() {
                    _docType         = t;
                    _confirmedResend = false;
                    _alreadySentLog  = null;
                  });
                  _refreshAutoFill();
                  _checkPriorSends();
                },
        ),

        // ── Department code (only shown when relevant + more than 1 option) ─
        if (_docType.usesDepartmentFilter) ...[
          const SizedBox(height: AppSpacing.sm),
          _FieldLabel('Department'),
          const SizedBox(height: AppSpacing.xs),
          if (_deptCodes.length > 1)
            DropdownButtonFormField<String>(
              value: _selectedDept,
              isDense: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: _deptCodes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(
                        c == 'All' ? 'All departments' : c,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: _sending
                  ? null
                  : (c) {
                      if (c == null) return;
                      setState(() => _selectedDept = c);
                      _refreshAutoFill();
                    },
            )
          else
            // Only one code in this snapshot — show it as a read-only pill.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.slate200),
                borderRadius: BorderRadius.circular(AppSpacing.radius),
                color: AppColors.slate50,
              ),
              child: Text(
                _deptCodes.first == 'All'
                    ? 'All departments'
                    : _deptCodes.first,
                style: AppTextStyles.body.copyWith(color: AppColors.slate600),
              ),
            ),
        ],

        const SizedBox(height: AppSpacing.sm),

        // ── Recipient fields ───────────────────────────────────────────────
        TextField(
          controller: _toCtrl,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'To',
            hintText: 'recipient@example.com',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _ccCtrl,
          enabled: !_sending,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Cc (optional)',
            hintText: 'cc@example.com',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _subjectCtrl,
          enabled: !_sending,
          decoration: const InputDecoration(
            labelText: 'Subject',
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _bodyCtrl,
          enabled: !_sending,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Message',
            alignLabelWithHint: true,
          ),
        ),

        // ── Error text ─────────────────────────────────────────────────────
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            _error!,
            style: AppTextStyles.small.copyWith(color: Colors.red.shade700),
          ),
        ],

        const SizedBox(height: AppSpacing.md),

        // ── Actions ────────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
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
              label: Text(
                _needsResendConfirmation && !_sending ? 'Send Again' : 'Send',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Send Salary by Email', style: AppTextStyles.h4),
                const SizedBox(height: 2),
                Text(
                  widget.summary.periodLabel,
                  style: AppTextStyles.small,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _sending ? null : () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      );
}

// ── Small widget helpers ──────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: AppTextStyles.small.copyWith(
          color: AppColors.slate600,
          fontWeight: FontWeight.w500,
        ),
      );
}

class _Notice extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final Color    bg;
  final String   text;

  const _Notice({
    required this.icon,
    required this.color,
    required this.bg,
    required this.text,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.small.copyWith(color: color),
              ),
            ),
          ],
        ),
      );
}
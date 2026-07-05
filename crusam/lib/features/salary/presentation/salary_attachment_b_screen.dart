import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/margin_settings_model.dart';
import '../../../shared/utils/title_utils.dart';
import '../../vouchers/notifiers/margin_settings_notifier.dart';
import '../../vouchers/services/pdf_export_service.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../widgets/attachment_b_preview.dart';
import '../widgets/shared_salary_widgets.dart';
import '../../../shared/widgets/full_screen_loader.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – matching the InvoicesScreen theme
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

  static const double radius   = 6.0;
  static const double cRadius  = 10.0;
  static const double padH     = 18.0;
  static const double padV     = 16.0;

  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );
}

class SalaryAttachmentBScreen extends StatefulWidget {
  const SalaryAttachmentBScreen({super.key});
  @override
  State<SalaryAttachmentBScreen> createState() =>
      _SalaryAttachmentBScreenState();
}

class _SalaryAttachmentBScreenState extends State<SalaryAttachmentBScreen> {
  final _marginNotifier = MarginSettingsNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting = false;

  final _billNoCtrl = TextEditingController(text: 'AE/-/25-26');
  final _descCtrl   = TextEditingController();

  static const List<String> _allCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  void _setControllerText(TextEditingController ctrl, String value) {
    if (ctrl.text == value) return;
    ctrl.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _syncBillNoFromSalaryData() {
    _setControllerText(
        _billNoCtrl, SalaryDataNotifier.instance.billNo);
  }

  void _onBillNoChanged() {
    SalaryDataNotifier.instance.setBillNo(_billNoCtrl.text);
  }

  void _syncDescFromSalaryData() {
    _setControllerText(
        _descCtrl, SalaryDataNotifier.instance.itemDescriptionAttachmentB);
  }

  void _onDescChanged() {
    SalaryDataNotifier.instance.setItemDescriptionAttachmentB(_descCtrl.text);
  }

  @override
  void initState() {
    super.initState();
    _marginNotifier.load();
    _loadConfig();
    if (SalaryStateController.instance.employees.isEmpty) {
      SalaryStateController.instance.loadEmployees();
    }
    _syncBillNoFromSalaryData();
    _syncDescFromSalaryData();
    SalaryDataNotifier.instance
        .removeListener(_syncBillNoFromSalaryData);
    SalaryDataNotifier.instance
        .addListener(_syncBillNoFromSalaryData);
    SalaryDataNotifier.instance
        .removeListener(_syncDescFromSalaryData);
    SalaryDataNotifier.instance
        .addListener(_syncDescFromSalaryData);
    _billNoCtrl.addListener(_onBillNoChanged);
    _descCtrl.addListener(_onDescChanged);
  }

  @override
  void dispose() {
    SalaryDataNotifier.instance
        .removeListener(_syncBillNoFromSalaryData);
    SalaryDataNotifier.instance
        .removeListener(_syncDescFromSalaryData);
    _billNoCtrl.removeListener(_onBillNoChanged);
    _descCtrl.removeListener(_onDescChanged);
    _marginNotifier.dispose();
    _billNoCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  EdgeInsets get _margins => EdgeInsets.fromLTRB(
        _marginNotifier.settings.left,
        _marginNotifier.settings.top,
        _marginNotifier.settings.right,
        _marginNotifier.settings.bottom,
      );

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    showLoader(context, message: 'Generating Attachment B…');
    try {
      final sc = SalaryStateController.instance;
      final n  = SalaryDataNotifier.instance;
      await PdfExportService.exportWidgets(
        context: context,
        pages: AttachmentBPreview.buildPdfPages(
          config:          _config,
          margins:         _margins,
          itemDescription: n.itemDescriptionAttachmentB,
          billNo:          n.billNo,
          poNo:            n.poNo,
          employeeCount:   sc.employeeCount,
          date:            n.dateDisplay,
          customerName:    n.clientName,
          customerAddress: n.clientAddr,
          customerGst:     n.clientGstin,
        ),
        fileNameSlug:         'attachment_b',
        filePrefix:           'attachment_b',
        shareSubject:         'Attachment B',
        assetPathsToPrecache: [
          'assets/images/aarti_logo.png',
          'assets/images/aarti_signature.png',
        ],
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      hideLoader(context);
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          SalaryStateController.instance,
          SalaryDataNotifier.instance,
          _marginNotifier,
        ]),
        builder: (context, _) {
          final sc    = SalaryStateController.instance;
          final n     = SalaryDataNotifier.instance;
          final code  = sc.selectedCompanyCode;
          final title =
              getTitle('Attachment B', code == 'All' ? null : code);
          final date  = n.dateDisplay;

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(children: [
              // ── Toolbar ─────────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      title,
                      style: AppTextStyles.h3.copyWith(color: Colors.white),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SalaryMonthBadge(
                        monthName: n.monthName, year: n.year),
                    const Spacer(),
                    if (_exporting)
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 16),
                        label: const Text('Download PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade400),
                        ),
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  SalaryCodeFilter(
                    codes:     _allCodes,
                    selected:  code,
                    onChanged: (c) =>
                        sc.setCompanyCode(c ?? 'All'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // ── Themed left pane ──────────────────────────────────────
                  Container(
                    width: 272,
                    margin: const EdgeInsets.only(right: 8),
                    child: Container(
                      padding: const EdgeInsets.all(_Tok.padV),
                      decoration: BoxDecoration(
                        color: _Tok.surface,
                        border: Border.all(color: _Tok.border),
                        borderRadius: BorderRadius.circular(_Tok.cRadius),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _LeftPane(
                        descCtrl:        _descCtrl,
                        billNoCtrl:      _billNoCtrl,
                        sc:              sc,
                        marginNotifier:  _marginNotifier,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: AppColors.slate200,
                  ),
                  // ── Preview pane ───────────────────────────────────────
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 820),
                          child: ListenableBuilder(
                            listenable: Listenable.merge(
                                [_billNoCtrl, _descCtrl, _marginNotifier]),
                            builder: (_, _) => AttachmentBPreview(
                              config:          _config,
                              margins:         _margins,
                              itemDescription: n.itemDescriptionAttachmentB,
                              billNo:          n.billNo,
                              poNo:            n.poNo,
                              employeeCount:   sc.employeeCount,
                              date:            date,
                              customerName:    n.clientName,
                              customerAddress: n.clientAddr,
                              customerGst:     n.clientGstin,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          );
        },
      );
}

// ── Themed left pane ──────────────────────────────────────────────────────────
class _LeftPane extends StatelessWidget {
  final TextEditingController   descCtrl;
  final TextEditingController   billNoCtrl;
  final SalaryStateController   sc;
  final MarginSettingsNotifier  marginNotifier;

  const _LeftPane({
    required this.descCtrl,
    required this.billNoCtrl,
    required this.sc,
    required this.marginNotifier,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: [
          Text('Document Details',
              style: _Tok.tsCardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: 16),
          _label('Bill No.'),
          const SizedBox(height: 4),
          _field(billNoCtrl),
          const SizedBox(height: 12),
          _label('Item Description'),
          const SizedBox(height: 4),
          _descriptionField(descCtrl),
          const SizedBox(height: 16),
          const Divider(color: _Tok.divider),
          const SizedBox(height: 8),
          Text('Attachment B Summary',
              style: _Tok.tsMeta.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          _row('Employee Count',
              '${sc.employeeCount}', _Tok.inkLight),
          _row('Rate per Employee', '₹1,753.00', _Tok.inkMuted),
          const Divider(color: _Tok.divider, height: 20),
          _row(
            'Total Amount',
            '₹${sc.attachmentBTotal.toStringAsFixed(0)}',
            _Tok.ink,
            bold: true,
          ),
          const SizedBox(height: 16),
          const Divider(color: _Tok.divider),
          const SizedBox(height: 8),
          SalaryMarginSection(notifier: marginNotifier),
        ],
      );

  static Widget _label(String t) => Text(
        t,
        style: _Tok.tsLabel,
      );

  static Widget _field(TextEditingController ctrl) => SizedBox(
        height: 38,
        child: TextField(
          controller: ctrl,
          style: _Tok.tsInput,
          decoration: InputDecoration(
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _Tok.border),
              borderRadius: BorderRadius.circular(_Tok.radius),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: _Tok.inkLight),
              borderRadius: BorderRadius.circular(_Tok.radius),
            ),
          ),
        ),
      );

  static Widget _descriptionField(TextEditingController ctrl) => TextField(
        controller: ctrl,
        minLines: 1,
        maxLines: 3,
        style: _Tok.tsInput,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _Tok.border),
            borderRadius: BorderRadius.circular(_Tok.radius),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _Tok.inkLight),
            borderRadius: BorderRadius.circular(_Tok.radius),
          ),
        ),
      );

  static Widget _row(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: _Tok.tsMeta),
            Text(
              value,
              style: _Tok.tsInput.copyWith(
                color: color,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                fontSize: bold ? 13 : 12,
              ),
            ),
          ],
        ),
      );
}
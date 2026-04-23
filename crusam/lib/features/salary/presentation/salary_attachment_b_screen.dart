import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/margin_settings_model.dart';
import '../../../shared/utils/title_utils.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
import '../../vouchers/notifiers/margin_settings_notifier.dart';
import '../../vouchers/services/pdf_export_service.dart';
import '../../vouchers/widgets/item_description_field.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../widgets/attachment_b_preview.dart';
import '../widgets/shared_salary_widgets.dart';

class SalaryAttachmentBScreen extends StatefulWidget {
  const SalaryAttachmentBScreen({super.key});
  @override
  State<SalaryAttachmentBScreen> createState() =>
      _SalaryAttachmentBScreenState();
}

class _SalaryAttachmentBScreenState extends State<SalaryAttachmentBScreen> {
  final _descNotifier   = ItemDescriptionNotifier();
  final _marginNotifier = MarginSettingsNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting = false;

  String _itemDescription = 'Manpower Supply Charges';
  final _billNoCtrl = TextEditingController(text: 'AE/-/25-26');

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

  @override
  void initState() {
    super.initState();
    _descNotifier.load();
    _marginNotifier.load();
    _loadConfig();
    if (SalaryStateController.instance.employees.isEmpty) {
      SalaryStateController.instance.loadEmployees();
    }
    _syncBillNoFromSalaryData();
    SalaryDataNotifier.instance
        .removeListener(_syncBillNoFromSalaryData);
    SalaryDataNotifier.instance
        .addListener(_syncBillNoFromSalaryData);
    _billNoCtrl.addListener(_onBillNoChanged);
  }

  @override
  void dispose() {
    SalaryDataNotifier.instance
        .removeListener(_syncBillNoFromSalaryData);
    _billNoCtrl.removeListener(_onBillNoChanged);
    _descNotifier.dispose();
    _marginNotifier.dispose();
    _billNoCtrl.dispose();
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
    try {
      final sc = SalaryStateController.instance;
      final n  = SalaryDataNotifier.instance;
      await PdfExportService.exportWidgets(
        context: context,
        pages: AttachmentBPreview.buildPdfPages(
          config:          _config,
          margins:         _margins,
          itemDescription: _itemDescription,
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
                    Text(title, style: AppTextStyles.h3),
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
                  // ── Left pane ──────────────────────────────────────────
                  Container(
                    width: 272,
                    color: Colors.grey[200],
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: _LeftPane(
                      descNotifier:    _descNotifier,
                      itemDescription: _itemDescription,
                      billNoCtrl:      _billNoCtrl,
                      sc:              sc,
                      marginNotifier:  _marginNotifier,
                      onDescChanged:
                          (v) => setState(() => _itemDescription = v),
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
                                [_billNoCtrl, _marginNotifier]),
                            builder: (_, _) => AttachmentBPreview(
                              config:          _config,
                              margins:         _margins,
                              itemDescription: _itemDescription,
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

// ── Left pane ─────────────────────────────────────────────────────────────────

class _LeftPane extends StatelessWidget {
  final ItemDescriptionNotifier descNotifier;
  final String                  itemDescription;
  final TextEditingController   billNoCtrl;
  final SalaryStateController   sc;
  final MarginSettingsNotifier  marginNotifier;
  final void Function(String)   onDescChanged;

  const _LeftPane({
    required this.descNotifier,
    required this.itemDescription,
    required this.billNoCtrl,
    required this.sc,
    required this.marginNotifier,
    required this.onDescChanged,
  });

  @override
  Widget build(BuildContext context) => ListView(
        children: [
          Text('Document Details', style: AppTextStyles.h4),
          const SizedBox(height: AppSpacing.lg),
          _label('Bill No.'),
          const SizedBox(height: 4),
          _field(billNoCtrl),
          const SizedBox(height: AppSpacing.md),
          _label('Item Description'),
          const SizedBox(height: 4),
          ItemDescriptionField(
            value:     itemDescription,
            onChanged: onDescChanged,
            notifier:  descNotifier,
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          Text('Attachment B Summary',
              style: AppTextStyles.label
                  .copyWith(color: AppColors.slate500)),
          const SizedBox(height: AppSpacing.sm),
          _row('Employee Count',
              '${sc.employeeCount}', AppColors.indigo600),
          _row('Rate per Employee', '₹1,753.00', AppColors.slate600),
          const Divider(height: AppSpacing.lg),
          _row(
            'Total Amount',
            '₹${sc.attachmentBTotal.toStringAsFixed(0)}',
            AppColors.emerald700,
            bold: true,
          ),
          const SizedBox(height: AppSpacing.xl),
          const Divider(),
          const SizedBox(height: AppSpacing.sm),
          SalaryMarginSection(notifier: marginNotifier),
        ],
      );

  static Widget _label(String t) => Text(
        t,
        style: AppTextStyles.smallMedium.copyWith(
          color: AppColors.slate600,
          fontWeight: FontWeight.w600,
        ),
      );

  static Widget _field(TextEditingController ctrl) => SizedBox(
        height: 38,
        child: TextField(
          controller: ctrl,
          style: AppTextStyles.input,
          decoration: const InputDecoration(
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            Text(label, style: AppTextStyles.small),
            Text(
              value,
              style: AppTextStyles.small.copyWith(
                color: color,
                fontWeight:
                    bold ? FontWeight.w700 : FontWeight.w600,
                fontSize: bold ? 13 : 12,
              ),
            ),
          ],
        ),
      );
}
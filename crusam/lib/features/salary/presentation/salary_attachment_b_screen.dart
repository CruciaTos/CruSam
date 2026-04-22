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

class SalaryAttachmentBScreen extends StatefulWidget {
  const SalaryAttachmentBScreen({super.key});
  @override
  State<SalaryAttachmentBScreen> createState() => _SalaryAttachmentBScreenState();
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
    _setControllerText(_billNoCtrl, SalaryDataNotifier.instance.billNo);
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
    SalaryDataNotifier.instance.removeListener(_syncBillNoFromSalaryData);
    SalaryDataNotifier.instance.addListener(_syncBillNoFromSalaryData);
    _billNoCtrl.addListener(_onBillNoChanged);
  }

  @override
  void dispose() {
    SalaryDataNotifier.instance.removeListener(_syncBillNoFromSalaryData);
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
      final sc   = SalaryStateController.instance;
      final n    = SalaryDataNotifier.instance;
      final code = sc.selectedCompanyCode;
      final title = getTitle('Attachment B', code == 'All' ? null : code);
      final date  = n.dateDisplay;

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(children: [
          // ── Toolbar ───────────────────────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(title, style: AppTextStyles.h3),
                const SizedBox(width: AppSpacing.md),
                _MonthBadge(monthName: n.monthName, year: n.year),
                const Spacer(),
                if (_exporting)
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                    label: const Text('Download PDF'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade400),
                    ),
                  ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              _CodeFilter(
                codes:     _allCodes,
                selected:  code,
                onChanged: (c) => sc.setCompanyCode(c ?? 'All'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── Left pane ─────────────────────────────────────────────────
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
                  onDescChanged:   (v) => setState(() => _itemDescription = v),
                ),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: AppColors.slate200,
              ),
              // ── Preview pane ──────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([_billNoCtrl, _marginNotifier]),
                        builder: (_, __) => AttachmentBPreview(
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

// ── Code filter ───────────────────────────────────────────────────────────────
class _CodeFilter extends StatelessWidget {
  final List<String> codes;
  final String       selected;
  final void Function(String?) onChanged;
  const _CodeFilter({
    required this.codes,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(children: [
      _chip('All', null, selected, onChanged),
      ...codes.map((c) => _chip(c, c, selected, onChanged)),
    ]),
  );

  static Widget _chip(
    String label,
    String? value,
    String selected,
    void Function(String?) onTap,
  ) {
    final active = selected == (value ?? 'All');
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.indigo600 : AppColors.slate800,
            border: Border.all(
              color: active ? AppColors.indigo600 : AppColors.slate600,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.slate400,
            ),
          ),
        ),
      ),
    );
  }
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
          style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: AppSpacing.sm),
      _row('Employee Count',
          '${sc.employeeCount}', AppColors.indigo600),
      _row('Rate per Employee',
          '₹1,753.00', AppColors.slate600),
      const Divider(height: AppSpacing.lg),
      _row('Total Amount',
          '₹${sc.attachmentBTotal.toStringAsFixed(0)}',
          AppColors.emerald700,
          bold: true),
      const SizedBox(height: AppSpacing.xl),
      const Divider(),
      const SizedBox(height: AppSpacing.sm),
      _MarginSection(notifier: marginNotifier),
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
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                fontSize: bold ? 13 : 12,
              ),
            ),
          ],
        ),
      );
}

// ── Month badge ───────────────────────────────────────────────────────────────
class _MonthBadge extends StatelessWidget {
  final String monthName;
  final int    year;
  const _MonthBadge({required this.monthName, required this.year});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.slate800,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.slate700, width: 0.5),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.calendar_month_outlined, size: 13, color: AppColors.slate400),
      const SizedBox(width: 5),
      Text(
        '$monthName $year',
        style: AppTextStyles.small.copyWith(
          color: AppColors.slate300,
          fontWeight: FontWeight.w500,
        ),
      ),
    ]),
  );
}

// ── Margin section ────────────────────────────────────────────────────────────
class _MarginSection extends StatefulWidget {
  final MarginSettingsNotifier notifier;
  const _MarginSection({required this.notifier});
  @override
  State<_MarginSection> createState() => _MarginSectionState();
}

class _MarginSectionState extends State<_MarginSection> {
  late final TextEditingController _top;
  late final TextEditingController _bottom;
  late final TextEditingController _left;
  late final TextEditingController _right;

  @override
  void initState() {
    super.initState();
    final s = widget.notifier.settings;
    _top    = TextEditingController(text: s.top.toStringAsFixed(0));
    _bottom = TextEditingController(text: s.bottom.toStringAsFixed(0));
    _left   = TextEditingController(text: s.left.toStringAsFixed(0));
    _right  = TextEditingController(text: s.right.toStringAsFixed(0));
    widget.notifier.addListener(_sync);
  }

  void _sync() {
    final s = widget.notifier.settings;
    if (mounted) {
      _top.text    = s.top.toStringAsFixed(0);
      _bottom.text = s.bottom.toStringAsFixed(0);
      _left.text   = s.left.toStringAsFixed(0);
      _right.text  = s.right.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_sync);
    _top.dispose();
    _bottom.dispose();
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _apply() => widget.notifier.update(MarginSettings(
    top:    double.tryParse(_top.text)    ?? 24,
    bottom: double.tryParse(_bottom.text) ?? 24,
    left:   double.tryParse(_left.text)   ?? 24,
    right:  double.tryParse(_right.text)  ?? 24,
  ));

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('PDF Margins (px)',
          style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _mf('Top', _top)),
        const SizedBox(width: 6),
        Expanded(child: _mf('Bottom', _bottom)),
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: _mf('Left', _left)),
        const SizedBox(width: 6),
        Expanded(child: _mf('Right', _right)),
      ]),
    ],
  );

  Widget _mf(String label, TextEditingController ctrl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.small),
      const SizedBox(height: 3),
      SizedBox(
        height: 32,
        child: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTextStyles.input,
          decoration: const InputDecoration(
            isDense: true,
            suffixText: 'px',
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          ),
          onChanged: (_) => _apply(),
        ),
      ),
    ],
  );
}
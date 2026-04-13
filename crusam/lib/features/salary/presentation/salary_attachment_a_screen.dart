import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
import '../../vouchers/widgets/item_description_field.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../widgets/attachment_a_preview.dart';

class SalaryAttachmentAScreen extends StatefulWidget {
  const SalaryAttachmentAScreen({super.key});
  @override
  State<SalaryAttachmentAScreen> createState() => _SalaryAttachmentAScreenState();
}

class _SalaryAttachmentAScreenState extends State<SalaryAttachmentAScreen> {
  final _descNotifier = ItemDescriptionNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();

  String _itemDescription = 'Manpower Supply Charges';
  final _billNoCtrl = TextEditingController(text: 'AE/-/25-26');

  @override
  void initState() {
    super.initState();
    _descNotifier.load();
    _loadConfig();
    if (SalaryStateController.instance.employees.isEmpty) {
      SalaryStateController.instance.loadEmployees();
    }
  }

  @override
  void dispose() {
    _descNotifier.dispose();
    _billNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) setState(() => _config = CompanyConfigModel.fromMap(map));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([SalaryStateController.instance, SalaryDataNotifier.instance]),
    builder: (context, _) {
      final sc   = SalaryStateController.instance;
      final n    = SalaryDataNotifier.instance;
      final code = sc.selectedCompanyCode;
      final title = code == 'All' ? 'Attachment A' : 'Attachment A - $code';
      final date = '${n.year}-${n.month.toString().padLeft(2, '0')}-01';

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(children: [
          Row(children: [
            Text(title, style: AppTextStyles.h3),
            const SizedBox(width: AppSpacing.md),
            _MonthBadge(monthName: n.monthName, year: n.year),
          ]),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left pane — grey bg
              Container(
                width: 272,
                color: Colors.grey[200],
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _LeftPane(
                  descNotifier:    _descNotifier,
                  itemDescription: _itemDescription,
                  billNoCtrl:      _billNoCtrl,
                  sc:              sc,
                  onDescChanged:   (v) => setState(() => _itemDescription = v),
                ),
              ),
              Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: AppColors.slate200),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListenableBuilder(
                        listenable: _billNoCtrl,
                        builder: (_, __) => AttachmentAPreview(
                          config:          _config,
                          itemDescription: _itemDescription,
                          billNo:          _billNoCtrl.text,
                          poNo:            n.poNo,
                          date:            date,
                          itemAmount:      sc.totalEarnedGross,
                          pfAmount:        sc.attachmentAPf,
                          esicAmount:      sc.attachmentAEsic,
                          totalAfterTax:   sc.attachmentATotal,
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

class _LeftPane extends StatelessWidget {
  final ItemDescriptionNotifier  descNotifier;
  final String                   itemDescription;
  final TextEditingController    billNoCtrl;
  final SalaryStateController    sc;
  final void Function(String)    onDescChanged;

  const _LeftPane({required this.descNotifier, required this.itemDescription,
      required this.billNoCtrl, required this.sc, required this.onDescChanged});

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Document Details', style: AppTextStyles.h4),
    const SizedBox(height: AppSpacing.lg),
    _label('Bill No.'), const SizedBox(height: 4), _field(billNoCtrl),
    const SizedBox(height: AppSpacing.md),
    _label('Item Description'), const SizedBox(height: 4),
    ItemDescriptionField(value: itemDescription, onChanged: onDescChanged, notifier: descNotifier),
    const SizedBox(height: AppSpacing.xl),
    const Divider(),
    const SizedBox(height: AppSpacing.sm),
    Text('Salary Aggregates', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
    const SizedBox(height: AppSpacing.sm),
    _row('Total Earned Gross',    '₹${sc.totalEarnedGross.toStringAsFixed(2)}',   AppColors.indigo600),
    _row('PF (13.61% basic)',     '₹${sc.attachmentAPf.toStringAsFixed(2)}',       AppColors.slate600),
    _row('ESIC (3.25% eligible)', '₹${sc.attachmentAEsic.toStringAsFixed(2)}',     AppColors.slate600),
    _row('Round Off',             '${sc.attachmentARoundOff >= 0 ? "+" : ""}${sc.attachmentARoundOff.toStringAsFixed(2)}', AppColors.slate500),
    const Divider(height: AppSpacing.lg),
    _row('Grand Total', '₹${sc.attachmentATotal.toStringAsFixed(0)}', AppColors.emerald700, bold: true),
  ]);

  static Widget _label(String t) =>
      Text(t, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate600, fontWeight: FontWeight.w600));

  static Widget _field(TextEditingController ctrl) => SizedBox(
    height: 38,
    child: TextField(controller: ctrl, style: AppTextStyles.input,
        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
  );

  static Widget _row(String label, String value, Color color, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: AppTextStyles.small),
          Text(value, style: AppTextStyles.small.copyWith(color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600, fontSize: bold ? 13 : 12)),
        ]),
      );
}

class _MonthBadge extends StatelessWidget {
  final String monthName; final int year;
  const _MonthBadge({required this.monthName, required this.year});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: AppColors.slate800, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.slate700, width: 0.5)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.calendar_month_outlined, size: 13, color: AppColors.slate400),
      const SizedBox(width: 5),
      Text('$monthName $year', style: AppTextStyles.small.copyWith(color: AppColors.slate300, fontWeight: FontWeight.w500)),
    ]),
  );
}
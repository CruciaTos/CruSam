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
import '../widgets/attachment_b_preview.dart';

class SalaryAttachmentBScreen extends StatefulWidget {
  const SalaryAttachmentBScreen({super.key});
  @override
  State<SalaryAttachmentBScreen> createState() => _SalaryAttachmentBScreenState();
}

class _SalaryAttachmentBScreenState extends State<SalaryAttachmentBScreen> {
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
      final title = code == 'All' ? 'Attachment B' : 'Attachment B - $code';

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(children: [
          Row(children: [Text(title, style: AppTextStyles.h3)]),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left pane — grey bg
              Container(
                width: 272,
                color: Colors.grey[200],
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Document Details', style: AppTextStyles.h4),
                  const SizedBox(height: AppSpacing.lg),
                  _label('Bill No.'), const SizedBox(height: 4), _field(_billNoCtrl),
                  const SizedBox(height: AppSpacing.md),
                  _label('Item Description'), const SizedBox(height: 4),
                  ItemDescriptionField(value: _itemDescription, onChanged: (v) => setState(() => _itemDescription = v), notifier: _descNotifier),
                  const SizedBox(height: AppSpacing.xl),
                  const Divider(),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Attachment B Summary', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
                  const SizedBox(height: AppSpacing.sm),
                  _summaryRow('Employee Count', '${sc.employeeCount}', AppColors.indigo600),
                  _summaryRow('Rate per Employee', '₹1,753.00', AppColors.slate600),
                  const Divider(height: AppSpacing.lg),
                  _summaryRow('Total Amount', '₹${sc.attachmentBTotal.toStringAsFixed(0)}', AppColors.emerald700, bold: true),
                ]),
              ),
              Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: AppColors.slate200),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListenableBuilder(
                        listenable: Listenable.merge([_billNoCtrl, SalaryDataNotifier.instance]),
                        builder: (_, __) => AttachmentBPreview(
                          config:          _config,
                          itemDescription: _itemDescription,
                          billNo:          _billNoCtrl.text,
                          poNo:            n.poNo,
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

  static Widget _label(String t) =>
      Text(t, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate600, fontWeight: FontWeight.w600));

  static Widget _field(TextEditingController ctrl) => SizedBox(
    height: 38,
    child: TextField(controller: ctrl, style: AppTextStyles.input,
        decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
  );

  static Widget _summaryRow(String label, String value, Color color, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: AppTextStyles.small),
          Text(value, style: AppTextStyles.small.copyWith(color: color,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600, fontSize: bold ? 13 : 12)),
        ]),
      );
}
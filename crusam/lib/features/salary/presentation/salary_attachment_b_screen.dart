import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
import '../../vouchers/widgets/item_description_field.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
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
  }

  @override
  void dispose() {
    _descNotifier.dispose();
    _billNoCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.pagePadding),
    child: Column(children: [
      // ── Toolbar ─────────────────────────────────────────────────────────
      Row(children: [Text('Attachment B', style: AppTextStyles.h3)]),
      const SizedBox(height: AppSpacing.lg),
      // ── Body ────────────────────────────────────────────────────────────
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Left pane
          SizedBox(
            width: 272,
            child: _LeftPane(
              descNotifier:    _descNotifier,
              itemDescription: _itemDescription,
              billNoCtrl:      _billNoCtrl,
              onDescChanged:   (v) => setState(() => _itemDescription = v),
            ),
          ),
          // Divider
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: AppColors.slate200,
          ),
          // Right pane — live preview
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
                      poNo:            SalaryDataNotifier.instance.poNo,
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
}

// ── Left pane ──────────────────────────────────────────────────────────────────
class _LeftPane extends StatelessWidget {
  final ItemDescriptionNotifier descNotifier;
  final String                  itemDescription;
  final TextEditingController   billNoCtrl;
  final void Function(String)   onDescChanged;

  const _LeftPane({
    required this.descNotifier,
    required this.itemDescription,
    required this.billNoCtrl,
    required this.onDescChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
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
    ],
  );

  static Widget _label(String t) =>
      Text(t, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate600, fontWeight: FontWeight.w600));

  static Widget _field(TextEditingController ctrl) => SizedBox(
    height: 38,
    child: TextField(
      controller: ctrl,
      style: AppTextStyles.input,
      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
    ),
  );
}
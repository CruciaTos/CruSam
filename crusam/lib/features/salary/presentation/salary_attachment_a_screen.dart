import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/employee_model.dart';
import '../../master_data/notifiers/employee_notifier.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
import '../../vouchers/widgets/item_description_field.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import '../widgets/attachment_a_preview.dart';

class SalaryAttachmentAScreen extends StatefulWidget {
  const SalaryAttachmentAScreen({super.key});
  @override
  State<SalaryAttachmentAScreen> createState() => _SalaryAttachmentAScreenState();
}

class _SalaryAttachmentAScreenState extends State<SalaryAttachmentAScreen> {
  final _employeeNotifier = EmployeeNotifier();
  final _descNotifier     = ItemDescriptionNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();

  String _itemDescription = 'Manpower Supply Charges';
  final _billNoCtrl = TextEditingController(text: 'AE/-/25-26');

  @override
  void initState() {
    super.initState();
    _employeeNotifier.load();
    _descNotifier.load();
    _loadConfig();
  }

  @override
  void dispose() {
    _employeeNotifier.dispose();
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

  _Calc _compute(List<EmployeeModel> employees) {
    final n = SalaryDataNotifier.instance;
    double totalEarnedBasic = 0, totalEarnedGross = 0, totalEligibleGross = 0;
    for (final e in employees) {
      if (n.totalDays == 0) continue;
      final days = n.getDays(e.id ?? 0);
      final eb   = e.basicCharges * days / n.totalDays;
      final eg   = eb + e.otherCharges * days / n.totalDays;
      totalEarnedBasic += eb;
      totalEarnedGross += eg;
      if (e.grossSalary > 21000) totalEligibleGross += eg;
    }
    final pf   = totalEarnedBasic * 0.1361;
    final esic = totalEligibleGross * 0.0325;
    return _Calc(
      itemAmount:    totalEarnedGross,
      pfAmount:      pf,
      esicAmount:    esic,
      totalAfterTax: totalEarnedGross + pf + esic,
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_employeeNotifier, SalaryDataNotifier.instance]),
    builder: (context, _) {
      final n    = SalaryDataNotifier.instance;
      final calc = _compute(_employeeNotifier.employees);
      final date = '${n.year}-${n.month.toString().padLeft(2, '0')}-01';

      return Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(children: [
          // ── Toolbar ───────────────────────────────────────────────────────
          Row(children: [
            Text('Attachment A', style: AppTextStyles.h3),
            const SizedBox(width: AppSpacing.md),
            _MonthBadge(monthName: n.monthName, year: n.year),
          ]),
          const SizedBox(height: AppSpacing.lg),
          // ── Body ──────────────────────────────────────────────────────────
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left pane
              SizedBox(
                width: 272,
                child: _LeftPane(
                  descNotifier:        _descNotifier,
                  itemDescription:     _itemDescription,
                  billNoCtrl:          _billNoCtrl,
                  calc:                calc,
                  onDescChanged:       (v) => setState(() => _itemDescription = v),
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
                        listenable: _billNoCtrl,
                        builder: (_, __) => AttachmentAPreview(
                          config:          _config,
                          itemDescription: _itemDescription,
                          billNo:          _billNoCtrl.text,
                          poNo:            n.poNo,
                          date:            date,
                          itemAmount:      calc.itemAmount,
                          pfAmount:        calc.pfAmount,
                          esicAmount:      calc.esicAmount,
                          totalAfterTax:   calc.totalAfterTax,
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

// ── Calculation data class ─────────────────────────────────────────────────────
class _Calc {
  final double itemAmount;
  final double pfAmount;
  final double esicAmount;
  final double totalAfterTax;
  const _Calc({
    required this.itemAmount,
    required this.pfAmount,
    required this.esicAmount,
    required this.totalAfterTax,
  });
}

// ── Left pane ──────────────────────────────────────────────────────────────────
class _LeftPane extends StatelessWidget {
  final ItemDescriptionNotifier  descNotifier;
  final String                   itemDescription;
  final TextEditingController    billNoCtrl;
  final _Calc                    calc;
  final void Function(String)    onDescChanged;

  const _LeftPane({
    required this.descNotifier,
    required this.itemDescription,
    required this.billNoCtrl,
    required this.calc,
    required this.onDescChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Document Details', style: AppTextStyles.h4),
      const SizedBox(height: AppSpacing.lg),

      // Bill No
      _label('Bill No.'),
      const SizedBox(height: 4),
      _field(billNoCtrl),
      const SizedBox(height: AppSpacing.md),

      // Item Description dropdown
      _label('Item Description'),
      const SizedBox(height: 4),
      ItemDescriptionField(
        value:      itemDescription,
        onChanged:  onDescChanged,
        notifier:   descNotifier,
      ),
      const SizedBox(height: AppSpacing.xl),

      // Salary-sourced summary
      const Divider(),
      const SizedBox(height: AppSpacing.sm),
      Text('Salary Aggregates', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: AppSpacing.sm),
      _summaryRow('Total Gross',     '₹${calc.itemAmount.toStringAsFixed(2)}', AppColors.indigo600),
      _summaryRow('PF (13.61% basic)',  '₹${calc.pfAmount.toStringAsFixed(2)}',  AppColors.slate600),
      _summaryRow('ESIC (3.25% elig.)', '₹${calc.esicAmount.toStringAsFixed(2)}', AppColors.slate600),
      const Divider(height: AppSpacing.lg),
      _summaryRow('Grand Total',     '₹${calc.totalAfterTax.toStringAsFixed(2)}', AppColors.emerald700, bold: true),
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

  static Widget _summaryRow(String label, String value, Color valueColor, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: AppTextStyles.small),
          Text(value, style: AppTextStyles.small.copyWith(
            color: valueColor,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontSize: bold ? 13 : 12,
          )),
        ]),
      );
}

// ── Month badge ────────────────────────────────────────────────────────────────
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
      Text('$monthName $year',
          style: AppTextStyles.small.copyWith(color: AppColors.slate300, fontWeight: FontWeight.w500)),
    ]),
  );
}
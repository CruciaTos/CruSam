import 'package:crusam/features/salary/services/Salary_pdf_export_service.dart';
import 'package:crusam/features/salary/services/salary_pdf_export_service.dart' hide SalaryPdfExportService;
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
  bool _exporting = false;

  String _itemDescription = 'Manpower Supply Charges';
  final _billNoCtrl = TextEditingController(text: 'AE/-/25-26');

  // ── Always show all four company codes regardless of what's in the DB ────────
  static const List<String> _allCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

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

  /// Formats the selected month/year into a display date string for the bill.
  String _buildDate(SalaryDataNotifier n) => '${n.monthName} ${n.year}';

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final sc = SalaryStateController.instance;
      final n  = SalaryDataNotifier.instance;
      await SalaryPdfExportService.exportAttachmentB(
        config:          _config,
        billNo:          _billNoCtrl.text,
        date:            _buildDate(n),
        poNo:            n.poNo,
        itemDescription: _itemDescription,
        employeeCount:   sc.employeeCount,
        customerName:    _config.companyName,
        customerAddress: _config.address,
        customerGst:     _config.gstin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
          // ── Toolbar (Column version) ──────────────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // First row: Title, Month badge, and Download button
              Row(
                children: [
                  Text(title, style: AppTextStyles.h3),
                  const SizedBox(width: AppSpacing.md),
                  _MonthBadge(monthName: n.monthName, year: n.year),
                  const Spacer(),
                  // Download PDF button
                  if (_exporting)
                    const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2))
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
                ],
              ),
              // Second row: Company code filter chips (fixed set)
              const SizedBox(height: AppSpacing.sm),
              _CodeFilter(
                codes:    _allCodes,
                selected: code,
                onChanged: (c) => sc.setCompanyCode(c ?? 'All'),
              ),
            ],
          ),
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
                  ItemDescriptionField(
                    value: _itemDescription,
                    onChanged: (v) => setState(() => _itemDescription = v),
                    notifier: _descNotifier,
                  ),
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
                        listenable: Listenable.merge([
                          _billNoCtrl,
                          SalaryDataNotifier.instance,
                          SalaryStateController.instance,
                        ]),
                        builder: (_, __) => AttachmentBPreview(
                          config:          _config,
                          itemDescription: _itemDescription,
                          billNo:          _billNoCtrl.text,
                          poNo:            n.poNo,
                          employeeCount:   sc.employeeCount,
                          date:            _buildDate(n),
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
    child: TextField(
      controller: ctrl,
      style: AppTextStyles.input,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    ),
  );

  static Widget _summaryRow(String label, String value, Color color, {bool bold = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: AppTextStyles.small),
          Text(value, style: AppTextStyles.small.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            fontSize: bold ? 13 : 12,
          )),
        ]),
      );
}

// ── Code filter — always shows All + F&B + I&L + P&S + A&P ──────────────────
class _CodeFilter extends StatelessWidget {
  final List<String> codes;
  final String       selected;
  final void Function(String?) onChanged;
  const _CodeFilter({required this.codes, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        _chip('All', null, selected, onChanged),
        ...codes.map((c) => _chip(c, c, selected, onChanged)),
      ],
    ),
  );

  static Widget _chip(String label, String? value, String selected,
      void Function(String?) onTap) {
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

// ── Month Badge Widget ─────────────────────────────────────────────────────────
class _MonthBadge extends StatelessWidget {
  final String monthName;
  final int year;
  const _MonthBadge({required this.monthName, required this.year});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.slate800,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.slate700, width: 0.5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.calendar_month_outlined, size: 13, color: AppColors.slate400),
        const SizedBox(width: 5),
        Text(
          '$monthName $year',
          style: AppTextStyles.small.copyWith(
            color: AppColors.slate300,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
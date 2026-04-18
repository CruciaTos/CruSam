import 'package:crusam/features/salary/services/Salary_pdf_export_service.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../shared/utils/title_utils.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
import '../../vouchers/notifiers/voucher_notifier.dart';
import '../../vouchers/widgets/item_description_field.dart';
import '../widgets/salary_bill_preview.dart';

class SalaryBillsScreen extends StatefulWidget {
  const SalaryBillsScreen({super.key});
  @override
  State<SalaryBillsScreen> createState() => _SalaryBillsScreenState();
}

class _SalaryBillsScreenState extends State<SalaryBillsScreen> {
  final _descNotifier = ItemDescriptionNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting = false;

  String _itemDescription = 'Manpower Supply Charges';

  final _billNoCtrl     = TextEditingController(text: 'AE/-/25-26');
  final _poNoCtrl       = TextEditingController(text: '-');
  final _clientNameCtrl = TextEditingController(text: 'M/s Diversey India Hygiene Private Ltd.');
  final _clientAddrCtrl = TextEditingController(
      text: '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093');
  final _clientGstCtrl  = TextEditingController(text: '27AABCC1597Q1Z2');
  final _dateCtrl       = TextEditingController(
      text: SalaryDataNotifier.instance.dateDisplay);

  // Hardcoded company codes – same as in SalaryEmployeesScreen
  static const List<String> _companyCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  late final Listenable _fieldListenable = Listenable.merge([
    _billNoCtrl, _poNoCtrl, _clientNameCtrl, _clientAddrCtrl, _clientGstCtrl, _dateCtrl,
  ]);

  String _toDisplayDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    return '$d/$m/$y';
  }

  @override
  void initState() {
    super.initState();
    _descNotifier.load();
    _loadConfig();
    _poNoCtrl.addListener(() => SalaryDataNotifier.instance.setPoNo(_poNoCtrl.text));
    _dateCtrl.addListener(() => SalaryDataNotifier.instance.setDateDisplay(_dateCtrl.text));

    // ── Sync metadata from VoucherBuilder if it has active data ──────────────
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vc = VoucherNotifier.instance.current;
      final hasData = vc.rows.isNotEmpty || vc.title.isNotEmpty;
      if (!hasData) return;

      if (vc.billNo.isNotEmpty) _billNoCtrl.text = vc.billNo;
      if (vc.poNo.isNotEmpty) {
        _poNoCtrl.text = vc.poNo;
        SalaryDataNotifier.instance.setPoNo(vc.poNo);
      }
      if (vc.date.isNotEmpty) {
        _dateCtrl.text = _toDisplayDate(vc.date);
        SalaryDataNotifier.instance.setDateIso(vc.date);
      }
      if (vc.clientName.isNotEmpty) _clientNameCtrl.text = vc.clientName;
      if (vc.clientAddress.isNotEmpty) _clientAddrCtrl.text = vc.clientAddress;
      if (vc.clientGstin.isNotEmpty) _clientGstCtrl.text = vc.clientGstin;
      if (vc.deptCode.isNotEmpty) {
        SalaryDataNotifier.instance.setDeptCode(vc.deptCode);
        // Propagate dept code to salary state so downstream screens filter correctly
        SalaryStateController.instance.setCompanyCode(vc.deptCode);
      }

      // Persist in SalaryDataNotifier for downstream screens
      SalaryDataNotifier.instance.setBillNo(_billNoCtrl.text);
      SalaryDataNotifier.instance.setDateDisplay(_dateCtrl.text);
      SalaryDataNotifier.instance.setClientName(_clientNameCtrl.text);
      SalaryDataNotifier.instance.setClientAddr(_clientAddrCtrl.text);
      SalaryDataNotifier.instance.setClientGstin(_clientGstCtrl.text);
    });

    // Keep SalaryDataNotifier in sync as user edits fields
    _billNoCtrl.addListener(() => SalaryDataNotifier.instance.setBillNo(_billNoCtrl.text));
    _clientNameCtrl.addListener(
        () => SalaryDataNotifier.instance.setClientName(_clientNameCtrl.text));
    _clientAddrCtrl.addListener(
        () => SalaryDataNotifier.instance.setClientAddr(_clientAddrCtrl.text));
    _clientGstCtrl.addListener(
        () => SalaryDataNotifier.instance.setClientGstin(_clientGstCtrl.text));

    if (SalaryStateController.instance.employees.isEmpty) {
      SalaryStateController.instance.loadEmployees();
    }
  }

  @override
  void dispose() {
    _descNotifier.dispose();
    for (final c in [_billNoCtrl, _poNoCtrl, _clientNameCtrl, _clientAddrCtrl, _clientGstCtrl, _dateCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) setState(() => _config = CompanyConfigModel.fromMap(map));
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(SalaryDataNotifier.instance.dateIso) ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null) {
      final iso = picked.toIso8601String().split('T').first;
      _dateCtrl.text = _toDisplayDate(iso);
      SalaryDataNotifier.instance.setDateIso(iso);
    }
  }

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final sc = SalaryStateController.instance;
      await SalaryPdfExportService.exportSalaryInvoice(
        config:            _config,
        billNo:            _billNoCtrl.text,
        date:              _dateCtrl.text,
        poNo:              _poNoCtrl.text,
        itemDescription:   _itemDescription,
        customerName:      _clientNameCtrl.text,
        customerAddress:   _clientAddrCtrl.text,
        customerGst:       _clientGstCtrl.text,
        invoiceBaseAmount: sc.invoiceTotal,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700));
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
      final title = getTitle('Salary Invoice', code == 'All' ? null : code);

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
                  // Download button
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
              // Second row: Company code filter chips (hardcoded, same as employee screen)
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _codeChip('All', code == 'All', () => sc.setCompanyCode('All')),
                    ..._companyCodes.map((c) => _codeChip(c, code == c, () => sc.setCompanyCode(c))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Left pane
              Container(
                width: 272,
                color: Colors.grey[200],
                child: _LeftPane(
                  descNotifier:    _descNotifier,
                  itemDescription: _itemDescription,
                  billNoCtrl:      _billNoCtrl,
                  poNoCtrl:        _poNoCtrl,
                  clientNameCtrl:  _clientNameCtrl,
                  clientAddrCtrl:  _clientAddrCtrl,
                  clientGstCtrl:   _clientGstCtrl,
                  dateCtrl:        _dateCtrl,
                  sc:              sc,
                  onDescChanged:   (v) => setState(() => _itemDescription = v),
                  onPickDate:      () => _pickDate(context),
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
                        listenable: Listenable.merge([
                          _fieldListenable,
                          SalaryStateController.instance,
                          SalaryDataNotifier.instance,
                        ]),
                        builder: (_, __) => SalaryBillPreview(
                          config:            _config,
                          customerName:      _clientNameCtrl.text,
                          customerAddress:   _clientAddrCtrl.text,
                          customerGst:       _clientGstCtrl.text,
                          billNo:            _billNoCtrl.text,
                          date:              _dateCtrl.text,
                          poNo:              _poNoCtrl.text,
                          itemDescription:   _itemDescription,
                          invoiceBaseAmount: sc.invoiceTotal,
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

  static Widget _codeChip(String label, bool active, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.indigo600 : AppColors.slate800,
          border: Border.all(color: active ? AppColors.indigo600 : AppColors.slate600),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.slate400,
        )),
      ),
    ),
  );
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

class _LeftPane extends StatelessWidget {
  final ItemDescriptionNotifier descNotifier;
  final String                  itemDescription;
  final TextEditingController   billNoCtrl, poNoCtrl, clientNameCtrl,
                                clientAddrCtrl, clientGstCtrl, dateCtrl;
  final SalaryStateController   sc;
  final void Function(String)   onDescChanged;
  final VoidCallback            onPickDate;

  const _LeftPane({
    required this.descNotifier, required this.itemDescription,
    required this.billNoCtrl, required this.poNoCtrl,
    required this.clientNameCtrl, required this.clientAddrCtrl,
    required this.clientGstCtrl, required this.dateCtrl,
    required this.sc, required this.onDescChanged, required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(AppSpacing.md),
    children: [
      Text('Invoice Details', style: AppTextStyles.h4),
      const SizedBox(height: AppSpacing.lg),
      _label('Bill No.'), const SizedBox(height: 4), _field(billNoCtrl),
      const SizedBox(height: AppSpacing.md),
      _label('Date'), const SizedBox(height: 4),
      SizedBox(
        height: 38,
        child: TextField(
          controller: dateCtrl, readOnly: true, onTap: onPickDate,
          style: AppTextStyles.input,
          decoration: const InputDecoration(isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: Icon(Icons.calendar_today, size: 16)),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      _label('PO No.'), const SizedBox(height: 4), _field(poNoCtrl),
      const SizedBox(height: AppSpacing.lg),
      Text('Client', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: AppSpacing.sm),
      _label('Client Name'), const SizedBox(height: 4), _field(clientNameCtrl),
      const SizedBox(height: AppSpacing.md),
      _label('Client GSTIN'), const SizedBox(height: 4), _field(clientGstCtrl),
      const SizedBox(height: AppSpacing.md),
      _label('Item Description'), const SizedBox(height: 4),
      ItemDescriptionField(value: itemDescription, onChanged: onDescChanged, notifier: descNotifier),
      const SizedBox(height: AppSpacing.xl),
      const Divider(),
      const SizedBox(height: AppSpacing.sm),
      Text('Invoice Totals', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: AppSpacing.sm),
      _summaryRow('Attachment A', '₹${sc.attachmentATotal.toStringAsFixed(0)}', AppColors.indigo600),
      _summaryRow('Attachment B', '₹${sc.attachmentBTotal.toStringAsFixed(0)}', AppColors.indigo600),
      const Divider(height: AppSpacing.lg),
      _summaryRow('Invoice Base', '₹${sc.invoiceTotal.toStringAsFixed(0)}', AppColors.emerald700, bold: true),
      const SizedBox(height: 4),
      _summaryRow('CGST (9%)', '₹${(sc.invoiceTotal * 0.09).toStringAsFixed(2)}', AppColors.slate500),
      _summaryRow('SGST (9%)', '₹${(sc.invoiceTotal * 0.09).toStringAsFixed(2)}', AppColors.slate500),
      const Divider(height: AppSpacing.md),
      _summaryRow('Grand Total',
          '₹${(sc.invoiceTotal * 1.18).roundToDouble().toStringAsFixed(0)}',
          AppColors.emerald700, bold: true),
    ],
  );

  static Widget _label(String t) =>
      Text(t, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate600, fontWeight: FontWeight.w600));

  static Widget _field(TextEditingController ctrl) => SizedBox(
    height: 38,
    child: TextField(controller: ctrl, style: AppTextStyles.input,
        decoration: const InputDecoration(isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10))),
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
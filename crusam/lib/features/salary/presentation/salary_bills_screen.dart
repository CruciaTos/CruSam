import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../../vouchers/notifiers/item_description_notifier.dart';
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

  String _itemDescription = 'Manpower Supply Charges';

  final _billNoCtrl     = TextEditingController(text: 'AE/-/25-26');
  final _poNoCtrl       = TextEditingController(text: '-');
  final _clientNameCtrl = TextEditingController(text: 'M/s Diversey India Hygiene Private Ltd.');
  final _clientAddrCtrl = TextEditingController(
      text: '501,5th flr,Ackruti center point, MIDC Central Road,Andheri (East), Mumbai-400093');
  final _clientGstCtrl  = TextEditingController(text: '27AABCC1597Q1Z2');
  final _dateCtrl       = TextEditingController(
      text: DateTime.now().toIso8601String().split('T').first);

  late final Listenable _fieldListenable = Listenable.merge([
    _billNoCtrl, _poNoCtrl, _clientNameCtrl, _clientAddrCtrl, _clientGstCtrl, _dateCtrl,
  ]);

  @override
  void initState() {
    super.initState();
    _descNotifier.load();
    _loadConfig();
    _poNoCtrl.addListener(() => SalaryDataNotifier.instance.setPoNo(_poNoCtrl.text));
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
      initialDate: DateTime.tryParse(_dateCtrl.text) ?? DateTime.now(),
      firstDate: DateTime(2000), lastDate: DateTime(2100),
    );
    if (picked != null) _dateCtrl.text = picked.toIso8601String().split('T').first;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([SalaryStateController.instance, SalaryDataNotifier.instance]),
    builder: (context, _) {
      final sc   = SalaryStateController.instance;
      final code = sc.selectedCompanyCode;
      final title = code == 'All' ? 'Salary Invoice' : 'Salary Invoice - $code';

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
                        listenable: _fieldListenable,
                        builder: (_, __) => SalaryBillPreview(
                          config:          _config,
                          customerName:    _clientNameCtrl.text,
                          customerAddress: _clientAddrCtrl.text,
                          customerGst:     _clientGstCtrl.text,
                          billNo:          _billNoCtrl.text,
                          date:            _dateCtrl.text,
                          poNo:            _poNoCtrl.text,
                          itemDescription: _itemDescription,
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
      Text('Item', style: AppTextStyles.label.copyWith(color: AppColors.slate500)),
      const SizedBox(height: AppSpacing.sm),
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
      _summaryRow('Invoice Total', '₹${sc.invoiceTotal.toStringAsFixed(0)}', AppColors.emerald700, bold: true),
    ],
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
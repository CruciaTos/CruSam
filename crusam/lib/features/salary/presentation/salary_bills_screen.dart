import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import '../../pdf/service/pdf_file_saver.dart';
import '../../vouchers/notifiers/margin_settings_notifier.dart';
import '../widgets/salary_bill_preview.dart';
import '../widgets/shared_salary_widgets.dart';
import '../../../shared/widgets/full_screen_loader.dart';
import 'package:crusam_core/crusam_core.dart';
import '../../../core/theme/ink_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – matching the InvoicesScreen theme
// ════════════════════════════════════════════════════════════════════════════
typedef _Tok = InkTokens;

class SalaryBillsScreen extends StatefulWidget {
  const SalaryBillsScreen({super.key});
  @override
  State<SalaryBillsScreen> createState() => _SalaryBillsScreenState();
}

class _SalaryBillsScreenState extends State<SalaryBillsScreen> {
  static final _dateFormat = DateFormat('dd/MM/yyyy');

  final _marginNotifier = MarginSettingsNotifier();
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _exporting          = false;
  bool _finalisingInvoice  = false;

  final _billNoCtrl     = TextEditingController(text: 'AE/-/25-26');
  final _poNoCtrl       = TextEditingController(text: '-');
  final _clientNameCtrl = TextEditingController(
      text: 'M/s Diversey India Hygiene Private Ltd.');
  final _clientAddrCtrl = TextEditingController(
      text: '501,5th flr,Ackruti center point, MIDC Central Road,'
            'Andheri (East), Mumbai-400093');
  final _clientGstCtrl  = TextEditingController(text: '27AABCC1597Q1Z2');
  final _dateCtrl       = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(DateTime.now()));
  final _descCtrl       = TextEditingController();

  static const List<String> _companyCodes = ['F&B', 'I&L', 'P&S', 'A&P'];

  late final Listenable _fieldListenable = Listenable.merge([
    _billNoCtrl, _poNoCtrl, _clientNameCtrl,
    _clientAddrCtrl, _clientGstCtrl, _dateCtrl, _descCtrl,
  ]);

  void _setControllerText(TextEditingController ctrl, String value) {
    if (ctrl.text == value) return;
    ctrl.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _syncFromSalaryData() {
    final n = SalaryDataNotifier.instance;
    _setControllerText(_billNoCtrl,     n.billNo);
    _setControllerText(_poNoCtrl,       n.poNo);
    _setControllerText(_clientNameCtrl, n.clientName);
    _setControllerText(_clientAddrCtrl, n.clientAddr);
    _setControllerText(_clientGstCtrl,  n.clientGstin);
    _setControllerText(_dateCtrl,       n.dateDisplay);
    _setControllerText(_descCtrl,       n.itemDescription);
  }

  void _onBillNoChanged()     => SalaryDataNotifier.instance.setBillNo(_billNoCtrl.text);
  void _onPoNoChanged()       => SalaryDataNotifier.instance.setPoNo(_poNoCtrl.text);
  void _onClientNameChanged() => SalaryDataNotifier.instance.setClientName(_clientNameCtrl.text);
  void _onClientAddrChanged() => SalaryDataNotifier.instance.setClientAddr(_clientAddrCtrl.text);
  void _onClientGstChanged()  => SalaryDataNotifier.instance.setClientGstin(_clientGstCtrl.text);
  void _onDateChanged()       => SalaryDataNotifier.instance.setDateDisplay(_dateCtrl.text);
  void _onDescChanged()       => SalaryDataNotifier.instance.setItemDescription(_descCtrl.text);

  @override
  void initState() {
    super.initState();
    _marginNotifier.load();
    _loadConfig();
    _syncFromSalaryData();
    SalaryDataNotifier.instance.removeListener(_syncFromSalaryData);
    SalaryDataNotifier.instance.addListener(_syncFromSalaryData);
    _billNoCtrl.addListener(_onBillNoChanged);
    _poNoCtrl.addListener(_onPoNoChanged);
    _clientNameCtrl.addListener(_onClientNameChanged);
    _clientAddrCtrl.addListener(_onClientAddrChanged);
    _clientGstCtrl.addListener(_onClientGstChanged);
    _dateCtrl.addListener(_onDateChanged);
    _descCtrl.addListener(_onDescChanged);
    if (SalaryStateController.instance.employees.isEmpty) {
      SalaryStateController.instance.loadEmployees();
    }
  }

  @override
  void dispose() {
    SalaryDataNotifier.instance.removeListener(_syncFromSalaryData);
    _billNoCtrl.removeListener(_onBillNoChanged);
    _poNoCtrl.removeListener(_onPoNoChanged);
    _clientNameCtrl.removeListener(_onClientNameChanged);
    _clientAddrCtrl.removeListener(_onClientAddrChanged);
    _clientGstCtrl.removeListener(_onClientGstChanged);
    _dateCtrl.removeListener(_onDateChanged);
    _descCtrl.removeListener(_onDescChanged);
    _marginNotifier.dispose();
    for (final c in [
      _billNoCtrl, _poNoCtrl, _clientNameCtrl,
      _clientAddrCtrl, _clientGstCtrl, _dateCtrl, _descCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    DateTime initialDate;
    try {
      initialDate = _dateFormat.parse(_dateCtrl.text);
    } catch (_) {
      initialDate = DateTime.now();
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) _dateCtrl.text = _dateFormat.format(picked);
  }

  EdgeInsets get _margins => EdgeInsets.fromLTRB(
        _marginNotifier.settings.left,
        _marginNotifier.settings.top,
        _marginNotifier.settings.right,
        _marginNotifier.settings.bottom,
      );

  /// Derive department code from selected company code for display
  String get _departmentCode {
    final code = SalaryStateController.instance.selectedCompanyCode;
    return code == 'All' ? '' : code;
  }

  pw.EdgeInsets get _pdfMargins => pw.EdgeInsets.fromLTRB(
        _margins.left, _margins.top, _margins.right, _margins.bottom);

  SalaryBillHeader get _billHeader => SalaryBillHeader(
        billNo:          _billNoCtrl.text,
        date:            _dateCtrl.text,
        poNo:            _poNoCtrl.text,
        customerName:    _clientNameCtrl.text,
        customerAddress: _clientAddrCtrl.text,
        customerGst:     _clientGstCtrl.text,
        departmentCode:  _departmentCode,
        period:          SalaryDataNotifier.instance.periodLabel,
      );

  Future<void> _exportPdf() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    showLoader(context, message: 'Generating salary invoice PDF…');
    try {
      final sc = SalaryStateController.instance;
      final n  = SalaryDataNotifier.instance;
      await SalaryBillPdfService.export(
        config:   _config,
        margins:  _pdfMargins,
        pages: [
          SalaryBillPdfService.salaryInvoiceSpec(
            header:            _billHeader,
            itemDescription:   n.itemDescription,
            invoiceBaseAmount: sc.invoiceTotal,
          ),
        ],
        fileName: 'salary_invoice_${PdfFileSaver.slug(_billNoCtrl.text)}',
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
      hideLoader();
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _finaliseInvoice() async {
    if (_finalisingInvoice) return;
    setState(() => _finalisingInvoice = true);
    showLoader(context, message: 'Finalising invoice bundle…');
    try {
      final sc = SalaryStateController.instance;
      final n  = SalaryDataNotifier.instance;

      final daysMap = <int, int>{};
      for (final e in sc.filteredEmployees) {
        if (e.id != null) daysMap[e.id!] = n.getDays(e.id!);
      }

      final header = _billHeader;
      await SalaryBillPdfService.export(
        config:  _config,
        margins: _pdfMargins,
        pages: [
          SalaryBillPdfService.salaryInvoiceSpec(
            header:            header,
            itemDescription:   n.itemDescription,
            invoiceBaseAmount: sc.invoiceTotal,
          ),
          SalaryBillPdfService.attachmentASpec(
            header:          header,
            itemDescription: n.itemDescriptionAttachmentA,
            itemAmount:      sc.totalEarnedGross,
            pfAmount:        sc.attachmentAPf,
            esicAmount:      sc.attachmentAEsic,
          ),
          SalaryBillPdfService.attachmentBSpec(
            header:          header,
            itemDescription: n.itemDescriptionAttachmentB,
            employeeCount:   sc.employeeCount,
          ),
        ],
        statement: SalaryStatementInput(
          employees:   sc.filteredEmployees,
          monthName:   n.monthName,
          year:        n.year,
          isMsw:       n.isMsw,
          mswAmount:   n.mswAmount,
          isFeb:       n.isFeb,
          daysMap:     daysMap,
          daysInMonth: n.totalDays,
        ),
        departmentCode: _departmentCode,
        fileName: 'final_invoice_${PdfFileSaver.slug(_billNoCtrl.text)}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finalise failed: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      hideLoader();
      if (mounted) setState(() => _finalisingInvoice = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([
          SalaryStateController.instance,
          SalaryDataNotifier.instance,
        ]),
        builder: (context, _) {
          final sc   = SalaryStateController.instance;
          final n    = SalaryDataNotifier.instance;
          final code = sc.selectedCompanyCode;
          final title = code == 'All'
              ? 'Salary Invoice'
              : 'Salary Invoice - $code';

          return Padding(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(children: [
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
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                    else
                      OutlinedButton.icon(
                        onPressed: _exportPdf,
                        icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 16),
                        label: const Text('Download PDF'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(
                              color: Colors.red.shade400),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (_finalisingInvoice)
                      const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                    else
                      FilledButton.icon(
                        onPressed: _finaliseInvoice,
                        icon: const Icon(
                            Icons.picture_as_pdf_outlined,
                            size: 16),
                        label: const Text('Finalise Invoice'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.indigo600,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ]),
                  const SizedBox(height: AppSpacing.sm),
                  SalaryCodeFilter(
                    codes:     _companyCodes,
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
                  // ── Themed left pane ──────────────────────────────────────────
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
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _LeftPane(
                        descCtrl:        _descCtrl,
                        billNoCtrl:      _billNoCtrl,
                        poNoCtrl:        _poNoCtrl,
                        clientNameCtrl:  _clientNameCtrl,
                        clientAddrCtrl:  _clientAddrCtrl,
                        clientGstCtrl:   _clientGstCtrl,
                        dateCtrl:        _dateCtrl,
                        sc:              sc,
                        marginNotifier:  _marginNotifier,
                        onPickDate: () => _pickDate(context),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    color: AppColors.slate200,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm),
                      child: Center(
                        child: ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxWidth: 820),
                          child: ListenableBuilder(
                            listenable: Listenable.merge([
                              _fieldListenable,
                              SalaryStateController.instance,
                              SalaryDataNotifier.instance,
                              _marginNotifier,
                            ]),
                            builder: (_, _) => SalaryBillPreview(
                              config:            _config,
                              margins:           _margins,
                              customerName:      _clientNameCtrl.text,
                              customerAddress:   _clientAddrCtrl.text,
                              customerGst:       _clientGstCtrl.text,
                              billNo:            _billNoCtrl.text,
                              date:              _dateCtrl.text,
                              poNo:              _poNoCtrl.text,
                              itemDescription:   n.itemDescription,
                              period:            n.periodLabel,
                              invoiceBaseAmount: sc.invoiceTotal,
                              departmentCode:    _departmentCode,
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
  final TextEditingController   billNoCtrl, poNoCtrl, clientNameCtrl,
                                clientAddrCtrl, clientGstCtrl, dateCtrl;
  final SalaryStateController   sc;
  final MarginSettingsNotifier  marginNotifier;
  final VoidCallback            onPickDate;

  const _LeftPane({
    required this.descCtrl,
    required this.billNoCtrl,
    required this.poNoCtrl,
    required this.clientNameCtrl,
    required this.clientAddrCtrl,
    required this.clientGstCtrl,
    required this.dateCtrl,
    required this.sc,
    required this.marginNotifier,
    required this.onPickDate,
  });

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.zero,
        children: [
          Text('Invoice Details',
              style: _Tok.tsCardTitle.copyWith(fontSize: 15)),
          const SizedBox(height: 16),
          _label('Bill No.'),
          const SizedBox(height: 4),
          _field(billNoCtrl),
          const SizedBox(height: 12),
          _label('Date'),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: TextField(
              controller: dateCtrl,
              readOnly: true,
              onTap: onPickDate,
              style: _Tok.tsInput,
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                suffixIcon: Icon(Icons.calendar_today,
                    size: 16, color: _Tok.inkLight),
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
          ),
          const SizedBox(height: 12),
          _label('PO No.'),
          const SizedBox(height: 4),
          _field(poNoCtrl),
          const SizedBox(height: 16),
          Text('Client',
              style: _Tok.tsMeta.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          _label('Client Name'),
          const SizedBox(height: 4),
          _field(clientNameCtrl),
          const SizedBox(height: 12),
          _label('Client GSTIN'),
          const SizedBox(height: 4),
          _field(clientGstCtrl),
          const SizedBox(height: 12),
          _label('Client Address'),
          const SizedBox(height: 4),
          _field(clientAddrCtrl),
          const SizedBox(height: 4),
          Text(
            '//  or  /n  creates a new line in the PDF',
            style: _Tok.tsMeta.copyWith(
              fontStyle: FontStyle.italic,
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),
          _label('Item Description'),
          const SizedBox(height: 4),
          _descriptionField(descCtrl),
          const SizedBox(height: 16),
          const Divider(color: _Tok.divider),
          const SizedBox(height: 8),
          Text('Invoice Totals',
              style: _Tok.tsMeta.copyWith(fontSize: 12)),
          const SizedBox(height: 8),
          _summaryRow('Attachment A',
              '₹${sc.attachmentATotal.toStringAsFixed(0)}',
              _Tok.inkLight),
          _summaryRow('Attachment B',
              '₹${sc.attachmentBTotal.toStringAsFixed(0)}',
              _Tok.inkLight),
          const Divider(color: _Tok.divider, height: 20),
          _summaryRow('Invoice Base',
              '₹${sc.invoiceTotal.toStringAsFixed(0)}',
              _Tok.ink,
              bold: true),
          const SizedBox(height: 4),
          _summaryRow('CGST (9%)',
              '₹${(sc.invoiceTotal * 0.09).toStringAsFixed(2)}',
              _Tok.inkMuted),
          _summaryRow('SGST (9%)',
              '₹${(sc.invoiceTotal * 0.09).toStringAsFixed(2)}',
              _Tok.inkMuted),
          const Divider(color: _Tok.divider, height: 16),
          _summaryRow(
            'Grand Total',
            '₹${(sc.invoiceTotal * 1.18).roundToDouble().toStringAsFixed(0)}',
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

  static Widget _summaryRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: _Tok.tsMeta, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
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
import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/bank_models.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class TaxScreen extends StatefulWidget {
  const TaxScreen({super.key});

  @override
  State<TaxScreen> createState() => _TaxScreenState();
}

class _TaxScreenState extends State<TaxScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _isLoading = true;
  String? _error;

  String _fromDate = '${DateTime.now().year}-04-01';
  String _toDate = '${DateTime.now().year + 1}-03-31';

  TaxRegister? _gstRegister;
  TaxRegister? _tdsRegister;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadRegisters();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRegisters() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final gst = await services.bank.gstRegister(societyId, _fromDate, _toDate);
      final tds = await services.bank.tdsRegister(societyId, _fromDate, _toDate);

      if (mounted) {
        setState(() {
          _gstRegister = gst;
          _tdsRegister = tds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Tax Registers (GST & TDS)',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadRegisters);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Date filters
        Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey.shade300),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Text('From Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    initialValue: _fromDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _fromDate = v.trim());
                      _loadRegisters();
                    },
                  ),
                ),
                const SizedBox(width: 24),
                const Text('To Date: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    initialValue: _toDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _toDate = v.trim());
                      _loadRegisters();
                    },
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadRegisters,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        TabBar(
          controller: _tabCtrl,
          labelColor: Theme.of(context).primaryColor,
          tabs: const [
            Tab(text: 'GST Register'),
            Tab(text: 'TDS Register'),
          ],
        ),
        const SizedBox(height: 12),

        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildGstTab(),
              _buildTdsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGstTab() {
    final gst = _gstRegister;
    if (gst == null) return const SizedBox.shrink();

    final outward = gst.gstOutwardLines;
    final inward = gst.gstInwardLines;
    final outputTax = outward.fold<int>(0, (sum, l) => sum + l.totalTaxPaise);
    final inputTax = inward.fold<int>(0, (sum, l) => sum + l.totalTaxPaise);
    final netPayable = outputTax - inputTax;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GST Summary KPI Cards
          Row(
            children: [
              Expanded(child: _kpiCard('Output GST (Liability)', outputTax, Colors.blue.shade900)),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard('Input Tax Credit (Asset)', inputTax, Colors.green.shade900)),
              const SizedBox(width: 12),
              Expanded(
                child: _kpiCard(
                  netPayable >= 0 ? 'Net GST Payable' : 'Net ITC Carry Forward',
                  netPayable.abs(),
                  netPayable >= 0 ? Colors.red.shade900 : Colors.teal.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          Text('Outward Supplies (Member Bills & Invoices) - ${outward.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildGstTable(outward),
          const SizedBox(height: 24),

          Text('Inward Supplies (Vendor Bills) - ${inward.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          _buildGstTable(inward),
        ],
      ),
    );
  }

  Widget _buildTdsTab() {
    final tds = _tdsRegister;
    if (tds == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TDS Summary KPI Cards
          Row(
            children: [
              Expanded(child: _kpiCard('TDS Deducted (Payable 2604)', tds.totalTdsPayablePaise, Colors.red.shade900)),
              const SizedBox(width: 12),
              Expanded(child: _kpiCard('TDS Withheld on Income (Receivable 1604)', tds.totalTdsReceivablePaise, Colors.green.shade900)),
            ],
          ),
          const SizedBox(height: 20),

          Text('TDS Deductions & Credits - ${tds.tdsLines.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SocietyDataTable<TdsRegisterLine>(
            columns: [
              SocietyColumn(label: 'Date', cell: (l) => Text(l.date)),
              SocietyColumn(label: 'Voucher', cell: (l) => Text(l.docNo)),
              SocietyColumn(label: 'Section', cell: (l) => Text(l.sectionCode)),
              SocietyColumn(label: 'Party Name', cell: (l) => Text(l.deducteeName)),
              SocietyColumn(label: 'PAN', cell: (l) => Text(l.pan ?? '-')),
              SocietyColumn(label: 'Gross Amount', numeric: true, cell: (l) => Text(formatPaise(l.grossAmountPaise))),
              SocietyColumn(label: 'Rate', cell: (l) => Text('${(l.tdsRateBp / 100).toStringAsFixed(2)}%')),
              SocietyColumn(
                label: 'TDS Amount',
                numeric: true,
                cell: (l) => Text(formatPaise(l.tdsPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
            rows: tds.tdsLines,
            total: tds.tdsLines.length,
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, int paise, Color color) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            Text(
              formatPaise(paise),
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGstTable(List<TaxRegisterLine> lines) {
    if (lines.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('No supplies found for this period.', style: TextStyle(color: Colors.grey))),
      );
    }

    return SocietyDataTable<TaxRegisterLine>(
      columns: [
        SocietyColumn(label: 'Date', cell: (l) => Text(l.date)),
        SocietyColumn(label: 'Doc No', cell: (l) => Text(l.docNo)),
        SocietyColumn(label: 'Party Name', cell: (l) => Text(l.partyOrMemberName)),
        SocietyColumn(label: 'GSTIN', cell: (l) => Text(l.gstin ?? '-')),
        SocietyColumn(label: 'Taxable Val', numeric: true, cell: (l) => Text(formatPaise(l.taxablePaise))),
        SocietyColumn(label: 'CGST', numeric: true, cell: (l) => Text(l.cgstPaise > 0 ? formatPaise(l.cgstPaise) : '-')),
        SocietyColumn(label: 'SGST', numeric: true, cell: (l) => Text(l.sgstPaise > 0 ? formatPaise(l.sgstPaise) : '-')),
        SocietyColumn(label: 'IGST', numeric: true, cell: (l) => Text(l.igstPaise > 0 ? formatPaise(l.igstPaise) : '-')),
        SocietyColumn(
          label: 'Total',
          numeric: true,
          cell: (l) => Text(formatPaise(l.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
      rows: lines,
      total: lines.length,
    );
  }
}

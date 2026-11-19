import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../documents/excel/report_excel.dart';
import '../../documents/pdf/report_pdf.dart';
import '../../domain/reports/report_definitions.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedCategory = 'Billing';
  ReportDefinition? _selectedReport;
  bool _isLoading = false;
  String? _error;

  String _fromDate = '${DateTime.now().year}-04-01';
  String _toDate = '${DateTime.now().year + 1}-03-31';
  String _asOfDate = DateTime.now().toIso8601String().substring(0, 10);

  ReportResult? _result;

  final categories = const ['Billing', 'Collections', 'Expenses', 'Bank', 'Tax', 'Accounts'];

  @override
  void initState() {
    super.initState();
    _selectFirstReport();
  }

  void _selectFirstReport() {
    final catReports = ReportCatalog.allReports.where((r) => r.category == _selectedCategory).toList();
    if (catReports.isNotEmpty) {
      _selectedReport = catReports.first;
      _runReport();
    }
  }

  Future<void> _runReport() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedReport == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final res = await services.reports.runReport(
        societyId,
        _selectedReport!.key,
        {
          'fromDate': _fromDate,
          'toDate': _toDate,
          'asOfDate': _asOfDate,
        },
      );

      if (mounted) {
        setState(() {
          _result = res;
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

  Future<void> _exportPdf() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _result == null) return;

    try {
      final services = await SocietyServices.instance();
      final society = await services.society.getSociety(societyId);

      final pdfBytes = await ReportPdf.generateBytes(
        society: society,
        report: _result!,
      );

      await Printing.layoutPdf(
        onLayout: (_) => pdfBytes,
        name: '${_result!.definition.key}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error exporting PDF: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Standard Reports',
      actions: [
        if (_result != null && _result!.rows.isNotEmpty) ...[
          FilledButton.icon(
            onPressed: _exportPdf,
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Export PDF'),
          ),
        ],
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category Chips
        Wrap(
          spacing: 8,
          children: categories.map((cat) {
            final isSel = cat == _selectedCategory;
            return ChoiceChip(
              label: Text(cat),
              selected: isSel,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedCategory = cat;
                    final list = ReportCatalog.allReports.where((r) => r.category == cat).toList();
                    _selectedReport = list.isNotEmpty ? list.first : null;
                  });
                  _runReport();
                }
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // Report Selector & Parameters Filter Bar
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
                const Text('Report: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _selectedReport?.key,
                  items: ReportCatalog.allReports
                      .where((r) => r.category == _selectedCategory)
                      .map((r) => DropdownMenuItem(value: r.key, child: Text(r.title)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => _selectedReport = ReportCatalog.find(v));
                      _runReport();
                    }
                  },
                ),
                const SizedBox(width: 20),
                const Text('From: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: _fromDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() => _fromDate = v.trim());
                      _runReport();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                const Text('To / As of: ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: _toDate,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    onFieldSubmitted: (v) {
                      setState(() {
                        _toDate = v.trim();
                        _asOfDate = v.trim();
                      });
                      _runReport();
                    },
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _runReport,
                  icon: const Icon(Icons.play_arrow_outlined, size: 18),
                  label: const Text('Run'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Results Section
        Expanded(
          child: _isLoading
              ? const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()))
              : _error != null
                  ? SocietyErrorView(message: _error!, onRetry: _runReport)
                  : _result == null || _result!.rows.isEmpty
                      ? const Center(child: Text('No records found matching the report criteria.'))
                      : _buildTable(),
        ),
      ],
    );
  }

  Widget _buildTable() {
    final res = _result!;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(res.definition.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                Text('${res.rows.length} records', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                child: DataTable(
                  columns: res.columns.map((col) => DataColumn(
                    label: Text(col.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                    numeric: col.isNumeric,
                  )).toList(),
                  rows: res.rows.map((row) => DataRow(
                    cells: res.columns.map((col) {
                      final val = row[col.key]?.toString() ?? '-';
                      return DataCell(Text(val));
                    }).toList(),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

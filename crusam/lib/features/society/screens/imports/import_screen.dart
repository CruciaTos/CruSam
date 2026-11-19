import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../domain/imports/import_service.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String _selectedType = 'units';
  final _csvTextController = TextEditingController();

  bool _busy = false;
  String? _error;
  String? _successMessage;
  List<Map<String, String>> _previewRows = [];

  final Map<String, String> _typeLabels = {
    'units': 'Units Master',
    'people': 'Members & Residents',
    'opening_units': 'Unit Opening Balances',
    'opening_ledger': 'Ledger Opening Balances',
    'meter_readings': 'Meter Readings',
    'receipts': 'Member Receipts',
  };

  final Map<String, String> _typeColumns = {
    'units': 'Block*, Unit No*, Unit Type*, Area 1, Area 2, Floor, Occupancy*, Active',
    'people': 'Block*, Unit No*, Full Name*, Role*, Primary Contact, Bill To, Phone, Email, Alternate Email, PAN, GSTIN, Address, Share Certificate No, From Date*',
    'opening_units': 'Block*, Unit No*, Debit, Credit, As Of*, Narration',
    'opening_ledger': 'Account Code*, Debit, Credit, As Of*, Narration',
    'meter_readings': 'Block*, Unit*, Meter Type*, Period From*, Period To*, Reading Date*, Reading*',
    'receipts': 'Block, Unit*, Date*, Amount*, TDS, Mode, Cheque No, Bank Name, Remarks',
  };

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _successMessage = null;
    });

    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'xls'],
        withData: true,
      );

      if (res != null && res.files.isNotEmpty) {
        final file = res.files.first;
        final bytes = file.bytes;
        final name = file.name.toLowerCase();

        if (bytes == null) return;

        final services = await SocietyServices.instance();
        List<Map<String, String>> parsed = [];

        if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
          parsed = services.import.parseExcelBytes(bytes);
        } else {
          final text = utf8.decode(bytes);
          _csvTextController.text = text;
          parsed = services.import.parseCsv(text);
        }

        setState(() {
          _previewRows = parsed;
        });
      }
    } catch (e) {
      setState(() => _error = 'Failed to read file: $e');
    }
  }

  void _onTextParsed() {
    final text = _csvTextController.text.trim();
    if (text.isEmpty) return;

    try {
      // Synchronous parse via helper
      final lines = text
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      if (lines.isEmpty) return;

      final headers = lines.first.split(',').map((h) => h.trim().replaceAll('"', '').toLowerCase()).toList();
      final parsed = <Map<String, String>>[];
      for (var i = 1; i < lines.length; i++) {
        final vals = lines[i].split(',').map((v) => v.trim().replaceAll('"', '')).toList();
        final row = <String, String>{};
        for (var j = 0; j < headers.length; j++) {
          row[headers[j]] = j < vals.length ? vals[j] : '';
        }
        parsed.add(row);
      }

      setState(() {
        _previewRows = parsed;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Error parsing CSV: $e');
    }
  }

  Future<void> _runImport() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_previewRows.isEmpty) {
      _onTextParsed();
    }

    if (_previewRows.isEmpty) {
      setState(() => _error = 'No data rows to import. Please pick a file or paste CSV content.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _successMessage = null;
    });

    try {
      final services = await SocietyServices.instance();
      ImportResult res;

      switch (_selectedType) {
        case 'units':
          res = await services.import.importUnits(societyId, _previewRows);
          break;
        case 'people':
          res = await services.import.importPeople(societyId, _previewRows);
          break;
        case 'opening_units':
          res = await services.import.importOpeningUnits(societyId, _previewRows);
          break;
        case 'opening_ledger':
          res = await services.import.importOpeningLedger(societyId, _previewRows);
          break;
        case 'meter_readings':
          res = await services.import.importMeterReadings(societyId, _previewRows);
          break;
        case 'receipts':
          res = await services.import.importReceipts(societyId, _previewRows);
          break;
        default:
          throw StateError('Unknown import type: $_selectedType');
      }

      setState(() {
        _busy = false;
        _successMessage = res.message;
        _previewRows = [];
        _csvTextController.clear();
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Import Data',
      subtitle: 'Import Units, Members, and Opening Balances from CSV or Excel',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Select type card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Import Type',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: _typeLabels.entries.map((e) {
                        final isSel = _selectedType == e.key;
                        return ChoiceChip(
                          label: Text(e.value),
                          selected: isSel,
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _selectedType = e.key;
                                _previewRows = [];
                                _error = null;
                                _successMessage = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.info_outline, size: 18, color: Colors.blue),
                              SizedBox(width: 8),
                              Text(
                                'Required Columns (* denotes mandatory):',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          SelectableText(
                            _typeColumns[_selectedType] ?? '',
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // File pick or Paste CSV
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.file_open_outlined, size: 18),
                          label: const Text('Choose CSV or Excel File'),
                          onPressed: _busy ? null : _pickFile,
                        ),
                        const SizedBox(width: 16),
                        const Text('or paste CSV text below', style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _csvTextController,
                      decoration: const InputDecoration(
                        hintText: 'Paste header and comma-separated rows here...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 6,
                      onChanged: (_) => _onTextParsed(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SocietyErrorView(
                  message: _error!,
                  onRetry: () => setState(() => _error = null),
                ),
              ),

            if (_successMessage != null)
              Card(
                color: Colors.green.withValues(alpha: 0.1),
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Preview Table
            if (_previewRows.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Parsed Preview (${_previewRows.length} rows ready)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.upload, size: 18),
                            label: _busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : Text('Import ${_previewRows.length} Rows'),
                            onPressed: _busy ? null : _runImport,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: _previewRows.first.keys.map((k) {
                            return DataColumn(label: Text(k.toUpperCase(), style: const TextStyle(fontSize: 12)));
                          }).toList(),
                          rows: _previewRows.take(10).map((r) {
                            return DataRow(
                              cells: r.values.map((v) => DataCell(Text(v, style: const TextStyle(fontSize: 12)))).toList(),
                            );
                          }).toList(),
                        ),
                      ),
                      if (_previewRows.length > 10)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Showing first 10 rows of ${_previewRows.length}',
                            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_selector/file_selector.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/domain/backup/backup_service.dart';
import 'package:crusam/features/society/domain/communication/communication_service.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';

class SocietySettingsScreen extends StatefulWidget {
  const SocietySettingsScreen({super.key});

  @override
  State<SocietySettingsScreen> createState() => _SocietySettingsScreenState();
}

class _SocietySettingsScreenState extends State<SocietySettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = false;
  Society? _society;
  List<Map<String, dynamic>> _numberSeries = [];
  List<DocumentFooterRow> _footers = [];
  List<EmailLogRow> _emailLogs = [];

  // Controllers for Billing
  late TextEditingController _billingDueOffsetCtrl;
  late TextEditingController _billingNotesCtrl;
  String _billingFrequency = 'monthly';
  String _billingRoundMode = 'none';

  // Controllers for Interest
  bool _interestEnabled = true;
  late TextEditingController _interestRateCtrl;
  late TextEditingController _interestGraceCtrl;
  String _interestMethod = 'simple';

  // Controllers for Tax
  late TextEditingController _taxExemptCtrl;
  late TextEditingController _tdsThresholdCtrl;

  // Controllers for Documents
  late TextEditingController _docBillTitleCtrl;
  late TextEditingController _docReceiptTitleCtrl;
  late TextEditingController _docSignatoryCtrl;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _initControllers();
    _load();
  }

  void _initControllers() {
    _billingDueOffsetCtrl = TextEditingController(text: '20');
    _billingNotesCtrl = TextEditingController();
    _interestRateCtrl = TextEditingController(text: '18');
    _interestGraceCtrl = TextEditingController(text: '0');
    _taxExemptCtrl = TextEditingController(text: '7500');
    _tdsThresholdCtrl = TextEditingController(text: '30000');
    _docBillTitleCtrl = TextEditingController(text: 'Maintenance Bill');
    _docReceiptTitleCtrl = TextEditingController(text: 'Receipt');
    _docSignatoryCtrl = TextEditingController(text: 'Authorised Signatory');
  }

  @override
  void dispose() {
    _tabController.dispose();
    _billingDueOffsetCtrl.dispose();
    _billingNotesCtrl.dispose();
    _interestRateCtrl.dispose();
    _interestGraceCtrl.dispose();
    _taxExemptCtrl.dispose();
    _tdsThresholdCtrl.dispose();
    _docBillTitleCtrl.dispose();
    _docReceiptTitleCtrl.dispose();
    _docSignatoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ctx = SocietyContext.instance;
    final societyId = ctx.societyId;
    if (societyId == null) return;

    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final soc = await services.society.getSociety(societyId);
      final setts = await services.society.getAllSettings(societyId);
      final series = await services.db.query(
        'number_series',
        where: 'society_id = ?',
        whereArgs: [societyId],
        orderBy: 'doc_type ASC',
      );
      final footers = await services.communication.listDocumentFooters(societyId);
      final emailLogs = await services.communication.listEmailLogs(societyId, limit: 50);

      if (mounted) {
        setState(() {
          _society = soc;
          _numberSeries = series;
          _footers = footers;
          _emailLogs = emailLogs;

          // Populate controllers from settings
          _billingFrequency = setts['billing.frequency'] ?? 'monthly';
          _billingDueOffsetCtrl.text = setts['billing.due_day_offset'] ?? '20';
          _billingRoundMode = setts['billing.round_mode'] ?? 'none';
          _billingNotesCtrl.text = setts['billing.bill_notes'] ?? '';

          _interestEnabled = (setts['interest.enabled'] ?? '1') == '1';
          _interestRateCtrl.text = setts['interest.rate_percent'] ?? '18';
          _interestGraceCtrl.text = setts['interest.grace_period_days'] ?? '0';
          _interestMethod = setts['interest.method'] ?? 'simple';

          _taxExemptCtrl.text = setts['tax.member_exempt_rupees'] ?? '7500';
          _tdsThresholdCtrl.text = setts['tax.tds_threshold_rupees'] ?? '30000';

          _docBillTitleCtrl.text = setts['document.bill_title'] ?? 'Maintenance Bill';
          _docReceiptTitleCtrl.text = setts['document.receipt_title'] ?? 'Receipt';
          _docSignatoryCtrl.text = setts['document.signatory'] ?? 'Authorised Signatory';

          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings(Map<String, String?> newSettings, String successMessage) async {
    final societyId = _society?.id;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      await services.society.setSettings(societyId, newSettings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage), backgroundColor: const Color(0xFF10B981)),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Society Settings',
      subtitle: 'Manage accounting policies, billing rules, documents, email and backups',
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF2563EB),
                  unselectedLabelColor: const Color(0xFF64748B),
                  indicatorColor: const Color(0xFF2563EB),
                  tabs: const [
                    Tab(text: 'General'),
                    Tab(text: 'Billing'),
                    Tab(text: 'Interest'),
                    Tab(text: 'GST & TDS'),
                    Tab(text: 'Numbering'),
                    Tab(text: 'Documents'),
                    Tab(text: 'Email'),
                    Tab(text: 'Backup & Restore'),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildGeneralTab(),
                      _buildBillingTab(),
                      _buildInterestTab(),
                      _buildTaxTab(),
                      _buildNumberingTab(),
                      _buildDocumentsTab(),
                      _buildEmailTab(),
                      _buildBackupTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ----------------------------------------------------------------------
  // 1. General Tab
  // ----------------------------------------------------------------------
  Widget _buildGeneralTab() {
    if (_society == null) return const SizedBox.shrink();
    final s = _society!;

    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'General Society Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Profile'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => context.go('/society/societies/${s.id}'),
                  ),
                ],
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              _infoRow('Society Name', s.name),
              if (s.shortName != null && s.shortName!.isNotEmpty)
                _infoRow('Short Name / Alias', s.shortName!),
              _infoRow('Registration No', s.registrationNo ?? '—'),
              _infoRow('Address', '${s.addressLine1 ?? ''} ${s.addressLine2 ?? ''}'.trim().isEmpty ? '—' : '${s.addressLine1 ?? ''} ${s.addressLine2 ?? ''}'.trim()),
              _infoRow('City, State, Pincode', '${s.city ?? ''}, ${s.state} - ${s.pincode ?? ''}'),
              _infoRow('State Code', s.stateCode),
              _infoRow('Phone', s.phone ?? '—'),
              _infoRow('Email', s.email ?? '—'),
              _infoRow('PAN / TAN', '${s.pan ?? '—'} / ${s.tan ?? '—'}'),
              _infoRow('GST Registered', s.gstRegistered ? 'Yes (${s.gstin ?? 'No GSTIN'})' : 'No'),
              if (s.gstRegistered && s.gstEffectiveFrom != null)
                _infoRow('GST Effective From', formatDisplayDate(s.gstEffectiveFrom!)),
              _infoRow('Books Start Date', formatDisplayDate(s.booksStartDate)),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 2. Billing Tab
  // ----------------------------------------------------------------------
  Widget _buildBillingTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Member Billing Policies',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _billingFrequency,
                      decoration: const InputDecoration(labelText: 'Default Billing Frequency', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                        DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                        DropdownMenuItem(value: 'half_yearly', child: Text('Half-Yearly')),
                        DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _billingFrequency = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _billingDueOffsetCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Payment Due Days Offset',
                        hintText: 'e.g. 20 days after bill date',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _billingRoundMode,
                decoration: const InputDecoration(labelText: 'Bill Total Rounding Mode', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('Exact Paise (No Rounding)')),
                  DropdownMenuItem(value: 'nearest_rupee', child: Text('Round to Nearest Rupee')),
                  DropdownMenuItem(value: 'round_up', child: Text('Round Up to Next Rupee')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _billingRoundMode = val);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _billingNotesCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Default Bill Notice / Terms',
                  hintText: 'Payment instructions or bank account details to print on every bill...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _saveSettings({
                    'billing.frequency': _billingFrequency,
                    'billing.due_day_offset': _billingDueOffsetCtrl.text.trim(),
                    'billing.round_mode': _billingRoundMode,
                    'billing.bill_notes': _billingNotesCtrl.text.trim(),
                  }, 'Billing settings saved successfully');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                child: const Text('Save Billing Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 3. Interest Tab
  // ----------------------------------------------------------------------
  Widget _buildInterestTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Late Payment Interest Rules',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              SwitchListTile(
                title: const Text('Enable Late Payment Interest Calculation', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('When enabled, bill runs automatically calculate interest on overdue balances.'),
                value: _interestEnabled,
                onChanged: (val) => setState(() => _interestEnabled = val),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _interestRateCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Annual Interest Rate (%)',
                        hintText: 'e.g. 18 or 21',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _interestGraceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Grace Period (Days)',
                        hintText: 'e.g. 0',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _interestMethod,
                decoration: const InputDecoration(labelText: 'Interest Method', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'simple', child: Text('Simple Interest (Daily pro-rata)')),
                  DropdownMenuItem(value: 'compound', child: Text('Monthly Compound')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _interestMethod = val);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _saveSettings({
                    'interest.enabled': _interestEnabled ? '1' : '0',
                    'interest.rate_percent': _interestRateCtrl.text.trim(),
                    'interest.grace_period_days': _interestGraceCtrl.text.trim(),
                    'interest.method': _interestMethod,
                  }, 'Interest settings saved successfully');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                child: const Text('Save Interest Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 4. GST & TDS Tab
  // ----------------------------------------------------------------------
  Widget _buildTaxTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Statutory Tax Configuration',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              TextField(
                controller: _taxExemptCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'RWA / Housing Society Monthly Maintenance Exemption Limit (₹)',
                  hintText: '7500 (per member per month under GST Notification 12/2017)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tdsThresholdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Vendor Payment TDS Exemption Threshold (₹)',
                  hintText: '30000 (Section 194C single invoice limit)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  _saveSettings({
                    'tax.member_exempt_rupees': _taxExemptCtrl.text.trim(),
                    'tax.tds_threshold_rupees': _tdsThresholdCtrl.text.trim(),
                  }, 'Tax settings saved successfully');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                child: const Text('Save Tax Settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 5. Numbering Tab
  // ----------------------------------------------------------------------
  Widget _buildNumberingTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Document Numbering Series',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              DataTable(
                columns: const [
                  DataColumn(label: Text('Document Type', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Prefix', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Next Number', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Padding', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _numberSeries.map((row) {
                  final id = row['id'] as int;
                  final docType = row['doc_type'] as String;
                  final prefix = row['prefix'] as String? ?? '';
                  final nextNo = row['next_no'] as int;
                  final padding = row['padding'] as int;

                  return DataRow(
                    cells: [
                      DataCell(Text(docType)),
                      DataCell(Text(prefix)),
                      DataCell(Text('$nextNo')),
                      DataCell(Text('$padding')),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.edit, size: 16, color: Color(0xFF2563EB)),
                          onPressed: () => _editNumberSeries(id, docType, prefix, nextNo),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editNumberSeries(int id, String docType, String currentPrefix, int currentNextNo) async {
    final prefixCtrl = TextEditingController(text: currentPrefix);
    final nextNoCtrl = TextEditingController(text: currentNextNo.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Number Series: $docType'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: prefixCtrl, decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: nextNoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Next Sequence Number', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final services = await SocietyServices.instance();
      await services.db.update(
        'number_series',
        {'prefix': prefixCtrl.text.trim(), 'next_no': int.tryParse(nextNoCtrl.text.trim()) ?? currentNextNo},
        where: 'id = ?',
        whereArgs: [id],
      );
      _load();
    }
  }

  // ----------------------------------------------------------------------
  // 6. Documents Tab
  // ----------------------------------------------------------------------
  Widget _buildDocumentsTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Print & PDF Document Customization',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _docBillTitleCtrl,
                      decoration: const InputDecoration(labelText: 'Bill Document Title', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _docReceiptTitleCtrl,
                      decoration: const InputDecoration(labelText: 'Receipt Document Title', border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _docSignatoryCtrl,
                decoration: const InputDecoration(labelText: 'Authorized Signatory Label', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  _saveSettings({
                    'document.bill_title': _docBillTitleCtrl.text.trim(),
                    'document.receipt_title': _docReceiptTitleCtrl.text.trim(),
                    'document.signatory': _docSignatoryCtrl.text.trim(),
                  }, 'Document titles saved');
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                child: const Text('Save Titles'),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Custom Document Footers', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Footer'),
                    onPressed: _addDocumentFooter,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_footers.isEmpty)
                const Text('No custom footers configured.', style: TextStyle(color: Color(0xFF94A3B8)))
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Doc Type', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Effective From', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Footer Text', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _footers.map((f) => DataRow(cells: [
                    DataCell(Text(f.docType)),
                    DataCell(Text(f.effectiveFrom)),
                    DataCell(Text(f.footerText, overflow: TextOverflow.ellipsis)),
                  ])).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addDocumentFooter() async {
    String docType = 'member_bill';
    final effectiveCtrl = TextEditingController(text: DateTime.now().toIso8601String().substring(0, 10));
    final footerCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Document Footer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: docType,
                decoration: const InputDecoration(labelText: 'Document Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'member_bill', child: Text('Member Bill')),
                  DropdownMenuItem(value: 'member_receipt', child: Text('Member Receipt')),
                  DropdownMenuItem(value: 'other_invoice', child: Text('Other Income Invoice')),
                  DropdownMenuItem(value: 'other_receipt', child: Text('Other Income Receipt')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => docType = val);
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: effectiveCtrl, decoration: const InputDecoration(labelText: 'Effective From (YYYY-MM-DD)', border: OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: footerCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Footer Text', border: OutlineInputBorder())),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
              child: const Text('Add Footer'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && footerCtrl.text.trim().isNotEmpty) {
      final services = await SocietyServices.instance();
      await services.communication.setDocumentFooter(
        _society!.id,
        docType,
        effectiveCtrl.text.trim(),
        footerCtrl.text.trim(),
      );
      _load();
    }
  }

  // ----------------------------------------------------------------------
  // 7. Email Tab
  // ----------------------------------------------------------------------
  Widget _buildEmailTab() {
    return SingleChildScrollView(
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Email Outbox & Delivery History',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Direct Gmail integration dispatches bills, receipts, and dues notices. All delivery attempts are audited below.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const Divider(color: Color(0xFFE2E8F0), height: 24),
              if (_emailLogs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No email delivery records logged yet.', style: TextStyle(color: Color(0xFF94A3B8)))),
                )
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Doc Type', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Recipient', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Subject', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Details / Error', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: _emailLogs.map((log) {
                    final isSent = log.status == 'sent';
                    return DataRow(cells: [
                      DataCell(Text(log.createdAt.length >= 16 ? log.createdAt.substring(0, 16) : log.createdAt)),
                      DataCell(Text(log.docType)),
                      DataCell(Text(log.toAddress)),
                      DataCell(Text(log.subject, overflow: TextOverflow.ellipsis)),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSent ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            log.status.toUpperCase(),
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSent ? const Color(0xFF166534) : const Color(0xFF991B1B)),
                          ),
                        ),
                      ),
                      DataCell(Text(log.errorMessage ?? log.providerMessageId ?? '—', overflow: TextOverflow.ellipsis)),
                    ]);
                  }).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // 8. Backup & Restore Tab
  // ----------------------------------------------------------------------
  Widget _buildBackupTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Export Card
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Export Society Backup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  const Text(
                    'Creates an offline compressed JSON backup file containing every account, member, bill, receipt, journal entry, and statutory register for this society.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('Export Backup (.gz)'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2563EB), foregroundColor: Colors.white),
                    onPressed: _handleExportBackup,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Restore Card
          Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Restore As New Society', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
                  const SizedBox(height: 8),
                  const Text(
                    'Restores a backup into a brand new society with independent ID remapping. The current society is never modified or overwritten.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: const Text('Select Backup File to Restore...'),
                    onPressed: _handleRestoreBackup,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleExportBackup() async {
    final societyId = _society?.id;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final bytes = await services.backup.exportSociety(societyId);
      final filename = '${_society!.name.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "_")}_Backup.gz';

      final saveLocation = await getSaveLocation(suggestedName: filename);
      if (saveLocation != null) {
        final xFile = XFile.fromData(bytes, name: filename);
        await xFile.saveTo(saveLocation.path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Backup exported successfully to ${saveLocation.path}'), backgroundColor: const Color(0xFF10B981)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _handleRestoreBackup() async {
    try {
      const typeGroup = XTypeGroup(label: 'CruSam Society Backup', extensions: ['gz', 'json']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final services = await SocietyServices.instance();
      final preview = await services.backup.inspect(bytes);

      if (!mounted) return;

      final newNameCtrl = TextEditingController(text: '${preview.originalSocietyName} (Restored)');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Restore Society as New Copy'),
          content: SizedBox(
            width: 480,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow('Source Society', preview.originalSocietyName),
                _infoRow('Exported At', preview.exportedAt),
                _infoRow('Units Count', '${preview.unitCount}'),
                _infoRow('Members Count', '${preview.memberCount}'),
                _infoRow('Bills Count', '${preview.billCount}'),
                _infoRow('Receipts Count', '${preview.receiptCount}'),
                _infoRow('Journal Entries', '${preview.journalEntryCount}'),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                TextField(
                  controller: newNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'New Society Name',
                    hintText: 'Enter name for restored society copy',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              child: const Text('Confirm Restore'),
            ),
          ],
        ),
      );

      if (ok == true && newNameCtrl.text.trim().isNotEmpty) {
        final newSocId = await services.backup.restoreAsNewSociety(preview, newNameCtrl.text.trim());
        await SocietyContext.instance.reload();
        await SocietyContext.instance.selectSociety(newSocId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully restored as new society: ${newNameCtrl.text}'), backgroundColor: const Color(0xFF10B981)),
          );
          context.go('/society/overview');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restore failed: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

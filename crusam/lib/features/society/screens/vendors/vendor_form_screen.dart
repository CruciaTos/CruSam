import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/society_page.dart';

class VendorFormScreen extends StatefulWidget {
  final int? vendorId;
  const VendorFormScreen({super.key, this.vendorId});

  @override
  State<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends State<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _altEmailsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _stateCtrl = TextEditingController(text: 'MH');
  final _panCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  final _payeeCtrl = TextEditingController();
  final _bankAccCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();

  int? _defaultGstRateBp;
  String? _legalType = 'company';
  int? _defaultExpenseAccountId;
  int? _tdsSectionId;
  int? _tdsRateBp;
  bool _isActive = true;

  List<Account> _expenseAccounts = [];
  List<TdsSection> _tdsSections = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final allAccounts = await services.ledger.listAccounts(societyId);
      final expenseAccounts = allAccounts.where((a) => a.accountType == 'expense').toList();
      final tdsSections = await services.expenses.listTdsSections(societyId);

      Vendor? existing;
      if (widget.vendorId != null) {
        existing = await services.expenses.getVendor(societyId, widget.vendorId!);
      }

      if (mounted) {
        setState(() {
          _expenseAccounts = expenseAccounts;
          _tdsSections = tdsSections;

          if (existing != null) {
            _nameCtrl.text = existing.name;
            _codeCtrl.text = existing.vendorCode ?? '';
            _contactCtrl.text = existing.contactName ?? '';
            _phoneCtrl.text = existing.phone ?? '';
            _emailCtrl.text = existing.email ?? '';
            _altEmailsCtrl.text = existing.alternateEmails ?? '';
            _notesCtrl.text = existing.notes ?? '';
            _addressCtrl.text = existing.address ?? '';
            _stateCtrl.text = existing.stateCode ?? 'MH';
            _panCtrl.text = existing.pan ?? '';
            _gstinCtrl.text = existing.gstin ?? '';
            _payeeCtrl.text = existing.payeeName ?? '';
            _bankAccCtrl.text = existing.bankAccountNo ?? '';
            _branchCtrl.text = existing.bankBranch ?? '';
            _ifscCtrl.text = existing.ifsc ?? '';
            _defaultGstRateBp = existing.defaultGstRateBp;
            _legalType = existing.legalType ?? 'company';
            _defaultExpenseAccountId = existing.defaultExpenseAccountId;
            _tdsSectionId = existing.tdsSectionId;
            _tdsRateBp = existing.tdsRateBp;
            _isActive = existing.isActive;
          }

          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() => _saving = true);
    try {
      final services = await SocietyServices.instance();
      await services.expenses.saveVendor(
        societyId,
        VendorDraft(
          name: _nameCtrl.text.trim(),
          vendorCode: _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim(),
          contactName: _contactCtrl.text.trim().isEmpty ? null : _contactCtrl.text.trim(),
          phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          alternateEmails: _altEmailsCtrl.text.trim().isEmpty ? null : _altEmailsCtrl.text.trim(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
          stateCode: _stateCtrl.text.trim().isEmpty ? null : _stateCtrl.text.trim(),
          pan: _panCtrl.text.trim().isEmpty ? null : _panCtrl.text.trim(),
          gstin: _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim(),
          defaultGstRateBp: _defaultGstRateBp,
          legalType: _legalType,
          payeeName: _payeeCtrl.text.trim().isEmpty ? null : _payeeCtrl.text.trim(),
          bankAccountNo: _bankAccCtrl.text.trim().isEmpty ? null : _bankAccCtrl.text.trim(),
          bankBranch: _branchCtrl.text.trim().isEmpty ? null : _branchCtrl.text.trim(),
          ifsc: _ifscCtrl.text.trim().isEmpty ? null : _ifscCtrl.text.trim(),
          defaultExpenseAccountId: _defaultExpenseAccountId,
          tdsSectionId: _tdsSectionId,
          tdsRateBp: _tdsRateBp,
          isActive: _isActive,
        ),
        vendorId: widget.vendorId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vendor saved successfully')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return SocietyPage(
      title: widget.vendorId != null ? 'Edit Vendor' : 'New Vendor',
      actions: [
        OutlinedButton(onPressed: _saving ? null : () => context.pop(), child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: const Text('Save Vendor'),
          onPressed: _saving ? null : _save,
        ),
      ],
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic details
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Vendor Information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _nameCtrl,
                              decoration: const InputDecoration(labelText: 'Vendor Name *'),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              controller: _codeCtrl,
                              decoration: const InputDecoration(labelText: 'Vendor Code'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<String>(
                              initialValue: _legalType,
                              decoration: const InputDecoration(labelText: 'Legal Entity Type'),
                              items: const [
                                DropdownMenuItem(value: 'company', child: Text('Company (Pvt / Ltd)')),
                                DropdownMenuItem(value: 'firm', child: Text('Partnership / LLP')),
                                DropdownMenuItem(value: 'individual', child: Text('Proprietorship / Individual')),
                                DropdownMenuItem(value: 'trust', child: Text('Trust / Society')),
                                DropdownMenuItem(value: 'other', child: Text('Other')),
                              ],
                              onChanged: (v) => setState(() => _legalType = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _contactCtrl,
                              decoration: const InputDecoration(labelText: 'Contact Person'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              decoration: const InputDecoration(labelText: 'Phone / Mobile'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtrl,
                              decoration: const InputDecoration(labelText: 'Email'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(labelText: 'Address'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Tax & Statutory
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tax & TDS Settings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _panCtrl,
                              decoration: const InputDecoration(labelText: 'PAN'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _gstinCtrl,
                              decoration: const InputDecoration(labelText: 'GSTIN'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateCtrl,
                              decoration: const InputDecoration(labelText: 'State Code (e.g. MH)'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _defaultGstRateBp,
                              decoration: const InputDecoration(labelText: 'Default GST Rate'),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('0% (Nil)')),
                                DropdownMenuItem(value: 500, child: Text('5%')),
                                DropdownMenuItem(value: 1200, child: Text('12%')),
                                DropdownMenuItem(value: 1800, child: Text('18%')),
                                DropdownMenuItem(value: 2800, child: Text('28%')),
                              ],
                              onChanged: (v) => setState(() => _defaultGstRateBp = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _tdsSectionId,
                              decoration: const InputDecoration(labelText: 'Applicable TDS Section'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('None (No TDS)')),
                                ..._tdsSections.map((ts) => DropdownMenuItem(value: ts.id, child: Text('${ts.code} - ${ts.name}'))),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _tdsSectionId = v;
                                  if (v != null) {
                                    final sel = _tdsSections.firstWhere((ts) => ts.id == v);
                                    _tdsRateBp = sel.defaultRateBp;
                                  } else {
                                    _tdsRateBp = null;
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 1,
                            child: TextFormField(
                              initialValue: _tdsRateBp != null ? (_tdsRateBp! / 100).toString() : '',
                              decoration: const InputDecoration(labelText: 'TDS Rate %'),
                              onChanged: (v) {
                                final d = double.tryParse(v);
                                if (d != null) _tdsRateBp = (d * 100).round();
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 2,
                            child: DropdownButtonFormField<int>(
                              initialValue: _defaultExpenseAccountId,
                              decoration: const InputDecoration(labelText: 'Default Expense Head'),
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Select default account')),
                                ..._expenseAccounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} - ${a.name}'))),
                              ],
                              onChanged: (v) => setState(() => _defaultExpenseAccountId = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Bank Details
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bank & Payment Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _payeeCtrl,
                              decoration: const InputDecoration(labelText: 'Payee Name (on cheque/RTGS)'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _bankAccCtrl,
                              decoration: const InputDecoration(labelText: 'Bank Account Number'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _ifscCtrl,
                              decoration: const InputDecoration(labelText: 'IFSC Code'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _branchCtrl,
                              decoration: const InputDecoration(labelText: 'Bank & Branch Name'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

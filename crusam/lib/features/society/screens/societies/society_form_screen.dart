import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/shared/widgets/society_date_field.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';

class SocietyFormScreen extends StatefulWidget {
  final int? societyId;

  const SocietyFormScreen({super.key, this.societyId});

  @override
  State<SocietyFormScreen> createState() => _SocietyFormScreenState();
}

class _SocietyFormScreenState extends State<SocietyFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _shortNameCtrl = TextEditingController();
  final _regNoCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  final _addr1Ctrl = TextEditingController();
  final _addr2Ctrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _stateCtrl = TextEditingController(text: 'Maharashtra');
  final _stateCodeCtrl = TextEditingController(text: '27');
  final _pincodeCtrl = TextEditingController();

  final _panCtrl = TextEditingController();
  final _tanCtrl = TextEditingController();
  final _gstinCtrl = TextEditingController();
  bool _gstRegistered = false;
  String? _gstEffectiveFrom;

  String _booksStartDate = todayIso();
  bool _isActive = true;

  bool _loading = false;
  bool _hasJournals = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.societyId != null) {
      _loadExisting();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _shortNameCtrl.dispose();
    _regNoCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addr1Ctrl.dispose();
    _addr2Ctrl.dispose();
    _cityCtrl.dispose();
    _stateCtrl.dispose();
    _stateCodeCtrl.dispose();
    _pincodeCtrl.dispose();
    _panCtrl.dispose();
    _tanCtrl.dispose();
    _gstinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final soc = await services.society.getSociety(widget.societyId!);

      final journals = await services.db.query(
        'journal_entries',
        columns: ['id'],
        where: 'society_id = ?',
        whereArgs: [widget.societyId!],
        limit: 1,
      );

      if (mounted) {
        setState(() {
          _nameCtrl.text = soc.name;
          _shortNameCtrl.text = soc.shortName ?? '';
          _regNoCtrl.text = soc.registrationNo ?? '';
          _phoneCtrl.text = soc.phone ?? '';
          _emailCtrl.text = soc.email ?? '';

          _addr1Ctrl.text = soc.addressLine1 ?? '';
          _addr2Ctrl.text = soc.addressLine2 ?? '';
          _cityCtrl.text = soc.city ?? '';
          _stateCtrl.text = soc.state;
          _stateCodeCtrl.text = soc.stateCode;
          _pincodeCtrl.text = soc.pincode ?? '';

          _panCtrl.text = soc.pan ?? '';
          _tanCtrl.text = soc.tan ?? '';
          _gstinCtrl.text = soc.gstin ?? '';
          _gstRegistered = soc.gstRegistered;
          _gstEffectiveFrom = soc.gstEffectiveFrom;

          _booksStartDate = soc.booksStartDate;
          _isActive = soc.isActive;

          _hasJournals = journals.isNotEmpty;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final draft = SocietyDraft(
        name: _nameCtrl.text.trim(),
        shortName: _shortNameCtrl.text.trim().isEmpty ? null : _shortNameCtrl.text.trim(),
        registrationNo: _regNoCtrl.text.trim().isEmpty ? null : _regNoCtrl.text.trim(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        addressLine1: _addr1Ctrl.text.trim().isEmpty ? null : _addr1Ctrl.text.trim(),
        addressLine2: _addr2Ctrl.text.trim().isEmpty ? null : _addr2Ctrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        state: _stateCtrl.text.trim().isEmpty ? 'Maharashtra' : _stateCtrl.text.trim(),
        stateCode: _stateCodeCtrl.text.trim().isEmpty ? '27' : _stateCodeCtrl.text.trim(),
        pincode: _pincodeCtrl.text.trim().isEmpty ? null : _pincodeCtrl.text.trim(),
        pan: _panCtrl.text.trim().isEmpty ? null : _panCtrl.text.trim().toUpperCase(),
        tan: _tanCtrl.text.trim().isEmpty ? null : _tanCtrl.text.trim().toUpperCase(),
        gstin: _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim().toUpperCase(),
        gstRegistered: _gstRegistered,
        gstEffectiveFrom: _gstEffectiveFrom,
        booksStartDate: _booksStartDate,
        isActive: _isActive,
      );

      final services = await SocietyServices.instance();
      if (widget.societyId == null) {
        final id = await services.society.createSociety(draft);
        await SocietyContext.instance.reload();
        await SocietyContext.instance.selectSociety(id);
      } else {
        await services.society.updateSociety(widget.societyId!, draft);
        await SocietyContext.instance.reload();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.societyId == null ? 'Society created successfully' : 'Society updated successfully')),
        );
        context.go('/society/societies');
      }
    } catch (e) {
      setState(() {
        _error = e is SocietyException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.societyId == null;

    return SocietyPage(
      title: isNew ? 'Add Society' : 'Edit Society',
      subtitle: isNew ? 'Register a new housing society' : 'Update society configuration and legal details',
      allowAllSocieties: true,
      requireSociety: false,
      actions: [
        OutlinedButton(
          onPressed: _loading ? null : () => context.go('/society/societies'),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: Text(isNew ? 'Create Society' : 'Save Changes'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF3B82F6),
            foregroundColor: Colors.white,
          ),
          onPressed: _loading ? null : _save,
        ),
      ],
      child: _loading && !isNew
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(fontSize: 13, color: Color(0xFFB91C1C)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildSectionCard('Identity', [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameCtrl,
                              maxLength: 120,
                              decoration: const InputDecoration(labelText: 'Society Name *', border: OutlineInputBorder()),
                              validator: (val) => val == null || val.trim().isEmpty ? 'Name is required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _shortNameCtrl,
                              maxLength: 30,
                              decoration: const InputDecoration(labelText: 'Short Name / Alias', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _regNoCtrl,
                              maxLength: 60,
                              decoration: const InputDecoration(labelText: 'Registration No', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              maxLength: 15,
                              decoration: const InputDecoration(labelText: 'Phone', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtrl,
                              maxLength: 80,
                              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('Active Status', style: TextStyle(fontSize: 14)),
                        subtitle: const Text('Inactive societies are hidden from day-to-day operations', style: TextStyle(fontSize: 12)),
                        value: _isActive,
                        onChanged: (val) => setState(() => _isActive = val),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSectionCard('Address', [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _addr1Ctrl,
                              maxLength: 120,
                              decoration: const InputDecoration(labelText: 'Address Line 1', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _addr2Ctrl,
                              maxLength: 120,
                              decoration: const InputDecoration(labelText: 'Address Line 2', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _cityCtrl,
                              maxLength: 60,
                              decoration: const InputDecoration(labelText: 'City', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateCtrl,
                              maxLength: 60,
                              decoration: const InputDecoration(labelText: 'State', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _stateCodeCtrl,
                              maxLength: 2,
                              decoration: const InputDecoration(labelText: 'State Code', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _pincodeCtrl,
                              maxLength: 10,
                              decoration: const InputDecoration(labelText: 'Pincode', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 16),
                    _buildSectionCard('Tax & Compliance', [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _panCtrl,
                              maxLength: 10,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'PAN', hintText: 'AAAAA9999A', border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _tanCtrl,
                              maxLength: 10,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(labelText: 'TAN', border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CheckboxListTile(
                        title: const Text('Society is GST Registered', style: TextStyle(fontSize: 14)),
                        value: _gstRegistered,
                        onChanged: (val) => setState(() => _gstRegistered = val ?? false),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_gstRegistered) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _gstinCtrl,
                                maxLength: 15,
                                textCapitalization: TextCapitalization.characters,
                                decoration: const InputDecoration(labelText: 'GSTIN (15 chars)', border: OutlineInputBorder()),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: SocietyDateField(
                                label: 'GST Effective From',
                                value: _gstEffectiveFrom,
                                onChanged: (val) => setState(() => _gstEffectiveFrom = val),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ]),
                    const SizedBox(height: 16),
                    _buildSectionCard('Books & Accounting', [
                      Row(
                        children: [
                          Expanded(
                            child: SocietyDateField(
                              label: 'Books Start Date *',
                              value: _booksStartDate,
                              enabled: !_hasJournals,
                              onChanged: (val) {
                                if (val != null) setState(() => _booksStartDate = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              _hasJournals
                                  ? 'Books start date cannot be changed because journals have already been posted.'
                                  : 'Financial year will be established around this date.',
                              style: TextStyle(
                                fontSize: 13,
                                color: _hasJournals ? const Color(0xFFB91C1C) : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionCard(String title, List<Widget> children) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
            ),
            const Divider(color: Color(0xFFE2E8F0), height: 24),
            ...children,
          ],
        ),
      ),
    );
  }
}

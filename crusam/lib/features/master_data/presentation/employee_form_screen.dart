import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import '../../../shared/widgets/app_text_field.dart';

class EmployeeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving   = false;
  bool _deleting = false;
  String _gender = 'M';

  List<String> _codeList = [];
  String? _selectedCode;

  // ── Bank dropdown ──────────────────────────────────────────────────────────
  String? _selectedBank;
  static const _bankOptions = [
    'IDBI Bank Ltd.',
    'State Bank Of India',
    'HDFC Bank Ltd',
    'Punjab National Bank',
    'Canara Bank',
    'Bank Of India',
    'Bank Of Maharashtra',
    'Union Bank Of India',
    'Indian Overseas Bank',
    'Indian Bank',
    'Bank Of Baroda',
    'Central Bank Of India',
    'Karur Vysya Bank',
    'Kotak Mahindra Bank',
    'ICICI Bank Ltd.',
    'The Kalyan Janata Sahakari Bank Ltd.',
    'Dombivali Nagari Bank Ltd.',
    'The Thane District Central Co-Op Bank Ltd',
    'Karnataka Vikas Grameena Bank',
    'Pragathi Krishna Gramin Bank',
    'Other',
  ];

  // ── Zone dropdown ──────────────────────────────────────────────────────────
  String? _selectedZone;
  static const _zoneOptions = ['North', 'South', 'East', 'West'];

  late final _ctrl = <String, TextEditingController>{
    'srNo': TextEditingController(),
    'name': TextEditingController(),
    'pfNo': TextEditingController(),
    'uanNo': TextEditingController(),
    'code': TextEditingController(),
    'ifscCode': TextEditingController(),
    'accountNumber': TextEditingController(),
    'aartiAcNo': TextEditingController(text: '0680651100000338'),
    'sbCode': TextEditingController(text: '10'),
    'bankDetails': TextEditingController(),
    'branch': TextEditingController(),
    'zone': TextEditingController(),
    'dateOfJoining': TextEditingController(),
    'basicCharges': TextEditingController(),
    'otherCharges': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _loadCodes();

    final emp = widget.employee;
    if (emp != null) {
      final m = EmployeeModel.fromMap(emp);
      _ctrl['srNo']!.text = m.srNo.toString();
      _ctrl['name']!.text = m.name;
      _ctrl['pfNo']!.text = m.pfNo;
      _ctrl['uanNo']!.text = m.uanNo;
      _ctrl['code']!.text = m.code;
      _selectedCode = m.code;
      _ctrl['ifscCode']!.text = m.ifscCode;
      _ctrl['accountNumber']!.text = m.accountNumber;
      _ctrl['aartiAcNo']!.text = m.aartiAcNo;
      _ctrl['sbCode']!.text = m.sbCode;
      _ctrl['bankDetails']!.text = m.bankDetails;
      _ctrl['branch']!.text = m.branch;
      _ctrl['zone']!.text = m.zone;
      _ctrl['dateOfJoining']!.text = m.dateOfJoining;
      _ctrl['basicCharges']!.text =
          m.basicCharges == 0 ? '' : m.basicCharges.toStringAsFixed(2);
      _ctrl['otherCharges']!.text =
          m.otherCharges == 0 ? '' : m.otherCharges.toStringAsFixed(2);
      _gender = m.gender;

      // Initialise dropdowns from saved values
      _selectedBank = _bankOptions.contains(m.bankDetails)
          ? m.bankDetails
          : null;
      _selectedZone = _zoneOptions.contains(m.zone) ? m.zone : null;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadCodes() async {
    const codes = ['F&B', 'I&L', 'P&S', 'A&P'];
    setState(() {
      _codeList = codes;
      if (_selectedCode == null && _codeList.isNotEmpty) {
        _selectedCode = _codeList.first;
        _ctrl['code']!.text = _selectedCode!;
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(1980),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _ctrl['dateOfJoining']!.text =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final emp = EmployeeModel(
        srNo: int.tryParse(_ctrl['srNo']!.text.trim()) ?? 0,
        name: _ctrl['name']!.text.trim(),
        pfNo: _ctrl['pfNo']!.text.trim(),
        uanNo: _ctrl['uanNo']!.text.trim(),
        code: _ctrl['code']!.text.trim(),
        ifscCode: _ctrl['ifscCode']!.text.trim().toUpperCase(),
        accountNumber: _ctrl['accountNumber']!.text.trim(),
        aartiAcNo: _ctrl['aartiAcNo']!.text.trim(),
        sbCode: _ctrl['sbCode']!.text.trim(),
        // Use dropdown value if selected, otherwise fall back to controller text
        bankDetails: _ctrl['bankDetails']!.text.trim(),
        branch: _ctrl['branch']!.text.trim(),
        zone: _ctrl['zone']!.text.trim(),
        dateOfJoining: _ctrl['dateOfJoining']!.text.trim(),
        basicCharges: double.tryParse(_ctrl['basicCharges']!.text.trim()) ?? 0,
        otherCharges: double.tryParse(_ctrl['otherCharges']!.text.trim()) ?? 0,
        gender: _gender,
      );
      if (widget.employee?['id'] != null) {
        await DatabaseHelper.instance
            .updateEmployee(widget.employee!['id'] as int, emp.toMap());
      } else {
        await DatabaseHelper.instance.insertEmployee(emp.toMap());
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final id = widget.employee?['id'] as int?;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Delete "${_ctrl['name']!.text.trim()}"? Cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dc, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await DatabaseHelper.instance.deleteEmployee(id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Widget _field(
    String key,
    String label, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? fmt,
    TextCapitalization cap = TextCapitalization.none,
    bool readOnly = false,
    VoidCallback? onTap,
    bool required = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: AppTextField(
          controller: _ctrl[key]!,
          label: label,
          keyboardType: type,
          formatters: fmt,
          capitalization: cap,
          readOnly: readOnly,
          onTap: onTap,
          suffix: readOnly ? const Icon(Icons.calendar_today, size: 18) : null,
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null
              : null,
        ),
      );

  Widget _codeDropdown() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: DropdownButtonFormField<String>(
          value: _selectedCode,
          decoration: const InputDecoration(labelText: 'Code'),
          items: _codeList
              .map((c) =>
                  DropdownMenuItem<String>(value: c, child: Text(c)))
              .toList(),
          onChanged: _codeList.isEmpty
              ? null
              : (v) => setState(() {
                    _selectedCode = v;
                    _ctrl['code']!.text = v ?? '';
                  }),
          validator: (v) =>
              v == null || v.isEmpty ? 'Please select a code' : null,
        ),
      );

  // ── Bank dropdown ──────────────────────────────────────────────────────────
  Widget _bankDropdown() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: DropdownButtonFormField<String>(
          value: _selectedBank,
          decoration: const InputDecoration(labelText: 'Bank Details'),
          isExpanded: true,
          items: _bankOptions
              .map((b) =>
                  DropdownMenuItem<String>(value: b, child: Text(b)))
              .toList(),
          onChanged: (v) => setState(() {
            _selectedBank = v;
            _ctrl['bankDetails']!.text = v ?? '';
          }),
        ),
      );

  // ── Zone dropdown ──────────────────────────────────────────────────────────
  Widget _zoneDropdown() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: DropdownButtonFormField<String>(
          value: _selectedZone,
          decoration: const InputDecoration(labelText: 'Zone'),
          items: _zoneOptions
              .map((z) =>
                  DropdownMenuItem<String>(value: z, child: Text(z)))
              .toList(),
          onChanged: (v) => setState(() {
            _selectedZone = v;
            _ctrl['zone']!.text = v ?? '';
          }),
        ),
      );

  Widget _genderToggle() => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Gender',
                style: TextStyle(color: AppColors.slate700, fontSize: 13)),
            const SizedBox(height: 6),
            Row(children: [
              _genderChip('M', 'Male', Icons.male),
              const SizedBox(width: 8),
              _genderChip('F', 'Female', Icons.female),
            ]),
          ],
        ),
      );

  Widget _genderChip(String value, String label, IconData icon) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo600 : AppColors.white,
          border: Border.all(
            color: selected ? AppColors.indigo600 : AppColors.slate300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 16,
              color: selected ? Colors.white : AppColors.slate500),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.slate600,
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          child: SizedBox(
            width: 520,
            child: Column(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppColors.slate50,
                  border:
                      Border(bottom: BorderSide(color: AppColors.slate200)),
                ),
                child: Row(children: [
                  Expanded(
                      child: Text(
                    widget.employee == null ? 'Add Employee' : 'Edit Employee',
                    style: AppTextStyles.h4,
                  )),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.pagePadding),
                  child: Form(
                    key: _formKey,
                    child: Column(children: [
                      _codeDropdown(),
                      _field('name', 'Name',
                          required: true, cap: TextCapitalization.words),
                      _genderToggle(),
                      _field('pfNo', 'PF No.'),
                      _field('uanNo', 'UAN No.', type: TextInputType.number),
                      _field('ifscCode', 'IFSC Code',
                          cap: TextCapitalization.characters),
                      _field('accountNumber', 'Account No.',
                          type: TextInputType.number),
                      _field('aartiAcNo', 'Aarti A/c No.',
                          type: TextInputType.number),
                      _field('sbCode', 'S/b Code',
                          type: TextInputType.number),
                      // ── Bank dropdown replaces plain text field ──────────
                      _bankDropdown(),
                      _field('branch', 'Branch',
                          cap: TextCapitalization.words),
                      // ── Zone dropdown replaces plain text field ──────────
                      _zoneDropdown(),
                      _field('dateOfJoining', 'Date of Joining',
                          readOnly: true, onTap: _pickDate),
                      Row(children: [
                        Expanded(
                            child: _field('basicCharges', 'Basic Charges',
                                type: const TextInputType.numberWithOptions(
                                    decimal: true))),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                            child: _field('otherCharges', 'Other Charges',
                                type: const TextInputType.numberWithOptions(
                                    decimal: true))),
                      ]),
                      const SizedBox(height: AppSpacing.md),
                      if (widget.employee == null)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: (_saving || _deleting) ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Text('Save Employee'),
                          ),
                        )
                      else
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  (_saving || _deleting) ? null : _delete,
                              icon: _deleting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.delete_outline,
                                      color: Colors.red),
                              label: const Text('Delete'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                minimumSize: const Size.fromHeight(48),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed:
                                    (_saving || _deleting) ? null : _save,
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2))
                                    : const Text('Save Changes'),
                              ),
                            ),
                          ),
                        ]),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
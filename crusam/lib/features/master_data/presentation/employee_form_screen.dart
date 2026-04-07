import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_spacing.dart';
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
  bool _saving = false;

  late final _ctrl = <String, TextEditingController>{
    'srNo':          TextEditingController(),
    'name':          TextEditingController(),
    'pfNo':          TextEditingController(),
    'uanNo':         TextEditingController(),
    'code':          TextEditingController(),
    'ifscCode':      TextEditingController(),
    'accountNumber': TextEditingController(),
    'aartiAcNo':     TextEditingController(text: '0680651100000338'),
    'sbCode':        TextEditingController(text: '10'),
    'bankDetails':   TextEditingController(),
    'branch':        TextEditingController(),
    'zone':          TextEditingController(),
    'dateOfJoining': TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    if (emp != null) {
      final m = EmployeeModel.fromMap(emp);
      _ctrl['srNo']!.text          = m.srNo.toString();
      _ctrl['name']!.text          = m.name;
      _ctrl['pfNo']!.text          = m.pfNo;
      _ctrl['uanNo']!.text         = m.uanNo;
      _ctrl['code']!.text          = m.code;
      _ctrl['ifscCode']!.text      = m.ifscCode;
      _ctrl['accountNumber']!.text = m.accountNumber;
      _ctrl['aartiAcNo']!.text     = m.aartiAcNo;
      _ctrl['sbCode']!.text        = m.sbCode;
      _ctrl['bankDetails']!.text   = m.bankDetails;
      _ctrl['branch']!.text        = m.branch;
      _ctrl['zone']!.text          = m.zone;
      _ctrl['dateOfJoining']!.text = m.dateOfJoining;
    }
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
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
        srNo:          int.tryParse(_ctrl['srNo']!.text.trim()) ?? 0,
        name:          _ctrl['name']!.text.trim(),
        pfNo:          _ctrl['pfNo']!.text.trim(),
        uanNo:         _ctrl['uanNo']!.text.trim(),
        code:          _ctrl['code']!.text.trim(),
        ifscCode:      _ctrl['ifscCode']!.text.trim().toUpperCase(),
        accountNumber: _ctrl['accountNumber']!.text.trim(),
        aartiAcNo:     _ctrl['aartiAcNo']!.text.trim(),
        sbCode:        _ctrl['sbCode']!.text.trim(),
        bankDetails:   _ctrl['bankDetails']!.text.trim(),
        branch:        _ctrl['branch']!.text.trim(),
        zone:          _ctrl['zone']!.text.trim(),
        dateOfJoining: _ctrl['dateOfJoining']!.text.trim(),
      );
      if (widget.employee?['id'] != null) {
        await DatabaseHelper.instance.updateEmployee(widget.employee!['id'] as int, emp.toMap());
      } else {
        await DatabaseHelper.instance.insertEmployee(emp.toMap());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.employee == null ? 'Employee added' : 'Employee updated')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String key, String label, {
    TextInputType type = TextInputType.text,
    List<TextInputFormatter>? fmt,
    TextCapitalization cap = TextCapitalization.none,
    bool readOnly = false, VoidCallback? onTap,
    bool required = false,
  }) => Padding(
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
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null : null,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.employee == null ? 'Add Employee' : 'Edit Employee'),
    ),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(children: [
            Row(children: [
              Expanded(child: _field('srNo', 'Sr. No.', type: TextInputType.number, fmt: [FilteringTextInputFormatter.digitsOnly])),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _field('code', 'Code')),
            ]),
            _field('name', 'Name', required: true, cap: TextCapitalization.words),
            _field('pfNo', 'PF No.'),
            _field('uanNo', 'UAN No.', type: TextInputType.number),
            _field('ifscCode', 'IFSC Code', cap: TextCapitalization.characters),
            _field('accountNumber', 'Account No.', type: TextInputType.number),
            _field('aartiAcNo', 'Aarti A/c No.', type: TextInputType.number),
            _field('sbCode', 'S/b Code', type: TextInputType.number),
            _field('bankDetails', 'Bank Details', cap: TextCapitalization.words),
            _field('branch', 'Branch', cap: TextCapitalization.words),
            _field('zone', 'Zone', cap: TextCapitalization.words),
            _field('dateOfJoining', 'Date of Joining', readOnly: true, onTap: _pickDate),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Employee'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../db/database_helper.dart';

class EmployeeFormScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;

  const EmployeeFormScreen({super.key, this.employee});

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _srNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _pfNoController = TextEditingController();
  final _uanNoController = TextEditingController();
  final _codeController = TextEditingController();
  final _ifscController = TextEditingController();
  final _accountNoController = TextEditingController();
  final _aartiAcNoController = TextEditingController();
  final _sbCodeController = TextEditingController();
  final _bankDetailsController = TextEditingController();
  final _branchController = TextEditingController();
  final _zoneController = TextEditingController();
  final _dateController = TextEditingController();

  // Focus Nodes
  final _srNoFocus = FocusNode();
  final _nameFocus = FocusNode();
  final _pfNoFocus = FocusNode();
  final _uanNoFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _ifscFocus = FocusNode();
  final _accountNoFocus = FocusNode();
  final _aartiAcNoFocus = FocusNode();
  final _sbCodeFocus = FocusNode();
  final _bankDetailsFocus = FocusNode();
  final _branchFocus = FocusNode();
  final _zoneFocus = FocusNode();
  final _dateFocus = FocusNode();

  bool _isSaving = false;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    if (widget.employee != null) {
      _prefillForm();
    } else {
      _aartiAcNoController.text = "0680651100000338";
      _sbCodeController.text = "10";
    }
  }

  void _prefillForm() {
    final emp = widget.employee!;
    _srNoController.text = emp['srNo']?.toString() ?? '';
    _nameController.text = emp['name'] ?? '';
    _pfNoController.text = emp['pfNo']?.toString() ?? '';
    _uanNoController.text = emp['uanNo']?.toString() ?? '';
    _codeController.text = emp['code']?.toString() ?? '';
    _ifscController.text = emp['ifsc'] ?? '';
    _accountNoController.text = emp['accountNo']?.toString() ?? '';
    _aartiAcNoController.text = emp['aartiAcNo']?.toString() ?? "0680651100000338";
    _sbCodeController.text = emp['sbCode']?.toString() ?? "10";
    _bankDetailsController.text = emp['bankDetails'] ?? '';
    _branchController.text = emp['branch'] ?? '';
    _zoneController.text = emp['zone'] ?? '';
    _dateController.text = emp['joiningDate'] ?? '';
  }

  @override
  void dispose() {
    _srNoController.dispose();
    _nameController.dispose();
    _pfNoController.dispose();
    _uanNoController.dispose();
    _codeController.dispose();
    _ifscController.dispose();
    _accountNoController.dispose();
    _aartiAcNoController.dispose();
    _sbCodeController.dispose();
    _bankDetailsController.dispose();
    _branchController.dispose();
    _zoneController.dispose();
    _dateController.dispose();

    _srNoFocus.dispose();
    _nameFocus.dispose();
    _pfNoFocus.dispose();
    _uanNoFocus.dispose();
    _codeFocus.dispose();
    _ifscFocus.dispose();
    _accountNoFocus.dispose();
    _aartiAcNoFocus.dispose();
    _sbCodeFocus.dispose();
    _bankDetailsFocus.dispose();
    _branchFocus.dispose();
    _zoneFocus.dispose();
    _dateFocus.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = _formatDate(picked);
      });
    }
  }

  String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}";
  }

  Future<void> _saveEmployee() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final data = {
        'srNo': _srNoController.text.trim(),
        'name': _nameController.text.trim(),
        'pfNo': _pfNoController.text.trim(),
        'uanNo': _uanNoController.text.trim(),
        'code': _codeController.text.trim(),
        'ifsc': _ifscController.text.trim().toUpperCase(),
        'accountNo': _accountNoController.text.trim(),
        'aartiAcNo': _aartiAcNoController.text.trim(),
        'sbCode': _sbCodeController.text.trim(),
        'bankDetails': _bankDetailsController.text.trim(),
        'branch': _branchController.text.trim(),
        'zone': _zoneController.text.trim(),
        'joiningDate': _dateController.text.trim(),
      };

      if (widget.employee != null) {
        await DatabaseHelper.instance.updateEmployee(widget.employee!['id'], data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee updated successfully')),
          );
        }
      } else {
        await DatabaseHelper.instance.insertEmployee(data);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee added successfully')),
          );
        }
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving employee: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.employee == null ? 'Add Employee' : 'Edit Employee'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              _buildTextField(
                controller: _srNoController,
                focusNode: _srNoFocus,
                label: 'Sr. No.',
                nextFocus: _nameFocus,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                focusNode: _nameFocus,
                label: 'Name',
                nextFocus: _pfNoFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _pfNoController,
                focusNode: _pfNoFocus,
                label: 'PF No.',
                nextFocus: _uanNoFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _uanNoController,
                focusNode: _uanNoFocus,
                label: 'UAN No.',
                nextFocus: _codeFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _codeController,
                focusNode: _codeFocus,
                label: 'Code',
                nextFocus: _ifscFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _ifscController,
                focusNode: _ifscFocus,
                label: 'IFSC Code',
                nextFocus: _accountNoFocus,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _accountNoController,
                focusNode: _accountNoFocus,
                label: 'Account No.',
                nextFocus: _aartiAcNoFocus,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _aartiAcNoController,
                focusNode: _aartiAcNoFocus,
                label: 'Aarti A/c No.',
                nextFocus: _sbCodeFocus,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _sbCodeController,
                focusNode: _sbCodeFocus,
                label: 'S/b Code',
                nextFocus: _bankDetailsFocus,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _bankDetailsController,
                focusNode: _bankDetailsFocus,
                label: 'Bank Details',
                nextFocus: _branchFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _branchController,
                focusNode: _branchFocus,
                label: 'Branch',
                nextFocus: _zoneFocus,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _zoneController,
                focusNode: _zoneFocus,
                label: 'Zone',
                nextFocus: _dateFocus,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dateController,
                focusNode: _dateFocus,
                readOnly: true,
                onTap: _pickDate,
                decoration: InputDecoration(
                  labelText: 'Date of Joining',
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.calendar_today),
                  errorStyle: const TextStyle(color: Colors.red),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _saveEmployee(),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Date of Joining is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveEmployee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Employee'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required FocusNode nextFocus,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        errorStyle: const TextStyle(color: Colors.red),
      ),
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => FocusScope.of(context).requestFocus(nextFocus),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return '$label is required';
        }
        return null;
      },
    );
  }
}
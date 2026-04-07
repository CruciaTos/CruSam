import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import 'employee_form_screen.dart';

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _searchController.addListener(() {
      _onSearchChanged(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final employees = await DatabaseHelper.instance.getAllEmployees();
      setState(() {
        _employees = employees;
        _filtered = employees;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading employees: $e')),
        );
      }
    }
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() {
        _filtered = _employees;
      });
    } else {
      DatabaseHelper.instance.searchEmployeesByName(query).then((results) {
        if (mounted) {
          setState(() {
            _filtered = results;
          });
        }
      }).catchError((error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Search error: $error')),
          );
        }
      });
    }
  }

  Future<void> _deleteEmployee(int id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Employee'),
          content: Text('Delete $name? This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await DatabaseHelper.instance.deleteEmployee(id);
        await _loadEmployees();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Employee deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting employee: $e')),
          );
        }
      }
    }
  }

  Future<void> _navigateToForm({Map<String, dynamic>? employee}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EmployeeFormScreen(employee: employee),
      ),
    );
    await _loadEmployees();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Master'),
        elevation: 2,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No employees yet. Tap + to add.',
                          style: TextStyle(fontSize: 16),
                        ),
                      )
                    : SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 20,
                            columns: const [
                              DataColumn(label: Text('Sr.No')),
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('PF No.')),
                              DataColumn(label: Text('UAN No.')),
                              DataColumn(label: Text('Code')),
                              DataColumn(label: Text('IFSC')),
                              DataColumn(label: Text('Account No.')),
                              DataColumn(label: Text('Aarti A/c')),
                              DataColumn(label: Text('S/b')),
                              DataColumn(label: Text('Bank')),
                              DataColumn(label: Text('Branch')),
                              DataColumn(label: Text('Zone')),
                              DataColumn(label: Text('Joining Date')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: _filtered.asMap().entries.map((entry) {
                              final int index = entry.key;
                              final employee = entry.value;
                              return DataRow(
                                cells: [
                                  DataCell(Text((index + 1).toString())),
                                  DataCell(Text(employee['name'] ?? '')),
                                  DataCell(Text(employee['pfNo'] ?? '')),
                                  DataCell(Text(employee['uanNo'] ?? '')),
                                  DataCell(Text(employee['code'] ?? '')),
                                  DataCell(Text(employee['ifsc'] ?? '')),
                                  DataCell(Text(employee['accountNo'] ?? '')),
                                  DataCell(Text(employee['aartiAcNo'] ?? '')),
                                  DataCell(Text(employee['sbCode'] ?? '')),
                                  DataCell(Text(employee['bankDetails'] ?? '')),
                                  DataCell(Text(employee['branch'] ?? '')),
                                  DataCell(Text(employee['zone'] ?? '')),
                                  DataCell(Text(employee['joiningDate'] ?? '')),
                                  DataCell(
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blue),
                                          onPressed: () => _navigateToForm(employee: employee),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          onPressed: () => _deleteEmployee(employee['id'], employee['name'] ?? 'this employee'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_error_view.dart';

class ExpenseComparisonScreen extends StatefulWidget {
  const ExpenseComparisonScreen({super.key});

  @override
  State<ExpenseComparisonScreen> createState() => _ExpenseComparisonScreenState();
}

class _ExpenseComparisonScreenState extends State<ExpenseComparisonScreen> {
  bool _loading = true;
  String? _error;

  List<FinancialYear> _years = [];
  int? _selectedFyId;
  String _mode = 'monthly'; // 'monthly', 'quarterly'
  ExpenseComparison? _comparison;

  @override
  void initState() {
    super.initState();
    _loadYears();
  }

  Future<void> _loadYears() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final years = await services.society.listFinancialYears(societyId);
      final active = years.where((y) => y.isOpen).isNotEmpty ? years.firstWhere((y) => y.isOpen) : (years.isNotEmpty ? years.first : null);

      if (mounted) {
        setState(() {
          _years = years;
          _selectedFyId = active?.id ?? (years.isNotEmpty ? years.first.id : null);
        });

        if (_selectedFyId != null) {
          _loadComparison();
        } else {
          setState(() => _loading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadComparison() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedFyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final comp = await services.expenses.expenseComparison(
        societyId,
        ComparisonRequest(mode: _mode, fyId: _selectedFyId!),
      );

      if (mounted) {
        setState(() {
          _comparison = comp;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Expense Comparison',
      actions: [
        if (_years.isNotEmpty)
          DropdownButton<int>(
            value: _selectedFyId,
            underline: const SizedBox(),
            items: _years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.code))).toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedFyId = v);
                _loadComparison();
              }
            },
          ),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _mode,
          underline: const SizedBox(),
          items: const [
            DropdownMenuItem(value: 'monthly', child: Text('Monthly Breakdown')),
            DropdownMenuItem(value: 'quarterly', child: Text('Quarterly Breakdown')),
          ],
          onChanged: (v) {
            if (v != null) {
              setState(() => _mode = v);
              _loadComparison();
            }
          },
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SocietyErrorView(message: _error!, onRetry: _loadComparison)
              : _comparison == null || _comparison!.accounts.isEmpty
                  ? const Center(child: Text('No expense accounts to compare'))
                  : SocietyDataTable<Map<String, dynamic>>(
                      total: _comparison!.accounts.length,
                      columns: [
                        SocietyColumn<Map<String, dynamic>>(
                          label: 'Code',
                          cell: (acc) => Text(acc['code'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                          width: 90,
                        ),
                        SocietyColumn<Map<String, dynamic>>(
                          label: 'Account Name',
                          cell: (acc) => Text(acc['name'] as String),
                          width: 200,
                        ),
                        ..._comparison!.columns.map((c) => SocietyColumn<Map<String, dynamic>>(
                              label: c.label,
                              numeric: true,
                              cell: (acc) {
                                final accId = acc['id'] as int;
                                final val = c.accountAmountPaise[accId] ?? 0;
                                return Text(val > 0 ? formatPaise(val) : '-');
                              },
                              width: 100,
                            )),
                        SocietyColumn<Map<String, dynamic>>(
                          label: 'Total',
                          numeric: true,
                          cell: (acc) {
                            final accId = acc['id'] as int;
                            var rowTotal = 0;
                            for (final col in _comparison!.columns) {
                              rowTotal += col.accountAmountPaise[accId] ?? 0;
                            }
                            return Text(formatPaise(rowTotal), style: const TextStyle(fontWeight: FontWeight.bold));
                          },
                          width: 120,
                        ),
                      ],
                      rows: _comparison!.accounts,
                    ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_page.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/money_field.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<FinancialYear> _years = [];
  int? _selectedFyId;
  BudgetReport? _report;
  final Map<int, int> _editedBudgets = {}; // accountId -> budgetPaise

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
          _loadReport(_selectedFyId!);
        } else {
          setState(() => _loading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _loadReport(int fyId) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final nowStr = DateTime.now().toIso8601String().substring(0, 10);
      final report = await services.expenses.budgetReport(societyId, fyId, nowStr);

      if (mounted) {
        setState(() {
          _selectedFyId = fyId;
          _report = report;
          _editedBudgets.clear();
          for (final r in report.rows) {
            _editedBudgets[r.accountId] = r.budgetPaise;
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _saveBudget() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedFyId == null) return;

    setState(() => _saving = true);
    try {
      final services = await SocietyServices.instance();
      final drafts = _editedBudgets.entries
          .map((e) => BudgetDraft(accountId: e.key, amountPaise: e.value))
          .toList();

      await services.expenses.saveBudget(societyId, _selectedFyId!, drafts);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Budget saved successfully')));
        _loadReport(_selectedFyId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving budget: $e')));
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _copyPreviousYear() async {
    if (_years.length < 2 || _selectedFyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No previous financial year available')));
      return;
    }
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    final idx = _years.indexWhere((y) => y.id == _selectedFyId);
    if (idx < 0 || idx + 1 >= _years.length) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No earlier financial year found')));
      return;
    }
    final prevFy = _years[idx + 1];

    setState(() => _saving = true);
    try {
      final services = await SocietyServices.instance();
      await services.expenses.copyBudget(societyId, prevFy.id, _selectedFyId!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied budget from ${prevFy.code}')));
        _loadReport(_selectedFyId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error copying budget: $e')));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Annual Budget',
      actions: [
        if (_years.isNotEmpty)
          DropdownButton<int>(
            value: _selectedFyId,
            underline: const SizedBox(),
            items: _years.map((y) => DropdownMenuItem(value: y.id, child: Text(y.code))).toList(),
            onChanged: (v) {
              if (v != null) _loadReport(v);
            },
          ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy),
          label: const Text('Copy Previous Year'),
          onPressed: _saving ? null : _copyPreviousYear,
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save),
          label: const Text('Save Budget'),
          onPressed: _saving ? null : _saveBudget,
        ),
      ],
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? SocietyErrorView(message: _error!, onRetry: () => _selectedFyId != null ? _loadReport(_selectedFyId!) : _loadYears())
              : _report == null
                  ? const Center(child: Text('No budget available'))
                  : Column(
                      children: [
                        // KPI summary
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                          ),
                          child: Row(
                            children: [
                              _buildKpi('Total Budget', formatPaise(_report!.totalBudgetPaise)),
                              _buildKpi('Actual Expenses', formatPaise(_report!.totalActualPaise)),
                              _buildKpi(
                                'Variance (Surplus/Deficit)',
                                formatPaise(_report!.totalVariancePaise),
                                isBold: true,
                                color: _report!.totalVariancePaise >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SocietyDataTable<BudgetRow>(
                            total: _report!.rows.length,
                            columns: [
                              SocietyColumn<BudgetRow>(
                                label: 'Code',
                                cell: (r) => Text(r.accountCode, style: const TextStyle(fontWeight: FontWeight.bold)),
                                width: 90,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Account Name',
                                cell: (r) => Text(r.accountName),
                                width: 200,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Group',
                                cell: (r) => Text(r.groupName),
                                width: 140,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Budget Amount',
                                numeric: true,
                                cell: (r) {
                                  final currentBudget = _editedBudgets[r.accountId] ?? r.budgetPaise;
                                  return SizedBox(
                                    width: 130,
                                    child: MoneyField(
                                      label: '',
                                      value: currentBudget,
                                      onChanged: (v) {
                                        setState(() => _editedBudgets[r.accountId] = v ?? 0);
                                      },
                                    ),
                                  );
                                },
                                width: 150,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Actual Expense',
                                numeric: true,
                                cell: (r) => Text(formatPaise(r.actualPaise)),
                                width: 120,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Variance',
                                numeric: true,
                                cell: (r) => Text(
                                  formatPaise(r.variancePaise),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: r.variancePaise >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                                width: 120,
                              ),
                              SocietyColumn<BudgetRow>(
                                label: 'Variance %',
                                numeric: true,
                                cell: (r) => Text(
                                  '${r.variancePercent.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: r.variancePercent >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                                  ),
                                ),
                                width: 100,
                              ),
                            ],
                            rows: _report!.rows,
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildKpi(String label, String value, {bool isBold = false, Color? color}) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

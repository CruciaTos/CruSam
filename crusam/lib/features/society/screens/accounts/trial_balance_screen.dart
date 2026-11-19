import 'package:flutter/material.dart';

import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_date.dart';
import '../../core/society_services.dart';
import '../../data/models/ledger_models.dart';
import '../../shared/widgets/amount_summary.dart';
import '../../shared/widgets/export_menu.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_date_field.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class TrialBalanceScreen extends StatefulWidget {
  const TrialBalanceScreen({super.key});

  @override
  State<TrialBalanceScreen> createState() => _TrialBalanceScreenState();
}

class _TrialBalanceScreenState extends State<TrialBalanceScreen> {
  late String _fromDate;
  late String _toDate;

  TrialBalance? _data;
  bool _loading = false;
  String? _error;
  bool _hideZeroBalances = true;

  @override
  void initState() {
    super.initState();
    final today = todayIso();
    final fy = fyCodeForDate(today);
    final parts = fy.split('-');
    final startYear = int.parse(parts[0]);
    _fromDate = '$startYear-04-01';
    _toDate = today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadTrialBalance();
  }

  Future<void> _loadTrialBalance() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final tb = await services.ledger.trialBalance(societyId, _fromDate, _toDate);
      if (mounted) {
        setState(() {
          _data = tb;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayedRows = _data == null
        ? <TrialBalanceRow>[]
        : _hideZeroBalances
            ? _data!.rows.where((r) =>
                r.openingDebitPaise != 0 ||
                r.openingCreditPaise != 0 ||
                r.debitPaise != 0 ||
                r.creditPaise != 0 ||
                r.closingDebitPaise != 0 ||
                r.closingCreditPaise != 0).toList()
            : _data!.rows;

    return SocietyPage(
      title: 'Trial Balance',
      actions: [
        ExportMenu(
          onExportPdf: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trial Balance export ready')),
            );
          },
          onExportExcel: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trial Balance export ready')),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload',
          onPressed: _loadTrialBalance,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Filter Bar
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    child: SocietyDateField(
                      label: 'From Date',
                      value: _fromDate,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _fromDate = val);
                          _loadTrialBalance();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: SocietyDateField(
                      label: 'To Date',
                      value: _toDate,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _toDate = val);
                          _loadTrialBalance();
                        }
                      },
                    ),
                  ),
                  FilterChip(
                    label: const Text('Hide Zero Balances'),
                    selected: _hideZeroBalances,
                    onSelected: (val) {
                      setState(() => _hideZeroBalances = val);
                    },
                  ),
                ],
              ),
            ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: SocietyErrorView(
                message: _error!,
                onRetry: _loadTrialBalance,
              ),
            ),

          // Balance Status & Summaries
          if (_data != null) ...[
            Card(
              color: _data!.isBalanced
                  ? Colors.green.withValues(alpha: 0.1)
                  : Colors.red.withValues(alpha: 0.1),
              margin: const EdgeInsets.only(bottom: 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      _data!.isBalanced ? Icons.check_circle : Icons.warning_amber,
                      color: _data!.isBalanced ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _data!.isBalanced
                            ? 'Trial Balance is in balance (Closing Dr: ${formatInr(_data!.totalClosingDebitPaise)} = Closing Cr: ${formatInr(_data!.totalClosingCreditPaise)})'
                            : 'Trial Balance is out of balance by ${formatInr((_data!.totalClosingDebitPaise - _data!.totalClosingCreditPaise).abs())}!',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _data!.isBalanced ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AmountSummary(
                  width: double.infinity,
                  rows: [
                    AmountSummaryRow(
                      label: 'Period Total Debits',
                      amountPaise: _data!.totalDebitPaise,
                    ),
                    AmountSummaryRow(
                      label: 'Period Total Credits',
                      amountPaise: _data!.totalCreditPaise,
                    ),
                    AmountSummaryRow(
                      label: 'Total Closing Dr',
                      amountPaise: _data!.totalClosingDebitPaise,
                    ),
                    AmountSummaryRow(
                      label: 'Total Closing Cr',
                      amountPaise: _data!.totalClosingCreditPaise,
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Data Table
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : displayedRows.isEmpty
                    ? const SocietyEmptyView(
                        icon: Icons.balance_outlined,
                        title: 'No accounts with activity',
                        message: 'No accounts have non-zero opening, movement, or closing balances.',
                      )
                    : SocietyDataTable<TrialBalanceRow>(
                        columns: [
                          SocietyColumn(
                            label: 'Code',
                            width: 90,
                            cell: (r) => Text(
                              r.accountCode,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Account Name',
                            cell: (r) => Text(r.accountName),
                          ),
                          SocietyColumn(
                            label: 'Group',
                            width: 160,
                            cell: (r) => Text(
                              r.groupName,
                              style: TextStyle(color: Theme.of(context).hintColor),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Opening Balance',
                            numeric: true,
                            width: 140,
                            cell: (r) {
                              final dr = r.openingDebitPaise;
                              final cr = r.openingCreditPaise;
                              if (dr == 0 && cr == 0) return const Text('-');
                              if (dr >= cr) {
                                return Text(
                                  '${formatInr(dr - cr)} Dr',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                );
                              } else {
                                return Text(
                                  '${formatInr(cr - dr)} Cr',
                                  style: const TextStyle(fontFamily: 'monospace'),
                                );
                              }
                            },
                          ),
                          SocietyColumn(
                            label: 'Debit',
                            numeric: true,
                            width: 120,
                            cell: (r) => Text(
                              r.debitPaise > 0 ? formatInr(r.debitPaise) : '-',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Credit',
                            numeric: true,
                            width: 120,
                            cell: (r) => Text(
                              r.creditPaise > 0 ? formatInr(r.creditPaise) : '-',
                              style: const TextStyle(fontFamily: 'monospace'),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Closing Balance',
                            numeric: true,
                            width: 140,
                            cell: (r) {
                              final dr = r.closingDebitPaise;
                              final cr = r.closingCreditPaise;
                              if (dr == 0 && cr == 0) return const Text('-');
                              if (dr >= cr) {
                                return Text(
                                  '${formatInr(dr - cr)} Dr',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              } else {
                                return Text(
                                  '${formatInr(cr - dr)} Cr',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }
                            },
                          ),
                        ],
                        rows: displayedRows,
                        total: displayedRows.length,
                        page: 0,
                        pageSize: displayedRows.length.clamp(1, 1000),
                        onPage: (_) {},
                      ),
          ),
        ],
      ),
    );
  }
}

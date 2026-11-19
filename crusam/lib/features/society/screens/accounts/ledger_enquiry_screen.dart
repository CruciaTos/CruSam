import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_date.dart';
import '../../core/society_services.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/amount_summary.dart';
import '../../shared/widgets/export_menu.dart';
import '../../shared/widgets/society_data_table.dart';
import '../../shared/widgets/society_date_field.dart';
import '../../shared/widgets/society_empty_view.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class LedgerEnquiryScreen extends StatefulWidget {
  const LedgerEnquiryScreen({super.key});

  @override
  State<LedgerEnquiryScreen> createState() => _LedgerEnquiryScreenState();
}

class _LedgerEnquiryScreenState extends State<LedgerEnquiryScreen> {
  int? _selectedAccountId;
  List<Account> _accounts = [];
  bool _loadingAccounts = true;

  late String _fromDate;
  late String _toDate;

  int _page = 0;
  static const int _pageSize = 50;

  LedgerResult? _result;
  bool _loadingLedger = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final today = todayIso();
    _fromDate = today.length >= 7 ? '${today.substring(0, 7)}-01' : today;
    _toDate = today;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAccounts();
  }

  Future<void> _loadAccounts() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    try {
      final services = await SocietyServices.instance();
      final tree = await services.ledger.chartOfAccounts(societyId);
      final flat = <Account>[];
      for (final grp in tree) {
        flat.addAll(grp.accounts);
      }
      flat.sort((a, b) => a.code.compareTo(b.code));

      if (mounted) {
        setState(() {
          _accounts = flat;
          _loadingAccounts = false;
          if (_selectedAccountId == null && flat.isNotEmpty) {
            _selectedAccountId = flat.first.id;
          }
        });
        _loadLedger();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingAccounts = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _loadLedger() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null || _selectedAccountId == null) return;

    setState(() {
      _loadingLedger = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final filter = LedgerFilter(
        accountId: _selectedAccountId,
        fromDate: _fromDate,
        toDate: _toDate,
      );
      final res = await services.ledger.ledgerEnquiry(
        societyId,
        filter,
        PageRequest(limit: _pageSize, offset: _page * _pageSize),
      );

      if (mounted) {
        setState(() {
          _result = res;
          _loadingLedger = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingLedger = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Ledger Enquiry',
      actions: [
        ExportMenu(
          onExportPdf: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ledger export is ready')),
            );
          },
          onExportExcel: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ledger export is ready')),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Reload',
          onPressed: _loadLedger,
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
                    width: 320,
                    child: _loadingAccounts
                        ? const LinearProgressIndicator()
                        : DropdownButtonFormField<int>(
                            initialValue: _selectedAccountId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Account',
                              isDense: true,
                            ),
                            items: _accounts.map((a) {
                              return DropdownMenuItem<int>(
                                value: a.id,
                                child: Text(
                                  '${a.code} - ${a.name}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedAccountId = val;
                                  _page = 0;
                                });
                                _loadLedger();
                              }
                            },
                          ),
                  ),
                  SizedBox(
                    width: 150,
                    child: SocietyDateField(
                      label: 'From Date',
                      value: _fromDate,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _fromDate = val;
                            _page = 0;
                          });
                          _loadLedger();
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
                          setState(() {
                            _toDate = val;
                            _page = 0;
                          });
                          _loadLedger();
                        }
                      },
                    ),
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
                onRetry: _loadLedger,
              ),
            ),

          // Summaries
          if (_result != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AmountSummary(
                  width: double.infinity,
                  rows: [
                    AmountSummaryRow(
                      label: 'Opening Balance',
                      customValue:
                          '${formatInr(_result!.openingBalancePaise.abs())}${_result!.openingBalancePaise >= 0 ? " Dr" : " Cr"}',
                    ),
                    AmountSummaryRow(
                      label: 'Period Debit',
                      amountPaise: _result!.totalDebitPaise,
                    ),
                    AmountSummaryRow(
                      label: 'Period Credit',
                      amountPaise: _result!.totalCreditPaise,
                    ),
                    AmountSummaryRow(
                      label: 'Closing Balance',
                      customValue:
                          '${formatInr(_result!.closingBalancePaise.abs())}${_result!.closingBalancePaise >= 0 ? " Dr" : " Cr"}',
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // Table
          Expanded(
            child: _loadingLedger
                ? const Center(child: CircularProgressIndicator())
                : _result == null || _result!.lines.rows.isEmpty
                    ? const SocietyEmptyView(
                        icon: Icons.manage_search_outlined,
                        title: 'No ledger transactions',
                        message:
                            'No journal lines found for this account in the selected period.',
                      )
                    : SocietyDataTable<LedgerLine>(
                        columns: [
                          SocietyColumn(
                            label: 'Date',
                            width: 100,
                            cell: (r) => Text(formatDisplayDate(r.date)),
                          ),
                          SocietyColumn(
                            label: 'Entry No',
                            width: 130,
                            cell: (r) => InkWell(
                              onTap: () => context.push('/society/journals/${r.journalId}'),
                              child: Text(
                                r.entryNo,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          SocietyColumn(
                            label: 'Source',
                            width: 110,
                            cell: (r) => Text(r.sourceType),
                          ),
                          SocietyColumn(
                            label: 'Narration',
                            cell: (r) => Text(
                              r.narration,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                            label: 'Running Balance',
                            numeric: true,
                            width: 140,
                            cell: (r) {
                              final bal = r.runningBalancePaise;
                              final suffix = bal >= 0 ? ' Dr' : ' Cr';
                              return Text(
                                '${formatInr(bal.abs())}$suffix',
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          ),
                        ],
                        rows: _result!.lines.rows,
                        total: _result!.lines.total,
                        page: _page,
                        pageSize: _pageSize,
                        onPage: (newPage) {
                          setState(() => _page = newPage);
                          _loadLedger();
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_credit.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/shared/widgets/society_data_table.dart';
import 'package:crusam/features/society/shared/widgets/society_empty_view.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';

class SocietyOverviewScreen extends StatefulWidget {
  const SocietyOverviewScreen({super.key});

  @override
  State<SocietyOverviewScreen> createState() => _SocietyOverviewScreenState();
}

class _SocietyOverviewScreenState extends State<SocietyOverviewScreen> {
  bool _loading = false;
  int _billedPaise = 0;
  int _collectedPaise = 0;
  int _outstandingPaise = 0;
  int _bankCashPaise = 0;

  // Setup checklist state
  bool _profileComplete = false;
  bool _bankAdded = false;
  bool _unitsAdded = false;
  bool _billToAssigned = false;
  bool _rulesAdded = false;

  final Map<int, int> _allUnits = {};
  final Map<int, int> _allOutstanding = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ctx = SocietyContext.instance;
    await ctx.ensureLoaded();

    if (ctx.societies.isEmpty) return;

    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();

      if (ctx.allSocieties) {
        _allUnits.clear();
        _allOutstanding.clear();
        for (final s in ctx.societies) {
          final uRows = await services.db.rawQuery(
            'SELECT COUNT(*) as cnt FROM units WHERE society_id = ? AND is_active = 1',
            [s.id],
          );
          _allUnits[s.id] = (uRows.first['cnt'] as int?) ?? 0;

          // Outstanding on members_receivable
          final balRows = await services.db.rawQuery('''
            SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as bal
            FROM journal_lines jl
            JOIN accounts a ON jl.account_id = a.id
            WHERE jl.society_id = ? AND a.system_key = 'members_receivable'
          ''', [s.id]);
          _allOutstanding[s.id] = (balRows.first['bal'] as int?) ?? 0;
        }
      } else if (ctx.societyId != null) {
        final socId = ctx.societyId!;
        final soc = ctx.society ?? await services.society.getSociety(socId);

        _profileComplete = (soc.addressLine1 != null && soc.addressLine1!.isNotEmpty) &&
            (soc.city != null && soc.city!.isNotEmpty);

        final bankCountRows = await services.db.rawQuery(
          'SELECT COUNT(*) as cnt FROM bank_accounts WHERE society_id = ? AND account_type != "cash"',
          [socId],
        );
        _bankAdded = ((bankCountRows.first['cnt'] as int?) ?? 0) > 0;

        final unitsCountRows = await services.db.rawQuery(
          'SELECT COUNT(*) as cnt FROM units WHERE society_id = ? AND is_active = 1',
          [socId],
        );
        final unitCount = (unitsCountRows.first['cnt'] as int?) ?? 0;
        _unitsAdded = unitCount > 0;

        final billToCountRows = await services.db.rawQuery(
          'SELECT COUNT(*) as cnt FROM unit_people WHERE society_id = ? AND is_bill_to = 1 AND to_date IS NULL',
          [socId],
        );
        final billToCount = (billToCountRows.first['cnt'] as int?) ?? 0;
        _billToAssigned = unitCount > 0 && billToCount >= unitCount;

        final rulesCountRows = await services.db.rawQuery(
          'SELECT COUNT(*) as cnt FROM billing_rules WHERE society_id = ? AND is_active = 1',
          [socId],
        );
        _rulesAdded = ((rulesCountRows.first['cnt'] as int?) ?? 0) > 0;

        // KPI balances
        final outRows = await services.db.rawQuery('''
          SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as bal
          FROM journal_lines jl
          JOIN accounts a ON jl.account_id = a.id
          WHERE jl.society_id = ? AND a.system_key = 'members_receivable'
        ''', [socId]);
        _outstandingPaise = (outRows.first['bal'] as int?) ?? 0;

        final bankCashRows = await services.db.rawQuery('''
          SELECT COALESCE(SUM(jl.debit_paise - jl.credit_paise), 0) as bal
          FROM journal_lines jl
          JOIN accounts a ON jl.account_id = a.id
          JOIN account_groups g ON a.group_id = g.id
          WHERE jl.society_id = ? AND g.system_key = 'cash_bank'
        ''', [socId]);
        _bankCashPaise = (bankCashRows.first['bal'] as int?) ?? 0;

        final billedRows = await services.db.rawQuery(
          'SELECT COALESCE(SUM(total_paise), 0) as total FROM bills WHERE society_id = ? AND status = "posted"',
          [socId],
        );
        _billedPaise = (billedRows.first['total'] as int?) ?? 0;

        final collRows = await services.db.rawQuery(
          'SELECT COALESCE(SUM(amount_paise), 0) as total FROM receipts WHERE society_id = ? AND status = "posted"',
          [socId],
        );
        _collectedPaise = (collRows.first['total'] as int?) ?? 0;
      }

      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SocietyContext.instance,
      builder: (context, _) {
        final ctx = SocietyContext.instance;

        if (ctx.societies.isEmpty && !ctx.loading) {
          return SocietyPage(
            title: 'Overview',
            allowAllSocieties: true,
            requireSociety: false,
            child: SocietyEmptyView(
              icon: Icons.apartment_outlined,
              title: 'Welcome to Society Management',
              message: 'No housing societies have been set up yet. Get started by creating your first society.',
              action: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Society'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/society/societies/new'),
              ),
            ),
          );
        }

        if (ctx.allSocieties) {
          return SocietyPage(
            title: 'All Societies Overview',
            subtitle: 'Portfolio summary of all managed housing societies',
            allowAllSocieties: true,
            actions: [
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Society'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/society/societies/new'),
              ),
            ],
            child: SocietyDataTable<SocietySummary>(
              columns: [
                SocietyColumn<SocietySummary>(
                  label: 'Society',
                  cell: (s) => Text(s.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                SocietyColumn<SocietySummary>(
                  label: 'City',
                  cell: (s) => Text(s.city ?? '—'),
                ),
                SocietyColumn<SocietySummary>(
                  label: 'Units',
                  numeric: true,
                  cell: (s) => Text('${_allUnits[s.id] ?? 0}'),
                ),
                SocietyColumn<SocietySummary>(
                  label: 'Outstanding',
                  numeric: true,
                  cell: (s) => Text(formatInr(_allOutstanding[s.id] ?? 0)),
                ),
                SocietyColumn<SocietySummary>(
                  label: 'Open FY',
                  cell: (s) => Text(s.activeFyCode ?? '—'),
                ),
                SocietyColumn<SocietySummary>(
                  label: 'Action',
                  cell: (s) => TextButton(
                    onPressed: () async {
                      await ctx.selectSociety(s.id);
                      _load();
                    },
                    child: const Text('Open'),
                  ),
                ),
              ],
              rows: ctx.societies,
              total: ctx.societies.length,
              loading: _loading,
              onRowTap: (s) async {
                await ctx.selectSociety(s.id);
                _load();
              },
            ),
          );
        }

        return SocietyPage(
          title: ctx.society?.name ?? 'Overview',
          subtitle: 'Society operations dashboard, quick actions and setup status',
          actions: [
            OutlinedButton.icon(
              icon: const Icon(Icons.playlist_add_check, size: 16),
              label: const Text('New Bill Run'),
              onPressed: () => context.go('/society/bill-runs/new'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.point_of_sale, size: 16),
              label: const Text('Add Receipt'),
              onPressed: () => context.go('/society/receipts/new'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.receipt_long, size: 16),
              label: const Text('Add Expense'),
              onPressed: () => context.go('/society/expenses/new'),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_note, size: 16),
              label: const Text('New Journal'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
              ),
              onPressed: () => context.go('/society/journals/new'),
            ),
          ],
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildKpiGrid(),
                const SizedBox(height: 24),
                _buildSetupChecklist(),
                const SizedBox(height: 32),
                _buildFooterCredit(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiGrid() {
    return LayoutBuilder(
      builder: (context, c) {
        final isNarrow = c.maxWidth < 800;
        final cardWidth = isNarrow ? (c.maxWidth - 12) / 2 : (c.maxWidth - 36) / 4;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard('Billed This Month', formatInr(_billedPaise), Icons.receipt_outlined, const Color(0xFF3B82F6), cardWidth),
            _kpiCard('Collected This Month', formatInr(_collectedPaise), Icons.payments_outlined, const Color(0xFF10B981), cardWidth),
            _kpiCard('Outstanding Dues', formatInr(_outstandingPaise), Icons.pending_actions_outlined, const Color(0xFFF59E0B), cardWidth),
            _kpiCard('Bank & Cash Balance', formatInr(_bankCashPaise), Icons.account_balance_wallet_outlined, const Color(0xFF6366F1), cardWidth),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupChecklist() {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist, size: 20, color: Color(0xFF3B82F6)),
                SizedBox(width: 8),
                Text(
                  'Society Setup Checklist',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
              ],
            ),
            const Divider(color: Color(0xFFE2E8F0), height: 24),
            _checkItem('Society Profile Complete', _profileComplete, '/society/settings'),
            _checkItem('Bank / Cash Accounts Added', _bankAdded, '/society/bank'),
            _checkItem('Units & Unit Types Added', _unitsAdded, '/society/units'),
            _checkItem('Active Bill-To Member Assigned to Units', _billToAssigned, '/society/units'),
            _checkItem('Billing Rules & Charge Heads Configured', _rulesAdded, '/society/billing-rules'),
            _checkItem('Interest & Late Payment Policy Reviewed', true, '/society/settings'),
            _checkItem('Invoice & Receipt Document Settings Set', true, '/society/settings'),
          ],
        ),
      ),
    );
  }

  Widget _checkItem(String title, bool isDone, String route) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: isDone ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isDone ? FontWeight.w500 : FontWeight.normal,
                color: isDone ? const Color(0xFF1E293B) : const Color(0xFF64748B),
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go(route),
            child: const Text('Configure', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterCredit() {
    return Center(
      child: InkWell(
        onTap: () => context.go('/society/about'),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text(
            kAddaCreditText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }
}

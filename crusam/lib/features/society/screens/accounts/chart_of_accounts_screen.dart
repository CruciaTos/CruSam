import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/money.dart';
import 'package:crusam/features/society/core/society_context.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/shared/widgets/society_page.dart';
import 'package:crusam/features/society/shared/widgets/status_chip.dart';
import 'package:crusam/features/society/screens/accounts/widgets/opening_balances_tab.dart';

class ChartOfAccountsScreen extends StatefulWidget {
  const ChartOfAccountsScreen({super.key});

  @override
  State<ChartOfAccountsScreen> createState() => _ChartOfAccountsScreenState();
}

class _ChartOfAccountsScreenState extends State<ChartOfAccountsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loading = true;
  List<AccountTreeGroup> _tree = [];
  final Map<int, int> _balances = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final ctx = SocietyContext.instance;
    final societyId = ctx.societyId;
    if (societyId == null) return;

    setState(() => _loading = true);
    try {
      final services = await SocietyServices.instance();
      final groups = await services.ledger.chartOfAccounts(societyId, includeInactive: true);

      _balances.clear();
      final balRows = await services.db.rawQuery('''
        SELECT jl.account_id, SUM(jl.debit_paise - jl.credit_paise) as bal
        FROM journal_lines jl
        JOIN journal_entries je ON jl.entry_id = je.id
        WHERE jl.society_id = ? AND je.status = 'posted'
        GROUP BY jl.account_id
      ''', [societyId]);

      for (final r in balRows) {
        _balances[r['account_id'] as int] = (r['bal'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() {
          _tree = groups;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final societyId = SocietyContext.instance.societyId;

    return SocietyPage(
      title: 'Chart of Accounts',
      subtitle: 'Double-entry general ledger chart, system accounts and opening balances',
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: const Color(0xFF3B82F6),
              unselectedLabelColor: const Color(0xFF64748B),
              indicatorColor: const Color(0xFF3B82F6),
              tabs: const [
                Tab(text: 'Chart of Accounts'),
                Tab(text: 'Opening Balances'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildTreeView(),
                societyId == null
                    ? const SizedBox.shrink()
                    : OpeningBalancesTab(societyId: societyId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeView() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tree.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, idx) {
          final groupTree = _tree[idx];
          return _buildGroupCard(groupTree);
        },
      ),
    );
  }

  Widget _buildGroupCard(AccountTreeGroup tg) {
    final g = tg.group;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(g.code, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
            ),
            const SizedBox(width: 8),
            Text(g.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(g.accountType.toUpperCase(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF3B82F6))),
            ),
          ],
        ),
        children: tg.accounts.map((a) {
          final bal = _balances[a.id] ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFF1F5F9))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  child: Text(a.code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    a.name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF1E293B)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(a.accountKind, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ),
                const SizedBox(width: 24),
                SizedBox(
                  width: 140,
                  child: Text(
                    formatInr(bal),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: bal < 0 ? const Color(0xFFB91C1C) : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                StatusChip(status: a.isActive ? 'active' : 'closed'),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

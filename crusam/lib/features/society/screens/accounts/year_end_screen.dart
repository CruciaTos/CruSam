import 'package:flutter/material.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/society_models.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class YearEndScreen extends StatefulWidget {
  const YearEndScreen({super.key});

  @override
  State<YearEndScreen> createState() => _YearEndScreenState();
}

class _YearEndScreenState extends State<YearEndScreen> {
  bool _isLoading = true;
  String? _error;
  List<FinancialYear> _years = [];
  FinancialYear? _selectedFy;
  List<String> _preconditions = [];

  @override
  void initState() {
    super.initState();
    _loadYears();
  }

  Future<void> _loadYears() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final services = await SocietyServices.instance();
      final years = await services.society.listFinancialYears(societyId);

      FinancialYear? active;
      if (_selectedFy != null) {
        final match = years.where((y) => y.id == _selectedFy!.id);
        if (match.isNotEmpty) active = match.first;
      }
      active ??= years.where((y) => y.isOpen).isNotEmpty
          ? years.firstWhere((y) => y.isOpen)
          : (years.isNotEmpty ? years.first : null);

      List<String> issues = [];
      if (active != null && active.isOpen) {
        issues = await services.yearEnd.checkPreconditions(societyId, active.id);
      }

      if (mounted) {
        setState(() {
          _years = years;
          _selectedFy = active;
          _preconditions = issues;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _showCloseYearDialog() {
    final societyId = SocietyContext.instance.societyId;
    final fy = _selectedFy;
    if (societyId == null || fy == null) return;

    final hasWarning = _preconditions.any((p) => p.startsWith('WARNING:'));
    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Close Financial Year ${fy.code}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Closing FY ${fy.code} will generate a Year End closing journal entry transferring all income and expenditure accounts to 2801 Income & Expenditure Account.'),
              const SizedBox(height: 12),
              const Text('This marks the year as closed and allows opening the subsequent financial year.'),
              if (hasWarning) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: const Text(
                    'Opening balance adjustment account is non-zero. To proceed despite this warning, type "CLOSE" below.',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmCtrl,
                  decoration: const InputDecoration(labelText: 'Type "CLOSE" to confirm'),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (hasWarning && confirmCtrl.text.trim() != 'CLOSE') {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please type "CLOSE" to confirm')));
                return;
              }
              try {
                final services = await SocietyServices.instance();
                await services.yearEnd.closeYear(
                  societyId,
                  fy.id,
                  confirmation: confirmCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadYears();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error closing year: $e')));
                }
              }
            },
            child: const Text('Close Financial Year'),
          ),
        ],
      ),
    );
  }

  void _showReopenDialog() {
    final societyId = SocietyContext.instance.societyId;
    final fy = _selectedFy;
    if (societyId == null || fy == null) return;

    final confirmCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reopen Financial Year ${fy.code}'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Reopening FY ${fy.code} will reverse the year-end closing entry and any appropriations, returning the year to Open status.'),
              const SizedBox(height: 12),
              const Text('This is only permitted for the most recently closed financial year.'),
              const SizedBox(height: 16),
              TextField(
                controller: confirmCtrl,
                decoration: const InputDecoration(labelText: 'Type "REOPEN" to confirm *'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () async {
              if (confirmCtrl.text.trim() != 'REOPEN') {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please type "REOPEN" to confirm')));
                return;
              }
              try {
                final services = await SocietyServices.instance();
                await services.yearEnd.reopenYear(
                  societyId,
                  fy.id,
                  confirmCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                _loadYears();
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error reopening year: $e')));
                }
              }
            },
            child: const Text('Reopen Year'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'Financial Year End Close',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_error != null) return SocietyErrorView(message: _error!, onRetry: _loadYears);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: List of financial years
        SizedBox(
          width: 300,
          child: Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _years.length,
              separatorBuilder: (_, index) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final y = _years[i];
                final isSel = y.id == _selectedFy?.id;
                return ListTile(
                  selected: isSel,
                  selectedTileColor: Colors.blue.shade50,
                  title: Text('FY ${y.code}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${y.startDate} to ${y.endDate}'),
                  trailing: Chip(
                    label: Text(y.isOpen ? 'OPEN' : 'CLOSED', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                    backgroundColor: y.isOpen ? Colors.green.shade50 : Colors.grey.shade200,
                    side: BorderSide(color: y.isOpen ? Colors.green.shade300 : Colors.grey.shade400),
                    padding: EdgeInsets.zero,
                  ),
                  onTap: () {
                    setState(() => _selectedFy = y);
                    _loadYears();
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 20),

        // Right Column: Details & Close / Reopen Panel
        Expanded(
          child: _selectedFy == null
              ? const SizedBox.shrink()
              : Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _selectedFy!.isOpen ? _buildOpenYearPanel() : _buildClosedYearPanel(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildOpenYearPanel() {
    final fy = _selectedFy!;
    final blockingIssues = _preconditions.where((i) => !i.startsWith('WARNING:')).toList();
    final warnings = _preconditions.where((i) => i.startsWith('WARNING:')).toList();
    final canClose = blockingIssues.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Close FY ${fy.code}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Period: ${fy.startDate} to ${fy.endDate}', style: const TextStyle(color: Colors.black54)),
              ],
            ),
            FilledButton.icon(
              onPressed: canClose ? _showCloseYearDialog : null,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Close Financial Year'),
            ),
          ],
        ),
        const Divider(height: 32),

        const Text('Preconditions Checklist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),

        _checklistRow('Year Status: Open', isPass: true),
        _checklistRow(
          'All prior financial years are closed',
          isPass: !blockingIssues.any((i) => i.contains('Prior financial years')),
          message: blockingIssues.where((i) => i.contains('Prior financial years')).firstOrNull,
        ),
        _checklistRow(
          'No draft member bills or bill runs',
          isPass: !blockingIssues.any((i) => i.contains('draft member bills') || i.contains('draft bill runs')),
          message: blockingIssues.where((i) => i.contains('draft member bills') || i.contains('draft bill runs')).firstOrNull,
        ),
        _checklistRow(
          'Trial balance is in parity',
          isPass: !blockingIssues.any((i) => i.contains('Trial balance is out of balance')),
          message: blockingIssues.where((i) => i.contains('Trial balance is out of balance')).firstOrNull,
        ),

        if (warnings.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amber.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(warnings.first, style: const TextStyle(fontSize: 12, color: Colors.brown))),
              ],
            ),
          ),
        ],

        if (!canClose) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Resolve the blocking precondition above before closing the financial year.',
                    style: TextStyle(fontSize: 12, color: Colors.red.shade900),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildClosedYearPanel() {
    final fy = _selectedFy!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FY ${fy.code} - Closed', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('Period: ${fy.startDate} to ${fy.endDate}', style: const TextStyle(color: Colors.black54)),
              ],
            ),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(foregroundColor: Colors.red.shade800),
              onPressed: _showReopenDialog,
              icon: const Icon(Icons.lock_open_outlined),
              label: const Text('Reopen Year'),
            ),
          ],
        ),
        const Divider(height: 32),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.green, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('This financial year is closed.', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text(
                      'All income and expenditure heads have been transferred to retained reserves. No new entries can be posted dated within this period.',
                      style: TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _checklistRow(String title, {required bool isPass, String? message}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPass ? Icons.check_circle : Icons.cancel,
            color: isPass ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isPass ? Colors.black87 : Colors.red.shade900)),
                if (message != null && !isPass)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(message, style: TextStyle(fontSize: 11, color: Colors.red.shade700)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

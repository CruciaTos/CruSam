import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/money.dart';
import '../../core/society_context.dart';
import '../../core/society_services.dart';
import '../../data/models/billing_models.dart';
import '../../domain/billing/billing_service.dart';
import '../../shared/widgets/amount_summary.dart';
import '../../shared/widgets/society_error_view.dart';
import '../../shared/widgets/society_page.dart';

class BillRunNewScreen extends StatefulWidget {
  const BillRunNewScreen({super.key});

  @override
  State<BillRunNewScreen> createState() => _BillRunNewScreenState();
}

class _BillRunNewScreenState extends State<BillRunNewScreen> {
  String _frequency = 'monthly';
  late final TextEditingController _fromCtrl;
  late final TextEditingController _toCtrl;
  late final TextEditingController _billDateCtrl;
  late final TextEditingController _dueDateCtrl;
  late final TextEditingController _interestThroughCtrl;
  late final TextEditingController _notesCtrl;

  bool _calculating = false;
  bool _submitting = false;
  String? _error;
  BillRunPreviewResult? _preview;
  bool _acknowledgedWarnings = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final lastDay = DateTime(now.year, now.month + 1, 0).day.toString().padLeft(2, '0');

    _fromCtrl = TextEditingController(text: '$year-$month-01');
    _toCtrl = TextEditingController(text: '$year-$month-$lastDay');
    _billDateCtrl = TextEditingController(text: '$year-$month-01');
    _dueDateCtrl = TextEditingController(text: '$year-$month-20');
    _interestThroughCtrl = TextEditingController();
    _notesCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _billDateCtrl.dispose();
    _dueDateCtrl.dispose();
    _interestThroughCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _onFrequencyChanged(String? freq) {
    if (freq == null) return;
    setState(() {
      _frequency = freq;
      _preview = null;
      _acknowledgedWarnings = false;
    });
  }

  BillRunDraft _buildDraft() {
    return BillRunDraft(
      frequency: _frequency,
      periodFrom: _fromCtrl.text.trim(),
      periodTo: _toCtrl.text.trim(),
      billDate: _billDateCtrl.text.trim(),
      dueDate: _dueDateCtrl.text.trim(),
      interestThrough: _interestThroughCtrl.text.trim().isEmpty ? null : _interestThroughCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );
  }

  Future<void> _runPreview() async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    setState(() {
      _calculating = true;
      _error = null;
      _preview = null;
      _acknowledgedWarnings = false;
    });

    try {
      final draft = _buildDraft();
      final services = await SocietyServices.instance();
      final res = await services.billing.previewBillRun(societyId, draft);
      if (mounted) {
        setState(() {
          _preview = res;
          _calculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _calculating = false;
        });
      }
    }
  }

  Future<void> _createRun({required bool autoPost}) async {
    final societyId = SocietyContext.instance.societyId;
    if (societyId == null) return;

    if (_preview == null) return;
    if (_preview!.blockers.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot proceed with blocking errors.')),
      );
      return;
    }

    if (_preview!.warnings.isNotEmpty && !_acknowledgedWarnings) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please acknowledge the warnings to continue.')),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final draft = _buildDraft();
      final services = await SocietyServices.instance();
      final runId = await services.billing.createDraftRun(societyId, draft);

      if (autoPost) {
        await services.billing.postBillRun(societyId, runId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(autoPost ? 'Bill run posted successfully!' : 'Draft bill run created.')),
        );
        context.go('/society/bill-runs/$runId');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SocietyPage(
      title: 'New Bill Run',
      subtitle: 'Configure billing parameters, preview calculations, review blockers, and generate bills',
      actions: [
        OutlinedButton(
          onPressed: () => context.go('/society/bill-runs'),
          child: const Text('Cancel'),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SocietyErrorView(message: _error!, onRetry: _runPreview),
              ),

            // Step 1: Configuration Form
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('1. Billing Period & Parameters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _frequency,
                            decoration: const InputDecoration(labelText: 'Billing Frequency *'),
                            items: const [
                              DropdownMenuItem(value: 'monthly', child: Text('Monthly')),
                              DropdownMenuItem(value: 'quarterly', child: Text('Quarterly')),
                              DropdownMenuItem(value: 'half_yearly', child: Text('Half Yearly')),
                              DropdownMenuItem(value: 'yearly', child: Text('Yearly')),
                            ],
                            onChanged: _onFrequencyChanged,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _fromCtrl,
                            decoration: const InputDecoration(labelText: 'Period From (YYYY-MM-DD) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _toCtrl,
                            decoration: const InputDecoration(labelText: 'Period To (YYYY-MM-DD) *'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _billDateCtrl,
                            decoration: const InputDecoration(labelText: 'Bill Date (YYYY-MM-DD) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _dueDateCtrl,
                            decoration: const InputDecoration(labelText: 'Due Date (YYYY-MM-DD) *'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _interestThroughCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Interest Through (Optional)',
                              hintText: 'Defaults to bill period start',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes / Remarks (Optional)'),
                    ),
                    const SizedBox(height: 20),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _calculating ? null : _runPreview,
                        icon: _calculating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.calculate_outlined, size: 18),
                        label: const Text('Calculate Preview'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Step 2 & 3: Preview and Review
            if (_preview != null) ...[
              // Blockers Section
              if (_preview!.blockers.isNotEmpty)
                Card(
                  color: const Color(0xFFFEF2F2),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                            const SizedBox(width: 8),
                            Text(
                              'Blocking Errors (${_preview!.blockers.length}) - Posting Disabled',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626), fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._preview!.blockers.map((b) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $b', style: const TextStyle(color: Color(0xFF991B1B))),
                            )),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              // Warnings Section
              if (_preview!.warnings.isNotEmpty)
                Card(
                  color: const Color(0xFFFFFBEB),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_amber_outlined, color: Color(0xFFD97706)),
                            const SizedBox(width: 8),
                            Text(
                              'Warnings (${_preview!.warnings.length})',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706), fontSize: 15),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ..._preview!.warnings.map((w) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('• $w', style: const TextStyle(color: Color(0xFF92400E))),
                            )),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('I acknowledge these warnings and wish to proceed.', style: TextStyle(fontWeight: FontWeight.w600)),
                          value: _acknowledgedWarnings,
                          onChanged: (v) => setState(() => _acknowledgedWarnings = v ?? false),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Preview Metrics
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Units', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${_preview!.totalUnits}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Billable Units', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${_preview!.billableUnits}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total Billing Amount', style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(formatPaise(_preview!.totalPaise), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Color(0xFF047857))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // Action Buttons
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _submitting || _preview!.blockers.isNotEmpty ? null : () => _createRun(autoPost: false),
                        child: const Text('Save as Draft'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _submitting ||
                                _preview!.blockers.isNotEmpty ||
                                (_preview!.warnings.isNotEmpty && !_acknowledgedWarnings)
                            ? null
                            : () => _createRun(autoPost: true),
                        icon: const Icon(Icons.send_outlined, size: 18),
                        label: const Text('Post Bill Run'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

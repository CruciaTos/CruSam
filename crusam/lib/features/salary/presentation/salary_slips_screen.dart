import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../widgets/salary_slip_preview.dart';

class SalarySlipsScreen extends StatefulWidget {
  const SalarySlipsScreen({super.key});

  @override
  State<SalarySlipsScreen> createState() => _SalarySlipsScreenState();
}

class _SalarySlipsScreenState extends State<SalarySlipsScreen> {
  CompanyConfigModel _config = const CompanyConfigModel();

  // When you add categorisation, expose this as a filter/tab selection.
  // String _selectedCode = 'All';

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final map = await DatabaseHelper.instance.getCompanyConfig();
    if (map != null && mounted) {
      setState(() => _config = CompanyConfigModel.fromMap(map));
    }
  }

  void _showPreview() {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _SalarySlipPreviewDialog(config: _config),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          children: [
            // ── Toolbar ─────────────────────────────────────────────────────
            Row(
              children: [
                Text('Salary Slips', style: AppTextStyles.h3),
                const Spacer(),
                // TODO: When adding code categorisation, insert a tab bar or
                // DropdownButton here (see navigation note at bottom of file).
                OutlinedButton.icon(
                  onPressed: _showPreview,
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Preview'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // ── Placeholder body ────────────────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 64, color: AppColors.slate300),
                    const SizedBox(height: 16),
                    Text('Salary Slips', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text(
                      'Select a month & employee to generate slips.',
                      style: AppTextStyles.small,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showPreview,
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Preview Sample Slip'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Preview Dialog ─────────────────────────────────────────────────────────────
class _SalarySlipPreviewDialog extends StatelessWidget {
  final CompanyConfigModel config;
  const _SalarySlipPreviewDialog({required this.config});

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              // ── Header bar ─────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.slate50,
                  border:
                      Border(bottom: BorderSide(color: AppColors.slate200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Salary Slip – Preview',
                        style: AppTextStyles.h4,
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ),
              // ── Scrollable preview ─────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: SalarySlipPreview(config: config),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/*
 * ── NAVIGATION NOTE: Adding Code Categorisation ──────────────────────────────
 *
 * When you're ready to filter salary slips by company code (F&B, I&L, etc.),
 * the recommended approach is a TabBar inside this screen — NOT new sidebar routes.
 *
 * Reason: codes are filters on the same document type, not separate features.
 * Adding 5-6 sidebar items for codes would clutter the nav and break the UX
 * pattern established by Attachment A/B (which are genuinely different docs).
 *
 * Implementation sketch:
 *
 *   class SalarySlipsScreen extends StatefulWidget ...
 *
 *   @override
 *   Widget build(BuildContext context) => DefaultTabController(
 *     length: _codes.length + 1,   // +1 for "All"
 *     child: Column(children: [
 *       _Toolbar(...),
 *       TabBar(tabs: [Tab(text: 'All'), ...codes.map((c) => Tab(text: c))]),
 *       Expanded(child: TabBarView(children: [
 *         _SlipList(filter: null),
 *         ..._codes.map((c) => _SlipList(filter: c)),
 *       ])),
 *     ]),
 *   );
 *
 * The 'Salary Slips' sidebar item stays exactly as-is.
 * ──────────────────────────────────────────────────────────────────────────────
 */
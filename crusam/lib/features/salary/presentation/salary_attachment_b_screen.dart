import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../widgets/attachment_b_preview.dart';

class SalaryAttachmentBScreen extends StatefulWidget {
  const SalaryAttachmentBScreen({super.key});

  @override
  State<SalaryAttachmentBScreen> createState() =>
      _SalaryAttachmentBScreenState();
}

class _SalaryAttachmentBScreenState extends State<SalaryAttachmentBScreen> {
  CompanyConfigModel _config = const CompanyConfigModel();

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
      builder: (_) => _AttachmentBPreviewDialog(config: _config),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          children: [
            // ── Toolbar ────────────────────────────────────────────────────
            Row(
              children: [
                Text('Attachment B', style: AppTextStyles.h3),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _showPreview,
                  icon: const Icon(Icons.description_outlined, size: 16),
                  label: const Text('Preview'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            // ── Placeholder body ───────────────────────────────────────────
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file_outlined,
                        size: 64, color: AppColors.slate300),
                    const SizedBox(height: 16),
                    Text('Attachment B', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text('PF & ESIC Deduction Statement',
                        style: AppTextStyles.small),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showPreview,
                      icon: const Icon(Icons.description_outlined, size: 16),
                      label: const Text('Preview Attachment B'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

// ── Preview dialog ─────────────────────────────────────────────────────────────
class _AttachmentBPreviewDialog extends StatelessWidget {
  final CompanyConfigModel config;
  const _AttachmentBPreviewDialog({required this.config});

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.xl),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              // ── Header bar ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.slate50,
                  border: Border(bottom: BorderSide(color: AppColors.slate200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Attachment B – Preview',
                          style: AppTextStyles.h4),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Close'),
                    ),
                  ],
                ),
              ),
              // ── Scrollable preview ────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: AttachmentBPreview(config: config),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
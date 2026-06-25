import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../auth/data/models/user_model.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/update_card.dart';
import 'package:crusam/features/profile/widgets/backup_restore_card.dart';
import 'package:crusam/features/profile/widgets/export_paths_card.dart';
import 'package:crusam/features/profile/widgets/gmail_account_card.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Profile screen – PC‑local only (no cloud login)
// ─────────────────────────────────────────────────────────────────────────────

class _PdfMethodCard extends StatelessWidget {
  const _PdfMethodCard();

  @override
  Widget build(BuildContext context) {
    final prefs = ExportPreferencesNotifier.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 18, color: AppColors.slate500),
              const SizedBox(width: 8),
              Text('PDF Generation', style: AppTextStyles.h4),
            ]),
            const SizedBox(height: 4),
            Text(
              'Applies to Tax Invoice & Voucher PDFs only.',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prefs.useWidgetPdfForInvoiceVoucher
                            ? 'Widget-based (Better Quality)'
                            : 'Screenshot-based (Default)',
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prefs.useWidgetPdfForInvoiceVoucher
                            ? 'Generates PDF using structured pw widgets — crisp text, no rasterization.'
                            : 'Captures a screenshot of the preview — matches on-screen appearance exactly.',
                        style: AppTextStyles.small
                            .copyWith(color: AppColors.slate500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: prefs.useWidgetPdfForInvoiceVoucher,
                  activeColor: AppColors.indigo600,
                  onChanged: (v) => prefs.setUseWidgetPdf(v),
                ),
              ],
            ),
            if (prefs.useWidgetPdfForInvoiceVoucher) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  border: Border.all(color: AppColors.indigo500.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.indigo600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Widget PDF is active for Tax Invoice & Voucher exports.',
                      style: AppTextStyles.small.copyWith(
                          color: AppColors.indigo600,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthNotifier.instance;

  // Generic local user identity – no real authentication required
  static const _localUserName = 'Aarti User';
  static const _localUserEmail = 'local@pc';
  static const _localAuthMethod = 'Local (PC)';

  @override
  void initState() {
    super.initState();
    ExportPreferencesNotifier.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Generic local profile header
              _LocalHeader(),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _LocalInfoCard(),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: const [
                        ExportPathsCard(),
                        SizedBox(height: 20),
                        _PdfMethodCard(),
                        SizedBox(height: 20),
                        BackupRestoreCard(),
                        SizedBox(height: 20),
                        GmailAccountCard(),
                        SizedBox(height: 20),
                        UpdateCard(),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Generic local user header ──────────────────────────────────────────────

class _LocalHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            const AvatarWidget(
              displayName: _ProfileScreenState._localUserName,
              avatarPath: null,
              size: 72,
              showBorder: true,
              borderColor: AppColors.indigo400,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _ProfileScreenState._localUserName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PC Local Account',
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.slate400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x1A4F46E5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x334F46E5)),
                    ),
                    child: const Text(
                      _ProfileScreenState._localAuthMethod,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.indigo400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // No sign out button
          ],
        ),
      );
}

// ── Local info card (simple static info) ───────────────────────────────────

class _LocalInfoCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Local PC Information', style: AppTextStyles.h4),
            const SizedBox(height: 20),
            _infoRow(Icons.computer_outlined, 'Instance',
                'This PC – ${Platform.localHostname}'),
            _infoRow(Icons.folder_outlined, 'Data Storage',
                'Local SQLite (per Windows user)'),
            _infoRow(Icons.cloud_off_outlined, 'Cloud Sync',
                'Disabled – manual backup only'),
            _infoRow(Icons.security_outlined, 'Access',
                'No login required – PC‑local only'),
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.slate400),
            const SizedBox(width: 10),
            Text('$label:', style: AppTextStyles.small),
            const SizedBox(width: 6),
            Expanded(
              child: Text(value,
                  style: AppTextStyles.small.copyWith(
                      color: AppColors.slate700,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
}
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/updater/update_service.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/update_card.dart';
import '../widgets/backup_restore_card.dart';
import '../widgets/data_location_card.dart';
import '../widgets/export_paths_card.dart';
import '../widgets/gmail_account_card.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – consistent with the indigo theme
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';

  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );

  static const tsBody = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
  );

  static const double radius  = 6.0;
  static const double cRadius = 10.0;
  static const double padH    = 18.0;
  static const double padV    = 16.0;
}

// ════════════════════════════════════════════════════════════════════════════
//  ProfileScreen
// ════════════════════════════════════════════════════════════════════════════
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth = AuthNotifier.instance;

  static const _localUserName = 'Crusam User';
  static const _localAuthMethod = 'Local (PC)';

  @override
  void initState() {
    super.initState();
    ExportPreferencesNotifier.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header (shows user name, local auth, and app version) ──
            const _ProfileHeader(),

            const SizedBox(height: 16),

            // ── Card list – Local Info first, then Update, then Gmail, then rest ──
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const _LocalInfoCard(),
                    const SizedBox(height: 12),
                    const UpdateCard(),
                    const SizedBox(height: 12),
                    const GmailAccountCard(),        // ← moved here
                    const SizedBox(height: 12),
                    const ExportPathsCard(),
                    const SizedBox(height: 12),
                    const _PdfMethodCard(),
                    const SizedBox(height: 12),
                    const BackupRestoreCard(),
                    const SizedBox(height: 12),
                    const DataLocationCard(),        // ← moved down
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header – fetches and displays the current version ───────────────────────
class _ProfileHeader extends StatefulWidget {
  const _ProfileHeader();

  @override
  State<_ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<_ProfileHeader> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _fetchVersion();
  }

  Future<void> _fetchVersion() async {
    try {
      final version = await UpdateService.getCurrentVersion();
      if (mounted) setState(() => _version = version);
    } catch (_) {
      if (mounted) setState(() => _version = 'unknown');
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: _Tok.padH, vertical: 10),
    decoration: BoxDecoration(
      color: _Tok.surfaceAlt,
      border: const Border(bottom: BorderSide(color: _Tok.divider)),
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(_Tok.cRadius),
        topRight: Radius.circular(_Tok.cRadius),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const AvatarWidget(
          displayName: _ProfileScreenState._localUserName,
          avatarPath: null,
          size: 32,
          showBorder: true,
          borderColor: _Tok.inkLight,
        ),
        const SizedBox(width: 12),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ProfileScreenState._localUserName,
              style: _Tok.tsInput.copyWith(
                fontWeight: FontWeight.w700,
                color: _Tok.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              _ProfileScreenState._localAuthMethod,
              style: _Tok.tsMeta.copyWith(fontSize: 10),
            ),
            const SizedBox(height: 1),
            Text(
              'v$_version',
              style: _Tok.tsMeta.copyWith(fontSize: 10, color: _Tok.inkMuted),
            ),
          ],
        ),
        const Spacer(),
      ],
    ),
  );
}

// ── Local info card ────────────────────────────────────────────────────────
class _LocalInfoCard extends StatelessWidget {
  const _LocalInfoCard();

  @override
  Widget build(BuildContext context) => _ThemedCard(
    title: 'PC Information',
    icon: Icons.computer_outlined,
    children: [
      _InfoRow(icon: Icons.computer_outlined, label: 'Instance',
          value: 'This PC – ${Platform.localHostname}'),
      _InfoRow(icon: Icons.folder_outlined, label: 'Data Storage',
          value: 'See "Data Storage Location" card for the live path'),
      _InfoRow(icon: Icons.cloud_off_outlined, label: 'Cloud Sync',
          value: 'Disabled – manual backup only'),
      _InfoRow(icon: Icons.security_outlined, label: 'Access',
          value: 'No login required – PC‑local only'),
    ],
  );
}

// ── PDF method card ────────────────────────────────────────────────────────
class _PdfMethodCard extends StatelessWidget {
  const _PdfMethodCard();

  @override
  Widget build(BuildContext context) {
    final prefs = ExportPreferencesNotifier.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) => _ThemedCard(
        title: 'PDF Generation',
        icon: Icons.picture_as_pdf_outlined,
        children: [
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
                      style: _Tok.tsInput.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prefs.useWidgetPdfForInvoiceVoucher
                          ? 'Generates PDF using structured pw widgets — crisp text, no rasterization.'
                          : 'Captures a screenshot of the preview — matches on-screen appearance exactly.',
                      style: _Tok.tsMeta,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: prefs.useWidgetPdfForInvoiceVoucher,
                activeColor: _Tok.inkLight,
                onChanged: (v) => prefs.setUseWidgetPdf(v),
              ),
            ],
          ),
          if (prefs.useWidgetPdfForInvoiceVoucher) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _Tok.surfaceAlt,
                border: Border.all(color: _Tok.inkLight.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(_Tok.radius),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: _Tok.inkLight),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Widget PDF is active for Tax Invoice & Voucher exports.',
                      style: _Tok.tsMeta.copyWith(
                        color: _Tok.inkLight,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Generic themed card wrapper ────────────────────────────────────────────
class _ThemedCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  const _ThemedCard({
    required this.title,
    required this.icon,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: _Tok.surface,
      border: Border.all(color: _Tok.border),
      borderRadius: BorderRadius.circular(_Tok.cRadius),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card header
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: _Tok.padH),
          decoration: const BoxDecoration(
            color: _Tok.surfaceAlt,
            border: Border(bottom: BorderSide(color: _Tok.divider)),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(_Tok.cRadius),
              topRight: Radius.circular(_Tok.cRadius),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _Tok.ink,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Icon(icon, size: 12, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Text(title.toUpperCase(), style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
        ),
        // Content
        Padding(
          padding: const EdgeInsets.all(_Tok.padV),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    ),
  );
}

// ── Info row (used in LocalInfoCard) ───────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, size: 16, color: _Tok.inkMuted),
        const SizedBox(width: 10),
        Text('$label:', style: _Tok.tsLabel),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
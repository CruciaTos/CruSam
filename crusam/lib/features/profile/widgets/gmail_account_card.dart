// lib/features/profile/widgets/gmail_account_card.dart
//
// Connect/disconnect the Gmail account invoices get sent from. Same card
// shape and state-handling convention as BackupRestoreCard right next to it.
//
// This is intentionally just identity + connect/disconnect — it doesn't
// know anything about invoices or sending. SendInvoiceDialog is the only
// place that actually calls GmailService; this card just manages whether
// there's an authenticated account for it to use.

import 'package:flutter/material.dart';

import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

class GmailAccountCard extends StatefulWidget {
  const GmailAccountCard({super.key});

  @override
  State<GmailAccountCard> createState() => _GmailAccountCardState();
}

class _GmailAccountCardState extends State<GmailAccountCard> {
  String? _statusMessage;
  bool _statusIsError = false;

  Future<void> _connect() async {
    setState(() => _statusMessage = null);
    final ok = await GoogleAuthService.instance.signIn();
    if (!mounted) return;
    setState(() {
      _statusMessage = ok
          ? 'Connected as ${GoogleAuthService.instance.userEmail ?? ""}.'
          : 'Sign-in was cancelled or failed.';
      _statusIsError = !ok;
    });
  }

  Future<void> _disconnect() async {
    setState(() => _statusMessage = null);
    await GoogleAuthService.instance.signOut();
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Gmail account disconnected.';
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: GoogleAuthService.instance,
      builder: (ctx, _) {
        final auth = GoogleAuthService.instance;
        final connected = auth.isSignedIn;
        final busy = auth.isLoading;

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.slate200),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(children: [
                const Icon(Icons.mail_outline,
                    size: 18, color: AppColors.slate500),
                const SizedBox(width: 8),
                Text('Email Sending (Gmail)', style: AppTextStyles.h4),
              ]),
              const SizedBox(height: 4),
              Text(
                connected
                    ? 'Invoices sent from Crusam go out from this account.'
                    : 'Connect a Gmail account to send invoices directly '
                        'from Crusam.',
                style: AppTextStyles.small.copyWith(color: AppColors.slate500),
              ),

              const SizedBox(height: 20),

              // ── Status / action row ──────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: connected ? AppColors.emerald50 : AppColors.indigo50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      connected ? Icons.check_circle_outline : Icons.link,
                      size: 20,
                      color: connected ? AppColors.emerald600 : AppColors.indigo600,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          connected ? 'Connected' : 'Not connected',
                          style: AppTextStyles.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          connected
                              ? (auth.userEmail ?? '—')
                              : 'No Gmail account linked yet.',
                          style: AppTextStyles.small.copyWith(
                              color: AppColors.slate500, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    height: 36,
                    child: connected
                        ? OutlinedButton(
                            onPressed: busy ? null : _disconnect,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(color: Color(0xFFFECACA)),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Disconnect'),
                          )
                        : ElevatedButton(
                            onPressed: busy ? null : _connect,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                            child: busy
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Connect'),
                          ),
                  ),
                ],
              ),

              // ── Status message ───────────────────────────────────────────
              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _statusIsError
                        ? const Color(0xFFFEF2F2)
                        : AppColors.emerald50,
                    border: Border.all(
                      color: _statusIsError
                          ? const Color(0xFFFECACA)
                          : AppColors.emerald100,
                    ),
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _statusIsError
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        size: 15,
                        color: _statusIsError
                            ? const Color(0xFFDC2626)
                            : AppColors.emerald700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusMessage!,
                          style: AppTextStyles.small.copyWith(
                            color: _statusIsError
                                ? const Color(0xFFDC2626)
                                : AppColors.emerald700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _statusMessage = null),
                        child: Icon(Icons.close,
                            size: 14,
                            color: _statusIsError
                                ? const Color(0xFFDC2626)
                                : AppColors.emerald700),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
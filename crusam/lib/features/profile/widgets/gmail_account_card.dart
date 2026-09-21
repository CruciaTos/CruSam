// lib/features/profile/widgets/gmail_account_card.dart
//
// Connect/disconnect the Gmail account invoices get sent from.
// Visual styling now matches the indigo theme used across the app.

import 'package:flutter/material.dart';

import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/ink_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – consistent with the indigo theme
// ════════════════════════════════════════════════════════════════════════════
typedef _Tok = InkTokens;

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

        // Themed card wrapper
        return Container(
          decoration: BoxDecoration(
            color: _Tok.surface,
            border: Border.all(color: _Tok.border),
            borderRadius: BorderRadius.circular(_Tok.cRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header bar
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
                      child: const Icon(Icons.mail_outline, size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('GMAIL ACCOUNT', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
                  ],
                ),
              ),

              // Body content
              Padding(
                padding: const EdgeInsets.all(_Tok.padV),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Description
                    Text(
                      connected
                          ? 'Invoices sent from Crusam go out from this account.'
                          : 'Connect a Gmail account to send invoices directly from Crusam.',
                      style: _Tok.tsSmall,
                    ),

                    const SizedBox(height: 16),

                    // Status / action row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: connected ? const Color(0xFFD1FAE5) : _Tok.surfaceAlt,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            connected ? Icons.check_circle_outline : Icons.link,
                            size: 18,
                            color: connected ? const Color(0xFF065F46) : _Tok.inkLight,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connected ? 'Connected' : 'Not connected',
                                style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                connected
                                    ? (auth.userEmail ?? '—')
                                    : 'No Gmail account linked yet.',
                                style: _Tok.tsSmall,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 34,
                          child: connected
                              ? OutlinedButton(
                                  onPressed: busy ? null : _disconnect,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFDC2626),
                                    side: const BorderSide(color: Color(0xFFFECACA)),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(_Tok.radius),
                                    ),
                                    textStyle: _Tok.tsLabel.copyWith(fontSize: 12),
                                  ),
                                  child: busy
                                      ? const SizedBox(
                                          width: 14, height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                                        )
                                      : const Text('Disconnect'),
                                )
                              : ElevatedButton(
                                  onPressed: busy ? null : _connect,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _Tok.ink,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(_Tok.radius),
                                    ),
                                    elevation: 0,
                                    textStyle: _Tok.tsLabel.copyWith(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                  child: busy
                                      ? const SizedBox(
                                          width: 14, height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : const Text('Connect'),
                                ),
                        ),
                      ],
                    ),

                    // Status message (if any)
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _statusIsError
                              ? const Color(0xFFFEF2F2)
                              : _Tok.surfaceAlt,
                          border: Border.all(
                            color: _statusIsError
                                ? const Color(0xFFFECACA)
                                : _Tok.border,
                          ),
                          borderRadius: BorderRadius.circular(_Tok.radius),
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
                                  : _Tok.inkLight,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _statusMessage!,
                                style: _Tok.tsSmall.copyWith(
                                  color: _statusIsError
                                      ? const Color(0xFFDC2626)
                                      : _Tok.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => setState(() => _statusMessage = null),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: _statusIsError
                                    ? const Color(0xFFDC2626)
                                    : _Tok.inkLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
// lib/features/profile/widgets/gmail_account_card.dart
//
// Connect/disconnect the Gmail account invoices get sent from — with a Gmail
// app password (the simple way: no Google Cloud setup), or with the Google
// sign-in when this build has it configured. See EmailAccount.
// Visual styling matches the indigo theme used across the app.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/email/app_password_account.dart';
import '../../../core/email/email_account.dart';
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
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String? _statusMessage;
  bool _statusIsError = false;
  bool _sendingTest = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _status(String message, {bool error = false}) => setState(() {
        _statusMessage = message;
        _statusIsError = error;
      });

  Future<void> _connectAppPassword() async {
    setState(() => _statusMessage = null);
    final error = await AppPasswordAccount.instance
        .connect(_emailCtrl.text, _passwordCtrl.text);
    if (!mounted) return;
    if (error != null) {
      _status(error, error: true);
    } else {
      _passwordCtrl.clear();
      _status('Connected. A test email was sent to ${AppPasswordAccount.instance.email}.');
    }
  }

  Future<void> _sendTest() async {
    final to = AppPasswordAccount.instance.email;
    if (to == null) return;
    setState(() {
      _sendingTest = true;
      _statusMessage = null;
    });
    try {
      await AppPasswordAccount.instance.send(
        to: to,
        cc: '',
        subject: 'CruSam test email',
        bodyText: 'CruSam can send email from this account.',
        attachments: const [],
      );
      if (mounted) _status('Test email sent to $to.');
    } catch (e) {
      if (mounted) _status(AppPasswordAccount.describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _sendingTest = false);
    }
  }

  Future<void> _connectGoogle() async {
    setState(() => _statusMessage = null);
    final ok = await GoogleAuthService.instance.signIn();
    if (!mounted) return;
    ok
        ? _status('Connected as ${GoogleAuthService.instance.userEmail ?? ""}.')
        : _status('Google sign-in is not available in this version. Use an app '
            'password instead.', error: true);
  }

  Future<void> _disconnect() async {
    setState(() => _statusMessage = null);
    if (GoogleAuthService.instance.isSignedIn) {
      await GoogleAuthService.instance.signOut();
    } else {
      await AppPasswordAccount.instance.disconnect();
    }
    if (mounted) _status('Gmail account disconnected.');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EmailAccount.changes,
      builder: (ctx, _) {
        final google = GoogleAuthService.instance;
        final appPw = AppPasswordAccount.instance;
        final connected = EmailAccount.canSend;
        final busy = google.isLoading || appPw.isLoading;

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
                    Text(
                      connected
                          ? 'Invoices and salary documents sent from CruSam, or by '
                              'Claude, go out from this account.'
                          : 'Connect Gmail to send invoices and salary documents '
                              'from CruSam, and to let Claude send them for you.',
                      style: _Tok.tsSmall,
                    ),
                    const SizedBox(height: 16),
                    if (connected)
                      _connectedRow(busy, viaAppPassword: !google.isSignedIn)
                    else
                      _appPasswordForm(busy),
                    if (_statusMessage != null) ...[
                      const SizedBox(height: 14),
                      _statusBox(),
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

  Widget _connectedRow(bool busy, {required bool viaAppPassword}) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_outline, size: 18, color: Color(0xFF065F46)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connected', style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  EmailAccount.senderEmail.isEmpty ? '—' : EmailAccount.senderEmail,
                  style: _Tok.tsSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (viaAppPassword) ...[
            const SizedBox(width: 8),
            SizedBox(
              height: 34,
              child: TextButton(
                onPressed: busy || _sendingTest ? null : _sendTest,
                child: _sendingTest
                    ? const SizedBox(
                        width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send test email'),
              ),
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: busy ? null : _disconnect,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFECACA)),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.radius)),
                textStyle: _Tok.tsLabel.copyWith(fontSize: 12),
              ),
              child: const Text('Disconnect'),
            ),
          ),
        ],
      );

  Widget _appPasswordForm(bool busy) {
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(_Tok.radius)),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _emailCtrl,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          decoration: deco('Gmail address', 'name@gmail.com'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _passwordCtrl,
          enabled: !busy,
          obscureText: true,
          decoration: deco('App password', '16 letters from Google'),
          onSubmitted: (_) => _connectAppPassword(),
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Not your Gmail password. ', style: _Tok.tsSmall),
            InkWell(
              onTap: () => launchUrl(Uri.parse(AppPasswordAccount.helpUrl)),
              child: Text(
                'Create an app password',
                style: _Tok.tsSmall.copyWith(
                    color: _Tok.ink,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline),
              ),
            ),
            Text(' (needs 2-Step Verification).', style: _Tok.tsSmall),
          ],
        ),
        const SizedBox(height: 14),
        Row(children: [
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: busy ? null : _connectAppPassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: _Tok.ink,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.radius)),
                elevation: 0,
                textStyle: _Tok.tsLabel.copyWith(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
              ),
              child: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Connect'),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: busy ? null : _connectGoogle,
            child: Text('Sign in with Google instead',
                style: _Tok.tsSmall.copyWith(color: _Tok.inkLight)),
          ),
        ]),
      ],
    );
  }

  Widget _statusBox() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _statusIsError ? const Color(0xFFFEF2F2) : _Tok.surfaceAlt,
          border: Border.all(
            color: _statusIsError ? const Color(0xFFFECACA) : _Tok.border,
          ),
          borderRadius: BorderRadius.circular(_Tok.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
              size: 15,
              color: _statusIsError ? const Color(0xFFDC2626) : _Tok.inkLight,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _statusMessage!,
                style: _Tok.tsSmall.copyWith(
                  color: _statusIsError ? const Color(0xFFDC2626) : _Tok.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _statusMessage = null),
              child: Icon(
                Icons.close,
                size: 14,
                color: _statusIsError ? const Color(0xFFDC2626) : _Tok.inkLight,
              ),
            ),
          ],
        ),
      );
}

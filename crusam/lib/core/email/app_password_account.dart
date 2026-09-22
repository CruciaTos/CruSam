// lib/core/email/app_password_account.dart
//
// Sending through Gmail with an app password — no Google Cloud project,
// sign-in screen or weekly re-login. The user creates a 16-letter app
// password at myaccount.google.com/apppasswords (needs 2-Step Verification)
// and enters it in Profile; mail then goes out over Gmail's SMTP server and
// still lands in the account's Sent folder.
//
// Used by GmailService whenever the Google sign-in (GoogleAuthService) isn't
// connected. The password is kept in flutter_secure_storage, like the Google
// sign-in's tokens.

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mailer/mailer.dart' hide send;
import 'package:mailer/mailer.dart' as mailer show send;
import 'package:mailer/smtp_server/gmail.dart';

import '../../shared/models/generated_document.dart';

class AppPasswordAccount extends ChangeNotifier {
  AppPasswordAccount._();
  static final AppPasswordAccount instance = AppPasswordAccount._();

  static const helpUrl = 'https://myaccount.google.com/apppasswords';

  static const _storage = FlutterSecureStorage();
  static const _kEmail = 'crusam_smtp_email';
  static const _kPassword = 'crusam_smtp_app_password';

  String? email;
  String? _password;
  bool isLoading = false;

  bool get connected => email != null && _password != null;

  /// Called once from main.dart.
  Future<void> load() async {
    try {
      email = await _storage.read(key: _kEmail);
      _password = await _storage.read(key: _kPassword);
    } catch (e) {
      debugPrint('AppPasswordAccount.load: $e');
    }
    notifyListeners();
  }

  /// Checks [password] by sending a short test email to [address] itself,
  /// and saves it if Gmail accepts it. Returns an error message, or null.
  Future<String?> connect(String address, String password) async {
    final user = address.trim();
    final pw = password.replaceAll(RegExp(r'\s'), '');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(user)) {
      return 'Enter the full Gmail address, e.g. name@gmail.com.';
    }
    if (pw.length != 16) {
      return 'An app password has 16 letters. Copy it exactly as Google shows it.';
    }
    isLoading = true;
    notifyListeners();
    try {
      await _send(user, pw,
          to: user,
          cc: '',
          subject: 'CruSam can now send email',
          bodyText: 'This test email confirms that CruSam can send email from '
              'this account. Invoices and salary documents you send from '
              'CruSam (or ask Claude to send) will go out from here.',
          attachments: const []);
      await _storage.write(key: _kEmail, value: user);
      await _storage.write(key: _kPassword, value: pw);
      email = user;
      _password = pw;
      return null;
    } catch (e) {
      return describeError(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    try {
      await _storage.delete(key: _kEmail);
      await _storage.delete(key: _kPassword);
    } catch (e) {
      debugPrint('AppPasswordAccount.disconnect: $e');
    }
    email = null;
    _password = null;
    notifyListeners();
  }

  /// Sends one email; returns an id for the email log.
  Future<String> send({
    required String to,
    required String cc,
    required String subject,
    required String bodyText,
    required List<GeneratedDocument> attachments,
  }) async {
    if (!connected) throw StateError('No app password connected.');
    await _send(email!, _password!,
        to: to, cc: cc, subject: subject, bodyText: bodyText, attachments: attachments);
    return 'smtp-${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Plain-language reason a send failed.
  static String describeError(Object e) {
    if (e is SmtpClientAuthenticationException) {
      return "Gmail didn't accept that app password. Check the Gmail address, "
          'and use the 16-letter app password, not your normal Gmail password.';
    }
    if (e is MailerException) {
      final text = e.problems.map((p) => p.msg).join(' ');
      return 'Gmail refused the email: ${text.isEmpty ? e.message : text}';
    }
    return 'Could not reach Gmail. Check the internet connection and try '
        'again. ($e)';
  }

  static Future<void> _send(
    String user,
    String password, {
    required String to,
    required String cc,
    required String subject,
    required String bodyText,
    required List<GeneratedDocument> attachments,
  }) async {
    List<String> split(String list) =>
        list.split(RegExp(r'[,;]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    final message = Message()
      ..from = Address(user)
      ..recipients.addAll(split(to))
      ..ccRecipients.addAll(split(cc))
      ..subject = subject
      ..text = bodyText
      ..attachments = [
        for (final d in attachments)
          StreamAttachment(Stream.value(d.bytes), d.mimeType, fileName: d.filename),
      ];
    await mailer.send(message, gmail(user, password),
        timeout: const Duration(seconds: 60));
  }
}

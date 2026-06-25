// lib/core/email/gmail_service.dart
//
// Sends an email with a single PDF attachment via the Gmail API.
// Built entirely on the OAuth client GoogleAuthService already provides —
// no new auth plumbing here, just the Gmail-specific request shape.
//
// Gmail's API doesn't take a structured "to/subject/body/attachment"
// payload — it wants one base64url-encoded RFC 2822 message. That's what
// _buildRawMimeMessage constructs: one multipart/mixed message with a
// plain-text body part and a base64 PDF attachment part.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;

import '../sync/google_auth_service.dart';

class GmailNotSignedInException implements Exception {
  @override
  String toString() =>
      'Not signed in to Gmail. Connect a Gmail account in Settings first.';
}

class GmailSendException implements Exception {
  final String message;
  GmailSendException(this.message);
  @override
  String toString() => message;
}

class GmailService {
  GmailService._();
  static final GmailService instance = GmailService._();

  /// Sends [pdfBytes] as an email attachment.
  ///
  /// Returns the Gmail message id on success. Throws
  /// [GmailNotSignedInException] if no Gmail account is connected, or
  /// [GmailSendException] for anything the Gmail API itself rejects
  /// (bad recipient, quota, etc).
  Future<String> sendPdfEmail({
    required String to,
    String cc = '',
    required String subject,
    required String bodyText,
    required Uint8List pdfBytes,
    required String attachmentFilename,
  }) async {
    final api = await _api();
    if (api == null) throw GmailNotSignedInException();

    final fromAddress = GoogleAuthService.instance.userEmail ?? 'me';
    final raw = _buildRawMimeMessage(
      from: fromAddress,
      to: to,
      cc: cc,
      subject: subject,
      bodyText: bodyText,
      attachmentFilename: attachmentFilename,
      attachmentBytes: pdfBytes,
    );

    // One retry on a transient failure — Gmail sending at this volume never
    // hits real quota limits, this just smooths over a momentary network blip.
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final sent = await api.users.messages.send(
          gmail.Message(raw: raw),
          'me',
        );
        if (sent.id == null) {
          throw GmailSendException('Gmail accepted the request but returned no message id.');
        }
        return sent.id!;
      } catch (e) {
        final isLastAttempt = attempt == 2;
        debugPrint('GmailService.sendPdfEmail attempt $attempt failed: $e');
        if (isLastAttempt) {
          throw GmailSendException(_friendlyError(e));
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    // Unreachable — the loop above always returns or throws.
    throw GmailSendException('Send failed for an unknown reason.');
  }

  Future<gmail.GmailApi?> _api() async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    return gmail.GmailApi(client);
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('401') || msg.contains('invalid_grant')) {
      return 'Your Gmail connection expired — reconnect it in Settings.';
    }
    if (msg.contains('insufficientPermissions') || msg.contains('403')) {
      return 'Gmail denied this request — reconnect your account in Settings '
          'to refresh permissions.';
    }
    if (msg.contains('SocketException') || msg.contains('Failed host lookup')) {
      return "Couldn't reach Gmail — check your internet connection.";
    }
    return 'Sending failed: $msg';
  }

  // ── RFC 2822 message builder ──────────────────────────────────────────────

  String _buildRawMimeMessage({
    required String from,
    required String to,
    required String cc,
    required String subject,
    required String bodyText,
    required String attachmentFilename,
    required Uint8List attachmentBytes,
  }) {
    final boundary = 'crusam_${DateTime.now().microsecondsSinceEpoch}';
    final b = StringBuffer()
      ..writeln('From: $from')
      ..writeln('To: $to');
    if (cc.trim().isNotEmpty) b.writeln('Cc: $cc');
    b
      // RFC 2047-encoded subject — survives non-ASCII characters safely
      // (rupee symbol, accented client names, etc).
      ..writeln('Subject: =?UTF-8?B?${base64.encode(utf8.encode(subject))}?=')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="UTF-8"')
      ..writeln()
      ..writeln(bodyText)
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: application/pdf; name="$attachmentFilename"')
      ..writeln('Content-Disposition: attachment; filename="$attachmentFilename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(base64.encode(attachmentBytes))
      ..writeln('--$boundary--');

    // Gmail wants the whole RFC 2822 message base64url-encoded.
    return base64Url.encode(utf8.encode(b.toString()));
  }
}
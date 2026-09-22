// lib/core/email/email_outbox_processor.dart
//
// Sends emails that Claude queued through the CruSam MCP server
// (`send_email` → email_outbox table). The server can't reach Gmail — the
// sign-in lives here — so while the app is open and a Gmail account is
// connected in Profile, this checks the outbox every 30 seconds and sends
// each queued email exactly like the Send dialogs do: email_log row first,
// then Gmail, then mark sent/failed.

import 'dart:async';
import 'dart:io';

import 'package:crusam_core/crusam_core.dart' show EmailOutboxStore, OutboxEmail, OutboxStatus;
import 'package:flutter/foundation.dart';

import '../../data/db/database_helper.dart';
import '../../data/db/email_log_repository.dart';
import '../../data/models/email_log_model.dart';
import '../../shared/models/generated_document.dart';
import 'email_account.dart';
import 'email_suggestions_cache.dart';
import 'gmail_service.dart';

class EmailOutboxProcessor {
  EmailOutboxProcessor._();
  static final EmailOutboxProcessor instance = EmailOutboxProcessor._();

  static const _interval = Duration(seconds: 30);

  Timer? _timer;
  bool _running = false;

  /// Called once from main.dart.
  Future<void> start() async {
    if (_timer != null) return;
    try {
      final db = await DatabaseHelper.instance.database;
      // Anything left mid-send by a previous run is reported, never re-sent.
      await EmailOutboxStore.failInterrupted(db, _now());
    } catch (e) {
      debugPrint('EmailOutboxProcessor.start: $e');
    }
    _timer = Timer.periodic(_interval, (_) => processNow());
    // Send right away when an account gets connected in Profile.
    EmailAccount.changes.addListener(processNow);
    unawaited(processNow());
  }

  void stop() {
    EmailAccount.changes.removeListener(processNow);
    _timer?.cancel();
    _timer = null;
  }

  /// Sends every queued email. Skipped while no Gmail account is connected —
  /// the emails simply wait in the queue.
  Future<void> processNow() async {
    if (_running || !EmailAccount.canSend) return;
    _running = true;
    try {
      final db = await DatabaseHelper.instance.database;
      for (final email in await EmailOutboxStore.queued(db)) {
        if (!EmailAccount.canSend) break;
        await _send(email);
      }
    } catch (e) {
      debugPrint('EmailOutboxProcessor.processNow: $e');
    } finally {
      _running = false;
    }
  }

  Future<void> _send(OutboxEmail email) async {
    final db = await DatabaseHelper.instance.database;
    final id = email.id!;
    // Claim it; if the server cancelled it meanwhile, leave it alone.
    if (!await EmailOutboxStore.transition(
        db, id, OutboxStatus.queued, OutboxStatus.sending, _now())) {
      return;
    }

    int? logId;
    try {
      logId = await DatabaseHelper.instance.insertEmailLog(EmailLogModel(
        entityType: email.entityType,
        entityId: email.entityId,
        recipientTo: email.to,
        recipientCc: email.cc,
        subject: email.subject,
        sentBy: EmailAccount.senderEmail,
        attachmentFormats: email.attachmentFormats,
      ));

      final docs = <GeneratedDocument>[];
      for (final path in email.attachments) {
        final file = File(path);
        if (!file.existsSync()) {
          throw GmailSendException('Attachment no longer exists: $path');
        }
        docs.add(GeneratedDocument(
          bytes: await file.readAsBytes(),
          filename: file.uri.pathSegments.last,
          mimeType: path.toLowerCase().endsWith('.pdf')
              ? GeneratedDocument.pdfMime
              : GeneratedDocument.xlsxMime,
        ));
      }

      final messageId = await GmailService.instance.sendAttachmentsEmail(
        to: email.to,
        cc: email.cc,
        subject: email.subject,
        bodyText: email.body,
        attachments: docs,
      );

      await DatabaseHelper.instance.markEmailSent(id: logId, gmailMessageId: messageId);
      await EmailOutboxStore.transition(
          db, id, OutboxStatus.sending, OutboxStatus.sent, _now(),
          emailLogId: logId, sentAt: _now());
      for (final to in email.to.split(',')) {
        EmailSuggestionsCache.instance.noteUsed(to.trim());
      }
    } catch (e) {
      if (logId != null) {
        await DatabaseHelper.instance.markEmailFailed(id: logId, errorMessage: e.toString());
      }
      await EmailOutboxStore.transition(
          db, id, OutboxStatus.sending, OutboxStatus.failed, _now(),
          emailLogId: logId, error: e.toString());
    }
  }

  static String _now() => DateTime.now().toUtc().toIso8601String();
}

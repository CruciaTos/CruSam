// lib/core/email/email_account.dart
//
// The account CruSam sends email from: the Google sign-in when it is
// connected, otherwise a Gmail app password (see AppPasswordAccount). Send
// dialogs, the email outbox and "created by" stamps ask here instead of
// GoogleAuthService directly, so both ways of connecting behave the same.

import 'package:flutter/foundation.dart';

import '../sync/google_auth_service.dart';
import 'app_password_account.dart';

class EmailAccount {
  EmailAccount._();

  static bool get canSend =>
      GoogleAuthService.instance.isSignedIn || AppPasswordAccount.instance.connected;

  /// The address mail goes out from ('' when none is connected).
  static String get senderEmail {
    final google = GoogleAuthService.instance;
    if (google.isSignedIn) return google.userEmail ?? '';
    return AppPasswordAccount.instance.email ?? '';
  }

  /// Fires when either way of connecting changes.
  static final Listenable changes =
      Listenable.merge([GoogleAuthService.instance, AppPasswordAccount.instance]);
}

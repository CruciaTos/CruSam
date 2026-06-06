// lib/core/sync/startup_sync.dart
//
// FIX: runInBackground() now uses Future.delayed(Duration.zero) instead of
// Future.microtask(), ensuring it fires AFTER the first frame and after
// restoreSession() has fully completed (including any token refresh).
// A microtask fires too early — before the event loop yields — which means
// it can race against the token refresh that restoreSession() triggers.

import 'package:flutter/foundation.dart';

import 'drive_service.dart';
import 'google_auth_service.dart';

class StartupSync {
  StartupSync._();

  // ── Non-blocking (recommended for most cases) ─────────────────────────────

  /// Starts the sync in the background without blocking app startup.
  ///
  /// Uses Future.delayed(Duration.zero) so it fires on the next event-loop
  /// iteration — AFTER restoreSession() has finished and the widget tree is
  /// up — eliminating the race condition where isSignedIn was true but the
  /// token hadn't been refreshed yet.
  static void runInBackground() {
    Future.delayed(Duration.zero, () async {
      if (!GoogleAuthService.instance.isSignedIn) {
        debugPrint('StartupSync: not signed in — skipping');
        return;
      }
      try {
        final result = await SyncManager.instance.syncOnStartup();
        debugPrint('StartupSync (background): $result');
      } catch (e) {
        debugPrint('StartupSync (background) error: $e');
      }
    });
  }

  // ── Blocking (for splash-screen / first-run flows) ────────────────────────

  /// Runs the full startup sync and waits for it to complete.
  static Future<SyncResult> runBlocking() async {
    if (!GoogleAuthService.instance.isSignedIn) {
      return const SyncResult.notSignedIn();
    }
    try {
      return await SyncManager.instance.syncOnStartup();
    } catch (e) {
      debugPrint('StartupSync (blocking) error: $e');
      return SyncResult.networkError(e.toString());
    }
  }
}
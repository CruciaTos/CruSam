// lib/core/sync/startup_sync.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// STARTUP SYNC — wire this into main.dart
// ═══════════════════════════════════════════════════════════════════════════
//
// HOW TO USE
// ──────────────────────────────────────────────────────────────────────────
// In your main.dart, replace (or extend) the existing startup logic with:
//
//   void main() async {
//     WidgetsFlutterBinding.ensureInitialized();
//
//     // 1. Restore Google session (non-blocking; router waits for AuthNotifier)
//     await GoogleAuthService.instance.restoreSession();
//
//     // 2. Fire cloud sync in the background — does NOT block app startup.
//     //    The app loads instantly from SQLite; Drive data arrives silently.
//     StartupSync.runInBackground();
//
//     runApp(const CrusamApp());
//   }
//
// The sync runs after the widget tree is up, so the user sees the
// dashboard immediately (populated from local SQLite) while Drive data
// merges in quietly.  If the user has made changes offline, those are
// pushed to Drive in the same background pass.
//
// For a BLOCKING sync (e.g., first-run onboarding where you show a
// splash screen), call:
//
//   final result = await StartupSync.runBlocking();
//   // then navigate to dashboard
//
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

import 'drive_service.dart';
import 'google_auth_service.dart';

class StartupSync {
  StartupSync._();

  // ── Non-blocking (recommended for most cases) ─────────────────────────────

  /// Starts the sync in the background without waiting for it to finish.
  ///
  /// Call this after [GoogleAuthService.instance.restoreSession()] and
  /// before [runApp].  The sync runs concurrently with app rendering.
  ///
  /// Errors are caught internally; the app will never crash due to a
  /// sync failure.
  static void runInBackground() {
    // Use a microtask so the sync starts after the first frame is submitted.
    Future.microtask(() async {
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
  ///
  /// Returns a [SyncResult] you can use to decide whether to show an
  /// error banner.  Suitable for a splash screen where you want to
  /// guarantee fresh data before the user reaches the dashboard.
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

// ═══════════════════════════════════════════════════════════════════════════
// RECOMMENDED main.dart SKELETON
// ═══════════════════════════════════════════════════════════════════════════
//
// import 'package:flutter/material.dart';
// import 'core/sync/google_auth_service.dart';
// import 'core/sync/startup_sync.dart';
// import 'core/router/app_router.dart';
//
// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//
//   // Restore persisted Google session (reads from FlutterSecureStorage).
//   // This is fast (< 100 ms on warm starts); do it before runApp so
//   // GoogleAuthService.isSignedIn is correct for the router redirect.
//   await GoogleAuthService.instance.restoreSession();
//
//   // Kick off Drive sync in the background.  The UI loads immediately
//   // from SQLite; Drive data merges in silently after the first frame.
//   StartupSync.runInBackground();
//
//   runApp(const CrusamApp());
// }
//
// class CrusamApp extends StatelessWidget {
//   const CrusamApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp.router(
//       title: 'CRUSAM',
//       routerConfig: AppRouter.router,
//       // ... theme, etc.
//     );
//   }
// }
//
// ═══════════════════════════════════════════════════════════════════════════
// WIRING CHECKLIST
// ═══════════════════════════════════════════════════════════════════════════
//
// 1. pubspec.yaml — ensure `uuid` is listed:
//      uuid: ^4.0.0
//
// 2. drive_service.dart — copy the new version (includes full SyncManager
//    with voucher push/pull, _bootstrapCloudIds, pushAllToCloud, etc.)
//
// 3. sync_models.dart — copy the new version (adds SyncVoucher class).
//
// 4. backup_restore_card.dart — copy the new version (calls
//    SyncManager.instance.pushAllToCloud() after successful import).
//
// 5. database_helper.dart — the existing upsertVoucherFromCloud already
//    accepts a Map with nested 'rows'; no changes needed there.
//    However, you must also add pushInvoiceChange calls wherever a voucher
//    is saved/deleted (mirror the employee pattern):
//
//      In updateVoucherWithRows():
//        final cloudId = voucherData['cloud_id'] as String?;
//        if (cloudId != null && cloudId.isNotEmpty) {
//          final full = Map<String, dynamic>.from(voucherData)
//            ..['rows'] = rows;
//          await SyncManager.instance.pushInvoiceChange(
//            cloudId: cloudId,
//            operation: 'update',
//            invoiceDbRow: full,
//          );
//        }
//
//      In insertVoucher(), after the insert:
//        // (cloud_id may not be present yet; bootstrap handles it at startup)
//
//    The bootstrap (_bootstrapCloudIds) takes care of any new vouchers
//    that were created without a cloud_id and will push them on next launch.
//
// 6. profile_screen.dart — the existing "Sync now" button already calls
//    SyncManager.instance.syncNow() which now delegates to syncOnStartup().
//    No changes needed.
//
// ═══════════════════════════════════════════════════════════════════════════
// DATA FLOW SUMMARY
// ═══════════════════════════════════════════════════════════════════════════
//
//  App launch
//  ──────────
//  restoreSession()               → GoogleAuthService hydrates token
//  StartupSync.runInBackground()  → fires and forgets:
//    createPreSyncBackup()        → copies aarti.db → aarti_backup_<ts>.db
//    initializeDriveStructure()   → ensures Crusam/ folder tree exists
//    _bootstrapCloudIds()         → assigns UUIDs to any rows missing cloud_id
//    _pullFromCloud()             → for each index entry:
//                                     cloud newer? → upsertFromCloud()
//                                     cloud deleted? → softDelete locally
//    _drainPendingQueue()         → upload each pending row → update index
//
//  User edits employee or voucher
//  ──────────────────────────────
//  DatabaseHelper writes SQLite row
//  → addPendingSync(SyncPendingEntry)
//  → _processSilently() drains the queue in the background
//
//  User imports local backup file
//  ──────────────────────────────
//  BackupRestoreCard.importBackupData()
//  → refreshes EmployeeNotifier + VoucherNotifier
//  → SyncManager.pushAllToCloud():
//      _bootstrapCloudIds()
//      _enqueueAllForPush()
//      _drainPendingQueue()   ← awaited; Drive is up to date before return
//
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/preferences/export_preferences_notifier.dart';
import 'core/router/app_router.dart';
import 'core/storage/app_paths.dart';
import 'core/sync/drive_service.dart';
import 'core/sync/google_auth_service.dart';
import 'core/theme/app_theme.dart';
import 'core/updater/update_dialog.dart';
import 'core/updater/update_notifier.dart';
import 'features/auth/notifiers/auth_notifier.dart';
import 'features/master_data/notifiers/employee_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No login required – skip all session checks
  // await AuthNotifier.instance.checkSession();
  await ExportPreferencesNotifier.instance.load();
  // Restores the saved Gmail connection (if any) so the app doesn't ask the
  // user to reconnect every launch — stays connected until they manually
  // disconnect in Profile. Not awaited, same as EmployeeNotifier.load() and
  // UpdateNotifier.checkForUpdate() below: this is a local-first desktop app
  // and startup shouldn't hang on a network call (OIDC discovery + possible
  // token refresh) if internet happens to be slow or unavailable. Whenever
  // it resolves, GoogleAuthService's own ChangeNotifier updates anything
  // listening (e.g. GmailAccountCard) automatically.
  GoogleAuthService.instance.restoreSession();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Resolve the canonical, per-user app-data directory (via path_provider
    // — NOT the install folder, see AppPaths) before anything touches the
    // database. If a previous build left aarti.db / semantic_index.db
    // sitting next to the executable (the old, buggy default), carry it
    // forward once so existing users don't appear to lose their data on
    // this update.
    final appDataDir = await AppPaths.directory;
    await AppPaths.migrateLegacyFileIfNeeded(
      legacyDir: Directory.current,
      fileName: 'aarti.db',
    );
    await AppPaths.migrateLegacyFileIfNeeded(
      legacyDir: Directory.current,
      fileName: 'semantic_index.db',
    );

    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Defense-in-depth: sqflite_common_ffi's getDatabasesPath() otherwise
    // defaults to Directory.current (the install folder). This neutralizes
    // that default for any code that still calls getDatabasesPath()
    // directly, on top of DatabaseHelper/SemanticIndexRepository resolving
    // their own paths explicitly via AppPaths.
    await databaseFactory.setDatabasesPath(appDataDir.path);
  }

  EmployeeNotifier.instance.load(); // Load local employee data
  UpdateNotifier.instance.checkForUpdate();
  // Cloud sync disabled on startup – manual backup/restore remains available
  // unawaited(SyncManager.instance.syncOnStartup());

  runApp(const AartiApp());
}

class AartiApp extends StatefulWidget {
  const AartiApp({super.key});

  @override
  State<AartiApp> createState() => _AartiAppState();
}

class _AartiAppState extends State<AartiApp> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    UpdateNotifier.instance.addListener(_onUpdateStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onUpdateStateChanged();
    });
  }

  @override
  void dispose() {
    UpdateNotifier.instance.removeListener(_onUpdateStateChanged);
    super.dispose();
  }

  void _onUpdateStateChanged() {
    if (_dialogShown) return;
    if (!UpdateNotifier.instance.hasUpdate) return;

    _dialogShown = true;
    Future<void>.delayed(const Duration(seconds: 2), () {
      final ctx = AppRouter.rootNavigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        UpdateDialog.show(ctx);
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: 'Crusam Enterprises',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: AppRouter.router,
      );
}
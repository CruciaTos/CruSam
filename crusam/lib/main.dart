// lib/main.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/preferences/export_preferences_notifier.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/update/update_dialog.dart';
import 'core/update/update_notifier.dart';
import 'features/auth/notifiers/auth_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AuthNotifier.instance.checkSession();
  await ExportPreferencesNotifier.instance.load();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  UpdateNotifier.instance.checkForUpdate();

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
        title: 'Aarti Enterprises',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        routerConfig: AppRouter.router,
      );
}
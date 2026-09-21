// Renders every screen at common desktop window sizes, with the sidebar
// expanded and collapsed (and every frame of the collapse/expand animation),
// and fails on any layout overflow (the yellow-and-black stripes).
//
// Uses the app's real fonts: the Google Fonts it downloads (copied into
// test/fonts) and Windows' Segoe UI / Consolas, so text is measured as it is
// in the running app. Data comes from a throwaway copy of the development
// database (mcp-server/dev-data/aarti_dev.db) when present, else an empty DB.
//
//   flutter test test/overflow_scan_test.dart

import 'dart:io';

import 'package:crusam/core/preferences/export_preferences_notifier.dart';
import 'package:crusam/core/router/app_router.dart';
import 'package:crusam/core/theme/app_theme.dart';
import 'package:crusam/data/db/database_helper.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_formula_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_snapshot_notifier.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';
import 'package:crusam/data/db/salary_disbursement_repository.dart';
import 'package:crusam/features/master_data/presentation/employee_form_screen.dart';
import 'package:crusam/features/salary/widgets/send_disbursement_dialog.dart';
import 'package:crusam/features/salary/widgets/send_salary_dialog.dart';
import 'package:crusam/features/vouchers/widgets/invoice_preview_dialog.dart';
import 'package:crusam/features/vouchers/widgets/send_invoice_dialog.dart';
import 'package:crusam/shared/document_hooks.dart';
import 'package:crusam_core/crusam_core.dart'
    show CompanyConfigModel, SalaryDisbursementModel, VoucherStore;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Logical window sizes: the smallest window the app allows (see
/// windows/runner), then maximized windows (screen minus taskbar and title
/// bar) on 1366x768 @125%, 1600x900 @125%, 1920x1080 @125% and @100%.
const sizes = [
  Size(960, 520), Size(1093, 535), Size(1280, 680), Size(1536, 800), Size(1920, 1000),
];

const routes = [
  '/dashboard', '/employees', '/vouchers', '/invoices', '/clients', '/settings',
  '/salary-formula-settings', '/profile', '/salary-employees', '/saved-salary',
  '/salary-slips', '/salary-invoice', '/salary-bills', '/salary-statement',
  '/salary-attachment-a', '/salary-attachment-b', '/salary-analytics',
];

class Overflow {
  final String where; // route @ size [state]
  final String what; // "RenderFlex overflowed by 12 pixels on the right"
  final String source; // file:line of the widget that overflowed
  Overflow(this.where, this.what, this.source);
  @override
  String toString() => '$source  $what  ($where)';
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final f in files) {
    final file = File(f);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
    any = true;
  }
  if (any) await loader.load();
}

Future<void> _loadFonts() async {
  for (final f in Directory('test/fonts').listSync().whereType<File>()) {
    await _loadFont(p.basenameWithoutExtension(f.path), [f.path]);
  }
  const win = r'C:\Windows\Fonts';
  final sans = ['$win\\segoeui.ttf', '$win\\segoeuib.ttf', '$win\\seguisb.ttf'];
  final noto = ['assets/fonts/NotoSans-Regular.ttf', 'assets/fonts/NotoSans-Bold.ttf'];
  final ui = File(sans.first).existsSync() ? sans : noto;
  for (final family in ['Roboto', 'sans-serif', 'Segoe UI', '.AppleSystemUIFont']) {
    await _loadFont(family, ui);
  }
  await _loadFont('monospace', ['$win\\consola.ttf', '$win\\consolab.ttf']);
  // Material icons, so icon glyphs have their real size.
  final icons = p.join(p.dirname(p.dirname(Platform.resolvedExecutable)),
      'cache', 'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf');
  await _loadFont('MaterialIcons', [icons]);
}

/// Fallback when there is no source location: the "relevant widget" line.
String _widgetLine(String details) => RegExp(r'The relevant error-causing widget was:\s*\n?\s*([^\n]+)')
        .firstMatch(details)
        ?.group(1)
        ?.trim() ??
    '';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    await _loadFonts();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    wireSharedDocumentHooks();

    tmp = Directory.systemTemp.createTempSync('crusam_overflow_');
    final appDir = Directory(p.join(tmp.path, 'CruSam'))..createSync();
    final dev = File(p.join('..', 'mcp-server', 'dev-data', 'aarti_dev.db'));
    if (dev.existsSync()) dev.copySync(p.join(appDir.path, 'aarti.db'));

    // path_provider → the temp folder (never the real app data).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
    // Secure storage (Gmail sign-in) → nothing stored.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async => null);
    // PDF previews (printing plugin) → no pages.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'),
            (call) async => null);
  });

  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets('no layout overflow on any screen, size or sidebar state',
      (tester) async {
    final found = <Overflow>[];
    final other = <String>{};
    var where = '';

    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) {
        final full = details.toString();
        final src = RegExp(r'file:///(?:[A-Za-z]:)?[^\s:]+\.dart:\d+(?::\d+)?')
            .allMatches(full)
            .map((m) => m.group(0)!)
            .firstWhere((s) => s.contains('/crusam/lib/'), orElse: () => '?');
        found.add(Overflow(where, text.split('\n').first,
            src == '?' ? '? ${_widgetLine(full)}' : src.replaceFirst(RegExp(r'^.*/crusam/'), '')));
      } else {
        other.add('${text.split('\n').first}  ($where)');
      }
    };

    Future<void> settle() async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 50));
    }

    try {
      // Same start-up loading as main.dart, then real data on screen: the
      // newest saved salary month and the newest invoice in the builder.
      await tester.runAsync(() async {
        await ExportPreferencesNotifier.instance.load();
        await SalaryFormulaNotifier.instance.load();
        await EmployeeNotifier.instance.load();
        final snaps = SalarySnapshotNotifier.instance;
        await snaps.loadSnapshotList();
        if (snaps.snapshots.isNotEmpty) await snaps.loadMonth(snaps.snapshots.first.id!);
        final db = await DatabaseHelper.instance.database;
        final newest = await db.query('vouchers',
            columns: ['id'], where: 'is_deleted = 0', orderBy: 'id DESC', limit: 1);
        if (newest.isNotEmpty) {
          final v = await VoucherStore.getById(db, newest.first['id'] as int);
          if (v != null) VoucherNotifier.instance.update((_) => v);
        }
      });

      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: AppRouter.router,
      ));

      for (final size in sizes) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        for (final route in routes) {
          where = '$route @ ${size.width.toInt()}x${size.height.toInt()}';
          AppRouter.router.go(route);
          await settle();

          // The AI assistant panel open over the page.
          final ai = find.byTooltip('AI Assistant');
          if (route == '/dashboard' && ai.evaluate().isNotEmpty) {
            where = '$route @ ${size.width.toInt()}x${size.height.toInt()} (AI panel)';
            await tester.tap(ai.first);
            await settle();
            await tester.tap(ai.first, warnIfMissed: false);
            await settle();
          }

          // Collapse and expand the sidebar, checking every animation frame.
          for (final state in ['collapsing', 'expanding']) {
            final toggle = find.byTooltip(
                state == 'collapsing' ? 'Collapse sidebar' : 'Expand sidebar');
            if (toggle.evaluate().isEmpty) break;
            where = '$route @ ${size.width.toInt()}x${size.height.toInt()} ($state)';
            await tester.tap(toggle.first);
            for (var i = 0; i < 16; i++) {
              await tester.pump(const Duration(milliseconds: 16));
            }
            await settle();
          }
        }
      }

      // Dialogs, on the smallest window and a common one.
      CompanyConfigModel config = const CompanyConfigModel();
      SalaryDisbursementModel? batch;
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        final c = await db.query('company_config', limit: 1);
        if (c.isNotEmpty) config = CompanyConfigModel.fromMap(c.first);
        final all = await DatabaseHelper.instance.getAllSalaryDisbursements();
        if (all.isNotEmpty) batch = all.first;
      });
      final employees = EmployeeNotifier.instance.employees;
      final summaries = SalarySnapshotNotifier.instance.summaries;
      final dialogs = <String, Widget Function()>{
        'employee form (new)': () => const EmployeeFormScreen(),
        if (employees.isNotEmpty)
          'employee form (edit)': () => EmployeeFormScreen(employee: employees.first.toMap()),
        'send invoice': () =>
            SendInvoiceDialog(voucher: VoucherNotifier.instance.current, config: config),
        'invoice preview': () => InvoicePreviewDialog(
            notifier: VoucherNotifier.instance, config: config, type: PreviewType.invoice),
        'bank preview': () => InvoicePreviewDialog(
            notifier: VoucherNotifier.instance, config: config, type: PreviewType.bank),
        if (summaries.isNotEmpty) 'send salary': () => SendSalaryDialog(summary: summaries.first),
        if (batch != null) 'send disbursement': () => SendDisbursementDialog(disbursement: batch!),
      };
      for (final size in [sizes.first, sizes[2]]) {
        tester.view.physicalSize = size;
        AppRouter.router.go('/dashboard');
        await settle();
        for (final d in dialogs.entries) {
          where = '${d.key} dialog @ ${size.width.toInt()}x${size.height.toInt()}';
          final ctx = AppRouter.rootNavigatorKey.currentContext!;
          showDialog<void>(context: ctx, builder: (_) => d.value());
          await settle();
          await settle();
          Navigator.of(ctx, rootNavigator: true).pop();
          await settle();
        }
      }
    } finally {
      FlutterError.onError = original;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }

    // Group identical overflows (same widget, same message).
    final grouped = <String, List<Overflow>>{};
    for (final o in found) {
      grouped.putIfAbsent('${o.source}  ${o.what}', () => []).add(o);
    }
    final report = StringBuffer();
    for (final e in grouped.entries) {
      final places = e.value.map((o) => o.where).toSet();
      report.writeln('${e.key}\n    seen ${e.value.length}x, e.g. ${places.take(3).join('; ')}');
    }
    if (other.isNotEmpty) {
      // ignore: avoid_print
      print('Other errors while rendering (not overflow):\n  ${other.take(20).join('\n  ')}');
    }
    File(p.join('build', 'overflow_report.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync(report.isEmpty ? 'No overflows.\n' : report.toString());
    expect(grouped, isEmpty, reason: '\n$report');
  });
}

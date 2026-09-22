import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crusam_core/crusam_core.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';

import '../db.dart';

/// Everything document generation needs on the server side: bundled assets
/// (fonts, letterhead, signature), the app's Export Paths folders, and the
/// saved PDF settings from the database.
class ExportEnv {
  final Database db;
  final Map<String, String> env;
  ExportEnv(this.db, [Map<String, String>? env]) : env = env ?? Platform.environment;

  // ── Assets ────────────────────────────────────────────────────────────────

  /// Folder that contains `assets/fonts/...`: CRUSAM_ASSETS_DIR, the folder
  /// next to server.exe (packaged extension), or the app's own source tree.
  late final String? assetsRoot = _findAssetsRoot();

  String? _findAssetsRoot() {
    bool ok(String root) =>
        File(p.join(root, 'assets', 'fonts', 'NotoSans-Regular.ttf')).existsSync();
    final explicit = env['CRUSAM_ASSETS_DIR'];
    if (explicit != null && explicit.isNotEmpty && ok(explicit)) return explicit;
    final starts = [
      p.dirname(Platform.resolvedExecutable),
      p.dirname(Platform.script.toFilePath()),
      Directory.current.path,
    ];
    for (final start in starts) {
      var dir = start;
      for (var i = 0; i < 8; i++) {
        if (ok(dir)) return dir;
        if (ok(p.join(dir, 'crusam'))) return p.join(dir, 'crusam');
        final parent = p.dirname(dir);
        if (parent == dir) break;
        dir = parent;
      }
    }
    return null;
  }

  Future<ByteData> loadAsset(String path) async {
    final root = assetsRoot;
    if (root == null) {
      throw const ToolError('Document fonts/images were not found next to the '
          'server. Reinstall the CruSam extension (or set CRUSAM_ASSETS_DIR).');
    }
    final bytes = await File(p.join(root, path)).readAsBytes();
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  // ── PDF settings from the database ─────────────────────────────────────────

  Future<Map<String, Object?>?> _pdfSettingsRow() async {
    final rows = await db.query('pdf_settings', where: 'id=1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<MarginSettings> margins() async {
    final r = await _pdfSettingsRow();
    return r == null ? const MarginSettings() : MarginSettings.fromMap(r);
  }

  Future<VoucherColumnWidthsSettings> voucherColumnWidths() async {
    final json = (await _pdfSettingsRow())?['voucher_col_widths'] as String?;
    return (json == null || json.isEmpty)
        ? const VoucherColumnWidthsSettings()
        : VoucherColumnWidthsSettings.fromJson(json);
  }

  Future<BankColumnWidthsSettings> bankColumnWidths() async {
    final json = (await _pdfSettingsRow())?['bank_col_widths'] as String?;
    return (json == null || json.isEmpty)
        ? const BankColumnWidthsSettings()
        : BankColumnWidthsSettings.fromJson(json);
  }

  /// Installs the hooks crusam_core's document builders use.
  void install() {
    ExportHooks.loadAsset = loadAsset;
    ExportHooks.margins = margins;
    ExportHooks.voucherColumnWidths = voucherColumnWidths;
    ExportHooks.bankColumnWidths = bankColumnWidths;
  }

  // ── The app's saved preferences (Export Paths, statement column widths) ────

  Map<String, Object?> _prefs() {
    final appData = env['APPDATA'];
    if (appData == null) return const {};
    final f = File(p.join(appData, 'com.cructiatus', 'crusam', 'shared_preferences.json'));
    if (!f.existsSync()) return const {};
    try {
      return (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>();
    } catch (_) {
      return const {};
    }
  }

  String _pref(String key) => (_prefs()['flutter.$key'] as String?)?.trim() ?? '';

  /// Same resolution as the app (ExportPreferencesNotifier + PdfFileSaver):
  /// per-type folder, then the general PDF/Excel folder, then Downloads.
  /// CRUSAM_EXPORT_DIR or an explicit [override] wins over all of them.
  Directory folderFor(ExportPathTarget target, {String? override}) {
    // An explicit folder is used as given (created if needed), never
    // silently replaced by another location.
    if (override != null && override.trim().isNotEmpty) {
      final dir = Directory(override.trim());
      if (!p.isAbsolute(dir.path)) {
        throw ToolError('output_dir must be an absolute path, got "$override".');
      }
      if (!dir.parent.existsSync()) {
        throw ToolError('output_dir "$override": parent folder does not exist.');
      }
      dir.createSync();
      return dir;
    }
    final candidates = <String>[
      if ((env['CRUSAM_EXPORT_DIR'] ?? '').isNotEmpty) env['CRUSAM_EXPORT_DIR']!,
      switch (target) {
        ExportPathTarget.taxInvoice => _pref('export_tax_invoice_pdf_path'),
        ExportPathTarget.salary => _pref('export_salary_pdf_path'),
        _ => '',
      },
      target.usesPdfDefaults ? _pref('export_pdf_path') : _pref('export_excel_path'),
      p.join(env['USERPROFILE'] ?? env['HOME'] ?? '', 'Downloads'),
    ];
    for (final c in candidates) {
      if (c.isNotEmpty && Directory(c).existsSync()) return Directory(c);
    }
    final fallback = Directory(p.join(p.dirname(db.path), 'exports'))
      ..createSync(recursive: true);
    return fallback;
  }

  /// Salary Statement column widths saved on the Salary Statement screen.
  Map<int, double> statementColumnWidths() {
    final raw = _prefs()['flutter.salary_statement_column_widths'];
    if (raw is! String) return const {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          if (int.tryParse(e.key) != null && e.value is num)
            int.parse(e.key): (e.value as num).toDouble(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Writes [bytes] without overwriting: "name.ext", then "name(1).ext", …
  Future<String> save(List<int> bytes, Directory dir, String fileName) async {
    final base = p.join(dir.path, fileName);
    var path = base;
    final dot = base.lastIndexOf('.');
    for (var i = 1; File(path).existsSync(); i++) {
      path = '${base.substring(0, dot)}($i)${base.substring(dot)}';
    }
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}

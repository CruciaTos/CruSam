// lib/features/vouchers/services/pdf_export_service.dart
//
// Task 3: _resolveOutputDir now accepts a _PathType enum so each
//         export flow uses its own configured save directory.
// Task 4: Share.shareXFiles removed — files are saved silently to disk.
// Fix  1: _uniquePath prevents overwriting existing files.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import 'package:crusam/features/vouchers/widgets/tax_invoice_preview.dart';
import 'package:crusam/features/vouchers/widgets/voucher_pdf_preview.dart';
import 'package:crusam/features/vouchers/widgets/bank_disbursement_preview.dart';

// ── Path type (Task 3) ────────────────────────────────────────────────────────
enum _PdfPathType { taxInvoice, salary, general }

class PdfExportService {
  static const Duration _captureDelay      = Duration(milliseconds: 150);
  static const double   _capturePixelRatio = 4.0;

  static pw.Font? _regularFont;
  static pw.Font? _boldFont;

  static Future<void> _ensurePdfFontsLoaded() async {
    _regularFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    _boldFont ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'),
    );
  }

  // ── PNG dimension reader ──────────────────────────────────────────────────

  static ({int width, int height}) _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return (width: 0, height: 0);
    final data = ByteData.sublistView(bytes, 16, 24);
    return (
      width:  data.getUint32(0, Endian.big),
      height: data.getUint32(4, Endian.big),
    );
  }

  static PdfPageFormat _pageFormatForBytes(Uint8List bytes) {
    final dim = _pngDimensions(bytes);
    return dim.width > dim.height
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
  }

  // ── Generic export (used by salary/attachment screens) ────────────────────

  static Future<void> exportWidgets({
    required BuildContext context,
    required List<Widget> pages,
    required String       fileNameSlug,
    required String       filePrefix,
    required String       shareSubject,
    List<String>?         assetPathsToPrecache,
  }) async {
    if (assetPathsToPrecache != null) {
      await _precacheAssets(context, assetPathsToPrecache);
    }
    // Determine path type from prefix — salary documents use salaryPdfPath
    final pathType = _prefixToPathType(filePrefix);
    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     fileNameSlug,
      filePrefix: filePrefix,
      pathType:   pathType,
    );
  }

  // ── Invoice bundle ────────────────────────────────────────────────────────

  static Future<void> exportInvoiceBundle({
    required BuildContext        context,
    required VoucherModel        voucher,
    required CompanyConfigModel  config,
    required EdgeInsets          taxInvoiceMargins,
    required EdgeInsets          voucherMargins,
  }) async {
    await _precacheInvoiceAssets(context);

    final pages = <Widget>[
      ...TaxInvoicePreview.buildPdfPages(
        voucher: voucher, config: config, margins: taxInvoiceMargins),
      ...VoucherPdfPreview.buildPdfPages(
        voucher: voucher, config: config, margins: voucherMargins),
    ];

    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     voucher.billNo,
      filePrefix: 'tax_invoice_voucher',
      pathType:   _PdfPathType.taxInvoice,  // Task 3
    );
  }

  // ── Bank disbursement export ──────────────────────────────────────────────

  static Future<void> exportBankDisbursement({
    required BuildContext        context,
    required VoucherModel        voucher,
    required CompanyConfigModel  config,
    required EdgeInsets          margins,
  }) async {
    final pages = BankDisbursementPreview.buildPdfPages(
      voucher: voucher, config: config, margins: margins);

    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     voucher.billNo,
      filePrefix: 'bank_disbursement',
      pathType:   _PdfPathType.general,   // uses general PDF path
    );
  }

  // ── Core: capture pages → PDF → save ─────────────────────────────────────

  static Future<void> _exportPages({
    required BuildContext    context,
    required List<Widget>    pages,
    required String          billNo,
    required String          filePrefix,
    _PdfPathType             pathType = _PdfPathType.general,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    await _ensurePdfFontsLoaded();

    // 1. Capture every page widget to PNG bytes.
    final capturedPages = <Uint8List>[];
    for (final page in pages) {
      capturedPages.add(await _capturePage(context, page));
    }

    // 2. Build the PDF, assigning correct page format from pixel dimensions.
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: _regularFont!, bold: _boldFont!),
    );
    for (final pageBytes in capturedPages) {
      final pdfImage = pw.MemoryImage(pageBytes);
      final format   = _pageFormatForBytes(pageBytes);
      pdf.addPage(pw.Page(
        pageFormat: format,
        margin:     pw.EdgeInsets.zero,
        build:      (_) => pw.SizedBox.expand(
          child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
        ),
      ));
    }

    // 3. Save to disk — Task 4: no Share popup.
    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final slug   = _slugify(billNo);
    final dir    = await _resolveOutputDir(pathType);
    final base   = '${dir.path}${Platform.pathSeparator}${filePrefix}_$slug.pdf';
    final path   = await _uniquePath(base);   // Fix 1: no overwriting
    await File(path).writeAsBytes(bytes, flush: true);
    // Task 4: file saved silently — no Share.shareXFiles call.
  }

  // ── Screenshot helper ─────────────────────────────────────────────────────

  static Future<Uint8List> _capturePage(BuildContext context, Widget page) async {
    final controller    = ScreenshotController();
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final mediaQuery    = MediaQuery.maybeOf(context) ??
        const MediaQueryData(size: Size(1200, 900));

    final widget = InheritedTheme.captureAll(
      context,
      MediaQuery(
        data: mediaQuery,
        child: Directionality(
          textDirection: textDirection,
          child: Material(
            color: Colors.white,
            child: ClipRect(child: page),
          ),
        ),
      ),
    );

    return controller.captureFromWidget(
      widget,
      context:    context,
      delay:      _captureDelay,
      pixelRatio: _capturePixelRatio,
    );
  }

  // ── Asset pre-caching ─────────────────────────────────────────────────────

  static Future<void> _precacheInvoiceAssets(BuildContext context) async {
    await _precacheAssets(context, [
      'assets/images/aarti_logo.png',
      'assets/images/letterhead.png',
      'assets/images/aarti_signature.png',
    ]);
  }

  static Future<void> _precacheAssets(
      BuildContext context, List<String> assetPaths) async {
    await Future.wait(
        assetPaths.map((p) => _safePrecache(context, p)));
  }

  static Future<void> _safePrecache(BuildContext context, String assetPath) async {
    try { await precacheImage(AssetImage(assetPath), context); } catch (_) {}
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Task 3 — per-type output directory
  // ══════════════════════════════════════════════════════════════════════════

  /// Maps a file-prefix string to the appropriate [_PdfPathType].
  static _PdfPathType _prefixToPathType(String prefix) {
    if (prefix.contains('salary') || prefix.contains('attachment') ||
        prefix.contains('final_invoice')) {
      return _PdfPathType.salary;
    }
    if (prefix.contains('tax_invoice') || prefix.contains('voucher')) {
      return _PdfPathType.taxInvoice;
    }
    return _PdfPathType.general;
  }

  /// Priority:  per-type path → general PDF path → system default.
  static Future<Directory> _resolveOutputDir(_PdfPathType type) async {
    final prefs = ExportPreferencesNotifier.instance;

    String specific = '';
    switch (type) {
      case _PdfPathType.taxInvoice: specific = prefs.taxInvoicePdfPath; break;
      case _PdfPathType.salary:     specific = prefs.salaryPdfPath;     break;
      case _PdfPathType.general:    break;
    }
    if (specific.isNotEmpty) {
      final dir = Directory(specific);
      if (await dir.exists()) return dir;
    }

    if (prefs.pdfPath.isNotEmpty) {
      final dir = Directory(prefs.pdfPath);
      if (await dir.exists()) return dir;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Fix 1 — unique path (no overwriting)
  // ══════════════════════════════════════════════════════════════════════════

  static Future<String> _uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;
    final dot  = basePath.lastIndexOf('.');
    final base = dot == -1 ? basePath : basePath.substring(0, dot);
    final ext  = dot == -1 ? '' : basePath.substring(dot);
    var counter = 1;
    while (true) {
      final candidate = '$base($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  // Kept for compatibility with legacy call sites.
  static Future<String> exportTaxInvoiceFromWidget() async => '';
}
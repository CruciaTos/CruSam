// lib/features/vouchers/services/pdf_export_service.dart
//
// Changes vs previous version
// ────────────────────────────
// • FIX 1: Added _uniquePath() so exports never overwrite an existing file.
//   e.g. invoice.pdf → invoice(1).pdf → invoice(2).pdf …
// • _exportPages now detects orientation from PNG IHDR dimensions (portrait vs
//   landscape) so the exported PDF matches the on-screen preview exactly.
// • All other logic, public API, and existing callers are unchanged.

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

class PdfExportService {
  static const Duration _captureDelay    = Duration(milliseconds: 150);
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

  // ── Generic export ────────────────────────────────────────────────────────

  static Future<void> exportWidgets({
    required BuildContext context,
    required List<Widget> pages,
    required String       fileNameSlug,
    required String       filePrefix,
    required String       shareSubject,
    ExportPathTarget?     outputTarget,
    List<String>?         assetPathsToPrecache,
  }) async {
    if (assetPathsToPrecache != null) {
      await _precacheAssets(context, assetPathsToPrecache);
    }
    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     fileNameSlug,
      subject:    shareSubject,
      filePrefix: filePrefix,
      outputTarget: outputTarget,
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
        voucher: voucher,
        config:  config,
        margins: taxInvoiceMargins,
      ),
      ...VoucherPdfPreview.buildPdfPages(
        voucher: voucher,
        config:  config,
        margins: voucherMargins,
      ),
    ];

    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     voucher.billNo,
      subject:    'Tax Invoice & Voucher',
      filePrefix: 'tax_invoice_voucher',
      outputTarget: ExportPathTarget.taxInvoiceVoucherPdf,
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
      voucher: voucher,
      config:  config,
      margins: margins,
    );

    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     voucher.billNo,
      subject:    'Bank Disbursement',
      filePrefix: 'bank_disbursement',
      outputTarget: ExportPathTarget.bankDisbursementPdf,
    );
  }

  // ── Core: capture pages → PDF ─────────────────────────────────────────────

  static Future<void> _exportPages({
    required BuildContext  context,
    required List<Widget>  pages,
    required String        billNo,
    required String        subject,
    required String        filePrefix,
    ExportPathTarget?      outputTarget,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    await _ensurePdfFontsLoaded();

    // 1. Capture every page widget to PNG bytes.
    final capturedPages = <Uint8List>[];
    for (final page in pages) {
      capturedPages.add(await _capturePage(context, page));
    }

    // 2. Build the PDF.
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _regularFont!,
        bold: _boldFont!,
      ),
    );

    for (final pageBytes in capturedPages) {
      final pdfImage  = pw.MemoryImage(pageBytes);
      final format    = _pageFormatForBytes(pageBytes);

      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin:     pw.EdgeInsets.zero,
          build:      (_) => pw.SizedBox.expand(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    // 3. Save and share — FIX 1: use _uniquePath to avoid overwriting.
    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final slug     = _slugify(billNo);
    final fileName = '${filePrefix}_$slug.pdf';
    final dir      = await _resolveOutputDir(outputTarget);
    final basePath = '${dir.path}${Platform.pathSeparator}$fileName';
    // Never overwrite: append (1), (2) … if file already exists
    final path     = await _uniquePath(basePath);
    final file     = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final written = await file.length();
    if (written == 0) throw Exception('File written but is empty: $path');
  }

  // ── Screenshot helper ─────────────────────────────────────────────────────

  static Future<Uint8List> _capturePage(
    BuildContext context,
    Widget       page,
  ) async {
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
      context:     context,
      delay:       _captureDelay,
      pixelRatio:  _capturePixelRatio,
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
    BuildContext  context,
    List<String>  assetPaths,
  ) async {
    await Future.wait(
      assetPaths.map((path) => _safePrecache(context, path)),
    );
  }

  static Future<void> _safePrecache(
    BuildContext context,
    String       assetPath,
  ) async {
    try {
      await precacheImage(AssetImage(assetPath), context);
    } catch (_) {}
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  static Future<Directory> _resolveOutputDir([ExportPathTarget? target]) async {
    final savedPath = target != null
        ? ExportPreferencesNotifier.instance.resolvedPathForTarget(target)
        : ExportPreferencesNotifier.instance.pdfPath;
    if (savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return dir;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return getApplicationDocumentsDirectory();
    }

    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final downloads = Directory(
      Platform.isWindows ? '$home\\Downloads' : '$home/Downloads',
    );
    if (await downloads.exists()) return downloads;
    return getApplicationDocumentsDirectory();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // FIX 1 — unique path helper (prevents file overwriting)
  // ══════════════════════════════════════════════════════════════════════════

  /// Returns [basePath] unchanged if the file does not yet exist.
  /// Otherwise appends an incrementing counter before the extension:
  ///   invoice.pdf → invoice(1).pdf → invoice(2).pdf …
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

  // Kept for compatibility with legacy call sites.
  static Future<String> exportTaxInvoiceFromWidget() async => '';
}
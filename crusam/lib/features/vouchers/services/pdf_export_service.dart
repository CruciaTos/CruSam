// lib/features/vouchers/services/pdf_export_service.dart
//
// Changes vs previous version
// ────────────────────────────
// • _exportPages now detects the orientation of every captured page from the
//   PNG image dimensions stored in the IHDR chunk (bytes 16-23, big-endian).
//   Portrait  images  (width ≤ height) → PdfPageFormat.a4
//   Landscape images  (width  > height) → PdfPageFormat.a4.landscape
//   This makes the exported PDF match the on-screen preview exactly for any
//   mix of portrait and landscape pages, including the voucher bundle where
//   page 1 is portrait and pages 2+ are landscape.
// • All other logic, public API, and existing callers are unchanged.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import 'package:crusam/features/vouchers/widgets/tax_invoice_preview.dart';
import 'package:crusam/features/vouchers/widgets/voucher_pdf_preview.dart';
import 'package:crusam/features/vouchers/widgets/bank_disbursement_preview.dart';

// NOTE: The import paths above assume this file lives at
//   lib/features/vouchers/services/pdf_export_service.dart
// which is the existing location.  The relative widget imports therefore
// need to go up one level, e.g.:
//   import '../widgets/bank_disbursement_preview.dart';
// Adjust if your folder layout differs.

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

  // ──────────────────────────────────────────────────────────────────────────
  // PNG dimension reader
  //
  // A valid PNG file starts with an 8-byte signature followed immediately by
  // the IHDR chunk:
  //   bytes  0– 7  PNG signature
  //   bytes  8–11  IHDR chunk length (4 bytes, big-endian) — always 13
  //   bytes 12–15  "IHDR"
  //   bytes 16–19  image width  (4 bytes, big-endian)
  //   bytes 20–23  image height (4 bytes, big-endian)
  //
  // Reading these 8 bytes lets us determine orientation without decoding the
  // full image, and without any additional package dependency.
  // ──────────────────────────────────────────────────────────────────────────

  static ({int width, int height}) _pngDimensions(Uint8List bytes) {
    if (bytes.length < 24) return (width: 0, height: 0);
    final data = ByteData.sublistView(bytes, 16, 24);
    return (
      width:  data.getUint32(0, Endian.big),
      height: data.getUint32(4, Endian.big),
    );
  }

  /// Returns the correct [PdfPageFormat] for a captured PNG page.
  ///
  /// Landscape images (pixel width > pixel height) → A4 landscape.
  /// Portrait  images (pixel width ≤ pixel height) → A4 portrait.
  static PdfPageFormat _pageFormatForBytes(Uint8List bytes) {
    final dim = _pngDimensions(bytes);
    return dim.width > dim.height
        ? PdfPageFormat.a4.landscape
        : PdfPageFormat.a4;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Generic export – used by salary/attachment screens
  // ──────────────────────────────────────────────────────────────────────────

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
    await _exportPages(
      context:    context,
      pages:      pages,
      billNo:     fileNameSlug,
      subject:    shareSubject,
      filePrefix: filePrefix,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Invoice bundle (Tax Invoice + Voucher PDF) – mixed orientation
  // ──────────────────────────────────────────────────────────────────────────

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
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Bank disbursement export (all portrait)
  // ──────────────────────────────────────────────────────────────────────────

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
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core: capture every page widget → PNG bytes → PDF
  //
  // Each page is screenshotted at its *actual* Container size
  // (portrait or landscape), then inserted into a PDF page whose format is
  // derived from the captured image's pixel dimensions.  This guarantees that
  // the on-screen preview and the saved PDF are pixel-perfect identical.
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> _exportPages({
    required BuildContext  context,
    required List<Widget>  pages,
    required String        billNo,
    required String        subject,
    required String        filePrefix,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    await _ensurePdfFontsLoaded();

    // 1. Capture every page widget to PNG bytes.
    final capturedPages = <Uint8List>[];
    for (final page in pages) {
      capturedPages.add(await _capturePage(context, page));
    }

    // 2. Build the PDF, assigning the correct page format to each page.
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: _regularFont!,
        bold: _boldFont!,
      ),
    );

    for (final pageBytes in capturedPages) {
      final pdfImage  = pw.MemoryImage(pageBytes);
      // Derive orientation from the screenshot's pixel dimensions.
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

    // 3. Save and share.
    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final slug     = _slugify(billNo);
    final fileName = '${filePrefix}_$slug.pdf';
    final dir      = await _resolveOutputDir();
    final path     = '${dir.path}${Platform.pathSeparator}$fileName';
    final file     = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final written = await file.length();
    if (written == 0) throw Exception('File written but is empty: $path');

    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: fileName)],
      subject: subject,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Screenshot helper
  //
  // The widget is rendered at its *intrinsic* size — i.e. the Container
  // dimensions set by VoucherPdfPreview._buildPage (portrait: 793.7 × 1122.5,
  // landscape: 1122.5 × 793.7).  No rotation, no forced size override.
  // ──────────────────────────────────────────────────────────────────────────

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

  // ──────────────────────────────────────────────────────────────────────────
  // Asset pre-caching
  // ──────────────────────────────────────────────────────────────────────────

  static Future<void> _precacheInvoiceAssets(BuildContext context) async {
    await _precacheAssets(context, [
      'assets/images/aarti_logo.png',
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

  // ──────────────────────────────────────────────────────────────────────────
  // Utilities
  // ──────────────────────────────────────────────────────────────────────────

  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  /// Resolves the output directory:
  ///   1. User-chosen path (set via Profile → Export Paths).
  ///   2. Platform default: Downloads on desktop, app documents on mobile.
  static Future<Directory> _resolveOutputDir() async {
    final savedPath = ExportPreferencesNotifier.instance.pdfPath;
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

  // Kept for compatibility with any legacy call sites.
  static Future<String> exportTaxInvoiceFromWidget() async => '';
}
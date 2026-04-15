import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';

import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../widgets/bank_disbursement_preview.dart';
import '../widgets/tax_invoice_preview.dart';
import '../widgets/voucher_pdf_preview.dart';

class PdfExportService {
  static const Duration _captureDelay = Duration(milliseconds: 150);
  static const double _capturePixelRatio = 4.0;

  // ──────────────────────────────────────────────────────────────────────────
  // ✅ NEW: Generic export method – can be used by any feature
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> exportWidgets({
    required BuildContext context,
    required List<Widget> pages,
    required String fileNameSlug,
    required String filePrefix,
    required String shareSubject,
    List<String>? assetPathsToPrecache,
  }) async {
    if (assetPathsToPrecache != null) {
      await _precacheAssets(context, assetPathsToPrecache);
    }
    await _exportPages(
      context: context,
      pages: pages,
      billNo: fileNameSlug,
      subject: shareSubject,
      filePrefix: filePrefix,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Existing invoice‑bundle export (unchanged)
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> exportInvoiceBundle({
    required BuildContext context,
    required VoucherModel voucher,
    required CompanyConfigModel config,
    required EdgeInsets taxInvoiceMargins,
    required EdgeInsets voucherMargins,
  }) async {
    await _precacheInvoiceAssets(context);

    final pages = <Widget>[
      ...TaxInvoicePreview.buildPdfPages(
        voucher: voucher,
        config: config,
        margins: taxInvoiceMargins,
      ),
      ...VoucherPdfPreview.buildPdfPages(
        voucher: voucher,
        config: config,
        margins: voucherMargins,
      ),
    ];

    await _exportPages(
      context: context,
      pages: pages,
      billNo: voucher.billNo,
      subject: 'Tax Invoice & Voucher',
      filePrefix: 'tax_invoice_voucher',
    );
  }

  static Future<void> exportBankDisbursement({
    required BuildContext context,
    required VoucherModel voucher,
    required CompanyConfigModel config,
    required EdgeInsets margins,
  }) async {
    final pages = BankDisbursementPreview.buildPdfPages(
      voucher: voucher,
      config: config,
      margins: margins,
    );

    await _exportPages(
      context: context,
      pages: pages,
      billNo: voucher.billNo,
      subject: 'Bank Disbursement',
      filePrefix: 'bank_disbursement',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Core capture & PDF generation (private, reused by all)
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> _exportPages({
    required BuildContext context,
    required List<Widget> pages,
    required String billNo,
    required String subject,
    required String filePrefix,
  }) async {
    await WidgetsBinding.instance.endOfFrame;

    final capturedPages = <Uint8List>[];
    for (final page in pages) {
      capturedPages.add(await _capturePage(context, page));
    }

    final pdf = pw.Document();
    for (final pageBytes in capturedPages) {
      final pdfImage = pw.MemoryImage(pageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.SizedBox.expand(
            child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final slug = _slugify(billNo);
    final fileName = '${filePrefix}_$slug.pdf';

    final dir = await _resolveOutputDir();
    final path = '${dir.path}${Platform.pathSeparator}$fileName';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final written = await file.length();
    if (written == 0) throw Exception('File written but is empty: $path');

    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf', name: fileName)],
      subject: subject,
    );
  }

  static Future<Uint8List> _capturePage(
    BuildContext context,
    Widget page,
  ) async {
    final controller = ScreenshotController();
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;
    final mediaQuery = MediaQuery.maybeOf(context) ??
        const MediaQueryData(size: Size(800, 1200));

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
      context: context,
      delay: _captureDelay,
      pixelRatio: _capturePixelRatio,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Asset precaching helpers
  // ──────────────────────────────────────────────────────────────────────────
  static Future<void> _precacheInvoiceAssets(BuildContext context) async {
    await _precacheAssets(context, [
      'assets/images/aarti_logo.png',
      'assets/images/aarti_signature.png',
    ]);
  }

  static Future<void> _precacheAssets(
    BuildContext context,
    List<String> assetPaths,
  ) async {
    await Future.wait(
      assetPaths.map((path) => _safePrecache(context, path)),
    );
  }

  static Future<void> _safePrecache(BuildContext context, String assetPath) async {
    try {
      await precacheImage(AssetImage(assetPath), context);
    } catch (_) {
      // Fall back to the preview widget errorBuilder if the asset is unavailable.
    }
  }

  static String _slugify(String billNo) => billNo.isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  static Future<Directory> _resolveOutputDir() async {
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

  static Future<String> exportTaxInvoiceFromWidget() async => '';
}
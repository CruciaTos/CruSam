import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class PdfExportService {
  /// Pass the GlobalKey attached to the RepaintBoundary wrapping TaxInvoicePreview.
  static Future<String> exportTaxInvoiceFromWidget(
    GlobalKey previewKey,
    String billNo,
  ) async {
    final boundary =
        previewKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

    // 3x pixel ratio = crisp on print
    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final pdf = pw.Document();
    final pdfImage = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pdfImage, fit: pw.BoxFit.contain),
      ),
    );

    final bytes = await pdf.save();
    final slug =
        billNo.isEmpty
            ? '${DateTime.now().millisecondsSinceEpoch}'
            : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

    late Directory dir;
    if (Platform.isAndroid || Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
    } else {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      final downloads = Directory('$home/Downloads');
      dir =
          await downloads.exists()
              ? downloads
              : await getApplicationDocumentsDirectory();
    }

    final path = '${dir.path}/tax_invoice_$slug.pdf';
    await File(path).writeAsBytes(bytes);
    return path;
  }
}

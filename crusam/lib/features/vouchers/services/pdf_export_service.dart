import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

class PdfExportService {
  static Future<void> exportAndShare({
    required GlobalKey previewKey,
    required String billNo,
    required String subject,
  }) async {
    // wait for the current frame to finish painting before capture
    await WidgetsBinding.instance.endOfFrame;

    final context = previewKey.currentContext;
    if (context == null) throw Exception('Preview widget not in tree');

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw Exception('RenderRepaintBoundary not found on key');
    }

    final ui.Image image = await renderObject.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('Image capture returned null bytes');
    final pngBytes = byteData.buffer.asUint8List();

    final pdf = pw.Document();
    final pdfImage = pw.MemoryImage(pngBytes);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(
          pdfImage,
          fit: pw.BoxFit.contain,
          width: PdfPageFormat.a4.width,
          height: PdfPageFormat.a4.height,
        ),
      ),
    );

    final bytes = await pdf.save();
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');

    final slug = billNo.isEmpty
        ? '${DateTime.now().millisecondsSinceEpoch}'
        : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

    final dir = await _resolveOutputDir();
    final path = '${dir.path}/tax_invoice_$slug.pdf';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final written = await file.length();
    if (written == 0) throw Exception('File written but is empty: $path');

    await Share.shareXFiles(
      [XFile(path, mimeType: 'application/pdf')],
      subject: subject,
    );
  }

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

  // keep old name as alias so nothing else breaks if referenced elsewhere
  static Future<String> exportTaxInvoiceFromWidget(
    GlobalKey previewKey,
    String billNo,
  ) async {
    await exportAndShare(
      previewKey: previewKey,
      billNo: billNo,
      subject: 'Tax Invoice',
    );
    return '';
  }
}

// lib/features/pdf/service/pdf_file_saver.dart
//
// Where every generated PDF lands on disk. Priority: the per-type folder
// from Export Paths → the general PDF folder → Downloads → app documents.
// Never overwrites: an existing name gets a (1), (2), … suffix.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/preferences/export_preferences_notifier.dart';

class PdfFileSaver {
  PdfFileSaver._();

  /// Writes [bytes] as [fileName] (".pdf" appended if missing) and returns
  /// the full path written.
  static Future<String> save(
    Uint8List bytes, {
    required String fileName,
    required ExportPathTarget target,
  }) async {
    if (bytes.isEmpty) throw Exception('PDF encode returned empty bytes');
    final name = fileName.toLowerCase().endsWith('.pdf') ? fileName : '$fileName.pdf';
    final dir = await _outputDir(target);
    final path = await _uniquePath('${dir.path}${Platform.pathSeparator}$name');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// A bill number made safe for a file name; a timestamp when empty.
  static String slug(String billNo) => billNo.trim().isEmpty
      ? '${DateTime.now().millisecondsSinceEpoch}'
      : billNo.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');

  static Future<Directory> _outputDir(ExportPathTarget target) async {
    final prefs = ExportPreferencesNotifier.instance;

    final specific = switch (target) {
      ExportPathTarget.taxInvoice => prefs.taxInvoicePdfPath,
      ExportPathTarget.salary     => prefs.salaryPdfPath,
      _                           => '',
    };
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
        Platform.environment['USERPROFILE'] ??
        '.';
    final dl =
        Directory(Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  static Future<String> _uniquePath(String basePath) async {
    if (!await File(basePath).exists()) return basePath;
    final dot = basePath.lastIndexOf('.');
    final base = dot == -1 ? basePath : basePath.substring(0, dot);
    final ext = dot == -1 ? '' : basePath.substring(dot);
    var counter = 1;
    while (true) {
      final candidate = '$base($counter)$ext';
      if (!await File(candidate).exists()) return candidate;
      counter++;
    }
  }
}

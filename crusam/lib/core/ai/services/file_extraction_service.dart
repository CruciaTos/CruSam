// crusam/lib/core/ai/services/file_extraction_service.dart
//
// Pure-Dart extraction service for PDF and Excel files.
// No vision model involved — reads the actual text/data layer directly.
//
// Dependencies to add to pubspec.yaml:
//   syncfusion_flutter_pdf: ^27.1.48   # free community licence
//   excel: ^4.0.6                       # pure Dart, no native code

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// ── File type enum ─────────────────────────────────────────────────────────

enum AttachedFileType { pdf, excel, csv, json }

extension AttachedFileTypeX on AttachedFileType {
  String get label {
    switch (this) {
      case AttachedFileType.pdf:
        return 'PDF';
      case AttachedFileType.excel:
        return 'Excel';
      case AttachedFileType.csv:
        return 'CSV';
      case AttachedFileType.json:
        return 'JSON';
    }
  }

  String get icon {
    switch (this) {
      case AttachedFileType.pdf:
        return '📄';
      case AttachedFileType.excel:
        return '📊';
      case AttachedFileType.csv:
        return '📋';
      case AttachedFileType.json:
        return '🔧';
    }
  }

  /// Detect file type from extension string (e.g. 'salary.xlsx' → excel).
  static AttachedFileType? fromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return AttachedFileType.pdf;
      case 'xlsx':
      case 'xls':
        return AttachedFileType.excel;
      case 'csv':
        return AttachedFileType.csv;
      case 'json':
        return AttachedFileType.json;
      default:
        return null;
    }
  }
}

// ── Result model ───────────────────────────────────────────────────────────

class FileExtractionResult {
  const FileExtractionResult({
    required this.text,
    required this.fileType,
    required this.fileName,
    this.rowCount = 0,
    this.pageCount = 0,
    this.wasTruncated = false,
    this.looksScanned = false,
    this.tables = const [],
  });

  final String text;
  final AttachedFileType fileType;
  final String fileName;
  final int rowCount;    // Excel rows or PDF pages
  final int pageCount;
  final bool wasTruncated;
  final bool looksScanned;
  final List<FileExtractionTable> tables;

  /// A short summary line shown in the chat bubble header.
  String get summaryLine {
    final base = fileType == AttachedFileType.pdf
        ? '$pageCount page${pageCount == 1 ? '' : 's'}'
        : '$rowCount row${rowCount == 1 ? '' : 's'}';
    return '${fileType.icon} ${fileType.label} — $base${wasTruncated ? ' (truncated)' : ''}${looksScanned ? ' (image-based PDF)' : ''}';
  }

  /// Convert extraction output into a prompt-friendly block.
  String toPromptString() {
    final buffer = StringBuffer();
    buffer.writeln('=== Extracted ${fileType.label} file: $fileName ===');
    if (fileType == AttachedFileType.pdf) {
      buffer.writeln('Pages: $pageCount');
    } else {
      buffer.writeln('Rows: $rowCount');
    }
    if (looksScanned) {
      buffer.writeln('Warning: The document appears to contain image-based pages with no embedded text.');
    }
    if (wasTruncated) {
      buffer.writeln('Warning: Extraction was truncated due to size limits.');
    }
    buffer.writeln();

    if (tables.isNotEmpty) {
      for (final table in tables) {
        buffer.writeln('--- Parsed table from ${table.locationDescription} ---');
        for (final row in table.rows) {
          buffer.writeln(row.join(' | '));
        }
        buffer.writeln();
      }
    }

    buffer.writeln(text.trim());
    return buffer.toString().trim();
  }
}

class FileExtractionTable {
  const FileExtractionTable({
    required this.rows,
    required this.locationDescription,
  });

  final List<List<String>> rows;
  final String locationDescription;
}

// ── Extraction failure ─────────────────────────────────────────────────────

class FileExtractionException implements Exception {
  const FileExtractionException(this.message);
  final String message;
  @override
  String toString() => 'FileExtractionException: $message';
}

// ── Service ────────────────────────────────────────────────────────────────

class FileExtractionService {
  FileExtractionService._();

  /// Soft character limit before truncation (≈ 5 000 tokens).
  /// Keeps qwen2.3's context lean and time-to-first-token fast.
  static const int _maxChars = 20000;

  /// Cache for extracted results to avoid re-processing identical files.
  static final _cache = <String, FileExtractionResult>{};

  /// Maximum cache size to prevent memory issues.
  static const int _maxCacheSize = 10;

  // ── Public entry point ───────────────────────────────────────────────────

  /// Detect file type from [fileName] and extract text from [bytes].
  /// Throws [FileExtractionException] if type is unrecognised or extraction fails.
  static Future<FileExtractionResult> extract({
    required Uint8List bytes,
    required String fileName,
    void Function(String progress)? onProgress,
  }) async {
    // Generate cache key from file content hash + filename
    final hash = sha256.convert(bytes).toString();
    final cacheKey = '$hash:$fileName';

    // Check cache first
    if (_cache.containsKey(cacheKey)) {
      onProgress?.call('Using cached result');
      return _cache[cacheKey]!;
    }

    final type = AttachedFileTypeX.fromExtension(fileName);
    if (type == null) {
      throw FileExtractionException(
        'Unsupported file type: "$fileName". Only PDF, Excel (.xlsx/.xls), CSV, and JSON are supported.',
      );
    }

    onProgress?.call('Starting extraction...');

    final result = switch (type) {
      AttachedFileType.pdf => await _extractPdf(bytes, fileName, onProgress),
      AttachedFileType.excel => await _extractExcel(bytes, fileName, onProgress),
      AttachedFileType.csv => await _extractCsv(bytes, fileName, onProgress),
      AttachedFileType.json => await _extractJson(bytes, fileName, onProgress),
    };

    // Cache the result
    _addToCache(cacheKey, result);

    onProgress?.call('Extraction complete');
    return result;
  }

  static void _addToCache(String key, FileExtractionResult result) {
    if (_cache.length >= _maxCacheSize) {
      // Remove oldest entry (LinkedHashMap maintains insertion order)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  /// Clear the extraction cache (useful for memory management).
  static void clearCache() {
    _cache.clear();
  }

  // ── PDF extraction ───────────────────────────────────────────────────────

  static Future<FileExtractionResult> _extractPdf(Uint8List bytes, String fileName, void Function(String progress)? onProgress) async {
    PdfDocument? document;
    try {
      document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      final extractor = PdfTextExtractor(document);

      onProgress?.call('Processing PDF with $pageCount pages...');

      final buffer = StringBuffer();
      buffer.writeln('=== PDF Document: $fileName ===');
      buffer.writeln('Pages: $pageCount');
      buffer.writeln();

      bool truncated = false;
      bool hasExtractedText = false;
      final tables = <FileExtractionTable>[];

      for (int i = 0; i < pageCount; i++) {
        onProgress?.call('Extracting page ${i + 1} of $pageCount...');

        final rawPageText = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
        if (rawPageText.isEmpty) continue;

        hasExtractedText = true;
        final pageLines = rawPageText.split(RegExp(r'\r?\n'));
        final normalizedPageText = _normalizeExtractedPdfText(pageLines);
        final pageTable = _parseTableLikeLines(pageLines);

        if (pageTable.isNotEmpty) {
          tables.add(FileExtractionTable(
            rows: pageTable,
            locationDescription: 'page ${i + 1}',
          ));
        }

        buffer.writeln('--- Page ${i + 1} ---');
        buffer.writeln(normalizedPageText);
        buffer.writeln();

        if (buffer.length >= _maxChars) {
          truncated = true;
          buffer.writeln('[... document truncated at page ${i + 1} of $pageCount ...]');
          break;
        }
      }

      if (!hasExtractedText) {
        throw FileExtractionException(
          'PDF contains no embedded text. This is likely a scanned or image-based PDF. Use OCR or a scanned-document extraction pipeline for this file.',
        );
      }

      return FileExtractionResult(
        text: buffer.toString().trim(),
        fileType: AttachedFileType.pdf,
        fileName: fileName,
        pageCount: pageCount,
        wasTruncated: truncated,
        looksScanned: !hasExtractedText,
        tables: tables,
      );
    } catch (e) {
      throw FileExtractionException('Failed to read PDF: $e');
    } finally {
      document?.dispose();
    }
  }

  // ── Excel extraction ─────────────────────────────────────────────────────

  static Future<FileExtractionResult> _extractExcel(Uint8List bytes, String fileName, void Function(String progress)? onProgress) async {
    try {
      onProgress?.call('Decoding Excel file...');
      final excel = Excel.decodeBytes(bytes);
      final buffer = StringBuffer();
      buffer.writeln('=== Excel File: $fileName ===');

      int totalRows = 0;
      bool truncated = false;
      final tables = <FileExtractionTable>[];

      final sheetNames = excel.tables.keys.toList();
      onProgress?.call('Processing ${sheetNames.length} sheets...');

      for (final sheetName in sheetNames) {
        final sheet = excel.tables[sheetName]!;
        final rows = sheet.rows;

        // Skip completely empty sheets
        if (rows.isEmpty) continue;
        // Skip sheets where every cell in every row is blank
        final hasData = rows.any(
          (row) => row.any((cell) =>
              cell?.value != null && cell!.value.toString().trim().isNotEmpty),
        );
        if (!hasData) continue;

        onProgress?.call('Processing sheet: $sheetName');

        buffer.writeln();
        buffer.writeln('--- Sheet: $sheetName ---');

        final sheetTable = <List<String>>[];

        for (final row in rows) {
          final cells = row
              .map((cell) {
                final v = cell?.value;
                if (v == null) return '';
                // Format dates cleanly
                if (v is DateCellValue) {
                  return '${v.year}-${v.month.toString().padLeft(2, '0')}-${v.day.toString().padLeft(2, '0')}';
                }
                // Format numbers: strip unnecessary .0
                if (v is DoubleCellValue) {
                  final d = v.value;
                  return d == d.truncateToDouble()
                      ? d.toInt().toString()
                      : d.toStringAsFixed(2);
                }
                return v.toString().trim();
              })
              .toList();

          final rowText = cells.join(' | ');

          // Skip rows that are all empty after joining
          if (rowText.replaceAll('|', '').trim().isEmpty) continue;

          buffer.writeln(rowText);
          sheetTable.add(cells);
          totalRows++;

          if (buffer.length >= _maxChars) {
            truncated = true;
            buffer.writeln('[... sheet truncated — too many rows ...]');
            break;
          }
        }

        if (sheetTable.isNotEmpty) {
          tables.add(FileExtractionTable(
            rows: sheetTable,
            locationDescription: 'sheet "$sheetName"',
          ));
        }

        if (truncated) break;
      }

      if (totalRows == 0) {
        throw FileExtractionException(
          'The Excel file appears to be empty or contains no readable data.',
        );
      }

      return FileExtractionResult(
        text: buffer.toString().trim(),
        fileType: AttachedFileType.excel,
        fileName: fileName,
        rowCount: totalRows,
        wasTruncated: truncated,
        tables: tables,
      );
    } catch (e) {
      if (e is FileExtractionException) rethrow;
      throw FileExtractionException('Failed to read Excel file: $e');
    }
  }

  // ── CSV extraction ────────────────────────────────────────────────────────

  static Future<FileExtractionResult> _extractCsv(Uint8List bytes, String fileName, void Function(String progress)? onProgress) async {
    try {
      onProgress?.call('Parsing CSV file...');
      final csvString = String.fromCharCodes(bytes);
      final lines = csvString.split(RegExp(r'\r?\n')).where((line) => line.trim().isNotEmpty).toList();

      if (lines.isEmpty) {
        throw FileExtractionException('CSV file appears to be empty.');
      }

      onProgress?.call('Processing ${lines.length} rows...');

      final buffer = StringBuffer();
      buffer.writeln('=== CSV File: $fileName ===');
      buffer.writeln('Rows: ${lines.length}');

      final tables = <FileExtractionTable>[];
      final csvTable = <List<String>>[];

      for (final line in lines) {
        // Simple CSV parsing - split by comma, but handle quoted fields
        final cells = _parseCsvLine(line);
        csvTable.add(cells);
        buffer.writeln(cells.join(' | '));

        if (buffer.length >= _maxChars) {
          buffer.writeln('[... file truncated — too many rows ...]');
          break;
        }
      }

      if (csvTable.isNotEmpty) {
        tables.add(FileExtractionTable(
          rows: csvTable,
          locationDescription: 'entire file',
        ));
      }

      return FileExtractionResult(
        text: buffer.toString().trim(),
        fileType: AttachedFileType.csv,
        fileName: fileName,
        rowCount: lines.length,
        tables: tables,
      );
    } catch (e) {
      if (e is FileExtractionException) rethrow;
      throw FileExtractionException('Failed to read CSV file: $e');
    }
  }

  // ── JSON extraction ───────────────────────────────────────────────────────

  static Future<FileExtractionResult> _extractJson(Uint8List bytes, String fileName, void Function(String progress)? onProgress) async {
    try {
      onProgress?.call('Parsing JSON file...');
      final jsonString = String.fromCharCodes(bytes);
      final dynamic jsonData = jsonDecode(jsonString);

      final buffer = StringBuffer();
      buffer.writeln('=== JSON File: $fileName ===');

      final tables = <FileExtractionTable>[];
      int totalRows = 0;

      if (jsonData is List) {
        // Array of objects
        buffer.writeln('Type: Array of ${jsonData.length} items');
        onProgress?.call('Processing ${jsonData.length} items...');

        if (jsonData.isNotEmpty && jsonData.first is Map) {
          final headers = (jsonData.first as Map).keys.map((k) => k.toString()).toList();
          tables.add(FileExtractionTable(
            rows: [
              headers, // Header row
              ...jsonData.map((item) => headers.map((h) => (item as Map)[h]?.toString() ?? '').toList())
            ],
            locationDescription: 'root array',
          ));

          for (final item in jsonData) {
            buffer.writeln(item.toString());
            totalRows++;
            if (buffer.length >= _maxChars) {
              buffer.writeln('[... file truncated — too many items ...]');
              break;
            }
          }
        }
      } else if (jsonData is Map) {
        // Object
        buffer.writeln('Type: Object');
        buffer.writeln(jsonData.toString());
        totalRows = 1;
      } else {
        buffer.writeln('Type: ${jsonData.runtimeType}');
        buffer.writeln(jsonData.toString());
        totalRows = 1;
      }

      return FileExtractionResult(
        text: buffer.toString().trim(),
        fileType: AttachedFileType.json,
        fileName: fileName,
        rowCount: totalRows,
        tables: tables,
      );
    } catch (e) {
      throw FileExtractionException('Failed to read JSON file: $e');
    }
  }

  static List<String> _parseCsvLine(String line) {
    final cells = <String>[];
    bool inQuotes = false;
    final cell = StringBuffer();

    for (int i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          // Escaped quote
          cell.write('"');
          i++; // Skip next quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        cells.add(cell.toString().trim());
        cell.clear();
      } else {
        cell.write(char);
      }
    }

    cells.add(cell.toString().trim());
    return cells;
  }

  // ── PDF text normalization ────────────────────────────────────────────────

  static String _normalizeExtractedPdfText(List<String> lines) {
    final buffer = StringBuffer();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln(trimmed);
      }
    }
    return buffer.toString().trim();
  }

  // ── Table detection from PDF text ─────────────────────────────────────────

  static List<List<String>> _parseTableLikeLines(List<String> lines) {
    final tables = <List<String>>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Look for lines that might be table rows (contain multiple separators)
      final separators = ['|', '\t', '  ', '   ']; // tab, double space, triple space
      bool looksLikeTable = false;

      for (final sep in separators) {
        if (sep == '  ' && trimmed.split(sep).length >= 3) {
          looksLikeTable = true;
          break;
        } else if (sep == '   ' && trimmed.split(sep).length >= 3) {
          looksLikeTable = true;
          break;
        } else if (trimmed.contains(sep) && trimmed.split(sep).length >= 2) {
          looksLikeTable = true;
          break;
        }
      }

      if (looksLikeTable) {
        // Split by most common separator
        List<String> cells;
        if (trimmed.contains('|')) {
          cells = trimmed.split('|').map((c) => c.trim()).toList();
        } else if (trimmed.contains('\t')) {
          cells = trimmed.split('\t').map((c) => c.trim()).toList();
        } else {
          // Split by multiple spaces
          cells = trimmed.split(RegExp(r'\s{2,}')).map((c) => c.trim()).toList();
        }

        // Only add if we have at least 2 columns and reasonable content
        if (cells.length >= 2 && cells.any((c) => c.isNotEmpty)) {
          tables.add(cells);
        }
      }
    }

    return tables;
  }
}

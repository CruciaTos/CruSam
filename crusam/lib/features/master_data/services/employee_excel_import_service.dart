import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import '../../../data/models/employee_model.dart';

class ImportResult {
  final List<EmployeeModel> validEmployees;
  final int duplicateCount;
  final int invalidCount;

  int get validCount => validEmployees.length;

  const ImportResult({
    required this.validEmployees,
    required this.duplicateCount,
    required this.invalidCount,
  });
}

class EmployeeExcelImportService {
  static Future<ImportResult> importFromFile() async {
    final file = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );

    if (file == null || file.files.isEmpty) {
      throw Exception('No file selected');
    }

    final bytes = file.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Unable to read selected file');
    }

    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('No sheet found in excel file');
    }

    final sheet = excel.tables['Data Sheet'] ?? excel.tables.values.first;
    final rows = sheet.rows;
    if (rows.isEmpty) {
      throw Exception('Empty sheet');
    }

    final headerRow = rows.first
        .map((e) => _normalize(e?.value.toString() ?? ''))
        .toList(growable: false);

    final map = _mapHeaders(headerRow);

    final valid = <EmployeeModel>[];
    int invalid = 0;
    int duplicate = 0;

    final seenKeys = <String>{};

    for (int i = 1; i < rows.length; i++) {
      final row = rows[i];

      String readAt(int? idx) {
        if (idx == null || idx < 0 || idx >= row.length) return '';
        return _normalize(row[idx]?.value.toString() ?? '');
      }

      final rawName = readAt(map['name']);
      final rawPfNo = readAt(map['pfNo']);
      final rawUanNo = readAt(map['uanNo']);
      final rawAccountNo = readAt(map['accountNumber']);
      final rawCode = _normalizeEmployeeCode(readAt(map['code']));
      final rawIfsc = readAt(map['ifscCode']).toUpperCase();
      final rawBank = readAt(map['bankDetails']);
      final rawBranch = readAt(map['branch']);
      final rawZone = readAt(map['zone']);
      final rawDoj = _normalizeDate(readAt(map['dateOfJoining']));
      final rawAartiAcNo = readAt(map['aartiAcNo']);
      final rawSbCode = readAt(map['sbCode']);
      final rawSrNo = readAt(map['srNo']);

      final hasAnyData = [
        rawName,
        rawPfNo,
        rawUanNo,
        rawAccountNo,
        rawCode,
        rawIfsc,
        rawBank,
        rawBranch,
        rawZone,
        rawDoj,
        rawAartiAcNo,
        rawSbCode,
        rawSrNo,
      ].any((e) => e.isNotEmpty);

      if (!hasAnyData) {
        continue;
      }

      if (rawName.isEmpty) {
        invalid++;
        continue;
      }

      final dedupeKey = _buildDedupeKey(
        name: rawName,
        pfNo: rawPfNo,
        uanNo: rawUanNo,
        accountNumber: rawAccountNo,
      );

      if (seenKeys.contains(dedupeKey)) {
        duplicate++;
        continue;
      }
      seenKeys.add(dedupeKey);

      valid.add(
        EmployeeModel(
          srNo: _parseInt(rawSrNo),
          name: rawName,
          pfNo: rawPfNo,
          uanNo: rawUanNo,
          code: rawCode,
          ifscCode: rawIfsc,
          accountNumber: rawAccountNo,
          aartiAcNo: rawAartiAcNo.isNotEmpty ? rawAartiAcNo : '0680651100000338',
          sbCode: rawSbCode.isNotEmpty ? rawSbCode : '10',
          bankDetails: rawBank,
          branch: rawBranch,
          zone: rawZone,
          dateOfJoining: rawDoj,
        ),
      );
    }

    return ImportResult(
      validEmployees: valid,
      duplicateCount: duplicate,
      invalidCount: invalid,
    );
  }

  static Map<String, int> _mapHeaders(List<String> headers) {
    final map = <String, int>{};

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].toLowerCase();
      if (h.isEmpty) continue;

      if (h.contains('sr') && h.contains('no')) map['srNo'] = i;
      if (h.contains('technician') || h == 'name' || h.contains('name of')) {
        map['name'] = i;
      }
      if (h.contains('pf')) map['pfNo'] = i;
      if (h.contains('uan')) map['uanNo'] = i;
      if (h == 'code') map['code'] = i;
      if (h.contains('ifsc')) map['ifscCode'] = i;

      if (h.contains('aarti') && h.contains('a/c')) map['aartiAcNo'] = i;
      if ((h.contains('s/b') && h.contains('code')) || h == 'sb code') {
        map['sbCode'] = i;
      }

      if (h.contains('account number') && !h.contains('aarti')) {
        map['accountNumber'] = i;
      }

      if (h.contains('bank details') || h == 'bank') map['bankDetails'] = i;
      if (h.contains('branch')) map['branch'] = i;
      if (h.contains('zone')) map['zone'] = i;
      if (h.contains('joining')) map['dateOfJoining'] = i;
    }

    return map;
  }

  static String _buildDedupeKey({
    required String name,
    required String pfNo,
    required String uanNo,
    required String accountNumber,
  }) {
    if (pfNo.isNotEmpty && pfNo != '-') return 'pf:${pfNo.toLowerCase()}';
    if (uanNo.isNotEmpty && uanNo != '-') return 'uan:${uanNo.toLowerCase()}';
    return 'na:${name.toLowerCase()}|${accountNumber.toLowerCase()}';
  }

  static int _parseInt(String value) {
    final clean = value.replaceAll(RegExp(r'[^0-9-]'), '');
    return int.tryParse(clean) ?? 0;
  }

  static String _normalizeEmployeeCode(String raw) {
    final code = _normalize(raw);
    final upper = code.toUpperCase();
    if (upper == 'AP' || upper == 'A&P') return 'A&P';
    return code;
  }

  static String _normalize(String text) {
    return text
        .replaceAll('\u00A0', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normalizeDate(String raw) {
    if (raw.isEmpty) return '';

    final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
    if (iso != null) {
      return '${iso.group(3)}/${iso.group(2)}/${iso.group(1)}';
    }

    final dmyDash = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(raw);
    if (dmyDash != null) {
      return '${dmyDash.group(1)}/${dmyDash.group(2)}/${dmyDash.group(3)}';
    }

    final dmySlash = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
    if (dmySlash != null) {
      return raw;
    }

    final serial = double.tryParse(raw);
    if (serial != null) {
      final excelEpoch = DateTime(1899, 12, 30);
      final dt = excelEpoch.add(Duration(days: serial.floor()));
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      return '$dd/$mm/${dt.year}';
    }

    return raw;
  }
}
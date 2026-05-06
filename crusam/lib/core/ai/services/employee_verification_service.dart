import 'package:crusam/core/ai/services/file_extraction_service.dart';
import 'package:crusam/data/models/employee_model.dart';

class ExtractedEmployeeRecord {
  ExtractedEmployeeRecord({
    required this.name,
    required this.pfNo,
    required this.uanNo,
    required this.code,
    required this.source,
  });

  final String name;
  final String pfNo;
  final String uanNo;
  final String code;
  final String source;

  String get normalizedName => _normalizeText(name);
  String get normalizedPf => _normalizeIdentifier(pfNo);
  String get normalizedUan => _normalizeIdentifier(uanNo);
  String get normalizedCode => _normalizeEmployeeCode(code);

  bool get hasReliableKey => normalizedPf.isNotEmpty || normalizedUan.isNotEmpty || normalizedCode.isNotEmpty;

  static String _normalizeText(String text) {
    return text
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
  }

  static String _normalizeIdentifier(String raw) {
    return raw
        .replaceAll(RegExp(r'[^\w\d]'), '')
        .trim()
        .toLowerCase();
  }

  static String _normalizeEmployeeCode(String raw) {
    final code = _normalizeText(raw).toUpperCase();
    if (code == 'AP' || code == 'A&P') return 'A&P';
    return raw.trim();
  }
}

class EmployeeFieldChange {
  EmployeeFieldChange({
    required this.field,
    required this.appValue,
    required this.fileValue,
  });

  final String field;
  final String appValue;
  final String fileValue;
}

class EmployeeMatch {
  EmployeeMatch({
    required this.extracted,
    required this.appEmployee,
    required this.fieldChanges,
  });

  final ExtractedEmployeeRecord extracted;
  final EmployeeModel appEmployee;
  final List<EmployeeFieldChange> fieldChanges;
}

class EmployeeVerificationResult {
  EmployeeVerificationResult({
    required this.matched,
    required this.additions,
    required this.deletions,
    required this.updates,
    required this.ambiguous,
  });

  final List<EmployeeMatch> matched;
  final List<ExtractedEmployeeRecord> additions;
  final List<EmployeeModel> deletions;
  final List<EmployeeMatch> updates;
  final List<ExtractedEmployeeRecord> ambiguous;

  bool get hasDifferences => additions.isNotEmpty || deletions.isNotEmpty || updates.isNotEmpty || ambiguous.isNotEmpty;

  String toPromptString() {
    final buffer = StringBuffer();

    buffer.writeln('=== Employee Verification Summary ===');
    buffer.writeln('Matched records: ${matched.length}');
    buffer.writeln('Potential additions: ${additions.length}');
    buffer.writeln('Potential deletions: ${deletions.length}');
    buffer.writeln('Field updates: ${updates.length}');
    if (ambiguous.isNotEmpty) {
      buffer.writeln('Ambiguous rows: ${ambiguous.length}');
    }
    buffer.writeln();

    if (additions.isNotEmpty) {
      buffer.writeln('--- Additions (file record not found in app) ---');
      for (final record in additions) {
        buffer.writeln('Name: ${record.name}, PF No: ${record.pfNo}, UAN: ${record.uanNo}, Code: ${record.code}');
      }
      buffer.writeln();
    }

    if (updates.isNotEmpty) {
      buffer.writeln('--- Updates (file record matches app employee but differs) ---');
      for (final match in updates) {
        buffer.writeln('App: ${match.appEmployee.name} (ID: ${match.appEmployee.id ?? 'unknown'})');
        buffer.writeln('File: ${match.extracted.name}, PF No: ${match.extracted.pfNo}, UAN: ${match.extracted.uanNo}, Code: ${match.extracted.code}');
        for (final change in match.fieldChanges) {
          buffer.writeln('  • ${change.field}: app="${change.appValue}" file="${change.fileValue}"');
        }
      }
      buffer.writeln();
    }

    if (deletions.isNotEmpty) {
      buffer.writeln('--- Deletions (app employee not found in file) ---');
      for (final employee in deletions) {
        buffer.writeln('Name: ${employee.name}, PF No: ${employee.pfNo}, UAN: ${employee.uanNo}, Code: ${employee.code}');
      }
      buffer.writeln();
    }

    if (ambiguous.isNotEmpty) {
      buffer.writeln('--- Ambiguous extracted records (could not safely match) ---');
      for (final record in ambiguous) {
        buffer.writeln('Name: ${record.name}, PF No: ${record.pfNo}, UAN: ${record.uanNo}, Code: ${record.code}');
      }
      buffer.writeln();
    }

    return buffer.toString().trim();
  }
}

class EmployeeVerificationService {
  EmployeeVerificationService._();

  static EmployeeVerificationResult compare(
    FileExtractionResult extraction,
    List<EmployeeModel> appEmployees,
  ) {
    final extractedRecords = _extractEmployeeRecords(extraction);
    final appByPf = <String, EmployeeModel>{};
    final appByUan = <String, EmployeeModel>{};
    final appByCode = <String, EmployeeModel>{};
    final appByName = <String, EmployeeModel>{};
    final ambiguousNames = <String>{};

    for (final employee in appEmployees) {
      final pfKey = _normalizeIdentifier(employee.pfNo);
      if (pfKey.isNotEmpty) appByPf[pfKey] = employee;

      final uanKey = _normalizeIdentifier(employee.uanNo);
      if (uanKey.isNotEmpty) appByUan[uanKey] = employee;

      final codeKey = _normalizeEmployeeCode(employee.code);
      if (codeKey.isNotEmpty) appByCode[codeKey] = employee;

      final nameKey = _normalizeText(employee.name);
      if (nameKey.isNotEmpty) {
        if (appByName.containsKey(nameKey)) {
          ambiguousNames.add(nameKey);
          appByName.remove(nameKey);
        } else if (!ambiguousNames.contains(nameKey)) {
          appByName[nameKey] = employee;
        }
      }
    }

    final matched = <EmployeeMatch>[];
    final updates = <EmployeeMatch>[];
    final additions = <ExtractedEmployeeRecord>[];
    final ambiguous = <ExtractedEmployeeRecord>[];
    final matchedAppKeys = <String>{};

    for (final record in extractedRecords) {
      final employee = _findMatchingAppEmployee(record, appByPf, appByUan, appByCode, appByName);
      if (employee == null) {
        if (record.hasReliableKey) {
          additions.add(record);
        } else {
          ambiguous.add(record);
        }
        continue;
      }

      final fieldChanges = _findFieldChanges(employee, record);
      final match = EmployeeMatch(
        extracted: record,
        appEmployee: employee,
        fieldChanges: fieldChanges,
      );

      matched.add(match);
      matchedAppKeys.add(_employeeKey(employee));

      if (fieldChanges.isNotEmpty) {
        updates.add(match);
      }
    }

    final deletions = appEmployees.where((employee) {
      final key = _employeeKey(employee);
      return !matchedAppKeys.contains(key);
    }).toList();

    return EmployeeVerificationResult(
      matched: matched,
      additions: additions,
      deletions: deletions,
      updates: updates,
      ambiguous: ambiguous,
    );
  }

  static List<ExtractedEmployeeRecord> _extractEmployeeRecords(FileExtractionResult extraction) {
    final records = <ExtractedEmployeeRecord>[];

    for (final table in extraction.tables) {
      if (table.rows.length < 2) continue;

      final header = table.rows.first.map(_normalizeText).toList(growable: false);
      final columnMap = _detectHeaderColumns(header);
      if (columnMap.isEmpty) {
        continue;
      }

      for (var rowIndex = 1; rowIndex < table.rows.length; rowIndex++) {
        final row = table.rows[rowIndex];
        final name = _valueAt(row, columnMap['name']);
        final pfNo = _valueAt(row, columnMap['pfNo']);
        final uanNo = _valueAt(row, columnMap['uanNo']);
        final code = _valueAt(row, columnMap['code']);

        if (name.isEmpty && pfNo.isEmpty && uanNo.isEmpty && code.isEmpty) {
          continue;
        }

        if (name.isEmpty && pfNo.isEmpty && uanNo.isEmpty) {
          continue;
        }

        records.add(ExtractedEmployeeRecord(
          name: name,
          pfNo: pfNo,
          uanNo: uanNo,
          code: code,
          source: table.locationDescription,
        ));
      }
    }

    return records;
  }

  static Map<String, int> _detectHeaderColumns(List<String> headerRow) {
    final map = <String, int>{};

    for (var i = 0; i < headerRow.length; i++) {
      final cell = headerRow[i];
      if (cell.contains('technician') || cell.contains('employee') || cell.contains('name')) {
        map['name'] = i;
      }
      if (cell.contains('pf')) {
        map['pfNo'] = i;
      }
      if (cell.contains('uan')) {
        map['uanNo'] = i;
      }
      if (cell == 'code' || cell.contains('code')) {
        map['code'] = i;
      }
    }

    if (map.containsKey('name') || map.containsKey('pfNo') || map.containsKey('uanNo') || map.containsKey('code')) {
      return map;
    }
    return {};
  }

  static EmployeeModel? _findMatchingAppEmployee(
    ExtractedEmployeeRecord record,
    Map<String, EmployeeModel> appByPf,
    Map<String, EmployeeModel> appByUan,
    Map<String, EmployeeModel> appByCode,
    Map<String, EmployeeModel> appByName,
  ) {
    if (record.normalizedPf.isNotEmpty && appByPf.containsKey(record.normalizedPf)) {
      return appByPf[record.normalizedPf];
    }
    if (record.normalizedUan.isNotEmpty && appByUan.containsKey(record.normalizedUan)) {
      return appByUan[record.normalizedUan];
    }
    if (record.normalizedCode.isNotEmpty && appByCode.containsKey(record.normalizedCode)) {
      return appByCode[record.normalizedCode];
    }
    if (record.normalizedName.isNotEmpty && appByName.containsKey(record.normalizedName)) {
      return appByName[record.normalizedName];
    }
    return null;
  }

  static List<EmployeeFieldChange> _findFieldChanges(
    EmployeeModel appEmployee,
    ExtractedEmployeeRecord record,
  ) {
    final changes = <EmployeeFieldChange>[];
    if (_normalizeText(appEmployee.name) != record.normalizedName && record.name.isNotEmpty) {
      changes.add(EmployeeFieldChange(field: 'name', appValue: appEmployee.name, fileValue: record.name));
    }
    if (_normalizeIdentifier(appEmployee.pfNo) != record.normalizedPf && record.pfNo.isNotEmpty) {
      changes.add(EmployeeFieldChange(field: 'pfNo', appValue: appEmployee.pfNo, fileValue: record.pfNo));
    }
    if (_normalizeIdentifier(appEmployee.uanNo) != record.normalizedUan && record.uanNo.isNotEmpty) {
      changes.add(EmployeeFieldChange(field: 'uanNo', appValue: appEmployee.uanNo, fileValue: record.uanNo));
    }
    if (_normalizeEmployeeCode(appEmployee.code) != record.normalizedCode && record.code.isNotEmpty) {
      changes.add(EmployeeFieldChange(field: 'code', appValue: appEmployee.code, fileValue: record.code));
    }
    return changes;
  }

  static String _valueAt(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index].trim();
  }

  static String _normalizeText(String text) {
    return ExtractedEmployeeRecord._normalizeText(text);
  }

  static String _normalizeIdentifier(String raw) {
    return ExtractedEmployeeRecord._normalizeIdentifier(raw);
  }

  static String _normalizeEmployeeCode(String raw) {
    return ExtractedEmployeeRecord._normalizeEmployeeCode(raw);
  }

  static String _employeeKey(EmployeeModel employee) {
    final pfKey = _normalizeIdentifier(employee.pfNo);
    if (pfKey.isNotEmpty) return 'pf:$pfKey';

    final uanKey = _normalizeIdentifier(employee.uanNo);
    if (uanKey.isNotEmpty) return 'uan:$uanKey';

    final codeKey = _normalizeEmployeeCode(employee.code);
    if (codeKey.isNotEmpty) return 'code:$codeKey';

    return 'name:${_normalizeText(employee.name)}';
  }
}

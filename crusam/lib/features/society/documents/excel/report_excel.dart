import 'dart:typed_data';
import 'package:excel/excel.dart';
import '../../data/models/society_models.dart';
import '../../domain/reports/report_definitions.dart';

class ReportExcel {
  const ReportExcel._();

  static List<int>? generateBytes({
    required Society society,
    required ReportResult report,
  }) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    // Society & Report Title Header
    sheet.appendRow([TextCellValue(society.name)]);
    sheet.appendRow([TextCellValue(report.definition.title)]);
    if (report.parameters.containsKey('fromDate') && report.parameters.containsKey('toDate')) {
      sheet.appendRow([TextCellValue('Period: ${report.parameters['fromDate']} to ${report.parameters['toDate']}')]);
    } else if (report.parameters.containsKey('asOfDate')) {
      sheet.appendRow([TextCellValue('As of Date: ${report.parameters['asOfDate']}')]);
    }
    sheet.appendRow([TextCellValue('')]);

    // Columns
    final headerRow = report.columns.map((col) => TextCellValue(col.label)).toList();
    sheet.appendRow(headerRow);

    // Data Rows
    for (final row in report.rows) {
      final line = report.columns.map((col) {
        final val = row[col.key]?.toString() ?? '';
        return TextCellValue(val);
      }).toList();
      sheet.appendRow(line);
    }

    return excel.encode();
  }
}

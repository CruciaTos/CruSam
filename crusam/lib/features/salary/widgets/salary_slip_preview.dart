import 'package:flutter/material.dart';

import '../../pdf/widgets/pdf_pages_preview.dart';
import 'package:crusam_core/crusam_core.dart';

/// One A4 sheet of salary slips (two employees, or one) — renders the exact
/// page the Salary Slips export writes for them.
class SalarySlipPairPage extends StatelessWidget {
  final List<EmployeeModel> employees; // exactly 2, or 1
  final CompanyConfigModel config;
  final int Function(int employeeId) getDays;
  final String month;
  final String year;
  final int daysInMonth;
  final bool isMsw;
  final double mswAmount;
  final bool isFeb;

  const SalarySlipPairPage({
    super.key,
    required this.employees,
    required this.config,
    required this.getDays,
    required this.month,
    required this.year,
    required this.daysInMonth,
    required this.isMsw,
    required this.mswAmount,
    required this.isFeb,
  }) : assert(employees.length <= 2, 'At most two employees per page');

  @override
  Widget build(BuildContext context) => PdfPagesPreview(
        inputs: [
          config.toMap(),
          for (final e in employees) ...[e.toMap(), getDays(e.id ?? 0)],
          month, year, daysInMonth, isMsw, mswAmount, isFeb,
        ],
        build: () => SalaryPdfExportService.buildSalarySlipsBytes(
          config: config,
          employees: employees,
          monthName: month,
          year: int.tryParse(year) ?? DateTime.now().year,
          daysInMonth: daysInMonth,
          isMsw: isMsw,
          isFeb: isFeb,
        ),
      );
}

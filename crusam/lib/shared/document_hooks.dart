// lib/shared/document_hooks.dart
//
// The PDF builders live in crusam_core (shared with the CruSam MCP server)
// and reach app services only through ExportHooks. This connects them to the
// app: bundled assets, saved margins/column widths, the PDF saver and the
// live salary screen state.

import 'package:crusam_core/crusam_core.dart' show ExportHooks, SalaryFormulaEngine;
import 'package:flutter/services.dart' show rootBundle;

import '../data/db/database_helper.dart';
import '../features/pdf/service/pdf_file_saver.dart';
import '../features/salary/notifier/salary_data_notifier.dart';
import '../features/salary/notifier/salary_formula_notifier.dart';

void wireSharedDocumentHooks() {
  ExportHooks.loadAsset = rootBundle.load;
  ExportHooks.margins = DatabaseHelper.instance.getMarginSettings;
  ExportHooks.voucherColumnWidths = DatabaseHelper.instance.getVoucherColumnWidths;
  ExportHooks.bankColumnWidths = DatabaseHelper.instance.getBankColumnWidths;
  ExportHooks.savePdf = PdfFileSaver.save;
  ExportHooks.liveSalaryDaysFor = SalaryDataNotifier.instance.getDays;
  ExportHooks.liveMswAmount = () => SalaryDataNotifier.instance.mswAmount;
  SalaryFormulaEngine.configProvider = () => SalaryFormulaNotifier.instance.config;
}

// lib/core/preferences/export_preferences_notifier.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ExportPathTarget {
  taxInvoiceVoucherPdf,
  bankDisbursementPdf,
  taxInvoiceExcel,
  bankDisbursementExcel,
  salaryStatementPdf,
  salaryStatementExcel,
  salarySlipsPdf,
  salaryInvoicePdf,
  attachmentAPdf,
  attachmentBPdf,
  finalInvoicePdf,
}

extension ExportPathTargetX on ExportPathTarget {
  bool get usesPdfDefaults => switch (this) {
        ExportPathTarget.taxInvoiceExcel ||
        ExportPathTarget.bankDisbursementExcel ||
        ExportPathTarget.salaryStatementExcel => false,
        _ => true,
      };

  String get preferenceKey => 'export_target_${name}_path';

  String get label => switch (this) {
        ExportPathTarget.taxInvoiceVoucherPdf => 'Tax Invoice + Voucher PDF',
        ExportPathTarget.bankDisbursementPdf => 'Bank Disbursement PDF',
        ExportPathTarget.taxInvoiceExcel => 'Tax Invoice Excel',
        ExportPathTarget.bankDisbursementExcel => 'Bank Disbursement Excel',
        ExportPathTarget.salaryStatementPdf => 'Salary Statement PDF',
        ExportPathTarget.salaryStatementExcel => 'Salary Statement Excel',
        ExportPathTarget.salarySlipsPdf => 'Salary Slips PDF',
        ExportPathTarget.salaryInvoicePdf => 'Salary Invoice PDF',
        ExportPathTarget.attachmentAPdf => 'Attachment A PDF',
        ExportPathTarget.attachmentBPdf => 'Attachment B PDF',
        ExportPathTarget.finalInvoicePdf => 'Final Invoice PDF',
      };
}

class ExportPreferencesNotifier extends ChangeNotifier {
  ExportPreferencesNotifier._();
  static final ExportPreferencesNotifier instance = ExportPreferencesNotifier._();

  static const _kPdfPath       = 'export_pdf_path';
  static const _kExcelPath     = 'export_excel_path';
  static const _kUseWidgetPdf  = 'use_widget_pdf_invoice_voucher'; // ← new

  String _pdfPath   = '';
  String _excelPath = '';
  bool   _useWidgetPdf = false; // ← new
  final Map<ExportPathTarget, String> _targetPaths = {
    for (final target in ExportPathTarget.values) target: '',
  };
  bool   _loaded    = false;

  String get pdfPath             => _pdfPath;
  String get excelPath           => _excelPath;
  bool   get useWidgetPdfForInvoiceVoucher => _useWidgetPdf; // ← new
  String pathForTarget(ExportPathTarget target) => _targetPaths[target] ?? '';
  String defaultPathForTarget(ExportPathTarget target) =>
      target.usesPdfDefaults ? _pdfPath : _excelPath;

  String resolvedPathForTarget(ExportPathTarget target) {
    final specificPath = pathForTarget(target);
    if (specificPath.isNotEmpty) return specificPath;
    return defaultPathForTarget(target);
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _pdfPath        = prefs.getString(_kPdfPath)   ?? '';
    _excelPath      = prefs.getString(_kExcelPath) ?? '';
    _useWidgetPdf   = prefs.getBool(_kUseWidgetPdf) ?? false; // ← new
    for (final target in ExportPathTarget.values) {
      _targetPaths[target] = prefs.getString(target.preferenceKey) ?? '';
    }
    _loaded         = true;
    notifyListeners();
  }

  Future<void> setPdfPath(String path) async {
    if (_pdfPath == path) return;
    _pdfPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPdfPath, path);
    notifyListeners();
  }

  Future<void> setExcelPath(String path) async {
    if (_excelPath == path) return;
    _excelPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kExcelPath, path);
    notifyListeners();
  }

  // ── NEW ────────────────────────────────────────────────────────────────────
  Future<void> setUseWidgetPdf(bool value) async {
    if (_useWidgetPdf == value) return;
    _useWidgetPdf = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseWidgetPdf, value);
    notifyListeners();
  }
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> setPathForTarget(ExportPathTarget target, String path) async {
    if ((_targetPaths[target] ?? '') == path) return;
    _targetPaths[target] = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(target.preferenceKey, path);
    notifyListeners();
  }

  Future<void> clearPdfPath() async {
    if (_pdfPath.isEmpty) return;
    _pdfPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPdfPath);
    notifyListeners();
  }

  Future<void> clearExcelPath() async {
    if (_excelPath.isEmpty) return;
    _excelPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kExcelPath);
    notifyListeners();
  }

  Future<void> clearPathForTarget(ExportPathTarget target) async {
    if ((_targetPaths[target] ?? '').isEmpty) return;
    _targetPaths[target] = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(target.preferenceKey);
    notifyListeners();
  }
}
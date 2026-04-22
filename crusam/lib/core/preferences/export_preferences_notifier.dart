// lib/core/preferences/export_preferences_notifier.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Enum for per‑target export paths — includes PDF and Excel variants
// ═══════════════════════════════════════════════════════════════════════════
enum ExportPathTarget {
  taxInvoice,                // Tax Invoice & Voucher PDF
  salary,                    // Salary Documents PDF
  general,                   // Fallback (uses general PDF path)
  salaryStatementExcel,      // Salary Statement Excel (monthly statement)
  taxInvoiceExcel,           // Tax Invoice Excel (generated via Python)
  bankDisbursementExcel;     // Bank Disbursement Excel sheet

  /// Returns true for PDF targets, false for Excel targets.
  bool get usesPdfDefaults =>
      this != salaryStatementExcel &&
      this != taxInvoiceExcel &&
      this != bankDisbursementExcel;
}

class ExportPreferencesNotifier extends ChangeNotifier {
  ExportPreferencesNotifier._();
  static final ExportPreferencesNotifier instance = ExportPreferencesNotifier._();

  // ── SharedPreferences keys ───────────────────────────────────────────────
  static const _kPdfPath              = 'export_pdf_path';
  static const _kExcelPath            = 'export_excel_path';
  static const _kUseWidgetPdf         = 'use_widget_pdf_invoice_voucher';
  static const _kTaxInvoicePdfPath    = 'export_tax_invoice_pdf_path';
  static const _kSalaryPdfPath        = 'export_salary_pdf_path';

  // ── State ────────────────────────────────────────────────────────────────
  String _pdfPath           = '';
  String _excelPath         = '';
  bool   _useWidgetPdf      = false;
  String _taxInvoicePdfPath = '';
  String _salaryPdfPath     = '';
  bool   _loaded            = false;

  // ── Getters ──────────────────────────────────────────────────────────────
  String get pdfPath                         => _pdfPath;
  String get excelPath                       => _excelPath;
  bool   get useWidgetPdfForInvoiceVoucher   => _useWidgetPdf;
  String get taxInvoicePdfPath               => _taxInvoicePdfPath;
  String get salaryPdfPath                   => _salaryPdfPath;

  // ── Load ─────────────────────────────────────────────────────────────────
  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _pdfPath           = prefs.getString(_kPdfPath)           ?? '';
    _excelPath         = prefs.getString(_kExcelPath)         ?? '';
    _useWidgetPdf      = prefs.getBool(_kUseWidgetPdf)        ?? false;
    _taxInvoicePdfPath = prefs.getString(_kTaxInvoicePdfPath) ?? '';
    _salaryPdfPath     = prefs.getString(_kSalaryPdfPath)     ?? '';
    _loaded = true;
    notifyListeners();
  }

  // ── General PDF path ─────────────────────────────────────────────────────
  Future<void> setPdfPath(String path) async {
    if (_pdfPath == path) return;
    _pdfPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPdfPath, path);
    notifyListeners();
  }

  Future<void> clearPdfPath() async {
    if (_pdfPath.isEmpty) return;
    _pdfPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPdfPath);
    notifyListeners();
  }

  // ── Excel path ───────────────────────────────────────────────────────────
  Future<void> setExcelPath(String path) async {
    if (_excelPath == path) return;
    _excelPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kExcelPath, path);
    notifyListeners();
  }

  Future<void> clearExcelPath() async {
    if (_excelPath.isEmpty) return;
    _excelPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kExcelPath);
    notifyListeners();
  }

  // ── Widget PDF toggle ────────────────────────────────────────────────────
  Future<void> setUseWidgetPdf(bool value) async {
    if (_useWidgetPdf == value) return;
    _useWidgetPdf = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseWidgetPdf, value);
    notifyListeners();
  }

  // ── Tax Invoice & Voucher PDF path ───────────────────────────────────────
  Future<void> setTaxInvoicePdfPath(String path) async {
    if (_taxInvoicePdfPath == path) return;
    _taxInvoicePdfPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTaxInvoicePdfPath, path);
    notifyListeners();
  }

  Future<void> clearTaxInvoicePdfPath() async {
    if (_taxInvoicePdfPath.isEmpty) return;
    _taxInvoicePdfPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kTaxInvoicePdfPath);
    notifyListeners();
  }

  // ── Salary documents PDF path ───────────────────────────────────────────
  Future<void> setSalaryPdfPath(String path) async {
    if (_salaryPdfPath == path) return;
    _salaryPdfPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSalaryPdfPath, path);
    notifyListeners();
  }

  Future<void> clearSalaryPdfPath() async {
    if (_salaryPdfPath.isEmpty) return;
    _salaryPdfPath = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSalaryPdfPath);
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Task 3: Per‑target path resolution
  // ═══════════════════════════════════════════════════════════════════════════

  /// Returns the user‑configured path for [target], or its default fallback.
  String resolvedPathForTarget(ExportPathTarget target) {
    final specificPath = pathForTarget(target);
    if (specificPath.isNotEmpty) return specificPath;
    return defaultPathForTarget(target);
  }

  /// Returns the specific path saved for [target] (empty string if none).
  String pathForTarget(ExportPathTarget target) {
    switch (target) {
      case ExportPathTarget.taxInvoice:
        return _taxInvoicePdfPath;
      case ExportPathTarget.salary:
        return _salaryPdfPath;
      case ExportPathTarget.general:
        return _pdfPath;
      case ExportPathTarget.salaryStatementExcel:
      case ExportPathTarget.taxInvoiceExcel:
      case ExportPathTarget.bankDisbursementExcel:
        return _excelPath;    // All Excel exports share the general Excel path
    }
  }

  /// Returns the default fallback path for [target].
  String defaultPathForTarget(ExportPathTarget target) {
    return target.usesPdfDefaults ? _pdfPath : _excelPath;
  }
}
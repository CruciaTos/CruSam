// lib/core/preferences/export_preferences_notifier.dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExportPreferencesNotifier extends ChangeNotifier {
  ExportPreferencesNotifier._();
  static final ExportPreferencesNotifier instance = ExportPreferencesNotifier._();

  static const _kPdfPath       = 'export_pdf_path';
  static const _kExcelPath     = 'export_excel_path';
  static const _kUseWidgetPdf  = 'use_widget_pdf_invoice_voucher'; // ← new

  String _pdfPath   = '';
  String _excelPath = '';
  bool   _useWidgetPdf = false; // ← new
  bool   _loaded    = false;

  String get pdfPath             => _pdfPath;
  String get excelPath           => _excelPath;
  bool   get useWidgetPdfForInvoiceVoucher => _useWidgetPdf; // ← new

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _pdfPath        = prefs.getString(_kPdfPath)   ?? '';
    _excelPath      = prefs.getString(_kExcelPath) ?? '';
    _useWidgetPdf   = prefs.getBool(_kUseWidgetPdf) ?? false; // ← new
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
}
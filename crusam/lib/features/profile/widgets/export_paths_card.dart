// lib/features/profile/widgets/export_paths_card.dart
//
// Exposes four independently configurable save directories.
// Visual styling now matches the indigo theme used across the app.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/preferences/export_preferences_notifier.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – consistent with the indigo theme
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';

  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsBody = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
  );

  static const tsSmall = TextStyle(
    fontFamily : fcond,
    fontWeight : FontWeight.w500,
    fontSize   : 11,
    color      : inkMuted,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
  );

  static const double radius  = 6.0;
  static const double cRadius = 10.0;
  static const double padH    = 18.0;
  static const double padV    = 16.0;
}

class ExportPathsCard extends StatefulWidget {
  const ExportPathsCard({super.key});

  @override
  State<ExportPathsCard> createState() => _ExportPathsCardState();
}

class _ExportPathsCardState extends State<ExportPathsCard> {
  final _prefs = ExportPreferencesNotifier.instance;

  late final TextEditingController _pdfCtrl;
  late final TextEditingController _taxInvoiceCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _excelCtrl;

  bool _pdfSaving        = false;
  bool _taxInvoiceSaving = false;
  bool _salarySaving     = false;
  bool _excelSaving      = false;

  bool get _supportsDirectoryPicker =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _pdfCtrl        = TextEditingController(text: _prefs.pdfPath);
    _taxInvoiceCtrl = TextEditingController(text: _prefs.taxInvoicePdfPath);
    _salaryCtrl     = TextEditingController(text: _prefs.salaryPdfPath);
    _excelCtrl      = TextEditingController(text: _prefs.excelPath);
    _prefs.addListener(_onPrefsChanged);
  }

  void _onPrefsChanged() {
    if (_pdfCtrl.text        != _prefs.pdfPath)           _pdfCtrl.text        = _prefs.pdfPath;
    if (_taxInvoiceCtrl.text != _prefs.taxInvoicePdfPath) _taxInvoiceCtrl.text = _prefs.taxInvoicePdfPath;
    if (_salaryCtrl.text     != _prefs.salaryPdfPath)     _salaryCtrl.text     = _prefs.salaryPdfPath;
    if (_excelCtrl.text      != _prefs.excelPath)         _excelCtrl.text      = _prefs.excelPath;
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _pdfCtrl.dispose();
    _taxInvoiceCtrl.dispose();
    _salaryCtrl.dispose();
    _excelCtrl.dispose();
    super.dispose();
  }

  Future<String?> _pickDir(String confirmText) async {
    try {
      return await getDirectoryPath(confirmButtonText: confirmText);
    } catch (_) {
      return null;
    }
  }

  // ── General PDF ────────────────────────────────────────────────────────
  Future<void> _pickPdf() async {
    final p = await _pickDir('Choose General PDF Folder');
    if (p == null || !mounted) return;
    _pdfCtrl.text = p;
    await _savePdf();
  }

  Future<void> _savePdf() async {
    setState(() => _pdfSaving = true);
    await _prefs.setPdfPath(_pdfCtrl.text.trim());
    if (mounted) setState(() => _pdfSaving = false);
  }

  Future<void> _clearPdf() async {
    await _prefs.clearPdfPath();
  }

  // ── Tax Invoice ────────────────────────────────────────────────────────
  Future<void> _pickTaxInvoice() async {
    final p = await _pickDir('Choose Tax Invoice & Voucher PDF Folder');
    if (p == null || !mounted) return;
    _taxInvoiceCtrl.text = p;
    await _saveTaxInvoice();
  }

  Future<void> _saveTaxInvoice() async {
    setState(() => _taxInvoiceSaving = true);
    await _prefs.setTaxInvoicePdfPath(_taxInvoiceCtrl.text.trim());
    if (mounted) setState(() => _taxInvoiceSaving = false);
  }

  Future<void> _clearTaxInvoice() async {
    await _prefs.clearTaxInvoicePdfPath();
  }

  // ── Salary PDFs ────────────────────────────────────────────────────────
  Future<void> _pickSalary() async {
    final p = await _pickDir('Choose Salary Documents PDF Folder');
    if (p == null || !mounted) return;
    _salaryCtrl.text = p;
    await _saveSalary();
  }

  Future<void> _saveSalary() async {
    setState(() => _salarySaving = true);
    await _prefs.setSalaryPdfPath(_salaryCtrl.text.trim());
    if (mounted) setState(() => _salarySaving = false);
  }

  Future<void> _clearSalary() async {
    await _prefs.clearSalaryPdfPath();
  }

  // ── Excel ──────────────────────────────────────────────────────────────
  Future<void> _pickExcel() async {
    final p = await _pickDir('Choose Excel Export Folder');
    if (p == null || !mounted) return;
    _excelCtrl.text = p;
    await _saveExcel();
  }

  Future<void> _saveExcel() async {
    setState(() => _excelSaving = true);
    await _prefs.setExcelPath(_excelCtrl.text.trim());
    if (mounted) setState(() => _excelSaving = false);
  }

  Future<void> _clearExcel() async {
    await _prefs.clearExcelPath();
  }

  // ── Build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: _Tok.surface,
          border: Border.all(color: _Tok.border),
          borderRadius: BorderRadius.circular(_Tok.cRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header bar
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: _Tok.padH),
              decoration: const BoxDecoration(
                color: _Tok.surfaceAlt,
                border: Border(bottom: BorderSide(color: _Tok.divider)),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(_Tok.cRadius),
                  topRight: Radius.circular(_Tok.cRadius),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _Tok.ink,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Icon(Icons.folder_outlined, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Text('EXPORT PATHS', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
                ],
              ),
            ),

            // Body content
            Padding(
              padding: const EdgeInsets.all(_Tok.padV),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set where each file type is saved. Specific paths take priority over the General PDF fallback.',
                    style: _Tok.tsSmall,
                  ),
                  const SizedBox(height: 20),

                  // ── 1. General PDF ─────────────────────────────────────
                  _sectionLabel('General PDF', 'Fallback path — used when no specific path is set.'),
                  const SizedBox(height: 6),
                  _PathRow(
                    icon: Icons.picture_as_pdf_outlined,
                    iconColor: _Tok.inkMuted,
                    controller: _pdfCtrl,
                    isSaving: _pdfSaving,
                    currentSavedPath: _prefs.pdfPath,
                    supportsDirectoryPicker: _supportsDirectoryPicker,
                    onPickDirectory: _pickPdf,
                    onSave: _savePdf,
                    onClear: _clearPdf,
                  ),

                  const Divider(height: 28, color: _Tok.divider),

                  // ── 2. Tax Invoice & Voucher ──────────────────────────
                  _sectionLabel('Tax Invoice & Voucher PDF', 'Bills generated from the Voucher Builder.'),
                  const SizedBox(height: 6),
                  _PathRow(
                    icon: Icons.receipt_long_outlined,
                    iconColor: _Tok.inkLight,
                    controller: _taxInvoiceCtrl,
                    isSaving: _taxInvoiceSaving,
                    currentSavedPath: _prefs.taxInvoicePdfPath,
                    supportsDirectoryPicker: _supportsDirectoryPicker,
                    onPickDirectory: _pickTaxInvoice,
                    onSave: _saveTaxInvoice,
                    onClear: _clearTaxInvoice,
                  ),

                  const Divider(height: 28, color: _Tok.divider),

                  // ── 3. Salary Documents ───────────────────────────────
                  _sectionLabel('Salary Documents PDF', 'Salary slips, statements, invoices, Attachment A & B.'),
                  const SizedBox(height: 6),
                  _PathRow(
                    icon: Icons.badge_outlined,
                    iconColor: const Color(0xFF065F46), // keep a green accent for salary
                    controller: _salaryCtrl,
                    isSaving: _salarySaving,
                    currentSavedPath: _prefs.salaryPdfPath,
                    supportsDirectoryPicker: _supportsDirectoryPicker,
                    onPickDirectory: _pickSalary,
                    onSave: _saveSalary,
                    onClear: _clearSalary,
                  ),

                  const Divider(height: 28, color: _Tok.divider),

                  // ── 4. Excel ──────────────────────────────────────────
                  _sectionLabel('Excel Exports', 'Bank disbursement sheets and salary statement spreadsheets.'),
                  const SizedBox(height: 6),
                  _PathRow(
                    icon: Icons.table_chart_outlined,
                    iconColor: const Color(0xFF065F46),
                    controller: _excelCtrl,
                    isSaving: _excelSaving,
                    currentSavedPath: _prefs.excelPath,
                    supportsDirectoryPicker: _supportsDirectoryPicker,
                    onPickDirectory: _pickExcel,
                    onSave: _saveExcel,
                    onClear: _clearExcel,
                  ),

                  const SizedBox(height: 12),
                  Text(
                    _supportsDirectoryPicker
                        ? 'Tap the folder icon to browse, or type a path and press Save.'
                        : 'Files are shared via the system share sheet. Custom paths are not supported on this platform.',
                    style: _Tok.tsSmall.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, String subtitle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: _Tok.tsSmall),
        ],
      );
}

// ── _PathRow ─────────────────────────────────────────────────────────────────
class _PathRow extends StatelessWidget {
  final IconData  icon;
  final Color     iconColor;
  final TextEditingController controller;
  final bool      isSaving;
  final String    currentSavedPath;
  final bool      supportsDirectoryPicker;
  final VoidCallback onPickDirectory;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _PathRow({
    required this.icon,
    required this.iconColor,
    required this.controller,
    required this.isSaving,
    required this.currentSavedPath,
    required this.supportsDirectoryPicker,
    required this.onPickDirectory,
    required this.onSave,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasPath = currentSavedPath.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Text field
            Expanded(
              child: TextField(
                controller: controller,
                style: _Tok.tsInput,
                readOnly: !supportsDirectoryPicker && (Platform.isAndroid || Platform.isIOS),
                decoration: InputDecoration(
                  hintText: hasPath ? currentSavedPath : 'Default (Downloads / Documents)',
                  hintStyle: _Tok.tsSmall,
                  prefixIcon: Icon(icon, size: 16, color: iconColor),
                  suffixIcon: supportsDirectoryPicker
                      ? Tooltip(
                          message: 'Browse folder',
                          child: IconButton(
                            icon: Icon(Icons.folder_open_outlined, size: 18, color: _Tok.inkLight),
                            onPressed: onPickDirectory,
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_Tok.radius),
                    borderSide: const BorderSide(color: _Tok.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_Tok.radius),
                    borderSide: const BorderSide(color: _Tok.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_Tok.radius),
                    borderSide: const BorderSide(color: _Tok.inkLight, width: 1.5),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Save button
            SizedBox(
              height: 38,
              child: ElevatedButton(
                onPressed: isSaving ? null : onSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Tok.ink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(_Tok.radius),
                  ),
                  elevation: 0,
                ),
                child: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Save', style: _Tok.tsLabel.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),

            // Clear button (only when a custom path is saved)
            if (hasPath) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Reset to default',
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: _Tok.inkMuted,
                  onPressed: onClear,
                ),
              ),
            ],
          ],
        ),

        // Current saved path display
        if (hasPath)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 12, color: _Tok.inkLight),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentSavedPath,
                    style: _Tok.tsSmall.copyWith(fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
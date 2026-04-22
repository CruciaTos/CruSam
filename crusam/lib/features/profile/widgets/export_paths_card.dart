// lib/features/profile/widgets/export_paths_card.dart
//
// Task 3: Replaces the old inline _ExportPathsCard that lived inside
// profile_screen.dart.  Now exposes four independently configurable
// save directories:
//
//   1. General PDF        (fallback for any PDF not in 2 or 3)
//   2. Tax Invoice & Voucher PDF
//   3. Salary Documents PDF  (slips, statement, invoices, attachments)
//   4. Excel exports
//
// Each row is backed by ExportPreferencesNotifier and persisted via
// SharedPreferences.  A native directory-picker dialog is offered on
// Windows / macOS / Linux.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

class ExportPathsCard extends StatefulWidget {
  const ExportPathsCard({super.key});

  @override
  State<ExportPathsCard> createState() => _ExportPathsCardState();
}

class _ExportPathsCardState extends State<ExportPathsCard> {
  final _prefs = ExportPreferencesNotifier.instance;

  // ── Controllers (one per path row) ──────────────────────────────────────
  late final TextEditingController _pdfCtrl;
  late final TextEditingController _taxInvoiceCtrl;
  late final TextEditingController _salaryCtrl;
  late final TextEditingController _excelCtrl;

  // ── Saving spinners ──────────────────────────────────────────────────────
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

  // ── Directory picker ─────────────────────────────────────────────────────
  Future<String?> _pickDir(String confirmText) async {
    try {
      return await getDirectoryPath(confirmButtonText: confirmText);
    } catch (_) {
      return null;
    }
  }

  // ── General PDF ──────────────────────────────────────────────────────────
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

  // ── Tax Invoice ──────────────────────────────────────────────────────────
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

  // ── Salary PDFs ──────────────────────────────────────────────────────────
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

  // ── Excel ────────────────────────────────────────────────────────────────
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

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _prefs,
      builder: (context, _) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.folder_outlined, size: 18, color: AppColors.slate500),
              const SizedBox(width: 8),
              Text('Export Paths', style: AppTextStyles.h4),
            ]),
            const SizedBox(height: 4),
            Text(
              'Set where each file type is saved. Specific paths take priority over the General PDF fallback.',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
            const SizedBox(height: 20),

            // ── 1. General PDF (fallback) ───────────────────────────────────
            _sectionLabel('General PDF', 'Fallback path — used when no specific path is set.'),
            const SizedBox(height: 6),
            _PathRow(
              icon: Icons.picture_as_pdf_outlined,
              iconColor: AppColors.slate500,
              controller: _pdfCtrl,
              isSaving: _pdfSaving,
              currentSavedPath: _prefs.pdfPath,
              supportsDirectoryPicker: _supportsDirectoryPicker,
              onPickDirectory: _pickPdf,
              onSave: _savePdf,
              onClear: _clearPdf,
            ),

            const Divider(height: 28),

            // ── 2. Tax Invoice & Voucher ────────────────────────────────────
            _sectionLabel('Tax Invoice & Voucher PDF',
                'Bills generated from the Voucher Builder.'),
            const SizedBox(height: 6),
            _PathRow(
              icon: Icons.receipt_long_outlined,
              iconColor: const Color(0xFF2563EB),
              controller: _taxInvoiceCtrl,
              isSaving: _taxInvoiceSaving,
              currentSavedPath: _prefs.taxInvoicePdfPath,
              supportsDirectoryPicker: _supportsDirectoryPicker,
              onPickDirectory: _pickTaxInvoice,
              onSave: _saveTaxInvoice,
              onClear: _clearTaxInvoice,
            ),

            const Divider(height: 28),

            // ── 3. Salary Documents ─────────────────────────────────────────
            _sectionLabel('Salary Documents PDF',
                'Salary slips, statements, invoices, Attachment A & B.'),
            const SizedBox(height: 6),
            _PathRow(
              icon: Icons.badge_outlined,
              iconColor: const Color(0xFF059669),
              controller: _salaryCtrl,
              isSaving: _salarySaving,
              currentSavedPath: _prefs.salaryPdfPath,
              supportsDirectoryPicker: _supportsDirectoryPicker,
              onPickDirectory: _pickSalary,
              onSave: _saveSalary,
              onClear: _clearSalary,
            ),

            const Divider(height: 28),

            // ── 4. Excel ────────────────────────────────────────────────────
            _sectionLabel('Excel Exports',
                'Bank disbursement sheets and salary statement spreadsheets.'),
            const SizedBox(height: 6),
            _PathRow(
              icon: Icons.table_chart_outlined,
              iconColor: const Color(0xFF16A34A),
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
              style: AppTextStyles.small.copyWith(
                  color: AppColors.slate400, fontSize: 11),
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
            style: AppTextStyles.small.copyWith(
                fontWeight: FontWeight.w600, color: AppColors.slate700),
          ),
          const SizedBox(height: 2),
          Text(subtitle,
              style:
                  AppTextStyles.small.copyWith(color: AppColors.slate400, fontSize: 11)),
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
                style: AppTextStyles.input,
                readOnly: !supportsDirectoryPicker &&
                    (Platform.isAndroid || Platform.isIOS),
                decoration: InputDecoration(
                  hintText: hasPath
                      ? currentSavedPath
                      : 'Default (Downloads / Documents)',
                  hintStyle: AppTextStyles.small
                      .copyWith(color: AppColors.slate400),
                  prefixIcon: Icon(icon, size: 16, color: iconColor),
                  suffixIcon: supportsDirectoryPicker
                      ? Tooltip(
                          message: 'Browse folder',
                          child: IconButton(
                            icon: const Icon(Icons.folder_open_outlined,
                                size: 18, color: AppColors.slate500),
                            onPressed: onPickDirectory,
                          ),
                        )
                      : null,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Save', style: TextStyle(fontSize: 13)),
              ),
            ),

            // Clear icon (only when a custom path is saved)
            if (hasPath) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Reset to default',
                child: IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: AppColors.slate400,
                  onPressed: onClear,
                ),
              ),
            ],
          ],
        ),

        // Show current saved path
        if (hasPath)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 2),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 12, color: AppColors.emerald600),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    currentSavedPath,
                    style: AppTextStyles.small.copyWith(
                        fontSize: 11, color: AppColors.slate500),
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
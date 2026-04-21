import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../core/preferences/export_preferences_notifier.dart';
import '../notifiers/voucher_notifier.dart';
import '../widgets/invoice_preview_dialog.dart';
import 'package:go_router/go_router.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<VoucherModel> _vouchers = [];
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final vMaps = await DatabaseHelper.instance.getAllVouchers();
    final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
    if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);
    final loaded = <VoucherModel>[];
    for (final v in vMaps) {
      final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
      loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
    }
    if (mounted) setState(() { _vouchers = loaded; _loading = false; });
  }

  Future<void> _deleteVoucher(VoucherModel v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Delete "${v.title.isEmpty ? "(Untitled)" : v.title}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && v.id != null) {
      await DatabaseHelper.instance.deleteVoucher(v.id!);
      await _load();
    }
  }

  void _editVoucher(BuildContext context, VoucherModel v) {
    final hasUnsavedWork = VoucherNotifier.instance.current.rows.isNotEmpty ||
        VoucherNotifier.instance.current.title.isNotEmpty;

    if (!hasUnsavedWork) {
      _loadIntoBuilder(context, v);
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Overwrite Current Draft?'),
        content: const Text(
          'The Voucher Builder has unsaved work.\n'
          'Loading this invoice will replace it. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.indigo600),
            child: const Text('Load Invoice'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) _loadIntoBuilder(context, v);
    });
  }

  void _loadIntoBuilder(BuildContext context, VoucherModel v) {
    VoucherNotifier.instance.update((_) => v);
    context.go('/vouchers');
  }

  // ── Export invoice list as CSV ─────────────────────────────────────────────
  Future<void> _exportList() async {
    if (_exporting || _vouchers.isEmpty) {
      if (_vouchers.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No invoices to export.')),
        );
      }
      return;
    }
    setState(() => _exporting = true);

    try {
      // Build CSV content
      final buf = StringBuffer();

      // Header row
      buf.writeln('Bill No,Date,Voucher Ref,Dept,Base Amount,CGST,SGST,Total Amount,Status');

      // Data rows — escape fields that may contain commas or quotes
      for (final v in _vouchers) {
        buf.writeln([
          _csvField(v.billNo.isEmpty ? '—' : v.billNo),
          _csvField(v.date),
          _csvField(v.title.isEmpty ? '(Untitled)' : v.title),
          _csvField(v.deptCode),
          v.baseTotal.toStringAsFixed(2),
          v.cgst.toStringAsFixed(2),
          v.sgst.toStringAsFixed(2),
          v.finalTotal.toStringAsFixed(2),
          _csvField(v.status.name),
        ].join(','));
      }

      // Resolve output directory (mirrors WidgetPdfExportService._outputDir)
      final dir = await _outputDir();
      final stamp = DateTime.now();
      final filename =
          'invoice_list_${stamp.year}${_pad(stamp.month)}${_pad(stamp.day)}'
          '_${_pad(stamp.hour)}${_pad(stamp.minute)}.csv';
      final path = '${dir.path}${Platform.pathSeparator}$filename';

      await File(path).writeAsString(buf.toString(), flush: true);

      // Open the file with the OS default app
      _openFile(path);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported: $filename'),
            action: SnackBarAction(
              label: 'Open Folder',
              onPressed: () => _openFolder(dir.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // ── CSV helpers ────────────────────────────────────────────────────────────

  /// Wraps a field in double-quotes if it contains commas, quotes, or newlines,
  /// and escapes any internal double-quotes per RFC 4180.
  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  // ── OS helpers ─────────────────────────────────────────────────────────────

  static Future<Directory> _outputDir() async {
    final saved = ExportPreferencesNotifier.instance.pdfPath;
    if (saved.isNotEmpty) {
      final dir = Directory(saved);
      if (await dir.exists()) return dir;
    }
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(
        Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }

  static void _openFile(String path) {
    try {
      if (Platform.isWindows)    Process.run('cmd',    ['/c', 'start', '', path]);
      else if (Platform.isMacOS) Process.run('open',   [path]);
      else if (Platform.isLinux) Process.run('xdg-open', [path]);
    } catch (_) {}
  }

  static void _openFolder(String folder) {
    try {
      if (Platform.isWindows)    Process.run('explorer', [folder]);
      else if (Platform.isMacOS) Process.run('open',     [folder]);
      else if (Platform.isLinux) Process.run('xdg-open', [folder]);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.pagePadding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Generated Invoices', style: AppTextStyles.h3),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: (_loading || _exporting) ? null : _exportList,
              icon: _exporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined, size: 16),
              label: Text(_exporting ? 'Exporting…' : 'Export List'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_loading)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: _vouchers.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: Text(
                          'No invoices generated yet.\nFinalise a voucher to create one.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Bill No')),
                          DataColumn(label: Text('Date')),
                          DataColumn(label: Text('Voucher Ref')),
                          DataColumn(label: Text('Dept')),
                          DataColumn(label: Text('Amount'), numeric: true),
                          DataColumn(label: Text('Status')),
                          DataColumn(label: Text('Actions')),
                        ],
                        rows: _vouchers.map((v) => DataRow(cells: [
                          DataCell(Text(
                            v.billNo.isNotEmpty ? v.billNo : '—',
                            style: AppTextStyles.bodySemi.copyWith(
                                color: AppColors.indigo600, fontSize: 13),
                          )),
                          DataCell(Text(v.date)),
                          DataCell(Text(v.title.isEmpty ? '(Untitled)' : v.title)),
                          DataCell(Text(v.deptCode)),
                          DataCell(Text(
                            formatCurrency(v.finalTotal),
                            style: AppTextStyles.bodySemi.copyWith(fontSize: 13),
                          )),
                          DataCell(_StatusBadge(status: v.status)),
                          DataCell(Row(children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 17, color: AppColors.indigo600),
                              onPressed: () => _editVoucher(context, v),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: const Icon(Icons.description_outlined,
                                  size: 17, color: AppColors.indigo600),
                              onPressed: () {
                                final previewNotifier = VoucherNotifier()
                                  ..current = v;
                                InvoicePreviewDialog.show(
                                  context,
                                  previewNotifier,
                                  _config,
                                  PreviewType.invoice,
                                );
                              },
                              tooltip: 'View',
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 17, color: Colors.red),
                              onPressed: () => _deleteVoucher(v),
                              tooltip: 'Delete',
                            ),
                          ])),
                        ])).toList(),
                      ),
                    ),
            ),
          ),
      ],
    ),
  );
}

class _StatusBadge extends StatelessWidget {
  final VoucherStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final saved = status == VoucherStatus.saved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: saved ? AppColors.emerald100 : AppColors.amber100,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        status.name.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: saved ? AppColors.emerald700 : AppColors.amber700,
        ),
      ),
    );
  }
}
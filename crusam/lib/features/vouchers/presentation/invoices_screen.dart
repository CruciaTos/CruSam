import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';
import '../../../core/preferences/export_preferences_notifier.dart';
import '../notifiers/voucher_notifier.dart';
import '../widgets/invoice_preview_dialog.dart';
import '../widgets/send_invoice_dialog.dart';
import '../../../data/db/email_log_repository.dart';
import '../../../data/models/email_log_model.dart';
import 'package:go_router/go_router.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});
  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  List<VoucherModel> _vouchers = [];
  Map<int, EmailLogModel> _sentLogs = {};
  CompanyConfigModel _config = const CompanyConfigModel();
  bool _loading = true;
  bool _exporting = false;
  String? _selectedCreator;

  List<String> get _creators {
    final values = _vouchers
        .map((v) => v.createdBy.trim().toLowerCase())
        .where((email) => email.isNotEmpty && email != 'unknown')
        .toSet()
        .toList()
      ..sort();
    return values;
  }

  List<VoucherModel> get _visibleVouchers {
    final selected = _selectedCreator;
    if (selected == null || selected.isEmpty) return _vouchers;
    return _vouchers
        .where((v) => v.createdBy.trim().toLowerCase() == selected)
        .toList(growable: false);
  }

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
    final sentLogs =
        await DatabaseHelper.instance.getLatestSentEmailLogsByType('invoice');
    if (mounted) {
      setState(() {
        _vouchers = loaded;
        _sentLogs = sentLogs;
        _loading = false;
      });
    }
  }

  // ── Quick-send from the list — no need to open the full preview ──────────
  Future<void> _quickSendEmail(VoucherModel v) async {
    final m = await DatabaseHelper.instance.getMarginSettings();
    final margins = EdgeInsets.fromLTRB(m.left, m.top, m.right, m.bottom);
    if (!mounted) return;
    await SendInvoiceDialog.show(
      context,
      voucher: v,
      config: _config,
      taxInvoiceMargins: margins,
    );
    // Sending updates email_log — refresh so the "Sent ✓" badge appears
    // without the user having to manually reload the screen.
    await _load();
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

  Future<void> _editVoucher(BuildContext context, VoucherModel v) async {
    final hasUnsavedWork = VoucherNotifier.instance.current.rows.isNotEmpty ||
        VoucherNotifier.instance.current.title.isNotEmpty;

    if (!hasUnsavedWork) {
      _loadIntoBuilder(context, v);
      return;
    }

    final confirmed = await showDialog<bool>(
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
    );
    if (!context.mounted || confirmed != true) return;
    _loadIntoBuilder(context, v);
  }

  void _loadIntoBuilder(BuildContext context, VoucherModel v) {
    VoucherNotifier.instance.update((_) => v);
    context.go('/vouchers');
  }

  // ── Export invoice list as CSV ─────────────────────────────────────────────
  Future<void> _exportList() async {
    final exportRows = _visibleVouchers;
    if (_exporting || exportRows.isEmpty) {
      if (exportRows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No invoices to export.')),
        );
      }
      return;
    }
    setState(() => _exporting = true);

    try {
      final buf = StringBuffer();
      buf.writeln('Bill No,Date,Voucher Ref,Dept,Created By,Updated By,Base Amount,CGST,SGST,Total Amount,Status');
      for (final v in exportRows) {
        buf.writeln([
          _csvField(v.billNo.isEmpty ? '—' : v.billNo),
          _csvField(v.date),
          _csvField(v.title.isEmpty ? '(Untitled)' : v.title),
          _csvField(v.deptCode),
          _csvField(v.createdBy.isEmpty ? '—' : v.createdBy),
          _csvField(v.updatedBy.isEmpty ? '—' : v.updatedBy),
          v.baseTotal.toStringAsFixed(2),
          v.cgst.toStringAsFixed(2),
          v.sgst.toStringAsFixed(2),
          v.finalTotal.toStringAsFixed(2),
          _csvField(v.status.name),
        ].join(','));
      }

      final dir = await _outputDir();
      final stamp = DateTime.now();
      final filename =
          'invoice_list_${stamp.year}${_pad(stamp.month)}${_pad(stamp.day)}'
          '_${_pad(stamp.hour)}${_pad(stamp.minute)}.csv';
      final path = '${dir.path}${Platform.pathSeparator}$filename';
      await File(path).writeAsString(buf.toString(), flush: true);
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

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

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
      if (Platform.isWindows) {
        Process.run('cmd',    ['/c', 'start', '', path]);
      } else if (Platform.isMacOS) {
        Process.run('open', [path]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  static void _openFolder(String folder) {
    try {
      if (Platform.isWindows) {
        Process.run('explorer', [folder]);
      } else if (Platform.isMacOS) {
        Process.run('open', [folder]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [folder]);
      }
    } catch (_) {}
  }

  // ── New UI Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final visible = _visibleVouchers;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Invoices',
                      style: AppTextStyles.h3.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (!_loading && _vouchers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: OutlinedButton.icon(
                        onPressed: _exporting ? null : _exportList,
                        icon: _exporting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_outlined, size: 18),
                        label: Text(_exporting ? 'Exporting…' : 'Export'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.indigo600,
                          side: const BorderSide(color: AppColors.indigo600),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Creator filter chips ────────────────────────────────
              if (!_loading && _vouchers.isNotEmpty) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedCreator == null,
                        onSelected: (_) => setState(() => _selectedCreator = null),
                        backgroundColor: Colors.white,
                        selectedColor: AppColors.indigo50,
                        checkmarkColor: AppColors.indigo600,
                        side: BorderSide(
                          color: AppColors.indigo600.withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        showCheckmark: false,
                      ),
                      const SizedBox(width: 8),
                      ..._creators.map(
                        (email) => Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: FilterChip(
                            label: Text(email),
                            selected: _selectedCreator == email,
                            onSelected: (selected) {
                              setState(() => _selectedCreator = selected ? email : null);
                            },
                            backgroundColor: Colors.white,
                            selectedColor: AppColors.indigo50,
                            checkmarkColor: AppColors.indigo600,
                            side: BorderSide(
                              color: AppColors.indigo600.withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            showCheckmark: false,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Invoice list ────────────────────────────────────────
              if (_loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visible.isEmpty)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No invoices yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Finalise a voucher to create one.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final v = visible[index];
                      return _InvoiceCard(
                        voucher: v,
                        sentLog: v.id != null ? _sentLogs[v.id] : null,
                        onEdit: () => _editVoucher(context, v),
                        onPreview: () {
                          final previewNotifier = VoucherNotifier()..current = v;
                          InvoicePreviewDialog.show(
                            context,
                            previewNotifier,
                            _config,
                            PreviewType.invoice,
                          );
                        },
                        onSendEmail: v.status == VoucherStatus.saved
                            ? () => _quickSendEmail(v)
                            : null,
                        onDelete: () => _deleteVoucher(v),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Invoice Card Widget ──────────────────────────────────────────────────────
class _InvoiceCard extends StatelessWidget {
  final VoucherModel voucher;
  final EmailLogModel? sentLog;
  final VoidCallback onEdit;
  final VoidCallback onPreview;
  final VoidCallback? onSendEmail;
  final VoidCallback onDelete;

  const _InvoiceCard({
    required this.voucher,
    this.sentLog,
    required this.onEdit,
    required this.onPreview,
    this.onSendEmail,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = voucher.status;
    final saved = status == VoucherStatus.saved;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Bill No, Date, Status Badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.billNo.isNotEmpty ? voucher.billNo : '—',
                        style: AppTextStyles.bodySemi.copyWith(
                          color: AppColors.indigo600,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        voucher.date,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: saved ? AppColors.emerald100 : AppColors.amber100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: saved ? AppColors.emerald700 : AppColors.amber700,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Voucher reference and department
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.title.isEmpty ? '(Untitled)' : voucher.title,
                        style: AppTextStyles.bodySemi.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Dept: ${voucher.deptCode}',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatCurrency(voucher.finalTotal),
                      style: AppTextStyles.bodySemi.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.indigo600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Created by: ${voucher.createdBy.isNotEmpty ? voucher.createdBy : '—'}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),

            if (sentLog != null) ...[
              Row(
                children: [
                  Icon(Icons.mark_email_read_outlined,
                      size: 14, color: AppColors.emerald700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Sent to ${sentLog!.recipientTo}'
                      '${sentLog!.sentAt != null ? " on ${_fmtSentDate(sentLog!.sentAt!)}" : ""}',
                      style: TextStyle(fontSize: 11.5, color: AppColors.emerald700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(
                  icon: Icons.edit_outlined,
                  label: 'Edit',
                  color: AppColors.indigo600,
                  onPressed: onEdit,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.visibility_outlined,
                  label: 'View',
                  color: AppColors.indigo600,
                  onPressed: onPreview,
                ),
                if (onSendEmail != null) ...[
                  const SizedBox(width: 8),
                  _ActionButton(
                    icon: Icons.send_outlined,
                    label: sentLog != null ? 'Resend' : 'Send',
                    color: AppColors.indigo600,
                    onPressed: onSendEmail!,
                  ),
                ],
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.delete_outline,
                  label: 'Delete',
                  color: Colors.red,
                  onPressed: onDelete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  static String _fmtSentDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso.split('T').first;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ── Reusable action button inside invoice cards ──────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
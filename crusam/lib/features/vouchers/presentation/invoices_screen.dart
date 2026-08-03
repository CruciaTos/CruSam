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

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – shared with SettingsScreen
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
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

  // Text styles
  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsBadge = TextStyle(
    fontFamily   : fxcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 11,
    letterSpacing: 2.0,
    color        : badgeFg,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    letterSpacing: 1.0,
    color        : inkLight,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,
    color        : inkMuted,
  );

  // Dimensions
  static const double radius   = 6.0;
  static const double cRadius  = 10.0;
  static const double padH     = 18.0;
  static const double padV     = 16.0;
}

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final vMaps = await DatabaseHelper.instance.getAllVouchers();
    final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
    if (cfgMap != null) _config = CompanyConfigModel.fromMap(cfgMap);
    final loaded = <VoucherModel>[];
    for (final v in vMaps) {
      final rowMaps = await DatabaseHelper.instance.getRowsByVoucherId(v['id'] as int);
      loaded.add(VoucherModel.fromDbMap(v, rowMaps.map(VoucherRowModel.fromDbMap).toList()));
    }
    final sentLogs = await DatabaseHelper.instance.getLatestSentEmailLogsByType('invoice');
    if (mounted) {
      setState(() {
        _vouchers = loaded;
        _sentLogs = sentLogs;
        _loading = false;
      });
    }
  }

  Future<void> _quickSendEmail(VoucherModel v) async {
    await SendInvoiceDialog.show(context, voucher: v, config: _config);
    if (!mounted) return;
    await _load();
  }

  Future<void> _deleteVoucher(VoucherModel v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Invoice'),
        content: Text('Delete "${v.title.isEmpty ? "(Untitled)" : v.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
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
        content: const Text('The Voucher Builder has unsaved work.\nLoading this invoice will replace it. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: _Tok.inkLight),
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

  Future<void> _exportList() async {
    final exportRows = _vouchers;
    if (_exporting || exportRows.isEmpty) {
      if (exportRows.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No invoices to export.')));
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
      final filename = 'invoice_list_${stamp.year}${_pad(stamp.month)}${_pad(stamp.day)}_${_pad(stamp.hour)}${_pad(stamp.minute)}.csv';
      final path = '${dir.path}${Platform.pathSeparator}$filename';
      await File(path).writeAsString(buf.toString(), flush: true);
      _openFile(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported: $filename'),
            action: SnackBarAction(label: 'Open Folder', onPressed: () => _openFolder(dir.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  static String _csvField(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) return '"${value.replaceAll('"', '""')}"';
    return value;
  }
  static String _pad(int n) => n.toString().padLeft(2, '0');
  static Future<Directory> _outputDir() async {
    final saved = ExportPreferencesNotifier.instance.pdfPath;
    if (saved.isNotEmpty) {
      final dir = Directory(saved);
      if (await dir.exists()) return dir;
    }
    final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';
    final dl = Directory(Platform.isWindows ? '$home\\Downloads' : '$home/Downloads');
    if (await dl.exists()) return dl;
    return getApplicationDocumentsDirectory();
  }
  static void _openFile(String path) {
    try {
      if (Platform.isWindows) Process.run('cmd', ['/c', 'start', '', path]);
      else if (Platform.isMacOS) Process.run('open', [path]);
      else if (Platform.isLinux) Process.run('xdg-open', [path]);
    } catch (_) {}
  }
  static void _openFolder(String folder) {
    try {
      if (Platform.isWindows) Process.run('explorer', [folder]);
      else if (Platform.isMacOS) Process.run('open', [folder]);
      else if (Platform.isLinux) Process.run('xdg-open', [folder]);
    } catch (_) {}
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Transparent background – the shell's dark surface shows through.
    // Only the header and invoice cards have solid white/alt backgrounds.
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _InvoicesHeader(exporting: _exporting, onExport: _exportList, hasData: _vouchers.isNotEmpty),

            const SizedBox(height: 16),

            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_vouchers.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: _Tok.inkMuted.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No invoices yet', style: _Tok.tsMeta.copyWith(fontSize: 16, color: _Tok.inkMuted, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      Text('Finalise a voucher to create one.', style: _Tok.tsMeta),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _vouchers.length,
                  itemBuilder: (context, index) {
                    final v = _vouchers[index];
                    return _InvoiceCard(
                      voucher: v,
                      sentLog: v.id != null ? _sentLogs[v.id] : null,
                      onEdit: () => _editVoucher(context, v),
                      onPreview: () {
                        final previewNotifier = VoucherNotifier()..current = v;
                        InvoicePreviewDialog.show(context, previewNotifier, _config, PreviewType.invoice);
                      },
                      onSendEmail: v.status == VoucherStatus.saved ? () => _quickSendEmail(v) : null,
                      onDelete: () => _deleteVoucher(v),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Header (has own background) ──────────────────────────────────────────────
class _InvoicesHeader extends StatelessWidget {
  final bool exporting;
  final VoidCallback onExport;
  final bool hasData;

  const _InvoicesHeader({required this.exporting, required this.onExport, required this.hasData});

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: _Tok.padH),
        decoration: BoxDecoration(
          color: _Tok.surfaceAlt,
          border: const Border(bottom: BorderSide(color: _Tok.divider)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(_Tok.cRadius),
            topRight: Radius.circular(_Tok.cRadius),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: _Tok.ink, borderRadius: BorderRadius.circular(4)),
              child: const Icon(Icons.receipt_long_outlined, color: Colors.white, size: 13),
            ),
            const SizedBox(width: 8),
            Text('INVOICES', style: _Tok.tsCardTitle),
            const Spacer(),
            if (hasData)
              OutlinedButton.icon(
                onPressed: exporting ? null : onExport,
                icon: exporting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _Tok.ink))
                    : const Icon(Icons.download_outlined, size: 16),
                label: Text(exporting ? 'Exporting…' : 'Export', style: _Tok.tsLabel.copyWith(color: _Tok.inkLight, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Tok.inkLight,
                  side: const BorderSide(color: _Tok.inkLight),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_Tok.radius)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
          ],
        ),
      );
}

// ── Invoice Card (has own solid white background) ─────────────────────────────
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _Tok.surface,   // solid white – this is the "invoice background"
        border: Border.all(color: _Tok.border),
        borderRadius: BorderRadius.circular(_Tok.cRadius),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 2)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(_Tok.padV),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Bill No, Date, Status badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.billNo.isNotEmpty ? voucher.billNo : '—',
                        style: _Tok.tsInput.copyWith(fontWeight: FontWeight.w700, color: _Tok.inkLight, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                      Text(voucher.date, style: _Tok.tsMeta),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: saved ? const Color(0xFFD1FAE5) : const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status.name.toUpperCase(),
                    style: _Tok.tsBadge.copyWith(
                      color: saved ? const Color(0xFF065F46) : const Color(0xFF92400E),
                      fontSize: 10,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Voucher title, dept, total
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        voucher.title.isEmpty ? '(Untitled)' : voucher.title,
                        style: _Tok.tsInput.copyWith(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text('Dept: ${voucher.deptCode}', style: _Tok.tsMeta),
                    ],
                  ),
                ),
                Text(
                  formatCurrency(voucher.finalTotal),
                  style: _Tok.tsInput.copyWith(fontWeight: FontWeight.w700, color: _Tok.inkLight, fontSize: 16),
                ),
              ],
            ),

            if (sentLog != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.mark_email_read_outlined, size: 14, color: const Color(0xFF065F46)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Sent to ${sentLog!.recipientTo}${sentLog!.sentAt != null ? " on ${_fmtSentDate(sentLog!.sentAt!)}" : ""}',
                      style: _Tok.tsMeta.copyWith(color: const Color(0xFF065F46)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ActionButton(icon: Icons.edit_outlined, label: 'Edit', color: _Tok.inkLight, onPressed: onEdit),
                const SizedBox(width: 8),
                _ActionButton(icon: Icons.visibility_outlined, label: 'View', color: _Tok.inkLight, onPressed: onPreview),
                if (onSendEmail != null) ...[
                  const SizedBox(width: 8),
                  _ActionButton(icon: Icons.send_outlined, label: sentLog != null ? 'Resend' : 'Send', color: _Tok.inkLight, onPressed: onSendEmail!),
                ],
                const SizedBox(width: 8),
                _ActionButton(icon: Icons.delete_outline, label: 'Delete', color: Colors.red.shade700, onPressed: onDelete),
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
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}

// ── Action Button (re‑themed) ────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({required this.icon, required this.label, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Text(label, style: _Tok.tsLabel.copyWith(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
            ],
          ),
        ),
      );
}
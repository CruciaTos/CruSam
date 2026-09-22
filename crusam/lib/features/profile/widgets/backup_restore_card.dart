// lib/features/profile/widgets/backup_restore_card.dart
//
// Local save-file backup & restore — with automatic cloud sync after import.
// Visual styling now matches the indigo theme used in the redesigned screens.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../data/db/backup_repository.dart';
import '../../../data/db/database_helper.dart';
import '../../master_data/notifiers/employee_notifier.dart';
import '../../vouchers/notifiers/voucher_notifier.dart';
import '../../../core/theme/ink_tokens.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – consistent with the indigo theme
// ════════════════════════════════════════════════════════════════════════════
typedef _Tok = InkTokens;

class BackupRestoreCard extends StatefulWidget {
  const BackupRestoreCard({super.key});

  @override
  State<BackupRestoreCard> createState() => _BackupRestoreCardState();
}

class _BackupRestoreCardState extends State<BackupRestoreCard> {
  bool _backingUp = false;
  bool _restoring = false;
  String? _lastBackupPath;
  String? _statusMessage;
  bool _statusIsError = false;

  // ── Backup ──────────────────────────────────────────────────────────────
  Future<void> _doBackup() async {
    setState(() {
      _backingUp = true;
      _statusMessage = null;
    });

    try {
      final data = await DatabaseHelper.instance.exportBackupData();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final bytes = utf8.encode(jsonStr);

      final now = DateTime.now();
      final stamp =
          '${now.year}${_p(now.month)}${_p(now.day)}_${_p(now.hour)}${_p(now.minute)}';
      final suggestedName = 'crusam_backup_$stamp.json';

      String? savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save CruSam Backup',
        fileName: suggestedName,
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (savePath != null) {
        final outFile = File(savePath);
        if (!outFile.existsSync() || outFile.lengthSync() == 0) {
          await outFile.writeAsBytes(bytes);
        }
        setState(() {
          _lastBackupPath = savePath;
          _statusMessage = 'Backup saved successfully.';
          _statusIsError = false;
        });
      } else {
        setState(() => _statusMessage = null);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Backup failed: $e';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  // ── Restore ─────────────────────────────────────────────────────────────
  Future<void> _doRestore() async {
    // Step 1: pick file
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open CruSam Backup',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Could not open file picker: $e';
        _statusIsError = true;
      });
      return;
    }

    if (result == null || result.files.isEmpty) return;

    final bytes = result.files.first.bytes;
    if (bytes == null || bytes.isEmpty) {
      setState(() {
        _statusMessage = 'Selected file is empty or unreadable.';
        _statusIsError = true;
      });
      return;
    }

    // Step 2: parse JSON
    Map<String, dynamic> backup;
    try {
      backup = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      setState(() {
        _statusMessage = 'File is not a valid CruSam backup.';
        _statusIsError = true;
      });
      return;
    }

    // Sanity check
    if (!backup.containsKey('meta') && !backup.containsKey('employees')) {
      setState(() {
        _statusMessage = 'File does not look like a CruSam backup.';
        _statusIsError = true;
      });
      return;
    }

    // Step 3: confirm
    final fileName = result.files.first.name;

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dc) => AlertDialog(
        title: const Text('Restore Backup?'),
        content: Text(
          'Restoring "$fileName" will merge all records from the backup into '
          'the current database.\n\n'
          'Existing records with the same ID will be updated. '
          'New records will be added. Nothing will be deleted.\n\n'
          'Proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dc, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Step 4: import into SQLite
    setState(() {
      _restoring = true;
      _statusMessage = null;
    });

    Map<String, int>? summary;
    try {
      summary = await DatabaseHelper.instance.importBackupData(backup);

      // Refresh UI notifiers immediately
      await EmployeeNotifier.instance.load();
      await VoucherNotifier.instance.loadDependencies();
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Restore failed: $e';
          _statusIsError = true;
          _restoring = false;
        });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _restoring = false);

    setState(() {
      _statusMessage =
          'Restore complete — ${summary!['employees']} employees, '
          '${summary['vouchers']} invoices, '
          '${summary['voucher_rows']} invoice rows restored.';
      _statusIsError = false;
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String _p(int n) => n.toString().padLeft(2, '0');
  bool get _busy => _backingUp || _restoring;

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Outer card styled exactly like the other themed cards (white bg, indigo border, shadow)
    return Container(
      decoration: BoxDecoration(
        color: _Tok.surface,
        border: Border.all(color: _Tok.border),
        borderRadius: BorderRadius.circular(_Tok.cRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar (icon chip + title) ──────────────────────────────
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
                  child: const Icon(Icons.save_outlined, size: 12, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text('BACKUP & RESTORE', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
              ],
            ),
          ),

          // ── Card body ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(_Tok.padV),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description text
                Text(
                  'Save all data to a file on disk, or load a saved file back in.',
                  style: _Tok.tsSmall,
                ),

                const SizedBox(height: 16),

                // Backup action row
                _ActionRow(
                  icon: Icons.download_outlined,
                  iconColor: _Tok.inkLight,
                  iconBg: _Tok.surfaceAlt,
                  title: 'Save Backup',
                  subtitle: 'Exports employees, invoices and settings to a .json file.',
                  buttonLabel: _backingUp ? 'Saving…' : 'Save Now',
                  busy: _backingUp,
                  disabled: _busy,
                  onTap: _doBackup,
                ),

                if (_lastBackupPath != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.check_circle_outline, size: 12, color: _Tok.inkLight),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _lastBackupPath!,
                        style: _Tok.tsSmall.copyWith(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ],

                const Divider(height: 28, color: _Tok.divider),

                // Restore action row
                _ActionRow(
                  icon: Icons.upload_outlined,
                  iconColor: const Color(0xFF065F46), // keep a green accent for restore
                  iconBg: const Color(0xFFECFDF5),
                  title: 'Load Backup',
                  subtitle: 'Pick a previously saved .json file and merge it back in.',
                  buttonLabel: _restoring ? 'Restoring…' : 'Load File',
                  busy: _restoring,
                  disabled: _busy,
                  onTap: _doRestore,
                ),

                // Status message (if any)
                if (_statusMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _statusIsError ? const Color(0xFFFEF2F2) : _Tok.surfaceAlt,
                      border: Border.all(
                        color: _statusIsError ? const Color(0xFFFECACA) : _Tok.border,
                      ),
                      borderRadius: BorderRadius.circular(_Tok.radius),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                            _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
                            size: 15,
                            color: _statusIsError ? const Color(0xFFDC2626) : _Tok.inkLight,
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: _Tok.tsSmall.copyWith(
                              color: _statusIsError ? const Color(0xFFDC2626) : _Tok.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                            onTap: () => setState(() => _statusMessage = null),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: _statusIsError ? const Color(0xFFDC2626) : _Tok.inkLight,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── _ActionRow (themed for Backup & Restore) ──────────────────────────────────
class _ActionRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool busy;
  final bool disabled;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.busy,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: _Tok.tsSmall),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 34,
          child: ElevatedButton(
            onPressed: disabled ? null : onTap,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              backgroundColor: _Tok.ink,
              foregroundColor: Colors.white,
              textStyle: _Tok.tsLabel.copyWith(fontWeight: FontWeight.w600, fontSize: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_Tok.radius),
              ),
              elevation: 0,
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(buttonLabel),
          ),
        ),
      ],
    );
  }
}
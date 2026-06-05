// lib/features/profile/widgets/backup_restore_card.dart
//
// Local save-file backup & restore — with automatic cloud sync after import.
//
// Backup  → exports employees, vouchers, voucher_rows, company_config and
//           item_descriptions as a single JSON file the user saves to disk.
//
// Restore → user picks a previously-saved .json backup; the app upserts all
//           rows back into SQLite, then:
//             1. Refreshes EmployeeNotifier / VoucherNotifier so the UI
//                updates immediately.
//             2. If Google Drive is connected, calls
//                SyncManager.pushAllToCloud() so the imported data becomes
//                the new cloud source-of-truth.

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../core/sync/drive_service.dart';
import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/db/backup_repository.dart';
import '../../../data/db/database_helper.dart';
import '../../master_data/notifiers/employee_notifier.dart';
import '../../vouchers/notifiers/voucher_notifier.dart';

class BackupRestoreCard extends StatefulWidget {
  const BackupRestoreCard({super.key});

  @override
  State<BackupRestoreCard> createState() => _BackupRestoreCardState();
}

class _BackupRestoreCardState extends State<BackupRestoreCard> {
  bool _backingUp = false;
  bool _restoring = false;
  bool _cloudSyncing = false;
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
    final isGoogleConnected = GoogleAuthService.instance.isSignedIn;

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
          '${isGoogleConnected ? '☁️  After import, all data will be automatically uploaded to Google Drive so it becomes the new cloud source-of-truth.\n\n' : ''}'
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

    // Step 5: push imported data to Google Drive (if connected)
    if (isGoogleConnected) {
      setState(() {
        _cloudSyncing = true;
        _statusMessage =
            'Import complete — uploading to Google Drive…';
        _statusIsError = false;
      });

      final syncResult =
          await SyncManager.instance.pushAllToCloud();

      if (!mounted) return;
      setState(() {
        _cloudSyncing = false;
        if (syncResult.success) {
          _statusMessage =
              'Restore & cloud sync complete — '
              '${summary!['employees']} employees, '
              '${summary['vouchers']} invoices imported and uploaded to Drive.';
          _statusIsError = false;
        } else {
          _statusMessage =
              'Data restored locally, but cloud upload failed: '
              '${syncResult.errorMessage}. '
              'It will retry on the next app launch.';
          _statusIsError = true;
        }
      });
    } else {
      // Not connected to Google Drive — local-only restore
      setState(() {
        _statusMessage =
            'Restore complete — ${summary!['employees']} employees, '
            '${summary['vouchers']} invoices, '
            '${summary['voucher_rows']} invoice rows restored. '
            '(Connect Google Drive in settings to sync to the cloud.)';
        _statusIsError = false;
      });
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _p(int n) => n.toString().padLeft(2, '0');

  bool get _busy => _backingUp || _restoring || _cloudSyncing;

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.save_outlined,
                size: 18, color: AppColors.slate500),
            const SizedBox(width: 8),
            Text('Local Backup & Restore', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 4),
          ListenableBuilder(
            listenable: GoogleAuthService.instance,
            builder: (ctx, _) {
              final connected = GoogleAuthService.instance.isSignedIn;
              return Text(
                connected
                    ? 'Save all data to a file on disk, or load a saved file '
                        'back in. Imported data is automatically synced to '
                        'Google Drive.'
                    : 'Save all data to a file on disk, or load a saved file '
                        'back in. Connect Google Drive to enable automatic '
                        'cloud sync after import.',
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate500),
              );
            },
          ),

          const SizedBox(height: 20),

          // ── Backup row ────────────────────────────────────────────────────
          _ActionRow(
            icon: Icons.download_outlined,
            iconColor: AppColors.indigo600,
            iconBg: AppColors.indigo50,
            title: 'Save Backup',
            subtitle:
                'Exports employees, invoices and settings to a .json file.',
            buttonLabel: _backingUp ? 'Saving…' : 'Save Now',
            busy: _backingUp,
            disabled: _busy,
            onTap: _doBackup,
          ),

          if (_lastBackupPath != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.check_circle_outline,
                  size: 12, color: AppColors.emerald600),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _lastBackupPath!,
                  style: AppTextStyles.small.copyWith(
                    fontSize: 11,
                    color: AppColors.slate500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ],

          const Divider(height: 28),

          // ── Restore row ───────────────────────────────────────────────────
          _ActionRow(
            icon: Icons.upload_outlined,
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFECFDF5),
            title: 'Load Backup',
            subtitle:
                'Pick a previously saved .json file and merge it back in.',
            buttonLabel: _restoring
                ? 'Restoring…'
                : _cloudSyncing
                    ? 'Syncing to Drive…'
                    : 'Load File',
            busy: _restoring || _cloudSyncing,
            disabled: _busy,
            onTap: _doRestore,
          ),

          // ── Status message ────────────────────────────────────────────────
          if (_statusMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _statusIsError
                    ? const Color(0xFFFEF2F2)
                    : AppColors.emerald50,
                border: Border.all(
                  color: _statusIsError
                      ? const Color(0xFFFECACA)
                      : AppColors.emerald100,
                ),
                borderRadius:
                    BorderRadius.circular(AppSpacing.radius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Spinner while cloud syncing, icon otherwise
                  if (_cloudSyncing)
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.indigo600),
                    )
                  else
                    Icon(
                      _statusIsError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 15,
                      color: _statusIsError
                          ? const Color(0xFFDC2626)
                          : AppColors.emerald700,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: AppTextStyles.small.copyWith(
                        color: _statusIsError
                            ? const Color(0xFFDC2626)
                            : _cloudSyncing
                                ? AppColors.indigo600
                                : AppColors.emerald700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (!_cloudSyncing)
                    GestureDetector(
                      onTap: () =>
                          setState(() => _statusMessage = null),
                      child: Icon(Icons.close,
                          size: 14,
                          color: _statusIsError
                              ? const Color(0xFFDC2626)
                              : AppColors.emerald700),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── _ActionRow ────────────────────────────────────────────────────────────────

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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodyMedium),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate500, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          height: 36,
          child: ElevatedButton(
            onPressed: disabled ? null : onTap,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(fontSize: 13),
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
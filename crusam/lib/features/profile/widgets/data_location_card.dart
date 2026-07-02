// lib/features/profile/widgets/data_location_card.dart
//
// Shows the ACTUAL, live, on-disk location of CruSam's local data (SQLite
// database + AI semantic index) directly in the Profile screen, instead of
// the old static "Local SQLite (per Windows user)" placeholder text.
//
// Purely diagnostic / read-only. Does not move, migrate, or touch anything
// on disk — it only reports what AppPaths.resolveStorageInfo() finds.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

class DataLocationCard extends StatefulWidget {
  const DataLocationCard({super.key});

  @override
  State<DataLocationCard> createState() => _DataLocationCardState();
}

class _DataLocationCardState extends State<DataLocationCard> {
  AppStorageInfo? _info;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final info = await AppPaths.resolveStorageInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openFolder(String path) async {
    if (!Platform.isWindows) return;
    try {
      // explorer.exe returns a non-zero exit code even on success in some
      // cases, so we don't check the result — just fire and forget.
      await Process.run('explorer.exe', [path]);
    } catch (_) {
      // Folder may not exist yet on a completely fresh install; non-fatal.
    }
  }

  Future<void> _copy(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

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
          Row(children: [
            const Icon(Icons.dns_outlined, size: 18, color: AppColors.slate500),
            const SizedBox(width: 8),
            Text('Data Storage Location', style: AppTextStyles.h4),
          ]),
          const SizedBox(height: 4),
          Text(
            'Exact on-disk location of your employees, vouchers, salary '
            'records and AI index — read live from this PC, right now.',
            style: AppTextStyles.small.copyWith(color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (_error != null)
            _errorBox(_error!)
          else if (_info != null)
            ..._buildContent(_info!),
        ],
      ),
    );
  }

  List<Widget> _buildContent(AppStorageInfo info) => [
        _pathBlock(
          icon: Icons.folder_outlined,
          iconColor: AppColors.indigo600,
          label: 'Database folder',
          path: info.databaseDirectory,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Platform.isWindows)
                _iconButton(
                  Icons.folder_open_outlined,
                  'Open folder',
                  () => _openFolder(info.databaseDirectory),
                ),
              _iconButton(
                Icons.copy_outlined,
                'Copy path',
                () => _copy(info.databaseDirectory, 'Folder path'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _fileRow(
          icon: Icons.storage_outlined,
          iconColor: const Color(0xFF2563EB),
          label: 'Main database (aarti.db)',
          file: info.database,
        ),
        const SizedBox(height: 10),
        _fileRow(
          icon: Icons.auto_awesome_outlined,
          iconColor: const Color(0xFF059669),
          label: 'AI semantic index (semantic_index.db)',
          file: info.semanticIndex,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 14),
        _pathBlock(
          icon: Icons.apps_outlined,
          iconColor: AppColors.slate400,
          label: 'Application program folder (not your data)',
          path: info.executableDirectory,
          trailing: _iconButton(
            Icons.copy_outlined,
            'Copy path',
            () => _copy(info.executableDirectory, 'Program folder path'),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _copy(info.toDiagnosticText(), 'Diagnostic info'),
            icon: const Icon(Icons.bug_report_outlined, size: 15),
            label:
                const Text('Copy diagnostic info', style: TextStyle(fontSize: 13)),
          ),
        ),
      ];

  Widget _pathBlock({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String path,
    required Widget trailing,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.small.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.slate700,
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(path, style: AppTextStyles.monoSm),
              ),
              trailing,
            ],
          ),
        ],
      );

  Widget _fileRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required AppFileInfo file,
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.small.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.slate700,
                  ),
                ),
                const SizedBox(height: 2),
                // ---------- THE ACTUAL FULL PATH ----------
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        file.path,
                        style: AppTextStyles.monoSm,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _copy(file.path, 'File path'),
                      child: Icon(Icons.copy, size: 12, color: AppColors.slate400),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  file.exists
                      ? '${file.sizeLabel} · updated ${_formatDate(file.lastModified)}'
                      : 'Not created yet',
                  style: AppTextStyles.small
                      .copyWith(fontSize: 11, color: AppColors.slate400),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: file.exists ? AppColors.emerald50 : AppColors.slate100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: file.exists ? AppColors.emerald100 : AppColors.slate200,
              ),
            ),
            child: Text(
              file.exists ? 'Found' : 'Missing',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: file.exists ? AppColors.emerald700 : AppColors.slate500,
              ),
            ),
          ),
        ],
      );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed) =>
      Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 16, color: AppColors.slate500),
          onPressed: onPressed,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(),
          splashRadius: 16,
        ),
      );

  Widget _errorBox(String message) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          border: Border.all(color: const Color(0xFFFECACA)),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 15, color: Color(0xFFDC2626)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ),
        ]),
      );

  String _formatDate(DateTime? d) {
    if (d == null) return '—';
    final local = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
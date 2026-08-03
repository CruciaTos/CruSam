// lib/features/profile/widgets/data_location_card.dart
//
// Shows the ACTUAL, live, on-disk location of CruSam's local data (SQLite
// database + AI semantic index) directly in the Profile screen.
// Visual styling now matches the indigo theme used across the app.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/storage/app_paths.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens – consistent with the indigo theme
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  static const ink        = Color(0xFF1E1B4B);
  static const inkLight   = Color(0xFF3730A3);
  static const inkMuted   = Color(0xFF818CF8);
  static const border     = Color(0xFFC7D2FE);
  static const divider    = Color(0xFFE0E7FF);
  static const surface    = Color(0xFFFFFFFF);
  static const surfaceAlt = Color(0xFFEEF2FF);

  static const fbody = 'NotoSans';
  static const fcond = 'NotoSansCondensed';

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

  static const tsMono = TextStyle(
    fontFamily: 'RobotoMono', // monospace font — keep as-is or replace if you have one
    fontWeight: FontWeight.w400,
    fontSize  : 12,
    color     : ink,
  );

  static const double radius  = 6.0;
  static const double cRadius = 10.0;
  static const double padH    = 18.0;
  static const double padV    = 16.0;
}

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
      await Process.run('explorer.exe', [path]);
    } catch (_) {}
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
    // Themed card wrapper — same style as the other profile cards
    return Container(
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
                  child: const Icon(Icons.dns_outlined, size: 12, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Text('DATA STORAGE', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
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
                  'Exact on-disk location of your employees, vouchers, salary '
                  'records and AI index — read live from this PC, right now.',
                  style: _Tok.tsSmall,
                ),
                const SizedBox(height: 16),
                if (_loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_error != null)
                  _errorBox(_error!)
                else if (_info != null)
                  ..._buildContent(_info!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(AppStorageInfo info) => [
        _pathBlock(
          icon: Icons.folder_outlined,
          iconColor: _Tok.inkLight,
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
          iconColor: _Tok.inkLight,
          label: 'Main database (aarti.db)',
          file: info.database,
        ),
        const SizedBox(height: 10),
        _fileRow(
          icon: Icons.auto_awesome_outlined,
          iconColor: const Color(0xFF065F46), // keep a green accent for AI
          label: 'AI semantic index (semantic_index.db)',
          file: info.semanticIndex,
        ),
        const SizedBox(height: 16),
        const Divider(height: 1, color: _Tok.divider),
        const SizedBox(height: 14),
        _pathBlock(
          icon: Icons.apps_outlined,
          iconColor: _Tok.inkMuted,
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
            icon: const Icon(Icons.bug_report_outlined, size: 15, color: _Tok.inkLight),
            label: Text('Copy diagnostic info', style: _Tok.tsLabel.copyWith(fontSize: 12)),
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
              style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600),
            ),
          ]),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(path, style: _Tok.tsMono),
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
                  style: _Tok.tsBody.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                // ── Full file path ─────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        file.path,
                        style: _Tok.tsMono,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _copy(file.path, 'File path'),
                      child: const Icon(Icons.copy, size: 12, color: _Tok.inkMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  file.exists
                      ? '${file.sizeLabel} · updated ${_formatDate(file.lastModified)}'
                      : 'Not created yet',
                  style: _Tok.tsSmall.copyWith(fontSize: 10, color: _Tok.inkMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: file.exists ? const Color(0xFFD1FAE5) : _Tok.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: file.exists ? const Color(0xFFA7F3D0) : _Tok.border,
              ),
            ),
            child: Text(
              file.exists ? 'Found' : 'Missing',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: file.exists ? const Color(0xFF065F46) : _Tok.inkMuted,
              ),
            ),
          ),
        ],
      );

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onPressed) =>
      Tooltip(
        message: tooltip,
        child: IconButton(
          icon: Icon(icon, size: 16, color: _Tok.inkLight),
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
          borderRadius: BorderRadius.circular(_Tok.radius),
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
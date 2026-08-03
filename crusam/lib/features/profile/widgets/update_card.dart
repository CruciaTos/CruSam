// lib/features/profile/widgets/update_card.dart

import 'package:flutter/material.dart';

import '../../../core/updater/update_dialog.dart';
import '../../../core/updater/update_notifier.dart';
import '../../../core/updater/update_service.dart';
import '../../../core/updater/version_constants.dart';

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

  static const double radius  = 6.0;
  static const double cRadius = 10.0;
  static const double padH    = 18.0;
  static const double padV    = 16.0;
}

class UpdateCard extends StatefulWidget {
  const UpdateCard({super.key});

  @override
  State<UpdateCard> createState() => _UpdateCardState();
}

class _UpdateCardState extends State<UpdateCard> {
  String _currentVersion = '...';

  @override
  void initState() {
    super.initState();
    _fetchCurrentVersion();
  }

  Future<void> _fetchCurrentVersion() async {
    try {
      final version = await UpdateService.getCurrentVersion();
      if (mounted) {
        setState(() => _currentVersion = version);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateNotifier.instance,
      builder: (ctx, _) {
        final notifier = UpdateNotifier.instance;
        final info = notifier.info;
        final hasUpdate = notifier.hasUpdate;
        final isBusy = notifier.isBusy;

        final displayVersion = info?.currentVersion ?? _currentVersion;

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
                      child: const Icon(Icons.system_update_outlined,
                          size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Text('APP VERSION', style: _Tok.tsCardTitle.copyWith(fontSize: 12)),
                  ],
                ),
              ),

              // Body
              Padding(
                padding: const EdgeInsets.all(_Tok.padV),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Version info rows
                    _InfoRow(
                      icon: Icons.tag_outlined,
                      label: 'Current version',
                      value: 'v$displayVersion',
                    ),
                    if (info != null)
                      _InfoRow(
                        icon: Icons.cloud_outlined,
                        label: 'Latest version',
                        value: 'v${info.latestVersion}',
                        valueColor:
                            hasUpdate ? const Color(0xFF065F46) : _Tok.ink,
                      ),
                    const SizedBox(height: 12),

                    // Status badge
                    _StatusBadge(notifier: notifier),

                    // Error message
                    if (notifier.state == UpdateState.error &&
                        notifier.errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          borderRadius: BorderRadius.circular(_Tok.radius),
                        ),
                        child: Text(
                          notifier.errorMessage!,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFDC2626)),
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: isBusy
                                ? null
                                : () async {
                                    await notifier.checkForUpdate();
                                    if (mounted && notifier.info != null) {
                                      setState(() {
                                        _currentVersion =
                                            notifier.info!.currentVersion;
                                      });
                                    }
                                  },
                            icon: isBusy &&
                                    notifier.state == UpdateState.checking
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh, size: 15),
                            label: const Text('Check'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _Tok.inkLight,
                              side: const BorderSide(color: _Tok.inkLight),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(_Tok.radius),
                              ),
                              textStyle: _Tok.tsLabel.copyWith(fontSize: 12),
                            ),
                          ),
                        ),
                        if (hasUpdate) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed:
                                  isBusy ? null : () => UpdateDialog.show(ctx),
                              icon: const Icon(Icons.download_outlined,
                                  size: 15),
                              label: const Text('Update Now'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _Tok.ink,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(_Tok.radius),
                                ),
                                elevation: 0,
                                textStyle: _Tok.tsLabel.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Reusable info row (themed) ───────────────────────────────────────────────
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: _Tok.inkMuted),
            const SizedBox(width: 8),
            Text('$label:', style: _Tok.tsSmall),
            const SizedBox(width: 6),
            Text(
              value,
              style: _Tok.tsBody.copyWith(
                color: valueColor ?? _Tok.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

// ── Status badge (themed colours) ────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.notifier});

  final UpdateNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final hasUpdate = notifier.hasUpdate;
    final state = notifier.state;
    final info = notifier.info;

    if (state == UpdateState.checking) {
      return _badge(
        Icons.sync_outlined,
        'Checking for updates…',
        _Tok.surfaceAlt,
        _Tok.inkLight,
      );
    }

    if (state == UpdateState.downloading) {
      return _badge(
        Icons.download_outlined,
        'Downloading ${(notifier.downloadProgress * 100).toStringAsFixed(0)}%…',
        _Tok.surfaceAlt,
        _Tok.inkLight,
      );
    }

    if (state == UpdateState.launching) {
      return _badge(
        Icons.launch_outlined,
        'Launching updater…',
        _Tok.surfaceAlt,
        _Tok.inkLight,
      );
    }

    if (hasUpdate) {
      return _badge(
        Icons.new_releases_outlined,
        'Update available: v${info!.latestVersion}',
        const Color(0xFFFEF3C7), // amber-100
        const Color(0xFF92400E), // amber-700
      );
    }

    if (info != null && !hasUpdate) {
      return _badge(
        Icons.check_circle_outline,
        'App is up to date',
        const Color(0xFFD1FAE5), // emerald-100
        const Color(0xFF065F46), // emerald-700
      );
    }

    return _badge(
      Icons.info_outline,
      'Tap "Check" to look for updates',
      _Tok.surfaceAlt,
      _Tok.inkMuted,
    );
  }

  Widget _badge(IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(_Tok.radius),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: _Tok.tsSmall.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}
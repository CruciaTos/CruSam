// lib/features/profile/widgets/update_card.dart

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/update/update_dialog.dart';
import '../../../core/update/update_notifier.dart';
import '../../../core/update/version_constants.dart';

class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateNotifier.instance,
      builder: (ctx, _) {
        final notifier = UpdateNotifier.instance;
        final info = notifier.info;
        final hasUpdate = notifier.hasUpdate;
        final isBusy = notifier.isBusy;

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
              Row(
                children: [
                  const Icon(
                    Icons.system_update_outlined,
                    size: 18,
                    color: AppColors.slate500,
                  ),
                  const SizedBox(width: 8),
                  Text('App Version', style: AppTextStyles.h4),
                ],
              ),
              const SizedBox(height: 16),
              _infoRow(
                Icons.tag_outlined,
                'Current version',
                'v$kAppVersion',
              ),
              if (info != null)
                _infoRow(
                  Icons.cloud_outlined,
                  'Latest version',
                  'v${info.latestVersion}',
                  valueColor:
                      hasUpdate ? AppColors.emerald700 : AppColors.slate700,
                ),
              const SizedBox(height: 12),
              _StatusBadge(notifier: notifier),
              if (notifier.state == UpdateState.error &&
                  notifier.errorMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    border: Border.all(color: const Color(0xFFFECACA)),
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                  ),
                  child: Text(
                    notifier.errorMessage!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: isBusy
                          ? null
                          : () async {
                              await notifier.checkForUpdate();
                            },
                      icon: isBusy && notifier.state == UpdateState.checking
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 15),
                      label: const Text('Check'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  if (hasUpdate) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isBusy ? null : () => UpdateDialog.show(ctx),
                        icon: const Icon(Icons.download_outlined, size: 15),
                        label: const Text('Update Now'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          textStyle: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 14, color: AppColors.slate400),
            const SizedBox(width: 8),
            Text(
              '$label:',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
            const SizedBox(width: 6),
            Text(
              value,
              style: AppTextStyles.small.copyWith(
                color: valueColor ?? AppColors.slate700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

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
        const Color(0xFFF0F9FF),
        AppColors.blue600,
      );
    }

    if (state == UpdateState.downloading) {
      return _badge(
        Icons.download_outlined,
        'Downloading ${(notifier.downloadProgress * 100).toStringAsFixed(0)}%…',
        const Color(0xFFF0F9FF),
        AppColors.blue600,
      );
    }

    if (state == UpdateState.launching) {
      return _badge(
        Icons.launch_outlined,
        'Launching updater…',
        const Color(0xFFF0F9FF),
        AppColors.blue600,
      );
    }

    if (hasUpdate) {
      return _badge(
        Icons.new_releases_outlined,
        'Update available: v${info!.latestVersion}',
        AppColors.amber100,
        AppColors.amber700,
      );
    }

    if (info != null && !hasUpdate) {
      return _badge(
        Icons.check_circle_outline,
        'App is up to date',
        AppColors.emerald50,
        AppColors.emerald700,
      );
    }

    return _badge(
      Icons.info_outline,
      'Tap "Check" to look for updates',
      AppColors.slate100,
      AppColors.slate500,
    );
  }

  Widget _badge(IconData icon, String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.small.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
}
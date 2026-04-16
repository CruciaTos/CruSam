// lib/core/update/update_dialog.dart

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'update_notifier.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const UpdateDialog(),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UpdateNotifier.instance,
      builder: (dialogContext, child) {
        final notifier = UpdateNotifier.instance;
        final info = notifier.info;

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          ),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppSpacing.radiusLg),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.indigo600.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radius),
                            ),
                            child: const Icon(
                              Icons.system_update_outlined,
                              color: AppColors.indigo400,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Update Available',
                            style:
                                AppTextStyles.h4.copyWith(color: Colors.white),
                          ),
                        ],
                      ),
                      if (info != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _VersionBadge(
                              label: 'Current',
                              version: info.currentVersion,
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: AppColors.slate500,
                              ),
                            ),
                            _VersionBadge(
                              label: 'New',
                              version: info.latestVersion,
                              highlight: true,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (info != null)
                        Text(
                          info.message,
                          style: AppTextStyles.body
                              .copyWith(color: AppColors.slate600),
                        ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.emerald50,
                          border: Border.all(color: AppColors.emerald100),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radius),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.shield_outlined,
                              size: 15,
                              color: AppColors.emerald600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'All your data, invoices and settings are kept safe.',
                                style: AppTextStyles.small.copyWith(
                                  color: AppColors.emerald700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (notifier.state == UpdateState.error &&
                          notifier.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            border: Border.all(
                              color: const Color(0xFFFECACA),
                            ),
                            borderRadius:
                                BorderRadius.circular(AppSpacing.radius),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: Color(0xFFDC2626),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  notifier.errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFFDC2626),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (notifier.state == UpdateState.downloading) ...[
                        const SizedBox(height: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Downloading…', style: AppTextStyles.small),
                                Text(
                                  '${(notifier.downloadProgress * 100).toStringAsFixed(0)}%',
                                  style: AppTextStyles.small.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: notifier.downloadProgress,
                                minHeight: 6,
                                backgroundColor: AppColors.slate200,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                  AppColors.indigo600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (notifier.state == UpdateState.launching) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.indigo600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Launching updater…',
                              style: AppTextStyles.small,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          if (!(info?.force ?? false))
                            Expanded(
                              child: OutlinedButton(
                                onPressed: notifier.isBusy
                                    ? null
                                    : () => Navigator.pop(context),
                                child: const Text('Later'),
                              ),
                            ),
                          if (!(info?.force ?? false))
                            const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: notifier.isBusy
                                  ? null
                                  : () {
                                      notifier.clearError();
                                      notifier.downloadAndInstall();
                                    },
                              icon: notifier.isBusy
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.download_outlined,
                                      size: 16,
                                    ),
                              label: Text(
                                notifier.isBusy ? 'Updating…' : 'Update Now',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VersionBadge extends StatelessWidget {
  const _VersionBadge({
    required this.label,
    required this.version,
    this.highlight = false,
  });

  final String label;
  final String version;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: highlight
              ? AppColors.indigo600.withValues(alpha: 0.15)
              : AppColors.slate800,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: highlight
                ? AppColors.indigo600.withValues(alpha: 0.4)
                : AppColors.slate700,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: AppTextStyles.small.copyWith(
                color: AppColors.slate400,
                fontSize: 10,
              ),
            ),
            Text(
              'v$version',
              style: AppTextStyles.bodyMedium.copyWith(
                color: highlight ? AppColors.indigo400 : AppColors.slate300,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
}
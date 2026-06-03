import 'package:flutter/material.dart';

import '../../../core/sync/google_auth_service.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

class GoogleDriveDebugScreen extends StatelessWidget {
  const GoogleDriveDebugScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive Debug'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListenableBuilder(
              listenable: GoogleAuthService.instance,
              builder: (context, child) {
                final service = GoogleAuthService.instance;
                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Google Drive Debug', style: AppTextStyles.h3),
                        const SizedBox(height: 16),
                        _debugLine('Signed in', service.isSignedIn ? 'Yes' : 'No'),
                        _debugLine('User email', service.userEmail ?? 'Not available'),
                        _debugLine('Access token expiry',
                            service.tokenExpiry?.toIso8601String() ?? 'Unknown'),
                        _debugLine('Refresh token available',
                            service.hasRefreshToken ? 'Yes' : 'No'),
                        _debugLine('Drive smoke test',
                            service.driveSmokeTestMessage ?? 'Not run yet'),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: service.isLoading ? null : () async {
                            await GoogleAuthService.instance.signIn();
                          },
                          child: const Text('Run Google Drive Sign-In'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _debugLine(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 180,
              child: Text('$label:', style: AppTextStyles.bodyMedium),
            ),
            Expanded(
              child: Text(value, style: AppTextStyles.bodyMedium),
            ),
          ],
        ),
      );
}

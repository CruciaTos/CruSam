// lib/core/update/update_model.dart

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
    required this.message,
    required this.force,
    required this.downloadUrl,
  });

  final String currentVersion;
  final String latestVersion;
  final bool updateAvailable;
  final String message;
  final bool force;
  final String downloadUrl;
}
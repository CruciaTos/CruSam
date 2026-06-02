// lib/core/sync/drive_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'google_auth_service.dart';

class DriveService {
  DriveService._();
  static final DriveService instance = DriveService._();

  static const _appFolderName = 'Crusam';
  String? _appFolderId;

  // ── Get or create the Crusam folder ──────────────────────────────────────
  Future<String?> getOrCreateAppFolder() async {
    if (_appFolderId != null) return _appFolderId;

    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final driveApi = drive.DriveApi(client);

      // Search for existing folder
      final result = await driveApi.files.list(
        q: "name='$_appFolderName' and "
           "mimeType='application/vnd.google-apps.folder' and "
           "trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        _appFolderId = result.files!.first.id;
        return _appFolderId;
      }

      // Create folder
      final folder = drive.File()
        ..name = _appFolderName
        ..mimeType = 'application/vnd.google-apps.folder';

      final created = await driveApi.files.create(folder);
      _appFolderId = created.id;
      return _appFolderId;
    } catch (e) {
      debugPrint('DriveService.getOrCreateAppFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── Upload JSON file ──────────────────────────────────────────────────────
  Future<String?> uploadJson({
    required String fileName,
    required Map<String, dynamic> data,
    String? parentFolderId,
    String? existingFileId,   // pass to update instead of create
  }) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final driveApi  = drive.DriveApi(client);
      final jsonBytes = utf8.encode(jsonEncode(data));
      final stream    = Stream.fromIterable([jsonBytes]);
      final media     = drive.Media(stream, jsonBytes.length,
          contentType: 'application/json');

      if (existingFileId != null) {
        // Update existing file
        final updated = await driveApi.files.update(
          drive.File()..name = fileName,
          existingFileId,
          uploadMedia: media,
        );
        return updated.id;
      }

      // Create new file
      final fileMetadata = drive.File()
        ..name    = fileName
        ..parents = parentFolderId != null ? [parentFolderId] : null;

      final created = await driveApi.files.create(
        fileMetadata,
        uploadMedia: media,
        $fields: 'id',
      );
      return created.id;
    } catch (e) {
      debugPrint('DriveService.uploadJson error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── Download JSON file ────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> downloadJson(String fileId) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final driveApi = drive.DriveApi(client);
      final media    = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DriveService.downloadJson error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── Delete file ───────────────────────────────────────────────────────────
  Future<bool> deleteFile(String fileId) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return false;

    try {
      final driveApi = drive.DriveApi(client);
      await driveApi.files.delete(fileId);
      return true;
    } catch (e) {
      debugPrint('DriveService.deleteFile error: $e');
      return false;
    } finally {
      client.close();
    }
  }

  // ── Find file by name in folder ───────────────────────────────────────────
  Future<String?> findFileId(String fileName, String parentFolderId) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final driveApi = drive.DriveApi(client);
      final result   = await driveApi.files.list(
        q: "name='$fileName' and "
           "'$parentFolderId' in parents and "
           "trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      return result.files?.firstOrNull?.id;
    } catch (e) {
      debugPrint('DriveService.findFileId error: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
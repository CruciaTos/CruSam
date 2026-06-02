// lib/core/sync/drive_service.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../../data/db/database_helper.dart';
import 'sync_models.dart';
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

  Future<String?> ensureCrusamFolder() async {
    return getOrCreateAppFolder();
  }

  Future<String?> ensureEmployeesFolder() async {
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return null;

    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;

    try {
      final driveApi = drive.DriveApi(client);
      final result = await driveApi.files.list(
        q: "name='employees' and "
           "mimeType='application/vnd.google-apps.folder' and "
           "'$appFolderId' in parents and "
           "trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }

      final folder = drive.File()
        ..name = 'employees'
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [appFolderId];

      final created = await driveApi.files.create(folder, $fields: 'id');
      return created.id;
    } catch (e) {
      debugPrint('DriveService.ensureEmployeesFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<SyncIndex> readEmployeesIndex() async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) {
      return SyncIndex(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        entries: [],
      );
    }

    final indexFileId = await findFileId('index.json', folderId);
    if (indexFileId == null) {
      return SyncIndex(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        entries: [],
      );
    }

    final json = await downloadJson(indexFileId);
    if (json == null) {
      return SyncIndex(
        updatedAt: DateTime.now().toUtc().toIso8601String(),
        entries: [],
      );
    }

    return SyncIndex.fromJson(json);
  }

  Future<void> writeEmployeesIndex(SyncIndex index) async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) return;

    final existingFileId = await findFileId('index.json', folderId);
    await uploadJson(
      fileName: 'index.json',
      data: index.toJson(),
      parentFolderId: folderId,
      existingFileId: existingFileId,
    );
  }

  Future<String?> uploadEmployee(SyncEmployee employee) async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) return null;

    final fileName = '${employee.cloudId}.json';
    final existingFileId = await findFileId(fileName, folderId);
    return uploadJson(
      fileName: fileName,
      data: employee.toJson(),
      parentFolderId: folderId,
      existingFileId: existingFileId,
    );
  }

  Future<SyncEmployee?> downloadEmployee(String cloudId) async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) return null;

    final fileId = await findFileId('$cloudId.json', folderId);
    if (fileId == null) return null;

    final json = await downloadJson(fileId);
    if (json == null) return null;
    return SyncEmployee.fromJson(json);
  }
}

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  final _db = DatabaseHelper.instance;
  final _drive = DriveService.instance;

  Future<void> syncOnStartup() async {
    final folderId = await _drive.ensureEmployeesFolder();
    if (folderId == null) return;

    final index = await _drive.readEmployeesIndex();
    for (final entry in index.entries) {
      final cloudEmployee = await _drive.downloadEmployee(entry.cloudId);
      if (cloudEmployee == null) continue;
      await _db.upsertEmployeeFromCloud(cloudEmployee.toJson());
    }
  }

  Future<void> processPendingUploads() async {
    final pendingRows = await _db.getPendingSyncs();
    for (final row in pendingRows) {
      final entry = SyncPendingEntry.fromDbMap(row);
      if (entry.entityType != 'employee') continue;

      final syncEmployee = SyncEmployee.fromJson(entry.payload);
      final uploadedFileId = await _drive.uploadEmployee(syncEmployee);
      if (uploadedFileId == null) continue;

      final index = await _drive.readEmployeesIndex();
      final updatedEntries = [
        ...index.entries.where((e) => e.cloudId != syncEmployee.cloudId),
        SyncIndexEntry(
          cloudId: syncEmployee.cloudId,
          updatedAt: syncEmployee.updatedAt,
          isDeleted: syncEmployee.isDeleted,
        ),
      ];

      await _drive.writeEmployeesIndex(
        SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: updatedEntries,
        ),
      );

      if (entry.id != null) {
        await _db.removePendingSync(entry.id!);
      }
    }
  }
}

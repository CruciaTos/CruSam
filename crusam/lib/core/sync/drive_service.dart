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
  String? _vouchersFolderId;
  String? _settingsFolderId;
  String? _backupsFolderId;

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

  // ── Generic subfolder helper ──────────────────────────────────────────────
  Future<String?> _ensureSubfolder(String parentId, String name) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      final driveApi = drive.DriveApi(client);
      final result = await driveApi.files.list(
        q: "name='$name' and "
            "mimeType='application/vnd.google-apps.folder' and "
            "'$parentId' in parents and "
            "trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      if (result.files != null && result.files!.isNotEmpty) {
        return result.files!.first.id;
      }
      final folder = drive.File()
        ..name = name
        ..mimeType = 'application/vnd.google-apps.folder'
        ..parents = [parentId];
      final created = await driveApi.files.create(folder, $fields: 'id');
      return created.id;
    } catch (e) {
      debugPrint('DriveService._ensureSubfolder($name) error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── Vouchers folder ───────────────────────────────────────────────────────
  Future<String?> ensureVouchersFolder() async {
    if (_vouchersFolderId != null) return _vouchersFolderId;
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return null;
    _vouchersFolderId = await _ensureSubfolder(appFolderId, 'vouchers');
    return _vouchersFolderId;
  }

  // ── Settings folder ───────────────────────────────────────────────────────
  Future<String?> ensureSettingsFolder() async {
    if (_settingsFolderId != null) return _settingsFolderId;
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return null;
    _settingsFolderId = await _ensureSubfolder(appFolderId, 'settings');
    return _settingsFolderId;
  }

  // ── Backups folder ────────────────────────────────────────────────────────
  Future<String?> ensureBackupsFolder() async {
    if (_backupsFolderId != null) return _backupsFolderId;
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return null;
    _backupsFolderId = await _ensureSubfolder(appFolderId, 'backups');
    return _backupsFolderId;
  }

  // ── Metadata ──────────────────────────────────────────────────────────────
  Future<DriveMetadata> readMetadata() async {
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) {
      return DriveMetadata(updatedAt: DateTime.now().toUtc().toIso8601String());
    }
    final fileId = await findFileId('metadata.json', appFolderId);
    if (fileId == null) {
      return DriveMetadata(updatedAt: DateTime.now().toUtc().toIso8601String());
    }
    final json = await downloadJson(fileId);
    if (json == null) {
      return DriveMetadata(updatedAt: DateTime.now().toUtc().toIso8601String());
    }
    return DriveMetadata.fromJson(json);
  }

  Future<void> writeMetadata(DriveMetadata metadata) async {
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return;
    final existingFileId = await findFileId('metadata.json', appFolderId);
    await uploadJson(
      fileName: 'metadata.json',
      data: metadata.toJson(),
      parentFolderId: appFolderId,
      existingFileId: existingFileId,
    );
  }

  Future<void> _registerDevice() async {
    final now = DateTime.now().toUtc().toIso8601String();
    String deviceId = 'device_unknown';
    String deviceName = 'Windows PC';
    try {
      final host = Platform.localHostname;
      deviceId = 'device_${host.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      deviceName = host;
    } catch (_) {}

    final metadata = await readMetadata();
    final thisDevice = DriveDevice(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: Platform.operatingSystem,
      appVersion: '1.0.0',
      dbSchemaVersion: 5,
      lastSeen: now,
    );
    final updatedDevices = [
      ...metadata.devices.where((d) => d.deviceId != deviceId),
      thisDevice,
    ];
    await writeMetadata(metadata.copyWith(updatedAt: now, devices: updatedDevices));
  }

  // ── Voucher index ─────────────────────────────────────────────────────────
  Future<SyncIndex> readVouchersIndex() async {
    final folderId = await ensureVouchersFolder();
    if (folderId == null) {
      return SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(), entries: []);
    }
    final indexFileId = await findFileId('index.json', folderId);
    if (indexFileId == null) {
      return SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(), entries: []);
    }
    final json = await downloadJson(indexFileId);
    if (json == null) {
      return SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(), entries: []);
    }
    return SyncIndex.fromJson(json);
  }

  Future<void> writeVouchersIndex(SyncIndex index) async {
    final folderId = await ensureVouchersFolder();
    if (folderId == null) return;
    final existingFileId = await findFileId('index.json', folderId);
    await uploadJson(
      fileName: 'index.json',
      data: index.toJson(),
      parentFolderId: folderId,
      existingFileId: existingFileId,
    );
  }

  // ── Settings files ────────────────────────────────────────────────────────
  Future<void> writeCompanyConfig(Map<String, dynamic> config) async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return;
    final existingId = await findFileId('company_config.json', folderId);
    await uploadJson(
        fileName: 'company_config.json',
        data: config,
        parentFolderId: folderId,
        existingFileId: existingId);
  }

  Future<Map<String, dynamic>?> readCompanyConfig() async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return null;
    final fileId = await findFileId('company_config.json', folderId);
    if (fileId == null) return null;
    return downloadJson(fileId);
  }

  Future<void> writeMargins(Map<String, dynamic> margins) async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return;
    final existingId = await findFileId('margins.json', folderId);
    await uploadJson(
        fileName: 'margins.json',
        data: margins,
        parentFolderId: folderId,
        existingFileId: existingId);
  }

  Future<Map<String, dynamic>?> readMargins() async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return null;
    final fileId = await findFileId('margins.json', folderId);
    if (fileId == null) return null;
    return downloadJson(fileId);
  }

  Future<void> writeItemDescriptions(List<Map<String, dynamic>> descriptions) async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return;
    final existingId = await findFileId('item_descriptions.json', folderId);
    await uploadJson(
        fileName: 'item_descriptions.json',
        data: {'descriptions': descriptions},
        parentFolderId: folderId,
        existingFileId: existingId);
  }

  Future<List<Map<String, dynamic>>?> readItemDescriptions() async {
    final folderId = await ensureSettingsFolder();
    if (folderId == null) return null;
    final fileId = await findFileId('item_descriptions.json', folderId);
    if (fileId == null) return null;
    final json = await downloadJson(fileId);
    if (json == null) return null;
    final list = json['descriptions'] as List?;
    return list?.map((e) => e as Map<String, dynamic>).toList();
  }

  // ── Full structure bootstrap ──────────────────────────────────────────────
  Future<void> initializeDriveStructure() async {
    if (!GoogleAuthService.instance.isSignedIn) return;
    try {
      // 1. Ensure all top-level folders exist
      await ensureCrusamFolder();
      await ensureEmployeesFolder();
      await ensureVouchersFolder();
      await ensureSettingsFolder();
      await ensureBackupsFolder();

      // 2. Seed employees/index.json if this is a fresh folder
      final empFolderId = await ensureEmployeesFolder();
      if (empFolderId != null) {
        final empIndexId = await findFileId('index.json', empFolderId);
        if (empIndexId == null) {
          await writeEmployeesIndex(SyncIndex(
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: []));
        }
      }

      // 3. Seed vouchers/index.json if this is a fresh folder
      final vFolderId = await ensureVouchersFolder();
      if (vFolderId != null) {
        final vIndexId = await findFileId('index.json', vFolderId);
        if (vIndexId == null) {
          await writeVouchersIndex(SyncIndex(
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: []));
        }
      }

      // 4. Register / update this device in metadata.json
      await _registerDevice();

      debugPrint('DriveService.initializeDriveStructure: complete');
    } catch (e) {
      debugPrint('DriveService.initializeDriveStructure error: $e');
    }
  }
}

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  final _db = DatabaseHelper.instance;
  final _drive = DriveService.instance;

  Future<void> syncOnStartup() async {
    // Ensure the full folder structure exists before reading anything
    await _drive.initializeDriveStructure();

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

  // ── NEW: push local employee changes to the sync queue ──────────────────
  Future<void> pushEmployeeChange({
    required String cloudId,
    required String operation,        // 'create' | 'update' | 'delete'
    required Map<String, dynamic> employeeDbRow,
  }) async {
    final now = (employeeDbRow['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();

    final entry = SyncPendingEntry(
      entityType:     'employee',
      cloudId:        cloudId,
      operation:      operation,
      payload:        employeeDbRow,
      localUpdatedAt: now,
    );

    await _db.addPendingSync(entry);
    _processSilently();
  }

  // ── NEW: push local invoice/voucher changes to the sync queue ───────────
  Future<void> pushInvoiceChange({
    required String cloudId,
    required String operation,        // 'create' | 'update' | 'delete'
    required Map<String, dynamic> invoiceDbRow,
  }) async {
    final now = (invoiceDbRow['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();

    final entry = SyncPendingEntry(
      entityType:     'invoice',
      cloudId:        cloudId,
      operation:      operation,
      payload:        invoiceDbRow,
      localUpdatedAt: now,
    );

    await _db.addPendingSync(entry);
    _processSilently();
  }

  // ── NEW: public full-sync trigger (pull then push) ──────────────────────
  Future<void> syncNow() async {
    await syncOnStartup();
    await processPendingUploads();
  }

  // ── Internal helper: fire-and-forget push without crashing the caller ──
  void _processSilently() {
    processPendingUploads().catchError((e) {
      debugPrint('SyncManager._processSilently error: $e');
    });
  }
}
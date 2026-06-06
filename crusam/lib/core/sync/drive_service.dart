// lib/core/sync/drive_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// CHANGES FROM PREVIOUS VERSION
// ═══════════════════════════════════════════════════════════════════════════
//
// CRITICAL CHANGE: All Drive API calls now use the SERVICE ACCOUNT client
// instead of the signed-in user's OAuth client.
//
// Before:
//   _api() → GoogleAuthService.instance.getAuthenticatedClient()
//            → user's personal Drive
//            → user-specific Crusam/ folder
//
// After:
//   _api() → DriveServiceAccount.getServiceAccountClient()
//            → service account's Drive access
//            → ONE shared Crusam/ folder (kCrusamRootFolderId)
//
// The folder discovery logic (_findFolder, _ensureFolder) is also changed:
//
// Before:
//   ensureCrusamFolder() → search for "Crusam" by name in user's Drive
//                        → create it if not found
//
// After:
//   ensureCrusamFolder() → return ServiceAccountConfig.kCrusamRootFolderId
//                          directly (the folder already exists and is shared
//                          with the service account — no search, no creation)
//
// This eliminates the root cause: no per-user folder creation ever occurs.
//
// Sub-folders (employees/, vouchers/, settings/, backups/) are still
// auto-created as needed, but always as children of the fixed root folder
// and always via the service account client.
//
// Everything else (SyncManager, SyncResult, sync logic, index helpers,
// file upload/download) is UNCHANGED.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:uuid/uuid.dart';

import '../../data/db/database_helper.dart';
import 'sync_models.dart';
import 'google_auth_service.dart';
import 'service_account_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DriveService  —  raw Drive I/O through the service account
// ─────────────────────────────────────────────────────────────────────────────

class DriveService {
  DriveService._();
  static final DriveService instance = DriveService._();

  // Sub-folder names inside the shared Crusam root.
  static const _employeesFolderName = 'employees';
  static const _vouchersFolderName  = 'vouchers';
  static const _settingsFolderName  = 'settings';
  static const _backupsFolderName   = 'backups';

  // Cached sub-folder IDs (reset on sign-out via clearCache()).
  // NOTE: _appFolderId is no longer discovered — it is always the fixed
  // ServiceAccountConfig.kCrusamRootFolderId.
  String? _employeesFolderId;
  String? _vouchersFolderId;
  String? _settingsFolderId;
  String? _backupsFolderId;

  // ── Cache management ──────────────────────────────────────────────────────

  void clearCache() {
    _employeesFolderId = null;
    _vouchersFolderId  = null;
    _settingsFolderId  = null;
    _backupsFolderId   = null;
    DriveServiceAccount.clearCache();
    debugPrint('DriveService.clearCache: sub-folder ID cache cleared');
  }

  // ── Service account client helper ─────────────────────────────────────────

  // _readApi() uses the service account — for all reads (folder discovery,
  // findFileId, downloadJson). Works regardless of who is signed in.
  //
  // _writeApi() uses the signed-in user's OAuth token — for all writes
  // (uploadJson, _createFolder). Personal Google accounts don't give service
  // accounts storage quota, so uploads must come from the human user's token.
  // Both authorized users have Editor access on the shared Crusam folder, so
  // both can write there using their own tokens.

  Future<drive.DriveApi?> _readApi() async {
    final client = await DriveServiceAccount.getServiceAccountClient();
    if (client == null) {
      debugPrint('DriveService._readApi: service account client not available');
      return null;
    }
    return drive.DriveApi(client);
  }

  Future<drive.DriveApi?> _writeApi() async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) {
      debugPrint('DriveService._writeApi: user OAuth client not available');
      return null;
    }
    return drive.DriveApi(client);
  }

  // ── Folder helpers ────────────────────────────────────────────────────────

  Future<String?> _findFolder(
      drive.DriveApi api, String name, String parentId) async {
    final q = "name='$name' "
        "and mimeType='application/vnd.google-apps.folder' "
        "and '$parentId' in parents "
        "and trashed=false";
    final result = await api.files.list(
      q: q,
      spaces: 'drive',
      $fields: 'files(id,name)',
    );
    final found = result.files?.firstOrNull;
    if (found != null) {
      debugPrint(
        'DriveService._findFolder: found "$name" id=${found.id} '
        'under parent=$parentId',
      );
    }
    return found?.id;
  }

  Future<String?> _createFolder(
      drive.DriveApi api, String name, String parentId) async {
    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = [parentId];
    final created = await api.files.create(meta, $fields: 'id,name');
    debugPrint(
      'DriveService._createFolder: created "$name" id=${created.id} '
      'under parent=$parentId',
    );
    return created.id;
  }

  Future<String?> _ensureFolder(
      drive.DriveApi readApi, drive.DriveApi writeApi,
      String name, String parentId) async {
    return await _findFolder(readApi, name, parentId) ??
        await _createFolder(writeApi, name, parentId);
  }

  // ── Top-level folder getter (now a fixed constant) ─────────────────────────

  /// Returns the shared Crusam root folder ID directly from config.
  /// No search, no creation — the folder must already exist and be
  /// shared with the service account (see setup instructions in
  /// service_account_config.dart).
  Future<String?> ensureCrusamFolder() async {
    final id = ServiceAccountConfig.kCrusamRootFolderId;
    if (id.contains('PASTE_')) {
      debugPrint(
        'DriveService.ensureCrusamFolder: '
        'kCrusamRootFolderId has not been configured. '
        'Please fill in service_account_config.dart.',
      );
      return null;
    }
    debugPrint('DriveService.ensureCrusamFolder: using fixed root id=$id');
    return id;
  }

  // ── Sub-folder getters (cached, auto-created under the fixed root) ─────────

  Future<String?> ensureEmployeesFolder() async {
    if (_employeesFolderId != null) return _employeesFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final readApi = await _readApi();
    if (readApi == null) return null;
    final writeApi = await _writeApi();
    if (writeApi == null) return null;
    try {
      _employeesFolderId = await _ensureFolder(
          readApi, writeApi, _employeesFolderName, parent);
      debugPrint(
        'DriveService.ensureEmployeesFolder: id=$_employeesFolderId',
      );
      return _employeesFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureEmployeesFolder error: $e');
      return null;
    }
  }

  Future<String?> ensureVouchersFolder() async {
    if (_vouchersFolderId != null) return _vouchersFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final readApi = await _readApi();
    if (readApi == null) return null;
    final writeApi = await _writeApi();
    if (writeApi == null) return null;
    try {
      _vouchersFolderId = await _ensureFolder(
          readApi, writeApi, _vouchersFolderName, parent);
      debugPrint('DriveService.ensureVouchersFolder: id=$_vouchersFolderId');
      return _vouchersFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureVouchersFolder error: $e');
      return null;
    }
  }

  Future<String?> ensureSettingsFolder() async {
    if (_settingsFolderId != null) return _settingsFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final readApi = await _readApi();
    if (readApi == null) return null;
    final writeApi = await _writeApi();
    if (writeApi == null) return null;
    try {
      _settingsFolderId = await _ensureFolder(
          readApi, writeApi, _settingsFolderName, parent);
      debugPrint('DriveService.ensureSettingsFolder: id=$_settingsFolderId');
      return _settingsFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureSettingsFolder error: $e');
      return null;
    }
  }

  Future<String?> ensureBackupsFolder() async {
    if (_backupsFolderId != null) return _backupsFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final readApi = await _readApi();
    if (readApi == null) return null;
    final writeApi = await _writeApi();
    if (writeApi == null) return null;
    try {
      _backupsFolderId = await _ensureFolder(
          readApi, writeApi, _backupsFolderName, parent);
      debugPrint('DriveService.ensureBackupsFolder: id=$_backupsFolderId');
      return _backupsFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureBackupsFolder error: $e');
      return null;
    }
  }

  // ── File lookup ───────────────────────────────────────────────────────────

  Future<String?> findFileId(String fileName, String parentFolderId) async {
    final api = await _readApi();
    if (api == null) return null;
    try {
      final result = await api.files.list(
        q: "name='$fileName' "
            "and '$parentFolderId' in parents "
            "and trashed=false",
        spaces: 'drive',
        $fields: 'files(id,name)',
      );
      final id = result.files?.firstOrNull?.id;
      debugPrint(
        'DriveService.findFileId: "$fileName" in folder=$parentFolderId → ${id ?? "not found"}',
      );
      return id;
    } catch (e) {
      debugPrint('DriveService.findFileId("$fileName") error: $e');
      return null;
    }
  }

  // ── JSON upload / download ────────────────────────────────────────────────

  /// Uploads [data] as JSON via the service account.
  Future<String?> uploadJson({
    required String fileName,
    required Map<String, dynamic> data,
    String? parentFolderId,
    String? existingFileId,
  }) async {
    final api = await _writeApi();
    if (api == null) return null;
    try {
      final jsonBytes = utf8.encode(jsonEncode(data));
      final media = drive.Media(
        Stream.fromIterable([jsonBytes]),
        jsonBytes.length,
        contentType: 'application/json',
      );

      if (existingFileId != null) {
        final updated = await api.files.update(
          drive.File()..name = fileName,
          existingFileId,
          uploadMedia: media,
          $fields: 'id',
        );
        debugPrint(
          'DriveService.uploadJson: updated "$fileName" id=${updated.id}',
        );
        return updated.id;
      }

      final meta = drive.File()
        ..name = fileName
        ..parents = parentFolderId != null ? [parentFolderId] : null;
      final created = await api.files.create(
        meta,
        uploadMedia: media,
        $fields: 'id',
      );
      debugPrint(
        'DriveService.uploadJson: created "$fileName" id=${created.id} '
        'in folder=$parentFolderId',
      );
      return created.id;
    } catch (e) {
      debugPrint('DriveService.uploadJson("$fileName") error: $e');
      return null;
    }
  }

  /// Downloads the file with [fileId] and parses it as JSON.
  Future<Map<String, dynamic>?> downloadJson(String fileId) async {
    final api = await _readApi();
    if (api == null) return null;
    try {
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      debugPrint('DriveService.downloadJson: downloaded fileId=$fileId');
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DriveService.downloadJson(fileId=$fileId) error: $e');
      return null;
    }
  }

  // ── Index helpers ─────────────────────────────────────────────────────────

  Future<SyncIndex> _readIndex(String? folderId) async {
    final empty = SyncIndex(
        updatedAt: DateTime.now().toUtc().toIso8601String(), entries: []);
    if (folderId == null) return empty;
    final fileId = await findFileId('index.json', folderId);
    if (fileId == null) return empty;
    final json = await downloadJson(fileId);
    if (json == null) return empty;
    try {
      return SyncIndex.fromJson(json);
    } catch (e) {
      debugPrint('DriveService._readIndex parse error: $e');
      return empty;
    }
  }

  Future<void> _writeIndex(String? folderId, SyncIndex index) async {
    if (folderId == null) return;
    final existingId = await findFileId('index.json', folderId);
    await uploadJson(
      fileName: 'index.json',
      data: index.toJson(),
      parentFolderId: folderId,
      existingFileId: existingId,
    );
  }

  Future<SyncIndex> readEmployeesIndex() =>
      ensureEmployeesFolder().then((id) => _readIndex(id));

  Future<void> writeEmployeesIndex(SyncIndex index) async =>
      _writeIndex(await ensureEmployeesFolder(), index);

  Future<SyncIndex> readVouchersIndex() =>
      ensureVouchersFolder().then((id) => _readIndex(id));

  Future<void> writeVouchersIndex(SyncIndex index) async =>
      _writeIndex(await ensureVouchersFolder(), index);

  // ── Employee file helpers ─────────────────────────────────────────────────

  Future<String?> uploadEmployee(SyncEmployee employee) async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) return null;
    final fileName = '${employee.cloudId}.json';
    final existingId = await findFileId(fileName, folderId);

    final uploadedId = await uploadJson(
      fileName: fileName,
      data: employee.toJson(),
      parentFolderId: folderId,
      existingFileId: existingId,
    );
    if (uploadedId == null) return null;

    // Confirm visibility with retries (eventual consistency on Drive)
    if (existingId == null) {
      const maxRetries = 3;
      for (int i = 0; i < maxRetries; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final found = await findFileId(fileName, folderId);
        if (found != null) {
          debugPrint(
            'DriveService.uploadEmployee: confirmed "$fileName" '
            'visible after retry $i',
          );
          return found;
        }
      }
      debugPrint(
        'DriveService.uploadEmployee: "$fileName" not yet visible '
        'after $maxRetries retries — using returned id',
      );
    }
    return uploadedId;
  }

  Future<SyncEmployee?> downloadEmployee(String cloudId) async {
    final folderId = await ensureEmployeesFolder();
    if (folderId == null) return null;
    final fileId = await findFileId('$cloudId.json', folderId);
    if (fileId == null) return null;
    final json = await downloadJson(fileId);
    if (json == null) return null;
    try {
      return SyncEmployee.fromJson(json);
    } catch (e) {
      debugPrint('DriveService.downloadEmployee($cloudId) parse error: $e');
      return null;
    }
  }

  // ── Voucher file helpers ──────────────────────────────────────────────────

  Future<String?> uploadVoucher(SyncVoucher voucher) async {
    final folderId = await ensureVouchersFolder();
    if (folderId == null) return null;
    final fileName = '${voucher.cloudId}.json';
    final existingId = await findFileId(fileName, folderId);

    final uploadedId = await uploadJson(
      fileName: fileName,
      data: voucher.toJson(),
      parentFolderId: folderId,
      existingFileId: existingId,
    );
    if (uploadedId == null) return null;

    if (existingId == null) {
      const maxRetries = 3;
      for (int i = 0; i < maxRetries; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final found = await findFileId(fileName, folderId);
        if (found != null) return found;
      }
    }
    return uploadedId;
  }

  Future<SyncVoucher?> downloadVoucher(String cloudId) async {
    final folderId = await ensureVouchersFolder();
    if (folderId == null) return null;
    final fileId = await findFileId('$cloudId.json', folderId);
    if (fileId == null) return null;
    final json = await downloadJson(fileId);
    if (json == null) return null;
    try {
      return SyncVoucher.fromJson(json);
    } catch (e) {
      debugPrint('DriveService.downloadVoucher($cloudId) parse error: $e');
      return null;
    }
  }

  // ── Metadata ──────────────────────────────────────────────────────────────

  Future<DriveMetadata> readMetadata() async {
    final appFolderId = await ensureCrusamFolder();
    final empty =
        DriveMetadata(updatedAt: DateTime.now().toUtc().toIso8601String());
    if (appFolderId == null) return empty;
    final fileId = await findFileId('metadata.json', appFolderId);
    if (fileId == null) return empty;
    final json = await downloadJson(fileId);
    if (json == null) return empty;
    try {
      return DriveMetadata.fromJson(json);
    } catch (_) {
      return empty;
    }
  }

  Future<void> writeMetadata(DriveMetadata metadata) async {
    final appFolderId = await ensureCrusamFolder();
    if (appFolderId == null) return;
    final existingId = await findFileId('metadata.json', appFolderId);
    await uploadJson(
      fileName: 'metadata.json',
      data: metadata.toJson(),
      parentFolderId: appFolderId,
      existingFileId: existingId,
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────

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

  Future<void> writeItemDescriptions(
      List<Map<String, dynamic>> descriptions) async {
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
      // Verify the fixed root folder is accessible
      final rootId = await ensureCrusamFolder();
      if (rootId == null) {
        debugPrint(
          'DriveService.initializeDriveStructure: '
          'root folder not accessible — check service account config',
        );
        return;
      }
      debugPrint(
        'DriveService.initializeDriveStructure: root folder OK id=$rootId',
      );

      await ensureEmployeesFolder();
      await ensureVouchersFolder();
      await ensureSettingsFolder();
      await ensureBackupsFolder();

      // Seed index files on first-time setup
      final empFolderId = await ensureEmployeesFolder();
      if (empFolderId != null) {
        final empIndexId = await findFileId('index.json', empFolderId);
        if (empIndexId == null) {
          debugPrint(
            'DriveService.initializeDriveStructure: seeding employees index',
          );
          await writeEmployeesIndex(SyncIndex(
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: []));
        }
      }

      final vFolderId = await ensureVouchersFolder();
      if (vFolderId != null) {
        final vIndexId = await findFileId('index.json', vFolderId);
        if (vIndexId == null) {
          debugPrint(
            'DriveService.initializeDriveStructure: seeding vouchers index',
          );
          await writeVouchersIndex(SyncIndex(
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: []));
        }
      }

      await _registerDevice();
      debugPrint('DriveService.initializeDriveStructure: complete');
    } catch (e) {
      debugPrint('DriveService.initializeDriveStructure error: $e');
    }
  }

  Future<void> _registerDevice() async {
    final now = DateTime.now().toUtc().toIso8601String();
    String deviceId = 'device_unknown';
    String deviceName = 'Windows PC';
    try {
      final host = Platform.localHostname;
      deviceId =
          'device_${host.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}';
      deviceName = host;
    } catch (_) {}

    // Include the signed-in user's email in the device record so the
    // metadata.json shows which user synced from which machine.
    final signedInEmail =
        GoogleAuthService.instance.userEmail ?? 'unknown';

    try {
      final metadata = await readMetadata();
      final thisDevice = DriveDevice(
        deviceId: '${deviceId}_$signedInEmail',
        deviceName: '$deviceName ($signedInEmail)',
        platform: Platform.operatingSystem,
        appVersion: '1.0.0',
        dbSchemaVersion: 6,
        lastSeen: now,
      );
      final updatedDevices = [
        ...metadata.devices
            .where((d) => d.deviceId != thisDevice.deviceId),
        thisDevice,
      ];
      await writeMetadata(
          metadata.copyWith(updatedAt: now, devices: updatedDevices));
      debugPrint(
        'DriveService._registerDevice: registered '
        'device="${thisDevice.deviceName}"',
      );
    } catch (e) {
      debugPrint(
        'DriveService._registerDevice error (non-fatal): $e',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncResult
// ─────────────────────────────────────────────────────────────────────────────

class SyncResult {
  final bool success;
  final int employeesPulled;
  final int vouchersPulled;
  final int employeesPushed;
  final int vouchersPushed;
  final String? errorMessage;

  const SyncResult({
    required this.success,
    this.employeesPulled = 0,
    this.vouchersPulled = 0,
    this.employeesPushed = 0,
    this.vouchersPushed = 0,
    this.errorMessage,
  });

  const SyncResult.notSignedIn()
      : success = false,
        employeesPulled = 0,
        vouchersPulled = 0,
        employeesPushed = 0,
        vouchersPushed = 0,
        errorMessage = 'Not signed in';

  const SyncResult.networkError(String msg)
      : success = false,
        employeesPulled = 0,
        vouchersPulled = 0,
        employeesPushed = 0,
        vouchersPushed = 0,
        errorMessage = msg;

  @override
  String toString() =>
      'SyncResult(ok=$success, empPulled=$employeesPulled, '
      'vPulled=$vouchersPulled, empPushed=$employeesPushed, '
      'vPushed=$vouchersPushed, err=$errorMessage)';
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncManager  —  orchestrates all sync logic (UNCHANGED from previous version)
// ─────────────────────────────────────────────────────────────────────────────

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  final _db = DatabaseHelper.instance;
  final _drive = DriveService.instance;
  static const _uuid = Uuid();

  bool _syncing = false;

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  Future<SyncResult> syncOnStartup() async {
    if (!GoogleAuthService.instance.isSignedIn) {
      debugPrint('SyncManager.syncOnStartup: not signed in, skipping');
      return const SyncResult.notSignedIn();
    }

    if (_syncing) {
      debugPrint('SyncManager.syncOnStartup: already syncing, skipping');
      return const SyncResult(
          success: false, errorMessage: 'Sync already running');
    }

    _syncing = true;
    debugPrint(
      'SyncManager.syncOnStartup: START — user=${GoogleAuthService.instance.userEmail}',
    );
    try {
      await _db.createPreSyncBackup();
      await _drive.initializeDriveStructure();
      await _bootstrapCloudIds();
      final (empPulled, vPulled) = await _pullFromCloud();
      final (empPushed, vPushed) = await _drainPendingQueue();

      final result = SyncResult(
        success: true,
        employeesPulled: empPulled,
        vouchersPulled: vPulled,
        employeesPushed: empPushed,
        vouchersPushed: vPushed,
      );
      debugPrint('SyncManager.syncOnStartup: DONE — $result');
      return result;
    } catch (e, st) {
      debugPrint('SyncManager.syncOnStartup error: $e\n$st');
      return SyncResult.networkError(e.toString());
    } finally {
      _syncing = false;
    }
  }

  Future<SyncResult> syncNow() => syncOnStartup();

  Future<void> pushEmployeeChange({
    required String cloudId,
    required String operation,
    required Map<String, dynamic> employeeDbRow,
  }) async {
    if (!GoogleAuthService.instance.isSignedIn) return;
    final now = (employeeDbRow['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    final entry = SyncPendingEntry(
      entityType: 'employee',
      cloudId: cloudId,
      operation: operation,
      payload: employeeDbRow,
      localUpdatedAt: now,
    );
    await _db.addPendingSync(entry);
    _processSilently();
  }

  Future<void> pushInvoiceChange({
    required String cloudId,
    required String operation,
    required Map<String, dynamic> invoiceDbRow,
  }) async {
    if (!GoogleAuthService.instance.isSignedIn) return;
    final now = (invoiceDbRow['updated_at'] as String?) ??
        DateTime.now().toUtc().toIso8601String();
    final entry = SyncPendingEntry(
      entityType: 'invoice',
      cloudId: cloudId,
      operation: operation,
      payload: invoiceDbRow,
      localUpdatedAt: now,
    );
    await _db.addPendingSync(entry);
    _processSilently();
  }

  Future<SyncResult> pushAllToCloud() async {
    if (!GoogleAuthService.instance.isSignedIn) {
      return const SyncResult.notSignedIn();
    }
    try {
      await _drive.initializeDriveStructure();
      await _bootstrapCloudIds();
      await _enqueueAllForPush();
      final (empPushed, vPushed) = await _drainPendingQueue();
      return SyncResult(
          success: true,
          employeesPushed: empPushed,
          vouchersPushed: vPushed);
    } catch (e) {
      debugPrint('SyncManager.pushAllToCloud error: $e');
      return SyncResult.networkError(e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE IMPLEMENTATION (unchanged from previous version)
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _bootstrapCloudIds() async {
    final now = DateTime.now().toUtc().toIso8601String();

    final empRows = await (await _db.database).query(
      'employees',
      columns: ['id'],
      where:
          "(cloud_id IS NULL OR cloud_id = '') AND (is_deleted = 0 OR is_deleted IS NULL)",
    );
    for (final row in empRows) {
      final id = row['id'] as int;
      final cloudId = _uuid.v4();
      await _db.assignCloudId(id, cloudId, now);
    }

    final vRows = await (await _db.database).query(
      'vouchers',
      columns: ['id'],
      where:
          "(cloud_id IS NULL OR cloud_id = '') AND (is_deleted = 0 OR is_deleted IS NULL)",
    );
    for (final row in vRows) {
      final id = row['id'] as int;
      final cloudId = _uuid.v4();
      final email =
          GoogleAuthService.instance.userEmail ?? 'unknown';
      await _db.assignVoucherCloudId(id, cloudId, now, email, email);
    }

    if (empRows.isNotEmpty || vRows.isNotEmpty) {
      debugPrint(
        'SyncManager._bootstrapCloudIds: '
        '${empRows.length} employees, ${vRows.length} vouchers assigned cloud_ids',
      );
    }
  }

  Future<void> _enqueueAllForPush() async {
    final now = DateTime.now().toUtc().toIso8601String();

    final empRows = await _db.getAllSyncedEmployees();
    for (final row in empRows) {
      final cloudId = row['cloud_id'] as String;
      await (await _db.database).delete(
        'sync_pending',
        where: 'cloud_id = ? AND entity_type = ?',
        whereArgs: [cloudId, 'employee'],
      );
      final entry = SyncPendingEntry(
        entityType: 'employee',
        cloudId: cloudId,
        operation: 'upsert',
        payload: row,
        localUpdatedAt: (row['updated_at'] as String?) ?? now,
      );
      await _db.addPendingSync(entry);
    }

    final vRows = await _db.getAllSyncedVouchers();
    for (final row in vRows) {
      final cloudId = row['cloud_id'] as String;
      final voucherRows = await _db.getRowsByVoucherId(row['id'] as int);
      await (await _db.database).delete(
        'sync_pending',
        where: 'cloud_id = ? AND entity_type = ?',
        whereArgs: [cloudId, 'invoice'],
      );
      final fullPayload = Map<String, dynamic>.from(row)
        ..['rows'] = voucherRows;
      final entry = SyncPendingEntry(
        entityType: 'invoice',
        cloudId: cloudId,
        operation: 'upsert',
        payload: fullPayload,
        localUpdatedAt: (row['updated_at'] as String?) ?? now,
      );
      await _db.addPendingSync(entry);
    }

    debugPrint(
      'SyncManager._enqueueAllForPush: '
      '${empRows.length} employees, ${vRows.length} vouchers enqueued',
    );
  }

  Future<(int, int)> _pullFromCloud() async {
    int empPulled = 0;
    int vPulled = 0;

    try {
      final empIndex = await _drive.readEmployeesIndex();
      debugPrint(
        'SyncManager._pullFromCloud: employees index has '
        '${empIndex.entries.length} entries',
      );
      for (final entry in empIndex.entries) {
        try {
          if (entry.isDeleted) {
            await _db.softDeleteByCloudId(entry.cloudId);
            continue;
          }
          final cloudEmployee =
              await _drive.downloadEmployee(entry.cloudId);
          if (cloudEmployee == null) continue;
          final upserted =
              await _db.upsertEmployeeFromCloud(cloudEmployee.toJson());
          if (upserted > 0) empPulled++;
        } catch (e) {
          debugPrint(
            'SyncManager._pullFromCloud: employee '
            '${entry.cloudId} error: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
          'SyncManager._pullFromCloud: employees index error: $e');
    }

    try {
      final vIndex = await _drive.readVouchersIndex();
      debugPrint(
        'SyncManager._pullFromCloud: vouchers index has '
        '${vIndex.entries.length} entries',
      );
      for (final entry in vIndex.entries) {
        try {
          if (entry.isDeleted) {
            await _db.softDeleteVoucherByCloudId(entry.cloudId);
            continue;
          }
          final cloudVoucher =
              await _drive.downloadVoucher(entry.cloudId);
          if (cloudVoucher == null) continue;
          final upserted =
              await _db.upsertVoucherFromCloud(cloudVoucher.toDbMap());
          if (upserted > 0) vPulled++;
        } catch (e) {
          debugPrint(
            'SyncManager._pullFromCloud: voucher '
            '${entry.cloudId} error: $e',
          );
        }
      }
    } catch (e) {
      debugPrint(
          'SyncManager._pullFromCloud: vouchers index error: $e');
    }

    debugPrint(
      'SyncManager._pullFromCloud: '
      '$empPulled employees, $vPulled vouchers pulled',
    );
    return (empPulled, vPulled);
  }

  Future<(int, int)> _drainPendingQueue() async {
    final pendingRows = await _db.getPendingSyncs();
    if (pendingRows.isEmpty) return (0, 0);

    final List<SyncEmployee> uploadedEmployees = [];
    final List<SyncVoucher> uploadedVouchers = [];
    int empPushed = 0;
    int vPushed = 0;

    for (final row in pendingRows) {
      final entry = SyncPendingEntry.fromDbMap(row);
      try {
        if (entry.entityType == 'employee') {
          final syncEmp = SyncEmployee.fromJson(entry.payload);
          final fileId = await _drive.uploadEmployee(syncEmp);
          if (fileId != null) {
            uploadedEmployees.add(syncEmp);
            empPushed++;
            if (entry.id != null) await _db.removePendingSync(entry.id!);
          }
        } else if (entry.entityType == 'invoice') {
          final syncVoucher = SyncVoucher.fromJson(entry.payload);
          final fileId = await _drive.uploadVoucher(syncVoucher);
          if (fileId != null) {
            uploadedVouchers.add(syncVoucher);
            vPushed++;
            if (entry.id != null) await _db.removePendingSync(entry.id!);
          }
        }
      } catch (e) {
        debugPrint(
          'SyncManager._drainPendingQueue: ${entry.entityType} '
          '${entry.cloudId} error: $e',
        );
      }
    }

    if (uploadedEmployees.isNotEmpty) {
      try {
        final index = await _drive.readEmployeesIndex();
        final updatedEntries =
            List<SyncIndexEntry>.from(index.entries);
        final uploadedCloudIds =
            uploadedEmployees.map((e) => e.cloudId).toSet();
        updatedEntries.removeWhere(
            (entry) => uploadedCloudIds.contains(entry.cloudId));
        updatedEntries.addAll(uploadedEmployees.map((e) => SyncIndexEntry(
              cloudId: e.cloudId,
              updatedAt: e.updatedAt,
              isDeleted: e.isDeleted,
            )));
        await _drive.writeEmployeesIndex(SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: updatedEntries,
        ));
        debugPrint(
          'SyncManager._drainPendingQueue: employees index updated '
          '(${updatedEntries.length} entries)',
        );
      } catch (e) {
        debugPrint(
          'SyncManager._drainPendingQueue: '
          'failed to update employees index: $e',
        );
      }
    }

    if (uploadedVouchers.isNotEmpty) {
      try {
        final index = await _drive.readVouchersIndex();
        final updatedEntries =
            List<SyncIndexEntry>.from(index.entries);
        final uploadedCloudIds =
            uploadedVouchers.map((v) => v.cloudId).toSet();
        updatedEntries.removeWhere(
            (entry) => uploadedCloudIds.contains(entry.cloudId));
        updatedEntries.addAll(uploadedVouchers.map((v) => SyncIndexEntry(
              cloudId: v.cloudId,
              updatedAt: v.updatedAt,
              isDeleted: v.isDeleted,
            )));
        await _drive.writeVouchersIndex(SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: updatedEntries,
        ));
        debugPrint(
          'SyncManager._drainPendingQueue: vouchers index updated '
          '(${updatedEntries.length} entries)',
        );
      } catch (e) {
        debugPrint(
          'SyncManager._drainPendingQueue: '
          'failed to update vouchers index: $e',
        );
      }
    }

    debugPrint(
      'SyncManager._drainPendingQueue: '
      '$empPushed employees, $vPushed vouchers pushed',
    );
    return (empPushed, vPushed);
  }

  void _processSilently() {
    if (!GoogleAuthService.instance.isSignedIn) return;
    _drainPendingQueue().catchError((e) {
      debugPrint('SyncManager._processSilently error: $e');
    });
  }
}
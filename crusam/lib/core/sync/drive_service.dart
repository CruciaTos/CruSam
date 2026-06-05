// lib/core/sync/drive_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════
// CLOUD SYNC ARCHITECTURE
// ═══════════════════════════════════════════════════════════════════════════
//
// Drive layout:
//   Crusam/
//     metadata.json            ← device registry + index hashes
//     employees/
//       index.json             ← {updated_at, entries:[{cloud_id,updated_at,is_deleted}]}
//       <cloud_id>.json        ← full SyncEmployee record
//     vouchers/
//       index.json             ← same shape as employees index
//       <cloud_id>.json        ← full SyncVoucher record (header + rows)
//     settings/
//       company_config.json
//       margins.json
//       item_descriptions.json
//     backups/
//       (timestamped manual backups)
//
// Sync contract (Cloud → Local, on startup):
//   1. Write a local SQLite pre-sync backup (non-fatal).
//   2. Read employees/index.json + vouchers/index.json from Drive.
//   3. For each entry in each index:
//        a. If cloud updated_at > local updated_at  AND
//           no pending local write exists for that cloud_id  → upsert cloud → local.
//        b. If cloud entry is marked is_deleted AND local is not → soft-delete local.
//        c. Otherwise (local is newer, or pending write exists) → local wins;
//           the pending queue will reconcile Drive shortly after.
//
// Sync contract (Local → Cloud, on every change):
//   1. DatabaseHelper writes the row and enqueues a SyncPendingEntry.
//   2. SyncManager.pushEmployeeChange / pushInvoiceChange fires
//      _processSilently() to drain the pending queue in the background.
//   3. Draining: upload the entity JSON, update the index, remove the
//      pending row — all in one logical step.  A failure leaves the row
//      in sync_pending so the next startup retries.
//
// Import-then-cloud contract (BackupRestoreCard):
//   After importBackupData() succeeds the caller must invoke
//   SyncManager.instance.pushAllToCloud() which:
//     • assigns cloud_ids to any records that still lack one,
//     • enqueues every employee + voucher,
//     • drains the queue immediately (upload all, rewrite both indexes).
//
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:uuid/uuid.dart';

import '../../data/db/database_helper.dart';
import 'sync_models.dart';
import 'google_auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DriveService  —  raw Drive I/O, folder management, JSON up/download
// ─────────────────────────────────────────────────────────────────────────────

class DriveService {
  DriveService._();
  static final DriveService instance = DriveService._();

  static const _appFolderName = 'Crusam';

  // Cached folder IDs (reset on sign-out via clearCache())
  String? _appFolderId;
  String? _employeesFolderId;
  String? _vouchersFolderId;
  String? _settingsFolderId;
  String? _backupsFolderId;

  // ── Cache management ──────────────────────────────────────────────────────

  /// Call this when the user signs out so IDs are re-fetched on next sign-in.
  void clearCache() {
    _appFolderId = null;
    _employeesFolderId = null;
    _vouchersFolderId = null;
    _settingsFolderId = null;
    _backupsFolderId = null;
  }

  // ── Authenticated client helper ───────────────────────────────────────────

  Future<drive.DriveApi?> _api() async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    // Note: caller is responsible for closing the underlying http.Client.
    // DriveApi wraps it; we stash the client on the caller side when needed.
    return drive.DriveApi(client);
  }

  // ── Folder helpers ────────────────────────────────────────────────────────

  Future<String?> _findFolder(
      drive.DriveApi api, String name, String? parentId) async {
    final q = parentId != null
        ? "name='$name' and mimeType='application/vnd.google-apps.folder' and '$parentId' in parents and trashed=false"
        : "name='$name' and mimeType='application/vnd.google-apps.folder' and trashed=false";
    final result = await api.files.list(q: q, spaces: 'drive', $fields: 'files(id)');
    return result.files?.firstOrNull?.id;
  }

  Future<String?> _createFolder(
      drive.DriveApi api, String name, String? parentId) async {
    final meta = drive.File()
      ..name = name
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = parentId != null ? [parentId] : null;
    final created = await api.files.create(meta, $fields: 'id');
    return created.id;
  }

  Future<String?> _ensureFolder(
      drive.DriveApi api, String name, String? parentId) async {
    return await _findFolder(api, name, parentId) ??
        await _createFolder(api, name, parentId);
  }

  // ── Top-level folder getters (cached) ─────────────────────────────────────

  Future<String?> ensureCrusamFolder() async {
    if (_appFolderId != null) return _appFolderId;
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      final api = drive.DriveApi(client);
      _appFolderId = await _ensureFolder(api, _appFolderName, null);
      return _appFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureCrusamFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> ensureEmployeesFolder() async {
    if (_employeesFolderId != null) return _employeesFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      _employeesFolderId =
          await _ensureFolder(drive.DriveApi(client), 'employees', parent);
      return _employeesFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureEmployeesFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> ensureVouchersFolder() async {
    if (_vouchersFolderId != null) return _vouchersFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      _vouchersFolderId =
          await _ensureFolder(drive.DriveApi(client), 'vouchers', parent);
      return _vouchersFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureVouchersFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> ensureSettingsFolder() async {
    if (_settingsFolderId != null) return _settingsFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      _settingsFolderId =
          await _ensureFolder(drive.DriveApi(client), 'settings', parent);
      return _settingsFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureSettingsFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  Future<String?> ensureBackupsFolder() async {
    if (_backupsFolderId != null) return _backupsFolderId;
    final parent = await ensureCrusamFolder();
    if (parent == null) return null;
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      _backupsFolderId =
          await _ensureFolder(drive.DriveApi(client), 'backups', parent);
      return _backupsFolderId;
    } catch (e) {
      debugPrint('DriveService.ensureBackupsFolder error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── File lookup ───────────────────────────────────────────────────────────

  Future<String?> findFileId(String fileName, String parentFolderId) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      final api = drive.DriveApi(client);
      final result = await api.files.list(
        q: "name='$fileName' and '$parentFolderId' in parents and trashed=false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      return result.files?.firstOrNull?.id;
    } catch (e) {
      debugPrint('DriveService.findFileId($fileName) error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  // ── JSON upload / download ────────────────────────────────────────────────

  /// Uploads [data] as JSON.  If [existingFileId] is supplied the file is
  /// updated in-place; otherwise a new file is created under [parentFolderId].
  /// Returns the Drive file-id on success, null on failure.
  Future<String?> uploadJson({
    required String fileName,
    required Map<String, dynamic> data,
    String? parentFolderId,
    String? existingFileId,
  }) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      final api = drive.DriveApi(client);
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
        return updated.id;
      }

      final meta = drive.File()
        ..name = fileName
        ..parents = parentFolderId != null ? [parentFolderId] : null;
      final created = await api.files.create(meta, uploadMedia: media, $fields: 'id');
      return created.id;
    } catch (e) {
      debugPrint('DriveService.uploadJson($fileName) error: $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Downloads the file with [fileId] and parses it as JSON.
  Future<Map<String, dynamic>?> downloadJson(String fileId) async {
    final client = await GoogleAuthService.instance.getAuthenticatedClient();
    if (client == null) return null;
    try {
      final api = drive.DriveApi(client);
      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('DriveService.downloadJson($fileId) error: $e');
      return null;
    } finally {
      client.close();
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

  Future<SyncIndex> readEmployeesIndex() => ensureEmployeesFolder()
      .then((id) => _readIndex(id));

  Future<void> writeEmployeesIndex(SyncIndex index) async =>
      _writeIndex(await ensureEmployeesFolder(), index);

  Future<SyncIndex> readVouchersIndex() => ensureVouchersFolder()
      .then((id) => _readIndex(id));

  Future<void> writeVouchersIndex(SyncIndex index) async =>
      _writeIndex(await ensureVouchersFolder(), index);

  // ── Employee file helpers ─────────────────────────────────────────────────

  /// Uploads an employee file. Adds a retry for eventual consistency:
  /// after creation, tries to confirm the file is visible via a name search.
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

    // If the file was newly created, wait and retry to confirm visibility
    if (existingId == null) {
      const maxRetries = 3;
      for (int i = 0; i < maxRetries; i++) {
        await Future.delayed(const Duration(seconds: 1));
        final found = await findFileId(fileName, folderId);
        if (found != null) {
          debugPrint('DriveService.uploadEmployee: confirmed file $fileName visible after retry $i');
          return found;
        }
      }
      debugPrint('DriveService.uploadEmployee: file $fileName not yet visible after $maxRetries retries, using returned id');
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

  /// Uploads a voucher file. Same eventual-consistency retry as for employees.
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
    final empty = DriveMetadata(updatedAt: DateTime.now().toUtc().toIso8601String());
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
      await ensureCrusamFolder();
      await ensureEmployeesFolder();
      await ensureVouchersFolder();
      await ensureSettingsFolder();
      await ensureBackupsFolder();

      // Seed index files on first-time setup
      final empFolderId = await ensureEmployeesFolder();
      if (empFolderId != null) {
        final empIndexId = await findFileId('index.json', empFolderId);
        if (empIndexId == null) {
          await writeEmployeesIndex(SyncIndex(
              updatedAt: DateTime.now().toUtc().toIso8601String(),
              entries: []));
        }
      }

      final vFolderId = await ensureVouchersFolder();
      if (vFolderId != null) {
        final vIndexId = await findFileId('index.json', vFolderId);
        if (vIndexId == null) {
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

    try {
      final metadata = await readMetadata();
      final thisDevice = DriveDevice(
        deviceId: deviceId,
        deviceName: deviceName,
        platform: Platform.operatingSystem,
        appVersion: '1.0.0',
        dbSchemaVersion: 6,
        lastSeen: now,
      );
      final updatedDevices = [
        ...metadata.devices.where((d) => d.deviceId != deviceId),
        thisDevice,
      ];
      await writeMetadata(
          metadata.copyWith(updatedAt: now, devices: updatedDevices));
    } catch (e) {
      debugPrint('DriveService._registerDevice error (non-fatal): $e');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SyncResult  —  returned by syncOnStartup() for progress / error reporting
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
// SyncManager  —  orchestrates all sync logic
// ─────────────────────────────────────────────────────────────────────────────

class SyncManager {
  SyncManager._();
  static final SyncManager instance = SyncManager._();

  final _db = DatabaseHelper.instance;
  final _drive = DriveService.instance;
  static const _uuid = Uuid();

  // Tracks whether a sync is already in progress to avoid concurrent runs.
  bool _syncing = false;

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  // ── Startup sync (pull then push) ─────────────────────────────────────────

  /// Full sync to run on every app launch.
  ///
  /// Order:
  ///   1. Write a pre-sync local SQLite backup (non-fatal).
  ///   2. Bootstrap Drive folder structure.
  ///   3. Assign cloud_ids to any local records that still lack one.
  ///   4. Pull cloud → local (cloud wins for newer records).
  ///   5. Push local → cloud (drain the pending queue).
  ///
  /// Returns a [SyncResult] you can use to show a status indicator.
  /// Never throws — all errors are caught and reflected in the result.
  Future<SyncResult> syncOnStartup() async {
    if (!GoogleAuthService.instance.isSignedIn) {
      debugPrint('SyncManager.syncOnStartup: not signed in, skipping');
      return const SyncResult.notSignedIn();
    }

    if (_syncing) {
      debugPrint('SyncManager.syncOnStartup: already syncing, skipping');
      return const SyncResult(success: false, errorMessage: 'Sync already running');
    }

    _syncing = true;
    try {
      // 1. Pre-sync backup
      await _db.createPreSyncBackup();

      // 2. Bootstrap Drive structure
      await _drive.initializeDriveStructure();

      // 3. Assign missing cloud_ids to local records before pulling
      //    (so that subsequent push doesn't create duplicates on Drive)
      await _bootstrapCloudIds();

      // 4. Pull cloud → local
      final (empPulled, vPulled) = await _pullFromCloud();

      // 5. Push local → cloud
      final (empPushed, vPushed) = await _drainPendingQueue();

      final result = SyncResult(
        success: true,
        employeesPulled: empPulled,
        vouchersPulled: vPulled,
        employeesPushed: empPushed,
        vouchersPushed: vPushed,
      );
      debugPrint('SyncManager.syncOnStartup: $result');
      return result;
    } catch (e, st) {
      debugPrint('SyncManager.syncOnStartup error: $e\n$st');
      return SyncResult.networkError(e.toString());
    } finally {
      _syncing = false;
    }
  }

  /// Convenience method for the "Sync now" button in the profile screen.
  Future<SyncResult> syncNow() => syncOnStartup();

  // ── Change notifications (called by DatabaseHelper) ───────────────────────

  /// Call after inserting / updating / deleting an employee in SQLite.
  Future<void> pushEmployeeChange({
    required String cloudId,
    required String operation, // 'create' | 'update' | 'delete'
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

  /// Call after inserting / updating / deleting a voucher in SQLite.
  Future<void> pushInvoiceChange({
    required String cloudId,
    required String operation, // 'create' | 'update' | 'delete'
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

  // ── Post-import full push ─────────────────────────────────────────────────

  /// Called by BackupRestoreCard immediately after a successful import.
  ///
  /// 1. Assigns cloud_ids to any newly-imported records that lack them.
  /// 2. Enqueues every employee and voucher for upload.
  /// 3. Drains the queue synchronously (awaited) so the cloud is updated
  ///    before the function returns and the caller can report success.
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
          success: true, employeesPushed: empPushed, vouchersPushed: vPushed);
    } catch (e) {
      debugPrint('SyncManager.pushAllToCloud error: $e');
      return SyncResult.networkError(e.toString());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE IMPLEMENTATION
  // ══════════════════════════════════════════════════════════════════════════

  // ── Bootstrap cloud_ids ───────────────────────────────────────────────────

  /// Any local employee or voucher row without a cloud_id gets one assigned now.
  Future<void> _bootstrapCloudIds() async {
    final now = DateTime.now().toUtc().toIso8601String();

    // Employees – FIX: exclude soft-deleted rows (Bug 3)
    final empRows = await (await _db.database).query(
      'employees',
      columns: ['id'],
      where: "(cloud_id IS NULL OR cloud_id = '') AND (is_deleted = 0 OR is_deleted IS NULL)",
    );
    for (final row in empRows) {
      final id = row['id'] as int;
      final cloudId = _uuid.v4();
      await _db.assignCloudId(id, cloudId, now);
    }

    // Vouchers
    final vRows = await (await _db.database).query(
      'vouchers',
      columns: ['id'],
      where: "(cloud_id IS NULL OR cloud_id = '') AND (is_deleted = 0 OR is_deleted IS NULL)",
    );
    for (final row in vRows) {
      final id = row['id'] as int;
      final cloudId = _uuid.v4();
      final email = GoogleAuthService.instance.userEmail ?? 'unknown';
      await _db.assignVoucherCloudId(id, cloudId, now, email, email);
    }

    if (empRows.isNotEmpty || vRows.isNotEmpty) {
      debugPrint('SyncManager._bootstrapCloudIds: '
          '${empRows.length} employees, ${vRows.length} vouchers assigned cloud_ids');
    }
  }

  // ── Enqueue everything for post-import push ───────────────────────────────

  Future<void> _enqueueAllForPush() async {
    final now = DateTime.now().toUtc().toIso8601String();

    final empRows = await _db.getAllSyncedEmployees();
    for (final row in empRows) {
      final cloudId = row['cloud_id'] as String;
      // Remove duplicate pending entries first to avoid double-uploads
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
        localUpdatedAt:
            (row['updated_at'] as String?) ?? now,
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
        localUpdatedAt:
            (row['updated_at'] as String?) ?? now,
      );
      await _db.addPendingSync(entry);
    }

    debugPrint('SyncManager._enqueueAllForPush: '
        '${empRows.length} employees, ${vRows.length} vouchers enqueued');
  }

  // ── Pull cloud → local ────────────────────────────────────────────────────

  Future<(int, int)> _pullFromCloud() async {
    int empPulled = 0;
    int vPulled = 0;

    // ── Employees ──────────────────────────────────────────────────────────
    try {
      final empIndex = await _drive.readEmployeesIndex();
      for (final entry in empIndex.entries) {
        try {
          if (entry.isDeleted) {
            // Propagate soft-delete to local if not already deleted
            await _db.softDeleteByCloudId(entry.cloudId);
            continue;
          }
          final cloudEmployee = await _drive.downloadEmployee(entry.cloudId);
          if (cloudEmployee == null) continue;
          final upserted =
              await _db.upsertEmployeeFromCloud(cloudEmployee.toJson());
          if (upserted > 0) empPulled++;
        } catch (e) {
          debugPrint(
              'SyncManager._pullFromCloud: employee ${entry.cloudId} error: $e');
        }
      }
    } catch (e) {
      debugPrint('SyncManager._pullFromCloud: employees index error: $e');
    }

    // ── Vouchers ───────────────────────────────────────────────────────────
    try {
      final vIndex = await _drive.readVouchersIndex();
      for (final entry in vIndex.entries) {
        try {
          if (entry.isDeleted) {
            await _db.softDeleteVoucherByCloudId(entry.cloudId);
            continue;
          }
          final cloudVoucher = await _drive.downloadVoucher(entry.cloudId);
          if (cloudVoucher == null) continue;
          final upserted =
              await _db.upsertVoucherFromCloud(cloudVoucher.toDbMap());
          if (upserted > 0) vPulled++;
        } catch (e) {
          debugPrint(
              'SyncManager._pullFromCloud: voucher ${entry.cloudId} error: $e');
        }
      }
    } catch (e) {
      debugPrint('SyncManager._pullFromCloud: vouchers index error: $e');
    }

    debugPrint('SyncManager._pullFromCloud: '
        '$empPulled employees, $vPulled vouchers pulled');
    return (empPulled, vPulled);
  }

  // ── Push (drain queue) ────────────────────────────────────────────────────

  /// Uploads all pending entries, then updates the Drive indexes once per
  /// entity type to avoid per‑record index clobbering and race conditions.
  Future<(int, int)> _drainPendingQueue() async {
    final pendingRows = await _db.getPendingSyncs();
    if (pendingRows.isEmpty) return (0, 0);

    // Collect successfully uploaded employee/voucher data
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
            '${entry.cloudId} error: $e');
        // Leave the row in sync_pending — it will be retried on the next sync.
      }
    }

    // ── Batch index update for employees ──────────────────────────────────
    if (uploadedEmployees.isNotEmpty) {
      try {
        final index = await _drive.readEmployeesIndex();
        final updatedEntries = List<SyncIndexEntry>.from(index.entries);
        // Remove all entries for the uploaded cloudIds, then add the new ones
        final uploadedCloudIds = uploadedEmployees.map((e) => e.cloudId).toSet();
        updatedEntries.removeWhere((entry) => uploadedCloudIds.contains(entry.cloudId));
        updatedEntries.addAll(uploadedEmployees.map((e) => SyncIndexEntry(
              cloudId: e.cloudId,
              updatedAt: e.updatedAt,
              isDeleted: e.isDeleted,
            )));
        await _drive.writeEmployeesIndex(SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: updatedEntries,
        ));
      } catch (e) {
        debugPrint('SyncManager._drainPendingQueue: failed to update employees index: $e');
      }
    }

    // ── Batch index update for vouchers ───────────────────────────────────
    if (uploadedVouchers.isNotEmpty) {
      try {
        final index = await _drive.readVouchersIndex();
        final updatedEntries = List<SyncIndexEntry>.from(index.entries);
        final uploadedCloudIds = uploadedVouchers.map((v) => v.cloudId).toSet();
        updatedEntries.removeWhere((entry) => uploadedCloudIds.contains(entry.cloudId));
        updatedEntries.addAll(uploadedVouchers.map((v) => SyncIndexEntry(
              cloudId: v.cloudId,
              updatedAt: v.updatedAt,
              isDeleted: v.isDeleted,
            )));
        await _drive.writeVouchersIndex(SyncIndex(
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          entries: updatedEntries,
        ));
      } catch (e) {
        debugPrint('SyncManager._drainPendingQueue: failed to update vouchers index: $e');
      }
    }

    debugPrint('SyncManager._drainPendingQueue: '
        '$empPushed employees, $vPushed vouchers pushed');
    return (empPushed, vPushed);
  }

  // The old per‑record index writers are removed (no longer called).

  // ── Fire-and-forget push ──────────────────────────────────────────────────

  void _processSilently() {
    if (!GoogleAuthService.instance.isSignedIn) return;
    _drainPendingQueue().catchError((e) {
      debugPrint('SyncManager._processSilently error: $e');
    });
  }
}
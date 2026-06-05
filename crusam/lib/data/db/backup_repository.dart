// lib/data/db/backup_repository.dart
//
// Extension on DatabaseHelper that adds two methods:
//
//   exportBackupData()  → serialises all user data to a Map ready for JSON
//   importBackupData()  → upserts rows from a backup Map back into SQLite
//
// HOW TO WIRE IN:
//   Add this import to database_helper.dart so the extension is always in scope:
//
//     import 'backup_repository.dart';
//
// Tables included in backup:
//   employees, vouchers, voucher_rows, company_config, item_descriptions
//
// Tables intentionally excluded (transient / can be rebuilt):
//   sync_pending, auth_session, app_migrations, voucher_draft, voucher_draft_rows
//   salary_disbursements, salary_disbursement_items, users, pdf_settings

import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

extension BackupRepository on DatabaseHelper {
  // ── Export ──────────────────────────────────────────────────────────────

  /// Returns a Map that can be JSON-encoded to produce a portable backup file.
  Future<Map<String, dynamic>> exportBackupData() async {
    final db = await database;

    final employees =
        await db.query('employees', orderBy: 'sr_no ASC');
    final vouchers =
        await db.query('vouchers', orderBy: 'id ASC');
    final voucherRows =
        await db.query('voucher_rows', orderBy: 'id ASC');
    final companyConfig = await db.query('company_config');
    final itemDescriptions =
        await db.query('item_descriptions', orderBy: 'id ASC');

    return {
      'meta': {
        'version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'app': 'CruSam',
      },
      'employees': employees,
      'vouchers': vouchers,
      'voucher_rows': voucherRows,
      'company_config': companyConfig,
      'item_descriptions': itemDescriptions,
    };
  }

  // ── Import ──────────────────────────────────────────────────────────────

  /// Merges rows from [backup] into the database.
  ///
  /// Strategy per table:
  ///   employees          – upsert by cloud_id when present, else by id
  ///   vouchers           – upsert by cloud_id when present, else by id
  ///   voucher_rows       – delete existing rows for each voucher_id then re-insert
  ///   company_config     – replace (single row)
  ///   item_descriptions  – insert-or-ignore (avoid duplicates by text)
  ///
  /// Returns a summary map: { 'employees': N, 'vouchers': N, 'voucher_rows': N }
  Future<Map<String, int>> importBackupData(
      Map<String, dynamic> backup) async {
    final db = await database;

    int empCount = 0;
    int voucherCount = 0;
    int rowCount = 0;

    await db.transaction((txn) async {
      // ── employees ──────────────────────────────────────────────────────
      final empList = _asList(backup['employees']);
      for (final raw in empList) {
        final row = Map<String, dynamic>.from(raw as Map);
        // Remove the integer primary key so SQLite can handle conflicts via
        // cloud_id or fall back to replace-by-id below.
        final cloudId = row['cloud_id'] as String?;

        if (cloudId != null && cloudId.isNotEmpty) {
          // Check whether this cloud_id already exists
          final existing = await txn.query(
            'employees',
            columns: ['id', 'updated_at'],
            where: 'cloud_id = ?',
            whereArgs: [cloudId],
            limit: 1,
          );
          if (existing.isEmpty) {
            // New record – strip id to let autoincrement assign one
            row.remove('id');
            await txn.insert('employees', row,
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } else {
            // Existing record – update if backup timestamp is newer
            final localTs = existing.first['updated_at'] as String? ?? '';
            final backupTs = row['updated_at'] as String? ?? '';
            if (backupTs.compareTo(localTs) >= 0) {
              row['id'] = existing.first['id'];
              await txn.update(
                'employees',
                row,
                where: 'cloud_id = ?',
                whereArgs: [cloudId],
              );
            }
          }
        } else {
          // No cloud_id – upsert by integer id
          await txn.insert('employees', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        empCount++;
      }

      // ── vouchers ───────────────────────────────────────────────────────
      // Keep a mapping from backup voucher id → local voucher id so we can
      // correctly re-link voucher_rows.
      final voucherIdMap = <int, int>{}; // backupId → localId

      final voucherList = _asList(backup['vouchers']);
      for (final raw in voucherList) {
        final row = Map<String, dynamic>.from(raw as Map);
        final backupId = row['id'] as int?;
        final cloudId = row['cloud_id'] as String?;

        if (cloudId != null && cloudId.isNotEmpty) {
          final existing = await txn.query(
            'vouchers',
            columns: ['id', 'updated_at'],
            where: 'cloud_id = ?',
            whereArgs: [cloudId],
            limit: 1,
          );
          if (existing.isEmpty) {
            row.remove('id');
            final localId = await txn.insert('vouchers', row,
                conflictAlgorithm: ConflictAlgorithm.ignore);
            if (backupId != null) voucherIdMap[backupId] = localId;
          } else {
            final localTs = existing.first['updated_at'] as String? ?? '';
            final backupTs = row['updated_at'] as String? ?? '';
            final localId = existing.first['id'] as int;
            if (backupId != null) voucherIdMap[backupId] = localId;
            if (backupTs.compareTo(localTs) >= 0) {
              row['id'] = localId;
              await txn.update(
                'vouchers',
                row,
                where: 'cloud_id = ?',
                whereArgs: [cloudId],
              );
            }
          }
        } else {
          final localId = await txn.insert('vouchers', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
          if (backupId != null) voucherIdMap[backupId] = localId;
        }
        voucherCount++;
      }

      // ── voucher_rows ───────────────────────────────────────────────────
      // Group rows by their backup voucher_id, then delete + re-insert under
      // the (possibly remapped) local voucher_id.
      final rowList = _asList(backup['voucher_rows']);
      final groupedRows = <int, List<Map<String, dynamic>>>{};

      for (final raw in rowList) {
        final r = Map<String, dynamic>.from(raw as Map);
        final vid = r['voucher_id'] as int?;
        if (vid == null) continue;
        groupedRows.putIfAbsent(vid, () => []).add(r);
      }

      for (final entry in groupedRows.entries) {
        final backupVid = entry.key;
        final localVid = voucherIdMap[backupVid] ?? backupVid;

        // Delete existing rows for this voucher
        await txn.delete(
          'voucher_rows',
          where: 'voucher_id = ?',
          whereArgs: [localVid],
        );

        for (final r in entry.value) {
          r.remove('id'); // let autoincrement assign new id
          r['voucher_id'] = localVid;
          await txn.insert('voucher_rows', r,
              conflictAlgorithm: ConflictAlgorithm.ignore);
          rowCount++;
        }
      }

      // ── company_config ─────────────────────────────────────────────────
      final configList = _asList(backup['company_config']);
      if (configList.isNotEmpty) {
        final configRow =
            Map<String, dynamic>.from(configList.first as Map);
        configRow['id'] = 1; // always row 1
        await txn.insert('company_config', configRow,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      // ── item_descriptions ──────────────────────────────────────────────
      final descList = _asList(backup['item_descriptions']);
      for (final raw in descList) {
        final r = Map<String, dynamic>.from(raw as Map);
        final text = r['text'] as String?;
        if (text == null || text.trim().isEmpty) continue;
        // Skip if this text already exists to avoid duplicates
        final dup = await txn.query(
          'item_descriptions',
          columns: ['id'],
          where: 'text = ?',
          whereArgs: [text],
          limit: 1,
        );
        if (dup.isEmpty) {
          r.remove('id');
          await txn.insert('item_descriptions', r,
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });

    return {
      'employees': empCount,
      'vouchers': voucherCount,
      'voucher_rows': rowCount,
    };
  }

  // ── Helper ──────────────────────────────────────────────────────────────

  List<dynamic> _asList(dynamic value) {
    if (value == null) return const [];
    if (value is List) return value;
    return const [];
  }
}
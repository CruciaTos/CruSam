import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';
import '../../core/society_exception.dart';

class BackupPreview {
  final String originalSocietyName;
  final String exportedAt;
  final int unitCount;
  final int memberCount;
  final int journalEntryCount;
  final int billCount;
  final int receiptCount;
  final Map<String, dynamic> rawData;

  const BackupPreview({
    required this.originalSocietyName,
    required this.exportedAt,
    required this.unitCount,
    required this.memberCount,
    required this.journalEntryCount,
    required this.billCount,
    required this.receiptCount,
    required this.rawData,
  });
}

class BackupService {
  final DatabaseExecutor db;

  BackupService(this.db);

  // ----------------------------------------------------------------------
  // 1. Export Society
  // ----------------------------------------------------------------------
  Future<Uint8List> exportSociety(int societyId) async {
    final socRows = await db.query('societies', where: 'id = ?', whereArgs: [societyId]);
    if (socRows.isEmpty) {
      throw SocietyException('not_found', 'Society not found: $societyId');
    }
    final societyData = Map<String, dynamic>.from(socRows.first);

    final tables = <String, List<Map<String, dynamic>>>{};

    const directTables = [
      'financial_years',
      'number_series',
      'account_groups',
      'accounts',
      'unit_types',
      'blocks',
      'units',
      'people',
      'unit_people',
      'charge_heads',
      'billing_rules',
      'bill_runs',
      'bills',
      'interest_accruals',
      'receipts',
      'unidentified_receipts',
      'credit_notes',
      'other_invoices',
      'other_receipts',
      'vendors',
      'expense_bills',
      'vendor_payments',
      'budgets',
      'bank_accounts',
      'bank_transfers',
      'bank_statement_imports',
      'fixed_deposits',
      'document_footers',
      'reminder_batches',
      'email_log',
      'society_settings',
    ];

    for (final tbl in directTables) {
      final rows = await db.query(tbl, where: 'society_id = ?', whereArgs: [societyId]);
      tables[tbl] = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    // Journal entries & lines
    final jeRows = await db.query('journal_entries', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['journal_entries'] = jeRows.map((r) => Map<String, dynamic>.from(r)).toList();

    final jlRows = await db.query('journal_lines', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['journal_lines'] = jlRows.map((r) => Map<String, dynamic>.from(r)).toList();

    // Bill lines
    final billLines = await db.query('bill_lines', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['bill_lines'] = billLines.map((r) => Map<String, dynamic>.from(r)).toList();

    // Bill allocations
    final allocRows = await db.query('bill_allocations', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['bill_allocations'] = allocRows.map((r) => Map<String, dynamic>.from(r)).toList();

    // Other invoice lines
    final otherLines = await db.query('other_invoice_lines', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['other_invoice_lines'] = otherLines.map((r) => Map<String, dynamic>.from(r)).toList();

    // Expense bill lines
    final expLines = await db.query('expense_lines', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['expense_lines'] = expLines.map((r) => Map<String, dynamic>.from(r)).toList();

    // Vendor payment allocations
    final vpaLines = await db.query('vendor_payment_allocations', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['vendor_payment_allocations'] = vpaLines.map((r) => Map<String, dynamic>.from(r)).toList();

    // Statement lines
    final stLines = await db.query('bank_statement_lines', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['bank_statement_lines'] = stLines.map((r) => Map<String, dynamic>.from(r)).toList();

    // FD transactions
    final fdTxns = await db.query('fd_transactions', where: 'society_id = ?', whereArgs: [societyId], orderBy: 'id ASC');
    tables['fd_transactions'] = fdTxns.map((r) => Map<String, dynamic>.from(r)).toList();

    // Bank clearances
    final bcRows = await db.query('bank_clearances', where: 'society_id = ?', whereArgs: [societyId]);
    tables['bank_clearances'] = bcRows.map((r) => Map<String, dynamic>.from(r)).toList();

    final backupPayload = {
      'format': 'crusam_society_backup',
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'society': societyData,
      'tables': tables,
    };

    final jsonStr = jsonEncode(backupPayload);
    final utfBytes = utf8.encode(jsonStr);
    final compressed = gzip.encode(utfBytes);
    return Uint8List.fromList(compressed);
  }

  // ----------------------------------------------------------------------
  // 2. Inspect Backup File
  // ----------------------------------------------------------------------
  Future<BackupPreview> inspect(Uint8List bytes) async {
    try {
      final decompressed = gzip.decode(bytes);
      final jsonStr = utf8.decode(decompressed);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      if (data['format'] != 'crusam_society_backup') {
        throw const SocietyException('invalid_format', 'Not a valid CruSam Society backup file');
      }

      final version = data['version'] as int? ?? 0;
      if (version > 1) {
        throw SocietyException('unsupported_version', 'Backup version $version is not supported');
      }

      final society = data['society'] as Map<String, dynamic>? ?? {};
      final tables = data['tables'] as Map<String, dynamic>? ?? {};

      return BackupPreview(
        originalSocietyName: society['name'] as String? ?? 'Unknown Society',
        exportedAt: data['exported_at'] as String? ?? '',
        unitCount: (tables['units'] as List?)?.length ?? 0,
        memberCount: (tables['people'] as List?)?.length ?? 0,
        journalEntryCount: (tables['journal_entries'] as List?)?.length ?? 0,
        billCount: (tables['bills'] as List?)?.length ?? 0,
        receiptCount: (tables['receipts'] as List?)?.length ?? 0,
        rawData: data,
      );
    } catch (e) {
      if (e is SocietyException) rethrow;
      throw SocietyException('corrupt_backup', 'Failed to read backup file: ${e.toString()}');
    }
  }

  // ----------------------------------------------------------------------
  // 3. Restore As New Society
  // ----------------------------------------------------------------------
  Future<int> restoreAsNewSociety(BackupPreview preview, String newName) async {
    final trimmedName = newName.trim();
    if (trimmedName.isEmpty) {
      throw const SocietyException('validation', 'New society name cannot be empty');
    }

    // Name uniqueness check
    final existing = await db.query('societies', where: 'name = ?', whereArgs: [trimmedName]);
    if (existing.isNotEmpty) {
      throw SocietyException('duplicate', 'A society with name "$trimmedName" already exists');
    }

    final rawData = preview.rawData;
    final societyData = Map<String, dynamic>.from(rawData['society'] as Map<String, dynamic>);
    final tables = rawData['tables'] as Map<String, dynamic>;

    return await (db as dynamic).transaction((txn) async {
      // 1. Insert new society record
      societyData.remove('id');
      societyData['name'] = trimmedName;
      societyData['created_at'] = DateTime.now().toIso8601String();
      societyData['updated_at'] = DateTime.now().toIso8601String();
      societyData['is_active'] = 1;

      final newSocId = await txn.insert('societies', societyData);

      // ID Mapping stores
      final fyMap = <int, int>{};
      final groupMap = <int, int>{};
      final accMap = <int, int>{};
      final unitTypeMap = <int, int>{};
      final blockMap = <int, int>{};
      final unitMap = <int, int>{};
      final personMap = <int, int>{};
      final headMap = <int, int>{};
      final runMap = <int, int>{};
      final billMap = <int, int>{};
      final receiptMap = <int, int>{};
      final jeMap = <int, int>{};
      final vendorMap = <int, int>{};
      final expBillMap = <int, int>{};
      final bankAccMap = <int, int>{};
      final fdMap = <int, int>{};

      // 2. Financial Years
      final fyList = (tables['financial_years'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in fyList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        final newId = await txn.insert('financial_years', map);
        fyMap[oldId] = newId;
      }

      // 3. Number Series
      final nsList = (tables['number_series'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in nsList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        await txn.insert('number_series', map);
      }

      // 4. Account Groups
      final grpList = (tables['account_groups'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in grpList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['parent_id'] != null && groupMap.containsKey(map['parent_id'])) {
          map['parent_id'] = groupMap[map['parent_id']];
        }
        final newId = await txn.insert('account_groups', map);
        groupMap[oldId] = newId;
      }

      // 5. Accounts
      final accList = (tables['accounts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in accList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['group_id'] != null) map['group_id'] = groupMap[map['group_id']];
        final newId = await txn.insert('accounts', map);
        accMap[oldId] = newId;
      }

      // 6. Unit Types
      final utList = (tables['unit_types'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in utList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        final newId = await txn.insert('unit_types', map);
        unitTypeMap[oldId] = newId;
      }

      // 7. Blocks
      final blkList = (tables['blocks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in blkList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        final newId = await txn.insert('blocks', map);
        blockMap[oldId] = newId;
      }

      // 8. Units
      final uList = (tables['units'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in uList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['block_id'] != null) map['block_id'] = blockMap[map['block_id']];
        if (map['unit_type_id'] != null) map['unit_type_id'] = unitTypeMap[map['unit_type_id']];
        final newId = await txn.insert('units', map);
        unitMap[oldId] = newId;
      }

      // 9. People
      final pList = (tables['people'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in pList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        final newId = await txn.insert('people', map);
        personMap[oldId] = newId;
      }

      // 10. Unit People
      final umList = (tables['unit_people'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in umList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['unit_id'] = unitMap[map['unit_id']];
        map['person_id'] = personMap[map['person_id']];
        await txn.insert('unit_people', map);
      }

      // 11. Charge Heads
      final chList = (tables['charge_heads'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in chList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['account_id'] != null) map['account_id'] = accMap[map['account_id']];
        final newId = await txn.insert('charge_heads', map);
        headMap[oldId] = newId;
      }

      // 12. Billing Rules
      final crList = (tables['billing_rules'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in crList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['charge_head_id'] = headMap[map['charge_head_id']];
        if (map['unit_type_id'] != null) map['unit_type_id'] = unitTypeMap[map['unit_type_id']];
        await txn.insert('billing_rules', map);
      }

      // 13. Journal Entries
      final jeList = (tables['journal_entries'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in jeList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        map['reversal_of_id'] = null;
        map['reversed_by_id'] = null;
        final newId = await txn.insert('journal_entries', map);
        jeMap[oldId] = newId;
      }

      // Remap reversal links in journal entries
      for (final r in jeList) {
        final oldId = r['id'] as int;
        final newId = jeMap[oldId]!;
        final oldRevOf = r['reversal_of_id'] as int?;
        final oldRevBy = r['reversed_by_id'] as int?;
        if (oldRevOf != null || oldRevBy != null) {
          await txn.update(
            'journal_entries',
            {
              'reversal_of_id': oldRevOf != null ? jeMap[oldRevOf] : null,
              'reversed_by_id': oldRevBy != null ? jeMap[oldRevBy] : null,
            },
            where: 'id = ?',
            whereArgs: [newId],
          );
        }
      }

      // 14. Journal Lines
      final jlMap = <int, int>{};
      final jlList = (tables['journal_lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in jlList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['entry_id'] = jeMap[map['entry_id']];
        map['account_id'] = accMap[map['account_id']];
        if (map['unit_id'] != null) map['unit_id'] = unitMap[map['unit_id']];
        final newId = await txn.insert('journal_lines', map);
        jlMap[oldId] = newId;
      }

      // Bank clearances
      final bcList = (tables['bank_clearances'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in bcList) {
        final map = Map<String, dynamic>.from(r);
        map['society_id'] = newSocId;
        if (map['journal_line_id'] != null) {
          map['journal_line_id'] = jlMap[map['journal_line_id']];
        }
        await txn.insert('bank_clearances', map);
      }

      // 15. Bill Runs
      final brList = (tables['bill_runs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in brList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        final newId = await txn.insert('bill_runs', map);
        runMap[oldId] = newId;
      }

      // 16. Bills
      final bList = (tables['bills'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in bList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        if (map['run_id'] != null) map['run_id'] = runMap[map['run_id']];
        map['unit_id'] = unitMap[map['unit_id']];
        if (map['bill_to_person_id'] != null) map['bill_to_person_id'] = personMap[map['bill_to_person_id']];
        if (map['journal_entry_id'] != null) map['journal_entry_id'] = jeMap[map['journal_entry_id']];
        if (map['reversal_entry_id'] != null) map['reversal_entry_id'] = jeMap[map['reversal_entry_id']];
        final newId = await txn.insert('bills', map);
        billMap[oldId] = newId;
      }

      // 17. Bill Lines
      final blList = (tables['bill_lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in blList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['bill_id'] = billMap[map['bill_id']];
        map['charge_head_id'] = headMap[map['charge_head_id']];
        await txn.insert('bill_lines', map);
      }

      // 18. Receipts
      final rcptList = (tables['receipts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in rcptList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        map['unit_id'] = unitMap[map['unit_id']];
        if (map['deposit_account_id'] != null) map['deposit_account_id'] = accMap[map['deposit_account_id']];
        if (map['journal_entry_id'] != null) map['journal_entry_id'] = jeMap[map['journal_entry_id']];
        if (map['reversal_entry_id'] != null) map['reversal_entry_id'] = jeMap[map['reversal_entry_id']];
        final newId = await txn.insert('receipts', map);
        receiptMap[oldId] = newId;
      }

      // 19. Bill Allocations
      final allocList = (tables['bill_allocations'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in allocList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['bill_id'] != null) map['bill_id'] = billMap[map['bill_id']];
        if (map['source_type'] == 'receipt' && map['source_id'] != null) {
          map['source_id'] = receiptMap[map['source_id']];
        }
        await txn.insert('bill_allocations', map);
      }

      // 20. Vendors
      final vList = (tables['vendors'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in vList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['default_expense_account_id'] != null) map['default_expense_account_id'] = accMap[map['default_expense_account_id']];
        final newId = await txn.insert('vendors', map);
        vendorMap[oldId] = newId;
      }

      // 21. Expense Bills
      final ebList = (tables['expense_bills'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in ebList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        map['vendor_id'] = vendorMap[map['vendor_id']];
        if (map['journal_entry_id'] != null) map['journal_entry_id'] = jeMap[map['journal_entry_id']];
        if (map['reversal_entry_id'] != null) map['reversal_entry_id'] = jeMap[map['reversal_entry_id']];
        final newId = await txn.insert('expense_bills', map);
        expBillMap[oldId] = newId;
      }

      // 22. Expense Lines
      final elList = (tables['expense_lines'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in elList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['bill_id'] = expBillMap[map['bill_id']];
        map['account_id'] = accMap[map['account_id']];
        await txn.insert('expense_lines', map);
      }

      // 23. Vendor Payments
      final vpList = (tables['vendor_payments'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in vpList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        if (map['vendor_id'] != null) map['vendor_id'] = vendorMap[map['vendor_id']];
        map['paid_from_account_id'] = accMap[map['paid_from_account_id']];
        if (map['journal_entry_id'] != null) map['journal_entry_id'] = jeMap[map['journal_entry_id']];
        if (map['reversal_entry_id'] != null) map['reversal_entry_id'] = jeMap[map['reversal_entry_id']];
        await txn.insert('vendor_payments', map);
      }

      // 24. Bank Accounts
      final baList = (tables['bank_accounts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in baList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['account_id'] = accMap[map['account_id']];
        final newId = await txn.insert('bank_accounts', map);
        bankAccMap[oldId] = newId;
      }

      // 25. Fixed Deposits
      final fdList = (tables['fixed_deposits'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in fdList) {
        final oldId = r['id'] as int;
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['account_id'] = accMap[map['account_id']];
        final newId = await txn.insert('fixed_deposits', map);
        fdMap[oldId] = newId;
      }

      // 26. FD Transactions
      final fdtList = (tables['fd_transactions'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in fdtList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        map['fd_id'] = fdMap[map['fd_id']];
        if (map['fy_id'] != null) map['fy_id'] = fyMap[map['fy_id']];
        if (map['bank_cash_account_id'] != null) map['bank_cash_account_id'] = accMap[map['bank_cash_account_id']];
        if (map['journal_entry_id'] != null) map['journal_entry_id'] = jeMap[map['journal_entry_id']];
        if (map['reversal_entry_id'] != null) map['reversal_entry_id'] = jeMap[map['reversal_entry_id']];
        await txn.insert('fd_transactions', map);
      }

      // 27. Settings
      final setList = (tables['society_settings'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in setList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        await txn.insert('society_settings', map);
      }

      // 28. Document Footers
      final dfList = (tables['document_footers'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final r in dfList) {
        final map = Map<String, dynamic>.from(r);
        map.remove('id');
        map['society_id'] = newSocId;
        await txn.insert('document_footers', map);
      }

      // Audit Log
      await txn.insert('audit_log', {
        'society_id': newSocId,
        'action': 'restore_from_backup',
        'entity_type': 'societies',
        'entity_id': newSocId,
        'summary': 'Restored from backup of ${preview.originalSocietyName} (exported at ${preview.exportedAt})',
        'created_at': DateTime.now().toIso8601String(),
      });

      return newSocId;
    });
  }
}

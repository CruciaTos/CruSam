import 'package:excel/excel.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/money.dart';
import '../../core/society_date.dart';
import '../../core/society_exception.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/member_models.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/member_repository.dart';
import '../ledger/ledger_service.dart';
import '../members/member_service.dart';
import '../billing/billing_service.dart';
import '../collections/collection_service.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/bank_models.dart';
import '../expenses/expense_service.dart';
import '../bank/bank_service.dart';

class ImportResult {
  final int count;
  final String message;

  const ImportResult({required this.count, required this.message});
}

class ImportService {
  final Database db;
  final MemberService memberService;
  final LedgerService ledgerService;
  final BillingService billingService;
  final CollectionService collectionService;
  final ExpenseService expenseService;
  final MemberRepository _memberRepo;
  final LedgerRepository _ledgerRepo;

  ImportService(
    this.db, {
    required this.memberService,
    required this.ledgerService,
    required this.billingService,
    CollectionService? collectionService,
    ExpenseService? expenseService,
  })  : collectionService = collectionService ?? CollectionService(db, ledgerService: ledgerService),
        expenseService = expenseService ?? ExpenseService(db, ledgerService: ledgerService),
        _memberRepo = MemberRepository(db),
        _ledgerRepo = LedgerRepository(db);

  // -------------------------------------------------------------
  // Parse Helpers
  // -------------------------------------------------------------

  List<Map<String, String>> parseCsv(String csvText) {
    final lines = csvText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) return [];

    final headers = _parseLine(lines.first).map((h) => h.trim().toLowerCase()).toList();
    final result = <Map<String, String>>[];

    for (var i = 1; i < lines.length; i++) {
      final values = _parseLine(lines[i]);
      final row = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        row[headers[j]] = j < values.length ? values[j].trim() : '';
      }
      result.add(row);
    }

    return result;
  }

  List<String> _parseLine(String line) {
    final result = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(sb.toString());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    result.add(sb.toString());
    return result;
  }

  List<Map<String, String>> parseExcelBytes(List<int> bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    final table = excel.tables.values.first;
    if (table.rows.isEmpty) return [];

    final headerRow = table.rows.first;
    final headers = headerRow
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();

    final result = <Map<String, String>>[];
    for (var i = 1; i < table.rows.length; i++) {
      final rowCells = table.rows[i];
      if (rowCells.every((c) => c == null || c.value == null || c.value.toString().trim().isEmpty)) {
        continue;
      }
      final row = <String, String>{};
      for (var j = 0; j < headers.length; j++) {
        if (headers[j].isEmpty) continue;
        final cellVal = j < rowCells.length ? rowCells[j]?.value?.toString().trim() ?? '' : '';
        row[headers[j]] = cellVal;
      }
      result.add(row);
    }
    return result;
  }

  String _cleanKey(String key) {
    return key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String? _findVal(Map<String, String> row, List<String> aliases) {
    for (final a in aliases) {
      final cleanAlias = _cleanKey(a);
      for (final entry in row.entries) {
        if (_cleanKey(entry.key) == cleanAlias) {
          if (entry.value.trim().isNotEmpty) return entry.value.trim();
        }
      }
    }
    return null;
  }

  String _requireVal(Map<String, String> row, List<String> aliases, String fieldName, int rowIndex) {
    final v = _findVal(row, aliases);
    if (v == null || v.isEmpty) {
      throw SocietyException('import_validation', 'Row $rowIndex: Missing required field "$fieldName"');
    }
    return v;
  }

  String _normalizeDate(String rawDate, int rowIndex) {
    final trimmed = rawDate.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return trimmed;
    }
    final parsed = parseDisplayDate(trimmed);
    if (parsed != null) return parsed;
    throw SocietyException('import_validation', 'Row $rowIndex: Invalid date format "$rawDate" (expected YYYY-MM-DD or DD/MM/YYYY)');
  }

  // -------------------------------------------------------------
  // 1. Units Import
  // Columns: Block*, Unit No*, Unit Type*, Area 1, Area 2, Floor, Occupancy*, Active
  // -------------------------------------------------------------

  Future<ImportResult> importUnits(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_validation', 'No data rows found to import');
    }

    return db.transaction((txn) async {
      // Load blocks and types caches
      final existingBlocks = await txn.query('blocks', where: 'society_id = ?', whereArgs: [societyId]);
      final blockMap = <String, int>{};
      for (final b in existingBlocks) {
        blockMap[(b['name'] as String).toLowerCase().trim()] = b['id'] as int;
      }

      final existingTypes = await txn.query('unit_types', where: 'society_id = ?', whereArgs: [societyId]);
      final typeMap = <String, int>{};
      for (final t in existingTypes) {
        typeMap[(t['name'] as String).toLowerCase().trim()] = t['id'] as int;
      }

      var imported = 0;

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final rowNum = i + 1;

        final blockName = _requireVal(row, ['block', 'blockname', 'wing'], 'Block', rowNum);
        final unitNo = _requireVal(row, ['unitno', 'unit', 'flatno', 'doorno'], 'Unit No', rowNum);
        final typeName = _requireVal(row, ['unittype', 'type'], 'Unit Type', rowNum);
        final rawOccupancy = _findVal(row, ['occupancy', 'occupancystatus']) ?? 'owner_occupied';

        // Auto-create block if missing
        int blockId;
        final blockKey = blockName.toLowerCase().trim();
        if (blockMap.containsKey(blockKey)) {
          blockId = blockMap[blockKey]!;
        } else {
          blockId = await txn.insert('blocks', {
            'society_id': societyId,
            'name': blockName.trim(),
            'is_active': 1,
          });
          blockMap[blockKey] = blockId;
        }

        // Auto-create unit type if missing
        int typeId;
        final typeKey = typeName.toLowerCase().trim();
        if (typeMap.containsKey(typeKey)) {
          typeId = typeMap[typeKey]!;
        } else {
          typeId = await txn.insert('unit_types', {
            'society_id': societyId,
            'name': typeName.trim(),
            'sort_order': typeMap.length,
            'is_active': 1,
          });
          typeMap[typeKey] = typeId;
        }

        final area1Str = _findVal(row, ['area1', 'area', 'builtuparea', 'chargeablearea']);
        final area1Centi = area1Str != null ? (parseAreaToCenti(area1Str) ?? 0) : 0;

        final area2Str = _findVal(row, ['area2', 'carpetarea']);
        final area2Centi = area2Str != null ? (parseAreaToCenti(area2Str) ?? 0) : 0;

        final floor = _findVal(row, ['floor', 'floorno']);

        String occupancy = 'owner_occupied';
        final occNorm = rawOccupancy.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if (occNorm.contains('tenant')) {
          occupancy = 'tenanted';
        } else if (occNorm.contains('vacant')) {
          occupancy = 'vacant';
        }

        final activeStr = _findVal(row, ['active', 'isactive']);
        final isActive = activeStr == null || !['0', 'no', 'false', 'n'].contains(activeStr.toLowerCase().trim());

        // Check duplicate within block
        final dup = await txn.query(
          'units',
          where: 'society_id = ? AND block_id = ? AND unit_no = ?',
          whereArgs: [societyId, blockId, unitNo.trim()],
        );
        if (dup.isNotEmpty) {
          throw SocietyException('duplicate', 'Row $rowNum: Unit "$unitNo" already exists in Block "$blockName"');
        }

        await txn.insert('units', {
          'society_id': societyId,
          'block_id': blockId,
          'unit_no': unitNo.trim(),
          'unit_type_id': typeId,
          'area1_centi': area1Centi,
          'area2_centi': area2Centi,
          'floor_no': floor?.trim(),
          'occupancy': occupancy,
          'is_active': isActive ? 1 : 0,
        });

        imported++;
      }

      return ImportResult(count: imported, message: 'Successfully imported $imported units');
    });
  }

  // -------------------------------------------------------------
  // 2. People Import
  // Columns: Block*, Unit No*, Full Name*, Role*, Primary Contact, Bill To, Phone, Email, Alternate Email, PAN, GSTIN, Address, Share Certificate No, From Date*
  // -------------------------------------------------------------

  Future<ImportResult> importPeople(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_validation', 'No data rows found to import');
    }

    return db.transaction((txn) async {
      var imported = 0;

      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        final rowNum = i + 1;

        final blockName = _requireVal(row, ['block', 'blockname', 'wing'], 'Block', rowNum);
        final unitNo = _requireVal(row, ['unitno', 'unit', 'flatno'], 'Unit No', rowNum);
        final fullName = _requireVal(row, ['fullname', 'name', 'membername'], 'Full Name', rowNum);
        final rawRole = _requireVal(row, ['role'], 'Role', rowNum);
        final rawFromDate = _requireVal(row, ['fromdate', 'startdate', 'date'], 'From Date', rowNum);
        final fromDate = _normalizeDate(rawFromDate, rowNum);

        // Find Unit
        final unitRows = await txn.rawQuery('''
          SELECT u.id
          FROM units u
          JOIN blocks b ON u.block_id = b.id
          WHERE u.society_id = ? AND LOWER(b.name) = ? AND LOWER(u.unit_no) = ?
          LIMIT 1
        ''', [societyId, blockName.toLowerCase().trim(), unitNo.toLowerCase().trim()]);

        if (unitRows.isEmpty) {
          throw SocietyException('not_found', 'Row $rowNum: Unit "$blockName-$unitNo" not found');
        }
        final unitId = unitRows.first['id'] as int;

        // Normalize Role
        String role = 'owner';
        final rClean = rawRole.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if (rClean.contains('coowner')) {
          role = 'co_owner';
        } else if (rClean.contains('tenant')) {
          role = 'tenant';
        } else if (rClean.contains('nominee')) {
          role = 'nominee';
        }

        final phone = _findVal(row, ['phone', 'mobile', 'phoneno', 'contact']);
        final email = _findVal(row, ['email', 'emailid', 'mail']);
        final altEmail = _findVal(row, ['alternateemail', 'altemail']);
        final pan = _findVal(row, ['pan', 'panno']);
        final gstin = _findVal(row, ['gstin', 'gst']);
        final address = _findVal(row, ['address']);
        final shareCert = _findVal(row, ['sharecertificateno', 'sharecertificate', 'sharecertno']);

        final isPrimaryStr = _findVal(row, ['primarycontact', 'isprimary', 'primary']);
        final isPrimary = isPrimaryStr != null && ['1', 'yes', 'true', 'y'].contains(isPrimaryStr.toLowerCase().trim());

        final isBillToStr = _findVal(row, ['billto', 'isbillto', 'billingcontact']);
        final isBillTo = isBillToStr != null && ['1', 'yes', 'true', 'y'].contains(isBillToStr.toLowerCase().trim());

        // Check if person exists or insert
        int personId;
        final personRows = await txn.query(
          'people',
          where: 'society_id = ? AND LOWER(full_name) = ?',
          whereArgs: [societyId, fullName.toLowerCase().trim()],
          limit: 1,
        );

        if (personRows.isNotEmpty) {
          personId = personRows.first['id'] as int;
        } else {
          personId = await txn.insert('people', {
            'society_id': societyId,
            'full_name': fullName.trim(),
            'phone': phone?.trim(),
            'email': email?.trim(),
            'alternate_email': altEmail?.trim(),
            'pan': pan?.trim().toUpperCase(),
            'gstin': gstin?.trim().toUpperCase(),
            'address': address?.trim(),
            'is_active': 1,
          });
        }

        if (isPrimary) {
          await _memberRepo.clearPrimaryContact(txn, unitId);
        }
        if (isBillTo) {
          await _memberRepo.clearBillTo(txn, unitId);
        }

        await _memberRepo.insertUnitPerson(
          txn,
          societyId,
          UnitPersonDraft(
            unitId: unitId,
            personId: personId,
            role: role,
            isPrimaryContact: isPrimary,
            isBillTo: isBillTo,
            shareCertificateNo: shareCert?.trim(),
            fromDate: fromDate,
          ),
        );

        imported++;
      }

      return ImportResult(count: imported, message: 'Successfully imported $imported member assignments');
    });
  }

  // -------------------------------------------------------------
  // 3. Opening Units Import
  // Columns: Block*, Unit No*, Debit, Credit, As Of*, Narration
  // -------------------------------------------------------------

  Future<ImportResult> importOpeningUnits(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_validation', 'No data rows found to import');
    }

    final drafts = <UnitOpeningBalanceDraft>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;

      final blockName = _requireVal(row, ['block', 'blockname', 'wing'], 'Block', rowNum);
      final unitNo = _requireVal(row, ['unitno', 'unit', 'flatno'], 'Unit No', rowNum);
      final rawAsOf = _requireVal(row, ['asof', 'asofdate', 'date'], 'As Of', rowNum);
      final asOfDate = _normalizeDate(rawAsOf, rowNum);

      final unitRows = await db.rawQuery('''
        SELECT u.id
        FROM units u
        JOIN blocks b ON u.block_id = b.id
        WHERE u.society_id = ? AND LOWER(b.name) = ? AND LOWER(u.unit_no) = ?
        LIMIT 1
      ''', [societyId, blockName.toLowerCase().trim(), unitNo.toLowerCase().trim()]);

      if (unitRows.isEmpty) {
        throw SocietyException('not_found', 'Row $rowNum: Unit "$blockName-$unitNo" not found');
      }
      final unitId = unitRows.first['id'] as int;

      final debStr = _findVal(row, ['debit', 'dr']) ?? '0';
      final credStr = _findVal(row, ['credit', 'cr']) ?? '0';

      final debPaise = parseRupeesToPaise(debStr) ?? 0;
      final credPaise = parseRupeesToPaise(credStr) ?? 0;
      final narration = _findVal(row, ['narration', 'note', 'remarks']);

      if (debPaise > 0 || credPaise > 0) {
        drafts.add(UnitOpeningBalanceDraft(
          unitId: unitId,
          debitPaise: debPaise,
          creditPaise: credPaise,
          asOfDate: asOfDate,
          narration: narration,
        ));
      }
    }

    await memberService.saveUnitOpeningBalances(societyId, drafts);
    return ImportResult(count: drafts.length, message: 'Successfully imported ${drafts.length} unit opening balances');
  }

  // -------------------------------------------------------------
  // 4. Opening Ledger Import
  // Columns: Account Code*, Debit, Credit, As Of*, Narration
  // -------------------------------------------------------------

  Future<ImportResult> importOpeningLedger(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_validation', 'No data rows found to import');
    }

    final drafts = <OpeningBalanceDraft>[];

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;

      final accCode = _requireVal(row, ['accountcode', 'code', 'account'], 'Account Code', rowNum);
      final rawAsOf = _requireVal(row, ['asof', 'asofdate', 'date'], 'As Of', rowNum);
      final asOfDate = _normalizeDate(rawAsOf, rowNum);

      final acc = await _ledgerRepo.getAccountByCode(db, societyId, accCode.trim());
      if (acc == null) {
        throw SocietyException('not_found', 'Row $rowNum: Account code "$accCode" not found');
      }

      final debStr = _findVal(row, ['debit', 'dr']) ?? '0';
      final credStr = _findVal(row, ['credit', 'cr']) ?? '0';

      final debPaise = parseRupeesToPaise(debStr) ?? 0;
      final credPaise = parseRupeesToPaise(credStr) ?? 0;
      final narration = _findVal(row, ['narration', 'note', 'remarks']);

      if (debPaise > 0 || credPaise > 0) {
        drafts.add(OpeningBalanceDraft(
          accountId: acc.id,
          debitPaise: debPaise,
          creditPaise: credPaise,
          asOfDate: asOfDate,
          narration: narration,
        ));
      }
    }

    await ledgerService.saveOpeningBalances(societyId, drafts);
    return ImportResult(count: drafts.length, message: 'Successfully imported ${drafts.length} account opening balances');
  }

  // -------------------------------------------------------------
  // 5. Meter Readings Import
  // Columns: Block*, Unit*, Meter Type*, Period From*, Period To*, Reading Date*, Reading*
  // -------------------------------------------------------------

  Future<ImportResult> importMeterReadings(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_validation', 'No data rows found to import');
    }

    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 1;

      final blockName = _requireVal(row, ['block', 'blockname'], 'Block', rowNum);
      final unitNo = _requireVal(row, ['unit', 'unitno', 'flat'], 'Unit', rowNum);
      final meterTypeName = _requireVal(row, ['metertype', 'meter', 'metertypename'], 'Meter Type', rowNum);

      final rawFrom = _requireVal(row, ['periodfrom', 'from', 'period_from'], 'Period From', rowNum);
      final periodFrom = _normalizeDate(rawFrom, rowNum);

      final rawTo = _requireVal(row, ['periodto', 'to', 'period_to'], 'Period To', rowNum);
      final periodTo = _normalizeDate(rawTo, rowNum);

      final rawDate = _findVal(row, ['readingdate', 'date', 'reading_date']) ?? rawTo;
      final readingDate = _normalizeDate(rawDate, rowNum);

      final readingStr = _requireVal(row, ['reading', 'readingmilli', 'currentreading', 'units'], 'Reading', rowNum);
      final readingVal = double.tryParse(readingStr);
      if (readingVal == null) {
        throw SocietyException('import_validation', 'Row $rowNum: Invalid reading value "$readingStr"');
      }
      final readingMilli = (readingVal * 1000).round();

      // Find unit
      final unitRows = await db.rawQuery('''
        SELECT u.id 
        FROM units u
        JOIN blocks b ON u.block_id = b.id
        WHERE u.society_id = ? AND LOWER(b.name) = ? AND LOWER(u.unit_no) = ?
        LIMIT 1
      ''', [societyId, blockName.toLowerCase().trim(), unitNo.toLowerCase().trim()]);

      if (unitRows.isEmpty) {
        throw SocietyException('not_found', 'Row $rowNum: Unit "$blockName-$unitNo" not found');
      }
      final unitId = unitRows.first['id'] as int;

      // Find meter for this unit and meter type
      final meterRows = await db.rawQuery('''
        SELECT m.id
        FROM meters m
        JOIN meter_types mt ON m.meter_type_id = mt.id
        WHERE m.society_id = ? AND m.unit_id = ? AND LOWER(mt.name) = ?
        LIMIT 1
      ''', [societyId, unitId, meterTypeName.toLowerCase().trim()]);

      if (meterRows.isEmpty) {
        throw SocietyException('not_found', 'Row $rowNum: No meter of type "$meterTypeName" found for unit "$blockName-$unitNo"');
      }
      final meterId = meterRows.first['id'] as int;

      await billingService.addMeterReading(
        societyId,
        meterId,
        periodFrom,
        periodTo,
        readingDate,
        readingMilli,
      );
      count++;
    }

    return ImportResult(count: count, message: 'Successfully imported $count meter readings');
  }

  // -------------------------------------------------------------
  // Member Receipts Import
  // -------------------------------------------------------------

  Future<ImportResult> importReceipts(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('import_empty', 'File contains no data rows');
    }

    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2;

      final blockName = _findVal(row, ['block', 'blockname', 'wing']) ?? '';
      final unitNo = _requireVal(row, ['unit', 'unitno', 'flat', 'flatno'], 'Unit', rowNum);
      final dateRaw = _requireVal(row, ['date', 'receiptdate', 'receipt_date'], 'Date', rowNum);
      final receiptDate = _normalizeDate(dateRaw, rowNum);

      final amtStr = _requireVal(row, ['amount', 'amountpaise', 'total'], 'Amount', rowNum);
      final amtPaise = parseRupeesToPaise(amtStr);
      if (amtPaise == null || amtPaise <= 0) {
        throw SocietyException('import_validation', 'Row $rowNum: Invalid amount "$amtStr"');
      }

      final tdsStr = _findVal(row, ['tds', 'tdspaise']);
      final tdsPaise = tdsStr != null ? (parseRupeesToPaise(tdsStr) ?? 0) : 0;

      final mode = (_findVal(row, ['mode', 'paymentmode', 'type']) ?? 'bank').toLowerCase().trim();
      final instNo = _findVal(row, ['instrumentno', 'chequeno', 'refno', 'instrument_no']);
      final instBank = _findVal(row, ['bank', 'bankname', 'instrumentbank']);
      final narration = _findVal(row, ['notes', 'narration', 'remarks']);

      final whereUnit = blockName.isNotEmpty
          ? 'u.society_id = ? AND LOWER(b.name) = ? AND LOWER(u.unit_no) = ?'
          : 'u.society_id = ? AND LOWER(u.unit_no) = ?';
      final argsUnit = blockName.isNotEmpty
          ? [societyId, blockName.toLowerCase().trim(), unitNo.toLowerCase().trim()]
          : [societyId, unitNo.toLowerCase().trim()];

      final unitRows = await db.rawQuery('''
        SELECT u.id,
          (SELECT p.full_name FROM unit_people up JOIN people p ON up.person_id = p.id WHERE up.unit_id = u.id AND up.is_bill_to = 1 AND up.to_date IS NULL LIMIT 1) as bill_to_name
        FROM units u
        JOIN blocks b ON u.block_id = b.id
        WHERE $whereUnit
        LIMIT 1
      ''', argsUnit);

      if (unitRows.isEmpty) {
        throw SocietyException('not_found', 'Row $rowNum: Unit "$blockName $unitNo" not found');
      }
      final unitId = unitRows.first['id'] as int;
      final defaultPayer = unitRows.first['bill_to_name'] as String? ?? 'Occupant';
      final payerName = _findVal(row, ['payer', 'payername', 'member', 'name']) ?? defaultPayer;

      await collectionService.createReceipt(
        societyId,
        ReceiptDraft(
          unitId: unitId,
          payerName: payerName,
          receiptDate: receiptDate,
          amountPaise: amtPaise,
          tdsPaise: tdsPaise,
          mode: mode == 'cash' ? 'cash' : 'cheque',
          instrumentNo: instNo,
          instrumentBank: instBank,
          narration: narration,
        ),
      );
      count++;
    }

    return ImportResult(count: count, message: 'Successfully imported $count receipts');
  }

  // -------------------------------------------------------------
  // Vendor Import
  // -------------------------------------------------------------

  Future<ImportResult> importVendors(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('validation', 'Import file contains no data rows');
    }

    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2;

      final name = _findVal(row, ['name', 'vendor', 'vendorname']);
      if (name == null || name.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Vendor name is required');
      }

      final code = _findVal(row, ['code', 'vendorcode']);
      final contact = _findVal(row, ['contact', 'contactname', 'person']);
      final phone = _findVal(row, ['phone', 'mobile']);
      final email = _findVal(row, ['email']);
      final pan = _findVal(row, ['pan']);
      final gstin = _findVal(row, ['gstin', 'gst']);
      final stateCode = _findVal(row, ['state', 'statecode']);

      await expenseService.saveVendor(
        societyId,
        VendorDraft(
          name: name,
          vendorCode: code,
          contactName: contact,
          phone: phone,
          email: email,
          pan: pan,
          gstin: gstin,
          stateCode: stateCode,
        ),
      );
      count++;
    }

    return ImportResult(count: count, message: 'Successfully imported $count vendors');
  }

  // -------------------------------------------------------------
  // Expense Bill Import
  // -------------------------------------------------------------

  Future<ImportResult> importExpenseBills(int societyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('validation', 'Import file contains no data rows');
    }

    var count = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2;

      final vendorRef = _findVal(row, ['vendor', 'vendorname', 'vendorcode']);
      if (vendorRef == null || vendorRef.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Vendor is required');
      }

      final billNo = _findVal(row, ['billno', 'invoiceno', 'vendorbillno']);
      if (billNo == null || billNo.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Vendor bill number is required');
      }

      final billDateStr = _findVal(row, ['billdate', 'date']);
      final billDate = billDateStr != null ? _normalizeDate(billDateStr, rowNum) : DateTime.now().toIso8601String().substring(0, 10);
      final postDateStr = _findVal(row, ['postdate', 'postingdate']);
      final postDate = postDateStr != null ? _normalizeDate(postDateStr, rowNum) : billDate;

      final accRef = _findVal(row, ['account', 'accountcode', 'expenseaccount']);
      if (accRef == null || accRef.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Expense account is required');
      }

      final amtStr = _findVal(row, ['amount', 'subtotal', 'total']);
      final amtPaise = amtStr != null ? parseRupeesToPaise(amtStr) : null;
      if (amtPaise == null || amtPaise <= 0) {
        throw SocietyException('validation', 'Row $rowNum: Valid amount is required');
      }

      // Find vendor
      final vendors = await expenseService.listVendors(societyId, filter: VendorFilter(search: vendorRef));
      if (vendors.isEmpty) {
        throw SocietyException('not_found', 'Row $rowNum: Vendor "$vendorRef" not found');
      }
      final vendor = vendors.first.vendor;

      // Find account
      final acc = await ledgerService.getAccountByCode(societyId, accRef);
      if (acc == null) {
        throw SocietyException('not_found', 'Row $rowNum: Account code "$accRef" not found');
      }

      final gstRateStr = _findVal(row, ['gst', 'gstrate', 'gstratebp']);
      final gstRateBp = gstRateStr != null ? (int.tryParse(gstRateStr) ?? 0) : 0;

      final narration = _findVal(row, ['notes', 'narration', 'description']);

      await expenseService.postExpenseBill(
        societyId,
        ExpenseBillDraft(
          vendorId: vendor.id,
          vendorBillNo: billNo,
          billDate: billDate,
          postDate: postDate,
          lines: [
            ExpenseLineDraft(
              accountId: acc.id,
              description: narration ?? 'Imported bill $billNo',
              amountPaise: amtPaise,
              gstRateBp: gstRateBp,
            ),
          ],
          narration: narration,
        ),
      );
      count++;
    }

    return ImportResult(count: count, message: 'Successfully imported $count expense bills');
  }

  // -------------------------------------------------------------
  // Budget Import
  // -------------------------------------------------------------

  Future<ImportResult> importBudgets(int societyId, int fyId, List<Map<String, String>> rows) async {
    if (rows.isEmpty) {
      throw const SocietyException('validation', 'Import file contains no data rows');
    }

    final budgetDrafts = <BudgetDraft>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2;

      final accCode = _findVal(row, ['account', 'accountcode', 'code']);
      if (accCode == null || accCode.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Account code is required');
      }

      final amtStr = _findVal(row, ['amount', 'budget', 'budgetamount']);
      final amtPaise = amtStr != null ? parseRupeesToPaise(amtStr) : null;
      if (amtPaise == null || amtPaise < 0) {
        throw SocietyException('validation', 'Row $rowNum: Valid budget amount is required');
      }

      final acc = await ledgerService.getAccountByCode(societyId, accCode);
      if (acc == null) {
        throw SocietyException('not_found', 'Row $rowNum: Account code "$accCode" not found');
      }

      budgetDrafts.add(BudgetDraft(accountId: acc.id, amountPaise: amtPaise));
    }

    await expenseService.saveBudget(societyId, fyId, budgetDrafts);
    return ImportResult(count: budgetDrafts.length, message: 'Successfully imported ${budgetDrafts.length} budget items');
  }

  // -------------------------------------------------------------
  // Bank Statement Import
  // Columns: Date*, Description, Reference, Withdrawal, Deposit, Balance
  // -------------------------------------------------------------
  Future<ImportResult> importBankStatement(
    int societyId,
    int bankAccountId,
    String fileName,
    List<Map<String, String>> rows, {
    BankService? bankService,
  }) async {
    if (rows.isEmpty) {
      throw const SocietyException('validation', 'Import file contains no data rows');
    }

    final statementLines = <StatementLineDraft>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2;

      final date = _findVal(row, ['date', 'txn_date', 'txndate', 'entry_date']);
      if (date == null || date.isEmpty) {
        throw SocietyException('validation', 'Row $rowNum: Date is required');
      }
      final desc = _findVal(row, ['description', 'particulars', 'narration', 'desc']);
      final ref = _findVal(row, ['reference', 'ref', 'chq_no', 'cheque_no', 'ref_no']);

      final wStr = _findVal(row, ['withdrawal', 'debit', 'dr']);
      final dStr = _findVal(row, ['deposit', 'credit', 'cr']);
      final bStr = _findVal(row, ['balance', 'closing_balance']);

      final withdrawalPaise = (wStr != null && wStr.isNotEmpty) ? (parseRupeesToPaise(wStr) ?? 0) : 0;
      final depositPaise = (dStr != null && dStr.isNotEmpty) ? (parseRupeesToPaise(dStr) ?? 0) : 0;
      final balancePaise = (bStr != null && bStr.isNotEmpty) ? parseRupeesToPaise(bStr) : null;

      if (withdrawalPaise == 0 && depositPaise == 0) {
        throw SocietyException('import_validation', 'Row $rowNum: Either Withdrawal or Deposit amount must be positive');
      }

      statementLines.add(StatementLineDraft(
        date: date,
        description: desc,
        reference: ref,
        withdrawalPaise: withdrawalPaise,
        depositPaise: depositPaise,
        balancePaise: balancePaise,
      ));
    }

    final bService = bankService ?? BankService(db, ledgerService: ledgerService);
    await bService.importStatement(societyId, bankAccountId, fileName, statementLines);

    return ImportResult(
      count: statementLines.length,
      message: 'Successfully imported ${statementLines.length} statement lines',
    );
  }
}

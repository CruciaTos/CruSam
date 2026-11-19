import 'package:sqflite/sqflite.dart';

import '../../core/society_exception.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../data/repositories/member_repository.dart';
import '../../data/repositories/society_repository.dart';
import '../ledger/ledger_service.dart';

class MemberService {
  final Database db;
  final MemberRepository _repo;
  final SocietyRepository _socRepo;
  final LedgerService ledgerService;

  MemberService(this.db, {required this.ledgerService})
      : _repo = MemberRepository(db),
        _socRepo = SocietyRepository(db);

  // -------------------------------------------------------------
  // Blocks & Unit Types
  // -------------------------------------------------------------

  Future<List<Block>> listBlocks(int societyId, {bool includeInactive = false}) {
    return _repo.listBlocks(societyId, includeInactive: includeInactive);
  }

  Future<int> createBlock(int societyId, BlockDraft draft) async {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Block name is required');
    }
    return db.transaction((txn) async {
      final existing = await txn.query(
        'blocks',
        where: 'society_id = ? AND name = ?',
        whereArgs: [societyId, draft.name.trim()],
      );
      if (existing.isNotEmpty) {
        throw SocietyException('duplicate', 'Block "${draft.name.trim()}" already exists');
      }
      return _repo.insertBlock(txn, societyId, draft);
    });
  }

  Future<void> updateBlock(int societyId, int blockId, BlockDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Block name is required');
    }
    return db.transaction((txn) => _repo.updateBlock(txn, societyId, blockId, draft));
  }

  Future<List<UnitType>> listUnitTypes(int societyId, {bool includeInactive = false}) {
    return _repo.listUnitTypes(societyId, includeInactive: includeInactive);
  }

  Future<int> createUnitType(int societyId, UnitTypeDraft draft) async {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Unit type name is required');
    }
    return db.transaction((txn) async {
      final existing = await txn.query(
        'unit_types',
        where: 'society_id = ? AND name = ?',
        whereArgs: [societyId, draft.name.trim()],
      );
      if (existing.isNotEmpty) {
        throw SocietyException('duplicate', 'Unit type "${draft.name.trim()}" already exists');
      }
      return _repo.insertUnitType(txn, societyId, draft);
    });
  }

  Future<void> updateUnitType(int societyId, int typeId, UnitTypeDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Unit type name is required');
    }
    return db.transaction((txn) => _repo.updateUnitType(txn, societyId, typeId, draft));
  }

  // -------------------------------------------------------------
  // Units
  // -------------------------------------------------------------

  Future<PageResult<UnitRow>> listUnits(
    int societyId, {
    int? blockId,
    int? unitTypeId,
    String? occupancy,
    String? search,
    bool includeInactive = false,
    PageRequest page = const PageRequest(),
  }) {
    return _repo.listUnits(
      societyId,
      blockId: blockId,
      unitTypeId: unitTypeId,
      occupancy: occupancy,
      search: search,
      includeInactive: includeInactive,
      page: page,
    );
  }

  Future<UnitRow?> getUnit(int unitId) {
    return _repo.getUnit(db, unitId);
  }

  Future<int> createUnit(int societyId, UnitDraft draft) async {
    if (draft.unitNo.trim().isEmpty) {
      throw const SocietyException('validation', 'Unit number is required');
    }
    return db.transaction((txn) async {
      final existing = await txn.query(
        'units',
        where: 'society_id = ? AND block_id = ? AND unit_no = ?',
        whereArgs: [societyId, draft.blockId, draft.unitNo.trim()],
      );
      if (existing.isNotEmpty) {
        throw SocietyException('duplicate', 'Unit "${draft.unitNo.trim()}" already exists in this block');
      }
      final id = await _repo.insertUnit(txn, societyId, draft);
      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'unit',
        id,
        'Created unit ${draft.unitNo}',
      );
      return id;
    });
  }

  Future<void> updateUnit(int societyId, int unitId, UnitDraft draft) {
    if (draft.unitNo.trim().isEmpty) {
      throw const SocietyException('validation', 'Unit number is required');
    }
    return db.transaction((txn) => _repo.updateUnit(txn, societyId, unitId, draft));
  }

  Future<void> setUnitActive(int societyId, int unitId, bool active) async {
    return db.transaction((txn) async {
      if (!active) {
        // Can deactivate, but verify
      }
      return _repo.setUnitActive(txn, societyId, unitId, active);
    });
  }

  // -------------------------------------------------------------
  // People
  // -------------------------------------------------------------

  Future<PageResult<Person>> listPeople(
    int societyId, {
    String? search,
    bool includeInactive = false,
    PageRequest page = const PageRequest(),
  }) {
    return _repo.listPeople(societyId, search: search, includeInactive: includeInactive, page: page);
  }

  Future<Person?> getPerson(int personId) {
    return _repo.getPerson(db, personId);
  }

  Future<int> createPerson(int societyId, PersonDraft draft) async {
    if (draft.fullName.trim().isEmpty) {
      throw const SocietyException('validation', 'Full name is required');
    }
    return db.transaction((txn) async {
      final id = await _repo.insertPerson(txn, societyId, draft);
      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'person',
        id,
        'Created person ${draft.fullName}',
      );
      return id;
    });
  }

  Future<void> updatePerson(int societyId, int personId, PersonDraft draft) {
    if (draft.fullName.trim().isEmpty) {
      throw const SocietyException('validation', 'Full name is required');
    }
    return db.transaction((txn) => _repo.updatePerson(txn, societyId, personId, draft));
  }

  Future<void> setPersonActive(int societyId, int personId, bool active) {
    return db.transaction((txn) => _repo.setPersonActive(txn, societyId, personId, active));
  }

  // -------------------------------------------------------------
  // Unit-People Assignments & Ownership Transfer
  // -------------------------------------------------------------

  Future<List<UnitPerson>> listUnitPeople(int societyId, int unitId, {bool currentOnly = false}) {
    return _repo.listUnitPeople(db, societyId, unitId, currentOnly: currentOnly);
  }

  Future<int> assignPerson(int societyId, UnitPersonDraft draft) async {
    return db.transaction((txn) async {
      final unit = await _repo.getUnit(txn, draft.unitId);
      if (unit == null || unit.societyId != societyId) {
        throw SocietyException('wrong_society', 'Unit does not belong to this society');
      }

      final person = await _repo.getPerson(txn, draft.personId);
      if (person == null || person.societyId != societyId) {
        throw SocietyException('wrong_society', 'Person does not belong to this society');
      }

      if (draft.isPrimaryContact && draft.toDate == null) {
        await _repo.clearPrimaryContact(txn, draft.unitId);
      }

      if (draft.isBillTo && draft.toDate == null) {
        await _repo.clearBillTo(txn, draft.unitId);
      }

      final id = await _repo.insertUnitPerson(txn, societyId, draft);
      await _socRepo.insertAudit(
        txn,
        societyId,
        'assign',
        'unit_person',
        id,
        'Assigned ${person.fullName} to unit ${unit.unitNo} as ${draft.role}',
      );
      return id;
    });
  }

  Future<void> endAssignment(int societyId, int assignmentId, String toDate) async {
    return db.transaction((txn) async {
      await _repo.endUnitPerson(txn, assignmentId, toDate);
    });
  }

  Future<int> transferOwnership(int societyId, OwnershipTransferDraft draft) async {
    return db.transaction((txn) async {
      final unit = await _repo.getUnit(txn, draft.unitId);
      if (unit == null || unit.societyId != societyId) {
        throw SocietyException('wrong_society', 'Unit does not belong to this society');
      }

      final person = await _repo.getPerson(txn, draft.newOwnerPersonId);
      if (person == null || person.societyId != societyId) {
        throw SocietyException('wrong_society', 'Person does not belong to this society');
      }

      // 1. End all active owner and co-owner roles for this unit
      await _repo.endActiveRolesForUnit(txn, draft.unitId, draft.transferDate, role: 'owner');
      await _repo.endActiveRolesForUnit(txn, draft.unitId, draft.transferDate, role: 'co_owner');

      // 2. Clear primary contact / bill-to if requested
      if (draft.setAsPrimaryContact) {
        await _repo.clearPrimaryContact(txn, draft.unitId);
      }
      if (draft.setAsBillTo) {
        await _repo.clearBillTo(txn, draft.unitId);
      }

      // 3. Insert new ownership assignment
      final unitPersonDraft = UnitPersonDraft(
        unitId: draft.unitId,
        personId: draft.newOwnerPersonId,
        role: 'owner',
        isPrimaryContact: draft.setAsPrimaryContact,
        isBillTo: draft.setAsBillTo,
        shareCertificateNo: draft.shareCertificateNo,
        fromDate: draft.transferDate,
      );

      final assignmentId = await _repo.insertUnitPerson(txn, societyId, unitPersonDraft);

      await _socRepo.insertAudit(
        txn,
        societyId,
        'transfer',
        'unit_ownership',
        draft.unitId,
        'Transferred ownership of unit ${unit.unitNo} to ${person.fullName}',
      );

      return assignmentId;
    });
  }

  // -------------------------------------------------------------
  // Unit Opening Balances (Task 3.8)
  // -------------------------------------------------------------

  Future<void> saveUnitOpeningBalances(
    int societyId,
    List<UnitOpeningBalanceDraft> drafts,
  ) async {
    if (drafts.isEmpty) return;

    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    final asOfDate = drafts.first.asOfDate;
    final memRecAccId = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');
    final adjAccId = await ledgerService.accountIdForKey(db, societyId, 'opening_adjustment');

    var totalDebit = 0;
    var totalCredit = 0;

    final lines = <JournalLineDraft>[];

    for (final d in drafts) {
      if (d.debitPaise > 0) {
        lines.add(JournalLineDraft(
          accountId: memRecAccId,
          debitPaise: d.debitPaise,
          unitId: d.unitId,
          note: d.narration ?? 'Unit opening balance',
        ));
        totalDebit += d.debitPaise;
      } else if (d.creditPaise > 0) {
        lines.add(JournalLineDraft(
          accountId: memRecAccId,
          creditPaise: d.creditPaise,
          unitId: d.unitId,
          note: d.narration ?? 'Unit opening advance',
        ));
        totalCredit += d.creditPaise;
      }
    }

    if (lines.isEmpty) return;

    // Balance with opening_adjustment
    if (totalDebit > totalCredit) {
      lines.add(JournalLineDraft(
        accountId: adjAccId,
        creditPaise: totalDebit - totalCredit,
        note: 'Unit opening balances difference',
      ));
    } else if (totalCredit > totalDebit) {
      lines.add(JournalLineDraft(
        accountId: adjAccId,
        debitPaise: totalCredit - totalDebit,
        note: 'Unit opening balances difference',
      ));
    }

    final journalDraft = JournalDraft(
      societyId: societyId,
      entryDate: asOfDate,
      sourceType: 'opening',
      narration: 'Unit Opening Balances as of $asOfDate',
      lines: lines,
    );

    await ledgerService.postManual(journalDraft);
  }
}

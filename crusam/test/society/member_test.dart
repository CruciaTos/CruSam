import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/repositories/member_repository.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late Society society;
  late LedgerService ledger;
  late MemberService member;

  late int blockId;
  late int unitTypeId;
  late int unitId;
  late int person1Id;
  late int person2Id;

  setUp(() async {
    db = await createTestDb();
    society = await createTestSociety(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);

    blockId = await member.createBlock(society.id, const BlockDraft(name: 'Tower A'));
    unitTypeId = await member.createUnitType(society.id, const UnitTypeDraft(name: '2BHK'));
    unitId = await member.createUnit(
      society.id,
      UnitDraft(
        blockId: blockId,
        unitNo: '101',
        unitTypeId: unitTypeId,
        area1Centi: 100000,
      ),
    );

    person1Id = await member.createPerson(
      society.id,
      const PersonDraft(fullName: 'Amitabh Sharma', phone: '9876543210', email: 'amitabh@example.com'),
    );

    person2Id = await member.createPerson(
      society.id,
      const PersonDraft(fullName: 'Rajesh Verma', phone: '9876543211', email: 'rajesh@example.com'),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Member & Unit Constraints', () {
    test('enforces at most one active primary contact and one active bill-to per unit', () async {
      // Assign person 1 as primary and bill to
      await member.assignPerson(
        society.id,
        UnitPersonDraft(
          unitId: unitId,
          personId: person1Id,
          role: 'owner',
          isPrimaryContact: true,
          isBillTo: true,
          fromDate: '2026-04-01',
        ),
      );

      var unit = await member.getUnit(unitId);
      expect(unit?.primaryContactName, 'Amitabh Sharma');
      expect(unit?.billToName, 'Amitabh Sharma');

      // Now assign person 2 as primary contact and bill to
      await member.assignPerson(
        society.id,
        UnitPersonDraft(
          unitId: unitId,
          personId: person2Id,
          role: 'tenant',
          isPrimaryContact: true,
          isBillTo: true,
          fromDate: '2026-05-01',
        ),
      );

      unit = await member.getUnit(unitId);
      // Person 2 took over active primary and bill to
      expect(unit?.primaryContactName, 'Rajesh Verma');
      expect(unit?.billToName, 'Rajesh Verma');

      // Check DB level count of active primary contacts for this unit
      final primaryRows = await db.query(
        'unit_people',
        where: 'unit_id = ? AND is_primary_contact = 1 AND to_date IS NULL',
        whereArgs: [unitId],
      );
      expect(primaryRows.length, 1);
      expect(primaryRows.first['person_id'], person2Id);

      final billToRows = await db.query(
        'unit_people',
        where: 'unit_id = ? AND is_bill_to = 1 AND to_date IS NULL',
        whereArgs: [unitId],
      );
      expect(billToRows.length, 1);
      expect(billToRows.first['person_id'], person2Id);
    });

    test('ownership transfer ends old owner assignment and keeps history', () async {
      // Person 1 is owner
      await member.assignPerson(
        society.id,
        UnitPersonDraft(
          unitId: unitId,
          personId: person1Id,
          role: 'owner',
          isPrimaryContact: true,
          isBillTo: true,
          shareCertificateNo: 'SC-001',
          fromDate: '2026-04-01',
        ),
      );

      // Transfer ownership to Person 2 on 2026-06-01
      await member.transferOwnership(
        society.id,
        OwnershipTransferDraft(
          unitId: unitId,
          newOwnerPersonId: person2Id,
          transferDate: '2026-06-01',
          shareCertificateNo: 'SC-002',
          setAsPrimaryContact: true,
          setAsBillTo: true,
        ),
      );

      final people = await member.listUnitPeople(society.id, unitId);
      expect(people.length, 2);

      // Old owner has toDate
      final oldAssignment = people.firstWhere((p) => p.personId == person1Id);
      expect(oldAssignment.toDate, '2026-06-01');
      expect(oldAssignment.isCurrent, isFalse);

      // New owner is current
      final newAssignment = people.firstWhere((p) => p.personId == person2Id);
      expect(newAssignment.fromDate, '2026-06-01');
      expect(newAssignment.toDate, isNull);
      expect(newAssignment.isCurrent, isTrue);
      expect(newAssignment.shareCertificateNo, 'SC-002');
      expect(newAssignment.isPrimaryContact, isTrue);
      expect(newAssignment.isBillTo, isTrue);
    });

    test('detects unit ledger history and prevents deletion', () async {
      final memRecAccId = await getAccountIdBySystemKey(db, society.id, 'members_receivable');
      final maintIncomeAccId = await getAccountIdBySystemKey(db, society.id, 'maintenance_income');

      // Check initially no history
      final hasHistBefore = await MemberRepository(db).hasLedgerHistory(db, unitId);
      expect(hasHistBefore, isFalse);

      // Post journal referencing unit
      await ledger.postManual(JournalDraft(
        societyId: society.id,
        entryDate: '2026-04-15',
        sourceType: 'manual',
        narration: 'Initial dues',
        lines: [
          JournalLineDraft(accountId: memRecAccId, debitPaise: 250000, unitId: unitId),
          JournalLineDraft(accountId: maintIncomeAccId, creditPaise: 250000),
        ],
      ));

      // Now has history
      final hasHistAfter = await MemberRepository(db).hasLedgerHistory(db, unitId);
      expect(hasHistAfter, isTrue);
    });
  });
}

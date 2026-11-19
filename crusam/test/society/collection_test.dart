import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/data/models/ledger_models.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/repositories/collection_repository.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  setUpAll(initTestSupport);

  late Database db;
  late SocietyAdminService admin;
  late LedgerService ledger;
  late MemberService member;
  late BillingService billing;
  late CollectionService collections;
  late CollectionRepository collRepo;

  int societyId = 0;
  int unitId = 0;
  int bankAccountId = 0;

  setUp(() async {
    db = await createTestDatabase();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);
    collections = CollectionService(db, ledgerService: ledger);
    collRepo = CollectionRepository(db);

    societyId = await admin.createSociety(
      const SocietyDraft(
        name: 'Gokuldham Co-op Hsg Soc',
        booksStartDate: '2026-04-01',
        city: 'Mumbai',
      ),
    );

    // Create a bank account
    final groups = await ledger.listGroups(societyId);
    final bankGroup = groups.firstWhere((g) => g.code == '1100');
    bankAccountId = await ledger.createAccount(
      societyId,
      AccountDraft(
        groupId: bankGroup.id,
        code: '1102',
        name: 'HDFC Bank',
        accountKind: 'bank',
      ),
    );

    // Create unit type, block, unit, person
    final utId = await member.createUnitType(
      societyId,
      const UnitTypeDraft(name: '2BHK', sortOrder: 1),
    );
    final bId = await member.createBlock(
      societyId,
      const BlockDraft(name: 'A Wing'),
    );
    unitId = await member.createUnit(
      societyId,
      UnitDraft(
        blockId: bId,
        unitTypeId: utId,
        unitNo: 'A-101',
        area1Centi: 80000,
      ),
    );

    final personId = await member.createPerson(
      societyId,
      const PersonDraft(fullName: 'Jethalal Gada', phone: '9820098200'),
    );
    await member.assignPerson(
      societyId,
      UnitPersonDraft(
        unitId: unitId,
        personId: personId,
        role: 'owner',
        fromDate: '2026-04-01',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('CollectionService', () {
    test('createReceipt posts journal and updates unit statement and dues', () async {
      // 1. Create a manual bill of ₹2,500.00
      final heads = await billing.listChargeHeads(societyId);
      final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

      await billing.createManualBill(
        societyId,
        ManualBillDraft(
          unitId: unitId,
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          lines: [
            BillLineDraft(
              chargeHeadId: maintHead.id,
              description: 'Monthly Maintenance',
              amountPaise: 250000,
              payablePaise: 250000,
            ),
          ],
        ),
      );

      // Verify open dues before receipt
      final duesBefore = await collections.getDuesSummary(societyId);
      expect(duesBefore.length, 1);
      expect(duesBefore.first.netDuePaise, 250000);

      // 2. Pay ₹2,500.00 via cheque
      final receipt = await collections.createReceipt(
        societyId,
        ReceiptDraft(
          unitId: unitId,
          payerName: 'Jethalal Gada',
          receiptDate: '2026-04-15',
          mode: 'cheque',
          bankCashAccountId: bankAccountId,
          instrumentNo: 'CHQ-1001',
          instrumentBank: 'HDFC',
          amountPaise: 250000,
          narration: 'April maintenance payment',
        ),
      );

      expect(receipt.id, isPositive);
      expect(receipt.status, 'posted');
      expect(receipt.amountPaise, 250000);
      expect(receipt.unallocatedPaise, 0);

      // 3. Verify dues after payment
      final duesAfter = await collections.getDuesSummary(societyId);
      expect(duesAfter.first.netDuePaise, 0);

      // 4. Verify unit statement has both Bill and Receipt
      final statement = await collections.getUnitStatement(societyId, unitId);
      expect(statement.length, 2);
      expect(statement[0].docType, 'member_bill');
      expect(statement[0].debitPaise, 250000);
      expect(statement[0].runningBalancePaise, 250000);
      expect(statement[1].docType, 'member_receipt');
      expect(statement[1].creditPaise, 250000);
      expect(statement[1].runningBalancePaise, 0);

      // 5. Verify trial balance is balanced
      final tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);
    });

    test('receipt with excess payment retains advance and allocates later', () async {
      // 1. Pay ₹3,000.00 without an open bill (all goes to advance)
      final receipt = await collections.createReceipt(
        societyId,
        ReceiptDraft(
          unitId: unitId,
          payerName: 'Jethalal Gada',
          receiptDate: '2026-04-05',
          mode: 'neft',
          bankCashAccountId: bankAccountId,
          amountPaise: 300000,
          narration: 'Advance payment',
        ),
      );

      expect(receipt.unallocatedPaise, 300000);

      // 2. Create bill of ₹2,000.00
      final heads = await billing.listChargeHeads(societyId);
      final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');
      await billing.createManualBill(
        societyId,
        ManualBillDraft(
          unitId: unitId,
          billDate: '2026-05-01',
          dueDate: '2026-05-20',
          lines: [
            BillLineDraft(
              chargeHeadId: maintHead.id,
              description: 'May Maintenance',
              amountPaise: 200000,
              payablePaise: 200000,
            ),
          ],
        ),
      );

      // 3. Allocate ₹2,000.00 from advance to bill
      final openLines = await collRepo.getOpenBillLines(db, societyId, unitId);
      expect(openLines.length, 1);

      await collections.allocateAdvance(
        societyId,
        receipt.id,
        [
          AllocationDraft(billLineId: openLines.first.billLineId, amountPaise: 200000),
        ],
      );

      final rUpdated = await collRepo.getReceipt(db, receipt.id);
      expect(rUpdated!.unallocatedPaise, 100000); // ₹1,000.00 remains in advance

      final tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-05-31');
      expect(tb.isBalanced, isTrue);
    });

    test('reverseReceipt reverses journal, deactivates allocations and restores dues', () async {
      final heads = await billing.listChargeHeads(societyId);
      final maintHead = heads.firstWhere((h) => h.name == 'Maintenance Charges');

      await billing.createManualBill(
        societyId,
        ManualBillDraft(
          unitId: unitId,
          billDate: '2026-04-01',
          dueDate: '2026-04-20',
          lines: [
            BillLineDraft(
              chargeHeadId: maintHead.id,
              description: 'Maintenance',
              amountPaise: 200000,
              payablePaise: 200000,
            ),
          ],
        ),
      );

      final receipt = await collections.createReceipt(
        societyId,
        ReceiptDraft(
          unitId: unitId,
          payerName: 'Jethalal Gada',
          receiptDate: '2026-04-10',
          mode: 'cheque',
          bankCashAccountId: bankAccountId,
          amountPaise: 200000,
        ),
      );

      // Verify dues cleared
      var dues = await collections.getDuesSummary(societyId);
      expect(dues.first.netDuePaise, 0);

      // Now reverse receipt (e.g. cheque bounced)
      await collections.reverseReceipt(
        societyId,
        receipt.id,
        '2026-04-12',
        'Cheque bounced due to insufficient funds',
        reversalKind: 'bounced',
      );

      final rRev = await collRepo.getReceipt(db, receipt.id);
      expect(rRev!.status, 'reversed');

      // Allocations must be deactivated
      final allocs = await collRepo.listAllocations(societyId, sourceType: 'receipt', sourceId: receipt.id);
      expect(allocs.every((a) => !a.isActive), isTrue);

      // Dues restored
      dues = await collections.getDuesSummary(societyId);
      expect(dues.first.netDuePaise, 200000);

      // Trial balance balanced
      final tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);
    });

    test('unidentified receipt recording, resolution, and reversal', () async {
      // 1. Record unidentified receipt of ₹5,000.00
      final ur = await collections.createUnidentified(
        societyId,
        UnidentifiedReceiptDraft(
          bankCashAccountId: bankAccountId,
          receiptDate: '2026-04-10',
          amountPaise: 500000,
          mode: 'neft',
          instrumentNo: 'TXN-998877',
          narration: 'Unknown Sender',
        ),
      );

      expect(ur.status, 'open');

      // 2. Resolve to Unit A-101
      final resolved = await collections.resolveUnidentified(
        societyId: societyId,
        unidentifiedId: ur.id,
        unitId: unitId,
        payerName: 'Jethalal Gada',
        receiptDate: '2026-04-15',
        narration: 'Payer confirmed as brother of Jethalal Gada',
      );

      final urResolved = await collRepo.getUnidentified(db, ur.id);
      expect(urResolved!.status, 'resolved');
      expect(urResolved.resolvedReceiptId, resolved.id);

      // Verify member receipt created and trial balance balanced
      expect(resolved.amountPaise, 500000);

      var tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);

      // 3. Reverse member receipt -> unidentified reopened
      await collections.reverseReceipt(
        societyId,
        resolved.id,
        '2026-04-16',
        'Wrong unit assigned by mistake',
      );

      final urReopened = await collRepo.getUnidentified(db, ur.id);
      expect(urReopened!.status, 'open');
      expect(urReopened.resolvedReceiptId, isNull);

      tb = await ledger.trialBalance(societyId, '2026-04-01', '2026-04-30');
      expect(tb.isBalanced, isTrue);
    });
  });
}

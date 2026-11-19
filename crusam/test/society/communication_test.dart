import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/data/models/member_models.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/models/billing_models.dart';
import 'package:crusam/features/society/data/models/collection_models.dart';
import 'package:crusam/features/society/domain/billing/billing_service.dart';
import 'package:crusam/features/society/domain/collections/collection_service.dart';
import 'package:crusam/features/society/domain/communication/communication_service.dart';
import 'package:crusam/features/society/domain/ledger/ledger_service.dart';
import 'package:crusam/features/society/domain/members/member_service.dart';
import 'package:crusam/features/society/domain/society/society_admin_service.dart';
import 'test_support.dart';

void main() {
  initTestSupport();

  late Database db;
  late SocietyAdminService admin;
  late MemberService member;
  late LedgerService ledger;
  late BillingService billing;
  late CollectionService collection;
  late Society society;
  late int unitId;
  late int billId;
  late int receiptId;

  setUp(() async {
    db = await createTestDb();
    admin = SocietyAdminService(db);
    ledger = LedgerService(db);
    member = MemberService(db, ledgerService: ledger);
    billing = BillingService(db, ledgerService: ledger);
    collection = CollectionService(db, ledgerService: ledger);

    final socId = await admin.createSociety(const SocietyDraft(
      name: 'Comms Test Society',
      city: 'Pune',
      state: 'Maharashtra',
      pincode: '411001',
      booksStartDate: '2026-04-01',
    ));
    society = await admin.getSociety(socId);

    final typeId = await member.createUnitType(society.id, const UnitTypeDraft(name: 'Flat'));
    final blockId = await member.createBlock(society.id, const BlockDraft(name: 'A'));
    unitId = await member.createUnit(society.id, UnitDraft(
      blockId: blockId,
      unitNo: '101',
      unitTypeId: typeId,
      area1Centi: 60000,
    ));

    final personId = await member.createPerson(society.id, const PersonDraft(
      fullName: 'Rahul Kulkarni',
      email: 'rahul@example.com',
    ));

    await member.assignPerson(society.id, UnitPersonDraft(
      unitId: unitId,
      personId: personId,
      role: 'owner',
      isBillTo: true,
      fromDate: '2026-04-01',
    ));

    final head = (await billing.listChargeHeads(society.id)).firstWhere((h) => h.name == 'Maintenance Charges');
    await billing.createRule(society.id, BillingRuleDraft(
      chargeHeadId: head.id,
      ruleType: 'area_and_fixed',
      fixedPaise: 400000,
      effectiveFrom: '2026-04-01',
    ));

    final runId = await billing.createDraftRun(society.id, const BillRunDraft(
      frequency: 'monthly',
      periodFrom: '2026-04-01',
      periodTo: '2026-04-30',
      billDate: '2026-04-01',
      dueDate: '2026-04-20',
    ));
    await billing.postDraftRun(society.id, runId);
    final bills = await billing.listBills(society.id, runId: runId);
    billId = bills.rows.first.id;

    final cashAcc = (await ledger.getAccountByCode(society.id, '1101'))!;
    final rcpt = await collection.createReceipt(society.id, ReceiptDraft(
      receiptDate: '2026-04-10',
      unitId: unitId,
      amountPaise: 400000,
      mode: 'cash',
      bankCashAccountId: cashAcc.id,
      payerName: 'Rahul Kulkarni',
    ));
    receiptId = rcpt.id;
  });

  tearDown(() async {
    await db.close();
  });

  test('CommunicationService dispatches bill and receipt emails and logs results', () async {
    final sentCalls = <String>[];
    Future<String> mockSender({
      required String to,
      String cc = '',
      required String subject,
      required String bodyText,
      required Uint8List pdfBytes,
      required String attachmentFilename,
    }) async {
      sentCalls.add('$to: $subject');
      return 'mock-msg-id-12345';
    }

    final comms = CommunicationService(db, billing, collection, emailSender: mockSender);

    // 1. Send Bill Email
    final billLogId = await comms.sendBillEmail(societyId: society.id, billId: billId);
    expect(billLogId, isPositive);
    expect(sentCalls.length, equals(1));
    expect(sentCalls.first, contains('rahul@example.com'));

    // 2. Send Receipt Email
    final rcptLogId = await comms.sendReceiptEmail(societyId: society.id, receiptId: receiptId);
    expect(rcptLogId, isPositive);
    expect(sentCalls.length, equals(2));

    // 3. Send Statement Email
    final stmtLogId = await comms.sendStatementEmail(
      societyId: society.id,
      unitId: unitId,
      fromDate: '2026-04-01',
      toDate: '2026-04-30',
    );
    expect(stmtLogId, isPositive);
    expect(sentCalls.length, equals(3));

    // 4. Verify email logs table
    final logs = await comms.listEmailLogs(society.id);
    expect(logs.length, equals(3));
    expect(logs.every((l) => l.status == 'sent'), isTrue);
    expect(logs.every((l) => l.providerMessageId == 'mock-msg-id-12345'), isTrue);
  });

  test('Email delivery failure is recorded in email_log without modifying accounting data', () async {
    Future<String> failingSender({
      required String to,
      String cc = '',
      required String subject,
      required String bodyText,
      required Uint8List pdfBytes,
      required String attachmentFilename,
    }) async {
      throw Exception('SMTP Network Timeout (504)');
    }

    final comms = CommunicationService(db, billing, collection, emailSender: failingSender);

    final tbBefore = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');

    final logId = await comms.sendBillEmail(societyId: society.id, billId: billId);
    expect(logId, isPositive);

    final logs = await comms.listEmailLogs(society.id);
    expect(logs.length, equals(1));
    expect(logs.first.status, equals('failed'));
    expect(logs.first.errorMessage, contains('SMTP Network Timeout'));

    final tbAfter = await ledger.trialBalance(society.id, '2026-04-01', '2026-04-30');
    expect(tbAfter.isBalanced, isTrue);
    expect(tbAfter.totalDebitPaise, equals(tbBefore.totalDebitPaise));
    expect(tbAfter.totalCreditPaise, equals(tbBefore.totalCreditPaise));
  });

  test('Document footers configuration and lookup', () async {
    final comms = CommunicationService(db, billing, collection);

    await comms.setDocumentFooter(
      society.id,
      'member_bill',
      '2026-04-01',
      'Please make cheques payable to Comms Test Society.',
    );

    final footer = await comms.getDocumentFooter(society.id, 'member_bill', '2026-04-15');
    expect(footer, equals('Please make cheques payable to Comms Test Society.'));

    final allFooters = await comms.listDocumentFooters(society.id);
    expect(allFooters.length, equals(1));
    expect(allFooters.first.docType, equals('member_bill'));
  });
}

import 'package:sqflite/sqflite.dart';
import '../../core/society_exception.dart';
import '../../data/models/collection_models.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/society_models.dart';
import '../../data/repositories/collection_repository.dart';
import '../../data/repositories/member_repository.dart';
import '../../data/repositories/society_repository.dart';
import '../ledger/ledger_service.dart';
import 'allocation_calculator.dart';

class CollectionService {
  final Database db;
  final LedgerService ledgerService;
  final CollectionRepository _repo;
  final MemberRepository _memberRepo;
  final SocietyRepository _socRepo;

  CollectionService(
    this.db, {
    required this.ledgerService,
    CollectionRepository? collectionRepo,
    MemberRepository? memberRepo,
    SocietyRepository? societyRepo,
  })  : _repo = collectionRepo ?? CollectionRepository(db),
        _memberRepo = memberRepo ?? MemberRepository(db),
        _socRepo = societyRepo ?? SocietyRepository(db);

  // -------------------------------------------------------------
  // Member Receipts
  // -------------------------------------------------------------

  Future<Receipt> createReceipt(int societyId, ReceiptDraft draft) async {
    return db.transaction((txn) async {
      final society = await _socRepo.getSociety(societyId, txn);
      if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

      if (draft.amountPaise + draft.tdsPaise <= 0) {
        throw const SocietyException('validation', 'Receipt amount + TDS must be greater than zero');
      }

      if (draft.receiptDate.compareTo(society.booksStartDate) < 0) {
        throw SocietyException(
          'before_books_start',
          'Receipt date ${draft.receiptDate} is before books start date ${society.booksStartDate}',
        );
      }

      final fy = await ledgerService.requireOpenYear(txn, societyId, draft.receiptDate);
      final unit = await _memberRepo.getUnit(txn, draft.unitId);
      if (unit == null || unit.societyId != societyId) {
        throw SocietyException('not_found', 'Unit not found: ${draft.unitId}');
      }

      // Resolve bank/cash account
      int? bankCashAccId = draft.bankCashAccountId;
      if (bankCashAccId == null && draft.unidentifiedId == null) {
        final bAccs = await txn.query(
          'bank_accounts',
          where: 'society_id = ? AND is_active = 1',
          orderBy: 'account_type ASC', // bank first, then cash
          limit: 1,
        );
        if (bAccs.isNotEmpty) {
          bankCashAccId = bAccs.first['account_id'] as int;
        } else {
          bankCashAccId = await ledgerService.accountIdForKey(txn, societyId, 'cash');
        }
      }

      // Check unidentified receipt if applicable
      UnidentifiedReceipt? unrec;
      if (draft.unidentifiedId != null) {
        unrec = await _repo.getUnidentified(txn, draft.unidentifiedId!);
        if (unrec == null || unrec.societyId != societyId) {
          throw SocietyException('not_found', 'Unidentified receipt not found: ${draft.unidentifiedId}');
        }
        if (!unrec.isOpen) {
          throw const SocietyException('validation', 'Unidentified receipt is not open');
        }
        bankCashAccId = unrec.bankCashAccountId;
      }

      // Calculate allocations
      final openLines = await _repo.getOpenBillLines(txn, societyId, draft.unitId, asOfDate: draft.receiptDate);
      AllocationResult allocResult;

      if (draft.customAllocations != null) {
        allocResult = AllocationCalculator.validateCustomAllocations(
          openLines: openLines,
          drafts: draft.customAllocations!,
          availablePaise: draft.totalPaise,
        );
      } else if (draft.receiptKind == 'bill') {
        allocResult = AllocationCalculator.autoAllocate(
          openLines: openLines,
          availablePaise: draft.totalPaise,
        );
      } else {
        // 'advance' or 'refundable_deposit': no initial line allocations
        allocResult = AllocationResult(
          allocations: const [],
          totalAllocatedPaise: 0,
          unallocatedPaise: draft.totalPaise,
        );
      }

      // Generate receipt number
      final receiptNo = await ledgerService.nextNumber(txn, societyId, fy.id, 'member_receipt');

      // Insert receipt
      final receiptId = await _repo.insertReceipt(txn, {
        'society_id': societyId,
        'fy_id': fy.id,
        'receipt_no': receiptNo,
        'receipt_kind': draft.receiptKind,
        'unit_id': draft.unitId,
        'payer_person_id': draft.payerPersonId,
        'payer_name': draft.payerName.trim(),
        'receipt_date': draft.receiptDate,
        'amount_paise': draft.amountPaise,
        'tds_paise': draft.tdsPaise,
        'mode': draft.mode,
        'instrument_no': draft.instrumentNo?.trim(),
        'instrument_date': draft.instrumentDate?.trim(),
        'instrument_bank': draft.instrumentBank?.trim(),
        'bank_cash_account_id': bankCashAccId,
        'unidentified_id': draft.unidentifiedId,
        'narration': draft.narration?.trim(),
        'status': 'posted',
      });

      // Insert allocations
      for (final a in allocResult.allocations) {
        await _repo.insertAllocation(txn, {
          'society_id': societyId,
          'source_type': 'receipt',
          'source_id': receiptId,
          'bill_line_id': a.billLineId,
          'allocated_paise': a.amountPaise,
          'allocation_date': draft.receiptDate,
          'is_active': 1,
        });
      }

      // Post double-entry journal
      final jLines = <JournalLineDraft>[];
      final memRecAccId = await ledgerService.accountIdForKey(txn, societyId, 'members_receivable');

      if (draft.receiptKind == 'refundable_deposit') {
        final refDepAccId = await ledgerService.accountIdForKey(txn, societyId, 'refundable_deposits');
        // Debit: bank/cash
        jLines.add(JournalLineDraft(
          accountId: bankCashAccId!,
          debitPaise: draft.amountPaise,
          note: 'Deposit receipt $receiptNo from ${draft.payerName}',
        ));
        // Credit: refundable_deposits (requires unit_id)
        jLines.add(JournalLineDraft(
          accountId: refDepAccId,
          creditPaise: draft.amountPaise,
          unitId: draft.unitId,
          note: 'Refundable deposit for Unit ${unit.blockName}-${unit.unitNo}',
        ));
      } else {
        // bill or advance
        if (draft.unidentifiedId != null) {
          // Resolution of unidentified receipt:
          // Debit: unidentified_receipts (2402)
          final unIdAcc = await ledgerService.accountIdForKey(txn, societyId, 'unidentified_receipts');
          jLines.add(JournalLineDraft(
            accountId: unIdAcc,
            debitPaise: draft.amountPaise,
            note: 'Resolve unidentified receipt ${unrec!.referenceNo}',
          ));
        } else {
          // Normal receipt: Debit bank/cash
          if (draft.amountPaise > 0) {
            jLines.add(JournalLineDraft(
              accountId: bankCashAccId!,
              debitPaise: draft.amountPaise,
              note: 'Receipt $receiptNo from ${draft.payerName}',
            ));
          }
        }

        // Debit TDS Receivable if applicable
        if (draft.tdsPaise > 0) {
          final tdsAccId = await ledgerService.accountIdForKey(txn, societyId, 'tds_receivable');
          jLines.add(JournalLineDraft(
            accountId: tdsAccId,
            debitPaise: draft.tdsPaise,
            note: 'TDS deducted on receipt $receiptNo',
          ));
        }

        // Credit Members Receivable
        jLines.add(JournalLineDraft(
          accountId: memRecAccId,
          creditPaise: draft.totalPaise,
          unitId: draft.unitId,
          note: 'Collection for Unit ${unit.blockName}-${unit.unitNo} (Receipt $receiptNo)',
        ));
      }

      final jDraft = JournalDraft(
        societyId: societyId,
        entryDate: draft.receiptDate,
        sourceType: 'member_receipt',
        sourceId: receiptId,
        narration: 'Receipt $receiptNo for Unit ${unit.blockName}-${unit.unitNo} (${draft.payerName})',
        lines: jLines,
      );

      final postedJ = await ledgerService.post(txn, jDraft);

      // Link journal entry
      await txn.update(
        'receipts',
        {'journal_entry_id': postedJ.id},
        where: 'id = ?',
        whereArgs: [receiptId],
      );

      // If resolving unidentified, mark unidentified receipt resolved
      if (draft.unidentifiedId != null) {
        await _repo.updateUnidentifiedStatus(
          txn,
          draft.unidentifiedId!,
          'resolved',
          resolvedReceiptId: receiptId,
        );
      }

      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'receipt',
        receiptId,
        'Created receipt $receiptNo for ₹${(draft.totalPaise / 100).toStringAsFixed(2)}',
      );

      return (await _repo.getReceipt(txn, receiptId))!;
    });
  }

  Future<void> allocateAdvance(
    int societyId,
    int receiptId,
    List<AllocationDraft> allocations, {
    String? allocationDate,
  }) async {
    return db.transaction((txn) async {
      final receipt = await _repo.getReceipt(txn, receiptId);
      if (receipt == null || receipt.societyId != societyId) {
        throw SocietyException('not_found', 'Receipt not found: $receiptId');
      }
      if (receipt.isReversed) {
        throw const SocietyException('validation', 'Cannot allocate reversed receipt');
      }

      final allocDt = allocationDate ?? DateTime.now().toIso8601String().substring(0, 10);
      final openLines = await _repo.getOpenBillLines(txn, societyId, receipt.unitId, asOfDate: allocationDate);

      final res = AllocationCalculator.validateCustomAllocations(
        openLines: openLines,
        drafts: allocations,
        availablePaise: receipt.unallocatedPaise,
      );

      for (final a in res.allocations) {
        await _repo.insertAllocation(txn, {
          'society_id': societyId,
          'source_type': 'receipt',
          'source_id': receiptId,
          'bill_line_id': a.billLineId,
          'allocated_paise': a.amountPaise,
          'allocation_date': allocDt,
          'is_active': 1,
        });
      }

      await _socRepo.insertAudit(
        txn,
        societyId,
        'allocate',
        'receipt',
        receiptId,
        'Allocated ₹${(res.totalAllocatedPaise / 100).toStringAsFixed(2)} of advance receipt ${receipt.receiptNo}',
      );
    });
  }

  Future<void> reverseReceipt(
    int societyId,
    int receiptId,
    String reversalDate,
    String reason, {
    String reversalKind = 'mistake',
  }) async {
    return db.transaction((txn) async {
      final receipt = await _repo.getReceipt(txn, receiptId);
      if (receipt == null || receipt.societyId != societyId) {
        throw SocietyException('not_found', 'Receipt not found: $receiptId');
      }
      if (receipt.isReversed) {
        throw const SocietyException('validation', 'Receipt is already reversed');
      }

      // Check if bank line is cleared
      if (receipt.journalEntryId != null) {
        final clearedRows = await txn.rawQuery(
          'SELECT COUNT(*) as cnt FROM bank_clearances bc '
          'JOIN journal_lines jl ON bc.journal_line_id = jl.id '
          'WHERE jl.entry_id = ?',
          [receipt.journalEntryId],
        );
        final clearedCnt = (clearedRows.first['cnt'] as int?) ?? 0;
        if (clearedCnt > 0) {
          throw const SocietyException(
            'cleared_line',
            'Cannot reverse receipt because its bank transaction is already reconciled/cleared',
          );
        }
      }

      // 1. Deactivate allocations
      await _repo.deactivateAllocationsForSource(txn, 'receipt', receiptId);

      // 2. Post reversal mirror journal
      int? revEntryId;
      if (receipt.journalEntryId != null) {
        final posted = await ledgerService.reverse(
          txn,
          societyId,
          receipt.journalEntryId!,
          reversalDate,
          'Reversal of receipt ${receipt.receiptNo}: $reason',
        );
        revEntryId = posted.id;
      }

      // 3. Update status
      await _repo.updateReceiptStatus(
        txn,
        receiptId,
        'reversed',
        reversalKind: reversalKind,
        reversalReason: reason,
        reversalEntryId: revEntryId,
      );

      // 4. If this receipt resolved an unidentified receipt, reopen the unidentified receipt
      if (receipt.unidentifiedId != null) {
        await _repo.updateUnidentifiedStatus(
          txn,
          receipt.unidentifiedId!,
          'open',
          clearResolvedReceipt: true,
        );
      }

      await _socRepo.insertAudit(
        txn,
        societyId,
        'reverse',
        'receipt',
        receiptId,
        'Reversed receipt ${receipt.receiptNo} ($reversalKind): $reason',
      );
    });
  }

  // -------------------------------------------------------------
  // Credit Notes
  // -------------------------------------------------------------

  Future<CreditNote> createCreditNote(int societyId, CreditNoteDraft draft) async {
    return db.transaction((txn) async {
      final society = await _socRepo.getSociety(societyId, txn);
      if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

      if (draft.totalPaise <= 0) {
        throw const SocietyException('validation', 'Credit note total must be greater than zero');
      }

      final fy = await ledgerService.requireOpenYear(txn, societyId, draft.noteDate);
      final unit = await _memberRepo.getUnit(txn, draft.unitId);
      if (unit == null || unit.societyId != societyId) {
        throw SocietyException('not_found', 'Unit not found: ${draft.unitId}');
      }

      final openLines = await _repo.getOpenBillLines(txn, societyId, draft.unitId, asOfDate: draft.noteDate);
      AllocationResult allocResult;

      if (draft.customAllocations != null) {
        allocResult = AllocationCalculator.validateCustomAllocations(
          openLines: openLines,
          drafts: draft.customAllocations!,
          availablePaise: draft.totalPaise,
        );
      } else {
        allocResult = AllocationCalculator.autoAllocate(
          openLines: openLines,
          availablePaise: draft.totalPaise,
        );
      }

      final noteNo = await ledgerService.nextNumber(txn, societyId, fy.id, 'credit_note');

      final noteId = await _repo.insertCreditNote(txn, {
        'society_id': societyId,
        'fy_id': fy.id,
        'note_no': noteNo,
        'scope': draft.scope,
        'unit_id': draft.unitId,
        'note_date': draft.noteDate,
        'charge_head_id': draft.chargeHeadId,
        'amount_paise': draft.amountPaise,
        'cgst_paise': draft.cgstPaise,
        'sgst_paise': draft.sgstPaise,
        'igst_paise': draft.igstPaise,
        'total_paise': draft.totalPaise,
        'reason': draft.reason.trim(),
        'status': 'posted',
      });

      for (final a in allocResult.allocations) {
        await _repo.insertAllocation(txn, {
          'society_id': societyId,
          'source_type': 'credit_note',
          'source_id': noteId,
          'bill_line_id': a.billLineId,
          'allocated_paise': a.amountPaise,
          'allocation_date': draft.noteDate,
          'is_active': 1,
        });
      }

      // Double-entry journal:
      // Debit: charge head's income account (or general income)
      // Debit: output_cgst, output_sgst, output_igst
      // Credit: members_receivable (with unit_id)
      final jLines = <JournalLineDraft>[];
      int incomeAccId;
      if (draft.chargeHeadId != null) {
        final headRow = await txn.query(
          'charge_heads',
          where: 'id = ?',
          whereArgs: [draft.chargeHeadId],
          limit: 1,
        );
        incomeAccId = headRow.first['account_id'] as int;
      } else {
        incomeAccId = await ledgerService.accountIdForKey(txn, societyId, 'maintenance');
      }

      if (draft.amountPaise > 0) {
        jLines.add(JournalLineDraft(
          accountId: incomeAccId,
          debitPaise: draft.amountPaise,
          note: 'Credit note $noteNo: ${draft.reason}',
        ));
      }

      if (draft.cgstPaise > 0) {
        final cgstAcc = await ledgerService.accountIdForKey(txn, societyId, 'output_cgst');
        jLines.add(JournalLineDraft(
          accountId: cgstAcc,
          debitPaise: draft.cgstPaise,
          note: 'CGST reversal on credit note $noteNo',
        ));
      }
      if (draft.sgstPaise > 0) {
        final sgstAcc = await ledgerService.accountIdForKey(txn, societyId, 'output_sgst');
        jLines.add(JournalLineDraft(
          accountId: sgstAcc,
          debitPaise: draft.sgstPaise,
          note: 'SGST reversal on credit note $noteNo',
        ));
      }
      if (draft.igstPaise > 0) {
        final igstAcc = await ledgerService.accountIdForKey(txn, societyId, 'output_igst');
        jLines.add(JournalLineDraft(
          accountId: igstAcc,
          debitPaise: draft.igstPaise,
          note: 'IGST reversal on credit note $noteNo',
        ));
      }

      final memRecAccId = await ledgerService.accountIdForKey(txn, societyId, 'members_receivable');
      jLines.add(JournalLineDraft(
        accountId: memRecAccId,
        creditPaise: draft.totalPaise,
        unitId: draft.unitId,
        note: 'Credit note $noteNo for Unit ${unit.blockName}-${unit.unitNo}',
      ));

      final jDraft = JournalDraft(
        societyId: societyId,
        entryDate: draft.noteDate,
        sourceType: 'credit_note',
        sourceId: noteId,
        narration: 'Credit Note $noteNo for Unit ${unit.blockName}-${unit.unitNo} (${draft.reason})',
        lines: jLines,
      );

      final postedJ = await ledgerService.post(txn, jDraft);

      await txn.update(
        'credit_notes',
        {'journal_entry_id': postedJ.id},
        where: 'id = ?',
        whereArgs: [noteId],
      );

      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'credit_note',
        noteId,
        'Created credit note $noteNo for ₹${(draft.totalPaise / 100).toStringAsFixed(2)}',
      );

      return (await _repo.getCreditNote(txn, noteId))!;
    });
  }

  Future<void> reverseCreditNote(
    int societyId,
    int noteId,
    String reversalDate,
    String reason,
  ) async {
    return db.transaction((txn) async {
      final note = await _repo.getCreditNote(txn, noteId);
      if (note == null || note.societyId != societyId) {
        throw SocietyException('not_found', 'Credit note not found: $noteId');
      }
      if (note.isReversed) {
        throw const SocietyException('validation', 'Credit note is already reversed');
      }

      await _repo.deactivateAllocationsForSource(txn, 'credit_note', noteId);

      int? revEntryId;
      if (note.journalEntryId != null) {
        final posted = await ledgerService.reverse(
          txn,
          societyId,
          note.journalEntryId!,
          reversalDate,
          'Reversal of credit note ${note.noteNo}: $reason',
        );
        revEntryId = posted.id;
      }

      await _repo.updateCreditNoteStatus(
        txn,
        noteId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: revEntryId,
      );

      await _socRepo.insertAudit(
        txn,
        societyId,
        'reverse',
        'credit_note',
        noteId,
        'Reversed credit note ${note.noteNo}: $reason',
      );
    });
  }

  // -------------------------------------------------------------
  // Unidentified Receipts
  // -------------------------------------------------------------

  Future<UnidentifiedReceipt> createUnidentified(
    int societyId,
    UnidentifiedReceiptDraft draft,
  ) async {
    return db.transaction((txn) async {
      final society = await _socRepo.getSociety(societyId, txn);
      if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

      if (draft.amountPaise <= 0) {
        throw const SocietyException('validation', 'Amount must be greater than zero');
      }

      final fy = await ledgerService.requireOpenYear(txn, societyId, draft.receiptDate);
      final refNo = await ledgerService.nextNumber(txn, societyId, fy.id, 'unidentified');

      final urId = await _repo.insertUnidentified(txn, {
        'society_id': societyId,
        'fy_id': fy.id,
        'reference_no': refNo,
        'receipt_date': draft.receiptDate,
        'amount_paise': draft.amountPaise,
        'mode': draft.mode,
        'instrument_no': draft.instrumentNo?.trim(),
        'instrument_bank': draft.instrumentBank?.trim(),
        'bank_cash_account_id': draft.bankCashAccountId,
        'narration': draft.narration?.trim(),
        'status': 'open',
      });

      // Journal:
      // Debit: Bank/Cash account
      // Credit: Unidentified Receipts (2402)
      final unIdAcc = await ledgerService.accountIdForKey(txn, societyId, 'unidentified_receipts');
      final jDraft = JournalDraft(
        societyId: societyId,
        entryDate: draft.receiptDate,
        sourceType: 'unidentified_receipt',
        sourceId: urId,
        narration: 'Unidentified receipt $refNo',
        lines: [
          JournalLineDraft(
            accountId: draft.bankCashAccountId,
            debitPaise: draft.amountPaise,
            note: 'Unidentified deposit $refNo',
          ),
          JournalLineDraft(
            accountId: unIdAcc,
            creditPaise: draft.amountPaise,
            note: 'Unidentified deposit $refNo',
          ),
        ],
      );

      final postedJ = await ledgerService.post(txn, jDraft);

      await txn.update(
        'unidentified_receipts',
        {'journal_entry_id': postedJ.id},
        where: 'id = ?',
        whereArgs: [urId],
      );

      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'unidentified_receipt',
        urId,
        'Recorded unidentified receipt $refNo for ₹${(draft.amountPaise / 100).toStringAsFixed(2)}',
      );

      return (await _repo.getUnidentified(txn, urId))!;
    });
  }

  Future<Receipt> resolveUnidentified({
    required int societyId,
    required int unidentifiedId,
    required int unitId,
    required String payerName,
    required String receiptDate,
    String? narration,
  }) async {
    final unrec = await _repo.getUnidentified(db, unidentifiedId);
    if (unrec == null || unrec.societyId != societyId) {
      throw SocietyException('not_found', 'Unidentified receipt not found: $unidentifiedId');
    }

    final draft = ReceiptDraft(
      receiptKind: 'bill',
      unitId: unitId,
      payerName: payerName,
      receiptDate: receiptDate,
      amountPaise: unrec.amountPaise,
      tdsPaise: 0,
      mode: 'unidentified',
      instrumentNo: unrec.instrumentNo,
      instrumentBank: unrec.instrumentBank,
      bankCashAccountId: unrec.bankCashAccountId,
      unidentifiedId: unidentifiedId,
      narration: narration ?? 'Resolved from unidentified ${unrec.referenceNo}',
    );

    return createReceipt(societyId, draft);
  }

  // -------------------------------------------------------------
  // Unit Statement, Dues and Ageing
  // -------------------------------------------------------------

  Future<List<UnitStatementRow>> getUnitStatement(
    int societyId,
    int unitId, {
    String? fromDate,
    String? toDate,
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    final memRecAccId = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');

    final where = StringBuffer("jl.society_id = ? AND jl.account_id = ? AND jl.unit_id = ? AND je.status IN ('posted', 'reversed')");
    final args = <Object?>[societyId, memRecAccId, unitId];

    if (fromDate != null && fromDate.isNotEmpty) {
      where.write(' AND je.entry_date >= ?');
      args.add(fromDate);
    }
    if (toDate != null && toDate.isNotEmpty) {
      where.write(' AND je.entry_date <= ?');
      args.add(toDate);
    }

    final sql = '''
      SELECT 
        je.entry_date,
        je.source_type,
        je.entry_no,
        je.narration,
        jl.note,
        jl.debit_paise,
        jl.credit_paise
      FROM journal_lines jl
      JOIN journal_entries je ON jl.entry_id = je.id
      WHERE $where
      ORDER BY je.entry_date ASC, je.id ASC, jl.line_no ASC
    ''';

    final rows = await db.rawQuery(sql, args);
    final results = <UnitStatementRow>[];
    var running = 0;

    for (final r in rows) {
      final deb = (r['debit_paise'] as int?) ?? 0;
      final cred = (r['credit_paise'] as int?) ?? 0;
      running += (deb - cred);

      final desc = (r['note'] as String?)?.isNotEmpty == true
          ? r['note'] as String
          : (r['narration'] as String?) ?? '';

      results.add(UnitStatementRow(
        date: r['entry_date'] as String,
        docType: r['source_type'] as String,
        docNo: r['entry_no'] as String,
        description: desc,
        debitPaise: deb,
        creditPaise: cred,
        runningBalancePaise: running,
      ));
    }

    return results;
  }

  Future<List<UnitDueSummary>> getDuesSummary(
    int societyId, {
    String? asOfDate,
  }) async {
    final society = await _socRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    final asOf = asOfDate ?? DateTime.now().toIso8601String().substring(0, 10);
    final asOfDt = DateTime.parse(asOf);

    final unitsRes = await _memberRepo.listUnits(societyId, page: const PageRequest(limit: 5000));
    final units = unitsRes.rows;

    final memRecAccId = await ledgerService.accountIdForKey(db, societyId, 'members_receivable');

    final summaries = <UnitDueSummary>[];

    for (final u in units) {
      // 1. Members receivable balance from ledger (debit - credit)
      final balRows = await db.rawQuery(
        'SELECT '
        'COALESCE(SUM(jl.debit_paise), 0) as total_deb, '
        'COALESCE(SUM(jl.credit_paise), 0) as total_cred '
        'FROM journal_lines jl '
        'JOIN journal_entries je ON jl.entry_id = je.id '
        'WHERE jl.society_id = ? AND jl.account_id = ? AND jl.unit_id = ? '
        "AND je.status IN ('posted', 'reversed') AND je.entry_date <= ?",
        [societyId, memRecAccId, u.id, asOf],
      );
      final totDeb = (balRows.first['total_deb'] as int?) ?? 0;
      final totCred = (balRows.first['total_cred'] as int?) ?? 0;
      final netBalance = totDeb - totCred;

      // 2. Open bills and ageing
      final openLines = await _repo.getOpenBillLines(db, societyId, u.id, asOfDate: asOf);
      var age0 = 0;
      var age31 = 0;
      var age61 = 0;
      var age90 = 0;

      for (final ol in openLines) {
        final rem = ol.remainingPaise;
        if (rem <= 0) continue;

        final dueDt = DateTime.parse(ol.dueDate);
        final overdueDays = asOfDt.difference(dueDt).inDays;

        if (overdueDays <= 30) {
          age0 += rem;
        } else if (overdueDays <= 60) {
          age31 += rem;
        } else if (overdueDays <= 90) {
          age61 += rem;
        } else {
          age90 += rem;
        }
      }

      // 3. Unallocated advance
      final advRows = await db.rawQuery(
        'SELECT '
        'COALESCE(SUM(r.amount_paise + r.tds_paise), 0) - '
        "COALESCE((SELECT SUM(ba.allocated_paise) FROM bill_allocations ba JOIN receipts r2 ON ba.source_id = r2.id WHERE ba.source_type = 'receipt' AND r2.unit_id = ? AND ba.is_active = 1), 0) as unallocated "
        'FROM receipts r '
        "WHERE r.society_id = ? AND r.unit_id = ? AND r.status = 'posted' AND r.receipt_date <= ?",
        [u.id, societyId, u.id, asOf],
      );
      final unallocatedAdv = (advRows.first['unallocated'] as int?) ?? 0;

      summaries.add(UnitDueSummary(
        unitId: u.id,
        unitNo: u.unitNo,
        blockName: u.blockName,
        ownerName: u.billToName ?? u.primaryContactName,
        phone: u.primaryContactPhone,
        membersReceivablePaise: netBalance > 0 ? netBalance : 0,
        advancePaise: netBalance < 0 ? -netBalance : (unallocatedAdv > 0 ? unallocatedAdv : 0),
        netDuePaise: netBalance,
        age0to30Paise: age0,
        age31to60Paise: age31,
        age61to90Paise: age61,
        age90PlusPaise: age90,
      ));
    }

    return summaries;
  }

  // Repository pass-throughs
  Future<PageResult<Receipt>> listReceipts(
    int societyId, {
    int? unitId,
    String? status,
    String? fromDate,
    String? toDate,
    PageRequest page = const PageRequest(),
  }) =>
      _repo.listReceipts(societyId, unitId: unitId, status: status, fromDate: fromDate, toDate: toDate, page: page);

  Future<Receipt?> getReceipt(int receiptId) => _repo.getReceipt(db, receiptId);

  Future<PageResult<CreditNote>> listCreditNotes(
    int societyId, {
    int? unitId,
    String? status,
    PageRequest page = const PageRequest(),
  }) =>
      _repo.listCreditNotes(societyId, unitId: unitId, status: status, page: page);

  Future<CreditNote?> getCreditNote(int noteId) => _repo.getCreditNote(db, noteId);

  Future<PageResult<UnidentifiedReceipt>> listUnidentified(
    int societyId, {
    String? status,
    PageRequest page = const PageRequest(),
  }) =>
      _repo.listUnidentified(societyId, status: status, page: page);

  Future<UnidentifiedReceipt?> getUnidentified(int id) => _repo.getUnidentified(db, id);

  Future<List<BillAllocation>> listAllocations(
    int societyId, {
    String? sourceType,
    int? sourceId,
    int? billLineId,
  }) =>
      _repo.listAllocations(societyId, sourceType: sourceType, sourceId: sourceId, billLineId: billLineId);
}

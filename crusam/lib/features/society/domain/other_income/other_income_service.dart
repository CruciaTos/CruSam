import 'package:sqflite/sqflite.dart';
import '../../core/money.dart';
import '../../core/society_exception.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/other_income_models.dart';
import '../../data/repositories/other_income_repository.dart';
import '../../data/repositories/society_repository.dart';
import '../ledger/ledger_service.dart';

class OtherIncomeService {
  final Database db;
  final OtherIncomeRepository _repo;
  final SocietyRepository _societyRepo;
  final LedgerService _ledger;

  OtherIncomeService(
    this.db, {
    required LedgerService ledgerService,
    OtherIncomeRepository? otherIncomeRepo,
    SocietyRepository? societyRepo,
  })  : _ledger = ledgerService,
        _repo = otherIncomeRepo ?? OtherIncomeRepository(db),
        _societyRepo = societyRepo ?? SocietyRepository(db);

  Future<int> saveParty(int societyId, PartyDraft draft, {int? partyId}) async {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Party name is required');
    }
    return await _repo.saveParty(societyId, draft, partyId: partyId);
  }

  Future<Party?> getParty(int societyId, int partyId) async {
    return await _repo.getParty(societyId, partyId);
  }

  Future<List<PartyRow>> listParties(int societyId, {PartyFilter? filter}) async {
    return await _repo.listParties(societyId, filter: filter);
  }

  Future<int> postInvoice(int societyId, OtherInvoiceDraft draft) async {
    if (draft.lines.isEmpty) {
      throw const SocietyException('validation', 'At least one invoice line is required');
    }

    final party = await _repo.getParty(societyId, draft.partyId);
    if (party == null || !party.isActive) {
      throw const SocietyException('validation', 'Invalid or inactive party');
    }

    final society = await _societyRepo.getSociety(societyId);
    if (society == null) {
      throw SocietyException('wrong_society', 'Society not found: $societyId');
    }

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.invoiceDate);
      final invoiceNo = await _ledger.nextNumber(txn, societyId, fy.id, 'other_invoice');

      // Check inter-state GST
      final societyState = society.stateCode.trim().toUpperCase();
      final partyState = (party.stateCode ?? '').trim().toUpperCase();
      final isInterState = societyState.isNotEmpty && partyState.isNotEmpty && societyState != partyState;
      final isGstRegistered = society.gstRegistered;

      var subtotal = 0;
      var totalCgst = 0;
      var totalSgst = 0;
      var totalIgst = 0;

      final processedLines = <OtherInvoiceLine>[];
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        if (line.amountPaise <= 0) {
          throw const SocietyException('validation', 'Line amount must be positive');
        }

        var cgst = 0;
        var sgst = 0;
        var igst = 0;

        if (isGstRegistered && line.gstRateBp > 0) {
          final totalGst = percentOf(line.amountPaise, line.gstRateBp);
          if (isInterState) {
            igst = totalGst;
          } else {
            cgst = totalGst ~/ 2;
            sgst = totalGst - cgst;
          }
        }

        subtotal += line.amountPaise;
        totalCgst += cgst;
        totalSgst += sgst;
        totalIgst += igst;

        processedLines.add(OtherInvoiceLine(
          id: 0,
          societyId: societyId,
          invoiceId: 0,
          lineNo: i + 1,
          accountId: line.accountId,
          description: line.description,
          hsnSac: line.hsnSac,
          amountPaise: line.amountPaise,
          gstRateBp: isGstRegistered ? line.gstRateBp : 0,
          cgstPaise: cgst,
          sgstPaise: sgst,
          igstPaise: igst,
        ));
      }

      final total = subtotal + totalCgst + totalSgst + totalIgst;

      // Find accounts by system key
      final otherRecAccId = await _ledger.accountIdForKey(txn, societyId, 'other_receivable');

      // Build journal lines
      final journalLines = <JournalLineDraft>[
        // Debit Other Receivable
        JournalLineDraft(
          accountId: otherRecAccId,
          debitPaise: total,
          creditPaise: 0,
          partyId: party.id,
          note: 'Invoice $invoiceNo',
        ),
      ];

      // Credit line income accounts
      for (final line in processedLines) {
        journalLines.add(JournalLineDraft(
          accountId: line.accountId,
          debitPaise: 0,
          creditPaise: line.amountPaise,
          partyId: party.id,
          note: line.description,
        ));
      }

      // Credit Output GST accounts if applicable
      if (totalCgst > 0) {
        final outCgstId = await _ledger.accountIdForKey(txn, societyId, 'output_cgst');
        journalLines.add(JournalLineDraft(
          accountId: outCgstId,
          debitPaise: 0,
          creditPaise: totalCgst,
        ));
      }
      if (totalSgst > 0) {
        final outSgstId = await _ledger.accountIdForKey(txn, societyId, 'output_sgst');
        journalLines.add(JournalLineDraft(
          accountId: outSgstId,
          debitPaise: 0,
          creditPaise: totalSgst,
        ));
      }
      if (totalIgst > 0) {
        final outIgstId = await _ledger.accountIdForKey(txn, societyId, 'output_igst');
        journalLines.add(JournalLineDraft(
          accountId: outIgstId,
          debitPaise: 0,
          creditPaise: totalIgst,
        ));
      }

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.invoiceDate,
          sourceType: 'other_invoice',
          narration: draft.narration ?? 'Other Invoice $invoiceNo - ${party.name}',
          lines: journalLines,
        ),
      );

      final invoiceId = await _repo.insertInvoice(
        societyId: societyId,
        fyId: fy.id,
        invoiceNo: invoiceNo,
        partyId: party.id,
        invoiceDate: draft.invoiceDate,
        dueDate: draft.dueDate,
        subtotalPaise: subtotal,
        cgstPaise: totalCgst,
        sgstPaise: totalSgst,
        igstPaise: totalIgst,
        totalPaise: total,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        lines: processedLines,
        executor: txn,
      );

      return invoiceId;
    });
  }

  Future<int> postReceipt(int societyId, OtherReceiptDraft draft) async {
    if (draft.amountPaise <= 0) {
      throw const SocietyException('validation', 'Receipt amount must be positive');
    }

    final party = await _repo.getParty(societyId, draft.partyId);
    if (party == null || !party.isActive) {
      throw const SocietyException('validation', 'Invalid or inactive party');
    }

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.receiptDate);
      final receiptNo = await _ledger.nextNumber(txn, societyId, fy.id, 'other_receipt');
      final otherRecAccId = await _ledger.accountIdForKey(txn, societyId, 'other_receivable');

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.receiptDate,
          sourceType: 'other_receipt',
          narration: draft.narration ?? 'Other Receipt $receiptNo - ${party.name}',
          lines: [
            // Debit Bank or Cash
            JournalLineDraft(
              accountId: draft.bankCashAccountId,
              debitPaise: draft.amountPaise,
              creditPaise: 0,
              note: '${draft.mode.toUpperCase()} $receiptNo',
            ),
            // Credit Other Receivable with party_id
            JournalLineDraft(
              accountId: otherRecAccId,
              debitPaise: 0,
              creditPaise: draft.amountPaise,
              partyId: party.id,
              note: draft.narration,
            ),
          ],
        ),
      );

      final receiptId = await _repo.insertReceipt(
        societyId: societyId,
        fyId: fy.id,
        receiptNo: receiptNo,
        partyId: party.id,
        receiptDate: draft.receiptDate,
        amountPaise: draft.amountPaise,
        mode: draft.mode,
        instrumentNo: draft.instrumentNo,
        instrumentBank: draft.instrumentBank,
        bankCashAccountId: draft.bankCashAccountId,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        allocations: draft.allocations,
        executor: txn,
      );

      return receiptId;
    });
  }

  Future<void> reverseInvoice(int societyId, int invoiceId, String date, String reason) async {
    final invoice = await _repo.getInvoice(societyId, invoiceId);
    if (invoice == null) throw const SocietyException('not_found', 'Invoice not found');
    if (invoice.status == 'reversed') throw const SocietyException('already_reversed', 'Invoice is already reversed');

    // Check if any allocations exist
    final openInvoices = await _repo.getOpenInvoices(societyId, invoice.partyId);
    final match = openInvoices.where((o) => (o['invoice'] as OtherInvoice).id == invoiceId);
    if (match.isNotEmpty && (match.first['allocated_paise'] as int) > 0) {
      throw const SocietyException('validation', 'Cannot reverse invoice with active receipt allocations');
    }

    await db.transaction((txn) async {
      final reversalJournal = await _ledger.reverse(
        txn,
        societyId,
        invoice.journalEntryId!,
        date,
        reason,
      );

      await _repo.updateInvoiceStatus(
        societyId,
        invoiceId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: reversalJournal.id,
        executor: txn,
      );
    });
  }

  Future<void> reverseReceipt(int societyId, int receiptId, String date, String reason) async {
    final receipt = await _repo.getReceipt(societyId, receiptId);
    if (receipt == null) throw const SocietyException('not_found', 'Receipt not found');
    if (receipt.status == 'reversed') throw const SocietyException('already_reversed', 'Receipt is already reversed');

    await db.transaction((txn) async {
      final reversalJournal = await _ledger.reverse(
        txn,
        societyId,
        receipt.journalEntryId!,
        date,
        reason,
      );

      await _repo.updateReceiptStatus(
        societyId,
        receiptId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: reversalJournal.id,
        clearAllocations: true,
        executor: txn,
      );
    });
  }

  Future<PartyStatement> partyStatement(int societyId, int partyId, String from, String to) async {
    final party = await _repo.getParty(societyId, partyId);
    if (party == null) throw const SocietyException('not_found', 'Party not found');

    final rows = await _repo.getPartyStatementRows(societyId, partyId, from, to);
    final openBalance = rows.isEmpty ? 0 : rows.first.balancePaise - (rows.first.debitPaise - rows.first.creditPaise);
    final closeBalance = rows.isEmpty ? openBalance : rows.last.balancePaise;

    return PartyStatement(
      party: party,
      fromDate: from,
      toDate: to,
      openingBalancePaise: openBalance,
      rows: rows,
      closingBalancePaise: closeBalance,
    );
  }

  Future<OtherInvoice?> getInvoice(int societyId, int invoiceId) => _repo.getInvoice(societyId, invoiceId);
  Future<List<OtherInvoiceLine>> getInvoiceLines(int societyId, int invoiceId) => _repo.getInvoiceLines(societyId, invoiceId);
  Future<List<OtherInvoice>> listInvoices(int societyId, {int? partyId, String? status}) =>
      _repo.listInvoices(societyId, partyId: partyId, status: status);
  Future<OtherReceipt?> getReceipt(int societyId, int receiptId) => _repo.getReceipt(societyId, receiptId);
  Future<List<OtherReceipt>> listReceipts(int societyId, {int? partyId, String? status}) =>
      _repo.listReceipts(societyId, partyId: partyId, status: status);
  Future<List<Map<String, dynamic>>> getOpenInvoices(int societyId, int partyId) =>
      _repo.getOpenInvoices(societyId, partyId);
}

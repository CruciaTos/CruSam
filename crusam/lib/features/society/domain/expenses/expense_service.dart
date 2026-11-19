import 'package:sqflite/sqflite.dart';
import '../../core/money.dart';
import '../../core/society_exception.dart';
import '../../data/models/expense_models.dart';
import '../../data/models/ledger_models.dart';
import '../../data/repositories/expense_repository.dart';
import '../../data/repositories/society_repository.dart';
import '../ledger/ledger_service.dart';

class ExpenseService {
  final Database db;
  final ExpenseRepository _repo;
  final SocietyRepository _societyRepo;
  final LedgerService _ledger;

  ExpenseService(
    this.db, {
    required LedgerService ledgerService,
    ExpenseRepository? expenseRepo,
    SocietyRepository? societyRepo,
  })  : _ledger = ledgerService,
        _repo = expenseRepo ?? ExpenseRepository(db),
        _societyRepo = societyRepo ?? SocietyRepository(db);

  // Vendors
  Future<int> saveVendor(int societyId, VendorDraft draft, {int? vendorId}) async {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Vendor name is required');
    }
    return await _repo.saveVendor(societyId, draft, vendorId: vendorId);
  }

  Future<Vendor?> getVendor(int societyId, int vendorId) async {
    return await _repo.getVendor(societyId, vendorId);
  }

  Future<List<VendorRow>> listVendors(int societyId, {VendorFilter? filter}) async {
    return await _repo.listVendors(societyId, filter: filter);
  }

  Future<VendorDetail> vendorDetail(int societyId, int vendorId) async {
    final detail = await _repo.getVendorDetail(societyId, vendorId);
    if (detail == null) throw const SocietyException('not_found', 'Vendor not found');
    return detail;
  }

  Future<List<TdsSection>> listTdsSections(int societyId) async {
    return await _repo.listTdsSections(societyId);
  }

  // Expense Bills
  Future<int> postExpenseBill(int societyId, ExpenseBillDraft draft) async {
    if (draft.lines.isEmpty) {
      throw const SocietyException('validation', 'At least one expense line is required');
    }
    if (draft.vendorBillNo.trim().isEmpty) {
      throw const SocietyException('validation', 'Vendor bill number is required');
    }

    final vendor = await _repo.getVendor(societyId, draft.vendorId);
    if (vendor == null || !vendor.isActive) {
      throw const SocietyException('validation', 'Invalid or inactive vendor');
    }

    final society = await _societyRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    // Check duplicate vendor bill number
    final existingBills = await _repo.listExpenseBills(
      societyId,
      vendorId: vendor.id,
      billKind: draft.billKind,
    );
    final isDup = existingBills.any((b) =>
        b.status != 'reversed' &&
        b.vendorBillNo.trim().toLowerCase() == draft.vendorBillNo.trim().toLowerCase());
    if (isDup) {
      throw SocietyException('duplicate_bill', 'Duplicate vendor bill number "${draft.vendorBillNo}" for this vendor');
    }

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.postDate);
      final voucherNo = await _ledger.nextNumber(txn, societyId, fy.id, 'expense_voucher');

      final societyState = society.stateCode.trim().toUpperCase();
      final vendorState = (vendor.stateCode ?? '').trim().toUpperCase();
      final isSameState = vendorState.isEmpty ||
          societyState.isEmpty ||
          societyState == vendorState ||
          (societyState == '27' && vendorState == 'MH') ||
          (societyState == 'MH' && vendorState == '27');
      final isInterState = !isSameState;

      var subtotal = 0;
      var totalCgst = 0;
      var totalSgst = 0;
      var totalIgst = 0;

      final processedLines = <ExpenseLine>[];
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        if (line.amountPaise <= 0) {
          throw const SocietyException('validation', 'Line amount must be positive');
        }

        var cgst = 0;
        var sgst = 0;
        var igst = 0;

        if (line.gstRateBp > 0) {
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

        processedLines.add(ExpenseLine(
          id: 0,
          societyId: societyId,
          expenseBillId: 0,
          lineNo: i + 1,
          accountId: line.accountId,
          description: line.description,
          hsnSac: line.hsnSac,
          amountPaise: line.amountPaise,
          gstRateBp: line.gstRateBp,
          cgstPaise: cgst,
          sgstPaise: sgst,
          igstPaise: igst,
        ));
      }

      final total = subtotal + totalCgst + totalSgst + totalIgst;

      // Calculate TDS
      var tdsPaise = 0;
      if (draft.customTdsPaise != null) {
        tdsPaise = draft.customTdsPaise!;
      } else if (draft.tdsRateBp != null && draft.tdsRateBp! > 0) {
        tdsPaise = percentOf(subtotal, draft.tdsRateBp!);
      }

      final payable = total - tdsPaise;
      if (payable < 0) {
        throw const SocietyException('validation', 'TDS cannot exceed total bill amount');
      }

      final vendorsPayableId = await _ledger.accountIdForKey(txn, societyId, 'vendors_payable');

      final journalLines = <JournalLineDraft>[];

      // Debits: Lines
      for (final line in processedLines) {
        journalLines.add(JournalLineDraft(
          accountId: line.accountId,
          debitPaise: line.amountPaise,
          creditPaise: 0,
          vendorId: vendor.id,
          note: line.description,
        ));
      }

      // Debits: Input GST
      if (totalCgst > 0) {
        final inCgstId = await _ledger.accountIdForKey(txn, societyId, 'input_cgst');
        journalLines.add(JournalLineDraft(accountId: inCgstId, debitPaise: totalCgst, creditPaise: 0));
      }
      if (totalSgst > 0) {
        final inSgstId = await _ledger.accountIdForKey(txn, societyId, 'input_sgst');
        journalLines.add(JournalLineDraft(accountId: inSgstId, debitPaise: totalSgst, creditPaise: 0));
      }
      if (totalIgst > 0) {
        final inIgstId = await _ledger.accountIdForKey(txn, societyId, 'input_igst');
        journalLines.add(JournalLineDraft(accountId: inIgstId, debitPaise: totalIgst, creditPaise: 0));
      }

      // Credits: Vendors Payable & TDS Payable
      journalLines.add(JournalLineDraft(
        accountId: vendorsPayableId,
        debitPaise: 0,
        creditPaise: payable,
        vendorId: vendor.id,
        note: 'Bill ${draft.vendorBillNo}',
      ));

      if (tdsPaise > 0) {
        final tdsPayableId = await _ledger.accountIdForKey(txn, societyId, 'tds_payable');
        journalLines.add(JournalLineDraft(
          accountId: tdsPayableId,
          debitPaise: 0,
          creditPaise: tdsPaise,
          vendorId: vendor.id,
          note: 'TDS on ${draft.vendorBillNo}',
        ));
      }

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.postDate,
          sourceType: 'expense_bill',
          narration: draft.narration ?? 'Expense Bill $voucherNo - ${vendor.name} (${draft.vendorBillNo})',
          lines: journalLines,
        ),
      );

      final billId = await _repo.insertExpenseBill(
        societyId: societyId,
        fyId: fy.id,
        voucherNo: voucherNo,
        billKind: 'bill',
        vendorId: vendor.id,
        vendorBillNo: draft.vendorBillNo,
        billDate: draft.billDate,
        postDate: draft.postDate,
        dueDate: draft.dueDate,
        subtotalPaise: subtotal,
        cgstPaise: totalCgst,
        sgstPaise: totalSgst,
        igstPaise: totalIgst,
        tdsSectionId: draft.tdsSectionId,
        tdsRateBp: draft.tdsRateBp,
        tdsPaise: tdsPaise,
        totalPaise: total,
        payablePaise: payable,
        payeeName: draft.payeeName ?? vendor.payeeName ?? vendor.name,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        lines: processedLines,
        executor: txn,
      );

      return billId;
    });
  }

  Future<int> postVendorDebitNote(int societyId, ExpenseBillDraft draft) async {
    if (draft.lines.isEmpty) {
      throw const SocietyException('validation', 'At least one line is required');
    }

    final vendor = await _repo.getVendor(societyId, draft.vendorId);
    if (vendor == null || !vendor.isActive) {
      throw const SocietyException('validation', 'Invalid or inactive vendor');
    }

    final society = await _societyRepo.getSociety(societyId);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.postDate);
      final voucherNo = await _ledger.nextNumber(txn, societyId, fy.id, 'expense_voucher');

      final societyState = society.stateCode.trim().toUpperCase();
      final vendorState = (vendor.stateCode ?? '').trim().toUpperCase();
      final isSameState = vendorState.isEmpty ||
          societyState.isEmpty ||
          societyState == vendorState ||
          (societyState == '27' && vendorState == 'MH') ||
          (societyState == 'MH' && vendorState == '27');
      final isInterState = !isSameState;

      var subtotal = 0;
      var totalCgst = 0;
      var totalSgst = 0;
      var totalIgst = 0;

      final processedLines = <ExpenseLine>[];
      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        if (line.amountPaise <= 0) {
          throw const SocietyException('validation', 'Line amount must be positive');
        }

        var cgst = 0;
        var sgst = 0;
        var igst = 0;

        if (line.gstRateBp > 0) {
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

        processedLines.add(ExpenseLine(
          id: 0,
          societyId: societyId,
          expenseBillId: 0,
          lineNo: i + 1,
          accountId: line.accountId,
          description: line.description,
          hsnSac: line.hsnSac,
          amountPaise: line.amountPaise,
          gstRateBp: line.gstRateBp,
          cgstPaise: cgst,
          sgstPaise: sgst,
          igstPaise: igst,
        ));
      }

      final total = subtotal + totalCgst + totalSgst + totalIgst;

      // Journal: Debit Vendors Payable, Credit Lines, Credit Input GST
      final vendorsPayableId = await _ledger.accountIdForKey(txn, societyId, 'vendors_payable');

      final journalLines = <JournalLineDraft>[
        JournalLineDraft(
          accountId: vendorsPayableId,
          debitPaise: total,
          creditPaise: 0,
          vendorId: vendor.id,
          note: 'Debit Note $voucherNo',
        ),
      ];

      for (final line in processedLines) {
        journalLines.add(JournalLineDraft(
          accountId: line.accountId,
          debitPaise: 0,
          creditPaise: line.amountPaise,
          vendorId: vendor.id,
          note: line.description,
        ));
      }

      if (totalCgst > 0) {
        final inCgstId = await _ledger.accountIdForKey(txn, societyId, 'input_cgst');
        journalLines.add(JournalLineDraft(accountId: inCgstId, debitPaise: 0, creditPaise: totalCgst));
      }
      if (totalSgst > 0) {
        final inSgstId = await _ledger.accountIdForKey(txn, societyId, 'input_sgst');
        journalLines.add(JournalLineDraft(accountId: inSgstId, debitPaise: 0, creditPaise: totalSgst));
      }
      if (totalIgst > 0) {
        final inIgstId = await _ledger.accountIdForKey(txn, societyId, 'input_igst');
        journalLines.add(JournalLineDraft(accountId: inIgstId, debitPaise: 0, creditPaise: totalIgst));
      }

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.postDate,
          sourceType: 'expense_debit_note',
          narration: draft.narration ?? 'Expense Debit Note $voucherNo - ${vendor.name}',
          lines: journalLines,
        ),
      );

      final billId = await _repo.insertExpenseBill(
        societyId: societyId,
        fyId: fy.id,
        voucherNo: voucherNo,
        billKind: 'debit_note',
        vendorId: vendor.id,
        vendorBillNo: draft.vendorBillNo,
        billDate: draft.billDate,
        postDate: draft.postDate,
        dueDate: draft.dueDate,
        subtotalPaise: subtotal,
        cgstPaise: totalCgst,
        sgstPaise: totalSgst,
        igstPaise: totalIgst,
        tdsPaise: 0,
        totalPaise: total,
        payablePaise: total,
        payeeName: draft.payeeName ?? vendor.payeeName ?? vendor.name,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        lines: processedLines,
        executor: txn,
      );

      return billId;
    });
  }

  Future<int> postPayment(int societyId, VendorPaymentDraft draft) async {
    if (draft.amountPaise <= 0) {
      throw const SocietyException('validation', 'Payment amount must be positive');
    }

    return await db.transaction((txn) async {
      final fy = await _ledger.requireOpenYear(txn, societyId, draft.paymentDate);
      final paymentNo = await _ledger.nextNumber(txn, societyId, fy.id, 'vendor_payment');

      final journalLines = <JournalLineDraft>[];
      final allocationsToInsert = <VendorPaymentAllocationDraft>[];

      if (draft.paymentKind == 'against_bills') {
        if (draft.vendorId == null) throw const SocietyException('validation', 'Vendor required for payment against bills');
        final vendor = await _repo.getVendor(societyId, draft.vendorId!, executor: txn);
        if (vendor == null) throw const SocietyException('not_found', 'Vendor not found');

        final openBills = await _repo.getOpenExpenseBills(societyId, vendor.id, executor: txn);
        final totalOpenPayable = openBills.fold<int>(0, (sum, b) => sum + b.duePaise);

        var amountAgainstBills = draft.amountPaise;
        var excessAdvance = 0;

        if (draft.amountPaise > totalOpenPayable) {
          // Excess is posted as advance!
          amountAgainstBills = totalOpenPayable;
          excessAdvance = draft.amountPaise - totalOpenPayable;
        }

        final vendorsPayableId = await _ledger.accountIdForKey(txn, societyId, 'vendors_payable');

        if (amountAgainstBills > 0) {
          journalLines.add(JournalLineDraft(
            accountId: vendorsPayableId,
            debitPaise: amountAgainstBills,
            creditPaise: 0,
            vendorId: vendor.id,
            note: 'Payment $paymentNo against bills',
          ));
        }

        if (excessAdvance > 0) {
          final vendorAdvId = await _ledger.accountIdForKey(txn, societyId, 'vendor_advances');
          journalLines.add(JournalLineDraft(
            accountId: vendorAdvId,
            debitPaise: excessAdvance,
            creditPaise: 0,
            vendorId: vendor.id,
            note: 'Advance payment $paymentNo',
          ));
        }

        // Credit bank/cash
        journalLines.add(JournalLineDraft(
          accountId: draft.bankCashAccountId,
          debitPaise: 0,
          creditPaise: draft.amountPaise,
          note: '${draft.mode.toUpperCase()} $paymentNo',
        ));

        // Allocations: custom or FIFO
        if (draft.allocations != null && draft.allocations!.isNotEmpty) {
          for (final a in draft.allocations!) {
            allocationsToInsert.add(a);
          }
        } else {
          // FIFO allocate
          var remaining = amountAgainstBills;
          for (final ob in openBills) {
            if (remaining <= 0) break;
            final canAlloc = remaining < ob.duePaise ? remaining : ob.duePaise;
            if (canAlloc > 0) {
              allocationsToInsert.add(VendorPaymentAllocationDraft(
                expenseBillId: ob.bill.id,
                allocatedPaise: canAlloc,
              ));
              remaining -= canAlloc;
            }
          }
        }
      } else if (draft.paymentKind == 'advance') {
        if (draft.vendorId == null) throw const SocietyException('validation', 'Vendor required for advance payment');
        final vendor = await _repo.getVendor(societyId, draft.vendorId!, executor: txn);
        if (vendor == null) throw const SocietyException('not_found', 'Vendor not found');

        final vendorAdvId = await _ledger.accountIdForKey(txn, societyId, 'vendor_advances');

        journalLines.add(JournalLineDraft(
          accountId: vendorAdvId,
          debitPaise: draft.amountPaise,
          creditPaise: 0,
          vendorId: vendor.id,
          note: 'Advance payment $paymentNo',
        ));

        journalLines.add(JournalLineDraft(
          accountId: draft.bankCashAccountId,
          debitPaise: 0,
          creditPaise: draft.amountPaise,
          note: '${draft.mode.toUpperCase()} $paymentNo',
        ));
      } else if (draft.paymentKind == 'direct_expense') {
        if (draft.expenseAccountId == null) throw const SocietyException('validation', 'Expense account required for direct expense');

        journalLines.add(JournalLineDraft(
          accountId: draft.expenseAccountId!,
          debitPaise: draft.amountPaise,
          creditPaise: 0,
          vendorId: draft.vendorId,
          note: draft.narration ?? 'Direct expense $paymentNo',
        ));

        journalLines.add(JournalLineDraft(
          accountId: draft.bankCashAccountId,
          debitPaise: 0,
          creditPaise: draft.amountPaise,
          note: '${draft.mode.toUpperCase()} $paymentNo',
        ));
      } else {
        throw SocietyException('validation', 'Invalid payment kind ${draft.paymentKind}');
      }

      final postedJournal = await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.paymentDate,
          sourceType: 'vendor_payment',
          narration: draft.narration ?? 'Vendor Payment $paymentNo (${draft.paymentKind})',
          lines: journalLines,
        ),
      );

      final paymentId = await _repo.insertVendorPayment(
        societyId: societyId,
        fyId: fy.id,
        paymentNo: paymentNo,
        paymentKind: draft.paymentKind,
        vendorId: draft.vendorId,
        expenseAccountId: draft.expenseAccountId,
        paymentDate: draft.paymentDate,
        amountPaise: draft.amountPaise,
        mode: draft.mode,
        instrumentNo: draft.instrumentNo,
        instrumentDate: draft.instrumentDate,
        payeeName: draft.payeeName,
        bankCashAccountId: draft.bankCashAccountId,
        narration: draft.narration,
        journalEntryId: postedJournal.id,
        allocations: allocationsToInsert,
        executor: txn,
      );

      return paymentId;
    });
  }

  Future<void> reverseExpenseBill(int societyId, int billId, String date, String reason) async {
    final bill = await _repo.getExpenseBill(societyId, billId);
    if (bill == null) throw const SocietyException('not_found', 'Expense bill not found');
    if (bill.status == 'reversed') throw const SocietyException('already_reversed', 'Bill is already reversed');

    if (bill.paidPaise > 0) {
      throw const SocietyException('validation', 'Cannot reverse expense bill with payments allocated to it');
    }

    await db.transaction((txn) async {
      final reversalJournal = await _ledger.reverse(
        txn,
        societyId,
        bill.journalEntryId!,
        date,
        reason,
      );

      await _repo.updateExpenseBillStatus(
        societyId,
        billId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: reversalJournal.id,
        executor: txn,
      );
    });
  }

  Future<void> reversePayment(int societyId, int paymentId, String date, String reason) async {
    final payment = await _repo.getVendorPayment(societyId, paymentId);
    if (payment == null) throw const SocietyException('not_found', 'Payment not found');
    if (payment.status == 'reversed') throw const SocietyException('already_reversed', 'Payment is already reversed');

    await db.transaction((txn) async {
      final reversalJournal = await _ledger.reverse(
        txn,
        societyId,
        payment.journalEntryId!,
        date,
        reason,
      );

      await _repo.updatePaymentStatus(
        societyId,
        paymentId,
        'reversed',
        reversalReason: reason,
        reversalEntryId: reversalJournal.id,
        clearAllocations: true,
        executor: txn,
      );
    });
  }

  Future<void> adjustVendorAdvance(int societyId, VendorAdvanceAdjustmentDraft draft) async {
    if (draft.amountPaise <= 0) {
      throw const SocietyException('validation', 'Adjustment amount must be positive');
    }

    final vendor = await _repo.getVendor(societyId, draft.vendorId);
    if (vendor == null) throw const SocietyException('not_found', 'Vendor not found');

    final detail = await _repo.getVendorDetail(societyId, draft.vendorId);
    if (detail == null || detail.advancePaise < draft.amountPaise) {
      throw const SocietyException('validation', 'Adjustment amount exceeds available vendor advance');
    }

    final bill = await _repo.getExpenseBill(societyId, draft.expenseBillId);
    if (bill == null || bill.status != 'posted' || bill.vendorId != draft.vendorId) {
      throw const SocietyException('validation', 'Invalid expense bill for adjustment');
    }

    if (bill.balancePaise < draft.amountPaise) {
      throw const SocietyException('validation', 'Adjustment amount exceeds open bill balance');
    }

    await db.transaction((txn) async {
      final vendorsPayableId = await _ledger.accountIdForKey(txn, societyId, 'vendors_payable');
      final vendorAdvId = await _ledger.accountIdForKey(txn, societyId, 'vendor_advances');

      await _ledger.post(
        txn,
        JournalDraft(
          societyId: societyId,
          entryDate: draft.date,
          sourceType: 'advance_adjustment',
          narration: draft.narration ?? 'Advance adjustment against ${bill.voucherNo} (${bill.vendorBillNo})',
          lines: [
            // Debit Vendors Payable
            JournalLineDraft(
              accountId: vendorsPayableId,
              debitPaise: draft.amountPaise,
              creditPaise: 0,
              vendorId: vendor.id,
              note: 'Advance adjustment against ${bill.voucherNo}',
            ),
            // Credit Vendor Advances
            JournalLineDraft(
              accountId: vendorAdvId,
              debitPaise: 0,
              creditPaise: draft.amountPaise,
              vendorId: vendor.id,
              note: 'Adjusted against bill',
            ),
          ],
        ),
      );

      // Record allocation against advance payment(s)
      final advPayments = await txn.rawQuery('''
        SELECT vp.id, vp.amount_paise,
          COALESCE((SELECT SUM(vpa.allocated_paise) FROM vendor_payment_allocations vpa WHERE vpa.payment_id = vp.id AND vpa.is_active = 1), 0) as allocated
        FROM vendor_payments vp
        WHERE vp.vendor_id = ? AND vp.society_id = ? AND vp.status = 'posted'
        ORDER BY vp.payment_date ASC, vp.id ASC
      ''', [vendor.id, societyId]);

      var remainingToAlloc = draft.amountPaise;
      for (final p in advPayments) {
        if (remainingToAlloc <= 0) break;
        final pId = p['id'] as int;
        final unalloc = (p['amount_paise'] as int) - (p['allocated'] as int);
        if (unalloc > 0) {
          final alloc = remainingToAlloc < unalloc ? remainingToAlloc : unalloc;
          await _repo.insertPaymentAllocation(
            societyId: societyId,
            paymentId: pId,
            expenseBillId: draft.expenseBillId,
            allocatedPaise: alloc,
            allocationDate: draft.date,
            executor: txn,
          );
          remainingToAlloc -= alloc;
        }
      }
    });
  }

  Future<VendorStatement> vendorStatement(int societyId, int vendorId, String from, String to) async {
    final vendor = await _repo.getVendor(societyId, vendorId);
    if (vendor == null) throw const SocietyException('not_found', 'Vendor not found');

    final rows = await _repo.getVendorStatementRows(societyId, vendorId, from, to);
    final openBalance = rows.isEmpty ? 0 : rows.first.balancePaise - (rows.first.creditPaise - rows.first.debitPaise);
    final closeBalance = rows.isEmpty ? openBalance : rows.last.balancePaise;

    return VendorStatement(
      vendor: vendor,
      fromDate: from,
      toDate: to,
      openingBalancePaise: openBalance,
      rows: rows,
      closingBalancePaise: closeBalance,
    );
  }

  // Budget
  Future<void> saveBudget(int societyId, int fyId, List<BudgetDraft> rows) async {
    await db.transaction((txn) async {
      for (final r in rows) {
        await _repo.saveBudget(societyId, fyId, r.accountId, r.amountPaise, executor: txn);
      }
    });
  }

  Future<void> copyBudget(int societyId, int fromFyId, int toFyId) async {
    await _repo.copyBudget(societyId, fromFyId, toFyId);
  }

  Future<BudgetReport> budgetReport(int societyId, int fyId, String asOf) async {
    final fy = await _societyRepo.getFinancialYear(fyId);
    if (fy == null) throw const SocietyException('not_found', 'Financial year not found');

    final expenseAccounts = await _repo.getExpenseAccounts(societyId);
    final budgetRows = await _repo.getBudgets(societyId, fyId);
    final budgetMap = <int, int>{};
    for (final b in budgetRows) {
      budgetMap[b['account_id'] as int] = b['amount_paise'] as int;
    }

    var totalBudget = 0;
    var totalActual = 0;
    final rows = <BudgetRow>[];

    for (final a in expenseAccounts) {
      final accId = a['id'] as int;
      final bPaise = budgetMap[accId] ?? 0;
      final actualPaise = await _repo.getAccountActualExpense(societyId, accId, fy.startDate, asOf);

      final variance = bPaise - actualPaise;
      final variancePct = bPaise > 0 ? (variance * 100.0) / bPaise : (actualPaise > 0 ? -100.0 : 0.0);

      totalBudget += bPaise;
      totalActual += actualPaise;

      rows.add(BudgetRow(
        accountId: accId,
        accountCode: a['code'] as String,
        accountName: a['name'] as String,
        groupName: a['group_name'] as String,
        budgetPaise: bPaise,
        actualPaise: actualPaise,
        variancePaise: variance,
        variancePercent: variancePct,
      ));
    }

    return BudgetReport(
      fyId: fyId,
      asOf: asOf,
      rows: rows,
      totalBudgetPaise: totalBudget,
      totalActualPaise: totalActual,
      totalVariancePaise: totalBudget - totalActual,
    );
  }

  // Expense comparison
  Future<ExpenseComparison> expenseComparison(int societyId, ComparisonRequest request) async {
    final fy = await _societyRepo.getFinancialYear(request.fyId);
    if (fy == null) throw const SocietyException('not_found', 'Financial year not found');

    final periods = <ComparisonPeriod>[];
    if (request.mode == 'monthly') {
      final start = DateTime.parse(fy.startDate);
      for (var m = 0; m < 12; m++) {
        final d1 = DateTime(start.year, start.month + m, 1);
        final d2 = DateTime(start.year, start.month + m + 1, 0);
        final label = '${d1.month.toString().padLeft(2, '0')}/${d1.year}';
        final fromStr = '${d1.year}-${d1.month.toString().padLeft(2, '0')}-01';
        final toStr = '${d2.year}-${d2.month.toString().padLeft(2, '0')}-${d2.day.toString().padLeft(2, '0')}';
        periods.add(ComparisonPeriod(label: label, fromDate: fromStr, toDate: toStr));
      }
    } else if (request.mode == 'quarterly') {
      final start = DateTime.parse(fy.startDate);
      for (var q = 0; q < 4; q++) {
        final d1 = DateTime(start.year, start.month + (q * 3), 1);
        final d2 = DateTime(start.year, start.month + (q * 3) + 3, 0);
        final label = 'Q${q + 1} (${d1.month}-${d2.month})';
        final fromStr = '${d1.year}-${d1.month.toString().padLeft(2, '0')}-01';
        final toStr = '${d2.year}-${d2.month.toString().padLeft(2, '0')}-${d2.day.toString().padLeft(2, '0')}';
        periods.add(ComparisonPeriod(label: label, fromDate: fromStr, toDate: toStr));
      }
    } else {
      periods.add(ComparisonPeriod(label: fy.code, fromDate: fy.startDate, toDate: fy.endDate));
    }

    final expenseAccounts = await _repo.getExpenseAccounts(societyId);
    final filteredAccounts = request.accountIds != null && request.accountIds!.isNotEmpty
        ? expenseAccounts.where((a) => request.accountIds!.contains(a['id'] as int)).toList()
        : expenseAccounts;

    final columns = <ComparisonColumn>[];
    for (final p in periods) {
      final colMap = <int, int>{};
      for (final a in filteredAccounts) {
        final accId = a['id'] as int;
        final actual = await _repo.getAccountActualExpense(societyId, accId, p.fromDate, p.toDate);
        colMap[accId] = actual;
      }
      columns.add(ComparisonColumn(label: p.label, accountAmountPaise: colMap));
    }

    return ExpenseComparison(
      columns: columns,
      accounts: filteredAccounts,
    );
  }

  // Helpers
  Future<ExpenseBill?> getExpenseBill(int societyId, int billId) => _repo.getExpenseBill(societyId, billId);
  Future<List<ExpenseLine>> getExpenseBillLines(int societyId, int billId) => _repo.getExpenseBillLines(societyId, billId);
  Future<List<ExpenseBill>> listExpenseBills(int societyId, {int? vendorId, String? billKind, String? status}) =>
      _repo.listExpenseBills(societyId, vendorId: vendorId, billKind: billKind, status: status);
  Future<List<OpenExpenseBill>> getOpenExpenseBills(int societyId, int vendorId) =>
      _repo.getOpenExpenseBills(societyId, vendorId);
  Future<VendorPayment?> getVendorPayment(int societyId, int paymentId) => _repo.getVendorPayment(societyId, paymentId);
  Future<List<VendorPayment>> listVendorPayments(int societyId, {int? vendorId, String? status}) =>
      _repo.listVendorPayments(societyId, vendorId: vendorId, status: status);
}

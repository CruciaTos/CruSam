import 'package:sqflite/sqflite.dart';

import '../../core/society_exception.dart';
import '../../data/models/billing_models.dart';
import '../../data/models/ledger_models.dart';
import '../../data/models/member_models.dart';
import '../../data/models/society_models.dart';
import '../../data/repositories/billing_repository.dart';
import '../../data/repositories/ledger_repository.dart';
import '../../data/repositories/member_repository.dart';
import '../../data/repositories/society_repository.dart';
import '../ledger/ledger_service.dart';
import 'bill_calculator.dart';
import 'interest_calculator.dart';

class BillRunPreviewResult {
  final BillRunDraft draft;
  final int totalUnits;
  final int billableUnits;
  final int totalPaise;
  final List<String> blockers;
  final List<String> warnings;
  final List<CalculatedBill> calculatedBills;

  const BillRunPreviewResult({
    required this.draft,
    required this.totalUnits,
    required this.billableUnits,
    required this.totalPaise,
    this.blockers = const [],
    this.warnings = const [],
    required this.calculatedBills,
  });
}

class BillingService {
  final Database db;
  final LedgerService ledgerService;
  final BillingRepository _repo;
  final MemberRepository _memberRepo;
  final SocietyRepository _socRepo;

  BillingService(this.db, {required this.ledgerService})
      : _repo = BillingRepository(db),
        _memberRepo = MemberRepository(db),
        _socRepo = SocietyRepository(db);

  // -------------------------------------------------------------
  // Setup: Charge Heads
  // -------------------------------------------------------------

  Future<List<ChargeHead>> listChargeHeads(int societyId, {bool includeInactive = false}) {
    return _repo.listChargeHeads(societyId, includeInactive: includeInactive);
  }

  Future<int> createChargeHead(int societyId, ChargeHeadDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Charge head name is required');
    }
    return db.transaction((txn) => _repo.insertChargeHead(txn, societyId, draft));
  }

  Future<void> updateChargeHead(int societyId, int id, ChargeHeadDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Charge head name is required');
    }
    return db.transaction((txn) => _repo.updateChargeHead(txn, societyId, id, draft));
  }

  Future<void> setChargeHeadActive(int societyId, int id, bool active) {
    return db.transaction((txn) => _repo.setChargeHeadActive(txn, societyId, id, active));
  }

  // -------------------------------------------------------------
  // Setup: Meter Types & Slabs
  // -------------------------------------------------------------

  Future<List<MeterType>> listMeterTypes(int societyId, {bool includeInactive = false}) {
    return _repo.listMeterTypes(societyId, includeInactive: includeInactive);
  }

  Future<int> createMeterType(int societyId, MeterTypeDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Meter type name is required');
    }
    return db.transaction((txn) => _repo.insertMeterType(txn, societyId, draft));
  }

  Future<void> updateMeterType(int societyId, int id, MeterTypeDraft draft) {
    if (draft.name.trim().isEmpty) {
      throw const SocietyException('validation', 'Meter type name is required');
    }
    return db.transaction((txn) => _repo.updateMeterType(txn, societyId, id, draft));
  }

  // -------------------------------------------------------------
  // Setup: Meters & Readings
  // -------------------------------------------------------------

  Future<List<Meter>> listMeters(int societyId, {int? unitId, int? meterTypeId, bool includeInactive = false}) {
    return _repo.listMeters(societyId, unitId: unitId, meterTypeId: meterTypeId, includeInactive: includeInactive);
  }

  Future<int> createMeter(int societyId, MeterDraft draft) {
    return db.transaction((txn) => _repo.insertMeter(txn, societyId, draft));
  }

  Future<int> addMeterReading(
    int societyId,
    int meterId,
    String periodFrom,
    String periodTo,
    String readingDate,
    int readingMilli,
  ) {
    return db.transaction((txn) => _repo.insertMeterReading(
          txn,
          societyId,
          meterId,
          periodFrom,
          periodTo,
          readingDate,
          readingMilli,
        ));
  }

  Future<List<Map<String, dynamic>>> listMeterReadings(int societyId, {int? meterId, String? periodFrom}) {
    return _repo.listMeterReadings(societyId, meterId: meterId, periodFrom: periodFrom);
  }

  // -------------------------------------------------------------
  // Setup: Billing Rules
  // -------------------------------------------------------------

  Future<List<BillingRule>> listRules(int societyId, {int? chargeHeadId, bool includeInactive = false}) {
    return _repo.listRules(societyId, chargeHeadId: chargeHeadId, includeInactive: includeInactive);
  }

  Future<int> createRule(int societyId, BillingRuleDraft draft) {
    return db.transaction((txn) => _repo.insertRule(txn, societyId, draft));
  }

  Future<void> updateRule(int societyId, int id, BillingRuleDraft draft) {
    return db.transaction((txn) => _repo.updateRule(txn, societyId, id, draft));
  }

  Future<void> setRuleActive(int societyId, int id, bool active) {
    return db.transaction((txn) => _repo.setRuleActive(txn, societyId, id, active));
  }

  // -------------------------------------------------------------
  // Bill Run Calculation Context Helper
  // -------------------------------------------------------------

  Future<_CalcContext> _buildCalcContext(DatabaseExecutor executor, int societyId, String billDate) async {
    final society = await _socRepo.getSociety(societyId, executor);
    if (society == null) throw SocietyException('wrong_society', 'Society not found: $societyId');

    final heads = await _repo.listChargeHeads(societyId, executor: executor);
    final headsMap = {for (final h in heads) h.id: h};

    final meterTypes = await _repo.listMeterTypes(societyId, executor: executor);
    final meterTypesMap = {for (final m in meterTypes) m.id: m};

    final rules = await _repo.listRules(societyId, executor: executor);

    final roundMode = await _socRepo.getSetting(societyId, 'billing.round_mode', executor) ?? 'none';
    final limitStr = await _socRepo.getSetting(societyId, 'gst.member_limit_paise', executor);
    final memberLimitPaise = limitStr != null ? int.tryParse(limitStr) : null;

    final gstEffectiveFrom = await _socRepo.getSetting(societyId, 'gst.effective_from', executor) ?? society.gstEffectiveFrom;

    return _CalcContext(
      society: society,
      headsMap: headsMap,
      meterTypesMap: meterTypesMap,
      rules: rules,
      roundMode: roundMode,
      memberLimitPaise: memberLimitPaise,
      gstEffectiveFrom: gstEffectiveFrom,
    );
  }

  Future<int?> _resolveMeterConsumption(
    DatabaseExecutor executor,
    Meter meter,
    String periodFrom,
    String periodTo,
  ) async {
    final currentRows = await executor.query(
      'meter_readings',
      where: 'meter_id = ? AND period_to <= ?',
      whereArgs: [meter.id, periodTo],
      orderBy: 'period_to DESC',
      limit: 1,
    );
    if (currentRows.isEmpty) return null;
    final currentReading = MeterReading.fromMap(currentRows.first);

    final prevRows = await executor.query(
      'meter_readings',
      where: 'meter_id = ? AND period_to <= ? AND id <> ?',
      whereArgs: [meter.id, currentReading.periodFrom, currentReading.id],
      orderBy: 'period_to DESC',
      limit: 1,
    );
    final prevMilli = prevRows.isNotEmpty
        ? (prevRows.first['reading_milli'] as int)
        : meter.openingReadingMilli;

    return currentReading.readingMilli - prevMilli;
  }

  ChargeHead? _findLateInterestHead(Map<int, ChargeHead> headsMap) {
    for (final h in headsMap.values) {
      if (h.systemKey == 'late_interest' || h.headKind == 'interest') {
        return h;
      }
    }
    return null;
  }

  Future<Map<int, UnitInterestResult>> _resolveInterestForUnits(
    DatabaseExecutor executor,
    int societyId,
    List<UnitRow> units,
    String billDate,
    String? interestThrough,
  ) async {
    final enabled = await _socRepo.getSetting(societyId, 'interest.enabled', executor);
    if (enabled != '1') return {};

    final startDate = await _socRepo.getSetting(societyId, 'interest.start_date', executor) ?? '2000-01-01';
    final graceStr = await _socRepo.getSetting(societyId, 'interest.grace_days', executor);
    final graceDays = graceStr != null ? (int.tryParse(graceStr) ?? 0) : 0;
    final rateStr = await _socRepo.getSetting(societyId, 'interest.rate_bp', executor);
    final rateBp = rateStr != null ? (int.tryParse(rateStr) ?? 1200) : 1200;

    final targetDate = interestThrough ??
        DateTime.parse(billDate).subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);

    final results = <int, UnitInterestResult>{};

    for (final unit in units) {
      final billsRows = await executor.rawQuery(
        "SELECT id, bill_date, due_date FROM bills WHERE society_id = ? AND unit_id = ? AND status = 'posted' AND bill_date <= ? ORDER BY due_date ASC, bill_date ASC, id ASC",
        [societyId, unit.id, targetDate],
      );

      final billResults = <BillInterestResult>[];
      var unitTotalInterest = 0;

      for (final b in billsRows) {
        final bId = b['id'] as int;
        final bDate = b['bill_date'] as String;
        final dDate = b['due_date'] as String;

        final lastAccRows = await executor.rawQuery(
          'SELECT MAX(to_date) as last_to FROM interest_accruals WHERE source_bill_id = ?',
          [bId],
        );
        final lastTo = lastAccRows.first['last_to'] as String?;

        final lineRows = await executor.rawQuery(
          'SELECT bl.id, bl.amount_paise, bl.payable_paise, ch.is_interest_bearing '
          'FROM bill_lines bl '
          'JOIN charge_heads ch ON bl.charge_head_id = ch.id '
          'WHERE bl.bill_id = ?',
          [bId],
        );

        final linesInfo = <SourceBillLineInfo>[];
        for (final lr in lineRows) {
          final blId = lr['id'] as int;
          final amt = (lr['amount_paise'] as int?) ?? 0;
          final payable = (lr['payable_paise'] as int?) ?? 0;
          final isIb = (lr['is_interest_bearing'] as int?) == 1;

          final allocRows = await executor.rawQuery(
            "SELECT allocation_date, allocated_paise FROM bill_allocations WHERE bill_line_id = ? AND is_active = 1 AND allocation_date <= ?",
            [blId, targetDate],
          );
          final allocs = allocRows
              .map((ar) => LineAllocationInfo(
                    allocationDate: ar['allocation_date'] as String,
                    allocatedPaise: (ar['allocated_paise'] as int?) ?? 0,
                  ))
              .toList();

          linesInfo.add(SourceBillLineInfo(
            lineId: blId,
            amountPaise: amt,
            payablePaise: payable,
            isInterestBearing: isIb,
            allocations: allocs,
          ));
        }

        final sourceInfo = SourceBillInfo(
          billId: bId,
          billDate: bDate,
          dueDate: dDate,
          lastAccruedToDate: lastTo,
          lines: linesInfo,
        );

        final bRes = InterestCalculator.calculateForSourceBill(
          bill: sourceInfo,
          interestStartDate: startDate,
          graceDays: graceDays,
          rateBp: rateBp,
          interestThrough: targetDate,
        );

        if (bRes != null) {
          billResults.add(bRes);
          unitTotalInterest += bRes.amountPaise;
        }
      }

      if (unitTotalInterest > 0) {
        results[unit.id] = UnitInterestResult(
          unitId: unit.id,
          totalInterestPaise: unitTotalInterest,
          billResults: billResults,
        );
      }
    }

    return results;
  }

  // -------------------------------------------------------------
  // Bill Run: Preview
  // -------------------------------------------------------------

  Future<BillRunPreviewResult> previewBillRun(int societyId, BillRunDraft draft) async {
    final calcCtx = await _buildCalcContext(db, societyId, draft.billDate);
    final unitsRes = await _memberRepo.listUnits(societyId, page: const PageRequest(limit: 5000));
    final units = unitsRes.rows;

    final blockers = <String>[];
    final warnings = <String>[];
    final calculatedBills = <CalculatedBill>[];
    var totalPaise = 0;

    final interestMap = await _resolveInterestForUnits(db, societyId, units, draft.billDate, draft.interestThrough);
    final lateInterestHead = _findLateInterestHead(calcCtx.headsMap);

    for (final unit in units) {
      if (unit.billToName == null || unit.billToName!.isEmpty) {
        blockers.add('Unit ${unit.blockName}-${unit.unitNo} has no active bill-to person.');
      }

      // Check meter consumptions for metered rules
      final consumptions = <int, int>{};
      for (final r in calcCtx.rules) {
        if (r.ruleType == 'metered_slab' && r.meterTypeId != null) {
          final mList = await _repo.listMeters(societyId, unitId: unit.id, meterTypeId: r.meterTypeId!);
          if (mList.isEmpty) {
            blockers.add('Unit ${unit.blockName}-${unit.unitNo} has no meter for ${r.chargeHeadName}.');
            continue;
          }
          final meter = mList.first;
          final consumption = await _resolveMeterConsumption(db, meter, draft.periodFrom, draft.periodTo);
          if (consumption == null) {
            blockers.add('Unit ${unit.blockName}-${unit.unitNo} has missing meter reading for ${r.chargeHeadName}.');
          } else if (consumption < 0) {
            blockers.add('Unit ${unit.blockName}-${unit.unitNo} has negative meter consumption ($consumption).');
          } else {
            consumptions[r.meterTypeId!] = consumption;
          }
        }
      }

      final unitInterest = interestMap[unit.id];
      final calc = BillCalculator.calculateUnitBill(
        unit: unit,
        billDate: draft.billDate,
        frequency: draft.frequency,
        activeRules: calcCtx.rules,
        headsMap: calcCtx.headsMap,
        meterTypesMap: calcCtx.meterTypesMap,
        meterConsumptions: consumptions,
        societyGstRegistered: calcCtx.society.gstRegistered,
        gstEffectiveFrom: calcCtx.gstEffectiveFrom,
        memberGstLimitPaise: calcCtx.memberLimitPaise,
        roundMode: calcCtx.roundMode,
        lateInterestPaise: unitInterest?.totalInterestPaise ?? 0,
        lateInterestHead: lateInterestHead,
      );

      if (calc.lines.isNotEmpty) {
        calculatedBills.add(calc);
        totalPaise += calc.totalPaise;
      } else {
        warnings.add('Unit ${unit.blockName}-${unit.unitNo} has zero charges.');
      }
    }

    return BillRunPreviewResult(
      draft: draft,
      totalUnits: units.length,
      billableUnits: calculatedBills.length,
      totalPaise: totalPaise,
      blockers: blockers,
      warnings: warnings,
      calculatedBills: calculatedBills,
    );
  }

  // -------------------------------------------------------------
  // Bill Run: Create Draft
  // -------------------------------------------------------------

  Future<int> createDraftRun(int societyId, BillRunDraft draft) async {
    return db.transaction((txn) async {
      // 1. Verify period doesn't already have an active/draft run
      final dupRun = await txn.query(
        'bill_runs',
        where: "society_id = ? AND period_from = ? AND period_to = ? AND status <> 'cancelled'",
        whereArgs: [societyId, draft.periodFrom, draft.periodTo],
      );
      if (dupRun.isNotEmpty) {
        throw SocietyException(
          'duplicate_run',
          'A bill run already exists for period ${draft.periodFrom} to ${draft.periodTo}',
        );
      }

      // 2. Financial Year
      final fy = await ledgerService.requireOpenYear(txn, societyId, draft.billDate);

      // 3. Units and context
      final calcCtx = await _buildCalcContext(txn, societyId, draft.billDate);
      final unitsRes = await _memberRepo.listUnits(societyId, executor: txn, page: const PageRequest(limit: 5000));
      final units = unitsRes.rows;

      // 4. Validate all units have a bill-to person
      for (final u in units) {
        if (u.billToName == null || u.billToName!.isEmpty) {
          throw SocietyException(
            'missing_bill_to',
            'Unit "${u.blockName}-${u.unitNo}" has no active bill-to person. Assign a member first.',
          );
        }
      }

      // 5. Insert draft BillRun
      final runId = await _repo.insertBillRun(txn, societyId, fy.id, draft);

      final interestMap = await _resolveInterestForUnits(txn, societyId, units, draft.billDate, draft.interestThrough);
      final lateInterestHead = _findLateInterestHead(calcCtx.headsMap);

      // 6. Generate and insert bills and lines
      for (final unit in units) {
        // Meter consumptions
        final consumptions = <int, int>{};
        for (final r in calcCtx.rules) {
          if (r.ruleType == 'metered_slab' && r.meterTypeId != null) {
            final mList = await _repo.listMeters(societyId, unitId: unit.id, meterTypeId: r.meterTypeId!, executor: txn);
            if (mList.isEmpty) {
              throw SocietyException(
                'missing_meter',
                'Unit "${unit.blockName}-${unit.unitNo}" has no meter for ${r.chargeHeadName}.',
              );
            }
            final meter = mList.first;
            final consumption = await _resolveMeterConsumption(txn, meter, draft.periodFrom, draft.periodTo);
            if (consumption == null) {
              throw SocietyException(
                'missing_meter_reading',
                'Unit "${unit.blockName}-${unit.unitNo}" has missing meter reading for ${r.chargeHeadName}.',
              );
            }
            if (consumption < 0) {
              throw SocietyException(
                'negative_consumption',
                'Unit "${unit.blockName}-${unit.unitNo}" has negative meter consumption ($consumption).',
              );
            }
            consumptions[r.meterTypeId!] = consumption;
          }
        }

        final unitInterest = interestMap[unit.id];
        final calc = BillCalculator.calculateUnitBill(
          unit: unit,
          billDate: draft.billDate,
          frequency: draft.frequency,
          activeRules: calcCtx.rules,
          headsMap: calcCtx.headsMap,
          meterTypesMap: calcCtx.meterTypesMap,
          meterConsumptions: consumptions,
          societyGstRegistered: calcCtx.society.gstRegistered,
          gstEffectiveFrom: calcCtx.gstEffectiveFrom,
          memberGstLimitPaise: calcCtx.memberLimitPaise,
          roundMode: calcCtx.roundMode,
          lateInterestPaise: unitInterest?.totalInterestPaise ?? 0,
          lateInterestHead: lateInterestHead,
        );

        if (calc.lines.isEmpty) continue;

        // Get bill to person ID
        final billToRows = await txn.query(
          'unit_people',
          columns: ['person_id'],
          where: 'unit_id = ? AND is_bill_to = 1 AND to_date IS NULL',
          whereArgs: [unit.id],
          limit: 1,
        );
        final billToPersonId = billToRows.isNotEmpty ? billToRows.first['person_id'] as int? : null;

        final billId = await _repo.insertBill(txn, {
          'society_id': societyId,
          'fy_id': fy.id,
          'run_id': runId,
          'bill_kind': 'regular',
          'unit_id': unit.id,
          'bill_to_person_id': billToPersonId,
          'bill_to_name': unit.billToName ?? 'Occupant',
          'bill_date': draft.billDate,
          'due_date': draft.dueDate,
          'period_from': draft.periodFrom,
          'period_to': draft.periodTo,
          'subtotal_paise': calc.subtotalPaise,
          'cgst_paise': calc.cgstPaise,
          'sgst_paise': calc.sgstPaise,
          'igst_paise': calc.igstPaise,
          'round_off_paise': calc.roundOffPaise,
          'total_paise': calc.totalPaise,
          'status': 'draft',
        });

        if (unitInterest != null) {
          for (final bRes in unitInterest.billResults) {
            await txn.insert('interest_accruals', {
              'society_id': societyId,
              'run_id': runId,
              'target_bill_id': billId,
              'source_bill_id': bRes.sourceBillId,
              'from_date': bRes.fromDate,
              'to_date': bRes.toDate,
              'amount_paise': bRes.amountPaise,
              'working_json': bRes.workingJson,
            });
          }
        }

        for (var i = 0; i < calc.lines.length; i++) {
          final line = calc.lines[i];
          await _repo.insertBillLine(txn, {
            'society_id': societyId,
            'bill_id': billId,
            'line_no': i + 1,
            'charge_head_id': line.head.id,
            'line_kind': line.lineKind,
            'description': line.description,
            'quantity_milli': line.quantityMilli,
            'rate_paise': line.ratePaise,
            'amount_paise': line.amountPaise,
            'gst_rate_bp': line.gstRateBp,
            'cgst_paise': line.cgstPaise,
            'sgst_paise': line.sgstPaise,
            'igst_paise': line.igstPaise,
            'round_off_paise': line.roundOffPaise,
            'payable_paise': line.payablePaise,
            'is_interest_bearing': line.isInterestBearing ? 1 : 0,
          });
        }
      }

      await _socRepo.insertAudit(
        txn,
        societyId,
        'create_draft',
        'bill_run',
        runId,
        'Created draft bill run for ${draft.periodFrom} to ${draft.periodTo}',
      );

      return runId;
    });
  }

  // -------------------------------------------------------------
  // Bill Run: Cancel Draft
  // -------------------------------------------------------------

  Future<void> cancelDraftRun(int societyId, int runId) async {
    return db.transaction((txn) async {
      final run = await _repo.getBillRun(txn, runId);
      if (run == null || run.societyId != societyId) {
        throw SocietyException('not_found', 'Bill run not found: $runId');
      }
      if (!run.isDraft) {
        throw SocietyException('validation', 'Only draft bill runs can be cancelled');
      }

      await _repo.deleteDraftRun(txn, runId);
      await _socRepo.insertAudit(
        txn,
        societyId,
        'cancel',
        'bill_run',
        runId,
        'Cancelled draft bill run $runId',
      );
    });
  }

  // -------------------------------------------------------------
  // Bill Run: Post Run
  // -------------------------------------------------------------

  Future<void> postDraftRun(int societyId, int runId) => postBillRun(societyId, runId);

  Future<void> postBillRun(int societyId, int runId) async {
    return db.transaction((txn) async {
      final run = await _repo.getBillRun(txn, runId);
      if (run == null || run.societyId != societyId) {
        throw SocietyException('not_found', 'Bill run not found: $runId');
      }
      if (!run.isDraft) {
        throw SocietyException('validation', 'Only draft bill runs can be posted');
      }

      final fy = await ledgerService.requireOpenYear(txn, societyId, run.billDate);

      // System accounts needed for posting
      final memRecAccId = await ledgerService.accountIdForKey(txn, societyId, 'members_receivable');
      final outCgstAccId = await ledgerService.accountIdForKey(txn, societyId, 'output_cgst');
      final outSgstAccId = await ledgerService.accountIdForKey(txn, societyId, 'output_sgst');

      // Round off account (find or use general group)
      int? roundOffAccId;
      final roundRows = await txn.query(
        'accounts',
        columns: ['id'],
        where: 'society_id = ? AND code = ?',
        whereArgs: [societyId, '4702'], // 4702 or round_off
        limit: 1,
      );
      if (roundRows.isNotEmpty) {
        roundOffAccId = roundRows.first['id'] as int;
      } else {
        // Fallback to general expense
        final expRows = await txn.query(
          'accounts',
          columns: ['id'],
          where: 'society_id = ? AND code = ?',
          whereArgs: [societyId, '4701'],
          limit: 1,
        );
        roundOffAccId = expRows.first['id'] as int;
      }

      final billsRes = await _repo.listBills(societyId, runId: runId, executor: txn, page: const PageRequest(limit: 5000));
      final bills = billsRes.rows;

      final nowIso = DateTime.now().toUtc().toIso8601String();

      for (final billItem in bills) {
        final bill = await _repo.getBill(txn, billItem.id);
        if (bill == null) continue;

        // 1. Reserve bill number
        final billNo = await ledgerService.nextNumber(txn, societyId, fy.id, 'member_bill');

        // 2. Build double-entry journal lines:
        // Debit: members_receivable with unitId for bill.totalPaise
        // Credit: each head's account_id for line.amountPaise
        // Credit: output_cgst, output_sgst, round_off
        final jLines = <JournalLineDraft>[];

        jLines.add(JournalLineDraft(
          accountId: memRecAccId,
          debitPaise: bill.totalPaise,
          unitId: bill.unitId,
          note: 'Maintenance bill $billNo',
        ));

        for (final line in bill.lines) {
          final head = await _repo.getChargeHead(txn, line.chargeHeadId);
          if (head == null) continue;

          jLines.add(JournalLineDraft(
            accountId: head.accountId,
            creditPaise: line.amountPaise,
            note: line.description ?? head.name,
          ));

          if (line.cgstPaise > 0) {
            jLines.add(JournalLineDraft(
              accountId: outCgstAccId,
              creditPaise: line.cgstPaise,
              note: 'CGST on ${head.name}',
            ));
          }
          if (line.sgstPaise > 0) {
            jLines.add(JournalLineDraft(
              accountId: outSgstAccId,
              creditPaise: line.sgstPaise,
              note: 'SGST on ${head.name}',
            ));
          }
          if (line.roundOffPaise > 0) {
            jLines.add(JournalLineDraft(
              accountId: roundOffAccId,
              creditPaise: line.roundOffPaise,
              note: 'Round off',
            ));
          } else if (line.roundOffPaise < 0) {
            jLines.add(JournalLineDraft(
              accountId: roundOffAccId,
              debitPaise: -line.roundOffPaise,
              note: 'Round off',
            ));
          }
        }

        final journalDraft = JournalDraft(
          societyId: societyId,
          entryDate: bill.billDate,
          sourceType: 'member_bill',
          sourceId: bill.id,
          narration: 'Maintenance bill $billNo for Unit ${bill.blockName}-${bill.unitNo}',
          lines: jLines,
        );

        final postedJ = await ledgerService.post(txn, journalDraft);

        await _repo.updateBillStatus(
          txn,
          bill.id,
          'posted',
          journalEntryId: postedJ.id,
          billNo: billNo,
        );
      }

      await _repo.updateBillRunStatus(txn, runId, 'posted', nowIso);

      await _socRepo.insertAudit(
        txn,
        societyId,
        'post',
        'bill_run',
        runId,
        'Posted bill run for ${run.periodFrom} to ${run.periodTo} (${bills.length} bills)',
      );
    });
  }

  // -------------------------------------------------------------
  // Manual & Debit Note Bills (Task 4.5)
  // -------------------------------------------------------------

  Future<Bill> createManualBill(int societyId, ManualBillDraft draft) async {
    return db.transaction((txn) async {
      final unit = await _memberRepo.getUnit(txn, draft.unitId);
      if (unit == null || unit.societyId != societyId) {
        throw SocietyException('wrong_society', 'Unit does not belong to this society');
      }

      final fy = await ledgerService.requireOpenYear(txn, societyId, draft.billDate);

      final billToRows = await txn.query(
        'unit_people',
        columns: ['person_id'],
        where: 'unit_id = ? AND is_bill_to = 1 AND to_date IS NULL',
        whereArgs: [unit.id],
        limit: 1,
      );
      final billToPersonId = billToRows.isNotEmpty ? billToRows.first['person_id'] as int? : null;

      var subtotal = 0;
      var totalCgst = 0;
      var totalSgst = 0;
      var totalRoundOff = 0;
      var totalPaise = 0;

      for (final line in draft.lines) {
        subtotal += line.amountPaise;
        totalCgst += line.cgstPaise;
        totalSgst += line.sgstPaise;
        totalRoundOff += line.roundOffPaise;
        totalPaise += line.payablePaise;
      }

      final docType = draft.billKind == 'debit_note' ? 'debit_note' : 'member_bill';
      final billNo = await ledgerService.nextNumber(txn, societyId, fy.id, docType);

      final billId = await _repo.insertBill(txn, {
        'society_id': societyId,
        'fy_id': fy.id,
        'bill_no': billNo,
        'bill_kind': draft.billKind,
        'unit_id': unit.id,
        'bill_to_person_id': billToPersonId,
        'bill_to_name': unit.billToName ?? 'Occupant',
        'bill_date': draft.billDate,
        'due_date': draft.dueDate,
        'period_from': draft.periodFrom,
        'period_to': draft.periodTo,
        'subtotal_paise': subtotal,
        'cgst_paise': totalCgst,
        'sgst_paise': totalSgst,
        'round_off_paise': totalRoundOff,
        'total_paise': totalPaise,
        'status': 'posted',
        'comment': draft.comment?.trim(),
      });

      for (var i = 0; i < draft.lines.length; i++) {
        final line = draft.lines[i];
        await _repo.insertBillLine(txn, {
          'society_id': societyId,
          'bill_id': billId,
          'line_no': i + 1,
          'charge_head_id': line.chargeHeadId,
          'line_kind': line.lineKind,
          'description': line.description,
          'quantity_milli': line.quantityMilli,
          'rate_paise': line.ratePaise,
          'amount_paise': line.amountPaise,
          'gst_rate_bp': line.gstRateBp,
          'cgst_paise': line.cgstPaise,
          'sgst_paise': line.sgstPaise,
          'round_off_paise': line.roundOffPaise,
          'payable_paise': line.payablePaise,
          'is_interest_bearing': line.isInterestBearing ? 1 : 0,
        });
      }

      // Post journal
      final memRecAccId = await ledgerService.accountIdForKey(txn, societyId, 'members_receivable');
      final outCgstAccId = await ledgerService.accountIdForKey(txn, societyId, 'output_cgst');
      final outSgstAccId = await ledgerService.accountIdForKey(txn, societyId, 'output_sgst');

      final jLines = <JournalLineDraft>[
        JournalLineDraft(
          accountId: memRecAccId,
          debitPaise: totalPaise,
          unitId: unit.id,
          note: '${draft.billKind == "debit_note" ? "Debit note" : "Manual bill"} $billNo',
        ),
      ];

      for (final line in draft.lines) {
        final head = await _repo.getChargeHead(txn, line.chargeHeadId);
        if (head == null) continue;

        jLines.add(JournalLineDraft(
          accountId: head.accountId,
          creditPaise: line.amountPaise,
          note: line.description ?? head.name,
        ));
        if (line.cgstPaise > 0) {
          jLines.add(JournalLineDraft(
            accountId: outCgstAccId,
            creditPaise: line.cgstPaise,
            note: 'CGST on ${head.name}',
          ));
        }
        if (line.sgstPaise > 0) {
          jLines.add(JournalLineDraft(
            accountId: outSgstAccId,
            creditPaise: line.sgstPaise,
            note: 'SGST on ${head.name}',
          ));
        }
      }

      final jDraft = JournalDraft(
        societyId: societyId,
        entryDate: draft.billDate,
        sourceType: draft.billKind == 'debit_note' ? 'debit_note' : 'member_bill',
        sourceId: billId,
        narration: '${draft.billKind == "debit_note" ? "Debit note" : "Manual bill"} $billNo for Unit ${unit.blockName}-${unit.unitNo}',
        lines: jLines,
      );

      final postedJ = await ledgerService.post(txn, jDraft);

      await _repo.updateBillStatus(txn, billId, 'posted', journalEntryId: postedJ.id);

      await _socRepo.insertAudit(
        txn,
        societyId,
        'create',
        'bill',
        billId,
        'Created ${draft.billKind} bill $billNo',
      );

      return (await _repo.getBill(txn, billId))!;
    });
  }

  Future<int> postManualBill(int societyId, ManualBillDraft draft) async {
    final bill = await createManualBill(societyId, draft);
    return bill.id;
  }

  // -------------------------------------------------------------
  // Bill Details & List
  // -------------------------------------------------------------

  Future<PageResult<BillRun>> listBillRuns(int societyId, {String? status, PageRequest page = const PageRequest()}) {
    return _repo.listBillRuns(societyId, status: status, page: page);
  }

  Future<BillRun?> getBillRun(int runId) {
    return _repo.getBillRun(db, runId);
  }

  Future<PageResult<Bill>> listBills(
    int societyId, {
    int? runId,
    int? unitId,
    String? status,
    String? billKind,
    PageRequest page = const PageRequest(),
  }) {
    return _repo.listBills(societyId, runId: runId, unitId: unitId, status: status, billKind: billKind, page: page);
  }

  Future<Bill?> getBill(int billId) {
    return _repo.getBill(db, billId);
  }

  Future<void> reverseBill(int societyId, int billId, String reversalDate, String reason) async {
    return db.transaction((txn) async {
      final bill = await _repo.getBill(txn, billId);
      if (bill == null || bill.societyId != societyId) {
        throw SocietyException('not_found', 'Bill not found: $billId');
      }
      if (bill.status != 'posted') {
        throw const SocietyException('validation', 'Only posted bills can be reversed');
      }

      final allocCount = Sqflite.firstIntValue(await txn.rawQuery(
        'SELECT COUNT(*) FROM bill_allocations ba JOIN bill_lines bl ON ba.bill_line_id = bl.id WHERE bl.bill_id = ? AND ba.is_active = 1',
        [billId],
      )) ?? 0;
      if (allocCount > 0) {
        throw const SocietyException('has_allocations', 'Cannot reverse bill with active receipt allocations');
      }

      final interestCount = Sqflite.firstIntValue(await txn.rawQuery(
        "SELECT COUNT(*) FROM interest_accruals ia JOIN bills b ON ia.target_bill_id = b.id WHERE ia.source_bill_id = ? AND b.status = 'posted'",
        [billId],
      )) ?? 0;
      if (interestCount > 0) {
        throw const SocietyException('has_interest_accruals', 'Cannot reverse bill because a later posted interest accrual references it');
      }

      int? reversalEntryId;
      if (bill.journalEntryId != null) {
        final posted = await ledgerService.reverse(
          txn,
          societyId,
          bill.journalEntryId!,
          reversalDate,
          'Reversal of bill ${bill.billNo ?? billId}: $reason',
        );
        reversalEntryId = posted.id;
      }

      await txn.update(
        'bills',
        {
          'status': 'reversed',
          'reversal_entry_id': reversalEntryId,
          'reversal_reason': reason,
        },
        where: 'id = ?',
        whereArgs: [billId],
      );

      await _socRepo.insertAudit(
        txn,
        societyId,
        'reverse',
        'bill',
        billId,
        'Reversed bill ${bill.billNo ?? billId}: $reason',
      );
    });
  }
}

class _CalcContext {
  final Society society;
  final Map<int, ChargeHead> headsMap;
  final Map<int, MeterType> meterTypesMap;
  final List<BillingRule> rules;
  final String roundMode;
  final int? memberLimitPaise;
  final String? gstEffectiveFrom;

  const _CalcContext({
    required this.society,
    required this.headsMap,
    required this.meterTypesMap,
    required this.rules,
    required this.roundMode,
    this.memberLimitPaise,
    this.gstEffectiveFrom,
  });
}

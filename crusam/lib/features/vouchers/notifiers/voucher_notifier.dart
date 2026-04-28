import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import '../../../core/constants/app_constants.dart';
import '../../../data/db/database_helper.dart';
import '../../../data/models/employee_model.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/voucher_row_model.dart';

class VoucherNotifier extends ChangeNotifier {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final VoucherNotifier instance = VoucherNotifier._();
  VoucherNotifier._();
  VoucherNotifier();          // keep public ctor for tests

  // ── State ──────────────────────────────────────────────────────────────────
  List<EmployeeModel>  employees     = [];
  List<VoucherModel>   savedVouchers = [];
  CompanyConfigModel   config        = const CompanyConfigModel();
  bool                 isLoading     = false;

  VoucherModel current = VoucherModel(
    date:            DateTime.now().toIso8601String().split('T').first,
    deptCode:        AppConstants.deptCodes.first,
    itemDescription: AppConstants.itemDescriptions.first,
    clientName:      AppConstants.defaultClientName,
    clientAddress:   AppConstants.defaultClientAddress,
    clientGstin:     AppConstants.defaultClientGstin,
  );

  // ── Computed ───────────────────────────────────────────────────────────────
  double get baseTotal   => current.rows.fold(0, (a, r) => a + r.amount);
  double get cgst        => baseTotal * AppConstants.cgstRate;
  double get sgst        => baseTotal * AppConstants.sgstRate;
  double get totalTax    => cgst + sgst;
  double get rawTotal    => baseTotal + totalTax;
  double get finalTotal  => rawTotal.roundToDouble();
  double get roundOff    => finalTotal - rawTotal;

  String get _companyBankIfscPrefix {
    final ifsc = config.ifscCode.trim().toUpperCase();
    if (ifsc.length >= 4) return ifsc.substring(0, 4);
    if (config.bankName.toLowerCase().contains('idbi')) return 'IBKL';
    return ifsc;
  }

  bool _isCompanyBankTransfer(VoucherRowModel row) {
    final rowIfsc = row.ifscCode.trim().toUpperCase();
    final bankName = row.bankDetails.trim().toLowerCase();
    final prefix = _companyBankIfscPrefix;

    return (prefix.isNotEmpty && rowIfsc.startsWith(prefix)) ||
        bankName.contains('idbi');
  }

  double get idbiToOther => current.rows
      .where((r) => !_isCompanyBankTransfer(r))
      .fold(0, (a, r) => a + r.amount);

  double get idbiToIdbi  => current.rows
      .where(_isCompanyBankTransfer)
      .fold(0, (a, r) => a + r.amount);

  VoucherModel get enriched => current.copyWith(
    baseTotal: baseTotal, cgst: cgst, sgst: sgst,
    totalTax:  totalTax,  roundOff: roundOff, finalTotal: finalTotal,
  );

  void _syncSalaryMetadata() {
    final n = SalaryDataNotifier.instance;
    n.setDateIso(current.date);
    n.setBillNo(current.billNo);
    n.setPoNo(current.poNo);
    n.setClientName(current.clientName);
    n.setClientAddr(current.clientAddress);
    n.setClientGstin(current.clientGstin);
  }

  // ── Load ───────────────────────────────────────────────────────────────────
  Future<void> loadDependencies() async {
    if (isLoading) return;
    isLoading = true;
    notifyListeners();
    try {
      final empMaps = await DatabaseHelper.instance.getAllEmployees();
      employees = empMaps.map(EmployeeModel.fromMap).toList();

      final cfgMap = await DatabaseHelper.instance.getCompanyConfig();
      if (cfgMap != null) config = CompanyConfigModel.fromMap(cfgMap);

      final vMaps = await DatabaseHelper.instance.getAllVouchers();
      final loaded = <VoucherModel>[];
      for (final v in vMaps) {
        final rowMaps = await DatabaseHelper.instance
            .getRowsByVoucherId(v['id'] as int);
        loaded.add(VoucherModel.fromDbMap(
          v,
          rowMaps.map(VoucherRowModel.fromDbMap).toList(),
        ));
      }
      savedVouchers = loaded;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Mutations ──────────────────────────────────────────────────────────────
  void update(VoucherModel Function(VoucherModel) fn) {
    current = fn(current);
    _syncSalaryMetadata();
    notifyListeners();
  }

  void addRow() {
    final id = '${DateTime.now().millisecondsSinceEpoch}'
               '${Random().nextInt(9999)}';
    final row = VoucherRowModel(
      id:                id,
      deptCode:          current.deptCode,
      debitAccountNumber:config.accountNo,
      debitAccountName:  config.companyName,
    );
    current = current.copyWith(rows: [...current.rows, row]);
    _syncSalaryMetadata();
    notifyListeners();
  }

  void updateRow(String id, VoucherRowModel Function(VoucherRowModel) fn) {
    current = current.copyWith(
      rows: current.rows.map((r) => r.id == id ? fn(r) : r).toList(),
    );
    _syncSalaryMetadata();
    notifyListeners();
  }

  void selectEmployee(String rowId, String empId) {
    final emp = employees.firstWhere(
      (e) => e.id.toString() == empId,
      orElse: () => const EmployeeModel(name: ''),
    );
    updateRow(
      rowId,
      (r) => r.copyWith(
        employeeId:    empId,
        employeeName:  emp.name,
        ifscCode:      emp.ifscCode,
        accountNumber: emp.accountNumber,
        bankDetails:   emp.bankDetails,
        branch:        emp.branch,
        sbCode:        emp.sbCode,
      ),
    );
  }

  void removeRow(String id) {
    current = current.copyWith(
      rows: current.rows.where((r) => r.id != id).toList(),
    );
    _syncSalaryMetadata();
    notifyListeners();
  }

  Future<void> discardDraft() async {
    await DatabaseHelper.instance.clearDraft();
    _resetCurrent();
    notifyListeners();
  }

  void _upsertSavedVoucher(VoucherModel voucher) {
    final idx = savedVouchers.indexWhere((v) => v.id == voucher.id);
    if (idx == -1) {
      savedVouchers = [voucher, ...savedVouchers];
      return;
    }

    final updated = [...savedVouchers];
    updated[idx] = voucher;
    savedVouchers = updated;
  }

  Future<bool> _persistCurrentVoucher() async {
    if (current.title.trim().isEmpty) return false;

    final voucherToSave = enriched.copyWith(status: VoucherStatus.saved);

    try {
      late final int voucherId;

      if (current.id == null) {
        voucherId = await DatabaseHelper.instance.insertVoucher(
          voucherToSave.toDbMap(),
        );
        for (final row in current.rows) {
          await DatabaseHelper.instance.insertVoucherRow(row.toDbMap(voucherId));
        }
      } else {
        voucherId = current.id!;
        await DatabaseHelper.instance.updateVoucherWithRows(
          voucherId,
          voucherToSave.toDbMap(),
          current.rows
              .map((row) => row.toDbMap(voucherId))
              .toList(growable: false),
        );
      }

      final savedVoucher = voucherToSave.copyWith(
        id: voucherId,
        status: VoucherStatus.saved,
      );

      current = savedVoucher;
      _upsertSavedVoucher(savedVoucher);
      _syncSalaryMetadata();
      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('Failed to save voucher: $e\n$st');
      return false;
    }
  }

  // ── saveVoucher — now saves WITHOUT resetting the form.
  //           The form stays intact so the invoice can be saved multiple times.
  Future<bool> saveVoucher() => _persistCurrentVoucher();

  // ── saveVoucherNoReset — saves WITHOUT clearing the form.
  //           Used by Finalise & Export so the user can export multiple times
  //           without re-entering all the voucher data. (kept for clarity)
  Future<bool> saveVoucherNoReset() => _persistCurrentVoucher();

  void _resetCurrent() {
    current = VoucherModel(
      date:            DateTime.now().toIso8601String().split('T').first,
      deptCode:        AppConstants.deptCodes.first,
      itemDescription: AppConstants.itemDescriptions.first,
      clientName:      AppConstants.defaultClientName,
      clientAddress:   AppConstants.defaultClientAddress,
      clientGstin:     AppConstants.defaultClientGstin,
    );
    _syncSalaryMetadata();
  }
}
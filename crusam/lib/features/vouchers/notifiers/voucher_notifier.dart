import 'dart:math';
import 'package:flutter/foundation.dart';
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

  double get idbiToOther => current.rows
      .where((r) => !r.ifscCode.startsWith('IDIB'))
      .fold(0, (a, r) => a + r.amount);

  double get idbiToIdbi  => current.rows
      .where((r) =>  r.ifscCode.startsWith('IDIB'))
      .fold(0, (a, r) => a + r.amount);

  VoucherModel get enriched => current.copyWith(
    baseTotal: baseTotal, cgst: cgst, sgst: sgst,
    totalTax:  totalTax,  roundOff: roundOff, finalTotal: finalTotal,
  );

  // ── Load ───────────────────────────────────────────────────────────────────
  /// Call once per screen mount.
  ///
  /// SINGLETON SAFETY: Because this notifier lives for the app's lifetime,
  /// stale [VoidCallback] listener references can accumulate across Flutter
  /// hot-reloads (the widget disposes but the singleton keeps the old
  /// closure). We cannot clear *all* listeners here (that would break
  /// widgets that haven't re-registered yet), so instead we rely on each
  /// widget calling [removeListener] before [addListener] in its own
  /// [initState]. See _MetadataCardState for the pattern.
  Future<void> loadDependencies() async {
    if (isLoading) return;           // prevent concurrent double-load
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
    notifyListeners();
  }

  void updateRow(String id, VoucherRowModel Function(VoucherRowModel) fn) {
    current = current.copyWith(
      rows: current.rows.map((r) => r.id == id ? fn(r) : r).toList(),
    );
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
    notifyListeners();
  }

  Future<void> discardDraft() async {
    await DatabaseHelper.instance.clearDraft();
    _resetCurrent();
    notifyListeners();
  }

  Future<bool> saveVoucher() async {
    if (current.title.trim().isEmpty) return false;
    try {
      final vid = await DatabaseHelper.instance.insertVoucher(enriched.toDbMap());
      for (final row in current.rows) {
        await DatabaseHelper.instance.insertVoucherRow(row.toDbMap(vid));
      }
      savedVouchers = [
        enriched.copyWith(id: vid, status: VoucherStatus.saved),
        ...savedVouchers,
      ];
      _resetCurrent();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _resetCurrent() {
    current = VoucherModel(
      date:            DateTime.now().toIso8601String().split('T').first,
      deptCode:        AppConstants.deptCodes.first,
      itemDescription: AppConstants.itemDescriptions.first,
      clientName:      AppConstants.defaultClientName,
      clientAddress:   AppConstants.defaultClientAddress,
      clientGstin:     AppConstants.defaultClientGstin,
    );
  }
}
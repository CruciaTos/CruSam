import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_date.dart';

Future<void> seedNewSociety(
  DatabaseExecutor db, {
  required int societyId,
  required String booksStartDate,
}) async {
  // 1. Financial year containing books_start_date
  final fyCode = fyCodeForDate(booksStartDate);
  final startDate = fyStartForCode(fyCode);
  final endDate = fyEndForCode(fyCode);

  final fyId = await db.insert('financial_years', {
    'society_id': societyId,
    'code': fyCode,
    'start_date': startDate,
    'end_date': endDate,
    'status': 'open',
  });

  // 2. Number series
  await seedNumberSeriesForFy(db, societyId: societyId, fyId: fyId, fyCode: fyCode);

  // 3. Account groups
  final groupIds = <String, int>{};
  for (final g in _kGroups) {
    final id = await db.insert('account_groups', {
      'society_id': societyId,
      'code': g.code,
      'name': g.name,
      'account_type': g.type,
      'system_key': g.systemKey,
      'sort_order': g.sortOrder,
      'is_active': 1,
    });
    groupIds[g.code] = id;
  }

  // 4. Accounts
  final accountIds = <String, int>{};
  int? cashAccountId;
  for (final a in _kAccounts) {
    final groupId = groupIds[a.groupCode];
    if (groupId == null) continue;
    final id = await db.insert('accounts', {
      'society_id': societyId,
      'group_id': groupId,
      'code': a.code,
      'name': a.name,
      'account_kind': a.kind,
      'system_key': a.systemKey,
      'is_active': 1,
    });
    accountIds[a.code] = id;
    if (a.code == '1101') {
      cashAccountId = id;
    }
  }

  // Cash account in bank_accounts table
  if (cashAccountId != null) {
    await db.insert('bank_accounts', {
      'society_id': societyId,
      'account_id': cashAccountId,
      'bank_name': 'Cash in Hand',
      'account_type': 'cash',
      'is_active': 1,
    });
  }

  // 5. Charge heads
  for (final h in _kChargeHeads) {
    final accountId = accountIds[h.accountCode];
    if (accountId == null) continue;
    await db.insert('charge_heads', {
      'society_id': societyId,
      'name': h.name,
      'account_id': accountId,
      'head_kind': h.headKind,
      'is_interest_bearing': h.isInterestBearing ? 1 : 0,
      'is_gst_applicable': 0,
      'sort_order': h.sortOrder,
      'system_key': h.systemKey,
      'is_active': 1,
    });
  }

  // 6. TDS sections
  for (final t in _kTdsSections) {
    await db.insert('tds_sections', {
      'society_id': societyId,
      'code': t.code,
      'name': t.name,
      'is_active': 1,
    });
  }

  // 7. Default settings
  for (final entry in _kDefaultSettings.entries) {
    await db.insert('society_settings', {
      'society_id': societyId,
      'key': entry.key,
      'value': entry.value,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}

Future<void> seedNumberSeriesForFy(
  DatabaseExecutor db, {
  required int societyId,
  required int fyId,
  required String fyCode,
}) async {
  final series = <Map<String, Object?>>[
    {'doc_type': 'journal', 'prefix': 'JE/$fyCode/'},
    {'doc_type': 'member_bill', 'prefix': 'BILL/$fyCode/'},
    {'doc_type': 'member_receipt', 'prefix': 'RCPT/$fyCode/'},
    {'doc_type': 'credit_note', 'prefix': 'CN/$fyCode/'},
    {'doc_type': 'debit_note', 'prefix': 'DN/$fyCode/'},
    {'doc_type': 'unidentified', 'prefix': 'UR/$fyCode/'},
    {'doc_type': 'other_invoice', 'prefix': 'OI/$fyCode/'},
    {'doc_type': 'other_receipt', 'prefix': 'OR/$fyCode/'},
    {'doc_type': 'expense_voucher', 'prefix': 'EXP/$fyCode/'},
    {'doc_type': 'vendor_payment', 'prefix': 'PAY/$fyCode/'},
    {'doc_type': 'bank_transfer', 'prefix': 'TRF/$fyCode/'},
  ];

  for (final s in series) {
    await db.insert('number_series', {
      'society_id': societyId,
      'fy_id': fyId,
      'doc_type': s['doc_type'],
      'prefix': s['prefix'],
      'next_no': 1,
      'pad': 6,
    });
  }
}

class _GroupDef {
  final String code;
  final String type;
  final String name;
  final String systemKey;
  final int sortOrder;
  const _GroupDef(this.code, this.type, this.name, this.systemKey, this.sortOrder);
}

const _kGroups = <_GroupDef>[
  _GroupDef('1100', 'asset', 'Cash and Bank', 'cash_bank', 10),
  _GroupDef('1200', 'asset', 'Member Receivables', 'member_receivables', 20),
  _GroupDef('1300', 'asset', 'Other Receivables', 'other_receivables', 30),
  _GroupDef('1400', 'asset', 'Investments and Fixed Deposits', 'investments', 40),
  _GroupDef('1500', 'asset', 'Fixed Assets', 'fixed_assets', 50),
  _GroupDef('1600', 'asset', 'Tax Assets', 'tax_assets', 60),
  _GroupDef('1700', 'asset', 'Advances and Prepaid', 'advances_prepaid', 70),
  _GroupDef('2100', 'liability', 'Share Capital', 'share_capital', 80),
  _GroupDef('2200', 'liability', 'Statutory Funds', 'statutory_funds', 90),
  _GroupDef('2300', 'liability', 'Reserves and General Funds', 'reserves', 100),
  _GroupDef('2400', 'liability', 'Member Deposits and Suspense', 'member_deposits', 110),
  _GroupDef('2500', 'liability', 'Creditors', 'creditors', 120),
  _GroupDef('2600', 'liability', 'Tax Payable', 'tax_payable', 130),
  _GroupDef('2700', 'liability', 'Other Liabilities', 'other_liabilities', 140),
  _GroupDef('2800', 'liability', 'Income and Expenditure', 'income_expenditure', 150),
  _GroupDef('3100', 'income', 'Member Charges', 'member_income', 160),
  _GroupDef('3200', 'income', 'Interest Income', 'interest_income', 170),
  _GroupDef('3300', 'income', 'Other Income', 'other_income', 180),
  _GroupDef('4100', 'expense', 'Repairs and Maintenance', 'repairs', 190),
  _GroupDef('4200', 'expense', 'Utilities', 'utilities', 200),
  _GroupDef('4300', 'expense', 'Staff and Security', 'staff_security', 210),
  _GroupDef('4400', 'expense', 'Administration and Professional', 'admin_professional', 220),
  _GroupDef('4500', 'expense', 'Taxes and Statutory', 'statutory_expense', 230),
  _GroupDef('4600', 'expense', 'Bank and Finance', 'bank_finance', 240),
  _GroupDef('4700', 'expense', 'Other Expenses', 'other_expense', 250),
];

class _AccountDef {
  final String code;
  final String groupCode;
  final String name;
  final String kind;
  final String? systemKey;
  const _AccountDef(this.code, this.groupCode, this.name, this.kind, [this.systemKey]);
}

const _kAccounts = <_AccountDef>[
  _AccountDef('1101', '1100', 'Cash in Hand', 'cash', 'cash'),
  _AccountDef('1201', '1200', 'Members Receivable', 'receivable', 'members_receivable'),
  _AccountDef('1301', '1300', 'Other Receivables', 'receivable', 'other_receivable'),
  _AccountDef('1401', '1400', 'Accrued Interest on FDs', 'general', 'accrued_interest'),
  _AccountDef('1601', '1600', 'Input CGST', 'tax', 'input_cgst'),
  _AccountDef('1602', '1600', 'Input SGST', 'tax', 'input_sgst'),
  _AccountDef('1603', '1600', 'Input IGST', 'tax', 'input_igst'),
  _AccountDef('1604', '1600', 'TDS Receivable', 'tax', 'tds_receivable'),
  _AccountDef('1701', '1700', 'Vendor Advances', 'general', 'vendor_advances'),
  _AccountDef('2101', '2100', 'Share Capital', 'fund', 'share_capital'),
  _AccountDef('2201', '2200', 'Sinking Fund', 'fund', 'sinking_fund'),
  _AccountDef('2202', '2200', 'Repair Fund', 'fund', 'repair_fund'),
  _AccountDef('2203', '2200', 'Major Repair Fund', 'fund', 'major_repair_fund'),
  _AccountDef('2301', '2300', 'General Fund', 'fund', 'general_fund'),
  _AccountDef('2302', '2300', 'Reserve Fund', 'fund', 'reserve_fund'),
  _AccountDef('2303', '2300', 'Education and Training Fund', 'fund', 'education_fund'),
  _AccountDef('2401', '2400', 'Refundable Deposits', 'deposit', 'refundable_deposits'),
  _AccountDef('2402', '2400', 'Unidentified Receipts', 'general', 'unidentified_receipts'),
  _AccountDef('2501', '2500', 'Vendors Payable', 'payable', 'vendors_payable'),
  _AccountDef('2601', '2600', 'Output CGST', 'tax', 'output_cgst'),
  _AccountDef('2602', '2600', 'Output SGST', 'tax', 'output_sgst'),
  _AccountDef('2603', '2600', 'Output IGST', 'tax', 'output_igst'),
  _AccountDef('2604', '2600', 'TDS Payable', 'tax', 'tds_payable'),
  _AccountDef('2801', '2800', 'Income and Expenditure Account', 'retained', 'income_expenditure'),
  _AccountDef('2899', '2800', 'Opening Balance Adjustment', 'general', 'opening_adjustment'),
  _AccountDef('3101', '3100', 'Maintenance Charges', 'general', 'maintenance_income'),
  _AccountDef('3102', '3100', 'Water Charges', 'general', 'water_income'),
  _AccountDef('3103', '3100', 'Common Electricity Charges', 'general', 'electricity_income'),
  _AccountDef('3104', '3100', 'Parking Charges', 'general', 'parking_income'),
  _AccountDef('3105', '3100', 'Non-Occupancy Charges', 'general', 'non_occupancy_income'),
  _AccountDef('3106', '3100', 'Insurance Charges', 'general', 'insurance_income'),
  _AccountDef('3107', '3100', 'Property Tax Recovery', 'general', 'property_tax_income'),
  _AccountDef('3201', '3200', 'Late Payment Interest', 'general', 'late_interest_income'),
  _AccountDef('3202', '3200', 'Bank Interest', 'general', 'bank_interest_income'),
  _AccountDef('3203', '3200', 'FD Interest', 'general', 'fd_interest_income'),
  _AccountDef('3301', '3300', 'Member Adjustments', 'general', 'member_adjustments'),
  _AccountDef('3302', '3300', 'Round Off', 'general', 'round_off'),
  _AccountDef('3303', '3300', 'Miscellaneous Income', 'general', 'misc_income'),
  _AccountDef('4101', '4100', 'Lift Maintenance', 'general'),
  _AccountDef('4102', '4100', 'Building Repairs', 'general'),
  _AccountDef('4103', '4100', 'Plumbing and Electrical Repairs', 'general'),
  _AccountDef('4201', '4200', 'Electricity', 'general'),
  _AccountDef('4202', '4200', 'Water', 'general'),
  _AccountDef('4301', '4300', 'Security Charges', 'general'),
  _AccountDef('4302', '4300', 'Housekeeping', 'general'),
  _AccountDef('4303', '4300', 'Salaries and Wages', 'general'),
  _AccountDef('4401', '4400', 'Audit Fees', 'general'),
  _AccountDef('4402', '4400', 'Accounting Charges', 'general'),
  _AccountDef('4403', '4400', 'Legal and Professional Fees', 'general'),
  _AccountDef('4404', '4400', 'Printing and Stationery', 'general'),
  _AccountDef('4501', '4500', 'Property Tax', 'general'),
  _AccountDef('4502', '4500', 'Insurance Premium', 'general'),
  _AccountDef('4601', '4600', 'Bank Charges', 'general', 'bank_charges'),
  _AccountDef('4701', '4700', 'Miscellaneous Expenses', 'general'),
];

class _HeadDef {
  final int sortOrder;
  final String name;
  final String accountCode;
  final bool isInterestBearing;
  final String headKind;
  final String systemKey;
  const _HeadDef(this.sortOrder, this.name, this.accountCode, this.isInterestBearing, this.headKind, this.systemKey);
}

const _kChargeHeads = <_HeadDef>[
  _HeadDef(10, 'Maintenance Charges', '3101', true, 'charge', 'maintenance'),
  _HeadDef(20, 'Sinking Fund', '2201', true, 'charge', 'sinking_fund'),
  _HeadDef(30, 'Repair Fund', '2202', true, 'charge', 'repair_fund'),
  _HeadDef(40, 'Water Charges', '3102', false, 'charge', 'water'),
  _HeadDef(50, 'Common Electricity Charges', '3103', false, 'charge', 'electricity'),
  _HeadDef(60, 'Parking Charges', '3104', true, 'charge', 'parking'),
  _HeadDef(70, 'Non-Occupancy Charges', '3105', true, 'charge', 'non_occupancy'),
  _HeadDef(80, 'Insurance Charges', '3106', true, 'charge', 'insurance'),
  _HeadDef(90, 'Property Tax Recovery', '3107', true, 'charge', 'property_tax'),
  _HeadDef(1000, 'Late Payment Interest', '3201', false, 'interest', 'late_interest'),
];

class _TdsSectionDef {
  final String code;
  final String name;
  const _TdsSectionDef(this.code, this.name);
}

const _kTdsSections = <_TdsSectionDef>[
  _TdsSectionDef('194C', 'Payments to Contractors'),
  _TdsSectionDef('194J', 'Fees for Professional or Technical Services'),
  _TdsSectionDef('194I', 'Rent'),
  _TdsSectionDef('194H', 'Commission or Brokerage'),
];

const _kDefaultSettings = <String, String>{
  'billing.frequency': 'monthly',
  'billing.due_day_offset': '20',
  'billing.round_mode': 'none',
  'billing.show_interest_breakup': '1',
  'billing.show_recent_receipts': '1',
  'collection.auto_apply_advance': '0',
  'interest.enabled': '0',
  'interest.grace_days': '0',
  'interest.start_date': '',
  'document.bill_title': 'Maintenance Bill',
  'document.receipt_title': 'Receipt',
  'document.payment_instructions': '',
  'document.signatory': 'Authorised Signatory',
  'email.send_to': 'primary_contact',
};

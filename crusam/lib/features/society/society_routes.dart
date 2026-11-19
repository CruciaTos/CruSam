import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:crusam/features/society/screens/overview/society_overview_screen.dart';
import 'package:crusam/features/society/screens/societies/societies_screen.dart';
import 'package:crusam/features/society/screens/societies/society_form_screen.dart';
import 'package:crusam/features/society/screens/settings/society_settings_screen.dart';
import 'package:crusam/features/society/screens/accounts/chart_of_accounts_screen.dart';
import 'package:crusam/features/society/screens/accounts/journal_list_screen.dart';
import 'package:crusam/features/society/screens/accounts/journal_new_screen.dart';
import 'package:crusam/features/society/screens/accounts/journal_detail_screen.dart';
import 'package:crusam/features/society/screens/accounts/ledger_enquiry_screen.dart';
import 'package:crusam/features/society/screens/accounts/trial_balance_screen.dart';
import 'package:crusam/features/society/screens/units/units_screen.dart';
import 'package:crusam/features/society/screens/units/unit_form_screen.dart';
import 'package:crusam/features/society/screens/units/unit_detail_screen.dart';
import 'package:crusam/features/society/screens/units/unit_types_screen.dart';
import 'package:crusam/features/society/screens/members/members_screen.dart';
import 'package:crusam/features/society/screens/members/member_form_screen.dart';
import 'package:crusam/features/society/screens/imports/import_screen.dart';
import 'package:crusam/features/society/screens/billing/charge_heads_screen.dart';
import 'package:crusam/features/society/screens/billing/billing_rules_screen.dart';
import 'package:crusam/features/society/screens/billing/meters_screen.dart';
import 'package:crusam/features/society/screens/billing/bill_runs_screen.dart';
import 'package:crusam/features/society/screens/billing/bill_run_new_screen.dart';
import 'package:crusam/features/society/screens/billing/bill_run_detail_screen.dart';
import 'package:crusam/features/society/screens/billing/bills_screen.dart';
import 'package:crusam/features/society/screens/billing/manual_bill_screen.dart';
import 'package:crusam/features/society/screens/billing/bill_detail_screen.dart';
import 'package:crusam/features/society/screens/collections/receipts_screen.dart';
import 'package:crusam/features/society/screens/collections/receipt_form_screen.dart';
import 'package:crusam/features/society/screens/collections/receipt_detail_screen.dart';
import 'package:crusam/features/society/screens/collections/notes_screen.dart';
import 'package:crusam/features/society/screens/collections/unidentified_screen.dart';
import 'package:crusam/features/society/screens/collections/dues_screen.dart';
import 'package:crusam/features/society/screens/other_income/other_income_screen.dart';
import 'package:crusam/features/society/screens/other_income/other_invoice_form_screen.dart';
import 'package:crusam/features/society/screens/vendors/vendors_screen.dart';
import 'package:crusam/features/society/screens/vendors/vendor_form_screen.dart';
import 'package:crusam/features/society/screens/vendors/vendor_detail_screen.dart';
import 'package:crusam/features/society/screens/expenses/expenses_screen.dart';
import 'package:crusam/features/society/screens/expenses/expense_form_screen.dart';
import 'package:crusam/features/society/screens/expenses/payments_screen.dart';
import 'package:crusam/features/society/screens/expenses/payment_form_screen.dart';
import 'package:crusam/features/society/screens/budget/budget_screen.dart';
import 'package:crusam/features/society/screens/expenses/expense_comparison_screen.dart';
import 'package:crusam/features/society/screens/bank/bank_screen.dart';
import 'package:crusam/features/society/screens/bank/transfers_screen.dart';
import 'package:crusam/features/society/screens/bank/reconciliation_screen.dart';
import 'package:crusam/features/society/screens/deposits/deposits_screen.dart';
import 'package:crusam/features/society/screens/tax/tax_screen.dart';
import 'package:crusam/features/society/screens/accounts/financial_statements_screen.dart';
import 'package:crusam/features/society/screens/accounts/year_end_screen.dart';
import 'package:crusam/features/society/screens/reports/reports_screen.dart';
import 'package:crusam/features/society/screens/about/society_about_screen.dart';

const List<String> societyNavPaths = [
  '/society/overview',
  '/society/societies',
  '/society/units',
  '/society/unit-types',
  '/society/members',
  '/society/import',
  '/society/charge-heads',
  '/society/billing-rules',
  '/society/meters',
  '/society/bill-runs',
  '/society/bills',
  '/society/receipts',
  '/society/notes',
  '/society/unidentified',
  '/society/dues',
  '/society/other-income',
  '/society/vendors',
  '/society/expenses',
  '/society/payments',
  '/society/budget',
  '/society/expense-comparison',
  '/society/bank',
  '/society/transfers',
  '/society/reconciliation',
  '/society/deposits',
  '/society/tax',
  '/society/accounts',
  '/society/journals',
  '/society/ledger',
  '/society/trial-balance',
  '/society/statements',
  '/society/year-end',
  '/society/reports',
  '/society/settings',
  '/society/about',
];

const Map<String, String> societyNavTitles = {
  '/society/overview': 'Overview',
  '/society/societies': 'Societies',
  '/society/units': 'Units',
  '/society/unit-types': 'Unit Types',
  '/society/members': 'Members',
  '/society/import': 'Import',
  '/society/charge-heads': 'Charge Heads',
  '/society/billing-rules': 'Billing Rules',
  '/society/meters': 'Meter Readings',
  '/society/bill-runs': 'Bill Runs',
  '/society/bills': 'Bills',
  '/society/receipts': 'Receipts',
  '/society/notes': 'Credit & Debit Notes',
  '/society/unidentified': 'Unidentified Receipts',
  '/society/dues': 'Dues & Reminders',
  '/society/other-income': 'Other Income',
  '/society/vendors': 'Vendors',
  '/society/expenses': 'Expense Bills',
  '/society/payments': 'Payments',
  '/society/budget': 'Budget',
  '/society/expense-comparison': 'Expense Comparison',
  '/society/bank': 'Accounts',
  '/society/transfers': 'Transfers',
  '/society/reconciliation': 'Reconciliation',
  '/society/deposits': 'Fixed Deposits',
  '/society/tax': 'GST & TDS',
  '/society/accounts': 'Chart of Accounts',
  '/society/journals': 'Journal Entries',
  '/society/ledger': 'Ledger Enquiry',
  '/society/trial-balance': 'Trial Balance',
  '/society/statements': 'Financial Statements',
  '/society/year-end': 'Year End',
  '/society/reports': 'Reports',
  '/society/settings': 'Society Settings',
  '/society/about': 'About & Credits',
};

final List<RouteBase> societyRoutes = [
  GoRoute(
    path: '/society',
    redirect: (_, _) => '/society/overview',
  ),
  GoRoute(
    path: '/society/overview',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const SocietyOverviewScreen(),
    ),
  ),
  GoRoute(
    path: '/society/societies',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const SocietiesScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const SocietyFormScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: SocietyFormScreen(societyId: id),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/settings',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const SocietySettingsScreen(),
    ),
  ),
  // Units & Unit Types
  GoRoute(
    path: '/society/units',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const UnitsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const UnitFormScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: UnitDetailScreen(unitId: id),
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: UnitFormScreen(unitId: id),
              );
            },
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/society/unit-types',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const UnitTypesScreen(),
    ),
  ),
  // Members & Residents
  GoRoute(
    path: '/society/members',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const MembersScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const MemberFormScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: MemberFormScreen(personId: id),
          );
        },
      ),
    ],
  ),
  // Import
  GoRoute(
    path: '/society/import',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ImportScreen(),
    ),
  ),
  // Accounts
  GoRoute(
    path: '/society/accounts',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ChartOfAccountsScreen(),
    ),
  ),
  GoRoute(
    path: '/society/journals',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const JournalListScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const JournalNewScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: JournalDetailScreen(entryId: id ?? 0),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/ledger',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const LedgerEnquiryScreen(),
    ),
  ),
  GoRoute(
    path: '/society/trial-balance',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const TrialBalanceScreen(),
    ),
  ),
  GoRoute(
    path: '/society/charge-heads',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ChargeHeadsScreen(),
    ),
  ),
  GoRoute(
    path: '/society/billing-rules',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const BillingRulesScreen(),
    ),
  ),
  GoRoute(
    path: '/society/meters',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const MetersScreen(),
    ),
  ),
  GoRoute(
    path: '/society/bill-runs',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const BillRunsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const BillRunNewScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: BillRunDetailScreen(runId: id),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/bills',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const BillsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) {
          final kind = state.uri.queryParameters['kind'];
          final unitId = int.tryParse(state.uri.queryParameters['unitId'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: ManualBillScreen(initialKind: kind, initialUnitId: unitId),
          );
        },
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: BillDetailScreen(billId: id),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/receipts',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ReceiptsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) {
          final unitId = int.tryParse(state.uri.queryParameters['unitId'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: ReceiptFormScreen(initialUnitId: unitId),
          );
        },
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: ReceiptDetailScreen(receiptId: id),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/notes',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const NotesScreen(),
    ),
  ),
  GoRoute(
    path: '/society/unidentified',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const UnidentifiedScreen(),
    ),
  ),
  GoRoute(
    path: '/society/dues',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const DuesScreen(),
    ),
  ),
  GoRoute(
    path: '/society/other-income',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const OtherIncomeScreen(),
    ),
    routes: [
      GoRoute(
        path: 'invoices/new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const OtherInvoiceFormScreen(),
        ),
      ),
    ],
  ),
  GoRoute(
    path: '/society/vendors',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const VendorsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) => NoTransitionPage<void>(
          key: state.pageKey,
          child: const VendorFormScreen(),
        ),
      ),
      GoRoute(
        path: ':id',
        pageBuilder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: VendorDetailScreen(vendorId: id),
          );
        },
        routes: [
          GoRoute(
            path: 'edit',
            pageBuilder: (context, state) {
              final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
              return NoTransitionPage<void>(
                key: state.pageKey,
                child: VendorFormScreen(vendorId: id),
              );
            },
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: '/society/expenses',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ExpensesScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) {
          final vendorId = int.tryParse(state.uri.queryParameters['vendorId'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: ExpenseFormScreen(initialVendorId: vendorId),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/payments',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const PaymentsScreen(),
    ),
    routes: [
      GoRoute(
        path: 'new',
        pageBuilder: (context, state) {
          final vendorId = int.tryParse(state.uri.queryParameters['vendorId'] ?? '');
          return NoTransitionPage<void>(
            key: state.pageKey,
            child: PaymentFormScreen(initialVendorId: vendorId),
          );
        },
      ),
    ],
  ),
  GoRoute(
    path: '/society/budget',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const BudgetScreen(),
    ),
  ),
  GoRoute(
    path: '/society/expense-comparison',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ExpenseComparisonScreen(),
    ),
  ),
  GoRoute(
    path: '/society/bank',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const BankScreen(),
    ),
  ),
  GoRoute(
    path: '/society/transfers',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const TransfersScreen(),
    ),
  ),
  GoRoute(
    path: '/society/reconciliation',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ReconciliationScreen(),
    ),
  ),
  GoRoute(
    path: '/society/deposits',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const DepositsScreen(),
    ),
  ),
  GoRoute(
    path: '/society/tax',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const TaxScreen(),
    ),
  ),
  GoRoute(
    path: '/society/statements',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const FinancialStatementsScreen(),
    ),
  ),
  GoRoute(
    path: '/society/year-end',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const YearEndScreen(),
    ),
  ),
  GoRoute(
    path: '/society/reports',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const ReportsScreen(),
    ),
  ),
  GoRoute(
    path: '/society/about',
    pageBuilder: (context, state) => NoTransitionPage<void>(
      key: state.pageKey,
      child: const SocietyAboutScreen(),
    ),
  ),
];

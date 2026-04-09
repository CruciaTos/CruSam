import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/master_data/presentation/employee_list_screen.dart';
import '../../features/vouchers/presentation/voucher_builder_screen.dart';
import '../../features/vouchers/presentation/invoices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/salary/presentation/salary_employees_screen.dart';
import '../../features/salary/presentation/salary_slips_screen.dart';
import '../../features/salary/presentation/salary_bills_screen.dart';
import '../../features/salary/presentation/salary_statement_screen.dart';
import '../../features/salary/presentation/salary_disbursements_screen.dart';
import '../../features/salary/presentation/salary_preview_screen.dart';

class AppRouter {
  static final _root  = GlobalKey<NavigatorState>();
  static final _shell = GlobalKey<NavigatorState>();

  static NoTransitionPage<void> _buildPageTransition(
    GoRouterState state,
    Widget child,
  ) {
    return NoTransitionPage<void>(
      key: state.pageKey,
      child: child,
    );
  }

  static final router = GoRouter(
    navigatorKey: _root,
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        navigatorKey: _shell,
        builder: (ctx, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            pageBuilder: (c, s) => _buildPageTransition(s, const DashboardScreen()),
          ),
          GoRoute(
            path: '/employees',
            pageBuilder: (c, s) => _buildPageTransition(s, const EmployeeListScreen()),
          ),
          GoRoute(
            path: '/vouchers',
            pageBuilder: (c, s) => _buildPageTransition(s, const VoucherBuilderScreen()),
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (c, s) => _buildPageTransition(s, const InvoicesScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (c, s) => _buildPageTransition(s, const SettingsScreen()),
          ),
          GoRoute(
            path: '/salary-employees',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalaryEmployeesScreen()),
          ),
          GoRoute(
            path: '/salary-slips',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalarySlipsScreen()),
          ),
          GoRoute(
            path: '/salary-bills',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalaryBillsScreen()),
          ),
          GoRoute(
            path: '/salary-statement',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalaryStatementScreen()),
          ),
          GoRoute(
            path: '/salary-disburse',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalaryDisbursementsScreen()),
          ),
          GoRoute(
            path: '/salary-preview',
            pageBuilder: (c, s) => _buildPageTransition(s, const SalaryPreviewScreen()),
          ),
        ],
      ),
    ],
  );
}
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/master_data/presentation/employee_list_screen.dart';
import '../../features/vouchers/presentation/voucher_builder_screen.dart';
import '../../features/vouchers/presentation/invoices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

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
        ],
      ),
    ],
  );
}
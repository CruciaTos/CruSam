import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/shell/shell_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/master_data/presentation/employee_list_screen.dart';
import '../../features/master_data/presentation/employee_form_screen.dart';
import '../../features/vouchers/presentation/voucher_builder_screen.dart';
import '../../features/vouchers/presentation/invoices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

class AppRouter {
  static final _root  = GlobalKey<NavigatorState>();
  static final _shell = GlobalKey<NavigatorState>();

  static final router = GoRouter(
    navigatorKey: _root,
    initialLocation: '/dashboard',
    routes: [
      ShellRoute(
        navigatorKey: _shell,
        builder: (ctx, state, child) => ShellScreen(child: child),
        routes: [
          GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
          GoRoute(path: '/employees', builder: (c, s) => const EmployeeListScreen()),
          GoRoute(path: '/vouchers',  builder: (c, s) => const VoucherBuilderScreen()),
          GoRoute(path: '/invoices',  builder: (c, s) => const InvoicesScreen()),
          GoRoute(path: '/settings',  builder: (c, s) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _root,
        path: '/employees/form',
        builder: (c, s) => EmployeeFormScreen(employee: s.extra as Map<String, dynamic>?),
      ),
    ],
  );
}
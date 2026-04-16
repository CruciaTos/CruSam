// ignore_for_file: unused_import

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
import '../../features/salary/presentation/salary_attachment_a_screen.dart';
import '../../features/salary/presentation/salary_attachment_b_screen.dart';
import '../../features/landing/presentation/landing_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/notifiers/auth_notifier.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../shared/widgets/coming_soon_screen.dart';

class AppRouter {
  static final _root = GlobalKey<NavigatorState>();
  static final _shell = GlobalKey<NavigatorState>();

  // Public routes that do not require authentication
  static const _publicPaths = {'/landing', '/login'};

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
    initialLocation: '/landing', // Starts on landing; auth will redirect accordingly
    refreshListenable: AuthNotifier.instance,
    redirect: (context, state) {
      final auth = AuthNotifier.instance;

      // Wait for session check before deciding
      if (auth.isLoading) return null;

      final isPublic = _publicPaths.contains(state.matchedLocation);

      // Not logged in → force to landing (unless already on public route)
      if (!auth.isLoggedIn && !isPublic) return '/landing';

      // Logged in → prevent going back to landing/login
      if (auth.isLoggedIn && isPublic) return '/dashboard';

      return null;
    },
    routes: [
      // ---------- Public routes (outside shell) ----------
      GoRoute(
        path: '/landing',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),

      // ---------- Protected shell routes ----------
      ShellRoute(
        navigatorKey: _shell,
        builder: (context, state, child) => ShellScreen(child: child),
        routes: [
          // ---- Existing routes (unchanged) ----
          GoRoute(
            path: '/dashboard',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const DashboardScreen()),
          ),
          GoRoute(
            path: '/employees',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const EmployeeListScreen()),
          ),
          GoRoute(
            path: '/vouchers',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const VoucherBuilderScreen()),
          ),
          GoRoute(
            path: '/invoices',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const InvoicesScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SettingsScreen()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const ProfileScreen()),
          ),
          GoRoute(
            path: '/salary-employees',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryEmployeesScreen()),
          ),
          GoRoute(
            path: '/salary-slips',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalarySlipsScreen()),
          ),
          GoRoute(
            path: '/salary-invoice',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryBillsScreen()),
          ),
          GoRoute(
            path: '/salary-bills',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryBillsScreen()),
          ),
          GoRoute(
            path: '/salary-statement',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryStatementScreen()),
          ),
          GoRoute(
            path: '/salary-disburse',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryDisbursementsScreen()),
          ),
          GoRoute(
            path: '/salary-preview',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryPreviewScreen()),
          ),
          GoRoute(
            path: '/salary-attachment-a',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryAttachmentAScreen()),
          ),
          GoRoute(
            path: '/salary-attachment-b',
            pageBuilder: (context, state) =>
                _buildPageTransition(state, const SalaryAttachmentBScreen()),
          ),
        ],
      ),
    ],
  );
}
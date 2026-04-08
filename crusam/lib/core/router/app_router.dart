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
          // Master Data screen: slow fade‑out of previous screen then slide‑up
          GoRoute(
  path: '/employees',
  pageBuilder: (context, state) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: const EmployeeListScreen(),
      opaque: false,
      transitionDuration: const Duration(milliseconds: 2500),
      reverseTransitionDuration: const Duration(milliseconds: 2500),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        // 1. Overlay that fades in to "cover" the old screen (simulates old screen fading out)
        final overlayFade = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: secondaryAnimation,
          curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
        ));

        // 2. New screen slide‑up (delayed)
        final slideAnimation = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: const Interval(0.6, 1.0, curve: Curves.easeOutCubic),
        ));

        // 3. New screen fade‑in (synchronized with slide)
        final fadeInAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
        ));

        return Stack(
          children: [
            // Overlay that fades in over the old screen – use your app's background color
            FadeTransition(
              opacity: overlayFade,
              child: Container(color: Colors.white), // Replace with your ShellScreen background color
            ),
            // New screen sliding up and fading in
            FadeTransition(
              opacity: fadeInAnimation,
              child: SlideTransition(
                position: slideAnimation,
                child: child,
              ),
            ),
          ],
        );
      },
    );
  },
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
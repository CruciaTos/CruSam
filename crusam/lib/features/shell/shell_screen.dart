import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';

class ShellScreen extends StatefulWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  bool _expanded = true;

  static const _items = [
    _NavDef('/dashboard', Icons.dashboard_outlined,   'Dashboard'),
    _NavDef('/employees', Icons.people_outline,        'Employee Master Data'),
    _NavDef('/vouchers',  Icons.description_outlined,  'Voucher'),
    _NavDef('/invoices',  Icons.receipt_outlined,       'Invoices'),
    _NavDef('/settings',  Icons.settings_outlined,      'Company-Config'),
  ];

  String _activeRoute(BuildContext ctx) {
    final loc = GoRouterState.of(ctx).uri.toString();
    for (final item in _items) {
      if (loc.startsWith(item.path)) return item.path;
    }
    return '/dashboard';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 768;
    if (!isDesktop) return _MobileShell(child: widget.child);

    final active = _activeRoute(context);
    final w = _expanded ? AppSpacing.sidebarExpanded : AppSpacing.sidebarCollapsed;

    return Scaffold(
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: w,
            color: AppColors.sidebarBg,
            child: Column(
              children: [
                _SidebarHeader(expanded: _expanded),
                const Divider(color: AppColors.slate800, height: 1),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    children: _items.map((item) => _SidebarTile(
                      def: item,
                      selected: active == item.path,
                      expanded: _expanded,
                      onTap: () => context.go(item.path),
                    )).toList(),
                  ),
                ),
                const Divider(color: AppColors.slate800, height: 1),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: _SidebarTile(
                    def: const _NavDef('', Icons.logout, 'Logout'),
                    selected: false, expanded: _expanded, onTap: () {},
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                _Header(
                  expanded: _expanded,
                  onToggle: () => setState(() => _expanded = !_expanded),
                  title: _items.firstWhere((e) => e.path == active,
                      orElse: () => _items.first).label,
                ),
                Expanded(
                  child: ColoredBox(color: AppColors.background, child: widget.child),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}

class _SidebarHeader extends StatelessWidget {
  final bool expanded;
  const _SidebarHeader({required this.expanded});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppSpacing.headerHeight,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: AppColors.indigo600,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          if (expanded) ...[
            const SizedBox(width: 10),
            Expanded(
              child: Text('AARTI ENTERPRISES',
                  style: AppTextStyles.sidebarBrand, overflow: TextOverflow.ellipsis),
            ),
          ],
        ],
      ),
    ),
  );
}

class _SidebarTile extends StatelessWidget {
  final _NavDef def;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  const _SidebarTile({required this.def, required this.selected, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo600 : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(def.icon, size: 19,
                color: selected ? Colors.white : AppColors.slate400),
            if (expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(def.label,
                  style: AppTextStyles.navLabel.copyWith(
                      color: selected ? Colors.white : AppColors.slate400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final String title;
  const _Header({required this.expanded, required this.onToggle, required this.title});

  @override
  Widget build(BuildContext context) => Container(
    height: AppSpacing.headerHeight,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    decoration: const BoxDecoration(
      color: AppColors.white,
      border: Border(bottom: BorderSide(color: AppColors.slate200))),
    child: Row(
      children: [
        IconButton(
          onPressed: onToggle,
          icon: AnimatedRotation(
            turns: expanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.chevron_right, color: AppColors.slate500),
          ),
        ),
        const SizedBox(width: 4),
        Text(title, style: AppTextStyles.h4),
        const Spacer(),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Admin User', style: AppTextStyles.bodyMedium),
            Text('boridkar24@gmail.com', style: AppTextStyles.small),
          ],
        ),
        const SizedBox(width: 12),
        const CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.slate200,
          child: Text('AU', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.slate600)),
        ),
      ],
    ),
  );
}

class _NavDef {
  final String path;
  final IconData icon;
  final String label;
  const _NavDef(this.path, this.icon, this.label);
}
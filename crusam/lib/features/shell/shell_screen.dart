// ignore_for_file: unused_element_parameter
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:particles_network/particles_network.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/notifiers/auth_notifier.dart';

// ── Nav model ──────────────────────────────────────────────────────────────
abstract class _NavItem { const _NavItem(); }

class _Route extends _NavItem {
  final String path, label;
  final IconData icon;
  const _Route(this.path, this.icon, this.label);
}

class _Group extends _NavItem {
  final IconData icon;
  final String label;
  final List<_NavItem> children;
  const _Group(this.icon, this.label, this.children);
}

// ── Nav tree ───────────────────────────────────────────────────────────────
const _kNav = <_NavItem>[
  _Route('/dashboard',        Icons.dashboard_outlined,       'Dashboard'),
  _Route('/employees',        Icons.people_outline,           'Employee Master Data'),
  _Route('/vouchers',         Icons.description_outlined,     'Voucher'),
  _Route('/invoices',         Icons.receipt_outlined,         'Invoices'),
  _Route('/settings',         Icons.settings_outlined,        'Company-Config'),
  _Route('/salary-employees', Icons.badge_outlined,           'Employee Salary'),
  _Group(Icons.payments_outlined, 'Salary-Output', [
    _Route('/salary-slips',        Icons.receipt_long_outlined,     'Salary Slips'),
    _Group(Icons.request_quote_outlined, 'Salary Bills', [
      _Route('/salary-invoice',        Icons.description_outlined,   'Salary Invoice'),
      _Group(Icons.folder_outlined, 'Corroborating Doc.', [
        _Route('/salary-attachment-a', Icons.attach_file,            'Attachment A'),
        _Route('/salary-attachment-b', Icons.attach_file,            'Attachment B'),
      ]),
    ]),
    _Route('/salary-statement',    Icons.summarize_outlined,        'Salary Statement'),
    _Route('/salary-disburse',     Icons.account_balance_outlined,  'Salary Disbursements'),
  ]),
];

// ── Tree helpers (memoized inside state) ───────────────────────────────────
String? _findActiveStatic(List<_NavItem> items, String loc) {
  for (final item in items) {
    if (item is _Route && (loc == item.path || loc.startsWith('${item.path}/'))) return item.path;
    if (item is _Group) { final f = _findActiveStatic(item.children, loc); if (f != null) return f; }
  }
  return null;
}

String _titleForStatic(List<_NavItem> items, String route) {
  String? t;
  void scan(List<_NavItem> items) {
    for (final item in items) {
      if (item is _Route && item.path == route) { t = item.label; return; }
      if (item is _Group) scan(item.children);
    }
  }
  scan(items);
  return t ?? 'Dashboard';
}

bool _groupContainsActiveStatic(List<_NavItem> items, String active) {
  for (final item in items) {
    if (item is _Route && item.path == active) return true;
    if (item is _Group && _groupContainsActiveStatic(item.children, active)) return true;
  }
  return false;
}

// ══════════════════════════════════════════════════════════════════════════
// ShellScreen
// ══════════════════════════════════════════════════════════════════════════
class ShellScreen extends StatefulWidget {
  final Widget child;
  const ShellScreen({super.key, required this.child});
  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  bool _expanded = true;
  // Groups open by default (note: 'Salary' label vs 'Salary-Output' in tree)
  final Set<String> _open = {'Salary-Output'};  // fixed to match actual group label

  // Memoized values to avoid recomputation on every build
  String _currentLocation = '';
  String _activePath = '/dashboard';
  String _pageTitle = 'Dashboard';

  void _toggle(String label) => setState(() =>
      _open.contains(label) ? _open.remove(label) : _open.add(label));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = GoRouterState.of(context).uri.toString();
    if (_currentLocation != loc) {
      _currentLocation = loc;
      _activePath = _findActiveStatic(_kNav, loc) ?? '/dashboard';
      _pageTitle = _titleForStatic(_kNav, _activePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 768) return _MobileShell(child: widget.child);

    final w = _expanded ? AppSpacing.sidebarExpanded : AppSpacing.sidebarCollapsed;

    return Scaffold(
      body: Stack(children: [
        // ── Particle layer wrapped with RepaintBoundary to isolate painting ──
        Positioned.fill(
          child: RepaintBoundary(
            child: Container(
              color: const Color.fromARGB(255, 199, 199, 201),
              child: const ParticleNetwork(
                particleColor: Colors.white60, // opacity handled in original
                lineColor: Color(0x1F4F46E5), // 0.12 opacity ≈ 0x1F
                particleCount: 100,
                maxSpeed: 1.0,
                maxSize: 2.0,
                lineDistance: 100,
                drawNetwork: true,
                touchActivation: false,
                gravityType: GravityType.none,
                gravityStrength: 0.08,
              ),
            ),
          ),
        ),
        Row(children: [
          // ── Sidebar ──────────────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: w,
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 18, 24, 35).withOpacity(0.90),
              border: const Border(right: BorderSide(color: Colors.white, width: 1)),
            ),
            child: ClipRect(
              child: _expanded
                  ? _ExpandedSidebar(
                      active: _activePath,
                      openGroups: _open,
                      onNavigate: (p) => context.go(p),
                      onToggle: _toggle,
                    )
                  : _CollapsedSidebar(
                      active: _activePath,
                      onNavigate: (p) => context.go(p),
                    ),
            ),
          ),
          // ── Content ──────────────────────────────────────────────────
          Expanded(
            child: Column(children: [
              _Header(
                expanded: _expanded,
                onToggle: () => setState(() => _expanded = !_expanded),
                title: _pageTitle,
              ),
              Expanded(child: widget.child),
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Expanded Sidebar (unchanged UI, added const where possible)
// ══════════════════════════════════════════════════════════════════════════
class _ExpandedSidebar extends StatelessWidget {
  final String active;
  final Set<String> openGroups;
  final void Function(String) onNavigate;
  final void Function(String) onToggle;

  const _ExpandedSidebar({
    required this.active,
    required this.openGroups,
    required this.onNavigate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Column(children: [
    const _SidebarHeader(expanded: true),
    const Divider(color: AppColors.slate800, height: 1),
    const SizedBox(height: 8),
    Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: _buildItems(_kNav, 0),
      ),
    ),
    const Divider(color: AppColors.slate800, height: 1),
  ]);

  static void _noop() {} // placeholder for logout action

  List<Widget> _buildItems(List<_NavItem> items, int depth) {
    final out = <Widget>[];
    for (final item in items) {
      if (item is _Route) {
        out.add(_NavTile(
          icon: item.icon,
          label: item.label,
          selected: active == item.path,
          depth: depth,
          onTap: () => onNavigate(item.path),
        ));
      } else if (item is _Group) {
        final isOpen = openGroups.contains(item.label);
        final hasActive = _groupContainsActiveStatic(item.children, active);
        out.add(_GroupTile(
          icon: item.icon,
          label: item.label,
          isOpen: isOpen,
          hasActive: hasActive,
          depth: depth,
          onTap: () => onToggle(item.label),
        ));
        if (isOpen) out.addAll(_buildItems(item.children, depth + 1));
      }
    }
    return out;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// Collapsed Sidebar (unchanged UI, added const)
// ══════════════════════════════════════════════════════════════════════════
class _CollapsedSidebar extends StatelessWidget {
  final String active;
  final void Function(String) onNavigate;

  const _CollapsedSidebar({required this.active, required this.onNavigate});

  @override
  Widget build(BuildContext context) => Column(children: [
    const _SidebarHeader(expanded: false),
    const Divider(color: AppColors.slate800, height: 1),
    const SizedBox(height: 8),
    Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: _kNav.map((item) {
          if (item is _Route) {
            return _CollapsedTile(
              icon: item.icon,
              label: item.label,
              selected: active == item.path,
              onTap: () => onNavigate(item.path),
            );
          } else if (item is _Group) {
            return _CollapsedGroupTile(
              group: item,
              active: active,
              onNavigate: onNavigate,
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    ),
    const Divider(color: AppColors.slate800, height: 1),
   
  ]);

  static void _noop() {}
}

// ══════════════════════════════════════════════════════════════════════════
// _NavTile (optimized with const constructor where possible)
// ══════════════════════════════════════════════════════════════════════════
class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int depth;
  final VoidCallback onTap;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final indent = depth == 0 ? 0.0 : depth * 14.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: depth == 0 ? 40 : 34,
          padding: EdgeInsets.only(left: 10 + indent, right: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.indigo600 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            if (depth == 0) ...[
              Icon(icon,
                  size: 18,
                  color: selected ? Colors.white : AppColors.slate400),
              const SizedBox(width: 10),
            ] else
              Container(
                width: 1.5,
                height: 16,
                color: selected
                    ? Colors.white.withOpacity(0.45)
                    : AppColors.slate700,
                margin: const EdgeInsets.only(right: 10),
              ),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: depth == 0 ? 14 : 13,
                  fontWeight: FontWeight.w500,
                  color: selected ? Colors.white : AppColors.slate400,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.chevron_right,
                  size: 15, color: Colors.white.withOpacity(0.7)),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// _GroupTile (optimized with const)
// ══════════════════════════════════════════════════════════════════════════
class _GroupTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOpen;
  final bool hasActive;
  final int depth;
  final VoidCallback onTap;

  const _GroupTile({
    required this.icon,
    required this.label,
    required this.isOpen,
    required this.hasActive,
    required this.depth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final indent = depth == 0 ? 0.0 : depth * 14.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: depth == 0 ? 40 : 34,
          padding: EdgeInsets.only(left: 10 + indent, right: 10),
          decoration: BoxDecoration(
            color: (hasActive && depth == 0)
                ? AppColors.slate800
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            if (depth == 0) ...[
              Icon(icon,
                  size: 18,
                  color: hasActive ? AppColors.indigo400 : AppColors.slate400),
              const SizedBox(width: 10),
            ] else
              Container(
                width: 1.5,
                height: 16,
                color: AppColors.slate700,
                margin: const EdgeInsets.only(right: 10),
              ),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: depth == 0 ? 14 : 13,
                  fontWeight: FontWeight.w500,
                  color: hasActive ? AppColors.slate200 : AppColors.slate400,
                ),
              ),
            ),
            AnimatedRotation(
              turns: isOpen ? 0.25 : 0,
              duration: const Duration(milliseconds: 200),
              child: Icon(Icons.chevron_right,
                  size: 16,
                  color: isOpen ? AppColors.slate300 : AppColors.slate600),
            ),
          ]),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// _CollapsedTile (const)
// ══════════════════════════════════════════════════════════════════════════
class _CollapsedTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CollapsedTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Tooltip(
          message: label,
          preferBelow: false,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: selected ? AppColors.indigo600 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(icon,
                    size: 19,
                    color: selected ? Colors.white : AppColors.slate400),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// _CollapsedGroupTile (improved overlay management)
// ══════════════════════════════════════════════════════════════════════════
class _CollapsedGroupTile extends StatefulWidget {
  final _Group group;
  final String active;
  final void Function(String) onNavigate;

  const _CollapsedGroupTile({
    required this.group,
    required this.active,
    required this.onNavigate,
  });

  @override
  State<_CollapsedGroupTile> createState() => _CollapsedGroupTileState();
}

class _CollapsedGroupTileState extends State<_CollapsedGroupTile> {
  OverlayEntry? _entry;
  Timer? _timer;
  final GlobalKey _key = GlobalKey();

  bool get _hasActive =>
      _groupContainsActiveStatic(widget.group.children, widget.active);

  void _show() {
    _timer?.cancel();
    if (_entry != null) return;

    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);

    _entry = OverlayEntry(
      builder: (_) => Positioned(
        left: AppSpacing.sidebarCollapsed + 6,
        top: pos.dy,
        child: MouseRegion(
          onEnter: (_) => _timer?.cancel(),
          onExit: (_) => _scheduleHide(),
          child: _GroupPopup(
            group: widget.group,
            active: widget.active,
            onNavigate: (path) {
              widget.onNavigate(path);
              _remove();
            },
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  void _scheduleHide() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 160), _remove);
  }

  void _remove() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
        key: _key,
        onEnter: (_) => _show(),
        onExit: (_) => _scheduleHide(),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: InkWell(
            onTap: () {}, // no action on tap; hover shows popup
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _hasActive ? AppColors.slate800 : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(widget.group.icon,
                    size: 19,
                    color:
                        _hasActive ? AppColors.indigo400 : AppColors.slate400),
              ),
            ),
          ),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// _GroupPopup (unchanged UI, added const)
// ══════════════════════════════════════════════════════════════════════════
class _GroupPopup extends StatelessWidget {
  final _Group group;
  final String active;
  final void Function(String) onNavigate;

  const _GroupPopup({
    required this.group,
    required this.active,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: Container(
          width: 208,
          constraints: const BoxConstraints(maxHeight: 440),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.slate700, width: 0.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 18,
                  offset: const Offset(3, 5))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(children: [
                  Icon(group.icon, size: 14, color: AppColors.indigo400),
                  const SizedBox(width: 8),
                  Text(group.label,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ]),
              ),
              const Divider(color: AppColors.slate800, height: 1),
              const SizedBox(height: 4),
              ..._buildItems(group.children, 0),
              const SizedBox(height: 4),
            ],
          ),
        ),
      );

  List<Widget> _buildItems(List<_NavItem> items, int depth) {
    final out = <Widget>[];
    for (final item in items) {
      if (item is _Route) {
        final sel = item.path == active;
        out.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
            child: InkWell(
              onTap: () => onNavigate(item.path),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: EdgeInsets.fromLTRB(8 + depth * 10.0, 8, 8, 8),
                decoration: BoxDecoration(
                  color: sel ? AppColors.indigo600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(item.label,
                        style: TextStyle(
                          fontSize: 13,
                          color: sel ? Colors.white : AppColors.slate300,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                        )),
                  ),
                  if (sel)
                    const Icon(Icons.chevron_right,
                        size: 14, color: Colors.white),
                ]),
              ),
            ),
          ),
        );
      } else if (item is _Group) {
        out.add(
          Padding(
            padding: EdgeInsets.fromLTRB(16 + depth * 10.0, 8, 12, 2),
            child: Text(item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.slate500,
                  letterSpacing: 0.5,
                )),
          ),
        );
        out.addAll(_buildItems(item.children, depth + 1));
      }
    }
    return out;
  }
}

// ══════════════════════════════════════════════════════════════════════════
// _SidebarHeader (const)
// ══════════════════════════════════════════════════════════════════════════
class _SidebarHeader extends StatelessWidget {
  final bool expanded;
  const _SidebarHeader({required this.expanded});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: AppSpacing.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  color: AppColors.indigo600,
                  borderRadius: BorderRadius.circular(8)),
              alignment: Alignment.center,
              child: const Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16)),
            ),
            if (expanded) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text('AARTI ENTERPRISES',
                    style: AppTextStyles.sidebarBrand,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// _Header (top bar) – UPDATED: dynamic user info from AuthNotifier
// ══════════════════════════════════════════════════════════════════════════
class _Header extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final String title;

  const _Header({
    required this.expanded,
    required this.onToggle,
    required this.title,
  });

  @override
  Widget build(BuildContext context) => Container(
        height: AppSpacing.headerHeight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 18, 24, 35).withOpacity(0.90),
          border: const Border(bottom: BorderSide(color: AppColors.slate200)),
        ),
        child: Row(children: [
          IconButton(
            onPressed: onToggle,
            icon: AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.chevron_right, color: AppColors.slate500),
            ),
          ),
          const SizedBox(width: 4),
          Text(title, style: AppTextStyles.h4.copyWith(color: Colors.white)),
          const Spacer(),

          // ── Dynamic user info section ────────────────────────────────────
          ListenableBuilder(
            listenable: AuthNotifier.instance,
            builder: (ctx, _) {
              final user = AuthNotifier.instance.user;
              final name = user?.displayName ?? 'Admin User';
              final email = user?.email ?? '';
              final initials = user?.initials ?? 'AU';
              return Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(name,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: Colors.white70)),
                      if (email.isNotEmpty)
                        Text(email,
                            style: AppTextStyles.small
                                .copyWith(color: Colors.white60)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => context.go('/profile'),
                      child: CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.indigo600,
                        child: Text(initials,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ]),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// _MobileShell
// ══════════════════════════════════════════════════════════════════════════
class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}
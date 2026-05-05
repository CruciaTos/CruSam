// ignore_for_file: unused_element_parameter
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:particles_network/particles_network.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/notifiers/auth_notifier.dart';
import 'package:crusam/features/master_data/notifiers/employee_notifier.dart';
// ── AI chat integration ─────────────────────────────────────────────────────
import '../../core/ai/presentation/ai_context_builder.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';
import 'package:crusam/features/salary/notifier/salary_state_controller.dart';
import 'package:crusam/features/salary/notifier/salary_data_notifier.dart';
import 'package:crusam/core/ai/notifier/ai_chat_notifier.dart';
import '../../shared/widgets/ai_chat_panel.dart';   // ← AiChatScreen lives here


// ─────────────────────────────────────────────────────────────────────────────
// Dark Slate Color Scheme – Minimal & Eye‑Friendly
// ─────────────────────────────────────────────────────────────────────────────
class _ShellColors {
  static const background = Color(0xFF0B1120);
  static const surface = Color(0xFF1E293B);
  static const surfaceGlass = Color(0xE61E293B);
  static const border = Color(0xFF334155);
  static const primary = Color(0xFF3B82F6);
  static const primaryLight = Color(0xFF60A5FA);
  static const primaryMuted = Color(0x1A3B82F6);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFF94A3B8);
  static const textDisabled = Color(0xFF64748B);
  static const iconDefault = Color(0xFF94A3B8);
  static const iconActive = Color(0xFFFFFFFF);
  static const divider = Color(0xFF334155);
  static const hoverOverlay = Color(0x1AF8FAFC);
  static const selectedOverlay = Color(0x261E3A8A);
  static const sectionHeader = Color(0xFF475569);
  static const squeezeLimit = Color(0xFFEF4444);   // red when min width reached
}

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
  final Set<String> _open = {'Salary-Output'};

  String _currentLocation = '';
  String _activePath = '/dashboard';
  String _pageTitle = 'Dashboard';

  // ─── Resizable AI panel state ───────────────────────────────────────────
  bool   _isPanelOpen   = false;
  double _panelWidth    = 400;
  bool   _handleHovered = false;

  static const double _minPanelWidth = 300;
  static const double _maxPanelWidth = 700;
  static const double _defaultWidth  = 400;

  // Dynamic line colour – turns red when the panel can't be squeezed further
  Color get _handleLineColor {
    final atLimit = _panelWidth == _minPanelWidth;
    if (atLimit) {
      return _ShellColors.squeezeLimit.withOpacity(_handleHovered ? 0.8 : 0.4);
    }
    return _handleHovered ? Colors.white54 : Colors.white24;
  }

  void _togglePanel() {
    setState(() {
      if (_isPanelOpen) {
        _isPanelOpen = false;
      } else {
        _isPanelOpen = true;
        _panelWidth = _defaultWidth;
      }
    });
  }

  void _closePanel() => setState(() => _isPanelOpen = false);

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
        // Animated background particles
        Positioned.fill(
          child: RepaintBoundary(
            child: Container(
              color: _ShellColors.background,
              child: const ParticleNetwork(
                particleColor: Color(0x3394A3B8),
                lineColor: Color(0x1A3B82F6),
                particleCount: 80,
                maxSpeed: 0.8,
                maxSize: 2.2,
                lineDistance: 120,
                drawNetwork: true,
                touchActivation: false,
                gravityType: GravityType.none,
                gravityStrength: 0.08,
              ),
            ),
          ),
        ),
        // Main layout – left sidebar + central area
        Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: w,
            decoration: BoxDecoration(
              color: _ShellColors.surfaceGlass,
              border: Border(right: BorderSide(color: _ShellColors.border)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(2, 0),
                ),
              ],
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
          // ───── Central area + resizable AI panel on the right ─────
          Expanded(
            child: Stack(children: [
              Column(children: [
                _Header(
                  expanded: _expanded,
                  onToggle: () => setState(() => _expanded = !_expanded),
                  title: _pageTitle,
                  onAiTap: _togglePanel,
                  isPanelOpen: _isPanelOpen,
                ),
                Expanded(child: widget.child),
              ]),
              // ── Resizable AI chat panel ──
              if (_isPanelOpen) ...[
                // Backdrop (tap to close)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closePanel,
                    child: Container(color: Colors.black.withOpacity(0.18)),
                  ),
                ),
                // Panel itself
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _panelWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ══════ Drag handle – full‑height line on the right side ══════
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        onEnter: (_) => setState(() => _handleHovered = true),
                        onExit:  (_) => setState(() => _handleHovered = false),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _panelWidth -= details.delta.dx;
                              _panelWidth = _panelWidth.clamp(_minPanelWidth, _maxPanelWidth);
                            });
                          },
                          child: Container(
                            width: 6,
                            decoration: BoxDecoration(
                              // The visible line is the right border of this thin zone
                              border: Border(
                                right: BorderSide(
                                  color: _handleLineColor,
                                  width: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ═══ Chat screen – with horizontal scroll when squeezed ═══
                      Expanded(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: _panelWidth,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surface,
                                border: Border(
                                  left: BorderSide(color: _ShellColors.border),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.30),
                                    blurRadius: 24,
                                    offset: const Offset(-6, 0),
                                  ),
                                ],
                              ),
                              child: const AiChatScreen(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ]),
          ),
        ]),
      ]),
    );
  }
}

// ───── Expanded Sidebar (unchanged) ─────────────────────────────────────────
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
    const SizedBox(height: 4),
    Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: _buildItems(_kNav, 0),
      ),
    ),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _ShellColors.divider.withOpacity(0.5))),
      ),
      child: _buildBottomActions(context),
    ),
  ]);

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
        if (out.isNotEmpty) {
          out.add(const SizedBox(height: 1));
          out.add(Divider(
            color: _ShellColors.divider.withOpacity(0.3),
            indent: 10,
            endIndent: 10,
            height: 1,
            thickness: 0.5,
          ));
          out.add(const SizedBox(height: 1));
        }
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

  Widget _buildBottomActions(BuildContext context) {
    return Column(
      children: [
        _NavTile(
          icon: Icons.settings_outlined,
          label: 'Settings',
          selected: active == '/profile',
          depth: 0,
          onTap: () => onNavigate('/profile'),
        ),
        const SizedBox(height: 2),
        _NavTile(
          icon: Icons.logout_outlined,
          label: 'Logout',
          selected: false,
          depth: 0,
          onTap: () async {
            await AuthNotifier.instance.logout();
            if (context.mounted) {
              context.go('/login');
            }
          },
        ),
      ],
    );
  }
}

// ───── Collapsed Sidebar (unchanged) ────────────────────────────────────────
class _CollapsedSidebar extends StatelessWidget {
  final String active;
  final void Function(String) onNavigate;

  const _CollapsedSidebar({required this.active, required this.onNavigate});

  @override
  Widget build(BuildContext context) => Column(children: [
    const _SidebarHeader(expanded: false),
    const SizedBox(height: 4),
    Expanded(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 6),
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
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _ShellColors.divider.withOpacity(0.5))),
      ),
      child: Column(
        children: [
          _CollapsedTile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            selected: active == '/profile',
            onTap: () => onNavigate('/profile'),
          ),
          const SizedBox(height: 2),
          _CollapsedTile(
            icon: Icons.logout_outlined,
            label: 'Logout',
            selected: false,
            onTap: () async {
              await AuthNotifier.instance.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    ),
  ]);
}

// ───── Navigation tiles (unchanged) ──────────────────────────────────────────
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
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: depth == 0 ? 40 : 32,
            padding: EdgeInsets.only(left: 6 + indent, right: 6),
            decoration: BoxDecoration(
              color: selected ? _ShellColors.selectedOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? Border.all(color: _ShellColors.primary.withOpacity(0.2), width: 1)
                  : null,
            ),
            child: Row(children: [
              if (depth == 0) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: selected
                        ? _ShellColors.primary.withOpacity(0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: selected ? _ShellColors.primary : _ShellColors.iconDefault,
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 2,
                    height: 14,
                    decoration: BoxDecoration(
                      color: selected
                          ? _ShellColors.primary.withOpacity(0.6)
                          : _ShellColors.divider,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: depth == 0 ? 13 : 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? _ShellColors.textPrimary : _ShellColors.textSecondary,
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.chevron_right,
                    size: 14, color: _ShellColors.primary.withOpacity(0.8)),
            ]),
          ),
        ),
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: depth == 0 ? 40 : 32,
            padding: EdgeInsets.only(left: 6 + indent, right: 6),
            decoration: BoxDecoration(
              color: hasActive ? _ShellColors.hoverOverlay : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              if (depth == 0) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: hasActive
                        ? _ShellColors.primary.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: hasActive ? _ShellColors.primary : _ShellColors.iconDefault,
                  ),
                ),
                const SizedBox(width: 8),
              ] else
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 2,
                    height: 14,
                    decoration: BoxDecoration(
                      color: _ShellColors.divider,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: depth == 0 ? 13 : 12,
                    fontWeight: FontWeight.w600,
                    color: hasActive ? _ShellColors.textPrimary : _ShellColors.textSecondary,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: isOpen ? 0.25 : 0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: isOpen ? _ShellColors.primary.withOpacity(0.1) : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: isOpen ? _ShellColors.primary : _ShellColors.textDisabled,
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

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
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: selected ? _ShellColors.selectedOverlay : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: selected
                      ? Border.all(color: _ShellColors.primary.withOpacity(0.3), width: 1)
                      : null,
                ),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? _ShellColors.primary.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: selected ? _ShellColors.primary : _ShellColors.iconDefault,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

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
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {},
              borderRadius: BorderRadius.circular(10),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: _hasActive ? _ShellColors.hoverOverlay : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _hasActive
                          ? _ShellColors.primary.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      widget.group.icon,
                      size: 18,
                      color: _hasActive ? _ShellColors.primary : _ShellColors.iconDefault,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

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
          width: 210,
          constraints: const BoxConstraints(maxHeight: 400),
          decoration: BoxDecoration(
            color: _ShellColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _ShellColors.border, width: 0.5),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(4, 6))
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _ShellColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(group.icon, size: 13, color: _ShellColors.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(group.label,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _ShellColors.textPrimary)),
                ]),
              ),
              Divider(color: _ShellColors.divider, height: 1),
              const SizedBox(height: 2),
              ..._buildItems(group.children, 0),
              const SizedBox(height: 2),
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
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onNavigate(item.path),
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  padding: EdgeInsets.fromLTRB(6 + depth * 10.0, 8, 6, 8),
                  decoration: BoxDecoration(
                    color: sel ? _ShellColors.selectedOverlay : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Text(item.label,
                          style: TextStyle(
                            fontSize: 12,
                            color: sel ? _ShellColors.textPrimary : _ShellColors.textSecondary,
                            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                          )),
                    ),
                    if (sel)
                      Icon(Icons.chevron_right,
                          size: 13, color: _ShellColors.primary),
                  ]),
                ),
              ),
            ),
          ),
        );
      } else if (item is _Group) {
        out.add(
          Padding(
            padding: EdgeInsets.fromLTRB(14 + depth * 10.0, 8, 14, 3),
            child: Text(item.label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _ShellColors.sectionHeader,
                  letterSpacing: 0.4,
                )),
          ),
        );
        out.addAll(_buildItems(item.children, depth + 1));
      }
    }
    return out;
  }
}

// ───── Sidebar header (unchanged) ────────────────────────────────────────────
class _SidebarHeader extends StatelessWidget {
  final bool expanded;
  const _SidebarHeader({required this.expanded});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: AppSpacing.headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _ShellColors.primary,
                      _ShellColors.primary.withOpacity(0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: _ShellColors.primary.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]),
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
                    style: AppTextStyles.sidebarBrand.copyWith(
                      color: _ShellColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ]),
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════
// _Header – with AI panel toggle
// ══════════════════════════════════════════════════════════════════════════
class _Header extends StatefulWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final String title;
  final VoidCallback onAiTap;
  final bool isPanelOpen;

  const _Header({
    required this.expanded,
    required this.onToggle,
    required this.title,
    required this.onAiTap,
    required this.isPanelOpen,
  });

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  bool _isHoveredAI = false;

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      height: AppSpacing.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _ShellColors.surfaceGlass,
        border: Border(bottom: BorderSide(color: _ShellColors.border)),
      ),
      child: Row(children: [
        IconButton(
          onPressed: widget.onToggle,
          icon: Icon(
            widget.expanded ? Icons.chevron_left : Icons.chevron_right,
            color: _ShellColors.iconDefault,
          ),
        ),
        const SizedBox(width: 4),
        Text(widget.title,
            style: AppTextStyles.h4.copyWith(color: _ShellColors.textPrimary)),
        const Spacer(),

        // AI Assistant – opens resizable right‑side panel
        MouseRegion(
          onEnter: (_) => setState(() => _isHoveredAI = true),
          onExit: (_) => setState(() => _isHoveredAI = false),
          child: IconButton(
            icon: Icon(
              Icons.auto_awesome,
              color: widget.isPanelOpen || _isHoveredAI
                  ? primaryColor
                  : _ShellColors.iconDefault,
            ),
            tooltip: 'AI Assistant',
            onPressed: () async {           // ← add async
  final ctx = await AiContextBuilder.build(   // ← add await
    employeeNotifier: EmployeeNotifier.instance,
    salaryStateController: SalaryStateController.instance,
    salaryDataNotifier: SalaryDataNotifier.instance,
    voucherNotifier: VoucherNotifier.instance,
    currentVoucher: VoucherNotifier.instance.current,
  );
  AiChatNotifier.instance.updateContext(ctx);
  widget.onAiTap();
},
          ),
        ),
        const SizedBox(width: 12),

        // User info
        ListenableBuilder(
          listenable: AuthNotifier.instance,
          builder: (ctx, _) {
            final user = AuthNotifier.instance.user;
            final name = user?.displayName ?? 'Admin User';
            final initials = user?.initials ?? 'AU';

            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(name,
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: _ShellColors.textPrimary)),
                  ],
                ),
                const SizedBox(width: 12),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => context.go('/profile'),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: _ShellColors.primary,
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
}

// ───── Mobile shell (unchanged) ──────────────────────────────────────────────
class _MobileShell extends StatelessWidget {
  final Widget child;
  const _MobileShell({required this.child});
  @override
  Widget build(BuildContext context) => Scaffold(body: child);
}
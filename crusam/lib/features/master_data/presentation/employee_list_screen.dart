// employee_list_screen.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/employee_model.dart';
import '../../../shared/widgets/app_card.dart';
import '../notifiers/employee_notifier.dart';
import '../services/employee_excel_import_service.dart';
import 'employee_form_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Column definition for the white table
// ─────────────────────────────────────────────────────────────────────────────

class _ColDef {
  final String label;
  double width;
  _ColDef(this.label, this.width);
}

// ─────────────────────────────────────────────────────────────────────────────
// EmployeeListScreen
// ─────────────────────────────────────────────────────────────────────────────

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});

  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  // ───────────── USE SINGLETON ─────────────
  final _notifier = EmployeeNotifier.instance;
  // ─────────────────────────────────────────

  final _searchController = TextEditingController();
  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();

  Timer? _debounceTimer;
  bool _showHorizontalScrollbar = false;
  bool _isImporting = false;
  bool _showColPanel = false;
  bool _insightsOpen = false;

  String _searchQuery = '';

  // Quick-filter state (from bigger file)
  String _genderFilter = 'All';
  String _zoneFilter = 'All';
  String _codeFilter = 'All';

  // ─────────────────────────── Focus Nodes ─────────────────────────────────
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'Search');
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'AddButton');
  final FocusNode _colButtonFocusNode = FocusNode(debugLabel: 'ColButton');
  final FocusNode _tableFocusNode = FocusNode(debugLabel: 'Table');
  late final List<FocusNode> _majorFocusNodes;

  int? _focusedRowIndex;

  // ─────────────────────────── Column Defs ─────────────────────────────────
  final _cols = [
    _ColDef('Sr.', 48),
    _ColDef('Gender', 72),
    _ColDef('Name', 180),
    _ColDef('PF No.', 140),
    _ColDef('UAN No.', 130),
    _ColDef('Code', 64),
    _ColDef('IFSC', 110),
    _ColDef('Account No.', 150),
    _ColDef('Bank', 160),
    _ColDef('Branch', 160),
    _ColDef('Zone', 80),
    _ColDef('Basic ₹', 90),
    _ColDef('Other ₹', 90),
    _ColDef('Gross ₹', 110),
  ];

  double _tableMarginH = 12;
  double _tableMarginV = 8;

  late TextEditingController _marginHCtrl;
  late TextEditingController _marginVCtrl;
  late List<TextEditingController> _colCtrls;

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_onModelChanged);
    _notifier.load();

    _searchController.addListener(_onSearchChanged);

    _marginHCtrl =
        TextEditingController(text: _tableMarginH.toStringAsFixed(0));
    _marginVCtrl =
        TextEditingController(text: _tableMarginV.toStringAsFixed(0));
    _colCtrls = _cols
        .map((c) => TextEditingController(text: c.width.toStringAsFixed(0)))
        .toList();

    _majorFocusNodes = [
      _searchFocusNode,
      _addButtonFocusNode,
      _colButtonFocusNode,
      _tableFocusNode,
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
      _notifier.search(_searchController.text);
      _clearRowFocus();
    });
  }

  void _onModelChanged() => setState(() {});

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _notifier.removeListener(_onModelChanged);
    // NOTE: Do NOT dispose the singleton notifier
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _marginHCtrl.dispose();
    _marginVCtrl.dispose();
    for (final c in _colCtrls) {
      c.dispose();
    }
    _searchFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _colButtonFocusNode.dispose();
    _tableFocusNode.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filtered lists (chip filters from bigger file)
  // ───────────────────────────────────────────────────────────────────────────

  List<EmployeeModel> get _filteredByChips {
    var list = _notifier.employees;
    if (_genderFilter != 'All') {
      list = list
          .where((e) => e.gender.toUpperCase() == _genderFilter)
          .toList();
    }
    if (_zoneFilter != 'All') {
      list = list.where((e) => e.zone.trim() == _zoneFilter).toList();
    }
    if (_codeFilter != 'All') {
      list = list.where((e) => e.code.trim() == _codeFilter).toList();
    }
    return list;
  }

  List<EmployeeModel> get _filteredForTable {
    var list = _filteredByChips;
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((e) =>
              e.name.toLowerCase().contains(_searchQuery) ||
              e.code.toLowerCase().contains(_searchQuery) ||
              e.pfNo.toLowerCase().contains(_searchQuery) ||
              e.uanNo.toLowerCase().contains(_searchQuery) ||
              e.accountNumber.toLowerCase().contains(_searchQuery))
          .toList();
    }
    return list;
  }

  List<String> get _distinctZones => _notifier.employees
      .map((e) => e.zone.trim())
      .where((z) => z.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  List<String> get _distinctCodes => _notifier.employees
      .map((e) => e.code.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  // ───────────────────────────────────────────────────────────────────────────
  // Actions
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _goToForm([EmployeeModel? emp]) async {
    await showDialog(
      context: context,
      barrierColor: Colors.black45,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: EmployeeFormScreen(employee: emp?.toMap()),
      ),
    );
    await _notifier.load();
    if (_searchController.text.isNotEmpty) {
      _notifier.search(_searchController.text);
    }
    _clearRowFocus();
  }

  Future<void> _onImportExcel() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await EmployeeExcelImportService.importFromFile();
      if (!mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Import Preview'),
          content: Text(
            'Valid: ${result.validCount}\n'
            'Duplicates (in file): ${result.duplicateCount}\n'
            'Invalid: ${result.invalidCount}\n\nProceed?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Import')),
          ],
        ),
      );
      if (confirm != true) return;
      final inserted =
          await _notifier.importEmployees(result.validEmployees);
      if (!mounted) return;
      final skipped = (result.validEmployees.length - inserted) +
          result.duplicateCount +
          result.invalidCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported: $inserted, Skipped: $skipped')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Import failed')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _resetFilters() {
    setState(() {
      _genderFilter = 'All';
      _zoneFilter = 'All';
      _codeFilter = 'All';
    });
  }

  bool get _hasActiveFilters =>
      _genderFilter != 'All' ||
      _zoneFilter != 'All' ||
      _codeFilter != 'All';

  // ─────────────────────── Horizontal Scrollbar toggle ─────────────────────
  void _toggleHorizontalScrollbar(bool visible) {
    if (_showHorizontalScrollbar == visible || !mounted) return;
    setState(() => _showHorizontalScrollbar = visible);
  }

  // ─────────────────────── Major Widget Focus Navigation ───────────────────
  bool _isEditableTextFocused() {
    final current = FocusManager.instance.primaryFocus;
    return current?.context
            ?.findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  void _moveFocusToPreviousMajor() {
    if (_isEditableTextFocused()) return;
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus == null) {
      _majorFocusNodes.first.requestFocus();
      return;
    }
    int currentIndex = _majorFocusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      _majorFocusNodes.first.requestFocus();
      return;
    }
    int prevIndex = (currentIndex - 1 + _majorFocusNodes.length) %
        _majorFocusNodes.length;
    _majorFocusNodes[prevIndex].requestFocus();
    _clearRowFocusIfNotTable(prevIndex);
  }

  void _moveFocusToNextMajor() {
    if (_isEditableTextFocused()) return;
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus == null) {
      _majorFocusNodes.first.requestFocus();
      return;
    }
    int currentIndex = _majorFocusNodes.indexOf(currentFocus);
    if (currentIndex == -1) {
      _majorFocusNodes.first.requestFocus();
      return;
    }
    int nextIndex = (currentIndex + 1) % _majorFocusNodes.length;
    _majorFocusNodes[nextIndex].requestFocus();
    _clearRowFocusIfNotTable(nextIndex);
  }

  void _clearRowFocusIfNotTable(int index) {
    if (_majorFocusNodes[index] != _tableFocusNode) {
      _clearRowFocus();
    }
  }

  // ─────────────────────────── Focus Management ────────────────────────────
  void _clearRowFocus() {
    if (_focusedRowIndex != null) {
      setState(() => _focusedRowIndex = null);
    }
  }

  void _ensureRowVisible(int index) {
    const rowHeight = 42.0;
    final scrollOffset = index * rowHeight;
    final viewportHeight =
        _verticalScrollController.position.viewportDimension;
    final currentScroll = _verticalScrollController.offset;

    if (scrollOffset < currentScroll) {
      _verticalScrollController.animateTo(
        scrollOffset.toDouble(),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else if (scrollOffset + rowHeight > currentScroll + viewportHeight) {
      _verticalScrollController.animateTo(
        (scrollOffset + rowHeight - viewportHeight).toDouble(),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final logicalKey = event.logicalKey;
    final isArrow = logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight;
    if (isArrow && !HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTableKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    final filtered = _filteredForTable;
    if (filtered.isEmpty) return KeyEventResult.ignored;

    final currentIndex = _focusedRowIndex;
    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.arrowDown) {
      if (currentIndex == null) {
        setState(() => _focusedRowIndex = 0);
        _ensureRowVisible(0);
      } else if (currentIndex < filtered.length - 1) {
        setState(() => _focusedRowIndex = currentIndex + 1);
        _ensureRowVisible(currentIndex + 1);
      }
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.arrowUp) {
      if (currentIndex != null && currentIndex > 0) {
        setState(() => _focusedRowIndex = currentIndex - 1);
        _ensureRowVisible(currentIndex - 1);
      } else if (currentIndex == null && filtered.isNotEmpty) {
        setState(() => _focusedRowIndex = 0);
        _ensureRowVisible(0);
      }
      return KeyEventResult.handled;
    }

    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (currentIndex != null && currentIndex < filtered.length) {
        _goToForm(filtered[currentIndex]);
        return KeyEventResult.handled;
      }
    }

    if (logicalKey == LogicalKeyboardKey.delete) {
      if (currentIndex != null && currentIndex < filtered.length) {
        _confirmAndDelete(filtered[currentIndex]);
        return KeyEventResult.handled;
      }
    }

    if (logicalKey == LogicalKeyboardKey.escape) {
      _clearRowFocus();
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance.isControlPressed &&
        logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance.isControlPressed &&
        logicalKey == LogicalKeyboardKey.keyN) {
      _goToForm();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _confirmAndDelete(EmployeeModel employee) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Delete "${employee.name}" (${employee.pfNo})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _notifier.delete(employee.id!);
    if (!mounted) return;
    setState(() {
      if (_focusedRowIndex != null) {
        final newLength = _filteredForTable.length;
        if (_focusedRowIndex! >= newLength) {
          _focusedRowIndex = newLength > 0 ? newLength - 1 : null;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${employee.name} deleted')),
    );
  }

  // ─────────────────────────── Build ───────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
          const _PreviousMajorFocusIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
          const _NextMajorFocusIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
          const _PreviousMajorFocusIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
          const _NextMajorFocusIntent(),
    };

    final actions = <Type, Action<Intent>>{
      _PreviousMajorFocusIntent:
          CallbackAction<_PreviousMajorFocusIntent>(
        onInvoke: (_) => _moveFocusToPreviousMajor(),
      ),
      _NextMajorFocusIntent:
          CallbackAction<_NextMajorFocusIntent>(
        onInvoke: (_) => _moveFocusToNextMajor(),
      ),
    };

    return Focus(
      onKeyEvent: _handleRootKeyEvent,
      canRequestFocus: false,
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: actions,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.pagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Dark Header (from bigger file) ──────────────────────
                  _buildHeader(),
                  const SizedBox(height: AppSpacing.md),

                  // ── Stats Bar (from bigger file) ────────────────────────
                  if (!_notifier.isLoading)
                    _StatsBar(employees: _filteredByChips),

                  const SizedBox(height: AppSpacing.md),

                  // ── Chip Filters (from bigger file) ─────────────────────
                  if (!_notifier.isLoading)
                    _Filters(
                      genderFilter: _genderFilter,
                      zoneFilter: _zoneFilter,
                      codeFilter: _codeFilter,
                      zones: _distinctZones,
                      codes: _distinctCodes,
                      onGenderChanged: (v) =>
                          setState(() => _genderFilter = v),
                      onZoneChanged: (v) =>
                          setState(() => _zoneFilter = v),
                      onCodeChanged: (v) =>
                          setState(() => _codeFilter = v),
                      onReset: _resetFilters,
                    ),

                  const SizedBox(height: AppSpacing.md),

                  // ── Search Bar ──────────────────────────────────────────
                  _buildSearchBar(),

                  const SizedBox(height: AppSpacing.sm),

                  // ── Table + Insights ────────────────────────────────────
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildMainContent()),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: _insightsOpen
                              ? SizedBox(
                                  width: 260,
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                        left: AppSpacing.md),
                                    child: _InsightsPanel(
                                        employees: _notifier.employees),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),

                  // ── Keyboard hint ───────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Keyboard: ↑↓ navigate rows • Shift+↑↓ switch widgets • Enter edit • Delete remove • Esc search',
                      style: AppTextStyles.small.copyWith(
                        color: AppColors.slate500,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Dark header bar (from bigger file) ─────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border:
            Border.all(color: AppColors.indigo600.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.indigo600.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: const Icon(Icons.people_outline,
                color: AppColors.indigo400, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Employee Master Data',
                  style:
                      AppTextStyles.h3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_notifier.employees.length} employees registered',
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate400),
                ),
              ],
            ),
          ),
          // Import button
          
          _HeaderButton(
            icon: Icons.tune,
            label: 'Columns',
            active: _showColPanel,
            onTap: () =>
                setState(() => _showColPanel = !_showColPanel),
          ),
          const SizedBox(width: 8),
          // Insights toggle
          _HeaderButton(
            icon: _insightsOpen
                ? Icons.view_sidebar
                : Icons.view_sidebar_outlined,
            label: 'Insights',
            active: _insightsOpen,
            onTap: () =>
                setState(() => _insightsOpen = !_insightsOpen),
          ),
          const SizedBox(width: 8),
          // Add Employee
          FocusTraversalOrder(
            order: const NumericFocusOrder(1),
            child: _FocusGlow(
              focusNode: _addButtonFocusNode,
              glowColor: AppColors.indigo400.withOpacity(0.4),
              child: Focus(
                focusNode: _addButtonFocusNode,
                child: _HeaderButton(
                  icon: Icons.add,
                  label: 'Add Employee',
                  active: false,
                  onTap: () => _goToForm(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Search bar (styled like bigger file, with focus node) ──────────────────
  Widget _buildSearchBar() {
    return _FocusGlow(
      focusNode: _searchFocusNode,
      glowColor: AppColors.indigo400.withOpacity(0.4),
      child: SizedBox(
        height: 38,
        child: Focus(
          focusNode: _searchFocusNode,
          child: TextField(
            controller: _searchController,
            style: AppTextStyles.body.copyWith(color: Colors.white),
            decoration: InputDecoration(
              hintText:
                  'Search by name, code, PF, UAN, account… (Ctrl+F)',
              hintStyle: AppTextStyles.small
                  .copyWith(color: AppColors.slate500),
              prefixIcon: const Icon(Icons.search,
                  size: 16, color: AppColors.slate500),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close,
                          size: 14, color: AppColors.slate500),
                      onPressed: () {
                        _searchController.clear();
                        _notifier.search('');
                        _clearRowFocus();
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.slate800,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radius),
                borderSide:
                    const BorderSide(color: AppColors.slate700),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radius),
                borderSide:
                    const BorderSide(color: AppColors.slate700),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius:
                    BorderRadius.circular(AppSpacing.radius),
                borderSide:
                    const BorderSide(color: AppColors.indigo500),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Main content area ──────────────────────────────────────────────────────
  Widget _buildMainContent() {
    if (_notifier.isLoading) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }

    final filtered = _filteredForTable;
    if (filtered.isEmpty) {
      return _EmptyState(
        hasSearch:
            _searchQuery.isNotEmpty || _hasActiveFilters,
        onAdd: () => _goToForm(),
        onClearFilters: _hasActiveFilters ? _resetFilters : null,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: FocusTraversalOrder(
            order: const NumericFocusOrder(3),
            child: _FocusGlow(
              focusNode: _tableFocusNode,
              glowColor:
                  AppColors.indigo400.withOpacity(0.4),
              borderRadius: BorderRadius.circular(
                  AppSpacing.radiusMd),
              child: _tableCard(filtered),
            ),
          ),
        ),
        if (_showColPanel) ...[
          const SizedBox(width: 8),
          _colPanel(),
        ],
      ],
    );
  }

  // ── White table card (from smaller file) ──────────────────────────────────
  Widget _tableCard(List<EmployeeModel> filtered) => AppCard(
        padding: EdgeInsets.symmetric(
            horizontal: _tableMarginH, vertical: _tableMarginV),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.slate400),
            borderRadius:
                BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(AppSpacing.radiusMd),
            child: Column(
              children: [
                // Table caption bar
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      horizontal: _tableMarginH,
                      vertical: AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.slate50,
                    border: Border(
                        bottom: BorderSide(
                            color: AppColors.slate200)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Double-tap or press Enter to edit • Delete to remove',
                        style: AppTextStyles.small,
                      ),
                      const Spacer(),
                      if (_focusedRowIndex != null)
                        Text(
                          'Row ${_focusedRowIndex! + 1} of ${filtered.length}',
                          style: AppTextStyles.small.copyWith(
                              fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: Focus(
                    focusNode: _tableFocusNode,
                    onKeyEvent: _handleTableKeyEvent,
                    canRequestFocus: true,
                    descendantsAreFocusable: false,
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _verticalScrollController,
                        child: MouseRegion(
                          onEnter: (_) =>
                              _toggleHorizontalScrollbar(true),
                          onExit: (_) =>
                              _toggleHorizontalScrollbar(false),
                          child: Scrollbar(
                            controller:
                                _horizontalScrollController,
                            thumbVisibility:
                                _showHorizontalScrollbar,
                            trackVisibility: false,
                            thickness: 8,
                            radius: const Radius.circular(8),
                            notificationPredicate: (n) =>
                                n.metrics.axis ==
                                Axis.horizontal,
                            child: SingleChildScrollView(
                              controller:
                                  _horizontalScrollController,
                              scrollDirection: Axis.horizontal,
                              child: _buildTable(filtered),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Footer count
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.slate50,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.slate200)),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${filtered.length} employee${filtered.length == 1 ? '' : 's'}',
                      style: AppTextStyles.small.copyWith(
                          color: AppColors.slate500,
                          fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildTable(List<EmployeeModel> filtered) {
    final headerCells =
        _cols.map((c) => _th(c.label, c.width)).toList();
    final dataRows = <TableRow>[];

    for (int idx = 0; idx < filtered.length; idx++) {
      final e = filtered[idx];
      final isFemale = e.gender.toUpperCase() == 'F';
      final isFocused = _focusedRowIndex == idx;

      final row = _HoverableTableRow(
        key: ValueKey(e.id),
        cells: [
          _td((idx + 1).toString(), _cols[0].width,
              isFocused: isFocused),
          _tdGender(isFemale, _cols[1].width,
              isFocused: isFocused),
          _td(e.name, _cols[2].width,
              bold: true, isFocused: isFocused),
          _td(e.pfNo, _cols[3].width, isFocused: isFocused),
          _td(e.uanNo, _cols[4].width, isFocused: isFocused),
          _td(e.code, _cols[5].width, isFocused: isFocused),
          _tdMono(e.ifscCode, _cols[6].width,
              isFocused: isFocused),
          _tdMono(e.accountNumber, _cols[7].width,
              isFocused: isFocused),
          _td(e.bankDetails, _cols[8].width,
              isFocused: isFocused),
          _td(e.branch, _cols[9].width, isFocused: isFocused),
          _td(e.zone, _cols[10].width, isFocused: isFocused),
          _tdNum(e.basicCharges, _cols[11].width,
              isFocused: isFocused),
          _tdNum(e.otherCharges, _cols[12].width,
              isFocused: isFocused),
          _tdNum(e.grossSalary, _cols[13].width,
              isFocused: isFocused),
        ],
        onDoubleTap: () => _goToForm(e),
        onTap: () {
          setState(() {
            _focusedRowIndex = idx;
            _tableFocusNode.requestFocus();
          });
        },
        isFocused: isFocused,
      );
      dataRows.add(row.buildRow());
    }

    return Table(
      columnWidths: {
        for (int i = 0; i < _cols.length; i++)
          i: FixedColumnWidth(_cols[i].width)
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration:
              const BoxDecoration(color: AppColors.slate50),
          children: headerCells,
        ),
        ...dataRows,
      ],
    );
  }

  static Widget _th(String label, double width) => Container(
        width: width,
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 9),
        decoration: const BoxDecoration(
            border: Border(
                bottom:
                    BorderSide(color: AppColors.slate300))),
        child: Text(label, style: AppTextStyles.label),
      );

  static Widget _td(String value, double width,
          {bool bold = false, bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 8),
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontWeight:
                  bold ? FontWeight.w600 : FontWeight.w400,
              color: isFocused ? AppColors.indigo700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  static Widget _tdGender(bool isFemale, double width,
          {bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFemale
                    ? const Color(0xFFFCE7F3)
                    : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(99),
                border: isFocused
                    ? Border.all(
                        color: AppColors.indigo400,
                        width: 1.5)
                    : null,
              ),
              child: Text(
                isFemale ? 'F' : 'M',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFemale
                      ? const Color(0xFFBE185D)
                      : AppColors.blue600,
                ),
              ),
            ),
          ),
        ),
      );

  static Widget _tdMono(String value, double width,
          {bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 8),
          child: Text(
            value,
            style: AppTextStyles.monoSm.copyWith(
              color:
                  isFocused ? AppColors.indigo700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  static Widget _tdNum(double value, double width,
          {bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 8),
          child: Text(
            value == 0 ? '—' : '₹${value.toStringAsFixed(2)}',
            textAlign: TextAlign.left,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  isFocused ? AppColors.indigo700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  // ── Column width panel (from smaller file) ────────────────────────────────
  Widget _colPanel() => Container(
        width: 240,
        color: AppColors.slate50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                  border: Border(
                      bottom: BorderSide(
                          color: AppColors.slate200))),
              child: Row(
                children: [
                  Text('Column Widths',
                      style: AppTextStyles.label),
                  const Spacer(),
                  IconButton(
                    icon:
                        const Icon(Icons.close, size: 16),
                    onPressed: () =>
                        setState(() => _showColPanel = false),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text('Table Margins',
                      style: AppTextStyles.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: _marginField(
                            'H-Margin',
                            _marginHCtrl,
                            (v) => setState(
                                () => _tableMarginH = v))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _marginField(
                            'V-Margin',
                            _marginVCtrl,
                            (v) => setState(
                                () => _tableMarginV = v))),
                  ]),
                  const Divider(height: 20),
                  Text('Column Widths (px)',
                      style: AppTextStyles.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate700)),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _cols.length; i++)
                    _colWidthRow(_cols[i], _colCtrls[i]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _marginField(String label,
          TextEditingController ctrl,
          void Function(double) onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.small),
          const SizedBox(height: 4),
          SizedBox(
            height: 34,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true),
              style: AppTextStyles.input,
              decoration: const InputDecoration(
                  isDense: true,
                  suffixText: 'px',
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8)),
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null && d >= 0) onChanged(d);
              },
            ),
          ),
        ],
      );

  Widget _colWidthRow(
          _ColDef col, TextEditingController ctrl) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(col.label,
                  style: AppTextStyles.small,
                  overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(
                          decimal: true),
                  style: AppTextStyles.input,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'px',
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 8, vertical: 6),
                  ),
                  onChanged: (v) {
                    final d = double.tryParse(v);
                    if (d != null && d >= 20) {
                      setState(() => col.width = d);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _HeaderButton
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _HeaderButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.indigo600.withOpacity(0.35)
              : AppColors.indigo600.withOpacity(0.15),
          border: Border.all(
              color: AppColors.indigo600.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.indigo400),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.smallMedium
                  .copyWith(color: AppColors.indigo400),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatsBar
// ─────────────────────────────────────────────────────────────────────────────

class _StatsBar extends StatelessWidget {
  final List<EmployeeModel> employees;

  const _StatsBar({required this.employees});

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) return const SizedBox.shrink();

    final maleCount =
        employees.where((e) => e.gender.toUpperCase() != 'F').length;
    final femaleCount =
        employees.where((e) => e.gender.toUpperCase() == 'F').length;
    final salaries = employees
        .map((e) => e.grossSalary)
        .where((s) => s > 0)
        .toList();
    final payroll = salaries.fold(0.0, (a, b) => a + b);
    final avg = salaries.isEmpty ? 0.0 : payroll / salaries.length;
    final max = salaries.isEmpty
        ? 0.0
        : salaries.reduce((a, b) => a > b ? a : b);

    String fmt(double v) {
      if (v >= 100000)
        return '₹${(v / 100000).toStringAsFixed(1)}L';
      if (v >= 1000) return '₹${(v / 1000).toStringAsFixed(1)}K';
      return '₹${v.toStringAsFixed(0)}';
    }

    final items = [
      _StatItem(Icons.people_outline, 'Total',
          '${employees.length}', AppColors.indigo500,
          const Color(0xFF312E81)),
      _StatItem(Icons.male, 'Male', '$maleCount',
          const Color(0xFF3B82F6), const Color(0xFF1E3A5F)),
      _StatItem(Icons.female, 'Female', '$femaleCount',
          const Color(0xFFEC4899), const Color(0xFF500724)),
      _StatItem(Icons.payments_outlined, 'Avg Salary', fmt(avg),
          const Color(0xFFF59E0B), const Color(0xFF78350F)),
      _StatItem(Icons.trending_up_outlined, 'Highest', fmt(max),
          AppColors.emerald600, const Color(0xFF064E3B)),
      _StatItem(Icons.account_balance_wallet_outlined, 'Payroll',
          fmt(payroll), AppColors.indigo400,
          const Color(0xFF1E1B4B)),
    ];

    return Row(
      children: items.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
                right: index < items.length - 1 ? 8 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.slate900,
                borderRadius:
                    BorderRadius.circular(AppSpacing.radiusMd),
                border: Border.all(
                    color: AppColors.slate700, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: item.backgroundColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(item.icon,
                        size: 15, color: item.accentColor),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.value,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        Text(
                          item.label,
                          style: AppTextStyles.small.copyWith(
                            color: AppColors.slate400,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final Color backgroundColor;

  const _StatItem(this.icon, this.label, this.value,
      this.accentColor, this.backgroundColor);
}

// ─────────────────────────────────────────────────────────────────────────────
// _Filters
// ─────────────────────────────────────────────────────────────────────────────

class _Filters extends StatelessWidget {
  final String genderFilter;
  final String zoneFilter;
  final String codeFilter;
  final List<String> zones;
  final List<String> codes;
  final ValueChanged<String> onGenderChanged;
  final ValueChanged<String> onZoneChanged;
  final ValueChanged<String> onCodeChanged;
  final VoidCallback onReset;

  const _Filters({
    required this.genderFilter,
    required this.zoneFilter,
    required this.codeFilter,
    required this.zones,
    required this.codes,
    required this.onGenderChanged,
    required this.onZoneChanged,
    required this.onCodeChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final hasActive = genderFilter != 'All' ||
        zoneFilter != 'All' ||
        codeFilter != 'All';

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            'FILTER:',
            style: AppTextStyles.label
                .copyWith(color: AppColors.slate500, fontSize: 10),
          ),
          const SizedBox(width: 12),

          _FilterGroup(
            label: 'Gender',
            options: const ['All', 'M', 'F'],
            displayMap: const {
              'All': 'All',
              'M': 'Male',
              'F': 'Female'
            },
            selected: genderFilter,
            onChanged: onGenderChanged,
          ),

          if (codes.isNotEmpty) ...[
            const SizedBox(width: 12),
            const _VerticalDivider(),
            const SizedBox(width: 12),
            _FilterGroup(
              label: 'Dept',
              options: ['All', ...codes],
              selected: codeFilter,
              onChanged: onCodeChanged,
            ),
          ],

          if (zones.isNotEmpty) ...[
            const SizedBox(width: 12),
            const _VerticalDivider(),
            const SizedBox(width: 12),
            _FilterGroup(
              label: 'Zone',
              options: ['All', ...zones],
              selected: zoneFilter,
              onChanged: onZoneChanged,
            ),
          ],

          if (hasActive) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onReset,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.rose400.withOpacity(0.12),
                  border: Border.all(
                      color: AppColors.rose400.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close,
                        size: 11, color: AppColors.rose400),
                    const SizedBox(width: 4),
                    Text(
                      'Reset',
                      style: AppTextStyles.small.copyWith(
                        color: AppColors.rose400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerticalDivider extends StatelessWidget {
  const _VerticalDivider();

  @override
  Widget build(BuildContext context) => Container(
      width: 1, height: 20, color: AppColors.slate700);
}

class _FilterGroup extends StatelessWidget {
  final String label;
  final List<String> options;
  final String selected;
  final Map<String, String>? displayMap;
  final ValueChanged<String> onChanged;

  const _FilterGroup({
    required this.label,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.displayMap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label:',
          style: AppTextStyles.small
              .copyWith(color: AppColors.slate500, fontSize: 11),
        ),
        const SizedBox(width: 6),
        ...options.map((opt) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => onChanged(opt),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 130),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: selected == opt
                        ? AppColors.indigo600
                        : AppColors.slate800,
                    border: Border.all(
                      color: selected == opt
                          ? AppColors.indigo600
                          : AppColors.slate600,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    displayMap?[opt] ?? opt,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected == opt
                          ? Colors.white
                          : AppColors.slate400,
                    ),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EmptyState
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onAdd;
  final VoidCallback? onClearFilters;

  const _EmptyState({
    required this.hasSearch,
    required this.onAdd,
    this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasSearch ? Icons.search_off : Icons.people_outline,
            size: 48,
            color: AppColors.slate600,
          ),
          const SizedBox(height: 16),
          Text(
            hasSearch
                ? 'No employees match your filters.'
                : 'No employees yet.',
            style:
                AppTextStyles.body.copyWith(color: AppColors.slate500),
          ),
          const SizedBox(height: 16),
          if (!hasSearch)
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add First Employee'),
            )
          else if (onClearFilters != null)
            TextButton.icon(
              onPressed: onClearFilters,
              icon:
                  const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Clear Filters'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InsightsPanel (from bigger file)
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsPanel extends StatelessWidget {
  final List<EmployeeModel> employees;

  const _InsightsPanel({required this.employees});

  static Color _codeColor(String code) {
    switch (code) {
      case 'F&B':
        return AppColors.indigo500;
      case 'I&L':
        return AppColors.emerald600;
      case 'P&S':
        return const Color(0xFFF59E0B);
      case 'A&P':
        return const Color(0xFFEC4899);
      default:
        return AppColors.slate500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...employees]
      ..sort((a, b) => b.grossSalary.compareTo(a.grossSalary));
    final top3 = sorted.take(3).toList();

    final codeMap = <String, int>{};
    for (final e in employees) {
      final c =
          e.code.trim().isEmpty ? 'Other' : e.code.trim();
      codeMap[c] = (codeMap[c] ?? 0) + 1;
    }
    final sortedCodes = codeMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final zoneMap = <String, int>{};
    for (final e in employees) {
      final z =
          e.zone.trim().isEmpty ? 'Unknown' : e.zone.trim();
      zoneMap[z] = (zoneMap[z] ?? 0) + 1;
    }

    const rankColors = [
      Color(0xFFFFD700),
      Color(0xFFC0C0C0),
      Color(0xFFCD7F32),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius:
            BorderRadius.circular(AppSpacing.radiusMd),
        border:
            Border.all(color: AppColors.slate700, width: 0.5),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_outlined,
                  size: 14, color: AppColors.indigo400),
              SizedBox(width: 7),
              Text('Insights',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),

          const SizedBox(height: 16),
          _SectionLabel('Top Earners'),
          const SizedBox(height: 8),
          ...top3.asMap().entries.map((entry) {
            final rankColor = rankColors[entry.key];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: rankColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${entry.key + 1}',
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: rankColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.value.name,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small.copyWith(
                          color: AppColors.slate300,
                          fontSize: 11),
                    ),
                  ),
                  Text(
                    '₹${entry.value.grossSalary.toStringAsFixed(0)}',
                    style: AppTextStyles.small.copyWith(
                      color: AppColors.emerald600,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),
          const Divider(color: AppColors.slate800, height: 1),
          const SizedBox(height: 16),

          _SectionLabel('Dept Distribution'),
          const SizedBox(height: 10),
          ...sortedCodes.take(5).map((entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.key,
                          style: AppTextStyles.small.copyWith(
                              color: AppColors.slate300,
                              fontSize: 11),
                        ),
                        const Spacer(),
                        Text(
                          '${entry.value}',
                          style: AppTextStyles.small.copyWith(
                            color: AppColors.slate400,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius:
                          BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: employees.isEmpty
                            ? 0
                            : entry.value /
                                employees.length,
                        minHeight: 4,
                        backgroundColor:
                            AppColors.slate800,
                        valueColor: AlwaysStoppedAnimation(
                            _codeColor(entry.key)),
                      ),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 16),
          const Divider(color: AppColors.slate800, height: 1),
          const SizedBox(height: 16),

          _SectionLabel('Zone Spread'),
          const SizedBox(height: 10),
          if (zoneMap.isEmpty)
            Text('No zone data',
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate500))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: zoneMap.entries
                  .map((e) => Container(
                        padding:
                            const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.slate800,
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.slate700),
                        ),
                        child: Text(
                          '${e.key} · ${e.value}',
                          style: AppTextStyles.small.copyWith(
                              color: AppColors.slate400,
                              fontSize: 10),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppTextStyles.label
          .copyWith(color: AppColors.slate500, fontSize: 10),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FocusGlow (from smaller file)
// ─────────────────────────────────────────────────────────────────────────────

class _FocusGlow extends StatefulWidget {
  final Widget child;
  final FocusNode focusNode;
  final Color glowColor;
  final BorderRadius? borderRadius;

  const _FocusGlow({
    required this.child,
    required this.focusNode,
    required this.glowColor,
    this.borderRadius,
  });

  @override
  State<_FocusGlow> createState() => _FocusGlowState();
}

class _FocusGlowState extends State<_FocusGlow> {
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_handleFocusChange);
    _isFocused = widget.focusNode.hasFocus;
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {
        _isFocused = widget.focusNode.hasFocus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius:
            widget.borderRadius ?? BorderRadius.circular(8),
        boxShadow: _isFocused
            ? [
                BoxShadow(
                  color: widget.glowColor,
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom Intents for Major Focus Navigation (from smaller file)
// ─────────────────────────────────────────────────────────────────────────────

class _PreviousMajorFocusIntent extends Intent {
  const _PreviousMajorFocusIntent();
}

class _NextMajorFocusIntent extends Intent {
  const _NextMajorFocusIntent();
}

// ─────────────────────────────────────────────────────────────────────────────
// _HoverableTableRow (from smaller file)
// ─────────────────────────────────────────────────────────────────────────────

class _HoverableTableRow extends StatefulWidget {
  final List<Widget> cells;
  final VoidCallback onDoubleTap;
  final VoidCallback onTap;
  final bool isFocused;

  const _HoverableTableRow({
    super.key,
    required this.cells,
    required this.onDoubleTap,
    required this.onTap,
    this.isFocused = false,
  });

  TableRow buildRow() {
    return TableRow(
      children: cells.map((cell) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onDoubleTap,
          onTap: onTap,
          child: cell,
        );
      }).toList(),
    );
  }

  @override
  State<_HoverableTableRow> createState() =>
      _HoverableTableRowState();
}

class _HoverableTableRowState
    extends State<_HoverableTableRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onDoubleTap,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: widget.isFocused
                ? AppColors.indigo50.withOpacity(0.4)
                : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: widget.isFocused
                    ? AppColors.indigo400
                    : (_hovered
                        ? AppColors.indigo400
                        : AppColors.slate100),
                width:
                    (widget.isFocused || _hovered) ? 2 : 1,
              ),
            ),
            boxShadow:
                (widget.isFocused || _hovered)
                    ? [
                        BoxShadow(
                          color: AppColors.indigo600
                              .withOpacity(0.12),
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 0),
                        ),
                      ]
                    : null,
          ),
          child: DefaultTextStyle(
            style: AppTextStyles.body.copyWith(
              color:
                  (widget.isFocused || _hovered)
                      ? AppColors.indigo700
                      : null,
            ),
            child: Row(
              children: widget.cells,
            ),
          ),
        ),
      ),
    );
  }
}
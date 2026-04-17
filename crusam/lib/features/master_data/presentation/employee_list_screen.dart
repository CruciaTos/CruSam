import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../data/models/employee_model.dart';
import '../services/employee_excel_import_service.dart';
import '../notifiers/employee_notifier.dart';
import 'employee_form_screen.dart';

class _ColDef {
  final String label;
  double width;
  _ColDef(this.label, this.width);
}

class EmployeeListScreen extends StatefulWidget {
  const EmployeeListScreen({super.key});
  @override
  State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
  final _notifier = EmployeeNotifier();
  final _search = TextEditingController();
  final _verticalScrollController = ScrollController();
  final _horizontalScrollController = ScrollController();
  bool _showHorizontalScrollbar = false;
  bool _isImporting = false;
  bool _showColPanel = false;

  // ─────────────────────────── Focus Nodes ─────────────────────────────────
  final FocusNode _searchFocusNode = FocusNode(debugLabel: 'Search');
  final FocusNode _addButtonFocusNode = FocusNode(debugLabel: 'AddButton');
  final FocusNode _colButtonFocusNode = FocusNode(debugLabel: 'ColButton');
  final FocusNode _tableFocusNode = FocusNode(debugLabel: 'Table');
  late final List<FocusNode> _majorFocusNodes;

  int? _focusedRowIndex;

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
    _notifier.load();
    _marginHCtrl = TextEditingController(text: _tableMarginH.toStringAsFixed(0));
    _marginVCtrl = TextEditingController(text: _tableMarginV.toStringAsFixed(0));
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

  @override
  void dispose() {
    _notifier.dispose();
    _search.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _marginHCtrl.dispose();
    _marginVCtrl.dispose();
    for (final c in _colCtrls) c.dispose();
    _searchFocusNode.dispose();
    _addButtonFocusNode.dispose();
    _colButtonFocusNode.dispose();
    _tableFocusNode.dispose();
    super.dispose();
  }

  void _toggleHorizontalScrollbar(bool visible) {
    if (_showHorizontalScrollbar == visible || !mounted) return;
    setState(() => _showHorizontalScrollbar = visible);
  }

  Future<void> _goToForm([EmployeeModel? emp]) async {
    final result = await showDialog(
      context: context,
      barrierColor: Colors.black45,
      barrierDismissible: false,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: EmployeeFormScreen(employee: emp?.toMap()),
      ),
    );
    await _notifier.load();
    if (_search.text.isNotEmpty) {
      _notifier.search(_search.text);
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
      final inserted = await _notifier.importEmployees(result.validEmployees);
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

  // ─────────────────────── Major Widget Focus Navigation ────────────────────
  bool _isEditableTextFocused() {
    final current = FocusManager.instance.primaryFocus;
    return current?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
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
    int prevIndex = (currentIndex - 1) % _majorFocusNodes.length;
    if (prevIndex < 0) prevIndex = _majorFocusNodes.length - 1;
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

  // ─────────────────────────── Focus Management ──────────────────────────────
  void _clearRowFocus() {
    if (_focusedRowIndex != null) {
      setState(() => _focusedRowIndex = null);
    }
  }

  void _ensureRowVisible(int index) {
    const rowHeight = 42.0;
    final scrollOffset = index * rowHeight;
    final viewportHeight = _verticalScrollController.position.viewportDimension;
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

  /// Root-level key event handler to block arrow keys (without Shift) from
  /// triggering default focus traversal.
  KeyEventResult _handleRootKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final logicalKey = event.logicalKey;
    final isArrow = logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight;

    if (isArrow && !HardwareKeyboard.instance.isShiftPressed) {
      // Block arrow keys from moving focus when Shift is not pressed.
      // This allows arrow keys to work only within focused widgets (e.g., text fields, table rows).
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  KeyEventResult _handleTableKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    // If Shift is pressed, let global shortcuts handle major focus movement
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }

    final filtered = _notifier.filtered;
    if (filtered.isEmpty) return KeyEventResult.ignored;

    final currentIndex = _focusedRowIndex;
    final logicalKey = event.logicalKey;

    // Arrow navigation within table (only without Shift)
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

    // Enter to edit
    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (currentIndex != null && currentIndex < filtered.length) {
        _goToForm(filtered[currentIndex]);
        return KeyEventResult.handled;
      }
    }

    // Delete key
    if (logicalKey == LogicalKeyboardKey.delete) {
      if (currentIndex != null && currentIndex < filtered.length) {
        _confirmAndDelete(filtered[currentIndex]);
        return KeyEventResult.handled;
      }
    }

    // Escape to clear focus and go to search
    if (logicalKey == LogicalKeyboardKey.escape) {
      _clearRowFocus();
      _searchFocusNode.requestFocus();
      return KeyEventResult.handled;
    }

    // Ctrl+F to focus search
    if (HardwareKeyboard.instance.isControlPressed &&
        logicalKey == LogicalKeyboardKey.keyF) {
      _searchFocusNode.requestFocus();
      _search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _search.text.length,
      );
      return KeyEventResult.handled;
    }

    // Ctrl+N for new employee
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
        final newLength = _notifier.filtered.length;
        if (_focusedRowIndex! >= newLength) {
          _focusedRowIndex = newLength > 0 ? newLength - 1 : null;
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${employee.name} deleted')),
    );
  }

  // ── Column width panel ────────────────────────────────────────────────────
  Widget _colPanel() => Container(
        width: 240,
        color: AppColors.slate50,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.slate200))),
              child: Row(
                children: [
                  Text('Column Widths', style: AppTextStyles.label),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => setState(() => _showColPanel = false),
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
                          fontWeight: FontWeight.w600, color: AppColors.slate700)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                        child: _marginField('H-Margin', _marginHCtrl,
                            (v) => setState(() => _tableMarginH = v))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _marginField('V-Margin', _marginVCtrl,
                            (v) => setState(() => _tableMarginV = v))),
                  ]),
                  const Divider(height: 20),
                  Text('Column Widths (px)',
                      style: AppTextStyles.small.copyWith(
                          fontWeight: FontWeight.w600, color: AppColors.slate700)),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _cols.length; i++)
                    _colWidthRow(_cols[i], _colCtrls[i]),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _marginField(String label, TextEditingController ctrl,
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.input,
              decoration: const InputDecoration(
                  isDense: true,
                  suffixText: 'px',
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
              onChanged: (v) {
                final d = double.tryParse(v);
                if (d != null && d >= 0) onChanged(d);
              },
            ),
          ),
        ],
      );

  Widget _colWidthRow(_ColDef col, TextEditingController ctrl) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(col.label,
                  style: AppTextStyles.small, overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              child: SizedBox(
                height: 32,
                child: TextField(
                  controller: ctrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: AppTextStyles.input,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'px',
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: (v) {
                    final d = double.tryParse(v);
                    if (d != null && d >= 20) setState(() => col.width = d);
                  },
                ),
              ),
            ),
          ],
        ),
      );

  // ─────────────────────────── Main Build ───────────────────────────────────
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
      _PreviousMajorFocusIntent: CallbackAction<_PreviousMajorFocusIntent>(
        onInvoke: (_) => _moveFocusToPreviousMajor(),
      ),
      _NextMajorFocusIntent: CallbackAction<_NextMajorFocusIntent>(
        onInvoke: (_) => _moveFocusToNextMajor(),
      ),
    };

    return ListenableBuilder(
      listenable: _notifier,
      builder: (ctx, _) => Focus(
        // Root-level focus to intercept and block arrow-key traversal
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1400),
                    child: Column(
                      children: [
                        // ── Toolbar ─────────────────────────────────────────
                        LayoutBuilder(builder: (context, constraints) {
                          final searchField = _FocusGlow(
                            focusNode: _searchFocusNode,
                            glowColor: AppColors.indigo400.withOpacity(0.4),
                            child: SizedBox(
                              height: 40,
                              child: Focus(
                                focusNode: _searchFocusNode,
                                child: TextField(
                                  controller: _search,
                                  onChanged: (value) {
                                    _notifier.search(value);
                                    _clearRowFocus();
                                  },
                                  style: AppTextStyles.input,
                                  decoration: InputDecoration(
                                    hintText: 'Search by name or PF No... (Ctrl+F)',
                                    prefixIcon: const Icon(Icons.search, size: 18),
                                    suffixIcon: _search.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, size: 16),
                                            onPressed: () {
                                              _search.clear();
                                              _notifier.search('');
                                              _clearRowFocus();
                                            },
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          );

                          final addBtn = FocusTraversalOrder(
                            order: const NumericFocusOrder(1),
                            child: _FocusGlow(
                              focusNode: _addButtonFocusNode,
                              glowColor: AppColors.indigo400.withOpacity(0.4),
                              child: Focus(
                                focusNode: _addButtonFocusNode,
                                child: ElevatedButton.icon(
                                  onPressed: () => _goToForm(),
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add Employee (Ctrl+N)'),
                                ),
                              ),
                            ),
                          );

                          final colBtn = FocusTraversalOrder(
                            order: const NumericFocusOrder(2),
                            child: _FocusGlow(
                              focusNode: _colButtonFocusNode,
                              glowColor: AppColors.indigo400.withOpacity(0.4),
                              child: Focus(
                                focusNode: _colButtonFocusNode,
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      setState(() => _showColPanel = !_showColPanel),
                                  icon: Icon(Icons.tune,
                                      size: 18,
                                      color: _showColPanel
                                          ? AppColors.indigo600
                                          : null),
                                  label: const Text('Columns'),
                                ),
                              ),
                            ),
                          );

                          if (constraints.maxWidth < 920) {
                            return Column(children: [
                              searchField,
                              const SizedBox(height: AppSpacing.md),
                              Wrap(
                                  spacing: AppSpacing.md,
                                  runSpacing: AppSpacing.md,
                                  children: [addBtn, colBtn]),
                            ]);
                          }
                          return Row(children: [
                            Expanded(child: searchField),
                            const SizedBox(width: AppSpacing.md),
                            addBtn,
                            const SizedBox(width: AppSpacing.md),
                            colBtn,
                          ]);
                        }),
                        const SizedBox(height: AppSpacing.lg),
                        // ── Body ───────────────────────────────────────────
                        if (_notifier.isLoading)
                          const Expanded(
                              child: Center(child: CircularProgressIndicator()))
                        else if (_notifier.filtered.isEmpty)
                          Expanded(
                            child: Center(
                              child: Text(
                                _notifier.employees.isEmpty
                                    ? 'No employees yet. Tap Add to create one.'
                                    : 'No results found.',
                                style: AppTextStyles.small,
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: FocusTraversalOrder(
                                    order: const NumericFocusOrder(3),
                                    child: _FocusGlow(
                                      focusNode: _tableFocusNode,
                                      glowColor: AppColors.indigo400.withOpacity(0.4),
                                      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                                      child: _tableCard(),
                                    ),
                                  ),
                                ),
                                if (_showColPanel) ...[
                                  const SizedBox(width: 8),
                                  _colPanel(),
                                ],
                              ],
                            ),
                          ),
                        // Keyboard hint
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
          ),
        ),
      ),
    );
  }

  Widget _tableCard() => AppCard(
        padding:
            EdgeInsets.symmetric(horizontal: _tableMarginH, vertical: _tableMarginV),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.slate400),
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      horizontal: _tableMarginH, vertical: AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.slate50,
                    border: Border(bottom: BorderSide(color: AppColors.slate200)),
                  ),
                  child: Row(
                    children: [
                      Text('Double-tap or press Enter to edit • Delete to remove',
                          style: AppTextStyles.small),
                      const Spacer(),
                      if (_focusedRowIndex != null)
                        Text(
                          'Row ${_focusedRowIndex! + 1} of ${_notifier.filtered.length}',
                          style: AppTextStyles.small
                              .copyWith(fontWeight: FontWeight.w600),
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
                    child: MouseRegion(
                      onEnter: (_) => _toggleHorizontalScrollbar(true),
                      onExit: (_) => _toggleHorizontalScrollbar(false),
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: _showHorizontalScrollbar,
                        trackVisibility: false,
                        thickness: 8,
                        radius: const Radius.circular(8),
                        notificationPredicate: (n) =>
                            n.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          child: Scrollbar(
                            controller: _verticalScrollController,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalScrollController,
                              child: _buildTable(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _buildTable() {
    final headerCells = _cols.map((c) => _th(c.label, c.width)).toList();

    final filtered = _notifier.filtered;
    final dataRows = <TableRow>[];

    for (int idx = 0; idx < filtered.length; idx++) {
      final e = filtered[idx];
      final isFemale = e.gender.toUpperCase() == 'F';
      final isFocused = _focusedRowIndex == idx;

      final row = _HoverableTableRow(
        key: ValueKey(e.id),
        cells: [
          _td((idx + 1).toString(), _cols[0].width, isFocused: isFocused),
          _tdGender(isFemale, _cols[1].width, isFocused: isFocused),
          _td(e.name, _cols[2].width, bold: true, isFocused: isFocused),
          _td(e.pfNo, _cols[3].width, isFocused: isFocused),
          _td(e.uanNo, _cols[4].width, isFocused: isFocused),
          _td(e.code, _cols[5].width, isFocused: isFocused),
          _tdMono(e.ifscCode, _cols[6].width, isFocused: isFocused),
          _tdMono(e.accountNumber, _cols[7].width, isFocused: isFocused),
          _td(e.bankDetails, _cols[8].width, isFocused: isFocused),
          _td(e.branch, _cols[9].width, isFocused: isFocused),
          _td(e.zone, _cols[10].width, isFocused: isFocused),
          _tdNum(e.basicCharges, _cols[11].width, isFocused: isFocused),
          _tdNum(e.otherCharges, _cols[12].width, isFocused: isFocused),
          _tdNum(e.grossSalary, _cols[13].width, isFocused: isFocused),
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
          decoration: const BoxDecoration(color: AppColors.slate50),
          children: headerCells,
        ),
        ...dataRows,
      ],
    );
  }

  static Widget _th(String label, double width) => Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.slate300))),
        child: Text(label, style: AppTextStyles.label),
      );

  static Widget _td(String value, double width,
          {bool bold = false, bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            value,
            style: AppTextStyles.body.copyWith(
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
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
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(99),
                border: isFocused
                    ? Border.all(color: AppColors.indigo400, width: 1.5)
                    : null,
              ),
              child: Text(
                isFemale ? 'F' : 'M',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isFemale ? const Color(0xFFBE185D) : AppColors.blue600,
                ),
              ),
            ),
          ),
        ),
      );

  static Widget _tdMono(String value, double width, {bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            value,
            style: AppTextStyles.monoSm.copyWith(
              color: isFocused ? AppColors.indigo700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );

  static Widget _tdNum(double value, double width, {bool isFocused = false}) =>
      SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(
            value == 0 ? '—' : '₹${value.toStringAsFixed(2)}',
            textAlign: TextAlign.left,
            style: AppTextStyles.body.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isFocused ? AppColors.indigo700 : null,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
}

// ──────────────────── Focus Glow Wrapper Widget ────────────────────────────
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
        borderRadius: widget.borderRadius ?? BorderRadius.circular(8),
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

// ──────────────────── Custom Intents for Major Focus Navigation ──────────────
class _PreviousMajorFocusIntent extends Intent {
  const _PreviousMajorFocusIntent();
}

class _NextMajorFocusIntent extends Intent {
  const _NextMajorFocusIntent();
}

// ──────────────────── Custom hoverable & focusable row ─────────────────────
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
  State<_HoverableTableRow> createState() => _HoverableTableRowState();
}

class _HoverableTableRowState extends State<_HoverableTableRow> {
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
                    : (_hovered ? AppColors.indigo400 : AppColors.slate100),
                width: (widget.isFocused || _hovered) ? 2 : 1,
              ),
            ),
            boxShadow: (widget.isFocused || _hovered)
                ? [
                    BoxShadow(
                      color: AppColors.indigo600.withOpacity(0.12),
                      blurRadius: 10,
                      spreadRadius: 1,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : null,
          ),
          child: DefaultTextStyle(
            style: AppTextStyles.body.copyWith(
              color: (widget.isFocused || _hovered) ? AppColors.indigo700 : null,
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
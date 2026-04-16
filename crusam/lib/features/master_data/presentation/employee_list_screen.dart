import 'package:flutter/material.dart';
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
  final _search   = TextEditingController();
  final _verticalScrollController    = ScrollController();
  final _horizontalScrollController  = ScrollController();
  bool _showHorizontalScrollbar = false;
  bool _isImporting = false;
  bool _showColPanel = false;

  final _cols = [
    _ColDef('Sr.',          48),
    _ColDef('Gender',       72),
    _ColDef('Name',        180),
    _ColDef('PF No.',      140),
    _ColDef('UAN No.',     130),
    _ColDef('Code',         64),
    _ColDef('IFSC',        110),
    _ColDef('Account No.', 150),
    _ColDef('Bank',        160),
    _ColDef('Branch',      160),
    _ColDef('Zone',         80),
    _ColDef('Basic ₹',      90),
    _ColDef('Other ₹',      90),
    _ColDef('Gross ₹',     110),
  ];

  double _tableMarginH = 12;
  double _tableMarginV = 8;

  // ── Persistent controllers (fix: no longer created in build) ─────────────
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
    // Always reload so both master-data and salary screens see fresh data
    await _notifier.load();
    if (_search.text.isNotEmpty) {
      _notifier.search(_search.text);
    }
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
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Import')),
          ],
        ),
      );
      if (confirm != true) return;
      final inserted = await _notifier.importEmployees(result.validEmployees);
      if (!mounted) return;
      final skipped = (result.validEmployees.length - inserted) + result.duplicateCount + result.invalidCount;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imported: $inserted, Skipped: $skipped')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Import failed')));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ── Column width panel ───────────────────────────────────────────────────
  Widget _colPanel() => Container(
    width: 240,
    color: AppColors.slate50,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slate200))),
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
              Text('Table Margins', style: AppTextStyles.small.copyWith(fontWeight: FontWeight.w600, color: AppColors.slate700)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: _marginField('H-Margin', _marginHCtrl, (v) => setState(() => _tableMarginH = v))),
                const SizedBox(width: 8),
                Expanded(child: _marginField('V-Margin', _marginVCtrl, (v) => setState(() => _tableMarginV = v))),
              ]),
              const Divider(height: 20),
              Text('Column Widths (px)', style: AppTextStyles.small.copyWith(fontWeight: FontWeight.w600, color: AppColors.slate700)),
              const SizedBox(height: 8),
              for (int i = 0; i < _cols.length; i++) _colWidthRow(_cols[i], _colCtrls[i]),
            ],
          ),
        ),
      ],
    ),
  );

  // Signature changed: accepts controller instead of creating one
  Widget _marginField(String label, TextEditingController ctrl, void Function(double) onChanged) => Column(
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
          decoration: const InputDecoration(isDense: true, suffixText: 'px', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
          onChanged: (v) { final d = double.tryParse(v); if (d != null && d >= 0) onChanged(d); },
        ),
      ),
    ],
  );

  // Signature changed: accepts controller instead of creating one
  Widget _colWidthRow(_ColDef col, TextEditingController ctrl) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(col.label, style: AppTextStyles.small, overflow: TextOverflow.ellipsis),
        ),
        Expanded(
          child: SizedBox(
            height: 32,
            child: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: AppTextStyles.input,
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'px',
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

  // ── Main build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _notifier,
    builder: (ctx, _) => Padding(
      padding: const EdgeInsets.all(AppSpacing.pagePadding),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Column(
            children: [
              // ── Toolbar ────────────────────────────────────────────────
              LayoutBuilder(builder: (context, constraints) {
                final searchField = SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onChanged: _notifier.search,
                    style: AppTextStyles.input,
                    decoration: InputDecoration(
                      hintText: 'Search by name or PF No...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _search.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: () { _search.clear(); _notifier.search(''); },
                            )
                          : null,
                    ),
                  ),
                );


                final addBtn = ElevatedButton.icon(
                  onPressed: () => _goToForm(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Employee'),
                );

                final colBtn = OutlinedButton.icon(
                  onPressed: () => setState(() => _showColPanel = !_showColPanel),
                  icon: Icon(Icons.tune, size: 18,
                      color: _showColPanel ? AppColors.indigo600 : null),
                  label: const Text('Columns'),
                );

                if (constraints.maxWidth < 920) {
                  return Column(children: [
                    searchField,
                    const SizedBox(height: AppSpacing.md),
                    Wrap(spacing: AppSpacing.md, runSpacing: AppSpacing.md, children: [addBtn, colBtn]),
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
              // ── Body ───────────────────────────────────────────────────
              if (_notifier.isLoading)
                const Expanded(child: Center(child: CircularProgressIndicator()))
              else if (_notifier.filtered.isEmpty)
                Expanded(
                  child: Center(
                    child: Text(
                      _notifier.employees.isEmpty ? 'No employees yet. Tap Add to create one.' : 'No results found.',
                      style: AppTextStyles.small,
                    ),
                  ),
                )
              else
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _tableCard()),
                      if (_showColPanel) ...[
                        const SizedBox(width: 8),
                        _colPanel(),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _tableCard() => AppCard(
    padding: EdgeInsets.symmetric(horizontal: _tableMarginH, vertical: _tableMarginV),
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
              padding: EdgeInsets.symmetric(horizontal: _tableMarginH, vertical: AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.slate50,
                border: Border(bottom: BorderSide(color: AppColors.slate200)),
              ),
              child: Text('Double-tap a row to edit or delete', style: AppTextStyles.small),
            ),
            Expanded(
              child: MouseRegion(
                onEnter: (_) => _toggleHorizontalScrollbar(true),
                onExit: (_) => _toggleHorizontalScrollbar(false),
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: _showHorizontalScrollbar,
                  trackVisibility: false,
                  thickness: 8,
                  radius: const Radius.circular(8),
                  notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
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
          ],
        ),
      ),
    ),
  );

  Widget _buildTable() {
    final headerCells = _cols.map((c) => _th(c.label, c.width)).toList();

    final dataRows = _notifier.filtered.asMap().entries.map((entry) {
      final idx = entry.key;
      final e = entry.value;
      final isFemale = e.gender.toUpperCase() == 'F';
      
      return _HoverableTableRow(
        key: ValueKey(e.id),
        cells: [
          _td((idx + 1).toString(), _cols[0].width),
          _tdGender(isFemale, _cols[1].width),
          _td(e.name, _cols[2].width, bold: true),
          _td(e.pfNo, _cols[3].width),
          _td(e.uanNo, _cols[4].width),
          _td(e.code, _cols[5].width),
          _tdMono(e.ifscCode, _cols[6].width),
          _tdMono(e.accountNumber, _cols[7].width),
          _td(e.bankDetails, _cols[8].width),
          _td(e.branch, _cols[9].width),
          _td(e.zone, _cols[10].width),
          _tdNum(e.basicCharges, _cols[11].width),
          _tdNum(e.otherCharges, _cols[12].width),
          _tdNum(e.grossSalary, _cols[13].width),
        ],
        onDoubleTap: () => _goToForm(e),
      );
    }).toList();

    return Table(
      columnWidths: {
        for (int i = 0; i < _cols.length; i++) i: FixedColumnWidth(_cols[i].width)
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: AppColors.slate50),
          children: headerCells,
        ),
        ...dataRows.map((row) => row.buildRow()),
      ],
    );
  }

  static Widget _th(String label, double width) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slate300))),
    child: Text(label, style: AppTextStyles.label),
  );

  static Widget _td(String value, double width, {bool bold = false}) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        value,
        style: AppTextStyles.body.copyWith(fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );

  static Widget _tdGender(bool isFemale, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isFemale ? const Color(0xFFFCE7F3) : const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(99),
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

  static Widget _tdMono(String value, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(value, style: AppTextStyles.monoSm, overflow: TextOverflow.ellipsis),
    ),
  );

  static Widget _tdNum(double value, double width) => SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        value == 0 ? '—' : '₹${value.toStringAsFixed(2)}',
        textAlign: TextAlign.left,
        style: AppTextStyles.body.copyWith(fontSize: 12, fontWeight: FontWeight.w600),
        overflow: TextOverflow.ellipsis,
      ),
    ),
  );
}

// ── Custom hoverable table row widget ─────────────────────────────────────
class _HoverableTableRow extends StatefulWidget {
  final List<Widget> cells;
  final VoidCallback onDoubleTap;
  
  const _HoverableTableRow({
    super.key,
    required this.cells,
    required this.onDoubleTap,
  });

  TableRow buildRow() {
    return TableRow(
      children: cells.map((cell) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onDoubleTap,
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: _hovered ? AppColors.indigo400 : AppColors.slate100,
                width: _hovered ? 2 : 1,
              ),
            ),
            boxShadow: _hovered
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
              color: _hovered ? AppColors.indigo700 : null,
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
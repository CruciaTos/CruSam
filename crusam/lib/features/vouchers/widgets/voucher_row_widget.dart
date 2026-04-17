import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/employee_model.dart';
import '../../../../data/models/voucher_row_model.dart';
import 'employee_search_dropdown.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ADJUSTABLE SIZES – change these values to manually set height and widths
// ─────────────────────────────────────────────────────────────────────────────

/// Default row height reference (used for header and optional sizing).
/// Individual fields can override this via their `height` parameter.
const double kDefaultRowHeight = 42.0;

/// Column widths – modify these to change the width of each column
class VoucherTableColumns {
  static double index = 48.0;       // '#'
  static double employee = 220.0;   // Employee dropdown
  static double amount = 130.0;     // Amount field
  static double fromDate = 120.0;   // From date
  static double toDate = 120.0;     // To date
  static double bankDetails = 200.0; // Auto-filled info
  static double actions = 56.0;     // Delete button
}

// ─────────────────────────────────────────────────────────────────────────────

/// Main table widget that handles auto‑scroll on row addition.
class VoucherTable extends StatefulWidget {
  final List<VoucherRowModel> rows;
  final List<EmployeeModel> employees;
  final ValueChanged<List<VoucherRowModel>> onRowsChanged;
  final VoidCallback? onAddRow;

  const VoucherTable({
    super.key,
    required this.rows,
    required this.employees,
    required this.onRowsChanged,
    this.onAddRow,
  });

  @override
  State<VoucherTable> createState() => _VoucherTableState();
}

class _VoucherTableState extends State<VoucherTable> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _tableKey = GlobalKey();

  void _addRow() {
    final newId = 'new_${DateTime.now().millisecondsSinceEpoch}';
    final newRows = List<VoucherRowModel>.from(widget.rows)
      ..add(VoucherRowModel(id: newId));
    widget.onRowsChanged(newRows);
    widget.onAddRow?.call();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNewRow();
    });
  }

  void _scrollToNewRow() {
    if (!_scrollController.hasClients) return;
    final tableContext = _tableKey.currentContext;
    if (tableContext == null) return;

    final RenderBox tableBox = tableContext.findRenderObject() as RenderBox;
    final RenderBox? scrollBox =
        _scrollController.position.context.storageContext.findRenderObject()
            as RenderBox?;
    if (scrollBox == null) return;

    final double rowHeight = kDefaultRowHeight + 12; // approximate
    final double lastRowTop = tableBox.size.height - rowHeight;
    final Offset rowGlobalPos = tableBox.localToGlobal(Offset(0, lastRowTop));
    final Offset scrollGlobalPos = scrollBox.localToGlobal(Offset.zero);

    final double targetScrollOffset = _scrollController.offset +
        (rowGlobalPos.dy - scrollGlobalPos.dy) -
        (scrollBox.size.height / 2) +
        (rowHeight / 2);

    _scrollController.animateTo(
      targetScrollOffset.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void _removeRow(int index) {
    final newRows = List<VoucherRowModel>.from(widget.rows)..removeAt(index);
    widget.onRowsChanged(newRows);
  }

  void _updateEmployee(int index, String empId) {
    final newRows = List<VoucherRowModel>.from(widget.rows);
    final emp = widget.employees.firstWhere(
      (e) => e.id?.toString() == empId,
      orElse: () => EmployeeModel(name: ''),
    );
    newRows[index] = newRows[index].copyWith(
      employeeId: empId,
      employeeName: emp.name,
      ifscCode: emp.ifscCode,
      accountNumber: emp.accountNumber,
      bankDetails: emp.bankDetails,
      branch: emp.branch,
    );
    widget.onRowsChanged(newRows);
  }

  void _updateAmount(int index, double amount) {
    final newRows = List<VoucherRowModel>.from(widget.rows);
    newRows[index] = newRows[index].copyWith(amount: amount);
    widget.onRowsChanged(newRows);
  }

  void _updateFromDate(int index, String date) {
    final newRows = List<VoucherRowModel>.from(widget.rows);
    newRows[index] = newRows[index].copyWith(fromDate: date);
    widget.onRowsChanged(newRows);
  }

  void _updateToDate(int index, String date) {
    final newRows = List<VoucherRowModel>.from(widget.rows);
    newRows[index] = newRows[index].copyWith(toDate: date);
    widget.onRowsChanged(newRows);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Table(
                  key: _tableKey,
                  columnWidths: {
                    0: FixedColumnWidth(VoucherTableColumns.index),
                    1: FixedColumnWidth(VoucherTableColumns.employee),
                    2: FixedColumnWidth(VoucherTableColumns.amount),
                    3: FixedColumnWidth(VoucherTableColumns.fromDate),
                    4: FixedColumnWidth(VoucherTableColumns.toDate),
                    5: FixedColumnWidth(VoucherTableColumns.bankDetails),
                    6: FixedColumnWidth(VoucherTableColumns.actions),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header row
                    TableRow(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.indigo50,
                            AppColors.indigo400.withOpacity(0.5),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: const Border(
                          bottom: BorderSide(
                            color: AppColors.indigo600,
                            width: 1.5,
                          ),
                        ),
                      ),
                      children: [
                        _headerCell('#', centered: true),
                        _headerCell('Employee'),
                        _headerCell('Amount', centered: true),
                        _headerCell('From', centered: true),
                        _headerCell('To', centered: true),
                        _headerCell('Bank Details'),
                        _headerCell('', centered: true),
                      ],
                    ),
                    // Data rows
                    ...widget.rows.asMap().entries.map((entry) {
                      final index = entry.key;
                      final row = entry.value;
                      return buildVoucherRow(
                        index: index,
                        row: row,
                        employees: widget.employees,
                        onSelectEmployee: (empId) =>
                            _updateEmployee(index, empId),
                        onAmountChanged: (amt) => _updateAmount(index, amt),
                        onFromDateChanged: (date) =>
                            _updateFromDate(index, date),
                        onToDateChanged: (date) => _updateToDate(index, date),
                        onRemove: () => _removeRow(index),
                        highlight: false,
                        // Optional: pass custom heights here if needed
                        // empDropdownHeight: 50,
                        // amountFieldHeight: 45,
                        // dateFieldHeight: 40,
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ElevatedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text(
              'Add New Row',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.indigo600,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: AppColors.indigo600.withOpacity(0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _headerCell(String text, {bool centered = false}) => Container(
        height: kDefaultRowHeight + 6, // slightly taller header
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        child: Text(
          text,
          style: AppTextStyles.small.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.indigo600,
            letterSpacing: 0.3,
          ),
        ),
      );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────

TableRow buildVoucherRow({
  required int index,
  required VoucherRowModel row,
  required List<EmployeeModel> employees,
  required void Function(String empId) onSelectEmployee,
  required void Function(double) onAmountChanged,
  required void Function(String) onFromDateChanged,
  required void Function(String) onToDateChanged,
  required VoidCallback onRemove,
  bool highlight = false,
  double? empDropdownHeight,
  double? amountFieldHeight,
  double? dateFieldHeight,
}) {
  final isEven = index.isEven;
  final bg = highlight
      ? const Color(0xFFFFF8E1)
      : isEven
          ? Colors.white
          : AppColors.slate50;

  return TableRow(
    decoration: BoxDecoration(
      color: bg,
      border: Border(
        bottom: BorderSide(
          color: AppColors.slate200.withOpacity(0.5),
          width: 0.8,
        ),
      ),
    ),
    children: [
      _cell(
        Text(
          '${index + 1}',
          style: AppTextStyles.small.copyWith(
            color: AppColors.slate500,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        center: true,
      ),
      _cell(_EmpDropdown(
        employees: employees,
        selectedId: row.employeeId,
        onChanged: onSelectEmployee,
        highlight: highlight,
        height: empDropdownHeight,
      )),
      _cell(_AmountField(
        value: row.amount,
        onChanged: onAmountChanged,
        highlight: highlight,
        height: amountFieldHeight,
      )),
      _cell(_DateField(
        value: row.fromDate,
        onChanged: onFromDateChanged,
        height: dateFieldHeight,
      )),
      _cell(_DateField(
        value: row.toDate,
        onChanged: onToDateChanged,
        height: dateFieldHeight,
      )),
      _cell(_AutoFilledInfo(row: row)),
      _cell(
        // Delete button: centered, natural height
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              size: 20, color: AppColors.slate400),
          onPressed: onRemove,
          hoverColor: Colors.red.withOpacity(0.08),
          splashRadius: 20,
          tooltip: 'Remove row',
        ),
        center: true,
      ),
    ],
  );
}

Widget _cell(Widget child, {bool center = false}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: center ? Center(child: child) : child,
      ),
    );

// ── Employee Dropdown ─────────────────────────────────────────────────────────

class _EmpDropdown extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String selectedId;
  final void Function(String) onChanged;
  final bool highlight;
  final double? height;

  const _EmpDropdown({
    required this.employees,
    required this.selectedId,
    required this.onChanged,
    this.highlight = false,
    this.height,
  });

  @override
  State<_EmpDropdown> createState() => _EmpDropdownState();
}

class _EmpDropdownState extends State<_EmpDropdown> {
  final LayerLink _layerLink = LayerLink();
  late final TextEditingController _sc;
  late final FocusNode _fn;
  OverlayEntry? _oe;

  EmployeeModel? get _sel {
    for (final e in widget.employees) {
      if (e.id?.toString() == widget.selectedId) return e;
    }
    return null;
  }

  String _label(EmployeeModel e) => '${e.name} (${e.pfNo})';

  void _sync() {
    final s = _sel;
    final t = s != null ? _label(s) : '';
    _sc.value = TextEditingValue(
        text: t, selection: TextSelection.collapsed(offset: t.length));
  }

  @override
  void initState() {
    super.initState();
    _sc = TextEditingController();
    _fn = FocusNode();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _EmpDropdown old) {
    super.didUpdateWidget(old);
    if (_oe == null && old.selectedId != widget.selectedId) _sync();
  }

  void _close({bool restore = true}) {
    _oe?.remove();
    _oe = null;
    if (restore) _sync();
    _fn.unfocus();
  }

  void _open({bool reset = true}) {
    if (_oe != null) return;
    final rb = context.findRenderObject() as RenderBox;
    final offset = rb.localToGlobal(Offset.zero);
    if (reset) {
      _sc.clear();
      _sc.selection = const TextSelection.collapsed(offset: 0);
    }
    _fn.requestFocus();
    _oe = OverlayEntry(builder: (_) => Stack(children: [
          Positioned.fill(
              child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _close,
            child: Container(color: Colors.transparent),
          )),
          Positioned(
            top: offset.dy + rb.size.height + 6,
            left: offset.dx,
            width: 480,
            child: CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              offset: Offset(0, rb.size.height + 6),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                shadowColor: Colors.black.withOpacity(0.15),
                child: EmployeeSearchDropdown(
                  employees: widget.employees,
                  selectedId: widget.selectedId,
                  searchController: _sc,
                  showSearchBar: false,
                  onSelected: (emp) {
                    final id = emp.id;
                    if (id != null) {
                      final lbl = _label(emp);
                      _sc.value = TextEditingValue(
                          text: lbl,
                          selection:
                              TextSelection.collapsed(offset: lbl.length));
                      widget.onChanged(id.toString());
                    }
                    _close(restore: false);
                  },
                ),
              ),
            ),
          ),
        ]));
    Overlay.of(context).insert(_oe!);
  }

  @override
  void dispose() {
    _close();
    _sc.dispose();
    _fn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _sc,
      focusNode: _fn,
      textAlignVertical: TextAlignVertical.center,
      style: AppTextStyles.input.copyWith(
        color: AppColors.slate800,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search employee...',
        hintStyle: AppTextStyles.input.copyWith(
          color: AppColors.slate400,
          fontSize: 13,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: widget.highlight
            ? const Color(0xFFFFF8E1)
            : Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: widget.highlight
                ? const Color(0xFFFFB300)
                : AppColors.slate300,
            width: widget.highlight ? 1.8 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.indigo500,
            width: 1.8,
          ),
        ),
        suffixIcon: IconButton(
          splashRadius: 18,
          onPressed: () => _oe == null ? _open() : _close(),
          icon: Icon(
            _oe == null ? Icons.arrow_drop_down : Icons.arrow_drop_up,
            size: 20,
            color: AppColors.slate500,
          ),
        ),
      ),
      onTap: () => _open(),
      onChanged: (_) {
        if (_oe == null) _open(reset: false);
      },
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: widget.height != null
          ? SizedBox(height: widget.height, child: field)
          : field,
    );
  }
}

// ── Amount Field ──────────────────────────────────────────────────────────────

class _AmountField extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;
  final bool highlight;
  final double? height;

  const _AmountField({
    required this.value,
    required this.onChanged,
    this.highlight = false,
    this.height,
  });

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatValue(widget.value));
  }

  String _formatValue(double v) {
    if (v == 0) return '';
    if (v == v.truncateToDouble()) {
      return v.toInt().toString();
    }
    return v.toStringAsFixed(2);
  }

  @override
  void didUpdateWidget(covariant _AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final newText = _formatValue(widget.value);
      if (_ctrl.text != newText) {
        _ctrl.text = newText;
        _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _ctrl,
      textAlign: TextAlign.right,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
      ],
      style: AppTextStyles.input.copyWith(
        color: AppColors.slate800,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: '0.00',
        hintStyle: AppTextStyles.input.copyWith(
          color: AppColors.slate400,
          fontSize: 13,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 8, top: 2),
          child: Text(
            '₹',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.slate600,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: widget.highlight
            ? const Color(0xFFFFF8E1)
            : Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: widget.highlight
                ? const Color(0xFFFFB300)
                : AppColors.slate300,
            width: widget.highlight ? 1.8 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.indigo500,
            width: 1.8,
          ),
        ),
      ),
      onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
    );

    return widget.height != null
        ? SizedBox(height: widget.height, child: field)
        : field;
  }
}

// ── Date Field ────────────────────────────────────────────────────────────────

class _DateField extends StatefulWidget {
  final String value;
  final void Function(String) onChanged;
  final double? height;

  const _DateField({
    required this.value,
    required this.onChanged,
    this.height,
  });

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _formatForDisplay(widget.value));
  }

  @override
  void didUpdateWidget(covariant _DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _ctrl.text = _formatForDisplay(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String _formatForDisplay(String iso) {
    if (iso.isEmpty) return '';
    if (iso.contains('-') && iso.length == 10) {
      final p = iso.split('-');
      return '${p[2]}/${p[1]}/${p[0]}';
    }
    return iso;
  }

  static String? _parseToIso(String input) {
    if (input.isEmpty) return '';
    final parts = input.split('/');
    if (parts.length == 3 &&
        parts[0].length == 2 &&
        parts[1].length == 2 &&
        parts[2].length == 4) {
      try {
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
          return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
        }
      } catch (_) {}
    }
    return null;
  }

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(widget.value) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.indigo600,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.slate800,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final iso = picked.toIso8601String().split('T').first;
      widget.onChanged(iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: _ctrl,
      textAlignVertical: TextAlignVertical.center,
      keyboardType: TextInputType.number,
      inputFormatters: [_DateMaskFormatter()],
      style: AppTextStyles.input.copyWith(
        fontSize: 13,
        color: AppColors.slate800,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'dd/mm/yyyy',
        hintStyle: AppTextStyles.input.copyWith(
          color: AppColors.slate400,
          fontSize: 13,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        filled: true,
        fillColor: Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slate300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.indigo500,
            width: 1.8,
          ),
        ),
        suffixIcon: IconButton(
          splashRadius: 18,
          onPressed: _pickDate,
          icon: const Icon(
            Icons.calendar_month_rounded,
            size: 18,
            color: AppColors.slate500,
          ),
          tooltip: 'Pick date',
        ),
      ),
      onChanged: (input) {
        final iso = _parseToIso(input);
        if (iso != null && iso.isNotEmpty) {
          widget.onChanged(iso);
        }
      },
    );

    return widget.height != null
        ? SizedBox(height: widget.height, child: field)
        : field;
  }
}

// ── Date Mask Formatter ───────────────────────────────────────────────────────

class _DateMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) buffer.write('/');
      buffer.write(digits[i]);
    }

    final masked = buffer.toString();
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

// ── Auto-filled Info ──────────────────────────────────────────────────────────

class _AutoFilledInfo extends StatelessWidget {
  final VoucherRowModel row;
  const _AutoFilledInfo({required this.row});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('IFSC', row.ifscCode),
            const SizedBox(height: 3),
            _kv('Account', row.accountNumber),
            const SizedBox(height: 3),
            _kv('Bank', row.bankDetails),
            const SizedBox(height: 3),
            _kv('Branch', row.branch),
          ],
        ),
      );

  static Widget _kv(String label, String value) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.slate500,
              ),
            ),
          ),
          const Text(
            ': ',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.slate400,
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppColors.slate700,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}
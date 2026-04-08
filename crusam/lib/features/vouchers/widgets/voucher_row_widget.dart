import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/employee_model.dart';
import '../../../../data/models/voucher_row_model.dart';
import 'employee_search_dropdown.dart';

/// Top-level builder — used by [_RowsTable] via alias import.
TableRow buildVoucherRow({
  required int index,
  required VoucherRowModel row,
  required List<EmployeeModel> employees,
  required void Function(String empId) onSelectEmployee,
  required void Function(double) onAmountChanged,
  required void Function(String) onFromDateChanged,
  required void Function(String) onToDateChanged,
  required VoidCallback onRemove,
}) =>
    TableRow(
      children: [
        _cell(Text('${index + 1}',
            style: AppTextStyles.small, textAlign: TextAlign.center)),
        _cell(_EmpDropdown(
            employees: employees,
            selectedId: row.employeeId,
            onChanged: onSelectEmployee)),
        _cell(_AmountField(value: row.amount, onChanged: onAmountChanged)),
        _cell(_DateField(value: row.fromDate, onChanged: onFromDateChanged)),
        _cell(_DateField(value: row.toDate, onChanged: onToDateChanged)),
        _cell(_AutoFilledInfo(row: row)),
        _cell(
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 17, color: AppColors.slate300),
            onPressed: onRemove,
            hoverColor: Colors.red.shade50,
          ),
          centerAlign: true,
        ),
      ],
    );

Widget _cell(Widget child, {bool centerAlign = false}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: centerAlign ? Center(child: child) : child,
      ),
    );

// ---------------------------------------------------------------------------

class _EmpDropdown extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String selectedId;
  final void Function(String) onChanged;

  const _EmpDropdown({
    required this.employees,
    required this.selectedId,
    required this.onChanged,
  });

  @override
  State<_EmpDropdown> createState() => _EmpDropdownState();
}

class _EmpDropdownState extends State<_EmpDropdown> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  EmployeeModel? get _selectedEmployee {
    for (final e in widget.employees) {
      if (e.id?.toString() == widget.selectedId) return e;
    }
    return null;
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _openDropdown() {
  if (_overlayEntry != null) return;

  final RenderBox renderBox = context.findRenderObject() as RenderBox;
  final Offset offset = renderBox.localToGlobal(Offset.zero);
  final double fieldWidth = renderBox.size.width;

  _overlayEntry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        // Barrier that closes on tap but does NOT block scroll gestures
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent, // allows scroll through
            onTap: _closeDropdown,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The dropdown widget itself
        Positioned(
          top: offset.dy + renderBox.size.height + 4,
          left: offset.dx,
          width: fieldWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, renderBox.size.height + 4),
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: EmployeeSearchDropdown(
                employees: widget.employees,
                selectedId: widget.selectedId,
                onSelected: (emp) {
                  final id = emp.id;
                  if (id != null) {
                    widget.onChanged(id.toString());
                  }
                  _closeDropdown();
                },
              ),
            ),
          ),
        ),
      ],
    ),
  );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _toggleDropdown() {
    if (_overlayEntry == null) {
      _openDropdown();
    } else {
      _closeDropdown();
    }
  }

  @override
  void dispose() {
    _closeDropdown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedEmployee;

    return CompositedTransformTarget(
      link: _layerLink,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: _toggleDropdown,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.slate200),
            borderRadius: BorderRadius.circular(6),
            color: AppColors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected != null
                      ? '${selected.name} (${selected.pfNo})'
                      : 'Select',
                  style: AppTextStyles.input.copyWith(
                    color: selected != null
                        ? AppColors.slate700
                        : AppColors.slate400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.unfold_more,
                  size: 14, color: AppColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _AmountField extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;

  const _AmountField({required this.value, required this.onChanged});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value == 0 ? '' : widget.value.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _ctrl,
        textAlign: TextAlign.right,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))
        ],
        style: AppTextStyles.input,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
      );
}

// ---------------------------------------------------------------------------

class _DateField extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const _DateField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(value) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            onChanged(picked.toIso8601String().split('T').first);
          }
        },
        child: Container(
          height: 36,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.slate200),
            borderRadius: BorderRadius.circular(6),
            color: AppColors.white,
          ),
          child: Text(
            value.isEmpty ? 'Pick date' : value,
            style: AppTextStyles.input.copyWith(
              fontSize: 12,
              color: value.isEmpty
                  ? AppColors.slate400
                  : AppColors.slate700,
            ),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------

class _AutoFilledInfo extends StatelessWidget {
  final VoucherRowModel row;

  const _AutoFilledInfo({required this.row});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 16,
        runSpacing: 4,
        children: [
          _kv('IFSC', row.ifscCode),
          _kv('A/c', row.accountNumber),
          _kv('Bank', row.bankDetails),
          _kv('Place', row.branch),
        ],
      );

  static Widget _kv(String k, String v) => RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 10, color: AppColors.slate500),
          children: [
            TextSpan(text: '$k: '),
            TextSpan(
              text: v.isEmpty ? '-' : v,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  color: AppColors.slate600),
            ),
          ],
        ),
      );
}
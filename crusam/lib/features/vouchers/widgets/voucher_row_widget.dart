import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/employee_model.dart';
import '../../../../data/models/voucher_row_model.dart';
import 'employee_search_dropdown.dart';

const double _kH = 38.0; // uniform field height across all row cells

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
}) {
  final isEven = index.isEven;
  final bg = highlight
      ? const Color(0xFFFFFDE7)
      : isEven ? AppColors.white : const Color(0xFFF8FAFC);

  return TableRow(
    decoration: BoxDecoration(
      color: bg,
      border: const Border(bottom: BorderSide(color: AppColors.slate200, width: 0.6)),
    ),
    children: [
      // # index
      _cell(Text('${index + 1}',
          style: AppTextStyles.small.copyWith(color: AppColors.slate500),
          textAlign: TextAlign.center)),
      // Employee dropdown
      _cell(_EmpDropdown(
        employees: employees,
        selectedId: row.employeeId,
        onChanged: onSelectEmployee,
        highlight: highlight,
      )),
      // Amount
      _cell(_AmountField(value: row.amount, onChanged: onAmountChanged)),
      // From date
      _cell(_DateField(value: row.fromDate, onChanged: onFromDateChanged)),
      // To date
      _cell(_DateField(value: row.toDate,   onChanged: onToDateChanged)),
      // Auto-filled details
      _cell(_AutoFilledInfo(row: row)),
      // Delete
      _cell(
        SizedBox(
          height: _kH,
          child: IconButton(
            icon: const Icon(Icons.delete_outline, size: 17, color: AppColors.slate300),
            onPressed: onRemove,
            hoverColor: Colors.red.shade50,
            tooltip: 'Remove',
          ),
        ),
        center: true,
      ),
    ],
  );
}

Widget _cell(Widget child, {bool center = false}) => TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: center ? Center(child: child) : child,
      ),
    );

// ── Employee Dropdown ─────────────────────────────────────────────────────────

class _EmpDropdown extends StatefulWidget {
  final List<EmployeeModel> employees;
  final String selectedId;
  final void Function(String) onChanged;
  final bool highlight;
  const _EmpDropdown({
    required this.employees,
    required this.selectedId,
    required this.onChanged,
    this.highlight = false,
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
    _sc.value = TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
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
    _oe?.remove(); _oe = null;
    if (restore) _sync();
    _fn.unfocus();
  }

  void _open({bool reset = true}) {
    if (_oe != null) return;
    final rb = context.findRenderObject() as RenderBox;
    final offset = rb.localToGlobal(Offset.zero);
    if (reset) { _sc.clear(); _sc.selection = const TextSelection.collapsed(offset: 0); }
    _fn.requestFocus();
    _oe = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _close,
        child: Container(color: Colors.transparent),
      )),
      Positioned(
        top: offset.dy + rb.size.height + 4,
        left: offset.dx,
        width: 460,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, rb.size.height + 4),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: EmployeeSearchDropdown(
              employees: widget.employees,
              selectedId: widget.selectedId,
              searchController: _sc,
              showSearchBar: false,
              onSelected: (emp) {
                final id = emp.id;
                if (id != null) {
                  final lbl = _label(emp);
                  _sc.value = TextEditingValue(text: lbl, selection: TextSelection.collapsed(offset: lbl.length));
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
  void dispose() { _close(); _sc.dispose(); _fn.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          height: _kH,
          child: TextField(
            controller: _sc,
            focusNode: _fn,
            style: AppTextStyles.input.copyWith(color: AppColors.slate700),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Select employee…',
              hintStyle: AppTextStyles.input.copyWith(color: AppColors.slate400),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              filled: true,
              fillColor: widget.highlight ? const Color(0xFFFFFDE7) : AppColors.white,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(
                  color: widget.highlight ? const Color(0xFFF59E0B) : AppColors.slate900,
                  width: widget.highlight ? 1.5 : 1.0,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.indigo500, width: 1.5),
              ),
              suffixIcon: IconButton(
                splashRadius: 16,
                onPressed: () => _oe == null ? _open() : _close(),
                icon: const Icon(Icons.unfold_more, size: 14, color: AppColors.slate400),
              ),
            ),
            onTap: () => _open(),
            onChanged: (_) { if (_oe == null) _open(reset: false); },
          ),
        ),
      );
}

// ── Amount Field ──────────────────────────────────────────────────────────────

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
    _ctrl = TextEditingController(text: widget.value == 0 ? '' : widget.value.toStringAsFixed(2));
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _kH,
        child: TextField(
          controller: _ctrl,
          textAlign: TextAlign.right,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: AppTextStyles.input,
          decoration: InputDecoration(
            isDense: true,
            hintText: '0.00',
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.slate900),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppColors.indigo500, width: 1.5),
            ),
          ),
          onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
        ),
      );
}

// ── Date Field ────────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;
  const _DateField({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final p = await showDatePicker(
            context: context,
            initialDate: DateTime.tryParse(value) ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (p != null) onChanged(p.toIso8601String().split('T').first);
        },
        child: Container(
          height: _kH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.white,
            border: Border.all(color: AppColors.slate900),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(children: [
            Expanded(
              child: Text(
                value.isEmpty ? 'Pick date' : value,
                style: AppTextStyles.input.copyWith(
                  fontSize: 12,
                  color: value.isEmpty ? AppColors.slate400 : AppColors.slate700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.calendar_today_outlined,
                size: 13, color: value.isEmpty ? AppColors.slate300 : AppColors.slate500),
          ]),
        ),
      );
}

// ── Auto-filled Info ──────────────────────────────────────────────────────────

class _AutoFilledInfo extends StatelessWidget {
  final VoucherRowModel row;
  const _AutoFilledInfo({required this.row});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            _kv('IFSC',  row.ifscCode),
            const SizedBox(height: 2),
            _kv('A/c',   row.accountNumber),
            const SizedBox(height: 2),
            _kv('Bank',  row.bankDetails),
            const SizedBox(height: 2),
            _kv('Place', row.branch),
          ],
        ),
      );

  static Widget _kv(String k, String v) => RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: const TextStyle(fontSize: 11, color: AppColors.slate500),
          children: [
            TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(
              text: v.isEmpty ? '—' : v,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.slate700),
            ),
          ],
        ),
      );
}
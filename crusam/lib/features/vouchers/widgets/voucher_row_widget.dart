import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/employee_model.dart';
import '../../../../data/models/voucher_row_model.dart';

TableRow buildVoucherRow({
  required int index,
  required VoucherRowModel row,
  required List<EmployeeModel> employees,
  required void Function(String empId) onSelectEmployee,
  required void Function(double) onAmountChanged,
  required void Function(String) onFromDateChanged,
  required void Function(String) onToDateChanged,
  required VoidCallback onRemove,
}) => TableRow(
  children: [
    _cell(Text('${index + 1}', style: AppTextStyles.small, textAlign: TextAlign.center)),
    _cell(_EmpDropdown(employees: employees, selectedId: row.employeeId, onChanged: onSelectEmployee)),
    _cell(_AmountField(value: row.amount, onChanged: onAmountChanged)),
    _cell(_DateField(value: row.fromDate, onChanged: onFromDateChanged)),
    _cell(_DateField(value: row.toDate, onChanged: onToDateChanged)),
    _cell(_AutoFilledInfo(row: row)),
    _cell(
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 17, color: AppColors.slate300),
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

/// A single row of a voucher table.
/// Returns a [Table] widget containing exactly one [TableRow].
class VoucherRowWidget extends StatelessWidget {
  final int index;
  final VoucherRowModel row;
  final List<EmployeeModel> employees;
  final void Function(String empId) onSelectEmployee;
  final void Function(double) onAmountChanged;
  final void Function(String) onFromDateChanged;
  final void Function(String) onToDateChanged;
  final VoidCallback onRemove;

  const VoucherRowWidget({
    super.key,
    required this.index,
    required this.row,
    required this.employees,
    required this.onSelectEmployee,
    required this.onAmountChanged,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
        6: FixedColumnWidth(48),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        buildVoucherRow(
          index: index,
          row: row,
          employees: employees,
          onSelectEmployee: onSelectEmployee,
          onAmountChanged: onAmountChanged,
          onFromDateChanged: onFromDateChanged,
          onToDateChanged: onToDateChanged,
          onRemove: onRemove,
        ),
      ],
    );
  }
}

class _EmpDropdown extends StatelessWidget {
  final List<EmployeeModel> employees;
  final String selectedId;
  final void Function(String) onChanged;
  const _EmpDropdown({required this.employees, required this.selectedId, required this.onChanged});

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: selectedId.isEmpty ? null : selectedId,
    hint: Text('Select', style: AppTextStyles.input),
    style: AppTextStyles.input,
    onChanged: (v) { if (v != null) onChanged(v); },
    isExpanded: true,
    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
    items: employees.map((e) => DropdownMenuItem(
      value: e.id.toString(),
      child: Text('${e.name} (${e.pfNo})', style: AppTextStyles.input, overflow: TextOverflow.ellipsis),
    )).toList(),
  );
}

class _AmountField extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;
  const _AmountField({required this.value, required this.onChanged});
  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  late final _ctrl = TextEditingController(text: widget.value == 0 ? '' : widget.value.toStringAsFixed(2));
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => TextField(
    controller: _ctrl,
    textAlign: TextAlign.right,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
    style: AppTextStyles.input,
    decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
    onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
  );
}

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
        firstDate: DateTime(2000), lastDate: DateTime(2100),
      );
      if (picked != null) onChanged(picked.toIso8601String().split('T').first);
    },
    child: Container(
      height: 36, alignment: Alignment.centerLeft,
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
          color: value.isEmpty ? AppColors.slate400 : AppColors.slate700,
        ),
      ),
    ),
  );
}

class _AutoFilledInfo extends StatelessWidget {
  final VoucherRowModel row;
  const _AutoFilledInfo({required this.row});

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 16, runSpacing: 4,
    children: [
      _kv('IFSC', row.ifscCode),
      _kv('A/c', row.accountNumber),
      _kv('Bank', row.bankDetails),
      _kv('Place', row.branch),
    ],
  );

  static Widget _kv(String k, String v) => RichText(
    text: TextSpan(
      style: const TextStyle(fontSize: 10, color: AppColors.slate500),
      children: [
        TextSpan(text: '$k: '),
        TextSpan(text: v.isEmpty ? '-' : v,
            style: const TextStyle(fontFamily: 'monospace', color: AppColors.slate600)),
      ],
    ),
  );
}
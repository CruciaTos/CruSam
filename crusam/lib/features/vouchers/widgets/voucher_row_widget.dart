import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/employee_model.dart';
import '../../../../data/models/voucher_row_model.dart';
import 'employee_search_dropdown.dart';

const double _kH = 38.0;
const EdgeInsets _kInputPadding = EdgeInsets.symmetric(horizontal: 8);

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
      : isEven
          ? AppColors.white
          : const Color(0xFFF8FAFC);

  return TableRow(
    decoration: BoxDecoration(
      color: bg,
      border: const Border(
          bottom: BorderSide(color: AppColors.slate200, width: 0.6)),
    ),
    children: [
      _cell(Text('${index + 1}',
          style: AppTextStyles.small.copyWith(color: AppColors.slate500),
          textAlign: TextAlign.center)),
      _cell(_EmpDropdown(
        employees: employees,
        selectedId: row.employeeId,
        onChanged: onSelectEmployee,
        highlight: highlight,
      )),
      _cell(_AmountField(
        value: row.amount,
        onChanged: onAmountChanged,
        highlight: highlight,
      )),
      _cell(_DateField(value: row.fromDate, onChanged: onFromDateChanged)),
      _cell(_DateField(value: row.toDate, onChanged: onToDateChanged)),
      _cell(_AutoFilledInfo(row: row)),
      _cell(
        SizedBox(
          height: _kH,
          child: IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 17, color: AppColors.rose400),
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: center ? Center(child: child) : child,
      ),
    );

OutlineInputBorder _border(Color color, {double width = 1.0}) =>
    OutlineInputBorder(
      borderRadius: BorderRadius.circular(6),
      borderSide: BorderSide(color: color, width: width),
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
    _sc.value =
        TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
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
                      _sc.value = TextEditingValue(
                          text: lbl,
                          selection: TextSelection.collapsed(offset: lbl.length));
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
  Widget build(BuildContext context) => CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          height: _kH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: TextField(
                  controller: _sc,
                  focusNode: _fn,
                  maxLines: null,
                  minLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.center,
                  style: AppTextStyles.input.copyWith(color: AppColors.slate700),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Select employee…',
                    hintStyle:
                        AppTextStyles.input.copyWith(color: AppColors.slate400),
                    contentPadding: _kInputPadding,
                    filled: true,
                    fillColor: widget.highlight
                        ? const Color(0xFFFFFDE7)
                        : AppColors.white,
                    enabledBorder: _border(
                      widget.highlight
                          ? const Color(0xFFF59E0B)
                          : AppColors.slate900,
                      width: widget.highlight ? 1.5 : 1.0,
                    ),
                    focusedBorder: _border(AppColors.indigo500, width: 1.5),
                  ),
                  onTap: () => _open(),
                  onChanged: (_) {
                    if (_oe == null) _open(reset: false);
                  },
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 28,
                child: IconButton(
                  splashRadius: 14,
                  onPressed: () => _oe == null ? _open() : _close(),
                  icon: const Icon(Icons.unfold_more,
                      size: 14, color: AppColors.slate400),
                  tooltip: 'Select employee',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
              ),
            ],
          ),
        ),
      );
}

// ── Amount Field ──────────────────────────────────────────────────────────────

class _AmountField extends StatefulWidget {
  final double value;
  final void Function(double) onChanged;
  final bool highlight;
  const _AmountField({
    required this.value,
    required this.onChanged,
    this.highlight = false,
  });
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
  void didUpdateWidget(covariant _AmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final t = widget.value == 0 ? '' : widget.value.toStringAsFixed(2);
      if (_ctrl.text != t) {
        _ctrl.text = t;
        _ctrl.selection = TextSelection.collapsed(offset: t.length);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _kH,
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          minLines: null,
          expands: true,
          textAlign: TextAlign.right,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
          style: AppTextStyles.input.copyWith(color: AppColors.slate700),
          decoration: InputDecoration(
            isDense: true,
            hintText: '0.00',
            hintStyle: AppTextStyles.input.copyWith(color: AppColors.slate400),
            contentPadding: _kInputPadding,
            filled: true,
            fillColor:
                widget.highlight ? const Color(0xFFFFFDE7) : AppColors.white,
            enabledBorder: _border(
              widget.highlight ? const Color(0xFFF59E0B) : AppColors.slate900,
              width: widget.highlight ? 1.5 : 1.0,
            ),
            focusedBorder: _border(AppColors.indigo500, width: 1.5),
          ),
          onChanged: (v) => widget.onChanged(double.tryParse(v) ?? 0),
        ),
      );
}

// ── Date Field ────────────────────────────────────────────────────────────────

class _DateField extends StatefulWidget {
  final String value;
  final void Function(String) onChanged;

  const _DateField({required this.value, required this.onChanged});

  @override
  State<_DateField> createState() => _DateFieldState();
}

class _DateFieldState extends State<_DateField> {
  static const String _mask = 'dd/mm/yyyy';
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _isValid = false;
  bool _isInternalUpdate = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _setInitialValue(widget.value);
    _controller.addListener(_handleChange);

    // Cursor-to-start: fires after platform settles cursor position
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _controller.text == _mask) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.hasFocus && _controller.text == _mask) {
            _controller.selection = const TextSelection.collapsed(offset: 0);
          }
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _setInitialValue(widget.value);
  }

  void _setInitialValue(String iso) {
    _isInternalUpdate = true;
    String displayText = _mask;
    if (iso.isNotEmpty) {
      try {
        final date = DateTime.parse(iso);
        final d = date.day.toString().padLeft(2, '0');
        final m = date.month.toString().padLeft(2, '0');
        final y = date.year.toString();
        displayText = '$d/$m/$y';
        _isValid = true;
      } catch (_) {
        _isValid = false;
      }
    } else {
      _isValid = false;
    }
    _controller.text = displayText;
    _controller.selection =
        TextSelection.collapsed(offset: displayText.length);
    _isInternalUpdate = false;
  }

  void _handleChange() {
    if (_isInternalUpdate) return;
    final text = _controller.text;
    final newIsValid = _isCompleteAndValid(text);
    if (newIsValid != _isValid) {
      _isValid = newIsValid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
    if (_isValid) {
      final iso = _toIsoString(text);
      if (iso != null) widget.onChanged(iso);
    }
  }

  bool _isCompleteAndValid(String text) {
    if (text.length != 10) return false;
    if (text[2] != '/' || text[5] != '/') return false;
    final day = int.tryParse(text.substring(0, 2));
    final month = int.tryParse(text.substring(3, 5));
    final year = int.tryParse(text.substring(6, 10));
    if (day == null || month == null || year == null) return false;
    if (day < 1 || day > 31 || month < 1 || month > 12) return false;
    if (year < 1900 || year > 2100) return false;
    int maxDay;
    if (month == 2) {
      maxDay =
          ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) ? 29 : 28;
    } else {
      maxDay = [4, 6, 9, 11].contains(month) ? 30 : 31;
    }
    return day <= maxDay;
  }

  String? _toIsoString(String text) {
    final parts = text.split('/');
    if (parts.length != 3) return null;
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  bool get _hasInput => _controller.text != _mask;

  Future<void> _pickDate() async {
    final initial = widget.value.isNotEmpty
        ? (DateTime.tryParse(widget.value) ?? DateTime.now())
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.indigo600,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: AppColors.slate800,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      _isInternalUpdate = true;
      final d = picked.day.toString().padLeft(2, '0');
      final m = picked.month.toString().padLeft(2, '0');
      final y = picked.year.toString();
      _controller.text = '$d/$m/$y';
      _isInternalUpdate = false;
      widget.onChanged(picked.toIso8601String().split('T').first);
      setState(() => _isValid = true);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _kH,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                maxLines: null,
                minLines: null,
                expands: true,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                keyboardType: TextInputType.number,
                inputFormatters: [_DateMaskFormatter()],
                style: AppTextStyles.input.copyWith(
                  color: AppColors.slate700,
                  fontFamily: 'monospace',
                ),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: _mask,
                  hintStyle: AppTextStyles.input.copyWith(
                    color: AppColors.slate400,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  contentPadding: _kInputPadding,
                  filled: true,
                  fillColor: Colors.white,
                  enabledBorder: _border(AppColors.slate300),
                  focusedBorder: _border(AppColors.indigo500, width: 1.6),
                  errorBorder: _border(Colors.red, width: 1.5),
                  focusedErrorBorder: _border(Colors.red, width: 1.5),
                  errorText: !_isValid && _hasInput ? '' : null,
                  errorStyle: const TextStyle(height: 0, fontSize: 0),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 28,
              child: IconButton(
                splashRadius: 14,
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_rounded,
                    size: 16, color: AppColors.slate500),
                tooltip: 'Pick date',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ),
          ],
        ),
      );
}

// ── Date Mask Formatter ───────────────────────────────────────────────────────

class _DateMaskFormatter extends TextInputFormatter {
  static const String _mask = 'dd/mm/yyyy';
  static const List<int> _digitPositions = [0, 1, 3, 4, 6, 7, 8, 9];
  static const List<int> _separatorPositions = [2, 5];

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldText = oldValue.text;
    final newTextRaw = newValue.text;

    if (oldText.isEmpty) {
      return const TextEditingValue(
        text: _mask,
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    if (newTextRaw.length < oldText.length) {
      int deletePos = oldValue.selection.baseOffset;
      if (deletePos > 0) {
        if (_separatorPositions.contains(deletePos - 1)) {
          if (deletePos - 2 >= 0) {
            final newText = _replaceWithPlaceholder(oldText, deletePos - 2);
            return TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: deletePos - 2),
            );
          }
          return oldValue;
        } else {
          final newText = _replaceWithPlaceholder(oldText, deletePos - 1);
          return TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: deletePos - 1),
          );
        }
      }
    }

    if (newTextRaw.length > oldText.length) {
      int insertPos = newValue.selection.baseOffset - 1;
      if (insertPos < 0) insertPos = 0;
      if (insertPos >= _mask.length) return oldValue;

      final insertedChar = newTextRaw[insertPos];
      if (_digitPositions.contains(insertPos) &&
          RegExp(r'\d').hasMatch(insertedChar)) {
        final newMaskedText = _replaceCharAt(oldText, insertPos, insertedChar);
        int nextPos = insertPos + 1;
        if (nextPos < _mask.length && _separatorPositions.contains(nextPos)) {
          nextPos++;
        }
        return TextEditingValue(
          text: newMaskedText,
          selection: TextSelection.collapsed(offset: nextPos),
        );
      }
    }

    return oldValue;
  }

  String _replaceCharAt(String text, int index, String newChar) {
    final chars = text.split('');
    chars[index] = newChar;
    return chars.join('');
  }

  String _replaceWithPlaceholder(String text, int index) =>
      _replaceCharAt(text, index, _mask[index]);
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
            _kv('IFSC', row.ifscCode),
            const SizedBox(height: 2),
            _kv('A/c', row.accountNumber),
            const SizedBox(height: 2),
            _kv('Bank', row.bankDetails),
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
            TextSpan(
                text: '$k: ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(
              text: v.isEmpty ? '—' : v,
              style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppColors.slate700),
            ),
          ],
        ),
      );
}
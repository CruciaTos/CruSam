import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/money.dart';

class MoneyField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? label;
  final String? hint;
  final bool enabled;
  final String? errorText;
  final bool allowNegative;

  const MoneyField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.hint = '0.00',
    this.enabled = true,
    this.errorText,
    this.allowNegative = false,
  });

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final text = widget.value != null ? formatPlainAmount(widget.value!) : '';
    _controller = TextEditingController(text: text);
  }

  @override
  void didUpdateWidget(covariant MoneyField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final currentPaise = parseRupeesToPaise(_controller.text);
      if (currentPaise != widget.value) {
        final text = widget.value != null ? formatPlainAmount(widget.value!) : '';
        _controller.text = text;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    final parsed = parseRupeesToPaise(text);
    if (parsed != null && !widget.allowNegative && parsed < 0) {
      widget.onChanged(null);
    } else {
      widget.onChanged(parsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        prefixText: '₹ ',
        prefixStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
        filled: true,
        fillColor: widget.enabled ? Colors.white : const Color(0xFFF1F5F9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
      onChanged: _onChanged,
    );
  }
}

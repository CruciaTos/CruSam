import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/money.dart';

class AreaField extends StatefulWidget {
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? label;
  final String? hint;
  final String unit;
  final bool enabled;
  final String? errorText;

  const AreaField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.hint = '0.00',
    this.unit = 'sq ft',
    this.enabled = true,
    this.errorText,
  });

  @override
  State<AreaField> createState() => _AreaFieldState();
}

class _AreaFieldState extends State<AreaField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final text = widget.value != null ? (widget.value! / 100).toStringAsFixed(2) : '';
    _controller = TextEditingController(text: text);
  }

  @override
  void didUpdateWidget(covariant AreaField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final currentCenti = parseAreaToCenti(_controller.text);
      if (currentCenti != widget.value) {
        final text = widget.value != null ? (widget.value! / 100).toStringAsFixed(2) : '';
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
    final parsed = parseAreaToCenti(text);
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: widget.errorText,
        suffixText: widget.unit,
        suffixStyle: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
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

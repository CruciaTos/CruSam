import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/society_date.dart';

class SocietyDateField extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final String? label;
  final bool enabled;
  final String? errorText;

  const SocietyDateField({
    super.key,
    this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
    this.errorText,
  });

  @override
  State<SocietyDateField> createState() => _SocietyDateFieldState();
}

class _SocietyDateFieldState extends State<SocietyDateField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final text = widget.value != null ? formatDisplayDate(widget.value!) : '';
    _controller = TextEditingController(text: text);
  }

  @override
  void didUpdateWidget(covariant SocietyDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final currentIso = parseDisplayDate(_controller.text);
      if (currentIso != widget.value) {
        final text = widget.value != null ? formatDisplayDate(widget.value!) : '';
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
    final parsedIso = parseDisplayDate(text);
    widget.onChanged(parsedIso);
  }

  Future<void> _selectDate() async {
    if (!widget.enabled) return;
    DateTime initial = DateTime.now();
    if (widget.value != null && widget.value!.isNotEmpty) {
      try {
        initial = parseIsoDate(widget.value!);
      } catch (_) {}
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      final iso = toIsoDate(picked);
      _controller.text = formatDisplayDate(iso);
      widget.onChanged(iso);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      enabled: widget.enabled,
      keyboardType: TextInputType.datetime,
      style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: 'DD/MM/YYYY',
        errorText: widget.errorText,
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          onPressed: widget.enabled ? _selectDate : null,
        ),
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

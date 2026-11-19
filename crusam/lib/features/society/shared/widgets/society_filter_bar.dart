import 'dart:async';
import 'package:flutter/material.dart';

class SocietyFilterBar extends StatefulWidget {
  final String? searchHint;
  final ValueChanged<String>? onSearch;
  final List<Widget>? filters;
  final Widget? trailing;

  const SocietyFilterBar({
    super.key,
    this.searchHint = 'Search...',
    this.onSearch,
    this.filters,
    this.trailing,
  });

  @override
  State<SocietyFilterBar> createState() => _SocietyFilterBarState();
}

class _SocietyFilterBarState extends State<SocietyFilterBar> {
  final TextEditingController _ctrl = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    if (widget.onSearch == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      widget.onSearch!(val.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (widget.onSearch != null)
          SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
              decoration: InputDecoration(
                hintText: widget.searchHint,
                hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                ),
              ),
              onChanged: _onChanged,
            ),
          ),
        if (widget.filters != null && widget.filters!.isNotEmpty) ...[
          const SizedBox(width: 12),
          for (var i = 0; i < widget.filters!.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            widget.filters![i],
          ],
        ],
        const Spacer(),
        if (widget.trailing != null) widget.trailing!,
      ],
    );
  }
}

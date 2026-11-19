import 'package:flutter/material.dart';

class StatusChip extends StatelessWidget {
  final String status;
  final String? label;

  const StatusChip({
    super.key,
    required this.status,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase().trim();
    Color bg;
    Color fg;

    switch (s) {
      case 'posted':
      case 'active':
      case 'resolved':
        bg = const Color(0xFFDCFCE7); // green-100
        fg = const Color(0xFF15803D); // green-700
        break;
      case 'reversed':
      case 'failed':
      case 'cancelled':
        bg = const Color(0xFFFEE2E2); // red-100
        fg = const Color(0xFFB91C1C); // red-700
        break;
      case 'open':
      case 'sent':
        bg = const Color(0xFFDBEAFE); // blue-100
        fg = const Color(0xFF1D4ED8); // blue-700
        break;
      case 'draft':
      case 'closed':
      default:
        bg = const Color(0xFFF1F5F9); // slate-100
        fg = const Color(0xFF475569); // slate-600
        break;
    }

    final displayText = label ?? _formatStatus(s);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        displayText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    if (status.isEmpty) return '';
    final words = status.split('_');
    return words.map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }
}

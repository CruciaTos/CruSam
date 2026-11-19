import 'package:flutter/material.dart';
import 'package:crusam/features/society/core/money.dart';

class AmountSummaryRow {
  final String label;
  final int? amountPaise;
  final String? customValue;
  final bool isTotal;
  final bool isHighlight;

  const AmountSummaryRow({
    required this.label,
    this.amountPaise,
    this.customValue,
    this.isTotal = false,
    this.isHighlight = false,
  });
}

class AmountSummary extends StatelessWidget {
  final List<AmountSummaryRow> rows;
  final double width;

  const AmountSummary({
    super.key,
    required this.rows,
    this.width = 300,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: rows.map((row) {
          final isTotal = row.isTotal;
          final valueText = row.customValue ??
              (row.amountPaise != null ? formatInr(row.amountPaise!) : '₹0.00');

          if (isTotal) {
            return Column(
              children: [
                const Divider(color: Color(0xFFCBD5E1), height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      row.label,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.isHighlight ? FontWeight.w600 : FontWeight.normal,
                    color: row.isHighlight ? const Color(0xFF0F172A) : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  valueText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: row.isHighlight ? FontWeight.w600 : FontWeight.w500,
                    color: row.isHighlight ? const Color(0xFF0F172A) : const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/voucher_model.dart';
import '../../../shared/utils/format_utils.dart';

class SalaryLineChart extends StatelessWidget {
  final List<VoucherModel> vouchers;

  const SalaryLineChart({super.key, required this.vouchers});

  List<FlSpot> _buildSpots() {
    // Filter only saved vouchers and those with salary rows
    final saved = vouchers
        .where((v) => v.status == VoucherStatus.saved)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final spots = <FlSpot>[];
    for (var i = 0; i < saved.length; i++) {
      final voucher = saved[i];
      // Sum salary amounts (assuming row description contains "Salary" or you have a type field)
      final salaryTotal = voucher.rows
          .where((row) => row.description.toLowerCase().contains('salary'))
          .fold(0.0, (sum, row) => sum + row.amount);
      if (salaryTotal > 0) {
        spots.add(FlSpot(i.toDouble(), salaryTotal));
      }
    }
    return spots;
  }

  String _formatDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd/MM').format(dt);
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final spots = _buildSpots();
    if (spots.isEmpty) {
      return const SizedBox.shrink();
    }

    final savedVouchers = vouchers
        .where((v) => v.status == VoucherStatus.saved)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // Find max salary for y-axis scaling
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yMax = (maxY * 1.1).ceilToDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 20, color: AppColors.indigo600),
              const SizedBox(width: 8),
              Text(
                'Salary Trend per Saved Invoice',
                style: AppTextStyles.h4,
              ),
            ],
          ),
          const SizedBox(height: 24),
          AspectRatio(
            aspectRatio: 2.5,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (yMax / 5).ceilToDouble(),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.slate200,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      interval: (yMax / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        return Text(
                          formatCurrency(value),
                          style: AppTextStyles.small.copyWith(
                            color: AppColors.slate600,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index >= 0 && index < savedVouchers.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _formatDate(savedVouchers[index].date),
                              style: AppTextStyles.small.copyWith(
                                color: AppColors.slate600,
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppColors.indigo600,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, barData, index) =>
                          FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeWidth: 2,
                        strokeColor: AppColors.indigo600,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.indigo50.withOpacity(0.5),
                    ),
                  ),
                ],
                minY: 0,
                maxY: yMax,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => AppColors.indigo600,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final index = spot.x.toInt();
                        final voucher = savedVouchers[index];
                        return LineTooltipItem(
                          '${voucher.title}\n${formatCurrency(spot.y)}',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
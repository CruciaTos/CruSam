// lib/features/dashboard/presentation/dashboard_screen.dart
import 'dart:math' as math;
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/models/employee_model.dart';
import '../../master_data/presentation/employee_form_screen.dart';
import '../../vouchers/notifiers/voucher_notifier.dart';
import '../notifiers/dashboard_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Computed analytics model — derives all stats from raw data once
// ─────────────────────────────────────────────────────────────────────────────
class _DashStats {
  // Employees
  final int totalEmployees;
  final Map<String, int> byCode;
  final Map<String, int> byZone;
  final int maleCount;
  final int femaleCount;
  final double totalGrossSalaryMass;

  // Vouchers
  final int totalVouchers;
  final int savedCount;
  final int draftCount;
  final double totalInvoiced;
  final double avgVoucherAmount;
  final double maxVoucherAmount;
  final double minVoucherAmount;
  final String topClient;
  final String topDept;

  // Monthly trend: sorted list of (label, total)
  final List<(String label, double total)> monthlyTrend;

  _DashStats({
    required this.totalEmployees,
    required this.byCode,
    required this.byZone,
    required this.maleCount,
    required this.femaleCount,
    required this.totalGrossSalaryMass,
    required this.totalVouchers,
    required this.savedCount,
    required this.draftCount,
    required this.totalInvoiced,
    required this.avgVoucherAmount,
    required this.maxVoucherAmount,
    required this.minVoucherAmount,
    required this.topClient,
    required this.topDept,
    required this.monthlyTrend,
  });

  factory _DashStats.from(
      List<EmployeeModel> employees, List<VoucherModel> vouchers) {
    // ── Employees ─────────────────────────────────────────────────────────
    final byCode = <String, int>{};
    final byZone = <String, int>{};
    int male = 0, female = 0;
    double totalGross = 0;
    for (final e in employees) {
      final code = e.code.trim().isEmpty ? 'Other' : e.code.trim();
      byCode[code] = (byCode[code] ?? 0) + 1;
      final zone = e.zone.trim().isEmpty ? 'Other' : e.zone.trim();
      byZone[zone] = (byZone[zone] ?? 0) + 1;
      if (e.gender.toUpperCase() == 'F') { female++; } else { male++; }
      totalGross += e.grossSalary;
    }

    // ── Vouchers ──────────────────────────────────────────────────────────
    final saved   = vouchers.where((v) => v.status == VoucherStatus.saved).toList();
    final drafts  = vouchers.where((v) => v.status == VoucherStatus.draft).toList();
    double total  = 0, maxA = 0, minA = double.infinity;
    final clientCount = <String, int>{};
    final deptCount   = <String, int>{};
    for (final v in vouchers) {
      total += v.finalTotal;
      if (v.finalTotal > maxA) maxA = v.finalTotal;
      if (v.finalTotal < minA) minA = v.finalTotal;
      if (v.clientName.isNotEmpty) {
        clientCount[v.clientName] = (clientCount[v.clientName] ?? 0) + 1;
      }
      if (v.deptCode.isNotEmpty) {
        deptCount[v.deptCode] = (deptCount[v.deptCode] ?? 0) + 1;
      }
    }
    if (minA == double.infinity) minA = 0;
    final avg = vouchers.isEmpty ? 0.0 : total / vouchers.length;
    final topC = clientCount.entries.isEmpty
        ? '—'
        : (clientCount.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final topD = deptCount.entries.isEmpty
        ? '—'
        : (deptCount.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;

    // ── Monthly trend (last 6 months of saved vouchers) ───────────────────
    final monthMap = <String, double>{};
    final monthOrder = <String, DateTime>{};
    for (final v in saved) {
      try {
        final dt = DateTime.parse(v.date);
        final key = DateFormat('MMM yy').format(dt);
        monthMap[key] = (monthMap[key] ?? 0) + v.baseTotal;
        if (!monthOrder.containsKey(key)) monthOrder[key] = dt;
      } catch (_) {}
    }
    final sorted = monthOrder.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final trend = sorted
        .take(6)
        .map((e) => (e.key, monthMap[e.key] ?? 0.0))
        .toList();

    return _DashStats(
      totalEmployees:      employees.length,
      byCode:              byCode,
      byZone:              byZone,
      maleCount:           male,
      femaleCount:         female,
      totalGrossSalaryMass: totalGross,
      totalVouchers:       vouchers.length,
      savedCount:          saved.length,
      draftCount:          drafts.length,
      totalInvoiced:       total,
      avgVoucherAmount:    avg,
      maxVoucherAmount:    maxA,
      minVoucherAmount:    minA,
      topClient:           topC,
      topDept:             topD,
      monthlyTrend:        trend,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DashboardScreen
// ─────────────────────────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _notifier = DashboardNotifier();

  @override
  void initState() {
    super.initState();
    _notifier.load();
  }

  @override
  void dispose() {
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _notifier,
        builder: (ctx, _) {
          if (_notifier.isLoading) return const _DashboardSkeleton();

          final stats = _DashStats.from(
            _notifier.employees, _notifier.vouchers);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WelcomeBanner(stats: stats),
                const SizedBox(height: 20),
                _HeroMetrics(stats: stats),
                const SizedBox(height: 20),
                _MiddleRow(
                  stats: stats,
                  vouchers: _notifier.vouchers,
                ),
                const SizedBox(height: 20),
                _BottomRow(
                  stats: stats,
                  vouchers: _notifier.vouchers,
                  onAddEmployee: () => _openAddEmployee(context),
                ),
              ],
            ),
          );
        },
      );

  void _openAddEmployee(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black45,
      barrierDismissible: false,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: const EmployeeFormScreen(employee: null),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Welcome Banner
// ─────────────────────────────────────────────────────────────────────────────
class _WelcomeBanner extends StatelessWidget {
  final _DashStats stats;
  const _WelcomeBanner({required this.stats});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final greeting = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final month = DateFormat('MMMM yyyy').format(now);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: AppColors.indigo600.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greeting, Admin',
                  style: AppTextStyles.h3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  '$month — ${stats.totalEmployees} employees · ${stats.savedCount} invoices finalized',
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate400),
                ),
              ],
            ),
          ),
          _QuickActionChip(
            icon: Icons.add,
            label: 'New Voucher',
            onTap: () => context.go('/vouchers'),
          ),
          const SizedBox(width: 10),
          _QuickActionChip(
            icon: Icons.people_outline,
            label: 'Employees',
            onTap: () => context.go('/employees'),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.indigo600.withOpacity(0.2),
            border: Border.all(color: AppColors.indigo600.withOpacity(0.4)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: AppColors.indigo400),
              const SizedBox(width: 6),
              Text(label,
                  style: AppTextStyles.smallMedium
                      .copyWith(color: AppColors.indigo400)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Metrics — 4 primary KPI cards
// ─────────────────────────────────────────────────────────────────────────────
class _HeroMetrics extends StatelessWidget {
  final _DashStats stats;
  const _HeroMetrics({required this.stats});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          final cols = c.maxWidth > 900 ? 4 : c.maxWidth > 600 ? 2 : 1;
          return GridView.count(
            crossAxisCount: cols,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: cols == 4 ? 1.9 : 2.2,
            children: [
              _MetricCard(
                icon: Icons.people_outline,
                label: 'Total Employees',
                value: '${stats.totalEmployees}',
                sub: '${stats.maleCount}M · ${stats.femaleCount}F',
                accent: const Color(0xFF3B82F6),
                accentBg: const Color(0xFF1E3A5F),
              ),
              _MetricCard(
                icon: Icons.receipt_long_outlined,
                label: 'Total Invoiced',
                value: formatCurrency(stats.totalInvoiced),
                sub: '${stats.savedCount} finalized',
                accent: AppColors.emerald600,
                accentBg: const Color(0xFF064E3B),
              ),
              _MetricCard(
                icon: Icons.description_outlined,
                label: 'Total Vouchers',
                value: '${stats.totalVouchers}',
                sub: '${stats.draftCount} drafts pending',
                accent: AppColors.indigo500,
                accentBg: const Color(0xFF312E81),
              ),
              _MetricCard(
                icon: Icons.payments_outlined,
                label: 'Salary Mass',
                value: formatCurrency(stats.totalGrossSalaryMass),
                sub: 'Monthly gross total',
                accent: const Color(0xFFF59E0B),
                accentBg: const Color(0xFF78350F),
              ),
            ],
          );
        },
      );
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color accent;
  final Color accentBg;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    required this.accentBg,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(sub,
                    style: TextStyle(
                        fontSize: 10,
                        color: accent,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5)),
            const SizedBox(height: 2),
            Text(label,
                style: AppTextStyles.small.copyWith(color: AppColors.slate400)),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Middle Row — Chart + Quick Insights
// ─────────────────────────────────────────────────────────────────────────────
class _MiddleRow extends StatelessWidget {
  final _DashStats stats;
  final List<VoucherModel> vouchers;
  const _MiddleRow({required this.stats, required this.vouchers});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          if (c.maxWidth < 760) {
            return Column(children: [
              _ChartPanel(stats: stats),
              const SizedBox(height: 14),
              _InsightsPanel(stats: stats),
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _ChartPanel(stats: stats)),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: _InsightsPanel(stats: stats)),
            ],
          );
        },
      );
}

// Monthly bar chart
class _ChartPanel extends StatefulWidget {
  final _DashStats stats;
  const _ChartPanel({required this.stats});
  @override
  State<_ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<_ChartPanel> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final trend = widget.stats.monthlyTrend;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        border: Border.all(color: AppColors.slate700, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded,
                size: 16, color: AppColors.indigo400),
            const SizedBox(width: 8),
            Text('Monthly Revenue',
                style: AppTextStyles.h4.copyWith(color: Colors.white)),
            const Spacer(),
            Text('Saved invoices · base total',
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate500, fontSize: 11)),
          ]),
          const SizedBox(height: 20),
          if (trend.isEmpty)
            _EmptyChartState()
          else
            _BarChartBody(trend: trend, touchedIndex: _touchedIndex,
                onTouch: (i) => setState(() => _touchedIndex = i)),
        ],
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 160,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart_outlined,
                  size: 40, color: AppColors.slate700),
              const SizedBox(height: 8),
              Text('No finalized invoices yet',
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate500)),
            ],
          ),
        ),
      );
}

class _BarChartBody extends StatelessWidget {
  final List<(String, double)> trend;
  final int touchedIndex;
  final void Function(int) onTouch;

  const _BarChartBody(
      {required this.trend,
      required this.touchedIndex,
      required this.onTouch});

  @override
  Widget build(BuildContext context) {
    final maxVal =
        trend.map((e) => e.$2).fold(0.0, (a, b) => a > b ? a : b);
    final yMax = maxVal == 0 ? 100.0 : maxVal * 1.15;
    final interval = (yMax / 4).ceilToDouble();

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: yMax,
          barTouchData: BarTouchData(
            touchCallback: (event, resp) {
              if (resp?.spot != null &&
                  event is FlTapUpEvent) {
                onTouch(resp!.spot!.touchedBarGroupIndex);
              }
            },
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
                '${trend[group.x].$1}\n${formatCurrency(rod.toY)}',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= trend.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(trend[i].$1,
                        style: AppTextStyles.small.copyWith(
                            color: AppColors.slate400, fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: interval,
                getTitlesWidget: (v, meta) => Text(
                  v == 0
                      ? '0'
                      : '₹${(v / 1000).toStringAsFixed(0)}k',
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate500, fontSize: 9),
                ),
              ),
            ),
            topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                const FlLine(color: Color(0x22FFFFFF), strokeWidth: 0.5),
          ),
          borderData: FlBorderData(show: false),
          barGroups: trend.asMap().entries.map((entry) {
            final i = entry.key;
            final touched = i == touchedIndex;
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: entry.value.$2,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4)),
                  gradient: LinearGradient(
                    colors: touched
                        ? [AppColors.indigo400, AppColors.indigo600]
                        : [
                            AppColors.indigo600.withOpacity(0.7),
                            AppColors.indigo600,
                          ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}

// Quick insights panel
class _InsightsPanel extends StatelessWidget {
  final _DashStats stats;
  const _InsightsPanel({required this.stats});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.auto_awesome_outlined,
                  size: 16, color: AppColors.indigo400),
              const SizedBox(width: 8),
              Text('Quick Insights',
                  style:
                      AppTextStyles.h4.copyWith(color: Colors.white)),
            ]),
            const SizedBox(height: 16),
            _InsightRow(
              icon: Icons.trending_up_outlined,
              label: 'Avg. Invoice Value',
              value: formatCurrency(stats.avgVoucherAmount),
              color: AppColors.emerald600,
            ),
            _InsightRow(
              icon: Icons.arrow_upward_rounded,
              label: 'Highest Invoice',
              value: formatCurrency(stats.maxVoucherAmount),
              color: const Color(0xFF3B82F6),
            ),
            _InsightRow(
              icon: Icons.arrow_downward_rounded,
              label: 'Lowest Invoice',
              value: stats.minVoucherAmount == 0
                  ? '—'
                  : formatCurrency(stats.minVoucherAmount),
              color: const Color(0xFFF59E0B),
            ),
            _InsightRow(
              icon: Icons.business_outlined,
              label: 'Top Department',
              value: stats.topDept,
              color: AppColors.indigo400,
            ),
            _InsightRow(
              icon: Icons.check_circle_outline,
              label: 'Finalized',
              value:
                  '${stats.savedCount} / ${stats.totalVouchers}',
              color: AppColors.emerald600,
            ),
            _InsightRow(
              icon: Icons.pending_outlined,
              label: 'Pending Drafts',
              value: '${stats.draftCount}',
              color: const Color(0xFFF59E0B),
            ),
          ],
        ),
      );
}

class _InsightRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InsightRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate400)),
          ),
          Text(value,
              style: AppTextStyles.smallMedium.copyWith(
                  color: AppColors.slate200,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Row — Recent Vouchers + Employee Breakdown
// ─────────────────────────────────────────────────────────────────────────────
class _BottomRow extends StatelessWidget {
  final _DashStats stats;
  final List<VoucherModel> vouchers;
  final VoidCallback onAddEmployee;

  const _BottomRow({
    required this.stats,
    required this.vouchers,
    required this.onAddEmployee,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, c) {
          if (c.maxWidth < 760) {
            return Column(children: [
              _RecentVouchersPanel(vouchers: vouchers),
              const SizedBox(height: 14),
              _EmployeeBreakdownPanel(
                  stats: stats, onAdd: onAddEmployee),
            ]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  flex: 3,
                  child: _RecentVouchersPanel(vouchers: vouchers)),
              const SizedBox(width: 14),
              Expanded(
                  flex: 2,
                  child: _EmployeeBreakdownPanel(
                      stats: stats, onAdd: onAddEmployee)),
            ],
          );
        },
      );
}

// Recent vouchers with edit support
class _RecentVouchersPanel extends StatelessWidget {
  final List<VoucherModel> vouchers;
  const _RecentVouchersPanel({required this.vouchers});

  void _loadIntoBuilder(BuildContext context, VoucherModel v) {
    VoucherNotifier.instance.update((_) => v);
    context.go('/vouchers');
  }

  void _editVoucher(BuildContext context, VoucherModel v) {
    final hasWork = VoucherNotifier.instance.current.rows.isNotEmpty ||
        VoucherNotifier.instance.current.title.isNotEmpty;

    if (!hasWork) {
      _loadIntoBuilder(context, v);
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Overwrite Current Draft?'),
        content: const Text(
            'The Voucher Builder has unsaved work. Loading this will replace it.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dc, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.indigo600),
              child: const Text('Load Invoice')),
        ],
      ),
    ).then((ok) {
      if (ok == true && context.mounted) _loadIntoBuilder(context, v);
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.history_outlined,
                  size: 16, color: AppColors.indigo400),
              const SizedBox(width: 8),
              Text('Recent Vouchers',
                  style: AppTextStyles.h4
                      .copyWith(color: Colors.white)),
              const Spacer(),
              TextButton(
                onPressed: () => context.go('/invoices'),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 0),
                    tapTargetSize:
                        MaterialTapTargetSize.shrinkWrap),
                child: Text('View all',
                    style: AppTextStyles.small.copyWith(
                        color: AppColors.indigo400)),
              ),
            ]),
            const SizedBox(height: 16),
            if (vouchers.isEmpty)
              _EmptyState(
                icon: Icons.description_outlined,
                message: 'No vouchers yet',
                sub: 'Create one from the Voucher screen',
              )
            else
              ...vouchers.take(6).map((v) => _VoucherRow(
                    voucher: v,
                    onTap: () => _editVoucher(context, v),
                  )),
          ],
        ),
      );
}

class _VoucherRow extends StatefulWidget {
  final VoucherModel voucher;
  final VoidCallback onTap;
  const _VoucherRow({required this.voucher, required this.onTap});
  @override
  State<_VoucherRow> createState() => _VoucherRowState();
}

class _VoucherRowState extends State<_VoucherRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final saved = widget.voucher.status == VoucherStatus.saved;
    String displayDate = widget.voucher.date;
    try {
      displayDate =
          DateFormat('dd MMM yy').format(DateTime.parse(widget.voucher.date));
    } catch (_) {}

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.indigo600.withOpacity(0.08)
                : AppColors.slate800.withOpacity(0.4),
            border: Border.all(
                color: _hovered
                    ? AppColors.indigo600.withOpacity(0.3)
                    : AppColors.slate700.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: saved
                    ? AppColors.emerald600
                    : const Color(0xFFF59E0B),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.voucher.title.isEmpty
                        ? '(Untitled)'
                        : widget.voucher.title,
                    style: AppTextStyles.smallMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$displayDate · ${widget.voucher.deptCode}',
                    style: AppTextStyles.small
                        .copyWith(color: AppColors.slate500),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatCurrency(widget.voucher.finalTotal),
                  style: AppTextStyles.smallMedium.copyWith(
                      color: AppColors.slate200,
                      fontWeight: FontWeight.w600),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: saved
                        ? AppColors.emerald700.withOpacity(0.2)
                        : const Color(0xFFF59E0B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.voucher.status.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: saved
                          ? AppColors.emerald600
                          : const Color(0xFFF59E0B),
                    ),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

// Employee breakdown
class _EmployeeBreakdownPanel extends StatelessWidget {
  final _DashStats stats;
  final VoidCallback onAdd;
  const _EmployeeBreakdownPanel(
      {required this.stats, required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.slate900,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: AppColors.slate700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.groups_outlined,
                  size: 16, color: AppColors.indigo400),
              const SizedBox(width: 8),
              Text('Workforce',
                  style: AppTextStyles.h4
                      .copyWith(color: Colors.white)),
              const Spacer(),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.indigo600.withOpacity(0.15),
                    border: Border.all(
                        color: AppColors.indigo600.withOpacity(0.3)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add,
                          size: 12, color: AppColors.indigo400),
                      const SizedBox(width: 4),
                      Text('Add',
                          style: AppTextStyles.small.copyWith(
                              color: AppColors.indigo400)),
                    ],
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Dept breakdown bars
            Text('By Department',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.slate500)),
            const SizedBox(height: 10),
            if (stats.byCode.isEmpty)
              Text('No employees',
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate500))
            else
              ...stats.byCode.entries
                  .take(5)
                  .map((e) => _BreakdownBar(
                        label: e.key,
                        count: e.value,
                        total: stats.totalEmployees,
                        color: _codeColor(e.key),
                      )),

            const SizedBox(height: 14),
            const Divider(color: AppColors.slate800, height: 1),
            const SizedBox(height: 14),

            // Gender + zone mini grid
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'Male',
                  value: '${stats.maleCount}',
                  icon: Icons.male,
                  color: const Color(0xFF3B82F6),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniStat(
                  label: 'Female',
                  value: '${stats.femaleCount}',
                  icon: Icons.female,
                  color: const Color(0xFFEC4899),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            if (stats.byZone.isNotEmpty)
              Row(
                children: stats.byZone.entries
                    .take(4)
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.slate800,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppColors.slate700),
                            ),
                            child: Text(
                              '${e.key} ${e.value}',
                              style: AppTextStyles.small.copyWith(
                                  color: AppColors.slate400,
                                  fontSize: 10),
                            ),
                          ),
                        ))
                    .toList(),
              ),
          ],
        ),
      );

  static Color _codeColor(String code) {
    switch (code) {
      case 'F&B':
        return AppColors.indigo500;
      case 'I&L':
        return AppColors.emerald600;
      case 'P&S':
        return const Color(0xFFF59E0B);
      case 'A&P':
        return const Color(0xFFEC4899);
      default:
        return AppColors.slate500;
    }
  }
}

class _BreakdownBar extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _BreakdownBar(
      {required this.label,
      required this.count,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label,
                style: AppTextStyles.small
                    .copyWith(color: AppColors.slate300)),
            const Spacer(),
            Text('$count',
                style: AppTextStyles.small.copyWith(
                    color: AppColors.slate400,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: AppColors.slate800,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MiniStat(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.slate800.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: AppColors.slate700.withOpacity(0.5)),
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white)),
              Text(label,
                  style: AppTextStyles.small
                      .copyWith(color: AppColors.slate500)),
            ],
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String sub;

  const _EmptyState(
      {required this.icon, required this.message, required this.sub});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: AppColors.slate700),
              const SizedBox(height: 8),
              Text(message,
                  style: AppTextStyles.smallMedium
                      .copyWith(color: AppColors.slate500)),
              Text(sub,
                  style: AppTextStyles.small
                      .copyWith(
                          color: AppColors.slate600, fontSize: 11)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeleton loading (kept from original, adapted to dark theme)
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: SkeletonPulse(
          child: Column(
            children: [
              // Banner
              Container(
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.slate800,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                ),
              ),
              const SizedBox(height: 20),
              // 4 metric cards
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.9,
                children: List.generate(
                  4,
                  (_) => Container(
                    decoration: BoxDecoration(
                      color: AppColors.slate800,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusMd),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 260,
                      decoration: BoxDecoration(
                        color: AppColors.slate800,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: Container(
                      height: 260,
                      decoration: BoxDecoration(
                        color: AppColors.slate800,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
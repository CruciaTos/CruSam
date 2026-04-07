import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/models/voucher_model.dart';
import '../notifiers/dashboard_notifier.dart';

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
      if (_notifier.isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      final totalInvoiced = _notifier.vouchers
          .fold(0.0, (acc, v) => acc + v.finalTotal);

      return SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatsRow(
              employeeCount: _notifier.employees.length,
              voucherCount: _notifier.vouchers.length,
              totalInvoiced: totalInvoiced,
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _RecentVouchers(vouchers: _notifier.vouchers)),
                const SizedBox(width: AppSpacing.xl),
                const Expanded(child: _QuickActions()),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class _StatsRow extends StatelessWidget {
  final int employeeCount;
  final int voucherCount;
  final double totalInvoiced;
  const _StatsRow({required this.employeeCount, required this.voucherCount, required this.totalInvoiced});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (ctx, constraints) {
      final isWide = constraints.maxWidth > 700;
      final cards = [
        StatCard(label: 'Total Employees', value: employeeCount.toString(),
            icon: Icons.people_outline, iconColor: AppColors.blue600, iconBg: AppColors.blue50),
        StatCard(label: 'Active Vouchers', value: voucherCount.toString(),
            icon: Icons.description_outlined, iconColor: AppColors.indigo600, iconBg: AppColors.indigo50),
        StatCard(label: 'Total Invoiced', value: formatCurrency(totalInvoiced),
            icon: Icons.receipt_outlined, iconColor: AppColors.emerald600, iconBg: AppColors.emerald50),
      ];
      if (isWide) {
        return Row(
          children: cards.expand((c) => [Expanded(child: c), const SizedBox(width: AppSpacing.lg)]).toList()..removeLast(),
        );
      }
      return Column(children: cards.map((c) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: c)).toList());
    },
  );
}

class _RecentVouchers extends StatelessWidget {
  final List<VoucherModel> vouchers;
  const _RecentVouchers({required this.vouchers});

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Recent Vouchers', style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.xxl),
        if (vouchers.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Column(children: [
                Icon(Icons.description_outlined, size: 48, color: AppColors.slate300),
                const SizedBox(height: 8),
                Text('No vouchers created yet', style: AppTextStyles.small),
              ]),
            ),
          )
        else
          ...vouchers.take(5).map((v) => _VoucherTile(voucher: v)),
      ],
    ),
  );
}

class _VoucherTile extends StatelessWidget {
  final VoucherModel voucher;
  const _VoucherTile({required this.voucher});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slate100))),
    child: Row(
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(voucher.title.isEmpty ? '(Untitled)' : voucher.title, style: AppTextStyles.bodyMedium),
            Text('${voucher.date} • ${voucher.deptCode}', style: AppTextStyles.small),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(formatCurrency(voucher.finalTotal), style: AppTextStyles.bodySemi),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: voucher.status == VoucherStatus.saved ? AppColors.emerald100 : AppColors.amber100,
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              voucher.status.name.toUpperCase(),
              style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: voucher.status == VoucherStatus.saved ? AppColors.emerald700 : AppColors.amber700,
              ),
            ),
          ),
        ]),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Actions', style: AppTextStyles.h4),
        const SizedBox(height: AppSpacing.md),
        GridView.count(
          crossAxisCount: 2, shrinkWrap: true,
          crossAxisSpacing: AppSpacing.md, mainAxisSpacing: AppSpacing.md,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _QuickActionTile(icon: Icons.add, label: 'New Voucher', onTap: () {}),
            _QuickActionTile(icon: Icons.person_add_outlined, label: 'Add Employee', onTap: () {}),
          ],
        ),
      ],
    ),
  );
}

class _QuickActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.slate200),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: AppColors.slate400, size: 24),
        const SizedBox(height: 8),
        Text(label, style: AppTextStyles.smallMedium.copyWith(color: AppColors.slate600),
            textAlign: TextAlign.center),
      ]),
    ),
  );
}
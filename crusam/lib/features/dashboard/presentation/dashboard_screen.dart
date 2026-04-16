import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/skeleton.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../data/models/voucher_model.dart';
import '../../master_data/presentation/employee_form_screen.dart';
import '../notifiers/dashboard_notifier.dart';
import 'package:crusam/features/vouchers/notifiers/voucher_notifier.dart';

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
            return const _DashboardSkeleton();
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
                    Expanded(
                        child: _RecentVouchers(vouchers: _notifier.vouchers)),
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

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: SkeletonPulse(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 700;
                  final cards = const [
                    _SkeletonStatCard(),
                    _SkeletonStatCard(),
                    _SkeletonStatCard(),
                  ];

                  if (isWide) {
                    return Row(
                      children: cards
                          .expand((c) => [
                                Expanded(child: c),
                                const SizedBox(width: AppSpacing.lg),
                              ])
                          .toList()
                        ..removeLast(),
                    );
                  }

                  return Column(
                    children: cards
                        .map(
                          (c) => const Padding(
                            padding: EdgeInsets.only(bottom: AppSpacing.md),
                            child: _SkeletonStatCard(),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final isWide = constraints.maxWidth > 900;
                  if (isWide) {
                    return const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _SkeletonPanel(lines: 5)),
                        SizedBox(width: AppSpacing.xl),
                        Expanded(child: _SkeletonPanel(lines: 4)),
                      ],
                    );
                  }

                  return const Column(
                    children: [
                      _SkeletonPanel(lines: 5),
                      SizedBox(height: AppSpacing.lg),
                      _SkeletonPanel(lines: 4),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
}

class _SkeletonStatCard extends StatelessWidget {
  const _SkeletonStatCard();

  @override
  Widget build(BuildContext context) => const AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonCircle(size: 28),
                SizedBox(width: AppSpacing.sm),
                Expanded(child: SkeletonBox(height: 12)),
              ],
            ),
            SizedBox(height: AppSpacing.md),
            SkeletonBox(width: 110, height: 22),
          ],
        ),
      );
}

class _SkeletonPanel extends StatelessWidget {
  final int lines;
  const _SkeletonPanel({required this.lines});

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 180, height: 16),
            const SizedBox(height: AppSpacing.lg),
            ...List.generate(
              lines,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    const SkeletonCircle(),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SkeletonBox(
                        height: 12,
                        width: index.isEven ? null : 180,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _StatsRow extends StatelessWidget {
  final int employeeCount;
  final int voucherCount;
  final double totalInvoiced;
  const _StatsRow(
      {required this.employeeCount,
      required this.voucherCount,
      required this.totalInvoiced});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, constraints) {
          final isWide = constraints.maxWidth > 700;
          final cards = [
            StatCard(
                label: 'Total Employees',
                value: employeeCount.toString(),
                icon: Icons.people_outline,
                iconColor: AppColors.blue600,
                iconBg: AppColors.blue50),
            StatCard(
                label: 'Active Vouchers',
                value: voucherCount.toString(),
                icon: Icons.description_outlined,
                iconColor: AppColors.indigo600,
                iconBg: AppColors.indigo50),
            StatCard(
                label: 'Total Invoiced',
                value: formatCurrency(totalInvoiced),
                icon: Icons.receipt_outlined,
                iconColor: AppColors.emerald600,
                iconBg: AppColors.emerald50),
          ];
          if (isWide) {
            return Row(
              children: cards
                  .expand((c) => [
                        Expanded(child: c),
                        const SizedBox(width: AppSpacing.lg)
                      ])
                  .toList()
                ..removeLast(),
            );
          }
          return Column(
            children: cards
                .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: c))
                .toList(),
          );
        },
      );
}

class _RecentVouchers extends StatelessWidget {
  final List<VoucherModel> vouchers;
  const _RecentVouchers({required this.vouchers});

  void _openVoucherForEdit(BuildContext context, VoucherModel voucher) {
    final hasUnsavedWork = VoucherNotifier.instance.current.rows.isNotEmpty ||
        VoucherNotifier.instance.current.title.isNotEmpty;

    if (!hasUnsavedWork) {
      _loadIntoBuilder(context, voucher);
      return;
    }

    showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Overwrite Current Draft?'),
        content: const Text(
          'The Voucher Builder has unsaved work.\n'
          'Loading this invoice will replace it. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.indigo600),
            child: const Text('Load Invoice'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && context.mounted) {
        _loadIntoBuilder(context, voucher);
      }
    });
  }

  void _loadIntoBuilder(BuildContext context, VoucherModel voucher) {
    VoucherNotifier.instance.update((_) => voucher);
    context.go('/vouchers');
  }

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
                    Icon(Icons.description_outlined,
                        size: 48, color: AppColors.slate300),
                    const SizedBox(height: 8),
                    Text('No vouchers created yet', style: AppTextStyles.small),
                  ]),
                ),
              )
            else
              ...vouchers.take(5).map((v) {
                final isLast = v == vouchers.last;
                return Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: _VoucherTile(
                    key: ValueKey(v.id),
                    voucher: v,
                    onTap: () => _openVoucherForEdit(context, v),
                  ),
                );
              }).toList(),
          ],
        ),
      );
}

class _VoucherTile extends StatefulWidget {
  final VoucherModel voucher;
  final VoidCallback onTap;
  const _VoucherTile({
    super.key,
    required this.voucher,
    required this.onTap,
  });

  @override
  State<_VoucherTile> createState() => _VoucherTileState();
}

class _VoucherTileState extends State<_VoucherTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    String displayDate;
    try {
      final dateTime = DateTime.parse(widget.voucher.date);
      displayDate = DateFormat('dd MMM yyyy').format(dateTime);
    } catch (_) {
      displayDate = widget.voucher.date;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            // No background color - just glow
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              bottom: BorderSide(
                color: _hovered
                    ? AppColors.indigo400
                    : AppColors.slate100,
                width: _hovered ? 2 : 1,
              ),
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppColors.indigo600.withOpacity(0.15),
                      blurRadius: 12,
                      spreadRadius: 2,
                      offset: const Offset(0, 0),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.voucher.title.isEmpty
                          ? '(Untitled)'
                          : widget.voucher.title,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: _hovered ? AppColors.indigo700 : null,
                        fontWeight: _hovered ? FontWeight.w600 : null,
                      ),
                    ),
                    Text(
                      '$displayDate • ${widget.voucher.deptCode}',
                      style: AppTextStyles.small.copyWith(
                        color: _hovered ? AppColors.indigo600 : null,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(widget.voucher.finalTotal),
                    style: AppTextStyles.bodySemi.copyWith(
                      color: _hovered ? AppColors.indigo700 : null,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.voucher.status == VoucherStatus.saved
                          ? AppColors.emerald100
                          : AppColors.amber100,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      widget.voucher.status.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: widget.voucher.status == VoucherStatus.saved
                            ? AppColors.emerald700
                            : AppColors.amber700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _QuickActionTile(
                  icon: Icons.add,
                  label: 'New Voucher',
                  onTap: () => context.go('/vouchers'),
                ),
                _QuickActionTile(
                  icon: Icons.person_add_outlined,
                  label: 'Add Employee',
                  onTap: () => _openAddEmployee(context),
                ),
              ],
            ),
          ],
        ),
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

class _QuickActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickActionTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  State<_QuickActionTile> createState() => _QuickActionTileState();
}

class _QuickActionTileState extends State<_QuickActionTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          hoverColor: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(
                color: _hovered ? AppColors.indigo400 : AppColors.slate200,
                width: _hovered ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: AppColors.indigo600.withOpacity(0.15),
                        blurRadius: 12,
                        spreadRadius: 2,
                        offset: const Offset(0, 0),
                      )
                    ]
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.icon,
                  color: _hovered ? AppColors.indigo600 : AppColors.slate400,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  widget.label,
                  style: AppTextStyles.smallMedium.copyWith(
                    color: _hovered ? AppColors.indigo600 : AppColors.slate600,
                    fontWeight: _hovered ? FontWeight.w600 : null,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
}
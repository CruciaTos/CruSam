import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const AppCard({super.key, required this.child, this.padding, this.color});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? AppColors.white,
      border: Border.all(color: AppColors.slate200),
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      boxShadow: const [BoxShadow(color: Color(0x08000000), blurRadius: 4, offset: Offset(0, 1))],
    ),
    padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
    child: child,
  );
}
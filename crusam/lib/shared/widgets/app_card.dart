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
      border: Border.all(color: const Color.fromARGB(255, 21, 39, 81), width: 0.5),
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      
    ),
    padding: padding ?? const EdgeInsets.all(AppSpacing.cardPadding),
    child: child,
  );
}
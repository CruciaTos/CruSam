import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  static const _base = TextStyle(fontFamily: 'sans-serif', package: null);

  static final h3 = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.slate900);
  static final h4 = _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.slate900);

  static final body        = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.slate900);
  static final bodyMedium  = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.slate900);
  static final bodySemi    = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.slate900);

  static final small       = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.slate500);
  static final smallMedium = _base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.slate500);

  static final label       = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate500, letterSpacing: 0.6);

  static final mono        = const TextStyle(fontFamily: 'monospace', fontSize: 13, color: AppColors.slate600);
  static final monoSm      = const TextStyle(fontFamily: 'monospace', fontSize: 11, color: AppColors.slate500);

  static final navLabel    = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.slate400);
  static final sidebarBrand = _base.copyWith(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.white, letterSpacing: -0.3);

  static final grandTotal  = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.indigo400);
  static final amountWords = _base.copyWith(fontSize: 10, fontWeight: FontWeight.w400, color: AppColors.slate400, fontStyle: FontStyle.italic);
}
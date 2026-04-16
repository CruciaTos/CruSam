import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class AvatarWidget extends StatelessWidget {
  final String displayName;
  final String? avatarPath;
  final double size;
  final List<Color>? gradientColors;
  final VoidCallback? onTap;
  final bool showBorder;
  final Color? borderColor;
  final double borderWidth;

  const AvatarWidget({
    super.key,
    required this.displayName,
    this.avatarPath,
    this.size = 48,
    this.gradientColors,
    this.onTap,
    this.showBorder = false,
    this.borderColor,
    this.borderWidth = 2.5,
  });

  String get _initials {
    final parts = displayName.trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  ImageProvider? get _image {
    if (avatarPath == null || avatarPath!.isEmpty) return null;
    try {
      final f = File(avatarPath!);
      if (f.existsSync()) return FileImage(f);
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colors = gradientColors ??
        [AppColors.indigo600, const Color(0xFF7C3AED)];
    final img = _image;

    Widget circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: img == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              )
            : null,
        image: img != null
            ? DecorationImage(image: img, fit: BoxFit.cover)
            : null,
        border: showBorder
            ? Border.all(
                color: borderColor ?? AppColors.indigo400,
                width: borderWidth,
              )
            : null,
      ),
      child: img == null
          ? Center(
              child: Text(
                _initials,
                style: TextStyle(
                  fontSize: size * 0.36,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            )
          : null,
    );

    if (onTap == null) return circle;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: circle),
    );
  }
}
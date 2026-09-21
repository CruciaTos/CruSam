// lib/shared/widgets/min_height_scroll.dart
//
// Gives [child] at least [minHeight]: when the space is shorter (a small or
// half-height window), the child keeps [minHeight] and becomes vertically
// scrollable instead of overflowing. The widget tree is the same either way,
// so screens keep their state when the window crosses the threshold.

import 'dart:math' as math;

import 'package:flutter/material.dart';

class MinHeightScroll extends StatelessWidget {
  const MinHeightScroll({super.key, required this.minHeight, required this.child});

  final double minHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final short = constraints.maxHeight < minHeight;
          return SingleChildScrollView(
            primary: false,
            physics: short ? null : const NeverScrollableScrollPhysics(),
            child: SizedBox(
              height: math.max(constraints.maxHeight, minHeight),
              child: child,
            ),
          );
        },
      );
}

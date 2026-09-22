// lib/core/window/window_mode_transition.dart
//
// Wraps the whole app: while WindowModeController switches between the full
// and the compact window, the content fades out (quickly), the window glides,
// and the new layout fades in with a slight scale-up — so the relayout a
// native resize causes is never seen.

import 'package:flutter/material.dart';

import 'window_mode_controller.dart';

class WindowModeTransition extends StatelessWidget {
  final Widget child;
  const WindowModeTransition({super.key, required this.child});

  /// The shell's background, shown under the fade.
  static const _backdrop = Color(0xFF0B1120);

  @override
  Widget build(BuildContext context) {
    final c = WindowModeController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final veiled = c.veiled;
        final duration =
            veiled ? WindowModeController.fadeOut : WindowModeController.fadeIn;
        final curve = veiled ? Curves.easeOut : Curves.easeOutCubic;
        return ColoredBox(
          color: _backdrop,
          child: AnimatedOpacity(
            opacity: veiled ? 0 : 1,
            duration: duration,
            curve: curve,
            child: AnimatedScale(
              scale: veiled ? 0.975 : 1,
              duration: duration,
              curve: curve,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

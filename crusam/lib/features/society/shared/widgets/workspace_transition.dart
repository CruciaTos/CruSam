import 'dart:async';

import 'package:flutter/material.dart';
import 'package:crusam/core/theme/app_colors.dart';

const Color _crusamAccent = Color(0xFF3B82F6);
const Color _darkBase = Color(0xFF0F172A);

bool _transitionRunning = false;

/// Plays a full-window, 4 second workspace switch animation.
///
/// [onMidpoint] runs once while the screen is fully covered; use it to
/// navigate. Taps during playback are ignored.
Future<void> playWorkspaceTransition(
  BuildContext context, {
  required bool toSociety,
  required VoidCallback onMidpoint,
}) async {
  if (_transitionRunning) return;
  _transitionRunning = true;

  final finished = Completer<void>();
  OverlayEntry? entry;
  try {
    final overlay = Overlay.of(context, rootOverlay: true);
    entry = OverlayEntry(
      builder: (_) => _WorkspaceTransitionCover(
        toSociety: toSociety,
        onMidpoint: onMidpoint,
        onFinished: () {
          if (!finished.isCompleted) finished.complete();
        },
      ),
    );
    overlay.insert(entry);
    await finished.future;
  } finally {
    if (entry != null && entry.mounted) entry.remove();
    _transitionRunning = false;
  }
}

class _WorkspaceSpec {
  final String name;
  final IconData icon;
  final Color accent;

  const _WorkspaceSpec({
    required this.name,
    required this.icon,
    required this.accent,
  });
}

const _WorkspaceSpec _crusamSpec = _WorkspaceSpec(
  name: 'CruSam',
  icon: Icons.dashboard_outlined,
  accent: _crusamAccent,
);

const _WorkspaceSpec _societySpec = _WorkspaceSpec(
  name: 'Society',
  icon: Icons.apartment_outlined,
  accent: AppColors.amber700,
);

class _WorkspaceTransitionCover extends StatefulWidget {
  final bool toSociety;
  final VoidCallback onMidpoint;
  final VoidCallback onFinished;

  const _WorkspaceTransitionCover({
    required this.toSociety,
    required this.onMidpoint,
    required this.onFinished,
  });

  @override
  State<_WorkspaceTransitionCover> createState() =>
      _WorkspaceTransitionCoverState();
}

class _WorkspaceTransitionCoverState extends State<_WorkspaceTransitionCover>
    with SingleTickerProviderStateMixin {
  static const double _midpoint = 0.475;

  late final AnimationController _controller;
  bool _midpointFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _controller.addListener(_checkMidpoint);
    _controller.forward().whenComplete(widget.onFinished);
  }

  void _checkMidpoint() {
    if (_midpointFired || _controller.value < _midpoint) return;
    _midpointFired = true;
    try {
      widget.onMidpoint();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'workspace transition',
      ));
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_checkMidpoint);
    _controller.dispose();
    widget.onFinished();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final to = widget.toSociety ? _societySpec : _crusamSpec;
    final from = widget.toSociety ? _crusamSpec : _societySpec;

    return Positioned.fill(
      child: AbsorbPointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            final reveal = const Interval(0.0, 0.25,
                    curve: Curves.easeInOutCubic)
                .transform(t);
            final exit = const Interval(0.75, 1.0,
                    curve: Curves.easeInOutCubic)
                .transform(t);
            final contentOut = const Interval(0.68, 0.78).transform(t);
            final contentIn = const Interval(0.22, 0.30).transform(t);
            final outT = const Interval(0.25, 0.45, curve: Curves.easeInCubic)
                .transform(t);
            final inT = const Interval(0.40, 0.60, curve: Curves.easeOutCubic)
                .transform(t);
            final lineT = const Interval(0.40, 0.72, curve: Curves.easeInOut)
                .transform(t);
            final captionT = const Interval(0.45, 0.62, curve: Curves.easeOut)
                .transform(t);

            return Opacity(
              opacity: 1,
              child: CustomPaint(
                painter: _RevealPainter(
                  enter: reveal,
                  exit: exit,
                  accent: to.accent,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Center(
                    child: Opacity(
                      opacity: contentIn * (1 - contentOut),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 320,
                            height: 120,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Opacity(
                                  opacity: 1 - outT,
                                  child: Transform.translate(
                                    offset: Offset(0, -28 * outT),
                                    child: _WorkspaceLabel(spec: from),
                                  ),
                                ),
                                Opacity(
                                  opacity: inT,
                                  child: Transform.scale(
                                    scale: 0.85 + 0.15 * inT,
                                    child: _WorkspaceLabel(spec: to),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: 200,
                            height: 3,
                            alignment: Alignment.centerLeft,
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              widthFactor: lineT,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Opacity(
                            opacity: captionT,
                            child: Text(
                              'Opening ${to.name} workspace',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Colors.white70,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _WorkspaceLabel extends StatelessWidget {
  final _WorkspaceSpec spec;

  const _WorkspaceLabel({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(spec.icon, size: 52, color: Colors.white),
        const SizedBox(height: 8),
        Text(
          spec.name,
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

/// Radial bloom from the centre of the window. [enter] grows a glowing,
/// soft-edged disc of colour until it covers everything; [exit] then opens an
/// iris hole from the centre that widens to reveal the new screen.
class _RevealPainter extends CustomPainter {
  final double enter;
  final double exit;
  final Color accent;

  const _RevealPainter({
    required this.enter,
    required this.exit,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (enter <= 0 || exit >= 1) return;
    const band = 0.4;
    final rect = Offset.zero & size;
    final radius = Offset(size.width, size.height).distance / 2 * 1.05;
    final glow = Color.lerp(_darkBase, accent, 0.85) ?? accent;
    double c(double v) => v.clamp(0.0, 1.0);

    final RadialGradient gradient;
    if (exit <= 0) {
      final lead = enter * (1 + band);
      gradient = RadialGradient(
        radius: 1.0,
        colors: [_darkBase, _darkBase, glow, glow.withValues(alpha: 0)],
        stops: [0.0, c(lead - band), c(lead - band * 0.3), c(lead)],
      );
    } else {
      final lead = exit * (1 + band);
      gradient = RadialGradient(
        radius: 1.0,
        colors: [glow.withValues(alpha: 0), glow, _darkBase],
        stops: [c(lead - band), c(lead - band * 0.3), c(lead)],
      );
    }
    final shader = gradient.createShader(
      Rect.fromCircle(center: rect.center, radius: radius),
    );
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_RevealPainter old) =>
      old.enter != enter || old.exit != exit || old.accent != accent;
}

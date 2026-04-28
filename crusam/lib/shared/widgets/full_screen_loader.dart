// lib/shared/widgets/full_screen_loader.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

// ── Public API ────────────────────────────────────────────────────────────────

void showLoader(BuildContext context, {String? message}) =>
    _FullScreenLoader._show(context, message: message);

void hideLoader(BuildContext context) => _FullScreenLoader._hide();

// ── Internal singleton ────────────────────────────────────────────────────────

class _FullScreenLoader {
  _FullScreenLoader._();

  static OverlayEntry? _entry;
  static _LoaderController? _ctrl;

  static void _show(BuildContext context, {String? message}) {
    // Anti-stack guard: update message instead of inserting a second overlay.
    if (_entry != null) {
      _ctrl?.updateMessage(message);
      return;
    }
    final ctrl = _LoaderController(message);
    _ctrl = ctrl;
    _entry = OverlayEntry(
      builder: (_) => _LoaderWidget(controller: ctrl),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  static void _hide() {
    _entry?.remove();
    _entry = null;
    _ctrl?.dispose();
    _ctrl = null;
  }
}

// ── Dynamic-message controller ────────────────────────────────────────────────

class _LoaderController extends ChangeNotifier {
  String? _message;
  _LoaderController(this._message);

  String? get message => _message;

  void updateMessage(String? msg) {
    if (_message == msg) return;
    _message = msg;
    notifyListeners();
  }
}

// ── Overlay widget ────────────────────────────────────────────────────────────

class _LoaderWidget extends StatefulWidget {
  final _LoaderController controller;
  const _LoaderWidget({super.key, required this.controller});

  @override
  State<_LoaderWidget> createState() => _LoaderWidgetState();
}

class _LoaderWidgetState extends State<_LoaderWidget>
    with TickerProviderStateMixin {
  // ── Animation controllers ────────────────────────────────────────────────
  late final AnimationController _fadeCtrl;   // backdrop fade-in
  late final AnimationController _orbitCtrl;  // main orbital loop
  late final AnimationController _pulseCtrl;  // inner core pulse
  late final AnimationController _glowCtrl;   // outer ripple glow

  // ── Derived animations ───────────────────────────────────────────────────
  late final Animation<double> _fadeAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    // Backdrop + card fade-in — short, snappy
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);

    // Main orbital spin — runs forever, drives the comet dots
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();

    // Core pulse — breathes in/out
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    // Ripple glow — slower, ethereal
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _glowAnim = CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut);

    widget.controller.addListener(_onMessageChanged);
  }

  // Only rebuilds when the message text changes — NOT on every anim frame
  void _onMessageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onMessageChanged);
    _fadeCtrl.dispose();
    _orbitCtrl.dispose();
    _pulseCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // blocks back navigation while loading
      child: FadeTransition(
        opacity: _fadeAnim,
        child: Material(
          color: Colors.transparent,
          child: Container(
            color: const Color(0xCC0B1120), // dark slate @ ~80 %
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 44, vertical: 36),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF334155),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.55),
                    blurRadius: 48,
                    offset: const Offset(0, 14),
                  ),
                  // Indigo ambient glow on the card itself
                  BoxShadow(
                    color: const Color(0xFF4F46E5).withOpacity(0.12),
                    blurRadius: 64,
                    spreadRadius: -8,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Animation canvas ─────────────────────────────────────
                  // RepaintBoundary promotes this subtree to its own GPU
                  // compositing layer. The painter ticks at full refresh rate
                  // completely independently of any widget rebuilds above.
                  RepaintBoundary(
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: AnimatedBuilder(
                        // Merge all ticking listenable into one subscription.
                        animation: Listenable.merge(
                          [_orbitCtrl, _pulseAnim, _glowAnim],
                        ),
                        // builder receives NO child — the painter owns drawing.
                        builder: (_, __) => CustomPaint(
                          painter: _OrbitPainter(
                            orbitProgress: _orbitCtrl.value,
                            pulseProgress: _pulseAnim.value,
                            glowProgress: _glowAnim.value,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ── Message label ────────────────────────────────────────
                  if (widget.controller.message != null) ...[
                    const SizedBox(height: 22),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: Text(
                        widget.controller.message!,
                        key: ValueKey(widget.controller.message),
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFCBD5E1),
                          decoration: TextDecoration.none,
                          letterSpacing: 0.15,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Custom orbital painter ────────────────────────────────────────────────────
//
// All drawing happens here, on the GPU raster thread via Skia/Impeller.
// Zero widget tree involvement per frame — pure canvas ops.
//
// Layout:
//   • Three concentric orbit rings at radii 90 %, 60 %, 32 % of half-width
//   • Each ring carries one dot with a comet-tail of 10 ghost dots
//   • Outer  → indigo-600,  clockwise,          1 revolution / cycle
//   • Middle → violet-600,  counter-clockwise,  1.5× speed
//   • Inner  → sky-500,     clockwise,          0.65× speed, phase-shifted
//   • Centre → white↔indigo radial gradient, pulses with _pulseProgress
//   • Ripple → expanding ring driven by _glowProgress

class _OrbitPainter extends CustomPainter {
  final double orbitProgress; // 0.0 → 1.0, loops
  final double pulseProgress; // 0.0 → 1.0, ping-pong (eased)
  final double glowProgress;  // 0.0 → 1.0, loops

  const _OrbitPainter({
    required this.orbitProgress,
    required this.pulseProgress,
    required this.glowProgress,
  });

  // ── Palette ────────────────────────────────────────────────────────────────
  static const Color _indigo  = Color(0xFF4F46E5); // outer dot
  static const Color _violet  = Color(0xFF7C3AED); // middle dot
  static const Color _sky     = Color(0xFF0EA5E9); // inner dot

  // ── shouldRepaint ──────────────────────────────────────────────────────────
  // Only return true when something actually changed — the engine calls paint()
  // only when this is true, saving CPU on unchanged frames.
  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.orbitProgress != orbitProgress ||
      old.pulseProgress != pulseProgress  ||
      old.glowProgress  != glowProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx     = size.width  / 2;
    final cy     = size.height / 2;
    final center = Offset(cx, cy);

    // ── 1. Expanding ripple ring ───────────────────────────────────────────
    _drawRipple(canvas, center, cx);

    // ── 2. Orbit track rings (faint guide circles) ─────────────────────────
    _drawTrack(canvas, center, cx * 0.90);
    _drawTrack(canvas, center, cx * 0.60);
    _drawTrack(canvas, center, cx * 0.32);

    // ── 3. Outer dot — indigo, clockwise, full speed ───────────────────────
    _drawComet(
      canvas, center,
      radius   : cx * 0.90,
      angle    : orbitProgress * math.pi * 2,
      color    : _indigo,
      dotRadius: 5.5,
      tailArc  : 0.55, // radians of tail arc
    );

    // ── 4. Middle dot — violet, counter-clockwise, 1.5× ───────────────────
    _drawComet(
      canvas, center,
      radius   : cx * 0.60,
      angle    : -(orbitProgress * math.pi * 2 * 1.5),
      color    : _violet,
      dotRadius: 4.5,
      tailArc  : 0.5,
    );

    // ── 5. Inner dot — sky, clockwise, 0.65×, phase-shifted ───────────────
    _drawComet(
      canvas, center,
      radius   : cx * 0.32,
      angle    : orbitProgress * math.pi * 2 * 0.65 + math.pi * 0.75,
      color    : _sky,
      dotRadius: 3.5,
      tailArc  : 0.45,
    );

    // ── 6. Centre core ─────────────────────────────────────────────────────
    _drawCore(canvas, center, pulseProgress);
  }

  // ── Ripple ─────────────────────────────────────────────────────────────────
  void _drawRipple(Canvas canvas, Offset center, double maxR) {
    final t       = Curves.easeOut.transform(glowProgress);
    final radius  = 10 + t * maxR * 0.85;
    final opacity = (1 - t) * 0.22;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color       = _indigo.withOpacity(opacity)
        ..maskFilter  = const MaskFilter.blur(BlurStyle.normal, 5),
    );
  }

  // ── Orbit track ────────────────────────────────────────────────────────────
  void _drawTrack(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..color       = const Color(0xFF4F46E5).withOpacity(0.12),
    );
  }

  // ── Comet (dot + tail) ─────────────────────────────────────────────────────
  // Draws a leading dot and N ghost dots fanning back along the orbit arc.
  void _drawComet(
    Canvas canvas,
    Offset center, {
    required double radius,
    required double angle,    // leading dot angle in radians
    required Color  color,
    required double dotRadius,
    required double tailArc,  // how many radians of arc the tail spans
  }) {
    const tailSteps = 12;

    // Tail ghosts — drawn back-to-front so leading dot renders on top
    for (int i = tailSteps; i >= 0; i--) {
      final frac       = i / tailSteps;             // 0 = tip, 1 = tail end
      final tailAngle  = angle - frac * tailArc;    // trailing behind
      final tx         = center.dx + radius * math.cos(tailAngle);
      final ty         = center.dy + radius * math.sin(tailAngle);

      // Opacity and size taper toward the tail end
      final opacity    = math.pow(1 - frac, 2.2).toDouble();
      final r          = dotRadius * (0.35 + 0.65 * (1 - frac));

      canvas.drawCircle(
        Offset(tx, ty),
        r,
        Paint()..color = color.withOpacity(opacity * 0.75),
      );
    }

    // ── Leading dot ──────────────────────────────────────────────────────────
    final lx  = center.dx + radius * math.cos(angle);
    final ly  = center.dy + radius * math.sin(angle);
    final dot = Offset(lx, ly);

    // Soft glow halo
    canvas.drawCircle(
      dot,
      dotRadius * 2.6,
      Paint()
        ..color      = color.withOpacity(0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Solid dot
    canvas.drawCircle(dot, dotRadius, Paint()..color = color);

    // Specular highlight — tiny white glint in the upper-left quadrant
    canvas.drawCircle(
      Offset(lx - dotRadius * 0.28, ly - dotRadius * 0.28),
      dotRadius * 0.32,
      Paint()..color = Colors.white.withOpacity(0.65),
    );
  }

  // ── Centre core ────────────────────────────────────────────────────────────
  void _drawCore(Canvas canvas, Offset center, double pulse) {
    // pulse: 0.0 → 1.0 (eased ping-pong)
    final coreR = 7.5 + pulse * 2.5;

    // Diffuse glow behind the core
    canvas.drawCircle(
      center,
      coreR * 2.8,
      Paint()
        ..color      = _indigo.withOpacity(0.22 + pulse * 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // Core disc — radial gradient from white at centre to indigo at edge
    final shader = RadialGradient(
      colors: [
        Colors.white,
        const Color(0xFF818CF8), // indigo-400
        _indigo,
      ],
      stops: const [0.0, 0.45, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: coreR));

    canvas.drawCircle(center, coreR, Paint()..shader = shader);
  }
}

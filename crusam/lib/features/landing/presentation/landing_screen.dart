import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:particles_network/particles_network.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Landing Screen
// ─────────────────────────────────────────────────────────────────────────────

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  final _scrollCtrl = ScrollController();
  bool _navScrolled = false;

  late final AnimationController _heroCtrl;
  late final Animation<double> _logoFade;
  late final Animation<Offset> _logoSlide;
  late final Animation<double> _textFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _ctaFade;

  @override
  void initState() {
    super.initState();

    _scrollCtrl.addListener(() {
      final scrolled = _scrollCtrl.offset > 40;
      if (scrolled != _navScrolled) setState(() => _navScrolled = scrolled);
    });

    _heroCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));

    _logoFade = CurvedAnimation(
        parent: _heroCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOut));
    _logoSlide = Tween<Offset>(
            begin: const Offset(0, 0.25), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _heroCtrl,
            curve: const Interval(0.0, 0.5, curve: Curves.easeOutCubic)));

    _textFade = CurvedAnimation(
        parent: _heroCtrl,
        curve: const Interval(0.3, 0.75, curve: Curves.easeOut));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _heroCtrl,
            curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic)));

    _ctaFade = CurvedAnimation(
        parent: _heroCtrl,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) => _heroCtrl.forward());
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    _heroCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      body: Stack(
        children: [
          // ── Particle background ──────────────────────────────────────────
          Positioned.fill(
            child: RepaintBoundary(
              child: Container(
                color: const Color(0xFF050B18),
                child: const ParticleNetwork(
                  particleColor: Color(0x556366F1),
                  lineColor: Color(0x1A4F46E5),
                  particleCount: 90,
                  maxSpeed: 0.55,
                  maxSize: 2.0,
                  lineDistance: 130,
                  drawNetwork: true,
                  touchActivation: true,
                  gravityType: GravityType.none,
                  gravityStrength: 0.0,
                ),
              ),
            ),
          ),

          // ── Left-side ambient glow ───────────────────────────────────────
          Positioned(
            left: -80,
            top: 80,
            child: IgnorePointer(
              child: Container(
                width: 700,
                height: 700,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4F46E5).withOpacity(0.07),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Bottom purple glow ───────────────────────────────────────────
          Positioned(
            right: -100,
            top: 300,
            child: IgnorePointer(
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7C3AED).withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Gradient overlay ─────────────────────────────────────────────
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(-0.5, -0.6),
                    radius: 1.4,
                    colors: [Color(0x551E1040), Color(0x00050B18)],
                  ),
                ),
              ),
            ),
          ),

          // ── Scrollable content ───────────────────────────────────────────
          Column(
            children: [
              _NavBar(scrolled: _navScrolled),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeroSection(
                        screenHeight: size.height - 64,
                        logoFade: _logoFade,
                        logoSlide: _logoSlide,
                        textFade: _textFade,
                        textSlide: _textSlide,
                        ctaFade: _ctaFade,
                      ),
                      _FadeInSection(
                        scrollController: _scrollCtrl,
                        child: const _ProblemSolutionSection(),
                      ),
                      _FadeInSection(
                        scrollController: _scrollCtrl,
                        child: const _FeaturesSection(),
                      ),
                      _FadeInSection(
                        scrollController: _scrollCtrl,
                        child: const _StatsSection(),
                      ),
                      _FadeInSection(
                        scrollController: _scrollCtrl,
                        child: const _CtaSection(),
                      ),
                      const _LandingFooter(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Scroll-triggered Fade-In Wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _FadeInSection extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final Duration delay;

  const _FadeInSection({
    required this.child,
    required this.scrollController,
    this.delay = Duration.zero,
  });

  @override
  State<_FadeInSection> createState() => _FadeInSectionState();
}

class _FadeInSectionState extends State<_FadeInSection>
    with SingleTickerProviderStateMixin {
  final _sectionKey = GlobalKey();
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    widget.scrollController.addListener(_checkVisibility);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkVisibility);
    _ctrl.dispose();
    super.dispose();
  }

  void _checkVisibility() {
    if (_triggered || !mounted) return;
    final ctx = _sectionKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(ctx).size.height;
    if (pos.dy < screenH * 0.93) {
      _triggered = true;
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward();
      });
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        key: _sectionKey,
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(position: _slide, child: widget.child),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Nav Bar
// ─────────────────────────────────────────────────────────────────────────────

class _NavBar extends StatelessWidget {
  final bool scrolled;
  const _NavBar({required this.scrolled});

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 64,
        decoration: BoxDecoration(
          color: scrolled ? const Color(0xCC0A0F1E) : Colors.transparent,
          border: scrolled
              ? const Border(
                  bottom: BorderSide(color: Color(0x1AFFFFFF)))
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Row(
          children: [
            // Logo mark
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.indigo600,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text('A',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ),
            const SizedBox(width: 10),
            Text('CRUSAM',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.2,
                )),
            const Spacer(),
            // Nav links
            ...[('Features', '#features'), ('How it Works', '#how'), ('About', '#about')]
                .map((item) => Padding(
                      padding: const EdgeInsets.only(right: 28),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(item.$1,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: const Color(0xFF94A3B8),
                            )),
                      ),
                    )),
            // Sign In (ghost)
            OutlinedButton(
              onPressed: () => context.go('/login'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF94A3B8),
                side: const BorderSide(color: Color(0x2AFFFFFF)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Sign In',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ),
            const SizedBox(width: 10),
            // Primary sticky CTA
            ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.indigo600,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('Get Started',
                  style: GoogleFonts.inter(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Section
// ─────────────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final double screenHeight;
  final Animation<double> logoFade, textFade, ctaFade;
  final Animation<Offset> logoSlide, textSlide;

  const _HeroSection({
    required this.screenHeight,
    required this.logoFade,
    required this.logoSlide,
    required this.textFade,
    required this.textSlide,
    required this.ctaFade,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 1000;

    return SizedBox(
      height: math.max(screenHeight, 600),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 5,
                    child: _HeroContent(
                      logoFade: logoFade,
                      logoSlide: logoSlide,
                      textFade: textFade,
                      textSlide: textSlide,
                      ctaFade: ctaFade,
                    ),
                  ),
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: FadeTransition(
                        opacity: ctaFade,
                        child: const _FloatingMockDashboard(),
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: _HeroContent(
                  logoFade: logoFade,
                  logoSlide: logoSlide,
                  textFade: textFade,
                  textSlide: textSlide,
                  ctaFade: ctaFade,
                  centered: true,
                ),
              ),
      ),
    );
  }
}

// ── Hero Content (left-aligned text block) ────────────────────────────────────

class _HeroContent extends StatelessWidget {
  final Animation<double> logoFade, textFade, ctaFade;
  final Animation<Offset> logoSlide, textSlide;
  final bool centered;

  const _HeroContent({
    required this.logoFade,
    required this.logoSlide,
    required this.textFade,
    required this.textSlide,
    required this.ctaFade,
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final xAlign =
        centered ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    final tAlign = centered ? TextAlign.center : TextAlign.left;
    final rowAlign =
        centered ? MainAxisAlignment.center : MainAxisAlignment.start;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: xAlign,
      children: [
        // ── Badge ────────────────────────────────────────────────────
        FadeTransition(
          opacity: logoFade,
          child: SlideTransition(
            position: logoSlide,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0x124F46E5),
                border: Border.all(color: const Color(0x334F46E5)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Color(0xFF818CF8), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text('Built for Indian Businesses',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF818CF8),
                        fontWeight: FontWeight.w500,
                      )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // ── Main headline ─────────────────────────────────────────────
        FadeTransition(
          opacity: textFade,
          child: SlideTransition(
            position: textSlide,
            child: Column(
              crossAxisAlignment: xAlign,
              children: [
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFF8FAFC), Color(0xFFCBD5E1)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'From Employee Data\nto GST Invoices —',
                    textAlign: tAlign,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 50,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -2,
                      height: 1.06,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFF818CF8), Color(0xFFC084FC)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(b),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'One Platform.',
                    textAlign: tAlign,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 50,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -2,
                      height: 1.06,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Subtitle ──────────────────────────────────────────────────
        FadeTransition(
          opacity: textFade,
          child: SlideTransition(
            position: textSlide,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                'CRUSAM replaces your salary spreadsheets, manual vouchers, '
                'and GST headaches with one clean, automated system.',
                textAlign: tAlign,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: const Color(0xFF64748B),
                  height: 1.7,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 36),

        // ── CTA Buttons ───────────────────────────────────────────────
        FadeTransition(
          opacity: ctaFade,
          child: Row(
            mainAxisAlignment: rowAlign,
            children: [
              _HeroButton(
                label: 'Open Dashboard',
                isPrimary: true,
                onTap: () => context.go('/login'),
              ),
              const SizedBox(width: 14),
              _HeroButton(
                label: 'See Features',
                isPrimary: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // ── Trust indicators ──────────────────────────────────────────
        FadeTransition(
          opacity: ctaFade,
          child: Row(
            mainAxisAlignment: rowAlign,
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 13, color: Color(0xFF4F46E5)),
              const SizedBox(width: 5),
              Text('No credit card required',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF475569))),
              const SizedBox(width: 16),
              const Icon(Icons.check_circle_outline,
                  size: 13, color: Color(0xFF4F46E5)),
              const SizedBox(width: 5),
              Text('GST compliant',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF475569))),
              const SizedBox(width: 16),
              const Icon(Icons.check_circle_outline,
                  size: 13, color: Color(0xFF4F46E5)),
              const SizedBox(width: 5),
              Text('Made for India',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: const Color(0xFF475569))),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Floating Mock Dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingMockDashboard extends StatefulWidget {
  const _FloatingMockDashboard();

  @override
  State<_FloatingMockDashboard> createState() =>
      _FloatingMockDashboardState();
}

class _FloatingMockDashboardState extends State<_FloatingMockDashboard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _float;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3800))
      ..repeat(reverse: true);
    _float = Tween<double>(begin: 0, end: 10)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _float,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, -_float.value),
          child: child,
        ),
        child: Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(-0.04)
            ..rotateX(0.02),
          alignment: FractionalOffset.center,
          child: const _MockDashboard(),
        ),
      );
}

class _MockDashboard extends StatelessWidget {
  const _MockDashboard();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D1424),
          border: Border.all(color: const Color(0x334F46E5)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.indigo600.withOpacity(0.22),
              blurRadius: 80,
              spreadRadius: 4,
              offset: const Offset(0, 24),
            ),
            BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.08),
              blurRadius: 40,
              spreadRadius: 10,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Browser chrome
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                color: const Color(0xFF0A101E),
                child: Row(
                  children: [
                    const Row(children: [
                      _DotIndicator(color: Color(0xFFFF5F57)),
                      SizedBox(width: 5),
                      _DotIndicator(color: Color(0xFFFFBD2E)),
                      SizedBox(width: 5),
                      _DotIndicator(color: Color(0xFF28C840)),
                    ]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('crusam.app/dashboard',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFF475569))),
                      ),
                    ),
                  ],
                ),
              ),
              // Dashboard body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Dashboard',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            )),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.indigo600.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: AppColors.indigo600.withOpacity(0.3)),
                          ),
                          child: Text('April 2025',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: const Color(0xFF818CF8),
                              )),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Stat cards
                    Row(
                      children: [
                        _DashStatCard(
                          label: 'Employees',
                          value: '48',
                          icon: Icons.people_outline,
                          color: const Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 8),
                        _DashStatCard(
                          label: 'Payout',
                          value: '₹4.2L',
                          icon: Icons.currency_rupee,
                          color: const Color(0xFF0D9488),
                        ),
                        const SizedBox(width: 8),
                        _DashStatCard(
                          label: 'Invoices',
                          value: '12',
                          icon: Icons.receipt_outlined,
                          color: const Color(0xFFD97706),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Chart + employee list
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: _MiniBarChart()),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: _MiniEmployeeList()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Recent activity strip
                    _MiniActivityStrip(),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _DotIndicator extends StatelessWidget {
  final Color color;
  const _DotIndicator({required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _DashStatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _DashStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF1E2640)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(icon, size: 13, color: color),
              ]),
              const SizedBox(height: 7),
              Text(value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.5,
                  )),
              const SizedBox(height: 1),
              Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    color: const Color(0xFF475569),
                  )),
            ],
          ),
        ),
      );
}

class _MiniBarChart extends StatelessWidget {
  static const _bars = [0.4, 0.6, 0.5, 0.8, 0.65, 0.9, 0.7];
  const _MiniBarChart();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E2640)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Salary Trend',
                style: GoogleFonts.inter(
                    fontSize: 9, color: const Color(0xFF475569))),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _bars
                    .map((h) => Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 2),
                            child: FractionallySizedBox(
                              heightFactor: h,
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF4F46E5),
                                      Color(0xFF818CF8),
                                    ],
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                  ),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      );
}

class _MiniEmployeeList extends StatelessWidget {
  static const _employees = [
    ('Rahul M.', '₹45,200'),
    ('Priya S.', '₹38,500'),
    ('Arjun K.', '₹52,000'),
  ];
  const _MiniEmployeeList();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1E2640)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recent Salaries',
                style: GoogleFonts.inter(
                    fontSize: 9, color: const Color(0xFF475569))),
            const SizedBox(height: 8),
            ..._employees.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(e.$1,
                        style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF94A3B8))),
                    Text(e.$2,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF818CF8),
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _MiniActivityStrip extends StatelessWidget {
  static const _items = [
    (Icons.check_circle_outline, 'Salary slip generated — Rahul M.', Color(0xFF0D9488)),
    (Icons.upload_file_outlined, 'Invoice #INV-047 exported', Color(0xFFD97706)),
  ];
  const _MiniActivityStrip();

  @override
  Widget build(BuildContext context) => Column(
        children: _items
            .map((item) => Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(6),
                    border:
                        Border.all(color: const Color(0xFF1E2640)),
                  ),
                  child: Row(
                    children: [
                      Icon(item.$1, size: 12, color: item.$3),
                      const SizedBox(width: 8),
                      Text(item.$2,
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: const Color(0xFF64748B),
                          )),
                    ],
                  ),
                ))
            .toList(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Buttons
// ─────────────────────────────────────────────────────────────────────────────

class _HeroButton extends StatefulWidget {
  final String label;
  final bool isPrimary;
  final VoidCallback onTap;
  const _HeroButton(
      {required this.label, required this.isPrimary, required this.onTap});
  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding:
                const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
            decoration: BoxDecoration(
              color: widget.isPrimary
                  ? (_hovered ? AppColors.indigo700 : AppColors.indigo600)
                  : (_hovered
                      ? const Color(0x1AFFFFFF)
                      : Colors.transparent),
              border: Border.all(
                color: widget.isPrimary
                    ? Colors.transparent
                    : const Color(0x33FFFFFF),
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: widget.isPrimary && _hovered
                  ? [
                      BoxShadow(
                        color: AppColors.indigo600.withOpacity(0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    )),
                if (widget.isPrimary) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward,
                      size: 16, color: Colors.white),
                ],
              ],
            ),
          ),
        ),
      );
}

class _ScrollDot extends StatefulWidget {
  const _ScrollDot();
  @override
  State<_ScrollDot> createState() => _ScrollDotState();
}

class _ScrollDotState extends State<_ScrollDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
    _anim = CurvedAnimation(parent: _c, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 36,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x44FFFFFF)),
          borderRadius: BorderRadius.circular(11),
        ),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) => Align(
            alignment: Alignment.lerp(const Alignment(0, -0.5),
                const Alignment(0, 0.5), _anim.value)!,
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(
                  color: Colors.white54, shape: BoxShape.circle),
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared: Section Badge
// ─────────────────────────────────────────────────────────────────────────────

class _SectionBadge extends StatelessWidget {
  final String text;
  const _SectionBadge(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x124F46E5),
          border: Border.all(color: const Color(0x334F46E5)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.indigo400,
              fontWeight: FontWeight.w500,
            )),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Problem / Solution Section
// ─────────────────────────────────────────────────────────────────────────────

class _ProblemSolutionSection extends StatelessWidget {
  const _ProblemSolutionSection();

  static const _problems = [
    (
      Icons.warning_amber_outlined,
      'Salary calculation errors',
      'Excel formulas break. Wrong PF deductions cause disputes every month.',
    ),
    (
      Icons.schedule_outlined,
      'Hours of payroll work',
      'Processing 50 employees manually devours your entire working day.',
    ),
    (
      Icons.receipt_long_outlined,
      'GST invoice confusion',
      'Manually computing 18% GST, TDS, and surcharges is a minefield.',
    ),
    (
      Icons.folder_copy_outlined,
      'Version control chaos',
      'Multiple salary sheet versions flying around. Which one is final?',
    ),
  ];

  static const _solutions = [
    (Icons.auto_fix_high_outlined, 'Auto PF, ESIC & PT deductions', Color(0xFF4F46E5)),
    (Icons.bolt_outlined, 'Process 50 salaries in minutes', Color(0xFF7C3AED)),
    (Icons.picture_as_pdf_outlined, 'GST invoices generated instantly', Color(0xFF0D9488)),
    (Icons.cloud_done_outlined, 'Single source of truth, always', Color(0xFF059669)),
  ];

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A0F1E),
        padding:
            const EdgeInsets.symmetric(vertical: 96, horizontal: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionBadge('The Problem'),
            const SizedBox(height: 18),
            Text(
              'Still managing payroll\non spreadsheets?',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 44,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1.5,
                height: 1.12,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              "You shouldn't be spending hours on salary math every month.",
              style: GoogleFonts.inter(
                fontSize: 16,
                color: const Color(0xFF64748B),
                height: 1.6,
              ),
            ),
            const SizedBox(height: 44),

            // Problem cards grid
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 720 ? 2 : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 3.4,
                ),
                itemCount: _problems.length,
                itemBuilder: (_, i) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1424),
                    border: Border.all(color: const Color(0xFF1E293B)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_problems[i].$1,
                            size: 17,
                            color: const Color(0xFFDC2626)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(_problems[i].$2,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                )),
                            const SizedBox(height: 3),
                            Text(_problems[i].$3,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF475569),
                                  height: 1.45,
                                )),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 52),

            // Transition arrow
            Row(
              children: [
                Container(
                    height: 1,
                    width: 40,
                    color: AppColors.indigo600),
                const SizedBox(width: 16),
                Text('CRUSAM fixes all of that.',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF818CF8),
                    )),
              ],
            ),
            const SizedBox(height: 28),

            // Solution chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _solutions
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: s.$3.withOpacity(0.08),
                          border:
                              Border.all(color: s.$3.withOpacity(0.25)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(s.$1, size: 15, color: s.$3),
                            const SizedBox(width: 8),
                            Text(s.$2,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      Colors.white.withOpacity(0.85),
                                )),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Features Section
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  static const _features = [
    (
      Icons.people_outline,
      'All Employee Data, One Place',
      'PF/UAN, bank details, salary structures — everything per employee, always current.',
      Color(0xFF4F46E5),
    ),
    (
      Icons.description_outlined,
      'Expense Vouchers, Auto-Calculated',
      'Build travel vouchers that auto-sum allowances and link directly to employee records.',
      Color(0xFF7C3AED),
    ),
    (
      Icons.receipt_long_outlined,
      'Salary Processing in Minutes',
      'Full payroll with PF, ESIC, PT & MSW deductions computed automatically, zero manual math.',
      Color(0xFF0D9488),
    ),
    (
      Icons.picture_as_pdf_outlined,
      'Professional PDFs in One Click',
      'Salary slips, invoices, Attachment A & B — export-ready documents generated instantly.',
      Color(0xFFD97706),
    ),
    (
      Icons.payments_outlined,
      'GST Invoices, Instantly Ready',
      'Auto-calculate 18% GST, generate Attachment A/B, and export — all in one flow.',
      Color(0xFFDC2626),
    ),
    (
      Icons.settings_outlined,
      'Company Setup, Done Once',
      'Enter your GST number, bank details, and logo once — auto-filled into every document.',
      Color(0xFF059669),
    ),
  ];

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF050B18),
        padding:
            const EdgeInsets.symmetric(vertical: 96, horizontal: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionBadge('Features'),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    'Everything to run payroll,\nzero chaos.',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -1.5,
                      height: 1.12,
                    ),
                  ),
                ),
                Text(
                  'Six modules.\nOne dashboard.',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF475569),
                    height: 1.6,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 52),
            LayoutBuilder(builder: (ctx, constraints) {
              final cols = constraints.maxWidth > 900 ? 3 : 2;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: cols,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                  childAspectRatio: 1.45,
                ),
                itemCount: _features.length,
                itemBuilder: (_, i) => _FeatureCard(
                  icon: _features[i].$1,
                  title: _features[i].$2,
                  description: _features[i].$3,
                  accentColor: _features[i].$4,
                ),
              );
            }),
          ],
        ),
      );
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
  });
  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _hovered
                ? const Color(0xFF111827)
                : const Color(0xFF0D1424),
            border: Border.all(
              color: _hovered
                  ? widget.accentColor.withOpacity(0.4)
                  : const Color(0xFF1E293B),
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.12),
                      blurRadius: 24,
                      spreadRadius: 2,
                    )
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.accentColor
                      .withOpacity(_hovered ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon,
                    size: 22, color: widget.accentColor),
              ),
              const SizedBox(height: 16),
              Text(widget.title,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  )),
              const SizedBox(height: 8),
              Expanded(
                child: Text(widget.description,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                      height: 1.6,
                    )),
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats Section
// ─────────────────────────────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF0A0F1E),
        padding:
            const EdgeInsets.symmetric(vertical: 80, horizontal: 56),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionBadge('Results'),
            const SizedBox(height: 40),
            LayoutBuilder(builder: (ctx, c) {
              final cols = c.maxWidth > 700 ? 4 : 2;
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                crossAxisSpacing: 1,
                mainAxisSpacing: 1,
                childAspectRatio: 1.6,
                children: const [
                  _StatTile(
                    value: '80%',
                    label: 'Less time on payroll',
                  ),
                  _StatTile(
                    value: '1-click',
                    label: 'GST invoice generation',
                  ),
                  _StatTile(
                    value: '0 errors',
                    label: 'Automated calculations',
                  ),
                  _StatTile(
                    value: '100%',
                    label: 'Compliance ready',
                  ),
                ],
              );
            }),
          ],
        ),
      );
}

class _StatTile extends StatelessWidget {
  final String value, label;
  const _StatTile({required this.value, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF1E293B)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [Color(0xFF818CF8), Color(0xFFC084FC)],
              ).createShader(b),
              blendMode: BlendMode.srcIn,
              child: Text(value,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -1.5,
                  )),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: const Color(0xFF475569),
                )),
          ],
        ),
      );
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(height: 60, width: 1, color: const Color(0xFF1E293B));
}

// ─────────────────────────────────────────────────────────────────────────────
// CTA Section
// ─────────────────────────────────────────────────────────────────────────────

class _CtaSection extends StatelessWidget {
  const _CtaSection();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF050B18),
        padding:
            const EdgeInsets.symmetric(vertical: 96, horizontal: 56),
        child: Container(
          padding:
              const EdgeInsets.symmetric(vertical: 64, horizontal: 60),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1E1B4B), Color(0xFF14103A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: const Color(0x334F46E5)),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF4F46E5).withOpacity(0.1),
                blurRadius: 60,
                spreadRadius: 5,
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: copy
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to kill the\nspreadsheet chaos?',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -1.2,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Join businesses already running payroll,\nvouchers, and invoices on CRUSAM.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: const Color(0xFF94A3B8),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              // Right: CTA
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => context.go('/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.indigo600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 36),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Launch Dashboard',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No setup fees. No spreadsheets.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Footer
// ─────────────────────────────────────────────────────────────────────────────

class _LandingFooter extends StatelessWidget {
  const _LandingFooter();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF050B18),
        padding: const EdgeInsets.fromLTRB(56, 40, 56, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: Color(0xFF1E293B)),
            const SizedBox(height: 36),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Brand column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.indigo600,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: const Text('A',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      Text('CRUSAM',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          )),
                    ]),
                    const SizedBox(height: 10),
                    Text(
                      'Business management for\nIndian enterprises.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF475569),
                        height: 1.65,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'support@crusam.app',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: const Color(0xFF4F46E5),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                // Link columns
                ...[
                  (
                    'Product',
                    ['Features', 'How it Works', 'Pricing', 'Changelog']
                  ),
                  (
                    'Support',
                    ['Documentation', 'Contact', 'Privacy Policy', 'Terms']
                  ),
                ].map((section) => Padding(
                      padding: const EdgeInsets.only(left: 72),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(section.$1,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.8,
                              )),
                          const SizedBox(height: 14),
                          ...section.$2.map((link) => Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: Text(link,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: const Color(0xFF475569),
                                      )),
                                ),
                              )),
                        ],
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 36),
            const Divider(color: Color(0xFF1E293B)),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  '© 2025 Aarti Enterprises. CRUSAM Business Management System.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF334155),
                  ),
                ),
                const Spacer(),
                Text(
                  'v1.0.0  •  GST Compliant  •  Made in India 🇮🇳',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF334155),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}
// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../notifiers/auth_notifier.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _obscure = true;
  bool _obscureConfirm = true;

  final _formKey    = GlobalKey<FormState>();
  final _emailCtrl  = TextEditingController();
  final _passCtrl   = TextEditingController();
  final _confirmCtrl= TextEditingController();
  final _nameCtrl   = TextEditingController();

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  final _auth = AuthNotifier.instance;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fade  = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(_fade);
    _fadeCtrl.forward();
    _auth.addListener(_onAuthChanged);
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (_auth.isLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/dashboard');
      });
    }
    setState(() {});
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    _fadeCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _switchMode() {
    setState(() => _isLogin = !_isLogin);
    _auth.clearError();
    _formKey.currentState?.reset();
    _fadeCtrl.reset();
    _fadeCtrl.forward();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    bool ok;
    if (_isLogin) {
      ok = await _auth.login(_emailCtrl.text.trim(), _passCtrl.text);
    } else {
      ok = await _auth.register(
        _emailCtrl.text.trim(), _passCtrl.text, _nameCtrl.text.trim());
    }
    if (ok && mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050B18),
      body: Row(
        children: [
          // ── Left branding panel ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: _LeftPanel(),
          ),
          // ── Right form panel ─────────────────────────────────────────
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.white,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(48),
                    child: FadeTransition(
                      opacity: _fade,
                      child: SlideTransition(
                        position: _slide,
                        child: _buildForm(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.indigo600,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: const Text('A',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Text('CRUSAM',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  )),
            ],
          ),
          const SizedBox(height: 40),

          // Title
          Text(
            _isLogin ? 'Welcome back' : 'Create account',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _isLogin
                ? 'Sign in to access your dashboard'
                : 'Get started with your business tools',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 32),

          // Error banner
          if (_auth.error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                border: Border.all(color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Color(0xFFDC2626)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _auth.error!,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFFDC2626)),
                    ),
                  ),
                ],
              ),
            ),

          // Name field (register only)
          if (!_isLogin) ...[
            _buildField(
              controller: _nameCtrl,
              label: 'Full name',
              hint: 'e.g. Rajesh Sharma',
              icon: Icons.person_outline,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Full name is required'
                  : null,
            ),
            const SizedBox(height: 16),
          ],

          // Email
          _buildField(
            controller: _emailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@') || !v.contains('.'))
                return 'Enter a valid email';
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Password
          _buildField(
            controller: _passCtrl,
            label: 'Password',
            hint: _isLogin ? 'Enter your password' : 'Min. 6 characters',
            icon: Icons.lock_outline,
            obscure: _obscure,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                size: 18,
                color: const Color(0xFF94A3B8),
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (!_isLogin && v.length < 6)
                return 'Password must be at least 6 characters';
              return null;
            },
          ),

          // Confirm password (register only)
          if (!_isLogin) ...[
            const SizedBox(height: 16),
            _buildField(
              controller: _confirmCtrl,
              label: 'Confirm password',
              hint: 'Repeat your password',
              icon: Icons.lock_outline,
              obscure: _obscureConfirm,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please confirm your password';
                if (v != _passCtrl.text) return 'Passwords do not match';
                return null;
              },
            ),
          ],

          const SizedBox(height: 28),

          // Submit button
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _auth.isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.indigo600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _auth.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      _isLogin ? 'Sign In' : 'Create Account',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _isLogin
                    ? "Don't have an account? "
                    : 'Already have an account? ',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              GestureDetector(
                onTap: _switchMode,
                child: Text(
                  _isLogin ? 'Register' : 'Sign in',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.indigo600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Back to landing
          Center(
            child: TextButton.icon(
              onPressed: () => context.go('/landing'),
              icon: const Icon(Icons.arrow_back, size: 14,
                  color: Color(0xFF94A3B8)),
              label: const Text('Back to home',
                  style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF334155),
            )),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          validator: validator,
          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 14),
            prefixIcon: Icon(icon, size: 18, color: const Color(0xFF94A3B8)),
            suffixIcon: suffixIcon,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.indigo500, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFFDC2626)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: Color(0xFFDC2626), width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Left branding panel ──────────────────────────────────────────────────────

class _LeftPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF050B18), Color(0xFF0F0A2E)],
        ),
      ),
      child: Stack(
        children: [
          // Decorative orbs
          Positioned(
            top: -100,
            right: -80,
            child: _Orb(size: 400, color: const Color(0x184F46E5)),
          ),
          Positioned(
            bottom: -80,
            left: -60,
            child: _Orb(size: 320, color: const Color(0x127C3AED)),
          ),
          Positioned(
            top: MediaQuery.of(context).size.height * 0.4,
            right: 40,
            child: _Orb(size: 200, color: const Color(0x0EC084FC)),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(64),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0x1A4F46E5),
                    border: Border.all(color: const Color(0x334F46E5)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Business Management Platform',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.indigo400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Main headline
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [
                      Color(0xFF818CF8),
                      Color(0xFFC084FC),
                      Color(0xFFF472B6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'CRUSAM',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 72,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -2,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Aarti Enterprises\nManagement System',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF94A3B8),
                    height: 1.4,
                  ),
                ),
                const Spacer(),

                // Feature list
                ..._features.map((f) => _FeatureLine(
                    icon: f.$1, label: f.$2)),
                const SizedBox(height: 48),

                // Footer
                Text(
                  '© 2025 Aarti Enterprises. All rights reserved.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _features = [
    (Icons.people_outline, 'Employee master data & salary processing'),
    (Icons.description_outlined, 'Voucher builder & invoice generation'),
    (Icons.picture_as_pdf_outlined, 'One-click PDF & Excel export'),
    (Icons.settings_outlined, 'Company configuration management'),
  ];
}

class _FeatureLine extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureLine({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0x154F46E5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: AppColors.indigo400),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: const Color(0xFF94A3B8),
                  )),
            ),
          ],
        ),
      );
}

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  const _Orb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      );
}
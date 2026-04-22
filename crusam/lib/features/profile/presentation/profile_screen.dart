// lib/features/profile/screens/profile_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_selector/file_selector.dart';

import '../../../core/preferences/export_preferences_notifier.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/company_config_model.dart';
import '../../../data/db/database_helper.dart';
import '../../auth/notifiers/auth_notifier.dart';
import '../../auth/data/models/user_model.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/update_card.dart';

import 'package:crusam/features/profile/widgets/export_paths_card.dart';

class _PdfMethodCard extends StatelessWidget {
  const _PdfMethodCard();

  @override
  Widget build(BuildContext context) {
    final prefs = ExportPreferencesNotifier.instance;
    return ListenableBuilder(
      listenable: prefs,
      builder: (ctx, _) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.picture_as_pdf_outlined,
                  size: 18, color: AppColors.slate500),
              const SizedBox(width: 8),
              Text('PDF Generation', style: AppTextStyles.h4),
            ]),
            const SizedBox(height: 4),
            Text(
              'Applies to Tax Invoice & Voucher PDFs only.',
              style: AppTextStyles.small.copyWith(color: AppColors.slate500),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prefs.useWidgetPdfForInvoiceVoucher
                            ? 'Widget-based (Better Quality)'
                            : 'Screenshot-based (Default)',
                        style: AppTextStyles.bodyMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        prefs.useWidgetPdfForInvoiceVoucher
                            ? 'Generates PDF using structured pw widgets — crisp text, no rasterization.'
                            : 'Captures a screenshot of the preview — matches on-screen appearance exactly.',
                        style: AppTextStyles.small
                            .copyWith(color: AppColors.slate500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: prefs.useWidgetPdfForInvoiceVoucher,
                  activeColor: AppColors.indigo600,
                  onChanged: (v) => prefs.setUseWidgetPdf(v),
                ),
              ],
            ),
            if (prefs.useWidgetPdfForInvoiceVoucher) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.indigo50,
                  border: Border.all(color: AppColors.indigo500.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.indigo600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Widget PDF is active for Tax Invoice & Voucher exports.',
                      style: AppTextStyles.small.copyWith(
                          color: AppColors.indigo600,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _auth  = AuthNotifier.instance;
  bool _editing = false;
  bool _saving  = false;
  bool _showPassSection = false;

  // Profile form
  final _nameCtrl     = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _usernameCtrl = TextEditingController();

  // Password form
  final _curPassCtrl  = TextEditingController();
  final _newPassCtrl  = TextEditingController();
  final _confPassCtrl = TextEditingController();
  bool _obscureCur = true, _obscureNew = true, _obscureConf = true;

  final _profileKey  = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _syncFromUser();
    // Ensure preferences are loaded whenever the profile screen is shown.
    ExportPreferencesNotifier.instance.load();
  }

  void _syncFromUser() {
    final u = _auth.user;
    if (u == null) return;
    _nameCtrl.text     = u.fullName;
    _emailCtrl.text    = u.email;
    _phoneCtrl.text    = u.phone;
    _usernameCtrl.text = u.username;
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _emailCtrl, _phoneCtrl, _usernameCtrl,
      _curPassCtrl, _newPassCtrl, _confPassCtrl,
    ]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final u = _auth.user!;
    final updated = u.copyWith(
      fullName: _nameCtrl.text.trim(),
      phone:    _phoneCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
    );
    final ok = await _auth.updateProfile(updated);
    if (!mounted) return;
    setState(() { _saving = false; _editing = false; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Profile updated successfully' : 'Failed to update profile'),
    ));
  }

  Future<void> _savePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await _auth.updateProfile(
      _auth.user!, newPassword: _newPassCtrl.text);
    if (!mounted) return;
    setState(() { _saving = false; _showPassSection = false; });
    _curPassCtrl.clear(); _newPassCtrl.clear(); _confPassCtrl.clear();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Password changed successfully' : 'Failed to change password'),
    ));
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dc, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(dc, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await _auth.logout();
      if (mounted) context.go('/landing');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (ctx, _) {
        final user = _auth.user;
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => context.go('/landing'));
          return const SizedBox.shrink();
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pagePadding),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileHeader(user: user, onLogout: _logout),
                  const SizedBox(height: 24),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: _PersonalInfoCard(
                          user: user,
                          editing: _editing,
                          saving: _saving,
                          formKey: _profileKey,
                          nameCtrl: _nameCtrl,
                          emailCtrl: _emailCtrl,
                          phoneCtrl: _phoneCtrl,
                          usernameCtrl: _usernameCtrl,
                          onEdit: () => setState(() => _editing = true),
                          onCancel: () {
                            _syncFromUser();
                            setState(() => _editing = false);
                          },
                          onSave: _saveProfile,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            _AccountCard(
                              user: user,
                              showPassSection: _showPassSection,
                              saving: _saving,
                              obscureCur: _obscureCur,
                              obscureNew: _obscureNew,
                              obscureConf: _obscureConf,
                              passwordKey: _passwordKey,
                              curPassCtrl: _curPassCtrl,
                              newPassCtrl: _newPassCtrl,
                              confPassCtrl: _confPassCtrl,
                              onTogglePass: () =>
                                  setState(() => _showPassSection = !_showPassSection),
                              onSavePass: _savePassword,
                              onToggleCur: () =>
                                  setState(() => _obscureCur = !_obscureCur),
                              onToggleNew: () =>
                                  setState(() => _obscureNew = !_obscureNew),
                              onToggleConf: () =>
                                  setState(() => _obscureConf = !_obscureConf),
                            ),
                            const SizedBox(height: 20),
                            const ExportPathsCard(),
                            const SizedBox(height: 20),
                            const _PdfMethodCard(),   // ← insert here
                            const SizedBox(height: 20),
                            const UpdateCard(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Profile Header ─────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final UserModel user;
  final VoidCallback onLogout;
  const _ProfileHeader({required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Row(
          children: [
            AvatarWidget(
              displayName: user.displayName,
              avatarPath: user.avatarPath,
              size: 72,
              showBorder: true,
              borderColor: AppColors.indigo400,
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.displayName,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      )),
                  const SizedBox(height: 4),
                  Text(user.email,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.slate400)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x1A4F46E5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0x334F46E5)),
                    ),
                    child: Text(
                      user.authProvider == AuthProviderType.manual
                          ? 'Manual Account'
                          : 'Google Account',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.indigo400,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, size: 16, color: Colors.red),
              label: const Text('Sign Out',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0x55DC2626)),
              ),
            ),
          ],
        ),
      );
}

// ── Personal Info Card ─────────────────────────────────────────────────────────

class _PersonalInfoCard extends StatelessWidget {
  final UserModel user;
  final bool editing, saving;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl, emailCtrl, phoneCtrl, usernameCtrl;
  final VoidCallback onEdit, onCancel, onSave;

  const _PersonalInfoCard({
    required this.user,
    required this.editing,
    required this.saving,
    required this.formKey,
    required this.nameCtrl,
    required this.emailCtrl,
    required this.phoneCtrl,
    required this.usernameCtrl,
    required this.onEdit,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('Personal Information', style: AppTextStyles.h4),
                const Spacer(),
                if (!editing)
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: const Text('Edit'),
                  ),
              ]),
              const SizedBox(height: 20),
              _formField('Full Name', nameCtrl, editing,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null),
              _formField('Email Address', emailCtrl, false),
              _formField('Username', usernameCtrl, editing),
              _formField('Phone', phoneCtrl, editing,
                  keyboardType: TextInputType.phone),
              if (editing) ...[
                const SizedBox(height: 8),
                Row(children: [
                  OutlinedButton(
                      onPressed: saving ? null : onCancel,
                      child: const Text('Cancel')),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: saving ? null : onSave,
                    child: saving
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Save Changes'),
                  ),
                ]),
              ],
            ],
          ),
        ),
      );

  Widget _formField(
    String label,
    TextEditingController ctrl,
    bool editable, {
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.small
                  .copyWith(fontWeight: FontWeight.w600, color: AppColors.slate600)),
          const SizedBox(height: 6),
          editable
              ? TextFormField(
                  controller: ctrl,
                  keyboardType: keyboardType,
                  validator: validator,
                  style: AppTextStyles.input,
                )
              : Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 11),
                  decoration: BoxDecoration(
                    color: AppColors.slate50,
                    border: Border.all(color: AppColors.slate200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ctrl.text.isEmpty ? '—' : ctrl.text,
                    style: AppTextStyles.input,
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Account Card ───────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final UserModel user;
  final bool showPassSection, saving;
  final bool obscureCur, obscureNew, obscureConf;
  final GlobalKey<FormState> passwordKey;
  final TextEditingController curPassCtrl, newPassCtrl, confPassCtrl;
  final VoidCallback onTogglePass, onSavePass;
  final VoidCallback onToggleCur, onToggleNew, onToggleConf;

  const _AccountCard({
    required this.user,
    required this.showPassSection,
    required this.saving,
    required this.obscureCur,
    required this.obscureNew,
    required this.obscureConf,
    required this.passwordKey,
    required this.curPassCtrl,
    required this.newPassCtrl,
    required this.confPassCtrl,
    required this.onTogglePass,
    required this.onSavePass,
    required this.onToggleCur,
    required this.onToggleNew,
    required this.onToggleConf,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.slate200),
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: AppTextStyles.h4),
            const SizedBox(height: 20),

            _infoRow(Icons.email_outlined, 'Email', user.email),
            _infoRow(
              Icons.shield_outlined,
              'Auth Method',
              user.authProvider == AuthProviderType.manual
                  ? 'Password'
                  : 'Google',
            ),
            _infoRow(Icons.calendar_today_outlined, 'Member Since',
                _fmtDate(user.createdAt)),

            const Divider(height: 28),

            GestureDetector(
              onTap: onTogglePass,
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 16,
                    color: AppColors.slate500),
                const SizedBox(width: 8),
                Text('Change Password', style: AppTextStyles.bodyMedium),
                const Spacer(),
                Icon(
                  showPassSection
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: AppColors.slate400,
                ),
              ]),
            ),

            if (showPassSection) ...[
              const SizedBox(height: 16),
              Form(
                key: passwordKey,
                child: Column(children: [
                  _passField(
                      'Current Password', curPassCtrl, obscureCur, onToggleCur,
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Required' : null),
                  const SizedBox(height: 12),
                  _passField(
                      'New Password', newPassCtrl, obscureNew, onToggleNew,
                      validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v.length < 6) return 'Min. 6 characters';
                    return null;
                  }),
                  const SizedBox(height: 12),
                  _passField('Confirm Password', confPassCtrl, obscureConf,
                      onToggleConf, validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    if (v != newPassCtrl.text) return 'Passwords do not match';
                    return null;
                  }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: saving ? null : onSavePass,
                      child: saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Update Password'),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.slate400),
            const SizedBox(width: 10),
            Text('$label:', style: AppTextStyles.small),
            const SizedBox(width: 6),
            Expanded(
              child: Text(value,
                  style: AppTextStyles.small.copyWith(
                      color: AppColors.slate700,
                      fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );

  Widget _passField(
    String label,
    TextEditingController ctrl,
    bool obscure,
    VoidCallback onToggle, {
    String? Function(String?)? validator,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppTextStyles.small
                  .copyWith(fontWeight: FontWeight.w600, color: AppColors.slate600)),
          const SizedBox(height: 4),
          TextFormField(
            controller: ctrl,
            obscureText: obscure,
            validator: validator,
            style: AppTextStyles.input,
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 17,
                  color: AppColors.slate400,
                ),
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      );

  static String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return iso.isEmpty ? '—' : iso;
    }
  }
}
import 'package:flutter/material.dart';
import '../../../core/sync/google_auth_service.dart';
import '../../../data/models/company_config_model.dart';
import '../notifiers/settings_notifier.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens — compact, label weight w600, label size reduced to 11
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

  // Colours
  static const ink         = Color(0xFF1E1B4B);
  static const inkLight    = Color(0xFF3730A3);
  static const inkMuted    = Color(0xFF818CF8);
  static const border      = Color(0xFFC7D2FE);
  static const borderFocus = Color(0xFF4338CA);
  static const divider     = Color(0xFFE0E7FF);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceAlt  = Color(0xFFEEF2FF);
  static const badgeBg     = Color(0xFF1E1B4B);
  static const badgeFg     = Color(0xFFFFFFFF);

  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

  // Text styles – label size now 11 (was 12)
  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 14,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsBadge = TextStyle(
    fontFamily   : fxcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 11,
    letterSpacing: 2.0,
    color        : badgeFg,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 11,                // ← reduced from 12 to 11
    letterSpacing: 1.0,
    color        : inkMuted,
  );

  static const tsInput = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w500,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
  );

  // Compact layout
  static const double padH    = 18.0;
  static const double padV    = 16.0;
  static const double gutter  = 12.0;
  static const double rowGap  = 16.0;
  static const double radius  =  5.0;
  static const double cRadius =  8.0;
}

// ── Field decoration – left padding 2 ──────────────────────────────────────
InputDecoration _inputDec({String? hint, Widget? suffix}) =>
    InputDecoration(
      hintText      : hint,
      hintStyle     : const TextStyle(
        fontFamily : _Tok.fbody,
        fontSize   : 12,
        color      : _Tok.inkMuted,
        fontWeight : FontWeight.w400,
      ),
      suffixIcon    : suffix,
      isDense       : true,
      contentPadding: const EdgeInsets.fromLTRB(2, 8, 10, 8),
      filled        : true,
      fillColor     : _Tok.surface,
      enabledBorder : OutlineInputBorder(
        borderRadius: BorderRadius.circular(_Tok.radius),
        borderSide  : const BorderSide(color: _Tok.border),
      ),
      focusedBorder : OutlineInputBorder(
        borderRadius: BorderRadius.circular(_Tok.radius),
        borderSide  : const BorderSide(color: _Tok.borderFocus, width: 1.5),
      ),
    );

// ── Label + Field column ────────────────────────────────────────────────
class _LF extends StatelessWidget {
  final String label;
  final Widget child;
  const _LF(this.label, this.child);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _Tok.tsLabel),
          const SizedBox(height: 4),
          child,
        ],
      );
}

// ── Section header with numbered badge ───────────────────────────────────
class _Section extends StatelessWidget {
  final String tag;
  final List<Widget> children;
  const _Section({required this.tag, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color       : _Tok.badgeBg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(tag, style: _Tok.tsBadge),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(height: 1, thickness: 1, color: _Tok.divider),
            ),
          ]),
          const SizedBox(height: 8),
          ...children,
        ],
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  SettingsScreen
// ════════════════════════════════════════════════════════════════════════════
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _notifier = SettingsNotifier();

  late final _ctrl = <String, TextEditingController>{
    'companyName':     TextEditingController(),
    'address':         TextEditingController(),
    'gstin':           TextEditingController(),
    'pan':             TextEditingController(),
    'jurisdiction':    TextEditingController(),
    'declarationText': TextEditingController(),
    'bankName':        TextEditingController(),
    'branch':          TextEditingController(),
    'accountNo':       TextEditingController(),
    'ifscCode':        TextEditingController(),
    'phone':           TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    _notifier.load().then((_) => _syncControllers());
    _notifier.addListener(_syncControllers);
  }

  void _syncControllers() {
    final c = _notifier.config;
    void set(String k, String v) {
      if (_ctrl[k]!.text != v) _ctrl[k]!.text = v;
    }
    set('companyName',     c.companyName);
    set('address',         c.address);
    set('gstin',           c.gstin);
    set('pan',             c.pan);
    set('jurisdiction',    c.jurisdiction);
    set('declarationText', c.declarationText);
    set('bankName',        c.bankName);
    set('branch',          c.branch);
    set('accountNo',       c.accountNo);
    set('ifscCode',        c.ifscCode);
    set('phone',           c.phone);
  }

  CompanyConfigModel _fromControllers(CompanyConfigModel base) => base.copyWith(
    companyName:     _ctrl['companyName']!.text.trim(),
    address:         _ctrl['address']!.text.trim(),
    gstin:           _ctrl['gstin']!.text.trim(),
    pan:             _ctrl['pan']!.text.trim(),
    jurisdiction:    _ctrl['jurisdiction']!.text.trim(),
    declarationText: _ctrl['declarationText']!.text.trim(),
    bankName:        _ctrl['bankName']!.text.trim(),
    branch:          _ctrl['branch']!.text.trim(),
    accountNo:       _ctrl['accountNo']!.text.trim(),
    ifscCode:        _ctrl['ifscCode']!.text.trim(),
    phone:           _ctrl['phone']!.text.trim(),
  );

  Future<void> _save() async {
    _notifier.update((_) => _fromControllers(_notifier.config));
    final ok = await _notifier.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Configuration saved' : 'Error saving configuration')),
      );
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_syncControllers);
    _notifier.dispose();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _notifier,
    builder: (ctx, _) {
      if (_notifier.isLoading) return const Center(child: CircularProgressIndicator());
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Container(
              decoration: BoxDecoration(
                color       : _Tok.surface,
                border      : Border.all(color: _Tok.border),
                borderRadius: BorderRadius.circular(_Tok.cRadius),
                boxShadow   : [
                  BoxShadow(
                    color     : Colors.black.withOpacity(0.04),
                    blurRadius: 12,
                    offset    : const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SettingsHeader(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _Tok.padH, _Tok.padV, _Tok.padH, _Tok.padV,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 01  COMPANY ──────────────────────────────────────
                        _Section(
                          tag: '01  COMPANY',
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: _LF('Company Name',
                                    TextField(
                                      controller: _ctrl['companyName']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'Legal name'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  flex: 3,
                                  child: _LF('Phone',
                                    TextField(
                                      controller: _ctrl['phone']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'Contact number'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: _Tok.rowGap),
                            _LF('Address',
                              TextField(
                                controller: _ctrl['address']!,
                                style     : _Tok.tsInput,
                                maxLines  : 3,
                                decoration: _inputDec(hint: 'Full address'),
                              ),
                            ),
                            const SizedBox(height: _Tok.rowGap),
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('GSTIN',
                                    TextField(
                                      controller: _ctrl['gstin']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: '22AAAAA0000A1Z5'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('PAN',
                                    TextField(
                                      controller: _ctrl['pan']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'AAAAA0000A'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: _Tok.rowGap),
                            _LF('Jurisdiction',
                              TextField(
                                controller: _ctrl['jurisdiction']!,
                                style     : _Tok.tsInput,
                                decoration: _inputDec(hint: 'e.g. Mumbai'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── 02  BANK ────────────────────────────────────────
                        _Section(
                          tag: '02  BANK',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('Bank Name',
                                    TextField(
                                      controller: _ctrl['bankName']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'Bank name'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Branch',
                                    TextField(
                                      controller: _ctrl['branch']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'Branch'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: _Tok.rowGap),
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('Account Number',
                                    TextField(
                                      controller: _ctrl['accountNo']!,
                                      style     : _Tok.tsInput,
                                      decoration: _inputDec(hint: 'Account no.'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('IFSC Code',
                                    TextField(
                                      controller: _ctrl['ifscCode']!,
                                      style     : _Tok.tsInput,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: _inputDec(hint: 'IFSC'),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── 03  DECLARATION ──────────────────────────────────
                        _Section(
                          tag: '03  DECLARATION',
                          children: [
                            _LF('Declaration Text',
                              TextField(
                                controller: _ctrl['declarationText']!,
                                style     : _Tok.tsInput,
                                maxLines  : 3,
                                decoration: _inputDec(hint: 'Declaration shown on invoices'),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── Save button ──────────────────────────────────────
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _notifier.isSaving ? null : _save,
                            icon: _notifier.isSaving
                                ? const SizedBox(
                                    width : 14,
                                    height: 14,
                                    child : CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save, size: 16),
                            label: Text(_notifier.isSaving ? 'Saving…' : 'Save Configuration'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _Tok.ink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(_Tok.radius),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ── Card header ──────────────────────────────────────────────────────────
class _SettingsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    height    : 40,
    padding   : const EdgeInsets.symmetric(horizontal: _Tok.padH),
    decoration: const BoxDecoration(
      color : _Tok.surfaceAlt,
      border: Border(bottom: BorderSide(color: _Tok.divider)),
      borderRadius: BorderRadius.only(
        topLeft : Radius.circular(_Tok.cRadius),
        topRight: Radius.circular(_Tok.cRadius),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width : 24,
          height: 24,
          decoration: BoxDecoration(
            color       : _Tok.ink,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Icon(
            Icons.settings_outlined,
            color: Colors.white,
            size : 13,
          ),
        ),
        const SizedBox(width: 8),
        Text('COMPANY CONFIGURATION', style: _Tok.tsCardTitle),
        const Spacer(),
      ],
    ),
  );
}
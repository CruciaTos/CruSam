import 'package:flutter/material.dart';
import '../../../data/models/salary_formula_config_model.dart';
import '../notifier/salary_formula_notifier.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Design tokens — matches Company-Config settings_screen.dart
// ════════════════════════════════════════════════════════════════════════════
class _Tok {
  _Tok._();

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
    fontSize     : 11,
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

  static const tsHint = TextStyle(
    fontFamily: fbody,
    fontWeight: FontWeight.w400,
    fontSize  : 11,
    color     : inkMuted,
    height    : 1.3,
  );

  static const double padH    = 18.0;
  static const double padV    = 16.0;
  static const double gutter  = 12.0;
  static const double rowGap  = 16.0;
  static const double radius  =  5.0;
  static const double cRadius =  8.0;
}

InputDecoration _inputDec({String? hint, String? suffixText}) =>
    InputDecoration(
      hintText      : hint,
      hintStyle     : const TextStyle(
        fontFamily : _Tok.fbody,
        fontSize   : 12,
        color      : _Tok.inkMuted,
        fontWeight : FontWeight.w400,
      ),
      suffixText    : suffixText,
      suffixStyle   : const TextStyle(
        fontFamily: _Tok.fbody,
        fontSize  : 12,
        color     : _Tok.inkMuted,
      ),
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

class _LF extends StatelessWidget {
  final String label;
  final Widget child;
  final String? hint;
  const _LF(this.label, this.child, {this.hint});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _Tok.tsLabel),
          const SizedBox(height: 4),
          child,
          if (hint != null) ...[
            const SizedBox(height: 3),
            Text(hint!, style: _Tok.tsHint),
          ],
        ],
      );
}

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
//  SalaryFormulaSettingsScreen
// ════════════════════════════════════════════════════════════════════════════
class SalaryFormulaSettingsScreen extends StatefulWidget {
  const SalaryFormulaSettingsScreen({super.key});
  @override
  State<SalaryFormulaSettingsScreen> createState() =>
      _SalaryFormulaSettingsScreenState();
}

class _SalaryFormulaSettingsScreenState
    extends State<SalaryFormulaSettingsScreen> {
  final _notifier = SalaryFormulaNotifier.instance;

  // Rates are edited as plain percentages (e.g. "12" for 0.12) for
  // readability; everything else is edited in its stored unit (₹ or ₹ gross).
  late final _ctrl = <String, TextEditingController>{
    'pfRatePct':               TextEditingController(),
    'pfBasicThreshold':        TextEditingController(),
    'pfCapAmount':             TextEditingController(),
    'esicRatePct':             TextEditingController(),
    'esicGrossThreshold':      TextEditingController(),
    'ptFemaleThreshold':       TextEditingController(),
    'ptMaleTier1Threshold':    TextEditingController(),
    'ptMaleTier2Threshold':    TextEditingController(),
    'ptMaleTier2Amount':       TextEditingController(),
    'ptStandardAmount':        TextEditingController(),
    'ptFebAmount':             TextEditingController(),
    'employerPfRatePct':       TextEditingController(),
    'employerEsicRatePct':     TextEditingController(),
    'attachmentBPerEmployee':  TextEditingController(),
  };

  @override
  void initState() {
    super.initState();
    if (!_notifier.isLoading && _notifier.config.id == null) {
      _notifier.load().then((_) => _syncControllers());
    } else {
      _syncControllers();
    }
    _notifier.addListener(_syncControllers);
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  void _syncControllers() {
    final c = _notifier.config;
    void set(String k, String v) {
      if (_ctrl[k]!.text != v) _ctrl[k]!.text = v;
    }
    set('pfRatePct',              _fmt(c.pfRate * 100));
    set('pfBasicThreshold',       _fmt(c.pfBasicThreshold));
    set('pfCapAmount',            _fmt(c.pfCapAmount));
    set('esicRatePct',            _fmt(c.esicRate * 100));
    set('esicGrossThreshold',     _fmt(c.esicGrossThreshold));
    set('ptFemaleThreshold',      _fmt(c.ptFemaleThreshold));
    set('ptMaleTier1Threshold',   _fmt(c.ptMaleTier1Threshold));
    set('ptMaleTier2Threshold',   _fmt(c.ptMaleTier2Threshold));
    set('ptMaleTier2Amount',      _fmt(c.ptMaleTier2Amount));
    set('ptStandardAmount',       _fmt(c.ptStandardAmount));
    set('ptFebAmount',            _fmt(c.ptFebAmount));
    set('employerPfRatePct',      _fmt(c.employerPfRate * 100));
    set('employerEsicRatePct',    _fmt(c.employerEsicRate * 100));
    set('attachmentBPerEmployee', _fmt(c.attachmentBPerEmployee));
  }

  double _num(String key, double fallback) =>
      double.tryParse(_ctrl[key]!.text.trim()) ?? fallback;

  SalaryFormulaConfigModel _fromControllers(SalaryFormulaConfigModel base) =>
      base.copyWith(
        pfRate:                 _num('pfRatePct', base.pfRate * 100) / 100,
        pfBasicThreshold:       _num('pfBasicThreshold', base.pfBasicThreshold),
        pfCapAmount:            _num('pfCapAmount', base.pfCapAmount),
        esicRate:               _num('esicRatePct', base.esicRate * 100) / 100,
        esicGrossThreshold:     _num('esicGrossThreshold', base.esicGrossThreshold),
        ptFemaleThreshold:      _num('ptFemaleThreshold', base.ptFemaleThreshold),
        ptMaleTier1Threshold:   _num('ptMaleTier1Threshold', base.ptMaleTier1Threshold),
        ptMaleTier2Threshold:   _num('ptMaleTier2Threshold', base.ptMaleTier2Threshold),
        ptMaleTier2Amount:      _num('ptMaleTier2Amount', base.ptMaleTier2Amount),
        ptStandardAmount:       _num('ptStandardAmount', base.ptStandardAmount),
        ptFebAmount:            _num('ptFebAmount', base.ptFebAmount),
        employerPfRate:         _num('employerPfRatePct', base.employerPfRate * 100) / 100,
        employerEsicRate:       _num('employerEsicRatePct', base.employerEsicRate * 100) / 100,
        attachmentBPerEmployee: _num('attachmentBPerEmployee', base.attachmentBPerEmployee),
      );

  Future<void> _save() async {
    _notifier.update((_) => _fromControllers(_notifier.config));
    final ok = await _notifier.save();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Formula configuration saved' : 'Error saving configuration')),
      );
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_syncControllers);
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
                  _FormulaHeader(),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _Tok.padH, _Tok.padV, _Tok.padH, _Tok.padV,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── 01  PF ────────────────────────────────────────
                        _Section(
                          tag: '01  PROVIDENT FUND',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('PF Rate',
                                    TextField(
                                      controller: _ctrl['pfRatePct']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '12', suffixText: '%'),
                                    ),
                                    hint: '% of earned basic deducted as PF',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Basic Threshold',
                                    TextField(
                                      controller: _ctrl['pfBasicThreshold']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '15000', suffixText: '₹'),
                                    ),
                                    hint: 'Earned basic at/above this uses the cap',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Cap Amount',
                                    TextField(
                                      controller: _ctrl['pfCapAmount']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '1800', suffixText: '₹'),
                                    ),
                                    hint: 'Flat PF once threshold is crossed',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── 02  ESIC ──────────────────────────────────────
                        _Section(
                          tag: '02  ESIC',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('ESIC Rate',
                                    TextField(
                                      controller: _ctrl['esicRatePct']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '0.75', suffixText: '%'),
                                    ),
                                    hint: '% of earned gross deducted as ESIC',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Gross Threshold',
                                    TextField(
                                      controller: _ctrl['esicGrossThreshold']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '21000', suffixText: '₹'),
                                    ),
                                    hint: 'Full monthly gross above this is ESIC-exempt',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── 03  PROFESSIONAL TAX ──────────────────────────
                        _Section(
                          tag: '03  PROFESSIONAL TAX',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('Female Threshold',
                                    TextField(
                                      controller: _ctrl['ptFemaleThreshold']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '25000', suffixText: '₹'),
                                    ),
                                    hint: 'Earned gross below this → ₹0 PT for women',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Male Tier-1 Threshold',
                                    TextField(
                                      controller: _ctrl['ptMaleTier1Threshold']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '7500', suffixText: '₹'),
                                    ),
                                    hint: 'Earned gross below this → ₹0 PT for men',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Male Tier-2 Threshold',
                                    TextField(
                                      controller: _ctrl['ptMaleTier2Threshold']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '10000', suffixText: '₹'),
                                    ),
                                    hint: 'Below this → Tier-2 flat PT for men',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: _Tok.rowGap),
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('Male Tier-2 Amount',
                                    TextField(
                                      controller: _ctrl['ptMaleTier2Amount']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '175', suffixText: '₹'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Standard PT',
                                    TextField(
                                      controller: _ctrl['ptStandardAmount']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '200', suffixText: '₹'),
                                    ),
                                    hint: 'Non-February PT (top tier / women above threshold)',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('February PT',
                                    TextField(
                                      controller: _ctrl['ptFebAmount']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '300', suffixText: '₹'),
                                    ),
                                    hint: 'February PT for the same groups',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── 04  EMPLOYER CONTRIBUTIONS ────────────────────
                        _Section(
                          tag: '04  EMPLOYER CONTRIBUTIONS (ATTACHMENT A/B)',
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _LF('Employer PF Rate',
                                    TextField(
                                      controller: _ctrl['employerPfRatePct']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '13', suffixText: '%'),
                                    ),
                                    hint: '% of total earned basic (employer share)',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Employer ESIC Rate',
                                    TextField(
                                      controller: _ctrl['employerEsicRatePct']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '3.25', suffixText: '%'),
                                    ),
                                    hint: '% of ESIC-eligible earned gross (employer share)',
                                  ),
                                ),
                                const SizedBox(width: _Tok.gutter),
                                Expanded(
                                  child: _LF('Attachment B / Employee',
                                    TextField(
                                      controller: _ctrl['attachmentBPerEmployee']!,
                                      style     : _Tok.tsInput,
                                      keyboardType: TextInputType.number,
                                      decoration: _inputDec(hint: '1753', suffixText: '₹'),
                                    ),
                                    hint: 'Fixed welfare amount per active employee',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: _Tok.rowGap),

                        // ── Save button ──────────────────────────────────
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
                            label: Text(_notifier.isSaving ? 'Saving…' : 'Save Formula Config'),
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
class _FormulaHeader extends StatelessWidget {
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
            Icons.calculate_outlined,
            color: Colors.white,
            size : 13,
          ),
        ),
        const SizedBox(width: 8),
        Text('SALARY FORMULA CONFIGURATION', style: _Tok.tsCardTitle),
        const Spacer(),
      ],
    ),
  );
}

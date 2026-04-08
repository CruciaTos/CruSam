import 'package:flutter/material.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../data/models/company_config_model.dart';
import '../notifiers/settings_notifier.dart';

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
        padding: const EdgeInsets.all(AppSpacing.pagePadding),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AppCard(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _CompanySection(ctrl: _ctrl)),
                      const SizedBox(width: AppSpacing.xl),
                      Expanded(child: _BankSection(ctrl: _ctrl)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: _ctrl['declarationText']!,
                    label: 'Declaration Text',
                    maxLines: 3,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton.icon(
                        onPressed: _notifier.isSaving ? null : _save,
                        icon: _notifier.isSaving
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save, size: 18),
                        label: const Text('Save Configuration'),
                      ),
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

class _CompanySection extends StatelessWidget {
  final Map<String, TextEditingController> ctrl;
  const _CompanySection({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Company Details', style: AppTextStyles.h4),
      const Divider(height: 20),
      _gap(AppTextField(controller: ctrl['companyName']!, label: 'Company Name')),
      _gap(AppTextField(controller: ctrl['address']!, label: 'Address', maxLines: 3)),
      _gap(AppTextField(controller: ctrl['phone']!, label: 'Phone')),
      Row(children: [
        Expanded(child: AppTextField(controller: ctrl['gstin']!, label: 'GSTIN', monospace: true)),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: AppTextField(controller: ctrl['pan']!, label: 'PAN', monospace: true)),
      ]),
      const SizedBox(height: AppSpacing.md),
      AppTextField(controller: ctrl['jurisdiction']!, label: 'Jurisdiction'),
    ],
  );

  static Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: w);
}

class _BankSection extends StatelessWidget {
  final Map<String, TextEditingController> ctrl;
  const _BankSection({required this.ctrl});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Bank Configuration', style: AppTextStyles.h4),
      const Divider(height: 20),
      _gap(AppTextField(controller: ctrl['bankName']!, label: 'Bank Name')),
      _gap(AppTextField(controller: ctrl['branch']!, label: 'Branch')),
      _gap(AppTextField(controller: ctrl['accountNo']!, label: 'Account Number', monospace: true)),
      AppTextField(controller: ctrl['ifscCode']!, label: 'IFSC Code', monospace: true,
          capitalization: TextCapitalization.characters),
    ],
  );

  static Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: AppSpacing.md), child: w);
}
// voucher_builder_screen.dart
// ════════════════════════════════════════════════════════════════════════════
//  VoucherBuilderScreen — Metadata card completely redesigned.
//  Design system: stark black-and-white, Noto Sans family, editorial grid.
//
//  pubspec.yaml fonts (adjust filenames to match your /assets/fonts/ contents):
//
//  fonts:
//    - family: NotoSans
//      fonts:
//        - asset: assets/fonts/NotoSans-Regular.ttf
//        - asset: assets/fonts/NotoSans-Medium.ttf
//          weight: 500
//        - asset: assets/fonts/NotoSans-SemiBold.ttf
//          weight: 600
//        - asset: assets/fonts/NotoSans-Bold.ttf
//          weight: 700
//    - family: NotoSansCondensed
//      fonts:
//        - asset: assets/fonts/NotoSans_Condensed-Regular.ttf
//        - asset: assets/fonts/NotoSans_Condensed-Medium.ttf
//          weight: 500
//        - asset: assets/fonts/NotoSans_Condensed-SemiBold.ttf
//          weight: 600
//        - asset: assets/fonts/NotoSans_Condensed-Bold.ttf
//          weight: 700
//    - family: NotoSansExtraCondensed
//      fonts:
//        - asset: assets/fonts/NotoSans_ExtraCondensed-Regular.ttf
//        - asset: assets/fonts/NotoSans_ExtraCondensed-Bold.ttf
//          weight: 700
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/voucher_model.dart';
import '../../../shared/widgets/app_card.dart';
import '../notifiers/item_description_notifier.dart';
import '../notifiers/voucher_notifier.dart';
import '../services/excel_export_service.dart';
import '../services/pdf_export_service.dart';               // ← added for PDF export
import '../widgets/voucher_row_widget.dart' as voucher_row_widget;
import '../widgets/calculations_card.dart';
import '../widgets/bank_split_card.dart';
import '../widgets/invoice_preview_dialog.dart';
import '../widgets/item_description_field.dart';

// ────────────────────────────────────────────────────────────────────────────
//  Design tokens  (private to this file)
// ────────────────────────────────────────────────────────────────────────────

class _Tok {
  _Tok._();

  // Colours — indigo palette
  static const ink          = Color(0xFF1E1B4B);  // indigo-950
  static const inkLight     = Color(0xFF3730A3);  // indigo-700
  static const inkMuted     = Color(0xFF818CF8);  // indigo-400
  static const border       = Color(0xFFC7D2FE);  // indigo-200
  static const borderFocus  = Color(0xFF4338CA);  // indigo-700
  static const divider      = Color(0xFFE0E7FF);  // indigo-100
  static const surface      = Color(0xFFFFFFFF);  // white
  static const surfaceAlt   = Color(0xFFEEF2FF);  // indigo-50
  static const badgeBg      = Color(0xFF1E1B4B);  // indigo-950
  static const badgeFg      = Color(0xFFFFFFFF);  // white
  static const dotFilled    = Color(0xFF4338CA);  // indigo-700
  static const dotEmpty     = Color(0xFFC7D2FE);  // indigo-200

  // Font families
  static const fbody       = 'NotoSans';
  static const fcond       = 'NotoSansCondensed';
  static const fxcond      = 'NotoSansExtraCondensed';

  // Text styles
  static const tsCardTitle = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 12.5,
    letterSpacing: 1.6,
    color        : inkLight,
  );

  static const tsBadge = TextStyle(
    fontFamily   : fxcond,
    fontWeight   : FontWeight.w700,
    fontSize     : 9.5,
    letterSpacing: 2.0,
    color        : badgeFg,
  );

  static const tsLabel = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w600,
    fontSize     : 9.5,
    letterSpacing: 1.0,
    color        : inkMuted,
  );

  static const tsInput = TextStyle(
    fontFamily   : fbody,
    fontWeight   : FontWeight.w400,
    fontSize     : 13,
    color        : ink,
    height       : 1.4,
  );

  static const tsInputMono = TextStyle(
    fontFamily   : fbody,
    fontWeight   : FontWeight.w500,
    fontSize     : 13,
    color        : ink,
    letterSpacing: 0.3,
    height       : 1.4,
  );

  static const tsMeta = TextStyle(
    fontFamily   : fcond,
    fontWeight   : FontWeight.w400,
    fontSize     : 11,
    letterSpacing: 0.2,
    color        : inkMuted,
  );

  // Dimensions
  static const double padH    = 22.0;
  static const double padV    = 20.0;
  static const double gutter  = 14.0;
  static const double rowGap  = 22.0;
  static const double radius  =  6.0;
  static const double cRadius = 10.0;  // card corner radius
}

// ── Shared field decoration ──────────────────────────────────────────────────

InputDecoration _inputDec({String? hint, Widget? suffix, bool mono = false}) =>
    InputDecoration(
      hintText      : hint,
      hintStyle     : const TextStyle(
        fontFamily   : _Tok.fbody,
        fontSize     : 12,
        color        : _Tok.inkMuted,
        fontWeight   : FontWeight.w400,
      ),
      suffixIcon    : suffix,
      isDense       : true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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

// ── Label + Field column ─────────────────────────────────────────────────────

class _LF extends StatelessWidget {
  final String label;
  final Widget child;
  const _LF(this.label, this.child);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _Tok.tsLabel),
          const SizedBox(height: 5),
          child,
        ],
      );
}

// ── Section divider row with numbered tag ────────────────────────────────────

class _Section extends StatelessWidget {
  final String tag;
  final List<Widget> children; // pre-wrapped Expanded/SizedBox
  const _Section({required this.tag, required this.children});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // tag + rule
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color       : _Tok.badgeBg,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(tag, style: _Tok.tsBadge),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Divider(height: 1, thickness: 1, color: _Tok.divider),
            ),
          ]),
          const SizedBox(height: 11),
          // fields
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ],
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  _MetadataCard
// ════════════════════════════════════════════════════════════════════════════

class _MetadataCard extends StatefulWidget {
  final VoucherNotifier notifier;
  const _MetadataCard({required this.notifier});

  @override
  State<_MetadataCard> createState() => _MetadataCardState();
}

class _MetadataCardState extends State<_MetadataCard> {
  // controllers
  late final _titleCtrl   = TextEditingController();
  late final _dateCtrl    = TextEditingController();
  late final _clientCtrl  = TextEditingController();
  late final _gstnCtrl    = TextEditingController();
  late final _addressCtrl = TextEditingController();
  late final _poCtrl      = TextEditingController();
  late final _billNoCtrl  = TextEditingController();

  late final _descNotifier = ItemDescriptionNotifier();

  @override
  void initState() {
    super.initState();
    _sync(widget.notifier.current);
    _descNotifier.load();
    // Remove first — guards against hot-reload leaving a stale reference
    // from a previous version of this method on the singleton notifier.
    widget.notifier.removeListener(_onChanged);
    widget.notifier.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant _MetadataCard old) {
    super.didUpdateWidget(old);
    if (old.notifier != widget.notifier) {
      old.notifier.removeListener(_onChanged);
      _sync(widget.notifier.current);
      widget.notifier.addListener(_onChanged);
    }
  }

  /// Converts stored ISO `YYYY-MM-DD` → display `dd/mm/yyyy`.
  static String _fmt(String iso) {
    final p = iso.split('-');
    if (p.length != 3) return iso;
    // Changed: now uses '/' and dd/mm/yyyy order
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  void _sync(VoucherModel c) {
    if (_titleCtrl.text   != c.title)          _titleCtrl.text   = c.title;
    if (_dateCtrl.text    != _fmt(c.date))     _dateCtrl.text    = _fmt(c.date);
    if (_clientCtrl.text  != c.clientName)     _clientCtrl.text  = c.clientName;
    if (_gstnCtrl.text    != c.clientGstin)    _gstnCtrl.text    = c.clientGstin;
    if (_addressCtrl.text != c.clientAddress)  _addressCtrl.text = c.clientAddress;
    if (_poCtrl.text      != c.poNo)           _poCtrl.text      = c.poNo;
    if (_billNoCtrl.text  != c.billNo)         _billNoCtrl.text  = c.billNo;
  }

  void _onChanged() {
    final c = widget.notifier.current;
    if (_titleCtrl.text   != c.title        ||
        _dateCtrl.text    != c.date         ||
        _clientCtrl.text  != c.clientName   ||
        _gstnCtrl.text    != c.clientGstin  ||
        _poCtrl.text      != c.poNo         ||
        _billNoCtrl.text  != c.billNo       ||
        _addressCtrl.text != c.clientAddress) {
      _sync(c);
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChanged);
    _titleCtrl.dispose();   _dateCtrl.dispose();
    _clientCtrl.dispose();  _gstnCtrl.dispose();
    _addressCtrl.dispose(); _poCtrl.dispose();
    _billNoCtrl.dispose();
    _descNotifier.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final p = await showDatePicker(
      context    : context,
      initialDate: DateTime.tryParse(widget.notifier.current.date) ??
          DateTime.now(),
      firstDate  : DateTime(2000),
      lastDate   : DateTime(2100),
      builder    : (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary  : _Tok.ink,
            onPrimary: Colors.white,
            surface  : Colors.white,
            onSurface: _Tok.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted || p == null) return;
    // Store internally as YYYY-MM-DD; _sync/_fmt will display as dd/mm/yyyy.
    widget.notifier.update(
      (c) => c.copyWith(date: p.toIso8601String().split('T').first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notifier;
    return Container(
      decoration: BoxDecoration(
        color       : _Tok.surface,
        border      : Border.all(color: _Tok.border),
        borderRadius: BorderRadius.circular(_Tok.cRadius),
        boxShadow   : [
          BoxShadow(
            color    : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset   : const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header bar ─────────────────────────────────────────────────
          _MetaHeader(notifier: n),

          // ── Body ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              _Tok.padH, _Tok.padV, _Tok.padH, _Tok.padV,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── 01  VOUCHER ─────────────────────────────────────────
                _Section(
                  tag: '01  VOUCHER',
                  children: [
                    Expanded(
                      flex: 5,
                      child: _LF('Voucher Title',
                        TextField(
                          controller: _titleCtrl,
                          style     : _Tok.tsInput,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(title: v)),
                          decoration: _inputDec(
                            hint: 'e.g. Exp. MAR-2026 aarti',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: _Tok.gutter),
                    Expanded(
                      flex: 3,
                      child: _LF('Department Code',
                        _DeptDropdown(notifier: n),
                      ),
                    ),
                    const SizedBox(width: _Tok.gutter),
                    Expanded(
                      flex: 2,
                      child: _LF('Date',
                        TextField(
                          controller: _dateCtrl,
                          style     : _Tok.tsInputMono,
                          readOnly  : true,
                          onTap     : _pickDate,
                          decoration: _inputDec(
                            suffix: const Icon(
                              Icons.calendar_today_outlined,
                              size : 14,
                              color: _Tok.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: _Tok.rowGap),

                // ── 02  CLIENT ──────────────────────────────────────────
                _Section(
                  tag: '02  CLIENT',
                  children: [
                    Expanded(
                      flex: 4,
                      child: _LF('Client Name',
                        TextField(
                          controller: _clientCtrl,
                          style     : _Tok.tsInput,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(clientName: v)),
                          decoration: _inputDec(hint: 'Full legal name'),
                        ),
                      ),
                    ),
                    const SizedBox(width: _Tok.gutter),
                    Expanded(
                      flex: 3,
                      child: _LF('Client GSTIN',
                        TextField(
                          controller: _gstnCtrl,
                          style     : _Tok.tsInputMono,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(clientGstin: v)),
                          decoration: _inputDec(hint: '22AAAAA0000A1Z5'),
                        ),
                      ),
                    ),
                    const SizedBox(width: _Tok.gutter),
                    Expanded(
                      flex: 2,
                      child: _LF('Bill No.',
                        TextField(
                          controller: _billNoCtrl,
                          style     : _Tok.tsInputMono,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(billNo: v)),
                          decoration: _inputDec(hint: 'AE/01/25-26'),
                        ),
                      ),
                    ),
                    const SizedBox(width: _Tok.gutter),
                    Expanded(
                      flex: 1,
                      child: _LF('PO No.',
                        TextField(
                          controller: _poCtrl,
                          style     : _Tok.tsInputMono,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(poNo: v)),
                          decoration: _inputDec(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: _Tok.rowGap),

                // ── 03  ADDRESS ─────────────────────────────────────────
                _Section(
                  tag: '03  ADDRESS',
                  children: [
                    Expanded(
                      child: _LF(
                        'Client Address  —  // makes new lines in previews',
                        TextField(
                          controller: _addressCtrl,
                          style     : _Tok.tsInput,
                          maxLines  : 2,
                          onChanged : (v) =>
                              n.update((c) => c.copyWith(clientAddress: v)),
                          decoration: _inputDec(
                            hint: 'Address line 1, Area, City – Pincode',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: _Tok.rowGap),

                // ── 04  ITEM DESCRIPTION ────────────────────────────────
                _Section(
                  tag: '04  ITEM DESCRIPTION',
                  children: [
                    Expanded(
                      child: _LF('Description shown on invoice',
                        ItemDescriptionField(
                          value    : n.current.itemDescription,
                          onChanged: (v) =>
                              n.update((c) => c.copyWith(itemDescription: v)),
                          notifier : _descNotifier,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _MetaHeader
// ════════════════════════════════════════════════════════════════════════════

class _MetaHeader extends StatelessWidget {
  final VoucherNotifier notifier;
  const _MetaHeader({required this.notifier});

  @override
  Widget build(BuildContext context) {
    final title    = notifier.current.title.trim();
    final hasTitle = title.isNotEmpty;

    return Container(
      height     : 44,
      padding    : const EdgeInsets.symmetric(horizontal: _Tok.padH),
      decoration : const BoxDecoration(
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
          // icon chip
          Container(
            width : 26,
            height: 26,
            decoration: BoxDecoration(
              color       : _Tok.ink,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: Colors.white,
              size : 14,
            ),
          ),
          const SizedBox(width: 10),

          Text('INVOICE METADATA', style: _Tok.tsCardTitle),

          // live title preview
          if (hasTitle) ...[
            const SizedBox(width: 12),
            Container(width: 1, height: 12, color: _Tok.border),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                title,
                maxLines : 1,
                overflow : TextOverflow.ellipsis,
                style    : _Tok.tsMeta.copyWith(
                  fontFamily : _Tok.fbody,
                  color      : _Tok.inkLight,
                  fontWeight : FontWeight.w500,
                  fontSize   : 12,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],

          const Spacer(),

        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ════════════════════════════════════════════════════════════════════════════
//  _DeptDropdown  —  uses DropdownMenu (M3) which always opens below
// ════════════════════════════════════════════════════════════════════════════

class _DeptDropdown extends StatelessWidget {
  final VoucherNotifier notifier;
  const _DeptDropdown({required this.notifier});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (ctx, box) => DropdownMenu<String>(
          key             : ValueKey(notifier.current.deptCode),
          initialSelection: notifier.current.deptCode,
          width           : box.maxWidth,
          textStyle       : _Tok.tsInput,
          enableFilter    : false,   // ← added
          enableSearch    : false,   // ← added
          trailingIcon    : const Icon(
            Icons.keyboard_arrow_down_rounded,
            size : 18,
            color: _Tok.inkMuted,
          ),
          selectedTrailingIcon: const Icon(
            Icons.keyboard_arrow_up_rounded,
            size : 18,
            color: _Tok.inkLight,
          ),
          menuStyle: MenuStyle(
            backgroundColor    : const WidgetStatePropertyAll(_Tok.surface),
            surfaceTintColor   : const WidgetStatePropertyAll(Colors.transparent),
            elevation          : const WidgetStatePropertyAll(6),
            padding            : const WidgetStatePropertyAll(
              EdgeInsets.symmetric(vertical: 4),
            ),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_Tok.radius + 2),
                side        : const BorderSide(color: _Tok.border),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            isDense       : true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10, vertical: 3,   // ← reduced from 9
            ),
            filled        : true,
            fillColor     : _Tok.surface,
            enabledBorder : OutlineInputBorder(
              borderRadius: BorderRadius.circular(_Tok.radius),
              borderSide  : const BorderSide(color: _Tok.border),
            ),
            focusedBorder : OutlineInputBorder(
              borderRadius: BorderRadius.circular(_Tok.radius),
              borderSide  : const BorderSide(
                color: _Tok.borderFocus, width: 1.5,
              ),
            ),
          ),
          onSelected: (v) {
            if (v != null)
              notifier.update((c) => c.copyWith(deptCode: v));
          },
          dropdownMenuEntries: AppConstants.deptCodes
              .map((d) => DropdownMenuEntry<String>(
                    value: d,
                    label: d,
                    style: ButtonStyle(
                      textStyle: const WidgetStatePropertyAll(
                        TextStyle(
                          fontFamily: _Tok.fbody,
                          fontSize  : 13,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      foregroundColor: const WidgetStatePropertyAll(_Tok.ink),
                      backgroundColor: WidgetStateProperty.resolveWith((s) =>
                        s.contains(WidgetState.hovered)
                            ? _Tok.surfaceAlt
                            : _Tok.surface,
                      ),
                    ),
                  ))
              .toList(),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  VoucherBuilderScreen  (unchanged logic, only _MetadataCard is replaced)
// ════════════════════════════════════════════════════════════════════════════

class VoucherBuilderScreen extends StatefulWidget {
  const VoucherBuilderScreen({super.key});
  @override
  State<VoucherBuilderScreen> createState() => _VoucherBuilderScreenState();
}

class _VoucherBuilderScreenState extends State<VoucherBuilderScreen> {
  final _notifier = VoucherNotifier.instance;
  bool _exporting         = false;
  bool _exportingBankSheet = false;

  @override
  void initState() {
    super.initState();
    _notifier.loadDependencies();
  }

  Future<void> _saveVoucher() async {
    if (_notifier.current.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a voucher title')),
      );
      return;
    }
    final ok = await _notifier.saveVoucher();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok ? 'Invoice saved successfully' : 'Error saving invoice',
          ),
        ),
      );
    }
  }

  Future<void> _exportBankSheet() async {
    if (_exportingBankSheet) return;
    if (_notifier.current.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Add at least one row before exporting the bank sheet'),
        ),
      );
      return;
    }
    setState(() => _exportingBankSheet = true);
    try {
      final path = await ExcelExportService.exportBankDisbursement(
        _notifier.enriched, _notifier.config,
        idbiToOther: _notifier.idbiToOther,
        idbiToIdbi : _notifier.idbiToIdbi,
      );
      await ExcelExportService.openFile(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Bank sheet saved: ${File(path).uri.pathSegments.last}',
            ),
            action: SnackBarAction(
              label    : 'Open Folder',
              onPressed: () => _openFolder(File(path).parent.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('Bank sheet export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exportingBankSheet = false);
    }
  }

// ──────────────────────────────────────────────────────────────────────────
//  FINALISE & EXPORT  —  PDF (tax invoice) + Excel (bank sheet only)
// ──────────────────────────────────────────────────────────────────────────
Future<void> _finaliseAndExport() async {
  if (_exporting) return;

  if (_notifier.current.title.trim().isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Please enter a voucher title before exporting')),
    );
    return;
  }
  if (_notifier.current.rows.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add at least one row before exporting')),
    );
    return;
  }

  setState(() => _exporting = true);

  if (!mounted) return;
  showDialog(
    context          : context,
    barrierDismissible: false,
    builder          : (_) => const AlertDialog(
      content: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child  : Row(
          mainAxisSize: MainAxisSize.min,
          children    : [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Generating files…'),
          ],
        ),
      ),
    ),
  );

  String? errorMsg;

  try {
    final voucher = _notifier.enriched;
    final config  = _notifier.config;

    // 1. Save as draft
    await _notifier.saveVoucher();

    // 2. Export PDF bundle (tax invoice + voucher)
    await PdfExportService.exportInvoiceBundle(
      context: context,
      voucher: voucher,
      config: config,
      taxInvoiceMargins: const EdgeInsets.all(24),
      voucherMargins: const EdgeInsets.all(24),
    );

    // 3. Export Excel bank disbursement sheet ONLY
    //    (identical to what "Preview Bank Sheet" produces)
    await ExcelExportService.exportBankDisbursement(
      voucher,
      config,
      idbiToOther: _notifier.idbiToOther,
      idbiToIdbi : _notifier.idbiToIdbi,
    );
  } catch (e, st) {
    errorMsg = '$e\n\n$st';
  } finally {
    if (mounted) setState(() => _exporting = false);
  }

  // Dismiss progress dialog
  if (!mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (errorMsg != null) {
    await showDialog(
      context: context,
      builder: (dc) => AlertDialog(
        title: Row(children: const [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('Export Failed'),
        ]),
        content: SizedBox(
          width: 560, height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              errorMsg!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dc),
            child    : const Text('Close'),
          ),
        ],
      ),
    );
    return;
  }

  if (mounted) _showInvoiceMadeOverlay();
}
  void _showInvoiceMadeOverlay() {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.indigo600, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  color: AppColors.emerald600,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Text(
                  'Invoice Made',
                  style: AppTextStyles.h4.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 5), () {
      entry.remove();
    });
  }

  static void _openFolder(String folder) {
    try {
      if (Platform.isWindows)      Process.run('explorer', [folder]);
      else if (Platform.isMacOS)   Process.run('open',     [folder]);
      else if (Platform.isLinux)   Process.run('xdg-open', [folder]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: _notifier,
        builder   : (ctx, _) {
          if (_notifier.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.pagePadding),
            child  : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children          : [
                // ── Redesigned metadata card ──────────────────────────
                _MetadataCard(notifier: _notifier),

                const SizedBox(height: AppSpacing.xl),
                _RowsTable(notifier: _notifier),
                const SizedBox(height: AppSpacing.xl),

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children          : [
                    Expanded(
                      child: BankSplitCard(
                        idbiToOther: _notifier.idbiToOther,
                        idbiToIdbi : _notifier.idbiToIdbi,
                        baseTotal  : _notifier.baseTotal,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(
                      child: CalculationsCard(
                        baseTotal : _notifier.baseTotal,
                        cgst      : _notifier.cgst,
                        sgst      : _notifier.sgst,
                        roundOff  : _notifier.roundOff,
                        finalTotal: _notifier.finalTotal,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),
                _ActionButtons(
                  notifier          : _notifier,
                  onSave            : _saveVoucher,
                  onFinalise        : _finaliseAndExport,
                  exporting         : _exporting,
                  onExportBankSheet : _exportBankSheet,
                  exportingBankSheet: _exportingBankSheet,
                ),
              ],
            ),
          );
        },
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  _RowsTable  (unchanged)
// ════════════════════════════════════════════════════════════════════════════

class _RowsTable extends StatelessWidget {
  final VoucherNotifier notifier;
  const _RowsTable({required this.notifier});

  static const _headers = [
    '#', 'Employee Name', 'Amount', 'From Date', 'To Date',
    'Auto-filled Details', '',
  ];
  static const _fixedLeft  = 36.0;
  static const _fixedRight = 44.0;
  static const _flex       = [3.0, 2.0, 1.6, 1.6, 3.0];

  Map<int, TableColumnWidth> _colWidths(double total) {
    final avail = total - _fixedLeft - _fixedRight;
    final sum   = _flex.fold(0.0, (a, b) => a + b);
    final w     = _flex.map((f) => avail * f / sum).toList();
    return {
      0: const FixedColumnWidth(_fixedLeft),
      1: FixedColumnWidth(w[0]),
      2: FixedColumnWidth(w[1]),
      3: FixedColumnWidth(w[2]),
      4: FixedColumnWidth(w[3]),
      5: FixedColumnWidth(w[4]),
      6: const FixedColumnWidth(_fixedRight),
    };
  }

  TableRow _headerRow(Map<int, TableColumnWidth> _) => TableRow(
        decoration: const BoxDecoration(
          color : AppColors.slate50,
          border: Border(
            bottom: BorderSide(
              color: const Color.fromARGB(255, 21, 39, 81),
              width: 0.5,
            ),
          ),
        ),
        children: _headers
            .map((h) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 10,
                  ),
                  child: Text(h,
                      style: AppTextStyles.label.copyWith(
                        color     : AppColors.slate500,
                        fontWeight: FontWeight.w700,
                      )),
                ))
            .toList(growable: false),
      );

  List<TableRow> _dataRows() {
    final counts = <String, int>{};
    for (final r in notifier.current.rows) {
      if (r.employeeId.isNotEmpty) {
        counts[r.employeeId] = (counts[r.employeeId] ?? 0) + 1;
      }
    }
    return List.generate(notifier.current.rows.length, (i) {
      final row = notifier.current.rows[i];
      final dup = row.employeeId.isNotEmpty &&
          (counts[row.employeeId] ?? 0) > 1;
      return voucher_row_widget.buildVoucherRow(
        index            : i,
        row              : row,
        employees        : notifier.employees,
        onSelectEmployee : (id) => notifier.selectEmployee(row.id, id),
        onAmountChanged  : (a) =>
            notifier.updateRow(row.id, (r) => r.copyWith(amount: a)),
        onFromDateChanged: (d) =>
            notifier.updateRow(row.id, (r) => r.copyWith(fromDate: d)),
        onToDateChanged  : (d) =>
            notifier.updateRow(row.id, (r) => r.copyWith(toDate: d)),
        onRemove         : () => notifier.removeRow(row.id),
        highlight        : dup,
      );
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color       : AppColors.white,
          border      : Border.all(
            color: const Color.fromARGB(255, 21, 39, 81),
            width: 0.5,
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radius - 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children          : [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10,
              ),
              decoration: BoxDecoration(
                color : AppColors.slate50,
                border: const Border(
                  bottom: BorderSide(
                    color: Color.fromARGB(255, 21, 39, 81),
                    width: 0.5,
                  ),
                ),
                borderRadius: const BorderRadius.only(
                  topLeft : Radius.circular(AppSpacing.radius - 1),
                  topRight: Radius.circular(AppSpacing.radius - 1),
                ),
              ),
              child: Row(children: [
                Text('Labour Disbursement Details',
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  '${notifier.current.rows.length} '
                  'row${notifier.current.rows.length == 1 ? '' : 's'}',
                  style: AppTextStyles.small,
                ),
              ]),
            ),
            LayoutBuilder(builder: (ctx, constraints) {
              final cw = _colWidths(constraints.maxWidth);
              return Table(
                columnWidths            : cw,
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children               : [
                  _headerRow(cw),
                  ..._dataRows(),
                ],
              );
            }),
            if (notifier.current.rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child  : Column(children: [
                  Icon(Icons.table_rows_outlined,
                      size: 36, color: AppColors.slate300),
                  const SizedBox(height: 8),
                  Text('No Employees yet.', style: AppTextStyles.small),
                ]),
              ),
            Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AppColors.slate200),
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft : Radius.circular(AppSpacing.radius - 1),
                  bottomRight: Radius.circular(AppSpacing.radius - 1),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child  : Center(
                child: TextButton.icon(
                  onPressed: notifier.addRow,
                  icon     : const Icon(Icons.add_circle_outline,
                      size: 17, color: AppColors.indigo600),
                  label    : Text('Add Employee',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color     : AppColors.indigo600,
                        fontWeight: FontWeight.w600,
                      )),
                  style: TextButton.styleFrom(
                    padding        : const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8,
                    ),
                    backgroundColor: AppColors.indigo50,
                    shape          : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  _ActionButtons  (with white text/icons as requested)
// ════════════════════════════════════════════════════════════════════════════

class _ActionButtons extends StatelessWidget {
  final VoucherNotifier notifier;
  final VoidCallback onSave;
  final VoidCallback onFinalise;
  final bool exporting;
  final VoidCallback onExportBankSheet;
  final bool exportingBankSheet;

  const _ActionButtons({
    required this.notifier,
    required this.onSave,
    required this.onFinalise,
    required this.exporting,
    required this.onExportBankSheet,
    required this.exportingBankSheet,
  });

  @override
  Widget build(BuildContext context) => Wrap(
        spacing   : AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        alignment : WrapAlignment.end,
        children  : [
          // ── Discard Draft (white text + icon) ──────────────────────────
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (dc) => AlertDialog(
                  title  : const Text('Discard Draft'),
                  content: const Text(
                    'This will clear all current progress. Cannot be undone.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dc, false),
                      child    : const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dc, true),
                      style    : TextButton.styleFrom(
                        foregroundColor: const Color(0xFF11083D),
                      ),
                      child: const Text('Discard'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) async => notifier.discardDraft(),
                );
              }
            },
            icon : const Icon(Icons.delete_outline, size: 16, color: Colors.white),
            label: const Text('Discard Draft', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFFAE3E3)),
            ),
          ),

          // ── Save as Draft (white text + icon) ──────────────────────────
          OutlinedButton.icon(
            onPressed: onSave,
            icon     : const Icon(Icons.save, size: 16, color: Colors.white),
            label    : const Text('Save as Draft', style: TextStyle(color: Colors.white)),
            style    : OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.emerald100),
            ),
          ),

          // ── Preview Invoice (white text + icon) ────────────────────────
          OutlinedButton.icon(
            onPressed: () => InvoicePreviewDialog.show(
              context, notifier, notifier.config, PreviewType.invoice,
            ),
            icon : const Icon(Icons.description_outlined, size: 16, color: Colors.white),
            label: const Text('Preview Invoice', style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.slate600),
            ),
          ),

          // ── Preview Bank Sheet (white text + icon) ─────────────────────
          OutlinedButton.icon(
            onPressed: exportingBankSheet ? null : onExportBankSheet,
            icon: exportingBankSheet
                ? const SizedBox(
                    width : 14,
                    height: 14,
                    child : CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_outlined, size: 16, color: Colors.white),
            label: Text(
              exportingBankSheet ? 'Exporting…' : 'Preview Bank Sheet',
              style: const TextStyle(color: Colors.white),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.slate600),
            ),
          ),

          // ── Finalise & Export (unchanged style, uses new logic) ────────
          ElevatedButton.icon(
            onPressed: exporting ? null : onFinalise,
            icon: exporting
                ? const SizedBox(
                    width : 14,
                    height: 14,
                    child : CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Icon(Icons.file_download_outlined, size: 16),
            label: Text(exporting ? 'Exporting…' : 'Finalise & Export'),
          ),
        ],
      );
}
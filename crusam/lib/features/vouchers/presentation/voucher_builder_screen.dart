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
import '../widgets/voucher_row_widget.dart' as voucher_row_widget;
import '../widgets/calculations_card.dart';
import '../widgets/bank_split_card.dart';
import '../widgets/invoice_preview_dialog.dart';
import '../widgets/item_description_field.dart';
import 'package:crusam/keyboard_navigation_phase1_demo.dart'
    show KeyboardNavigableForm, KeyboardNavigationController;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../data/models/voucher_model.dart';
import '../../salary/notifier/salary_data_notifier.dart';
import '../../../shared/widgets/app_card.dart';
import '../notifiers/item_description_notifier.dart';
import '../notifiers/voucher_notifier.dart';
import '../services/excel_export_service.dart';
import 'package:crusam/features/pdf/service/widget_pdf_export_service.dart';
import 'package:crusam/shared/widgets/full_screen_loader.dart';

// ────────────────────────────────────────────────────────────────────────────
//  Design tokens  (private to this file)
// ────────────────────────────────────────────────────────────────────────────

class _Tok {
  _Tok._();

  // Colours — indigo palette
  static const ink         = Color(0xFF1E1B4B); // indigo-950
  static const inkLight    = Color(0xFF3730A3); // indigo-700
  static const inkMuted    = Color(0xFF818CF8); // indigo-400
  static const border      = Color(0xFFC7D2FE); // indigo-200
  static const borderFocus = Color(0xFF4338CA); // indigo-700
  static const divider     = Color(0xFFE0E7FF); // indigo-100
  static const surface     = Color(0xFFFFFFFF); // white
  static const surfaceAlt  = Color(0xFFEEF2FF); // indigo-50
  static const badgeBg     = Color(0xFF1E1B4B); // indigo-950
  static const badgeFg     = Color(0xFFFFFFFF); // white
  static const dotFilled   = Color(0xFF4338CA); // indigo-700
  static const dotEmpty    = Color(0xFFC7D2FE); // indigo-200

  // Font families
  static const fbody  = 'NotoSans';
  static const fcond  = 'NotoSansCondensed';
  static const fxcond = 'NotoSansExtraCondensed';

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
    fontFamily: fbody,
    fontWeight: FontWeight.w400,
    fontSize  : 13,
    color     : ink,
    height    : 1.4,
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
  static const double cRadius = 10.0; // card corner radius
}

// ── Shared field decoration ──────────────────────────────────────────────────

InputDecoration _inputDec({String? hint, Widget? suffix, bool mono = false}) =>
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
  final VoidCallback    onMoveToAddEmployee;
  final FocusNode       itemDescriptionFocusNode; // ← lifted from State
  const _MetadataCard({
    required this.notifier,
    required this.onMoveToAddEmployee,
    required this.itemDescriptionFocusNode,
  });

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

  // focus nodes (itemDescriptionFocusNode now comes from widget)
  late final _titleFocus   = FocusNode();
  late final _deptFocus    = FocusNode();
  late final _dateFocus    = FocusNode();
  late final _clientFocus  = FocusNode();
  late final _gstnFocus    = FocusNode();
  late final _billNoFocus  = FocusNode();
  late final _poFocus      = FocusNode();
  late final _addressFocus = FocusNode();

  late final _keyboardNavigationController = KeyboardNavigationController([
    _titleFocus,
    _deptFocus,
    _dateFocus,
    _clientFocus,
    _gstnFocus,
    _billNoFocus,
    _poFocus,
    _addressFocus,
    widget.itemDescriptionFocusNode, // ← use the shared node
  ]);

  late final _descNotifier = ItemDescriptionNotifier();

  @override
  void initState() {
    super.initState();
    _sync(widget.notifier.current);
    _descNotifier.load();
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
    return '${p[2]}/${p[1]}/${p[0]}';
  }

  void _sync(VoucherModel c) {
    if (_titleCtrl.text   != c.title)         _titleCtrl.text   = c.title;
    if (_dateCtrl.text    != _fmt(c.date))    _dateCtrl.text    = _fmt(c.date);
    if (_clientCtrl.text  != c.clientName)    _clientCtrl.text  = c.clientName;
    if (_gstnCtrl.text    != c.clientGstin)   _gstnCtrl.text    = c.clientGstin;
    if (_addressCtrl.text != c.clientAddress) _addressCtrl.text = c.clientAddress;
    if (_poCtrl.text      != c.poNo)          _poCtrl.text      = c.poNo;
    if (_billNoCtrl.text  != c.billNo)        _billNoCtrl.text  = c.billNo;
    _syncSalaryMetadata(c);
  }

  void _syncSalaryMetadata(VoucherModel c) {
    final n = SalaryDataNotifier.instance;
    n.setDateIso(c.date);
    n.setBillNo(c.billNo);
    n.setPoNo(c.poNo);
    n.setClientName(c.clientName);
    n.setClientAddr(c.clientAddress);
    n.setClientGstin(c.clientGstin);
  }

  void _onChanged() {
    final c = widget.notifier.current;
    _syncSalaryMetadata(c);
    if (_titleCtrl.text   != c.title        ||
        _dateCtrl.text    != _fmt(c.date)   ||
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
    _titleFocus.dispose();
    _deptFocus.dispose();
    _dateFocus.dispose();
    _clientFocus.dispose();
    _gstnFocus.dispose();
    _billNoFocus.dispose();
    _poFocus.dispose();
    _addressFocus.dispose();
    // ← itemDescriptionFocusNode is owned by _VoucherBuilderScreenState, not disposed here
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
            color     : Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset    : const Offset(0, 2),
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
            child: KeyboardNavigableForm(
              controller: _keyboardNavigationController,
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
                            focusNode : _titleFocus,
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
                          _DeptDropdown(
                            notifier      : n,
                            focusNode     : _deptFocus,
                            onMoveNext    : _keyboardNavigationController.next,
                            onMovePrevious: _keyboardNavigationController.previous,
                          ),
                        ),
                      ),
                      const SizedBox(width: _Tok.gutter),
                      Expanded(
                        flex: 2,
                        child: _LF('Date',
                          TextField(
                            controller: _dateCtrl,
                            focusNode : _dateFocus,
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
                            focusNode : _clientFocus,
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
                            focusNode : _gstnFocus,
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
                            focusNode : _billNoFocus,
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
                            focusNode : _poFocus,
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
                            focusNode : _addressFocus,
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
                            focusNode: widget.itemDescriptionFocusNode, // ← shared node
                            onMoveNext    : widget.onMoveToAddEmployee,
                            onMovePrevious: _keyboardNavigationController.previous,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
      height    : 44,
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style   : _Tok.tsMeta.copyWith(
                  fontFamily   : _Tok.fbody,
                  color        : _Tok.inkLight,
                  fontWeight   : FontWeight.w500,
                  fontSize     : 12,
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
//  _DeptDropdown
// ════════════════════════════════════════════════════════════════════════════

class _DropdownPrimaryIntent extends Intent {
  const _DropdownPrimaryIntent();
}

class _DropdownBackwardIntent extends Intent {
  const _DropdownBackwardIntent();
}

class _DeptDropdown extends StatefulWidget {
  final VoucherNotifier notifier;
  final FocusNode       focusNode;
  final VoidCallback    onMoveNext;
  final VoidCallback    onMovePrevious;

  const _DeptDropdown({
    required this.notifier,
    required this.focusNode,
    required this.onMoveNext,
    required this.onMovePrevious,
  });

  @override
  State<_DeptDropdown> createState() => _DeptDropdownState();
}

class _DeptDropdownState extends State<_DeptDropdown> {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey  = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _hasFocus           = false;
  bool _isOpen             = false;
  bool _selectionCommitted = false;
  int  _highlightedIndex   = 0;

  List<String> get _options      => AppConstants.deptCodes;
  String       get _selectedValue => widget.notifier.current.deptCode;
  int          get _selectedIndex {
    final index = _options.indexOf(_selectedValue);
    return index >= 0 ? index : 0;
  }

  void _handleFocusChange(bool hasFocus) {
    if (_hasFocus == hasFocus) return;
    setState(() => _hasFocus = hasFocus);
    if (hasFocus) {
      if (!_isOpen && !_selectionCommitted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && widget.focusNode.hasFocus && !_isOpen && !_selectionCommitted) {
            _open();
          }
        });
      }
    } else {
      _close(resetCommitted: true);
    }
  }

  void _open() {
    if (_isOpen) return;
    _highlightedIndex    = _selectedIndex;
    _selectionCommitted  = false;
    _overlayEntry        = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context).insert(_overlayEntry!);
    setState(() => _isOpen = true);
  }

  void _close({bool resetCommitted = false}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (!mounted) return;
    setState(() {
      _isOpen = false;
      if (resetCommitted) _selectionCommitted = false;
    });
  }

  void _moveHighlight(int delta) {
    if (!_isOpen || _options.isEmpty) return;
    final next = (_highlightedIndex + delta).clamp(0, _options.length - 1);
    if (next == _highlightedIndex) return;
    setState(() => _highlightedIndex = next);
    _overlayEntry?.markNeedsBuild();
  }

  void _selectIndex(int index, {bool moveNext = false}) {
    final value = _options[index];
    widget.notifier.update((c) => c.copyWith(deptCode: value));
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (!mounted) return;
    setState(() {
      _highlightedIndex    = index;
      _isOpen              = false;
      _selectionCommitted  = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (moveNext) {
        _selectionCommitted = false;
        widget.onMoveNext();
      } else {
        widget.focusNode.requestFocus();
      }
    });
  }

  void _handlePrimaryAction() {
    if (_isOpen) {
      _selectIndex(_highlightedIndex, moveNext: true);
      return;
    }
    if (_selectionCommitted) {
      _selectionCommitted = false;
      widget.onMoveNext();
      return;
    }
    _open();
  }

  void _handleBackwardAction() {
    if (_isOpen) {
      _close(resetCommitted: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.focusNode.requestFocus();
      });
      return;
    }
    _selectionCommitted = false;
    widget.onMovePrevious();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_isOpen) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildOverlay(BuildContext context) {
    final box  = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size.zero;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _close(resetCommitted: true);
              widget.focusNode.requestFocus();
            },
          ),
        ),
        CompositedTransformFollower(
          link           : _layerLink,
          showWhenUnlinked: false,
          offset         : Offset(0, size.height + 4),
          child: Material(
            elevation    : 8,
            borderRadius : BorderRadius.circular(_Tok.radius + 2),
            child: Container(
              width      : size.width,
              constraints: const BoxConstraints(maxHeight: 220),
              decoration : BoxDecoration(
                color       : _Tok.surface,
                border      : Border.all(color: _Tok.borderFocus, width: 1.2),
                borderRadius: BorderRadius.circular(_Tok.radius + 2),
              ),
              child: ListView.builder(
                padding    : const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap : true,
                itemCount  : _options.length,
                itemBuilder: (context, index) {
                  final option      = _options[index];
                  final highlighted = index == _highlightedIndex;
                  final selected    = option == _selectedValue;
                  return InkWell(
                    onTap  : () => _selectIndex(index),
                    onHover: (hovering) {
                      if (!hovering || index == _highlightedIndex) return;
                      setState(() => _highlightedIndex = index);
                      _overlayEntry?.markNeedsBuild();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical  : 10,
                      ),
                      decoration: BoxDecoration(
                        color       : highlighted ? _Tok.surfaceAlt : _Tok.surface,
                        borderRadius: BorderRadius.circular(_Tok.radius),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              option,
                              style: _Tok.tsInput.copyWith(
                                fontWeight: highlighted || selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: highlighted ? _Tok.inkLight : _Tok.ink,
                              ),
                            ),
                          ),
                          if (selected)
                            const Icon(Icons.check, size: 16, color: _Tok.inkLight),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter)                   : _DropdownPrimaryIntent(),
          SingleActivator(LogicalKeyboardKey.enter, shift: true)      : _DropdownBackwardIntent(),
        },
        child: Actions(
          actions: {
            _DropdownPrimaryIntent : CallbackAction<_DropdownPrimaryIntent>(
              onInvoke: (_) { _handlePrimaryAction(); return null; },
            ),
            _DropdownBackwardIntent: CallbackAction<_DropdownBackwardIntent>(
              onInvoke: (_) { _handleBackwardAction(); return null; },
            ),
          },
          child: Focus(
            focusNode    : widget.focusNode,
            onFocusChange: _handleFocusChange,
            onKeyEvent   : _onKeyEvent,
            child: CompositedTransformTarget(
              link: _layerLink,
              child: GestureDetector(
                key     : _fieldKey,
                behavior: HitTestBehavior.opaque,
                onTap   : () {
                  widget.focusNode.requestFocus();
                  if (_isOpen) {
                    _close(resetCommitted: true);
                  } else {
                    _open();
                  }
                },
                child: AnimatedContainer(
                  duration : const Duration(milliseconds: 120),
                  padding  : const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                    color       : _isOpen
                        ? _Tok.surfaceAlt.withOpacity(0.45)
                        : _Tok.surface,
                    borderRadius: BorderRadius.circular(_Tok.radius),
                    border      : Border.all(
                      color: (_isOpen || _hasFocus) ? _Tok.borderFocus : _Tok.border,
                      width: (_isOpen || _hasFocus) ? 1.5 : 1,
                    ),
                    boxShadow: (_isOpen || _hasFocus)
                        ? [
                            BoxShadow(
                              color     : _Tok.borderFocus.withOpacity(0.10),
                              blurRadius: 8,
                              offset    : const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedValue,
                          style   : _Tok.tsInput,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _isOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size : 18,
                        color: _isOpen ? _Tok.inkLight : _Tok.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ════════════════════════════════════════════════════════════════════════════
//  VoucherBuilderScreen
// ════════════════════════════════════════════════════════════════════════════

class VoucherBuilderScreen extends StatefulWidget {
  const VoucherBuilderScreen({super.key});
  @override
  State<VoucherBuilderScreen> createState() => _VoucherBuilderScreenState();
}

class _VoucherBuilderScreenState extends State<VoucherBuilderScreen> {
  final _notifier                = VoucherNotifier.instance;
  final _addEmployeeButtonFocus  = FocusNode();
  final _itemDescriptionFocus    = FocusNode(); // ← lifted here so _RowsTable can reach it
  bool _exporting          = false;
  bool _exportingBankSheet = false;

  @override
  void initState() {
    super.initState();
    _notifier.loadDependencies();
  }

  @override
  void dispose() {
    _addEmployeeButtonFocus.dispose();
    _itemDescriptionFocus.dispose(); // ← owned here, disposed here
    super.dispose();
  }

  Future<void> _saveVoucher() async {
    if (_notifier.current.title.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a voucher title')),
      );
      return;
    }
    showLoader(context, message: 'Saving voucher…');
    try {
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
    } finally {
      hideLoader(context);
    }
  }

  Future<void> _exportBankSheet() async {
    if (_exportingBankSheet) return;
    if (_notifier.current.rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one row before exporting the bank sheet'),
        ),
      );
      return;
    }
    setState(() => _exportingBankSheet = true);
    showLoader(context, message: 'Exporting bank sheet…');
    try {
      await ExcelExportService.exportBankDisbursement(
        _notifier.enriched, _notifier.config,
        idbiToOther: _notifier.idbiToOther,
        idbiToIdbi : _notifier.idbiToIdbi,
      );
      // file saved silently — no snackbar
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
      hideLoader(context);
      if (mounted) setState(() => _exportingBankSheet = false);
    }
  }

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
    showLoader(context, message: 'Generating PDF & Excel…');

    try {
      final voucher = _notifier.enriched;
      final config  = _notifier.config;

      await _notifier.saveVoucherNoReset();

      await WidgetPdfExportService.exportTaxInvoiceAndVoucher(
        voucher: voucher,
        config : config,
      );

      await ExcelExportService.exportBankDisbursement(
        voucher,
        config,
        idbiToOther: _notifier.idbiToOther,
        idbiToIdbi : _notifier.idbiToIdbi,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content        : Text('Export failed: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      hideLoader(context);
      if (mounted) setState(() => _exporting = false);
    }
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
                _MetadataCard(
                  notifier                : _notifier,
                  onMoveToAddEmployee     : () => _addEmployeeButtonFocus.requestFocus(),
                  itemDescriptionFocusNode: _itemDescriptionFocus, // ← passed down
                ),

                const SizedBox(height: AppSpacing.xl),
                _RowsTable(
                  notifier                : _notifier,
                  addEmployeeButtonFocus  : _addEmployeeButtonFocus,
                  itemDescriptionFocusNode: _itemDescriptionFocus, // ← passed down
                ),
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
//  _RowsTable
// ════════════════════════════════════════════════════════════════════════════

class _RowsTable extends StatefulWidget {
  final VoucherNotifier notifier;
  final FocusNode       addEmployeeButtonFocus;
  final FocusNode?      itemDescriptionFocusNode; // ← new
  const _RowsTable({
    required this.notifier,
    required this.addEmployeeButtonFocus,
    this.itemDescriptionFocusNode,
  });

  @override
  State<_RowsTable> createState() => _RowsTableState();
}

class _RowsTableState extends State<_RowsTable> {
  final _employeeFocusNodes  = <String, FocusNode>{};
  final _amountFocusNodes    = <String, FocusNode>{};
  final _fromDateFocusNodes  = <String, FocusNode>{};
  final _toDateFocusNodes    = <String, FocusNode>{};

  VoucherNotifier get notifier => widget.notifier;

  @override
  void initState() {
    super.initState();
    widget.addEmployeeButtonFocus.addListener(_handleAddEmployeeFocusChange);
    widget.addEmployeeButtonFocus.onKeyEvent = _handleAddEmployeeKeyEvent;
  }

  @override
  void didUpdateWidget(covariant _RowsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.addEmployeeButtonFocus != widget.addEmployeeButtonFocus) {
      oldWidget.addEmployeeButtonFocus.removeListener(_handleAddEmployeeFocusChange);
      oldWidget.addEmployeeButtonFocus.onKeyEvent = null;
      widget.addEmployeeButtonFocus.addListener(_handleAddEmployeeFocusChange);
      widget.addEmployeeButtonFocus.onKeyEvent = _handleAddEmployeeKeyEvent;
    }
  }

  /// Shift+Enter on the Add Employee button → jump back to last row's To Date.
  KeyEventResult _handleAddEmployeeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        HardwareKeyboard.instance.isShiftPressed) {
      final rows = notifier.current.rows;
      if (rows.isNotEmpty) {
        _toDateFocusNodes[rows.last.id]?.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleAddEmployeeFocusChange() {
    if (mounted) setState(() {});
  }

  void _disposeNodeMap(Map<String, FocusNode> map) {
    for (final node in map.values) node.dispose();
    map.clear();
  }

  void _syncFocusNodes() {
    final ids = notifier.current.rows.map((r) => r.id).toSet();

    void syncMap(Map<String, FocusNode> map) {
      final removed = map.keys
          .where((id) => !ids.contains(id))
          .toList(growable: false);
      for (final id in removed) map.remove(id)?.dispose();
      for (final id in ids) map.putIfAbsent(id, FocusNode.new);
    }

    syncMap(_employeeFocusNodes);
    syncMap(_amountFocusNodes);
    syncMap(_fromDateFocusNodes);
    syncMap(_toDateFocusNodes);
  }

  @override
  void dispose() {
    widget.addEmployeeButtonFocus.removeListener(_handleAddEmployeeFocusChange);
    widget.addEmployeeButtonFocus.onKeyEvent = null;
    _disposeNodeMap(_employeeFocusNodes);
    _disposeNodeMap(_amountFocusNodes);
    _disposeNodeMap(_fromDateFocusNodes);
    _disposeNodeMap(_toDateFocusNodes);
    super.dispose();
  }

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
              color: Color.fromARGB(255, 21, 39, 81),
              width: 0.5,
            ),
          ),
        ),
        children: _headers
            .map((h) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
      final dup = row.employeeId.isNotEmpty && (counts[row.employeeId] ?? 0) > 1;

      return voucher_row_widget.buildVoucherRow(
        index            : i,
        row              : row,
        employees        : notifier.employees,
        employeeFocusNode: _employeeFocusNodes[row.id],
        amountFocusNode  : _amountFocusNodes[row.id],
        fromDateFocusNode: _fromDateFocusNodes[row.id],
        toDateFocusNode  : _toDateFocusNodes[row.id],
        onSelectEmployee : (id) => notifier.selectEmployee(row.id, id),
        onEmployeeSelected: () => _amountFocusNodes[row.id]?.requestFocus(),
        // Shift+Enter on employee field:
        //   row 0 → back to Item Description
        //   row N → back to previous row's To Date
        onEmployeeMovePrevious: i == 0
            ? () => widget.itemDescriptionFocusNode?.requestFocus()
            : () {
                final prevId = notifier.current.rows[i - 1].id;
                _toDateFocusNodes[prevId]?.requestFocus();
              },
        onAmountChanged     : (a) =>
            notifier.updateRow(row.id, (r) => r.copyWith(amount: a)),
        onAmountSubmitted   : () => _fromDateFocusNodes[row.id]?.requestFocus(),
        onAmountMovePrevious: () => _employeeFocusNodes[row.id]?.requestFocus(),
        onFromDateChanged   : (d) =>
            notifier.updateRow(row.id, (r) => r.copyWith(fromDate: d)),
        onFromDateSubmitted   : () => _toDateFocusNodes[row.id]?.requestFocus(),
        onFromDateMovePrevious: () => _amountFocusNodes[row.id]?.requestFocus(),
        onToDateChanged  : (d) =>
            notifier.updateRow(row.id, (r) => r.copyWith(toDate: d)),
        // Enter on To Date:
        //   next row exists → jump to its employee dropdown
        //   no next row    → jump to Add Employee button
        onToDateSubmitted: () {
          final nextIndex = i + 1;
          if (nextIndex < notifier.current.rows.length) {
            final nextId = notifier.current.rows[nextIndex].id;
            _employeeFocusNodes[nextId]?.requestFocus();
          } else {
            widget.addEmployeeButtonFocus.requestFocus();
          }
        },
        onToDateMovePrevious: () => _fromDateFocusNodes[row.id]?.requestFocus(),
        onRemove            : () => notifier.removeRow(row.id),
        highlight           : dup,
      );
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) {
    _syncFocusNodes();
    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              border: Border(top: BorderSide(color: AppColors.slate200)),
              borderRadius: BorderRadius.only(
                bottomLeft : Radius.circular(AppSpacing.radius - 1),
                bottomRight: Radius.circular(AppSpacing.radius - 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 10),
            child  : Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  boxShadow: widget.addEmployeeButtonFocus.hasFocus
                      ? [
                          BoxShadow(
                            color     : AppColors.indigo500.withOpacity(0.22),
                            blurRadius: 10,
                            offset    : const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: TextButton.icon(
                  focusNode: widget.addEmployeeButtonFocus,
                  onPressed: () {
                    final rowId = notifier.addRow();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _employeeFocusNodes[rowId]?.requestFocus();
                    });
                  },
                  icon : const Icon(Icons.add_circle_outline,
                      size: 17, color: AppColors.indigo600),
                  label: Text('Add Employee',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color     : AppColors.indigo600,
                        fontWeight: FontWeight.w600,
                      )),
                  style: ButtonStyle(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    ),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppSpacing.radius),
                      ),
                    ),
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return const Color(0xFFE0E7FF);
                      }
                      return AppColors.indigo50;
                    }),
                    side: WidgetStateProperty.resolveWith((states) {
                      return BorderSide(
                        color: states.contains(WidgetState.focused)
                            ? AppColors.indigo500
                            : Colors.transparent,
                        width: states.contains(WidgetState.focused) ? 1.4 : 1,
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  _ActionButtons
// ════════════════════════════════════════════════════════════════════════════

class _ActionButtons extends StatelessWidget {
  final VoucherNotifier notifier;
  final VoidCallback    onSave;
  final VoidCallback    onFinalise;
  final bool            exporting;
  final VoidCallback    onExportBankSheet;
  final bool            exportingBankSheet;

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
          // ── Discard Draft ──────────────────────────────────────────────
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
            label: const Text('Discard Draft',
                style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFFAE3E3)),
            ),
          ),

          // ── Save as Draft ──────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: onSave,
            icon     : const Icon(Icons.save, size: 16, color: Colors.white),
            label    : const Text('Save as Draft',
                style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.emerald100),
            ),
          ),

          // ── Preview Invoice ────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () => InvoicePreviewDialog.show(
              context, notifier, notifier.config, PreviewType.invoice,
            ),
            icon : const Icon(Icons.description_outlined,
                size: 16, color: Colors.white),
            label: const Text('Preview Invoice',
                style: TextStyle(color: Colors.white)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.slate600),
            ),
          ),

          // ── Preview Bank Sheet ─────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: exportingBankSheet ? null : onExportBankSheet,
            icon: exportingBankSheet
                ? const SizedBox(
                    width : 14,
                    height: 14,
                    child : CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.account_balance_outlined,
                    size: 16, color: Colors.white),
            label: Text(
              exportingBankSheet ? 'Exporting…' : 'Preview Bank Sheet',
              style: const TextStyle(color: Colors.white),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: AppColors.slate600),
            ),
          ),

          // ── Finalise & Export ──────────────────────────────────────────
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
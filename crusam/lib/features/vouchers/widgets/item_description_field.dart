import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../notifiers/item_description_notifier.dart';

class _ItemDescriptionPrimaryIntent extends Intent {
  const _ItemDescriptionPrimaryIntent();
}

class _ItemDescriptionBackwardIntent extends Intent {
  const _ItemDescriptionBackwardIntent();
}

class ItemDescriptionField extends StatefulWidget {
  final String value;
  final void Function(String) onChanged;
  final ItemDescriptionNotifier notifier;
  final FocusNode? focusNode;
  final VoidCallback? onMoveNext;
  final VoidCallback? onMovePrevious;

  /// Custom background color for the dropdown overlay.
  /// Defaults to [Colors.white] if not provided.
  final Color? overlayBackgroundColor;

  /// Custom border for the dropdown overlay.
  /// Defaults to `Border.all(color: AppColors.slate100)` if not provided.
  final Border? overlayBorder;

  const ItemDescriptionField({
    super.key,
    required this.value,
    required this.onChanged,
    required this.notifier,
    this.focusNode,
    this.onMoveNext,
    this.onMovePrevious,
    this.overlayBackgroundColor,
    this.overlayBorder,
  });

  @override
  State<ItemDescriptionField> createState() => _ItemDescriptionFieldState();
}

class _ItemDescriptionFieldState extends State<ItemDescriptionField>
    with SingleTickerProviderStateMixin {
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  final TextEditingController _addCtrl = TextEditingController();
  final FocusNode _addFocusNode = FocusNode();
  final FocusNode _internalFocusNode = FocusNode();

  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _hasFocus = false;
  bool _selectionCommitted = false;
  int _highlightedIndex = 0;

  bool get _isOpen => _overlayEntry != null;
  FocusNode get _focusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onNotifierChanged);
    widget.notifier.load();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant ItemDescriptionField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.removeListener(_onNotifierChanged);
      widget.notifier.addListener(_onNotifierChanged);
      widget.notifier.load();
    }
  }

  void _onNotifierChanged() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onNotifierChanged);
    _removeOverlay(triggerSetState: false);
    _addCtrl.dispose();
    _addFocusNode.dispose();
    if (widget.focusNode == null) _internalFocusNode.dispose();
    _animationController.dispose();
    super.dispose();
  }

  int get _selectedIndex {
    final items = widget.notifier.items;
    final index = items.indexWhere((item) => ((item['text'] as String?) ?? '') == widget.value);
    return index >= 0 ? index : 0;
  }

  void _handleFocusChange(bool hasFocus) {
    if (_hasFocus == hasFocus) return;
    setState(() => _hasFocus = hasFocus);
    if (hasFocus) {
      if (!_isOpen && !_selectionCommitted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _focusNode.hasFocus && !_isOpen && !_selectionCommitted) {
            _showOverlay();
          }
        });
      }
    } else {
      _removeOverlay(resetCommitted: true);
    }
  }

  void _toggleOverlay() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    if (_isOpen) return;

    _highlightedIndex = _selectedIndex;
    _selectionCommitted = false;
    final overlay = Overlay.of(context);
    _overlayEntry = OverlayEntry(builder: _buildOverlay);
    overlay.insert(_overlayEntry!);
    setState(() {});
    _animationController.forward();
  }

  void _removeOverlay({bool triggerSetState = true, bool resetCommitted = false}) {
    _animationController.reverse().then((_) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (triggerSetState && mounted) {
        setState(() {
          if (resetCommitted) _selectionCommitted = false;
        });
      } else if (resetCommitted) {
        _selectionCommitted = false;
      }
    });
  }

  void _moveHighlight(int delta) {
    final items = widget.notifier.items;
    if (!_isOpen || items.isEmpty) return;
    final next = (_highlightedIndex + delta).clamp(0, items.length - 1);
    if (next == _highlightedIndex) return;
    setState(() => _highlightedIndex = next);
    _overlayEntry?.markNeedsBuild();
  }

  void _selectItem(String text, {bool moveNext = false}) {
    widget.onChanged(text);
    _selectionCommitted = true;
    _removeOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (moveNext) {
        _selectionCommitted = false;
        widget.onMoveNext?.call();
      } else {
        _focusNode.requestFocus();
      }
    });
  }

  void _handlePrimaryAction() {
    final items = widget.notifier.items;
    if (_isOpen) {
      if (items.isEmpty) {
        _removeOverlay(resetCommitted: true);
        widget.onMoveNext?.call();
        return;
      }
      final text = (items[_highlightedIndex]['text'] as String?) ?? '';
      _selectItem(text, moveNext: true);
      return;
    }
    if (_selectionCommitted) {
      _selectionCommitted = false;
      widget.onMoveNext?.call();
      return;
    }
    _showOverlay();
  }

  void _handleBackwardAction() {
    if (_isOpen) {
      _removeOverlay(resetCommitted: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
      return;
    }
    _selectionCommitted = false;
    widget.onMovePrevious?.call();
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

  Future<void> _handleAdd() async {
    final text = _addCtrl.text.trim();
    if (text.isEmpty) return;
    await widget.notifier.add(text);
    if (!mounted) return;
    _addCtrl.clear();
    _overlayEntry?.markNeedsBuild();
    _addFocusNode.requestFocus();
  }

  Widget _buildOverlay(BuildContext context) {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final size = box?.size ?? Size.zero;
    final items = widget.notifier.items;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _removeOverlay,
          ),
        ),
        CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Material(
                elevation: 8,
                shadowColor: Colors.black.withOpacity(0.90),
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  child: Container(
                    width: size.width,
                    constraints: const BoxConstraints(maxHeight: 320),
                    decoration: BoxDecoration(
                      color: widget.overlayBackgroundColor ?? const Color.fromARGB(255, 156, 154, 208),
                      border: widget.overlayBorder ?? Border.all(color: const Color.fromARGB(255, 70, 79, 229)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (items.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(12, 10, 12, 4),
                          ),
                        if (items.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                            child: Column(
                              children: [
                                Icon(Icons.description_outlined, size: 32, color: AppColors.slate300),
                                SizedBox(height: 8),
                                Text(
                                  'No saved descriptions',
                                  style: TextStyle(color: AppColors.slate400),
                                ),
                                Text(
                                  'Add your first one below',
                                  style: TextStyle(fontSize: 12, color: AppColors.slate300),
                                ),
                              ],
                            ),
                          )
                        else
                          Flexible(
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              shrinkWrap: true,
                              itemCount: items.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                thickness: 1,
                                color: AppColors.slate50,
                              ),
                              itemBuilder: (_, i) {
                                final item = items[i];
                                final text = (item['text'] as String?) ?? '';
                                final id = item['id'] as int?;
                                final isCustom =
                                    ((item['is_custom'] as num?)?.toInt() ?? 0) == 1;
                                final canDelete = isCustom || items.length > 1;
                                final isSelected = widget.value == text;
                                final isHighlighted = i == _highlightedIndex;

                                return Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () => _selectItem(text),
                                    onHover: (hovering) {
                                      if (!hovering || i == _highlightedIndex) return;
                                      setState(() => _highlightedIndex = i);
                                      _overlayEntry?.markNeedsBuild();
                                    },
                                    hoverColor: AppColors.slate25,
                                    splashColor: AppColors.primary.withOpacity(0.1),
                                    child: Container(
                                      color: isHighlighted ? AppColors.slate25 : Colors.transparent,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                      child: Row(
                                        children: [
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle,
                                              size: 16,
                                              color: AppColors.primary,
                                            )
                                          else
                                            const SizedBox(width: 16),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              text,
                                              style: AppTextStyles.input.copyWith(
                                                fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                                                color: isSelected ? AppColors.primary : AppColors.slate700,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (canDelete && id != null)
                                            InkWell(
                                              onTap: () => widget.notifier.delete(id),
                                              borderRadius: BorderRadius.circular(20),
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 16,
                                                  color: AppColors.slate400,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        const Divider(height: 1, thickness: 1, color: AppColors.slate100),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _addCtrl,
                                  focusNode: _addFocusNode,
                                  onSubmitted: (_) => _handleAdd(),
                                  style: AppTextStyles.input,
                                  decoration: InputDecoration(
                                    hintText: 'Add new description...',
                                    hintStyle: AppTextStyles.input.copyWith(color: AppColors.slate400),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    filled: true,
                                    fillColor: AppColors.slate25,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                                      borderSide: BorderSide.none,
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(AppSpacing.radius),
                                      borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                onPressed: _handleAdd,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add'),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(AppSpacing.radius),
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
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _isOpen;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _ItemDescriptionPrimaryIntent(),
        SingleActivator(LogicalKeyboardKey.enter, shift: true): _ItemDescriptionBackwardIntent(),
      },
      child: Actions(
        actions: {
          _ItemDescriptionPrimaryIntent: CallbackAction<_ItemDescriptionPrimaryIntent>(
            onInvoke: (_) {
              _handlePrimaryAction();
              return null;
            },
          ),
          _ItemDescriptionBackwardIntent: CallbackAction<_ItemDescriptionBackwardIntent>(
            onInvoke: (_) {
              _handleBackwardAction();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: _focusNode,
          onFocusChange: _handleFocusChange,
          onKeyEvent: _onKeyEvent,
          child: CompositedTransformTarget(
            link: _layerLink,
            child: InkWell(
              key: _fieldKey,
              onTap: _toggleOverlay,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: (isOpen || _hasFocus) ? AppColors.primary : AppColors.slate200,
                    width: (isOpen || _hasFocus) ? 1.5 : 1,
                  ),
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  color: Colors.white,
                  boxShadow: (isOpen || _hasFocus)
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.value.isEmpty ? 'Select or add a description...' : widget.value,
                          style: AppTextStyles.input.copyWith(
                            color: widget.value.isEmpty ? AppColors.slate400 : AppColors.slate800,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.value.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            widget.onChanged('');
                            if (_isOpen) _removeOverlay();
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 4),
                          ),
                        ),
                      AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: isOpen ? 0.5 : 0,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: isOpen ? AppColors.primary : AppColors.slate500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
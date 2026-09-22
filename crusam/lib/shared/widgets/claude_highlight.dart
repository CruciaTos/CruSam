// lib/shared/widgets/claude_highlight.dart
//
// Wraps a list item that Claude can point at (see ClaudeFollowController).
// When the controller focuses [focusKey] the item scrolls into view and
// glows for a couple of seconds.
//
// Lazy lists (ListView.builder) don't build far-away items, so the screen
// also mixes in [ClaudeListFocus], which scrolls toward the item until it is
// built; the item then centres itself.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/sync/claude_follow_controller.dart';

class ClaudeHighlight extends StatefulWidget {
  /// `<type>:<id>`, built with UiEventStore's focus helpers.
  final String focusKey;
  final BorderRadius borderRadius;
  final Widget child;

  const ClaudeHighlight({
    super.key,
    required this.focusKey,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    required this.child,
  });

  /// Keys of the highlights currently built.
  static final _built = <String, int>{};
  static bool isBuilt(String key) => (_built[key] ?? 0) > 0;

  @override
  State<ClaudeHighlight> createState() => _ClaudeHighlightState();
}

class _ClaudeHighlightState extends State<ClaudeHighlight> {
  static const _glowFor = Duration(milliseconds: 2600);
  static const _glow = Color(0xFF3B82F6);

  final _c = ClaudeFollowController.instance;
  int _seenSerial = 0;
  bool _lit = false;
  Timer? _off;

  @override
  void initState() {
    super.initState();
    ClaudeHighlight._built.update(widget.focusKey, (n) => n + 1, ifAbsent: () => 1);
    _c.addListener(_onFocus);
    // The screen may have just been opened for this very item.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onFocus());
  }

  @override
  void dispose() {
    ClaudeHighlight._built.update(widget.focusKey, (n) => n - 1);
    _c.removeListener(_onFocus);
    _off?.cancel();
    super.dispose();
  }

  void _onFocus() {
    if (!mounted || _c.focusSerial == _seenSerial) return;
    _seenSerial = _c.focusSerial;
    if (!_c.isFocused(widget.focusKey)) return;
    setState(() => _lit = true);
    Scrollable.ensureVisible(context,
        alignment: 0.3,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic);
    _off?.cancel();
    _off = Timer(_glowFor, () {
      if (mounted) setState(() => _lit = false);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          boxShadow: _lit
              ? [
                  BoxShadow(color: _glow.withValues(alpha: 0.9), spreadRadius: 2),
                  BoxShadow(color: _glow.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 2),
                ]
              : const [],
        ),
        child: widget.child,
      );
}

/// For screens with a lazy list of [ClaudeHighlight] items: give the list
/// [claudeScroll] as its controller, return the items' focus keys (in list
/// order) from [claudeKeys], and call [claudeListChanged] after the list's
/// data changes (it may load after Claude pointed at an item).
mixin ClaudeListFocus<T extends StatefulWidget> on State<T> {
  final claudeScroll = ScrollController();
  List<String> get claudeKeys;

  int _claudeSerial = 0;

  @override
  void initState() {
    super.initState();
    ClaudeFollowController.instance.addListener(claudeListChanged);
  }

  @override
  void dispose() {
    ClaudeFollowController.instance.removeListener(claudeListChanged);
    claudeScroll.dispose();
    super.dispose();
  }

  void claudeListChanged() {
    final c = ClaudeFollowController.instance;
    if (!mounted || c.focusSerial == _claudeSerial) return;
    final keys = claudeKeys;
    final i = keys.indexWhere(c.isFocused);
    if (i < 0) return;
    _claudeSerial = c.focusSerial;
    _scrollToward(i, keys[i], keys.length);
  }

  /// Scrolls to the estimated position of item [i] until it is built (its
  /// ClaudeHighlight then centres it exactly).
  Future<void> _scrollToward(int i, String key, int count) async {
    for (var attempt = 0; attempt < 4; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !claudeScroll.hasClients) return;
      if (ClaudeHighlight.isBuilt(key)) return;
      final p = claudeScroll.position;
      // The list's own estimate of its length, from the items built so far.
      final extent = (p.maxScrollExtent + p.viewportDimension) / count;
      final target = (i * extent - p.viewportDimension * 0.3)
          .clamp(0.0, p.maxScrollExtent);
      await claudeScroll.animateTo(target,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic);
    }
  }
}

// lib/core/window/window_mode_controller.dart
//
// Full window vs. compact window. Compact is a slim, always-on-top window
// docked to the right edge of the screen, next to Claude Desktop, showing a
// scaled live view of the app — it pops up by itself when Claude starts
// working (Follow Claude) while the app isn't the focused window.
//
// The switch: the content fades out, the window glides to its new frame on
// an Apple-style ease, the new layout fades/scales in. Fading hides the
// per-frame relayout a native resize causes on Windows.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

enum WindowMode { full, compact }

class WindowModeController extends ChangeNotifier {
  WindowModeController._();
  static final WindowModeController instance = WindowModeController._();

  /// Smallest full window the layouts are designed for (960x520 of content
  /// plus the frame; window_manager now owns WM_GETMINMAXINFO).
  static const _fullMinSize = Size(976, 559);
  static const _compactMinSize = Size(420, 480);
  static const _compactWidth = 580.0;
  static const _compactMaxHeight = 860.0;
  static const _edgeMargin = 16.0;

  /// Apple's "sheet" curve: quick start, long soft landing.
  static const _glideCurve = Cubic(0.32, 0.72, 0.0, 1.0);
  static const _glide = Duration(milliseconds: 420);
  static const fadeOut = Duration(milliseconds: 130);
  static const fadeIn = Duration(milliseconds: 260);

  /// Claude counts as idle after this long without a step; a manual switch
  /// to full keeps the window full until then.
  static const _idleAfter = Duration(seconds: 60);

  bool get _supported =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  WindowMode mode = WindowMode.full;
  bool get isCompact => mode == WindowMode.compact;

  /// True while switching: content is faded out under the glide.
  bool veiled = false;

  Rect? _fullBounds;
  bool _fullWasMaximized = false;
  bool _busy = false;
  bool _ready = false;
  DateTime _lastClaudeStep = DateTime.fromMillisecondsSinceEpoch(0);
  bool _stayFull = false;

  /// Called once from main.dart, before runApp.
  Future<void> init() async {
    if (!_supported) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(_fullMinSize);
      _ready = true;
    } catch (e) {
      debugPrint('WindowModeController.init: $e');
    }
  }

  /// Follow Claude: a step is about to be shown.
  Future<void> onClaudeStep() async {
    final now = DateTime.now();
    if (now.difference(_lastClaudeStep) > _idleAfter) _stayFull = false;
    _lastClaudeStep = now;
    if (!_ready || _busy || _stayFull) return;
    try {
      if (isCompact) {
        // Already compact; just make sure it can be seen.
        if (await windowManager.isMinimized()) await windowManager.restore();
        if (!await windowManager.isVisible()) await windowManager.show(inactive: true);
        return;
      }
      // The user is working in the app: don't shrink it under them.
      if (await windowManager.isFocused() && !await windowManager.isMinimized()) return;
      await setMode(WindowMode.compact, activate: false);
    } catch (e) {
      debugPrint('WindowModeController.onClaudeStep: $e');
    }
  }

  /// Tests: render the compact or full layout without a real window.
  @visibleForTesting
  void debugSetMode(WindowMode m) {
    mode = m;
    notifyListeners();
  }

  Future<void> toggle() => setMode(isCompact ? WindowMode.full : WindowMode.compact);

  Future<void> setMode(WindowMode target, {bool activate = true}) async {
    if (!_ready || _busy || target == mode) return;
    _busy = true;
    try {
      if (target == WindowMode.full) _stayFull = activate; // chosen by the user
      if (target == WindowMode.compact) {
        await _toCompact(activate: activate);
      } else {
        await _toFull();
      }
    } catch (e) {
      debugPrint('WindowModeController.setMode: $e');
      veiled = false;
      notifyListeners();
    } finally {
      _busy = false;
    }
  }

  Future<void> _toCompact({required bool activate}) async {
    final wasMinimized = await windowManager.isMinimized();
    if (wasMinimized) await windowManager.restore();
    _fullWasMaximized = await windowManager.isMaximized();
    if (_fullWasMaximized) await windowManager.unmaximize();
    _fullBounds = await windowManager.getBounds();

    final to = await _compactBounds(_fullBounds!);
    await _veil();
    mode = WindowMode.compact;
    notifyListeners();
    await windowManager.setMinimumSize(_compactMinSize);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setAlwaysOnTop(true);
    // A minimized window has no useful frame to glide from.
    if (wasMinimized) {
      await windowManager.setBounds(to);
    } else {
      await _glideTo(_fullBounds!, to);
    }
    if (activate) {
      await windowManager.show();
    } else if (!await windowManager.isVisible()) {
      await windowManager.show(inactive: true);
    }
    await _unveil();
  }

  Future<void> _toFull() async {
    final from = await windowManager.getBounds();
    final to = _fullBounds ?? await _defaultFullBounds();
    await _veil();
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    // The compact layout copes with any size, so it stays during the glide;
    // the full layout only appears once the window is full size.
    await _glideTo(from, to);
    await windowManager.setMinimumSize(_fullMinSize);
    mode = WindowMode.full;
    notifyListeners();
    if (_fullWasMaximized) await windowManager.maximize();
    await windowManager.focus();
    await _unveil();
  }

  Future<void> _veil() async {
    veiled = true;
    notifyListeners();
    await Future<void>.delayed(fadeOut);
  }

  Future<void> _unveil() async {
    // Let the new layout paint once before it fades in.
    await SchedulerBinding.instance.endOfFrame;
    veiled = false;
    notifyListeners();
  }

  /// Moves the window frame by frame, one bounds update per Flutter frame.
  Future<void> _glideTo(Rect from, Rect to) async {
    final clock = Stopwatch()..start();
    while (true) {
      final t = math.min(1.0, clock.elapsedMicroseconds / _glide.inMicroseconds);
      final r = Rect.lerp(from, to, _glideCurve.transform(t))!;
      await windowManager.setBounds(Rect.fromLTWH(
          r.left.roundToDouble(), r.top.roundToDouble(),
          r.width.roundToDouble(), r.height.roundToDouble()));
      if (t >= 1) break;
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  /// Right edge of the display the window is on, vertically centred.
  Future<Rect> _compactBounds(Rect current) async {
    final area = await _workArea(current.center);
    final height = math.min(_compactMaxHeight, area.height - 2 * _edgeMargin);
    return Rect.fromLTWH(
      area.right - _compactWidth - _edgeMargin,
      area.top + (area.height - height) / 2,
      _compactWidth,
      height,
    );
  }

  Future<Rect> _defaultFullBounds() async {
    final area = await _workArea(null);
    return Rect.fromCenter(
        center: area.center,
        width: math.min(1280, area.width - 64),
        height: math.min(760, area.height - 64));
  }

  Future<Rect> _workArea(Offset? near) async {
    final displays = await screenRetriever.getAllDisplays();
    Display display = await screenRetriever.getPrimaryDisplay();
    if (near != null) {
      for (final d in displays) {
        final pos = d.visiblePosition ?? Offset.zero;
        final size = d.visibleSize ?? d.size;
        if ((pos & size).contains(near)) display = d;
      }
    }
    return (display.visiblePosition ?? Offset.zero) & (display.visibleSize ?? display.size);
  }
}

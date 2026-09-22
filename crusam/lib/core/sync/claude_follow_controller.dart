// lib/core/sync/claude_follow_controller.dart
//
// "Follow Claude": plays back the UI events the CruSam MCP server records
// after each tool call (see crusam_core's UiEventStore), so the user can
// watch Claude work — the matching screen opens, the row it touched is
// highlighted, and the activity banner says what it's doing.
//
// Steps are shown one at a time for at least [_dwell] so a burst of calls
// doesn't turn into a blur. With Follow off, or when leaving the current
// screen could lose work (an open dialog, a form being edited), the banner
// still shows the step with a "View" button instead of navigating.

import 'dart:async';
import 'dart:collection';

import 'package:crusam_core/crusam_core.dart' show UiEvent, UiEventStore;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/salary/notifier/salary_snapshot_notifier.dart';
import '../../features/vouchers/notifiers/voucher_notifier.dart';
import '../router/app_router.dart';
import '../window/window_mode_controller.dart';

class ClaudeFollowController extends ChangeNotifier {
  ClaudeFollowController._();
  static final ClaudeFollowController instance = ClaudeFollowController._();

  static const _prefKey = 'follow_claude';
  static const _dwell = Duration(milliseconds: 1500);
  static const _dwellWhenBehind = Duration(milliseconds: 600);
  static const _linger = Duration(seconds: 4);

  /// Screens where navigating away could throw away typed-in work.
  static const _editingRoutes = {
    '/settings',
    '/salary-formula-settings',
  };

  bool _follow = true;
  bool get follow => _follow;

  /// The step on the banner, or null when it's hidden.
  UiEvent? current;

  /// True when [current] has a screen the app didn't open by itself.
  bool canView = false;

  /// `<type>:<id>` to highlight, e.g. `employee:42`; bumps [focusSerial]
  /// each time so the same row can be highlighted twice in a row.
  String focus = '';
  int focusSerial = 0;
  DateTime _focusAt = DateTime.fromMillisecondsSinceEpoch(0);

  final _queue = Queue<UiEvent>();
  bool _playing = false;
  Timer? _hideTimer;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _follow = prefs.getBool(_prefKey) ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint('ClaudeFollowController.load: $e');
    }
  }

  Future<void> setFollow(bool value) async {
    _follow = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, value);
    } catch (e) {
      debugPrint('ClaudeFollowController.setFollow: $e');
    }
  }

  /// Called by DbChangeWatcher with new events, oldest first.
  void enqueue(List<UiEvent> events) {
    if (events.isEmpty) return;
    // Claude is working: pop the app up (compact, on top) so it can be seen.
    if (_follow) unawaited(WindowModeController.instance.onClaudeStep());
    _queue.addAll(events);
    if (!_playing) unawaited(_play());
  }

  Future<void> _play() async {
    _playing = true;
    _hideTimer?.cancel();
    try {
      while (_queue.isNotEmpty) {
        final e = _queue.removeFirst();
        await _show(e, navigate: _follow);
        await Future<void>.delayed(
            _queue.length > 3 ? _dwellWhenBehind : _dwell);
      }
    } finally {
      _playing = false;
    }
    _hideTimer = Timer(_linger, dismiss);
  }

  Future<void> _show(UiEvent e, {required bool navigate}) async {
    current = e;
    canView = false;
    if (e.route.isNotEmpty) {
      if (navigate && _canLeaveFor(e.route)) {
        await _open(e);
      } else {
        // A salary step needs its month shown too, even on the same screen.
        canView = _currentPath != e.route || e.period.isNotEmpty;
        if (!canView) _setFocus(e.focus);
      }
    }
    notifyListeners();
  }

  /// "View" on the banner: open the step's screen even with Follow off.
  Future<void> view() async {
    final e = current;
    if (e == null || e.route.isEmpty) return;
    canView = false;
    await _open(e);
    notifyListeners();
  }

  /// Opens [e]'s screen. For a salary step, first shows Claude's saved month
  /// there (the user's own month is parked — see SalarySnapshotNotifier).
  Future<void> _open(UiEvent e) async {
    var route = e.route;
    final period = UiEventStore.parsePeriod(e.period);
    if (period != null &&
        !await SalarySnapshotNotifier.instance
            .showMonthForClaude(period.$1, period.$2)) {
      route = '/saved-salary'; // not a saved month (any more)
    }
    if (_currentPath != route) AppRouter.router.go(route);
    _setFocus(e.focus);
  }

  /// Hides the banner (the next step, if any, brings it back).
  void dismiss() {
    _hideTimer?.cancel();
    current = null;
    canView = false;
    notifyListeners();
  }

  void _setFocus(String key) {
    if (key.isEmpty) return;
    focus = key;
    focusSerial++;
    _focusAt = DateTime.now();
  }

  /// Whether [key] is the row to highlight right now (a row built later,
  /// e.g. on revisiting the screen, doesn't light up for an old step).
  bool isFocused(String key) =>
      key.isNotEmpty &&
      key == focus &&
      DateTime.now().difference(_focusAt) < const Duration(seconds: 3);

  String get _currentPath =>
      AppRouter.router.routerDelegate.currentConfiguration.uri.path;

  bool _canLeaveFor(String route) {
    final here = _currentPath;
    if (here == route) return true;
    // A dialog (e.g. the employee form) is open on top of the screen.
    if (AppRouter.rootNavigatorKey.currentState?.canPop() ?? false) return false;
    if (_editingRoutes.contains(here)) return false;
    if (here == '/vouchers') {
      final v = VoucherNotifier.instance.current;
      if (v.rows.isNotEmpty || v.title.isNotEmpty) return false;
    }
    return true;
  }
}

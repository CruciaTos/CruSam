// lib/core/sync/db_change_watcher.dart
//
// Picks up changes other processes make to aarti.db — mainly Claude through
// the CruSam MCP server (update_employee, update_salary_formula_settings,
// create_invoice, ...) — while the app is open.
//
// SQLite's `PRAGMA data_version` changes only when ANOTHER connection
// commits, so the app's own writes never trigger a reload. Polling it is
// just a counter read, so once a second costs nothing noticeable.
//
// On a change it first reads the UI events the MCP server recorded for
// Claude's tool calls and hands them to ClaudeFollowController (screen,
// highlight, activity banner). Unless those were all reads/previews, it then
// reloads the app-wide caches (employees, salary formula) and notifies
// listeners: screens mixing in [ReloadOnDbChange] reload what they show, and
// the shell shows the "Updated" pill when no banner explains the change.

import 'dart:async';

import 'package:crusam_core/crusam_core.dart' show UiEvent, UiEventStore;
import 'package:flutter/widgets.dart';

import '../../data/db/database_helper.dart';
import '../../features/master_data/notifiers/employee_notifier.dart';
import '../../features/salary/notifier/salary_data_notifier.dart';
import '../../features/salary/notifier/salary_formula_notifier.dart';
import '../../features/salary/notifier/salary_state_controller.dart';
import 'claude_follow_controller.dart';

class DbChangeWatcher extends ChangeNotifier {
  DbChangeWatcher._();
  static final DbChangeWatcher instance = DbChangeWatcher._();

  static const _interval = Duration(seconds: 1);

  Timer? _timer;
  int? _lastVersion;
  int? _lastEventId;
  bool _checking = false;

  /// Bumped once per detected external change.
  int revision = 0;

  /// Whether the latest change came with UI events (the activity banner
  /// already says what changed, so the "Updated" pill stays hidden).
  bool lastChangeExplained = false;

  /// Called once from main.dart.
  void start() {
    _timer ??= Timer.periodic(_interval, (_) => _check());
    unawaited(_check());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.rawQuery('PRAGMA data_version');
      final version = rows.first.values.first as int;
      final changed = _lastVersion != null && version != _lastVersion;
      _lastVersion = version;
      if (_lastEventId == null) {
        // Only events recorded from now on are played back.
        await UiEventStore.ensureTable(db);
        _lastEventId = await UiEventStore.lastId(db);
      }
      if (!changed) return;

      var events = await _newEvents();
      if (events.isEmpty) {
        // The server commits a tool's data write and its UI event
        // separately; give the event a moment to land.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        events = await _newEvents();
      }
      ClaudeFollowController.instance.enqueue(events);
      if (events.isEmpty || events.any((e) => e.dataChanged)) {
        lastChangeExplained = events.isNotEmpty;
        await _reloadShared();
      }
    } catch (e) {
      debugPrint('DbChangeWatcher: $e');
    } finally {
      _checking = false;
    }
  }

  Future<List<UiEvent>> _newEvents() async {
    final db = await DatabaseHelper.instance.database;
    final events = await UiEventStore.after(db, _lastEventId ?? 0);
    if (events.isNotEmpty) _lastEventId = events.last.id;
    return events;
  }

  Future<void> _reloadShared() async {
    if (await SalaryFormulaNotifier.instance.reloadIfChanged()) {
      // Salary screens compute off SalaryFormulaEngine synchronously; make
      // them rebuild with the new PF/ESIC/PT values.
      SalaryDataNotifier.instance.refresh();
    }
    await EmployeeNotifier.instance.load(silent: true);
    final salary = SalaryStateController.instance;
    if (salary.employees.isNotEmpty) await salary.loadEmployees(silent: true);

    revision++;
    notifyListeners();
  }
}

/// Reloads a screen's data whenever [DbChangeWatcher] sees an external
/// change. Implement [onDbChanged] with a reload that doesn't flash the
/// loading skeleton.
mixin ReloadOnDbChange<T extends StatefulWidget> on State<T> {
  void onDbChanged();

  void _handleDbChange() {
    if (mounted) onDbChanged();
  }

  @override
  void initState() {
    super.initState();
    DbChangeWatcher.instance.addListener(_handleDbChange);
  }

  @override
  void dispose() {
    DbChangeWatcher.instance.removeListener(_handleDbChange);
    super.dispose();
  }
}

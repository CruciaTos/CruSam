// UI events: how the MCP server shows the user what Claude is doing. After
// each tool call the server records which app screen shows the result (and
// which row to highlight) plus a one-line description; the running app plays
// them back one by one ("Follow Claude"). New, additive table; nothing in the
// existing schema references it. Events are fire-and-forget and pruned.

import 'package:sqflite_common/sqlite_api.dart';

class UiEvent {
  final int? id;

  /// App route to open, e.g. `/employees`; empty = describe only.
  final String route;

  /// What to highlight on that screen, as `<type>:<id>` (see [UiEventStore]
  /// focus helpers); empty = nothing.
  final String focus;

  /// Saved salary month (`YYYY-M`, see [UiEventStore.period]) the app should
  /// show on its salary screens before opening [route]; empty = none.
  final String period;

  /// One line for the activity banner, e.g. "Updating Ramesh Patil".
  final String message;

  /// True when the call changed data (the app reloads); false for reads,
  /// previews and navigation-only calls.
  final bool dataChanged;
  final String tool;
  final String createdAt;

  const UiEvent({
    this.id,
    this.route = '',
    this.focus = '',
    this.period = '',
    required this.message,
    this.dataChanged = false,
    this.tool = '',
    this.createdAt = '',
  });

  factory UiEvent.fromDbMap(Map<String, Object?> m) => UiEvent(
        id: m['id'] as int?,
        route: (m['route'] as String?) ?? '',
        focus: (m['focus'] as String?) ?? '',
        period: (m['period'] as String?) ?? '',
        message: (m['message'] as String?) ?? '',
        dataChanged: (m['data_changed'] as int?) == 1,
        tool: (m['tool'] as String?) ?? '',
        createdAt: (m['created_at'] as String?) ?? '',
      );

  Map<String, Object?> toDbMap() => {
        if (id != null) 'id': id,
        'route': route,
        'focus': focus,
        'period': period,
        'message': message,
        'data_changed': dataChanged ? 1 : 0,
        'tool': tool,
        'created_at': createdAt,
      };
}

class UiEventStore {
  UiEventStore._();

  static const table = 'ui_events';

  /// Only the most recent events are kept; the app only needs new ones.
  static const keep = 200;

  static const createTableSql = '''CREATE TABLE IF NOT EXISTS ui_events(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      route TEXT NOT NULL DEFAULT '',
      focus TEXT NOT NULL DEFAULT '',
      period TEXT NOT NULL DEFAULT '',
      message TEXT NOT NULL DEFAULT '',
      data_changed INTEGER NOT NULL DEFAULT 0,
      tool TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL)''';

  static Future<void> ensureTable(DatabaseExecutor db) async {
    await db.execute(createTableSql);
    // Tables created before `period` existed.
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (!cols.any((c) => c['name'] == 'period')) {
      await db.execute(
          "ALTER TABLE $table ADD COLUMN period TEXT NOT NULL DEFAULT ''");
    }
  }

  /// Inserts [e] and prunes old events.
  static Future<int> add(DatabaseExecutor db, UiEvent e) async {
    final id = await db.insert(table, e.toDbMap()..remove('id'));
    await db.delete(table, where: 'id <= ?', whereArgs: [id - keep]);
    return id;
  }

  /// Events after [afterId], oldest first.
  static Future<List<UiEvent>> after(DatabaseExecutor db, int afterId) async {
    final rows = await db.query(table,
        where: 'id > ?', whereArgs: [afterId], orderBy: 'id', limit: keep);
    return rows.map(UiEvent.fromDbMap).toList();
  }

  static Future<int> lastId(DatabaseExecutor db) async =>
      ((await db.rawQuery('SELECT MAX(id) AS m FROM $table')).first['m']
          as int?) ??
      0;

  // ── Focus keys (shared so the server and the app agree) ──────────────────
  static String employeeFocus(int id) => 'employee:$id';
  static String invoiceFocus(int id) => 'invoice:$id';
  static String clientFocus(int id) => 'client:$id';
  static String salaryMonthFocus(int month, int year) => 'salary_month:$year-$month';
  static String disbursementFocus(int id) => 'disbursement:$id';

  static String period(int month, int year) => '$year-$month';

  /// (month, year) from [period], or null.
  static (int, int)? parsePeriod(String p) {
    final parts = p.split('-');
    if (parts.length != 2) return null;
    final y = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return y == null || m == null ? null : (m, y);
  }
}

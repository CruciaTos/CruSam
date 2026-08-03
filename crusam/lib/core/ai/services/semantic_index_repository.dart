// crusam/lib/core/ai/services/semantic_index_repository.dart
//
// Self-contained SQLite persistence layer for the semantic search index.
//
// ── Tables ───────────────────────────────────────────────────────────────
//
//   semantic_index_entries  — one row per IndexEntry (term_vector as JSON)
//   semantic_index_idf      — per-domain IDF weights, one row per term
//   semantic_index_meta     — staleness check data (timestamp + row count)
//
// ── Design notes ─────────────────────────────────────────────────────────
//
//   • Lifecycle is fully lazy: the database is opened and tables are
//     ensured on the first call that needs them.  No Flutter init hook
//     or app-startup dependency.
//
//   • Table creation uses CREATE TABLE IF NOT EXISTS — idempotent on every
//     cold-start.  Future column additions are guarded by PRAGMA table_info
//     checks directly in _ensureTables(); no versioned onUpgrade callbacks.
//
//   • replaceDomainIndex wraps delete + insert in a single db.batch() commit
//     so the domain is never in a half-replaced state under concurrent reads.
//
//   • Term vectors are serialised as JSON strings ({term: weight}).
//     The dart:convert round-trip is done once per build/load, not per query.
//
// On Android/iOS this file still has no Flutter dependency and is safe to
// call from any isolate, same as before. On Windows/Linux/macOS it now
// resolves its database file via AppPaths (see _openDb), which uses
// path_provider — a Flutter plugin — instead of sqflite_common_ffi's
// getDatabasesPath() default (which resolves to Directory.current, i.e. the
// install folder). That makes this file transitively Flutter-dependent on
// desktop; nothing currently calls it from a background isolate, but if that
// ever changes on desktop, the resolved directory would need to be handed in
// rather than looked up from within the spawned isolate.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../storage/app_paths.dart';
import 'semantic_index_models.dart';

// ── Table and column name constants ────────────────────────────────────────
//
// Kept module-private so nothing outside this file can hardcode a string
// that would silently survive a rename.

const _tEntries = 'semantic_index_entries';
const _tIdf     = 'semantic_index_idf';
const _tMeta    = 'semantic_index_meta';

// ── Repository ─────────────────────────────────────────────────────────────

class SemanticIndexRepository {
  SemanticIndexRepository._();
  static final SemanticIndexRepository instance = SemanticIndexRepository._();

  Database? _db;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Lazily opens the database (once) and ensures all tables exist.
  Future<Database> get _database async => _db ??= await _openDb();

  Future<Database> _openDb() async {
    final dbPath = await _resolveDbPath();
    // Opened without a `version` so sqflite never runs onUpgrade/onDowngrade.
    // Table creation and column migrations are handled entirely in _ensureTables.
    final db = await openDatabase(dbPath);
    await _ensureTables(db);
    return db;
  }

  /// Resolves the absolute path to `semantic_index.db`.
  ///
  /// Same rationale as [DatabaseHelper._resolveDbPath] in database_helper.dart:
  /// desktop resolves through [AppPaths] (path_provider, not the install
  /// folder); Android/iOS keep using the native plugin's already-correct
  /// `getDatabasesPath()` unchanged.
  static Future<String> _resolveDbPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return AppPaths.childPath('semantic_index.db');
    }
    return p.join(await getDatabasesPath(), 'semantic_index.db');
  }

  /// Creates tables on first open and guards any future ALTER TABLE migrations
  /// with PRAGMA table_info checks so the method remains safe to call on every
  /// cold-start.
  Future<void> _ensureTables(Database db) async {
    // ── Table creation (all idempotent) ──────────────────────────────────

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tEntries (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        domain        TEXT    NOT NULL,
        record_id     TEXT    NOT NULL,
        secondary_id  TEXT,
        display_text  TEXT    NOT NULL,
        search_text   TEXT    NOT NULL,
        term_vector   TEXT    NOT NULL
      )
    ''');

    // A plain domain index is enough: getDomainEntries loads an entire domain
    // at once, and SemanticIndexService keeps the corpus in memory afterwards.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_entries_domain
      ON $_tEntries (domain)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tIdf (
        domain  TEXT NOT NULL,
        term    TEXT NOT NULL,
        weight  REAL NOT NULL,
        PRIMARY KEY (domain, term)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_tMeta (
        domain           TEXT PRIMARY KEY,
        last_built_at    TEXT,
        source_row_count INTEGER
      )
    ''');

    // ── Column migrations (PRAGMA-guarded, idempotent) ──────────────────
    //
    // Future ALTER TABLE additions belong here.  Pattern:
    //
    //   final cols = (await db.rawQuery('PRAGMA table_info($_tEntries)'))
    //       .map((r) => r['name'] as String)
    //       .toSet();
    //
    //   if (!cols.contains('boost_factor')) {
    //     await db.execute(
    //       'ALTER TABLE $_tEntries ADD COLUMN boost_factor REAL',
    //     );
    //   }
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  /// Converts an [IndexDomain] enum value to the string key stored in SQLite.
  /// Using `.name` means the DB string always matches the Dart identifier
  /// (e.g. `IndexDomain.employees` → `"employees"`).
  static String _key(IndexDomain domain) => domain.name;

  /// Deserialises a term-vector JSON string back to `Map<String, double>`.
  ///
  /// JSON numbers decode as [int] or [double] depending on whether they
  /// contain a decimal point; `(v as num).toDouble()` handles both.
  static Map<String, double> _vecFromJson(String json) {
    final raw = jsonDecode(json) as Map<String, dynamic>;
    return raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
  }

  // ── Writes ────────────────────────────────────────────────────────────────

  /// Atomically replaces all index data for [domain].
  ///
  /// The entire operation — delete-old + insert-entries + insert-IDF +
  /// upsert-meta — is committed as a single [db.batch()] so a partial write
  /// is never visible to concurrent readers.
  ///
  /// [sourceRowCount] is the number of raw DB rows the builder scanned to
  /// produce [entries]; stored in meta so [getMeta] can detect staleness
  /// without re-scanning the source tables.
  Future<void> replaceDomainIndex(
    IndexDomain domain,
    List<IndexEntry> entries,
    Map<String, double> idf,
    int sourceRowCount,
  ) async {
    final db  = await _database;
    final key = _key(domain);
    final now = DateTime.now().toUtc().toIso8601String();

    final batch = db.batch();

    // ── 1. Wipe the existing domain data ─────────────────────────────────
    batch.delete(_tEntries, where: 'domain = ?', whereArgs: [key]);
    batch.delete(_tIdf,     where: 'domain = ?', whereArgs: [key]);
    batch.delete(_tMeta,    where: 'domain = ?', whereArgs: [key]);

    // ── 2. Insert fresh entries ───────────────────────────────────────────
    for (final e in entries) {
      batch.insert(_tEntries, {
        'domain':       key,
        'record_id':    e.recordId,
        'secondary_id': e.secondaryId,   // nullable — sqflite stores as NULL
        'display_text': e.displayText,
        'search_text':  e.searchText,
        'term_vector':  jsonEncode(e.termVector),
      });
    }

    // ── 3. Insert IDF weights ─────────────────────────────────────────────
    idf.forEach((term, weight) {
      batch.insert(_tIdf, {
        'domain': key,
        'term':   term,
        'weight': weight,
      });
    });

    // ── 4. Write meta ─────────────────────────────────────────────────────
    batch.insert(_tMeta, {
      'domain':           key,
      'last_built_at':    now,
      'source_row_count': sourceRowCount,
    });

    await batch.commit(noResult: true);
  }

  // ── Reads ─────────────────────────────────────────────────────────────────

  /// Loads all [IndexEntry] objects for [domain] from SQLite.
  ///
  /// Called once per domain per app session by [SemanticIndexService], which
  /// then holds the corpus in memory.  The JSON deserialisation here is the
  /// only costly step; everything after is in-memory cosine scoring.
  Future<List<IndexEntry>> getDomainEntries(IndexDomain domain) async {
    final db   = await _database;
    final rows = await db.query(
      _tEntries,
      where:     'domain = ?',
      whereArgs: [_key(domain)],
    );

    return rows
        .map((r) => IndexEntry(
              domain:      domain,
              recordId:    r['record_id']    as String,
              secondaryId: r['secondary_id'] as String?,
              displayText: r['display_text'] as String,
              searchText:  r['search_text']  as String,
              termVector:  _vecFromJson(r['term_vector'] as String),
            ))
        .toList();
  }

  /// Loads the IDF weight map for [domain].
  ///
  /// Used by [SemanticIndexService] to build a query vector at query time
  /// (via `buildQueryVector` in text_vectorizer.dart) without re-reading
  /// the entire entry corpus.
  Future<Map<String, double>> getDomainIdf(IndexDomain domain) async {
    final db   = await _database;
    final rows = await db.query(
      _tIdf,
      where:     'domain = ?',
      whereArgs: [_key(domain)],
    );

    return {
      for (final r in rows)
        r['term'] as String: (r['weight'] as num).toDouble(),
    };
  }

  /// Returns the staleness-check metadata for [domain].
  ///
  /// Both fields are `null` when the domain has never been indexed.
  /// [SemanticIndexService] calls this on startup to decide whether a
  /// rebuild is needed before loading entries into memory:
  ///
  /// ```dart
  /// final meta = await repo.getMeta(IndexDomain.employees);
  /// final needsRebuild = meta.sourceRowCount != currentEmployeeCount
  ///                   || meta.lastBuiltAt == null;
  /// ```
  Future<({String? lastBuiltAt, int? sourceRowCount})> getMeta(
    IndexDomain domain,
  ) async {
    final db   = await _database;
    final rows = await db.query(
      _tMeta,
      where:     'domain = ?',
      whereArgs: [_key(domain)],
      limit:     1,
    );

    if (rows.isEmpty) return (lastBuiltAt: null, sourceRowCount: null);

    final r = rows.first;
    return (
      lastBuiltAt:    r['last_built_at']    as String?,
      sourceRowCount: r['source_row_count'] as int?,
    );
  }
}
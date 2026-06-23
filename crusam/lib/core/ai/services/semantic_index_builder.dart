// crusam/lib/core/ai/services/semantic_index_builder.dart
//
// §4 of Phase 2 Implementation Brief — Semantic Indexing.
//
// Scans the live SQLite tables for each IndexDomain, assembles per-domain
// TF-IDF corpora, and persists them via SemanticIndexRepository.
//
// ── Lifecycle ─────────────────────────────────────────────────────────────
//
//   Call ensureFresh(domain) once per domain before any search in a given
//   sendMessage() turn.  The *first* call after a cold start (or after rows
//   are added/deleted) does the real work.  Subsequent calls in the same
//   session hit the fast path: one COUNT(*) + one meta row, then return.
//
// ── Staleness detection ───────────────────────────────────────────────────
//
//   The index stores source_row_count in semantic_index_meta.  On every
//   ensureFresh() call, we count the live source table and compare.
//   Row-count equality is a safe proxy for "nothing changed" at CruSam's
//   data scale (tens–hundreds of records, not millions).  If you need finer
//   detection (e.g. name edits that don't change count), add a
//   last_modified_at column to the source table and compare that too.
//
// ── No Flutter widget imports ─────────────────────────────────────────────
//
//   Only flutter/foundation is imported (for kDebugMode / debugPrint).
//   Safe to call from any context; no BuildContext dependency.
//
// ── Open question (§10 of brief) ─────────────────────────────────────────
//
//   Are salary_disbursements / salary_disbursement_items (the older table
//   pair) still actively written to, or fully superseded by
//   salary_month_snapshots / salary_month_employees?
//   _buildSalarySnapshots() covers only the newer tables.  If the older
//   tables are still live, add a second builder method and merge the results
//   before calling replaceDomainIndex().
//
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'package:crusam/core/ai/services/semantic_index_models.dart';
import 'package:crusam/core/ai/services/semantic_index_repository.dart';
import 'package:crusam/core/ai/services/semantic_index_service.dart';
import 'package:crusam/core/ai/services/text_vectorizer.dart';
import 'package:crusam/data/db/database_helper.dart';

// ── Builder ────────────────────────────────────────────────────────────────

class SemanticIndexBuilder {
  SemanticIndexBuilder._();
  static final SemanticIndexBuilder instance = SemanticIndexBuilder._();

  /// Domains for which a rebuild is currently in flight.
  ///
  /// Acts as a lightweight mutex so back-to-back ensureFresh() calls in the
  /// same session cannot race.  ensureFresh() polls this set (50 ms sleep)
  /// rather than launching a second parallel build.
  final _rebuilding = <IndexDomain>{};

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Ensures the [domain] index is current, rebuilding only when the live
  /// source row-count differs from the count stored in semantic_index_meta.
  ///
  /// **Fast path** (index fresh): one meta query + one COUNT(*), then returns
  /// immediately — no corpus construction, no JSON serialisation.
  ///
  /// **Slow path** (stale or never built): runs the full build pipeline and
  /// atomically replaces the domain's data in SemanticIndexRepository.
  ///
  /// Always call this before [SemanticIndexService.search] for the same domain.
  Future<void> ensureFresh(IndexDomain domain) async {
    // If another caller already kicked off a rebuild for this domain, wait
    // for it to finish rather than launching a duplicate.
    if (_rebuilding.contains(domain)) {
      while (_rebuilding.contains(domain)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    final meta      = await SemanticIndexRepository.instance.getMeta(domain);
    final liveCount = await _sourceRowCount(domain);

    if (meta.sourceRowCount == liveCount && meta.lastBuiltAt != null) {
      if (kDebugMode) {
        debugPrint(
          '[SemanticIndexBuilder] $domain — index fresh '
          '(${meta.sourceRowCount} rows, last built ${meta.lastBuiltAt})',
        );
      }
      return; // ✓ fast path — nothing to do
    }

    await _buildDomain(domain, liveCount);
  }

  /// Forces a full rebuild of [domain] regardless of the stored meta.
  ///
  /// Useful for the "Rebuild Index" action in an AI diagnostics / debug screen,
  /// or when data has been edited in a way that doesn't change row-count
  /// (e.g. an employee name corrected in place).
  Future<void> forceRebuild(IndexDomain domain) async {
    if (_rebuilding.contains(domain)) return;
    final count = await _sourceRowCount(domain);
    await _buildDomain(domain, count);
  }

  // ── Orchestration ──────────────────────────────────────────────────────────

  Future<void> _buildDomain(IndexDomain domain, int sourceRowCount) async {
    _rebuilding.add(domain);
    try {
      if (kDebugMode) {
        debugPrint(
          '[SemanticIndexBuilder] ⟳ rebuilding $domain '
          '($sourceRowCount source rows)…',
        );
      }

      final sw = Stopwatch()..start();

      final result = await switch (domain) {
        IndexDomain.employees       => _buildEmployees(),
        IndexDomain.vouchers        => _buildVouchers(),
        IndexDomain.salarySnapshots => _buildSalarySnapshots(),
      };

      await SemanticIndexRepository.instance.replaceDomainIndex(
        domain,
        result.entries,
        result.idf,
        sourceRowCount,
      );

      // Tell SemanticIndexService to discard its in-memory cache for this
      // domain so the next search reloads fresh data from the repository.
      SemanticIndexService.instance.invalidate(domain);

      sw.stop();
      if (kDebugMode) {
        debugPrint(
          '[SemanticIndexBuilder] ✓ $domain — '
          '${result.entries.length} entries in ${sw.elapsedMilliseconds} ms',
        );
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[SemanticIndexBuilder] ✕ $domain build failed:\n$e\n$st');
      }
      rethrow;
    } finally {
      _rebuilding.remove(domain);
    }
  }

  // ── Employees ──────────────────────────────────────────────────────────────
  //
  // One IndexEntry per employee row.
  //
  // displayText: "Ali Hassan – Sr. Engineer · Dept: Engineering"
  // searchText:  name × 3 + dept + designation + phone + email + "emp{id}"
  //
  // The name token is repeated three times so it dominates TF for the
  // most common query pattern ("salary of Rajesh") over incidental
  // department/designation words.
  //
  // ⚠ SCHEMA NOTE: column names must match your `employees` table.
  //   If yours differ (e.g. `base_salary` instead of `salary`, or
  //   `job_title` instead of `designation`), adjust the columns list and
  //   the variable assignments below.

  Future<({List<IndexEntry> entries, Map<String, double> idf})>
      _buildEmployees() async {
    final db = await DatabaseHelper.instance.database;

    final rows = await db.query(
      'employees',
      columns: [
        'id', 'name', 'department', 'designation',
        'phone', 'email',
        // 'salary' intentionally omitted from the text corpus —
        // numeric salary fields surface through Stage-1 structured queries,
        // not through free-text TF-IDF matching.
      ],
    );

    final allTf   = <Map<String, double>>[];
    final rawDocs = <_RawDoc>[];

    for (final r in rows) {
      final id    = (r['id']          as int).toString();
      final name  = (r['name']        as String? ?? '').trim();
      final dept  = (r['department']  as String? ?? '').trim();
      final desig = (r['designation'] as String? ?? '').trim();
      final phone = (r['phone']       as String? ?? '').trim();
      final email = (r['email']       as String? ?? '').trim();

      // ── displayText ──────────────────────────────────────────────────────
      // This is the one-liner injected into the LLM prompt per match.
      // Keep it under ~80 chars; the LLM only needs enough to reason from.
      final displayParts = <String>[
        if (name.isNotEmpty)  name,
        if (desig.isNotEmpty) desig,
        if (dept.isNotEmpty)  'Dept: $dept',
      ];

      // ── searchText ───────────────────────────────────────────────────────
      // Fed into tokenize() at build time.  Not sent to the LLM.
      // Include an "emp{id}" token so a query like "emp12" or "employee 12"
      // can still hit via Stage-2 vector if Stage-1 ID lookup misses.
      final searchText = [
        name, name, name,       // 3× name weight
        dept, desig,
        if (phone.isNotEmpty) phone,
        if (email.isNotEmpty) email,
        'emp$id', id,
      ].join(' ');

      final tf = termFrequency(tokenize(searchText));
      allTf.add(tf);
      rawDocs.add(_RawDoc(
        recordId:    id,
        displayText: displayParts.join(' – ').replaceFirst(' – ', ' – ').trimRight(),
        searchText:  searchText,
        tf:          tf,
      ));
    }

    return _finalize(IndexDomain.employees, rawDocs, allTf);
  }

  // ── Vouchers ───────────────────────────────────────────────────────────────
  //
  // One IndexEntry per voucher header.  Line-item descriptions are collapsed
  // into the same entry's searchText so free-text queries like
  // "cement bags invoice" match via Stage-2 even when the party name alone
  // doesn't contain those terms.
  //
  // displayText: "INV-042 · ABC Corp · ₹45,000 · 12 Mar 2025"
  // searchText:  bill_no × 2 + party × 2 + type + status + date + item descs
  //
  // ⚠ SCHEMA NOTE: adjust 'vouchers' / 'voucher_items' table names and
  //   column names to match your actual schema if they differ.

  Future<({List<IndexEntry> entries, Map<String, double> idf})>
      _buildVouchers() async {
    final db = await DatabaseHelper.instance.database;

    // Load all headers in one query.
    final headers = await db.query(
      'vouchers',
      columns: [
        'id', 'bill_no', 'party_name', 'voucher_type',
        'date', 'total_amount', 'status',
      ],
    );

    // Load all line-item text in one query, then group client-side.
    // Avoids N×1 per-header queries for large voucher lists.
    final allItems = await db.query(
      'voucher_items',
      columns: ['voucher_id', 'description', 'narration'],
    );

    // Group item text by parent voucher id.
    final itemsByParent = <String, List<String>>{};
    for (final item in allItems) {
      final pid  = (item['voucher_id'] as int).toString();
      final desc = (item['description'] as String? ?? '').trim();
      final narr = (item['narration']   as String? ?? '').trim();
      if (desc.isNotEmpty) itemsByParent.putIfAbsent(pid, () => []).add(desc);
      if (narr.isNotEmpty) itemsByParent.putIfAbsent(pid, () => []).add(narr);
    }

    final allTf   = <Map<String, double>>[];
    final rawDocs = <_RawDoc>[];

    for (final r in headers) {
      final id     = (r['id']           as int).toString();
      final billNo = (r['bill_no']      as String? ?? '').trim();
      final party  = (r['party_name']   as String? ?? '').trim();
      final type   = (r['voucher_type'] as String? ?? '').trim();
      final date   = (r['date']         as String? ?? '').trim();
      final amount = r['total_amount'];
      final status = (r['status']       as String? ?? '').trim();

      final amountStr = amount != null
          ? '₹${(amount as num).toStringAsFixed(0)}'
          : '';

      final displayParts = <String>[
        if (billNo.isNotEmpty)    billNo,
        if (party.isNotEmpty)     party,
        if (amountStr.isNotEmpty) amountStr,
        if (date.isNotEmpty)      _formatDateShort(date),
      ];

      final itemDescs = itemsByParent[id] ?? const [];

      final searchText = [
        billNo, billNo,     // bill number gets extra TF weight
        party,  party,      // party name weighted similarly
        type, status,
        date, amountStr,
        ...itemDescs,       // line-item descriptions expand the vocabulary
      ].join(' ');

      final tf = termFrequency(tokenize(searchText));
      allTf.add(tf);
      rawDocs.add(_RawDoc(
        recordId:    id,
        displayText: displayParts.join(' · '),
        searchText:  searchText,
        tf:          tf,
      ));
    }

    return _finalize(IndexDomain.vouchers, rawDocs, allTf);
  }

  // ── Salary Snapshots ───────────────────────────────────────────────────────
  //
  // One IndexEntry per employee-per-snapshot row.
  //
  //   recordId    = employee_id  — Stage-1 ID lookup without the join
  //   secondaryId = snapshot_id  — fast parent lookup from hit results
  //
  // displayText: "Rajesh Kumar · April 2026 · ₹52,000"
  // searchText:  name × 2 + dept + desig + short/full month + month# + year
  //
  // Month appears in three forms ("apr", "april", "04") so queries like
  // "salary April", "salary 4", "salary 04" all resolve via Stage-2 vector
  // even when the exact form isn't matched in Stage-1's monthHint filter.
  //
  // ⚠ SCHEMA NOTE: adjust column names if yours differ from the join below.
  //   If salary_disbursements / salary_disbursement_items (the older table
  //   pair) are still active, add a second builder method for those rows and
  //   merge the rawDocs lists before calling _finalize().

  Future<({List<IndexEntry> entries, Map<String, double> idf})>
      _buildSalarySnapshots() async {
    final db = await DatabaseHelper.instance.database;

    final rows = await db.rawQuery('''
      SELECT
        sme.snapshot_id                AS snapshot_id,
        sme.employee_id                AS employee_id,
        sme.employee_name              AS employee_name,
        sme.department                 AS department,
        sme.designation                AS designation,
        sme.net_salary                 AS net_salary,
        sms.month                      AS month,
        sms.year                       AS year
      FROM salary_month_employees  sme
      INNER JOIN salary_month_snapshots sms
        ON sme.snapshot_id = sms.id
      ORDER BY sms.year DESC, sms.month DESC
    ''');

    final allTf   = <Map<String, double>>[];
    final rawDocs = <_RawDoc>[];

    for (final r in rows) {
      final empId      = (r['employee_id'] as int).toString();
      final snapshotId = (r['snapshot_id'] as int).toString();
      final name       = (r['employee_name'] as String? ?? '').trim();
      final dept       = (r['department']    as String? ?? '').trim();
      final desig      = (r['designation']   as String? ?? '').trim();
      final netSalary  = r['net_salary'];
      final monthInt   = r['month'] is int
          ? r['month'] as int
          : int.tryParse(r['month'].toString()) ?? 0;
      final year       = r['year']?.toString() ?? '';

      final monthShort = _monthShort(monthInt);
      final monthFull  = _monthFull(monthInt);
      final monthPadded = monthInt.toString().padLeft(2, '0');
      final salaryStr  = netSalary != null
          ? '₹${(netSalary as num).toStringAsFixed(0)}'
          : '';

      final displayParts = <String>[
        if (name.isNotEmpty)       name,
        if (monthFull.isNotEmpty && year.isNotEmpty) '$monthFull $year',
        if (salaryStr.isNotEmpty)  salaryStr,
      ];

      final searchText = [
        name, name,
        dept, desig,
        monthShort, monthFull, monthPadded, monthInt.toString(),
        year,
        salaryStr,
      ].join(' ');

      final tf = termFrequency(tokenize(searchText));
      allTf.add(tf);
      rawDocs.add(_RawDoc(
        recordId:    empId,
        secondaryId: snapshotId,
        displayText: displayParts.join(' · '),
        searchText:  searchText,
        tf:          tf,
      ));
    }

    return _finalize(IndexDomain.salarySnapshots, rawDocs, allTf);
  }

  // ── Shared finalization ────────────────────────────────────────────────────

  /// Computes global IDF, applies TF-IDF to each doc, wraps into IndexEntry.
  ///
  /// Returns an empty corpus (rather than crashing) when the source table is
  /// empty — valid state for a freshly installed app with no data yet.
  ({List<IndexEntry> entries, Map<String, double> idf}) _finalize(
    IndexDomain domain,
    List<_RawDoc> rawDocs,
    List<Map<String, double>> allTf,
  ) {
    if (rawDocs.isEmpty) {
      if (kDebugMode) {
        debugPrint('[SemanticIndexBuilder] $domain — source table is empty');
      }
      return (entries: const [], idf: const {});
    }

    final idf = computeIdf(allTf);

    final entries = rawDocs.map((d) => IndexEntry(
      domain:      domain,
      recordId:    d.recordId,
      secondaryId: d.secondaryId,
      displayText: d.displayText,
      searchText:  d.searchText,
      termVector:  applyTfIdf(d.tf, idf),
    )).toList(growable: false);

    return (entries: entries, idf: idf);
  }

  // ── Source row count (staleness check) ────────────────────────────────────

  Future<int> _sourceRowCount(IndexDomain domain) async {
    final db = await DatabaseHelper.instance.database;
    return switch (domain) {
      IndexDomain.employees =>
        _countRows(db, 'employees'),
      IndexDomain.vouchers =>
        _countRows(db, 'vouchers'),
      // salary_month_employees is the leaf table — a snapshot with N employees
      // contributes N index entries, so its row-count is the right sentinel.
      IndexDomain.salarySnapshots =>
        _countRows(db, 'salary_month_employees'),
    };
  }

  Future<int> _countRows(Database db, String table) async {
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (result.first['c'] as int? ?? 0);
  }

  // ── Date / month helpers ───────────────────────────────────────────────────

  /// Converts "YYYY-MM-DD" or "DD/MM/YYYY" to "12 Mar 2025" for displayText.
  static String _formatDateShort(String raw) {
    try {
      final parts = raw.split(RegExp(r'[-/]'));
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          // ISO format: YYYY-MM-DD
          return '${parts[2].padLeft(2, '0')} '
              '${_monthShort(int.parse(parts[1]))} '
              '${parts[0]}';
        } else {
          // Locale format: DD/MM/YYYY or DD-MM-YYYY
          return '${parts[0].padLeft(2, '0')} '
              '${_monthShort(int.parse(parts[1]))} '
              '${parts[2]}';
        }
      }
    } catch (_) {}
    return raw; // return as-is if parsing fails
  }

  static String _monthShort(int m) => const [
        '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m.clamp(0, 12)];

  static String _monthFull(int m) => const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December',
      ][m.clamp(0, 12)];
}

// ── Internal DTO ──────────────────────────────────────────────────────────────

/// Ephemeral struct used during a single domain build to carry partially-
/// constructed entry data before IDF weights are available.
/// Never exported outside this file.
class _RawDoc {
  const _RawDoc({
    required this.recordId,
    this.secondaryId,
    required this.displayText,
    required this.searchText,
    required this.tf,
  });

  final String recordId;
  final String? secondaryId;
  final String displayText;
  final String searchText;
  final Map<String, double> tf;
}

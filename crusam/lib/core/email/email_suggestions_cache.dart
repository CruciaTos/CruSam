// lib/core/email/email_suggestions_cache.dart
//
// In-memory cache of "people you've emailed before", shared by every send
// dialog (invoices, salary documents, ...). Loaded once per app session —
// not once per dialog open, not once per keystroke — every dialog reuses
// the same cached list for the rest of the launch. Resets only on the next
// app restart.
//
// This replaces an earlier Autocomplete-widget-based version that crashed
// the app. Deliberately conservative this time:
//   - No Autocomplete / RawAutocomplete — no shared-controller, no overlay
//     positioning, none of that machinery. Just a plain TextField with a
//     PopupMenuButton suffix icon (see SendInvoiceDialog / SendSalaryDialog).
//   - A DB read failure here can never throw into the caller — it's caught
//     and the cache just falls back to the seeded defaults. A crash in a
//     "nice to have" suggestions list is worse than the list being empty.
//   - Loaded once and cached; reopening a dialog never re-queries the DB.

import 'package:flutter/foundation.dart';

import '../../data/db/database_helper.dart';
import '../../data/db/email_log_repository.dart';

class EmailSuggestionsCache {
  EmailSuggestionsCache._();
  static final EmailSuggestionsCache instance = EmailSuggestionsCache._();

  /// Always present in the dropdown, even on a brand-new install with no
  /// send history yet.
  static const List<String> seedDefaults = [
    'sohamboridkar@gmail.com',
    'bharatboridkar@gmail.com',
  ];

  List<String>? _cached;
  Future<List<String>>? _inFlight;

  /// Returns the suggestion list, loading it from the database the first
  /// time this is called in the current app session. Every later call —
  /// from any dialog — resolves instantly from memory. Never throws: any
  /// DB error falls back to [seedDefaults] only.
  Future<List<String>> load() {
    final cached = _cached;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _loadFromDb();
  }

  Future<List<String>> _loadFromDb() async {
    try {
      final fromDb =
          await DatabaseHelper.instance.getAllDistinctSentRecipientEmails();
      final merged = <String>[...fromDb];
      for (final d in seedDefaults) {
        if (!merged.contains(d)) merged.add(d);
      }
      _cached = merged;
    } catch (e, st) {
      debugPrint('EmailSuggestionsCache: DB read failed, '
          'falling back to defaults only: $e\n$st');
      _cached = List.of(seedDefaults);
    } finally {
      _inFlight = null;
    }
    return _cached!;
  }

  /// Bumps [email] to the top of the cached list right after a successful
  /// send, so a brand-new recipient is offered as a suggestion immediately
  /// — without waiting for the next app launch to re-query the database.
  void noteUsed(String email) {
    final e = email.trim();
    if (e.isEmpty) return;
    _cached ??= List.of(seedDefaults);
    _cached!.remove(e);
    _cached!.insert(0, e);
  }

  /// Whatever's cached right now, or empty if [load] hasn't resolved yet.
  /// Safe to call from build() — never triggers a DB read itself.
  List<String> get cachedOrEmpty => _cached ?? const [];
}
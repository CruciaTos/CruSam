// lib/core/ai/services/api_usage_manager.dart
//
// Tracks Gemini API usage and enforces token + rate limits.
// All limits are configurable and persisted to SharedPreferences.
//
// INTEGRATION — in gemini_service.dart, two hooks:
//
//   // Before the HTTP call:
//   await ApiUsageManager.instance.enforceBeforeRequest();
//
//   // After extracting the response text:
//   final tokens = (decoded['usageMetadata']?['totalTokenCount'] as num?)?.toInt()
//       ?? (text.length ~/ 4);
//   await ApiUsageManager.instance.recordUsage(tokens);
//
// DEFAULTS (Gemini Flash free tier):
//   • 1 000 000 tokens / day
//   • 15 requests / minute
//   • 1 500 requests / day
//
// Change via updateLimits() — persisted across restarts.
//
// STATS UI — call getStats() to get a snapshot for display in Settings.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Limit-check types
// ─────────────────────────────────────────────────────────────────────────────

enum ApiLimitType {
  requestsPerMinute,
  requestsPerDay,
  dailyTokens,
}

class ApiLimitViolation {
  const ApiLimitViolation({
    required this.type,
    required this.message,
    required this.resetAt,
  });

  final ApiLimitType type;
  final String message; // technical detail
  final DateTime resetAt;

  /// Emoji-prefixed message suitable for direct display in the chat UI.
  String get userMessage {
    switch (type) {
      case ApiLimitType.requestsPerMinute:
        return '⏱️ Rate limit hit — too many requests. Wait a few seconds and try again.';
      case ApiLimitType.requestsPerDay:
        return '📊 Daily request limit reached. Resets at midnight.';
      case ApiLimitType.dailyTokens:
        return '🪙 Daily token budget exhausted. Resets at midnight.';
    }
  }
}

/// Thrown by [ApiUsageManager.enforceBeforeRequest] when any limit is exceeded.
/// [GeminiService] lets this propagate so [AiChatNotifier._friendlyError]
/// surfaces it as a chat error message.
class ApiRateLimitException implements Exception {
  const ApiRateLimitException(this.violation);

  final ApiLimitViolation violation;

  @override
  String toString() => violation.userMessage;
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats snapshot — read by settings / debug UI
// ─────────────────────────────────────────────────────────────────────────────

class ApiUsageStats {
  const ApiUsageStats({
    required this.tokensUsedToday,
    required this.dailyTokenLimit,
    required this.requestsThisMinute,
    required this.rpmLimit,
    required this.requestsToday,
    required this.dailyRequestLimit,
    required this.resetDate,
  });

  final int tokensUsedToday;
  final int dailyTokenLimit;
  final int requestsThisMinute;
  final int rpmLimit;
  final int requestsToday;
  final int dailyRequestLimit;
  final DateTime resetDate;

  /// 0.0 – 1.0 fraction of daily token budget used.
  double get tokenUsagePercent =>
      dailyTokenLimit == 0 ? 0.0 : (tokensUsedToday / dailyTokenLimit).clamp(0.0, 1.0);

  int get tokensRemaining =>
      (dailyTokenLimit - tokensUsedToday).clamp(0, dailyTokenLimit);

  /// One-liner for a chip/badge: "342k / 1M tokens".
  String get tokenBadge =>
      '${_compact(tokensUsedToday)} / ${_compact(dailyTokenLimit)} tokens';

  /// One-liner: "47 / 1500 requests today  ·  3 / 15 rpm".
  String get requestBadge =>
      '$requestsToday / $dailyRequestLimit req today  ·  '
      '$requestsThisMinute / $rpmLimit rpm';

  static String _compact(int n) {
    if (n >= 1_000_000) return '${(n / 1_000_000).toStringAsFixed(1)}M';
    if (n >= 1_000) return '${(n / 1_000).toStringAsFixed(0)}k';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manager
// ─────────────────────────────────────────────────────────────────────────────

class ApiUsageManager {
  ApiUsageManager._();
  static final ApiUsageManager instance = ApiUsageManager._();

  static const String _prefsKey = 'api_usage_v1';

  // ── Configurable limits ───────────────────────────────────────────────────
  // Defaults = Gemini Flash free tier. Override with updateLimits().
  int dailyTokenLimit = 1_000_000;  // tokens / day
  int rpmLimit = 15;                 // requests / minute
  int dailyRequestLimit = 1_500;     // requests / day

  // ── State ─────────────────────────────────────────────────────────────────
  String _trackingDate = '';         // 'YYYY-MM-DD' of the current window
  int _tokensUsedToday = 0;
  int _requestsToday = 0;
  final List<DateTime> _rpmWindow = []; // sliding 60-second window

  bool _loaded = false;

  // ── Getters for quick reads ───────────────────────────────────────────────
  int get tokensUsedToday => _tokensUsedToday;
  int get requestsToday => _requestsToday;

  // ══════════════════════════════════════════════════════════════════════════
  // Initialization
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null) {
        final d = jsonDecode(raw) as Map<String, dynamic>;

        // Always restore user-configured limits regardless of date.
        dailyTokenLimit =
            (d['daily_token_limit'] as num?)?.toInt() ?? dailyTokenLimit;
        rpmLimit = (d['rpm_limit'] as num?)?.toInt() ?? rpmLimit;
        dailyRequestLimit =
            (d['daily_request_limit'] as num?)?.toInt() ?? dailyRequestLimit;

        final savedDate = (d['date'] as String?) ?? '';
        if (savedDate == _today()) {
          _trackingDate = savedDate;
          _tokensUsedToday = (d['tokens_today'] as num?)?.toInt() ?? 0;
          _requestsToday = (d['requests_today'] as num?)?.toInt() ?? 0;
        } else {
          // New day — zero the counters (limits already restored above).
          _resetDailyCounters();
        }
      } else {
        _resetDailyCounters();
      }
      _loaded = true;
      debugPrint(
        'ApiUsageManager.load: '
        'tokens=$_tokensUsedToday/$dailyTokenLimit  '
        'requests=$_requestsToday/$dailyRequestLimit  '
        'rpmLimit=$rpmLimit',
      );
    } catch (e) {
      debugPrint('ApiUsageManager.load error (non-fatal): $e');
      _resetDailyCounters();
      _loaded = true;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Enforcement — call BEFORE the API request
  // ══════════════════════════════════════════════════════════════════════════

  /// Throws [ApiRateLimitException] if any limit is exceeded.
  /// Does NOT count the request itself — call [recordUsage] after success.
  Future<void> enforceBeforeRequest() async {
    if (!_loaded) await load();
    _maybeResetDay();
    _trimRpmWindow();

    // 1. RPM
    if (_rpmWindow.length >= rpmLimit) {
      final resetAt = _rpmWindow.first.add(const Duration(minutes: 1));
      throw ApiRateLimitException(ApiLimitViolation(
        type: ApiLimitType.requestsPerMinute,
        message: 'RPM limit: ${_rpmWindow.length}/$rpmLimit. '
            'Resets at ${_hms(resetAt)}.',
        resetAt: resetAt,
      ));
    }

    // 2. Daily requests
    if (_requestsToday >= dailyRequestLimit) {
      throw ApiRateLimitException(ApiLimitViolation(
        type: ApiLimitType.requestsPerDay,
        message: 'Daily request limit: '
            '$_requestsToday/$dailyRequestLimit. Resets at midnight.',
        resetAt: _tomorrowMidnight(),
      ));
    }

    // 3. Daily tokens
    if (_tokensUsedToday >= dailyTokenLimit) {
      throw ApiRateLimitException(ApiLimitViolation(
        type: ApiLimitType.dailyTokens,
        message: 'Daily token budget: '
            '$_tokensUsedToday/$dailyTokenLimit used. Resets at midnight.',
        resetAt: _tomorrowMidnight(),
      ));
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Recording — call AFTER a successful API response
  // ══════════════════════════════════════════════════════════════════════════

  /// Record a completed request.
  ///
  /// [totalTokens] should come from `usageMetadata.totalTokenCount` in the
  /// Gemini response JSON. If the field is absent, pass `text.length ~/ 4`
  /// as a rough estimate (≈ 4 chars per token).
  Future<void> recordUsage(int totalTokens) async {
    _maybeResetDay();

    _tokensUsedToday += totalTokens;
    _requestsToday++;
    _rpmWindow.add(DateTime.now());

    debugPrint(
      'ApiUsageManager.recordUsage: '
      '+$totalTokens tok  '
      'day: $_tokensUsedToday/$dailyTokenLimit  '
      'req: $_requestsToday/$dailyRequestLimit  '
      'rpm: ${_rpmWindow.length}/$rpmLimit',
    );

    await _persist();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Configuration
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> updateLimits({
    int? dailyTokens,
    int? rpm,
    int? dailyRequests,
  }) async {
    if (!_loaded) await load();
    if (dailyTokens != null) dailyTokenLimit = dailyTokens;
    if (rpm != null) rpmLimit = rpm;
    if (dailyRequests != null) dailyRequestLimit = dailyRequests;
    await _persist();
    debugPrint(
      'ApiUsageManager.updateLimits: '
      'tokens=$dailyTokenLimit  rpm=$rpmLimit  rpd=$dailyRequestLimit',
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Stats
  // ══════════════════════════════════════════════════════════════════════════

  Future<ApiUsageStats> getStats() async {
    if (!_loaded) await load();
    _maybeResetDay();
    _trimRpmWindow();
    return ApiUsageStats(
      tokensUsedToday: _tokensUsedToday,
      dailyTokenLimit: dailyTokenLimit,
      requestsThisMinute: _rpmWindow.length,
      rpmLimit: rpmLimit,
      requestsToday: _requestsToday,
      dailyRequestLimit: dailyRequestLimit,
      resetDate: _tomorrowMidnight(),
    );
  }

  /// Hard-reset today's counters — useful for testing.
  Future<void> resetToday() async {
    _resetDailyCounters();
    await _persist();
    debugPrint('ApiUsageManager.resetToday: counters cleared');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Private helpers
  // ══════════════════════════════════════════════════════════════════════════

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-'
        '${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  void _maybeResetDay() {
    if (_trackingDate != _today()) _resetDailyCounters();
  }

  void _resetDailyCounters() {
    _trackingDate = _today();
    _tokensUsedToday = 0;
    _requestsToday = 0;
    _rpmWindow.clear();
    debugPrint('ApiUsageManager: counters reset for $_trackingDate');
  }

  void _trimRpmWindow() {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    _rpmWindow.removeWhere((t) => t.isBefore(cutoff));
  }

  static DateTime _tomorrowMidnight() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day + 1);
  }

  static String _hms(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode({
          'date': _trackingDate,
          'tokens_today': _tokensUsedToday,
          'requests_today': _requestsToday,
          'daily_token_limit': dailyTokenLimit,
          'rpm_limit': rpmLimit,
          'daily_request_limit': dailyRequestLimit,
        }),
      );
    } catch (e) {
      debugPrint('ApiUsageManager._persist error (non-fatal): $e');
    }
  }
}
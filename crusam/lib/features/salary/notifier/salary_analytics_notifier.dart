// lib/features/salary/notifier/salary_analytics_notifier.dart
//
// UI state for Salary Analytics. Reads exclusively through
// SalaryAnalyticsRepository + SalaryAnalyticsAggregationService — never
// SalaryDataNotifier / SalaryStateController.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/db/salary_analytics_repository.dart';
import '../../../shared/utils/financial_year_utils.dart';
import '../models/salary_analytics_models.dart';
import '../services/salary_analytics_aggregation_service.dart';

enum SalaryAnalyticsFilterPreset {
  thisFinancialYear,
  lastFinancialYear,
  thisCalendarYear,
  custom,
}

class SalaryAnalyticsNotifier extends ChangeNotifier {
  SalaryAnalyticsNotifier._();
  static final SalaryAnalyticsNotifier instance = SalaryAnalyticsNotifier._();

  static const _prefsKey = 'salary_analytics_filter_v1';

  final _repo = SalaryAnalyticsRepository.instance;
  final _aggregator = const SalaryAnalyticsAggregationService();

  List<MonthYear> availableMonths = [];
  List<MonthYear> selectedMonths = [];
  SalaryAnalyticsFilterPreset preset = SalaryAnalyticsFilterPreset.thisFinancialYear;
  PayrollAnalyticsSnapshot snapshot = PayrollAnalyticsSnapshot.empty;
  Set<int> expandedKeys = {};

  bool isLoading = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      availableMonths = await _repo.getAvailableMonths();
      await _restoreFilter();
      await _refreshSnapshot();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      availableMonths = await _repo.getAvailableMonths();
      await _refreshSnapshot();
    } catch (e) {
      error = e.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshSnapshot() async {
    final records = await _repo.getRecordsForMonths(selectedMonths);
    snapshot = _aggregator.aggregate(records: records, selectedMonths: selectedMonths);
  }

  // ── Filters ────────────────────────────────────────────────────────────
  Future<void> selectPreset(SalaryAnalyticsFilterPreset p) async {
    preset = p;
    switch (p) {
      case SalaryAnalyticsFilterPreset.thisFinancialYear:
        selectedMonths = FinancialYearUtils.thisFinancialYear();
        break;
      case SalaryAnalyticsFilterPreset.lastFinancialYear:
        selectedMonths = FinancialYearUtils.lastFinancialYear();
        break;
      case SalaryAnalyticsFilterPreset.thisCalendarYear:
        selectedMonths = FinancialYearUtils.thisCalendarYear();
        break;
      case SalaryAnalyticsFilterPreset.custom:
        break; // caller follows up with setCustomMonths(...)
    }
    await _persistFilter();
    await _reload();
  }

  Future<void> setCustomMonths(List<MonthYear> months) async {
    preset = SalaryAnalyticsFilterPreset.custom;
    selectedMonths = months;
    await _persistFilter();
    await _reload();
  }

  Future<void> _reload() async {
    isLoading = true;
    notifyListeners();
    try {
      await _refreshSnapshot();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  // ── Expand / collapse (no extra DB query — uses cached snapshot) ───────
  void toggleExpanded(int employeeId) {
    if (expandedKeys.contains(employeeId)) {
      expandedKeys = {...expandedKeys}..remove(employeeId);
    } else {
      expandedKeys = {...expandedKeys, employeeId};
    }
    notifyListeners();
  }

  bool isExpanded(int employeeId) => expandedKeys.contains(employeeId);

  // ── Persistence ────────────────────────────────────────────────────────
  Future<void> _persistFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'preset': preset.name,
        'months': selectedMonths.map((m) => {'month': m.month, 'year': m.year}).toList(),
      };
      await prefs.setString(_prefsKey, jsonEncode(payload));
    } catch (_) {
      // Non-fatal — filter just won't be restored next launch.
    }
  }

  Future<void> _restoreFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        selectedMonths = FinancialYearUtils.thisFinancialYear();
        preset = SalaryAnalyticsFilterPreset.thisFinancialYear;
        return;
      }
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final presetName = decoded['preset'] as String?;
      final months = (decoded['months'] as List?) ?? const [];

      preset = SalaryAnalyticsFilterPreset.values.firstWhere(
        (p) => p.name == presetName,
        orElse: () => SalaryAnalyticsFilterPreset.thisFinancialYear,
      );

      if (preset == SalaryAnalyticsFilterPreset.custom && months.isNotEmpty) {
        selectedMonths = months
            .whereType<Map>()
            .map((m) => MonthYear(
                  (m['month'] as num?)?.toInt() ?? 1,
                  (m['year'] as num?)?.toInt() ?? DateTime.now().year,
                ))
            .toList();
      } else {
        switch (preset) {
          case SalaryAnalyticsFilterPreset.lastFinancialYear:
            selectedMonths = FinancialYearUtils.lastFinancialYear();
            break;
          case SalaryAnalyticsFilterPreset.thisCalendarYear:
            selectedMonths = FinancialYearUtils.thisCalendarYear();
            break;
          default:
            selectedMonths = FinancialYearUtils.thisFinancialYear();
            preset = SalaryAnalyticsFilterPreset.thisFinancialYear;
        }
      }
    } catch (_) {
      selectedMonths = FinancialYearUtils.thisFinancialYear();
      preset = SalaryAnalyticsFilterPreset.thisFinancialYear;
    }
  }
}
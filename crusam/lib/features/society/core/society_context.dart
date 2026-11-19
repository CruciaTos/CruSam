import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_services.dart';
import 'package:crusam/features/society/data/models/society_models.dart';

class SocietyContext extends ChangeNotifier {
  SocietyContext._();
  static final SocietyContext instance = SocietyContext._();

  int? _societyId;
  Society? _society;
  FinancialYear? _financialYear;
  List<SocietySummary> _societies = [];
  bool _allSocieties = false;
  bool _loading = false;
  String? _error;
  bool _loaded = false;

  int? get societyId => _societyId;
  Society? get society => _society;
  FinancialYear? get financialYear => _financialYear;
  List<SocietySummary> get societies => _societies;
  bool get allSocieties => _allSocieties;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    await reload();
  }

  Future<void> reload() async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final services = await SocietyServices.instance();
      _societies = await services.society.listSocieties();

      final db = services.db;
      final lastSocVal = await _getAppSetting(db, 'society.last_society_id');
      final lastFyVal = await _getAppSetting(db, 'society.last_fy_id');

      if (lastSocVal == 'all') {
        _allSocieties = true;
        _societyId = null;
        _society = null;
        _financialYear = null;
      } else {
        int? targetId = int.tryParse(lastSocVal ?? '');
        if (targetId == null || !_societies.any((s) => s.id == targetId)) {
          targetId = _societies.isNotEmpty ? _societies.first.id : null;
        }

        if (targetId != null) {
          _allSocieties = false;
          _societyId = targetId;
          _society = await services.society.getSociety(targetId);
          final years = await services.society.listFinancialYears(targetId);

          int? targetFyId = int.tryParse(lastFyVal ?? '');
          FinancialYear? selectedFy;
          if (targetFyId != null) {
            for (final y in years) {
              if (y.id == targetFyId) {
                selectedFy = y;
                break;
              }
            }
          }
          if (selectedFy == null) {
            for (final y in years.reversed) {
              if (y.isOpen) {
                selectedFy = y;
                break;
              }
            }
          }
          _financialYear = selectedFy ?? (years.isNotEmpty ? years.last : null);
        } else {
          _allSocieties = false;
          _societyId = null;
          _society = null;
          _financialYear = null;
        }
      }
      _loaded = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectSociety(int id) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final services = await SocietyServices.instance();
      _society = await services.society.getSociety(id);
      _societyId = id;
      _allSocieties = false;

      final years = await services.society.listFinancialYears(id);
      FinancialYear? selectedFy;
      for (final y in years.reversed) {
        if (y.isOpen) {
          selectedFy = y;
          break;
        }
      }
      _financialYear = selectedFy ?? (years.isNotEmpty ? years.last : null);

      await _setAppSetting(services.db, 'society.last_society_id', id.toString());
      if (_financialYear != null) {
        await _setAppSetting(services.db, 'society.last_fy_id', _financialYear!.id.toString());
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectAllSocieties() async {
    _allSocieties = true;
    _societyId = null;
    _society = null;
    _financialYear = null;
    notifyListeners();

    try {
      final services = await SocietyServices.instance();
      await _setAppSetting(services.db, 'society.last_society_id', 'all');
    } catch (_) {}
  }

  Future<void> selectFinancialYear(int fyId) async {
    if (_societyId == null) return;
    try {
      final services = await SocietyServices.instance();
      final years = await services.society.listFinancialYears(_societyId!);
      for (final y in years) {
        if (y.id == fyId) {
          _financialYear = y;
          await _setAppSetting(services.db, 'society.last_fy_id', fyId.toString());
          notifyListeners();
          break;
        }
      }
    } catch (_) {}
  }

  Future<String?> _getAppSetting(Database db, String key) async {
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _setAppSetting(Database db, String key, String value) async {
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  void resetForTest() {
    _societyId = null;
    _society = null;
    _financialYear = null;
    _societies = [];
    _allSocieties = false;
    _loading = false;
    _error = null;
    _loaded = false;
  }
}

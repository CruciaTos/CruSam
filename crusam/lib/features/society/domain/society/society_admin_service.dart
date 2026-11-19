import 'package:sqflite/sqflite.dart';
import 'package:crusam/features/society/core/society_date.dart';
import 'package:crusam/features/society/core/society_exception.dart';
import 'package:crusam/features/society/data/models/society_models.dart';
import 'package:crusam/features/society/data/repositories/society_repository.dart';
import 'package:crusam/features/society/data/seed/society_seed.dart';

class SocietyAdminService {
  final Database db;
  late final SocietyRepository _repo;

  SocietyAdminService(this.db) {
    _repo = SocietyRepository(db);
  }

  Future<List<SocietySummary>> listSocieties({bool includeInactive = false}) {
    return _repo.listSocieties(includeInactive: includeInactive);
  }

  Future<Society> getSociety(int societyId) async {
    final society = await _repo.getSociety(societyId);
    if (society == null) {
      throw SocietyException('not_found', 'Society not found: $societyId');
    }
    return society;
  }

  Future<int> createSociety(SocietyDraft draft) async {
    final name = draft.name.trim();
    if (name.isEmpty) {
      throw const SocietyException('validation', 'Society name cannot be empty');
    }
    if (draft.booksStartDate.trim().isEmpty) {
      throw const SocietyException('validation', 'Books start date is required');
    }

    try {
      parseIsoDate(draft.booksStartDate);
    } catch (_) {
      throw const SocietyException('validation', 'Invalid books start date format (YYYY-MM-DD)');
    }

    return db.transaction((txn) async {
      final existing = await txn.query(
        'societies',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw SocietyException('duplicate', 'A society with name "$name" already exists');
      }

      final id = await _repo.insertSociety(txn, draft);
      await seedNewSociety(txn, societyId: id, booksStartDate: draft.booksStartDate);
      await writeAudit(txn, id, 'create', 'society', id, 'Created society $name');
      return id;
    });
  }

  Future<void> updateSociety(int societyId, SocietyDraft draft) async {
    final existing = await getSociety(societyId);

    if (existing.booksStartDate != draft.booksStartDate) {
      final journals = await db.query(
        'journal_entries',
        columns: ['id'],
        where: 'society_id = ?',
        whereArgs: [societyId],
        limit: 1,
      );
      if (journals.isNotEmpty) {
        throw const SocietyException(
          'validation',
          'Cannot change books start date after journals are posted',
        );
      }
    }

    await db.transaction((txn) async {
      await _repo.updateSociety(txn, societyId, draft);
      await writeAudit(txn, societyId, 'update', 'society', societyId, 'Updated society ${draft.name}');
    });
  }

  Future<void> setSocietyActive(int societyId, bool active) async {
    await db.transaction((txn) async {
      await _repo.setSocietyActive(txn, societyId, active);
      await writeAudit(
        txn,
        societyId,
        'update',
        'society',
        societyId,
        active ? 'Activated society' : 'Deactivated society',
      );
    });
  }

  Future<List<FinancialYear>> listFinancialYears(int societyId) {
    return _repo.listFinancialYears(societyId);
  }

  Future<int> createNextFinancialYear(int societyId) async {
    return db.transaction((txn) async {
      final years = await txn.query(
        'financial_years',
        where: 'society_id = ?',
        whereArgs: [societyId],
        orderBy: 'start_date DESC',
        limit: 1,
      );
      if (years.isEmpty) {
        throw const SocietyException('not_found', 'No existing financial years found');
      }

      final latest = FinancialYear.fromMap(years.first);
      final currentStartYear = int.parse(latest.code.split('-')[0]);
      final nextStartYear = currentStartYear + 1;
      final nextEndYearShort = (nextStartYear + 1).toString().substring(2);
      final nextCode = '$nextStartYear-$nextEndYearShort';
      final nextStart = '$nextStartYear-04-01';
      final nextEnd = '${nextStartYear + 1}-03-31';

      final fyId = await _repo.insertFinancialYear(
        txn,
        societyId,
        nextCode,
        nextStart,
        nextEnd,
      );
      await seedNumberSeriesForFy(txn, societyId: societyId, fyId: fyId, fyCode: nextCode);
      await writeAudit(
        txn,
        societyId,
        'create',
        'financial_year',
        fyId,
        'Created financial year $nextCode',
      );
      return fyId;
    });
  }

  Future<String?> getSetting(int societyId, String key) {
    return _repo.getSetting(societyId, key);
  }

  Future<Map<String, String>> getAllSettings(int societyId) {
    return _repo.getAllSettings(societyId);
  }

  Future<void> setSettings(int societyId, Map<String, String?> values) async {
    await db.transaction((txn) async {
      for (final entry in values.entries) {
        await _repo.setSetting(txn, societyId, entry.key, entry.value);
      }
      await writeAudit(
        txn,
        societyId,
        'update',
        'settings',
        null,
        'Updated society settings (${values.keys.join(", ")})',
      );
    });
  }

  Future<String?> getDatedSetting(int societyId, String key, String onDate) {
    return _repo.getDatedSetting(societyId, key, onDate);
  }

  Future<void> addDatedSetting(
    int societyId,
    String key,
    String value,
    String from, {
    String? note,
  }) async {
    await db.transaction((txn) async {
      await _repo.addDatedSetting(txn, societyId, key, value, from, note: note);
      await writeAudit(
        txn,
        societyId,
        'create',
        'dated_setting',
        null,
        'Added dated setting $key = $value from $from',
      );
    });
  }

  Future<void> writeAudit(
    DatabaseExecutor executor,
    int? societyId,
    String action,
    String entityType,
    int? entityId,
    String summary,
  ) {
    return _repo.insertAudit(executor, societyId, action, entityType, entityId, summary);
  }
}

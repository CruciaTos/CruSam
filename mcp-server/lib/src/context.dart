import 'package:crusam_core/crusam_core.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import 'db.dart';

/// Shared by every tool group: the database plus injectable clock/ids so
/// tests are deterministic.
class ToolContext {
  final CrusamDb store;
  final DateTime Function() clock;
  final String Function() newUuid;

  ToolContext(this.store, {DateTime Function()? clock, String Function()? newUuid})
      : clock = clock ?? DateTime.now,
        newUuid = newUuid ?? (() => const Uuid().v4());

  Database get db => store.db;
  String get userEmail => store.config.userEmail;

  /// UTC ISO timestamp, the convention for invoices/employees.
  String nowUtcIso() => clock().toUtc().toIso8601String();

  /// Local ISO timestamp, the convention for salary snapshots.
  String nowLocalIso() => clock().toLocal().toIso8601String();

  Future<CompanyConfigModel> companyConfig(DatabaseExecutor db) async {
    final rows = await db.query('company_config', limit: 1);
    return rows.isEmpty
        ? const CompanyConfigModel()
        : CompanyConfigModel.fromMap(rows.first);
  }
}

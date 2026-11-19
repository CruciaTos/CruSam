import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:crusam/core/storage/app_paths.dart';
import 'package:crusam/features/society/data/migrations/m001_initial.dart';

class SocietyDatabase {
  SocietyDatabase._();
  static final SocietyDatabase instance = SocietyDatabase._();
  static Database? _db;

  Future<Database> get database async => _db ??= await _init();

  Future<Database> _init() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = await _resolveDbPath();
    return openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA busy_timeout = 5000');
      },
      onCreate: (db, version) async {
        await m001Initial(db);
      },
    );
  }

  static Future<String> _resolveDbPath() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return AppPaths.childPath('society.db');
    }
    return '${await getDatabasesPath()}/society.db';
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }

  static Future<Database> openForTest({String path = inMemoryDatabasePath}) async {
    sqfliteFfiInit();
    final factory = createDatabaseFactoryFfi(noIsolate: true);
    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA busy_timeout = 5000');
        },
        onCreate: (db, version) async {
          await m001Initial(db);
        },
      ),
    );
  }
}

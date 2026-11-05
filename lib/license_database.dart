import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'license_service.dart';

class LicenseDatabase {
  LicenseDatabase._();
  static final LicenseDatabase instance = LicenseDatabase._();
  Database? _db;

  Future<Database> get _database async => _db ??= await _open();

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'license.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) => db.execute('''
        CREATE TABLE license(
          device_id TEXT PRIMARY KEY,
          license_key TEXT NOT NULL,
          activated_at TEXT NOT NULL
        )'''),
    );
  }

  Future<void> saveLicense(String deviceId, String key) async {
    final db = await _database;
    await db.insert(
      'license',
      {
        'device_id': deviceId,
        'license_key': key,
        'activated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isLicensed(String deviceId) async {
    final db = await _database;
    final rows = await db.query('license', where: 'device_id = ?', whereArgs: [deviceId], limit: 1);
    if (rows.isEmpty) return false;
    return LicenseService.validateKey(deviceId, rows.first['license_key'] as String);
  }
}
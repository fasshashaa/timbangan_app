import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:intl/intl.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('timbangan.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2, // Upgrade versi database
      onCreate: _createDB,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('DROP TABLE IF EXISTS transaksi');
          await _createDB(db, newVersion);
        }
      },
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transaksi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nopol TEXT NOT NULL,
        tipe_kendaraan TEXT NOT NULL,
        customer TEXT NOT NULL,
        supir TEXT NOT NULL,
        produk TEXT NOT NULL,
        tara INTEGER NOT NULL,
        bruto INTEGER DEFAULT 0,
        netto INTEGER DEFAULT 0,
        status TEXT NOT NULL,
        waktu TEXT NOT NULL
      )
    ''');
  }

  // Insert Timbang Masuk
  Future<int> insertTimbangMasuk({
    required String nopol,
    required String tipeKendaraan,
    required String customer,
    required String supir,
    required String produk,
    required int tara,
  }) async {
    final db = await instance.database;
    final waktuSekarang = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    return await db.insert('transaksi', {
      'nopol': nopol,
      'tipe_kendaraan': tipeKendaraan,
      'customer': customer,
      'supir': supir,
      'produk': produk,
      'tara': tara,
      'bruto': 0,
      'netto': 0,
      'status': 'PENDING',
      'waktu': waktuSekarang,
    });
  }

  // Update Timbang Keluar
  Future<int> updateTimbangKeluar(int id, int bruto, int tara) async {
    final db = await instance.database;
    int netto = bruto - tara;
    final waktuSekarang = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());

    return await db.update(
      'transaksi',
      {
        'bruto': bruto,
        'netto': netto,
        'status': 'SELESAI',
        'waktu': waktuSekarang,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> getTrukPending() async {
    final db = await instance.database;
    return await db.query('transaksi', where: 'status = ?', whereArgs: ['PENDING'], orderBy: 'id DESC');
  }

  Future<List<Map<String, dynamic>>> getSemuaTransaksi() async {
    final db = await instance.database;
    return await db.query('transaksi', orderBy: 'id DESC');
  }

  // Export Excel dengan Kolom Lengkap.
  // Jika `data` diisi (mis. hasil filter dari halaman Riwayat), baris yang
  // diekspor mengikuti data tersebut. Jika tidak diisi, seluruh transaksi
  // di database yang diekspor (perilaku lama tetap jalan).
  Future<String?> exportToExcel({List<Map<String, dynamic>>? data}) async {
    final rows = data ?? await getSemuaTransaksi();
    if (rows.isEmpty) return null;

    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Riwayat Timbangan'];
    excel.delete('Sheet1');

    sheetObject.appendRow([
      TextCellValue('ID'),
      TextCellValue('Waktu'),
      TextCellValue('No Kendaraan'),
      TextCellValue('Tipe Kendaraan'),
      TextCellValue('Customer'),
      TextCellValue('Supir'),
      TextCellValue('Produk'),
      TextCellValue('Tara (KG)'),
      TextCellValue('Bruto (KG)'),
      TextCellValue('Netto (KG)'),
      TextCellValue('Status')
    ]);

    for (var row in rows) {
      sheetObject.appendRow([
        IntCellValue(row['id']),
        TextCellValue(row['waktu'].toString()),
        TextCellValue(row['nopol'].toString()),
        TextCellValue(row['tipe_kendaraan'].toString()),
        TextCellValue(row['customer'].toString()),
        TextCellValue(row['supir'].toString()),
        TextCellValue(row['produk'].toString()),
        IntCellValue(row['tara']),
        IntCellValue(row['bruto']),
        IntCellValue(row['netto']),
        TextCellValue(row['status'].toString()),
      ]);
    }

    Directory? directory = await getExternalStorageDirectory();
    String newPath = "";
    List<String> paths = directory!.path.split("/");
    for (int x = 1; x < paths.length; x++) {
      String folder = paths[x];
      if (folder != "Android") {
        newPath += "/" + folder;
      } else {
        break;
      }
    }
    newPath = newPath + "/Download";
    directory = Directory(newPath);

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    String filePath = "${directory.path}/Laporan_Timbangan_${DateTime.now().millisecondsSinceEpoch}.xlsx";
    File file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
    return filePath;
  }
}
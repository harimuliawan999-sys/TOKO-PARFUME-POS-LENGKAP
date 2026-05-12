import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();
  static Database? _db;

  Future<Database> get db async {
    _db ??= await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'ks_parfume_v3.db');
    return await openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database db, int version) async {
    // === PRODUK (Bahan Baku + Botol) ===
    await db.execute('''
      CREATE TABLE produk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        kategori TEXT DEFAULT 'STOCK PARFUME',
        harga_beli REAL DEFAULT 0,
        stok REAL DEFAULT 0,
        min_stok REAL DEFAULT 50,
        satuan TEXT DEFAULT 'ml',
        created_at TEXT
      )
    ''');

    // === VARIAN (Produk Jadi = Bibit + Ukuran + Kualitas) ===
    await db.execute('''
      CREATE TABLE varian (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        produk_id INTEGER,
        nama TEXT NOT NULL,
        ukuran TEXT,
        kualitas TEXT,
        harga_jual REAL DEFAULT 0,
        resep_bibit REAL DEFAULT 8,
        resep_botol_id INTEGER,
        FOREIGN KEY (produk_id) REFERENCES produk(id),
        FOREIGN KEY (resep_botol_id) REFERENCES produk(id)
      )
    ''');

    // === TRANSAKSI ===
    await db.execute('''
      CREATE TABLE transaksi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        no_nota TEXT,
        tanggal TEXT,
        user_nama TEXT,
        subtotal REAL DEFAULT 0,
        diskon REAL DEFAULT 0,
        total REAL DEFAULT 0,
        bayar REAL DEFAULT 0,
        kembalian REAL DEFAULT 0,
        metode TEXT DEFAULT 'Cash',
        hpp_total REAL DEFAULT 0
      )
    ''');

    // === DETAIL TRANSAKSI ===
    await db.execute('''
      CREATE TABLE detail_transaksi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        transaksi_id INTEGER,
        varian_id INTEGER,
        nama_item TEXT,
        qty INTEGER DEFAULT 1,
        harga_jual REAL,
        hpp_per_item REAL DEFAULT 0,
        FOREIGN KEY (transaksi_id) REFERENCES transaksi(id)
      )
    ''');

    // === PERGERAKAN STOK ===
    await db.execute('''
      CREATE TABLE stok_movement (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        produk_id INTEGER,
        tipe TEXT,
        qty REAL DEFAULT 0,
        stok_sebelum REAL DEFAULT 0,
        stok_sesudah REAL DEFAULT 0,
        keterangan TEXT,
        tanggal TEXT,
        user_nama TEXT,
        FOREIGN KEY (produk_id) REFERENCES produk(id)
      )
    ''');

    // === STOK MASUK ===
    await db.execute('''
      CREATE TABLE stok_masuk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        produk_id INTEGER,
        nama_produk TEXT,
        qty REAL DEFAULT 0,
        tanggal TEXT,
        user_nama TEXT,
        FOREIGN KEY (produk_id) REFERENCES produk(id)
      )
    ''');

    // === PENGELUARAN ===
    await db.execute('''
      CREATE TABLE pengeluaran (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kategori TEXT,
        keterangan TEXT NOT NULL,
        jumlah REAL DEFAULT 0,
        tanggal TEXT
      )
    ''');

    // === USERS ===
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL,
        pin TEXT NOT NULL,
        peran TEXT DEFAULT 'kasir'
      )
    ''');

    // === PENGATURAN ===
    await db.execute('''
      CREATE TABLE pengaturan (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // ============ DATA AWAL ============
    final now = DateTime.now().toIso8601String();

    // Users
    await db.insert('users', {'nama': 'Owner', 'pin': '1234', 'peran': 'owner'});
    await db.insert('users', {'nama': 'Kasir 1', 'pin': '0000', 'peran': 'kasir'});
    await db.insert('users', {'nama': 'Kasir 2', 'pin': '1111', 'peran': 'kasir'});

    // Pengaturan
    await db.insert('pengaturan', {'key': 'nama_usaha', 'value': 'KS Parfume Tj. Mulia'});
    await db.insert('pengaturan', {'key': 'alamat', 'value': 'Medan, Sumatera Utara'});
    await db.insert('pengaturan', {'key': 'telp', 'value': '081234567890'});

    // Produk (Bibit)
    final bibitAwal = [
      ['BIBIT Ariana Grande Sweet Candy PREMIUM', 'STOCK PARFUME', 900, 50, 50, 'ml'],
      ['BIBIT Annasui Fantasy Mermaid PREMIUM', 'STOCK PARFUME', 1000, 80, 50, 'ml'],
      ['BIBIT Aigner Black PREMIUM', 'STOCK PARFUME', 1500, 120, 50, 'ml'],
      ['BIBIT Aigner Blue PREMIUM', 'STOCK PARFUME', 900, 200, 50, 'ml'],
      ['BIBIT Baccarat Rouge PREMIUM', 'STOCK PARFUME', 1000, 30, 50, 'ml'],
      ['BIBIT Dior Sauvage PREMIUM', 'STOCK PARFUME', 1000, 15, 50, 'ml'],
      ['BIBIT CH Good Girl PREMIUM', 'STOCK PARFUME', 900, 90, 50, 'ml'],
      ['BIBIT Tom Ford PREMIUM', 'STOCK PARFUME', 1500, 45, 50, 'ml'],
      ['BIBIT Versace Eros PREMIUM', 'STOCK PARFUME', 900, 110, 50, 'ml'],
      ['BIBIT Malaikat Subuh', 'STOCK PARFUME', 900, 260, 50, 'ml'],
      ['BIBIT Kasturi Merah', 'STOCK PARFUME', 900, 137, 50, 'ml'],
      ['BIBIT Drakar Nuir', 'STOCK PARFUME', 900, 93, 50, 'ml'],
      ['BIBIT Dior Jadore PREMIUM', 'STOCK PARFUME', 1000, 80, 50, 'ml'],
      ['BIBIT Chanel Allure PREMIUM', 'STOCK PARFUME', 1000, 65, 50, 'ml'],
      ['BIBIT Melati', 'STOCK PARFUME', 400, 300, 50, 'ml'],
      ['BIBIT Mawar', 'STOCK PARFUME', 350, 250, 50, 'ml'],
    ];
    for (final p in bibitAwal) {
      await db.insert('produk', {
        'nama': p[0], 'kategori': p[1], 'harga_beli': p[2],
        'stok': p[3], 'min_stok': p[4], 'satuan': p[5], 'created_at': now,
      });
    }

    // Produk (Botol)
    final botolAwal = [
      ['STOK BOTOL 15ML', 2500, 200, 30], ['STOK BOTOL 20ML', 3000, 180, 30],
      ['STOK BOTOL 25ML', 4000, 150, 30], ['STOK BOTOL 30ML', 5600, 120, 30],
      ['STOK BOTOL 35ML', 5600, 100, 30], ['STOK BOTOL 40ML', 5600, 90, 30],
      ['STOK BOTOL 50ML', 6000, 80, 30], ['STOK BOTOL 100ML', 7000, 60, 30],
    ];
    for (final b in botolAwal) {
      await db.insert('produk', {
        'nama': b[0], 'kategori': 'STOK BOTOL', 'harga_beli': b[1],
        'stok': b[2], 'min_stok': b[3], 'satuan': 'pcs', 'created_at': now,
      });
    }

    // Ambil ID botol
    final botol30 = (await db.query('produk', where: "nama = ?", whereArgs: ['STOK BOTOL 30ML'])).first['id'] as int;
    final botol15 = (await db.query('produk', where: "nama = ?", whereArgs: ['STOK BOTOL 15ML'])).first['id'] as int;
    final botol50 = (await db.query('produk', where: "nama = ?", whereArgs: ['STOK BOTOL 50ML'])).first['id'] as int;

    // Varian contoh: Ariana Grande (produk_id = 1)
    final varianAriana = [
      ['15ml', 'Medium', 30000, 8, botol15], ['15ml', 'Super', 35000, 9, botol15], ['15ml', 'Platinum', 45000, 11, botol15],
      ['30ml', 'Medium', 55000, 15, botol30], ['30ml', 'Super', 75000, 18, botol30], ['30ml', 'Platinum', 85000, 21, botol30],
      ['50ml', 'Medium', 90000, 25, botol50], ['50ml', 'Platinum', 140000, 35, botol50],
    ];
    for (final v in varianAriana) {
      await db.insert('varian', {
        'produk_id': 1, 'nama': 'Ariana Grande Sweet Candy PREMIUM',
        'ukuran': v[0], 'kualitas': v[1], 'harga_jual': v[2], 'resep_bibit': v[3], 'resep_botol_id': v[4],
      });
    }

    // Varian: Aigner Blue (produk_id = 4)
    for (final v in [
      ['15ml', 'Medium', 30000, 8, botol15], ['15ml', 'Super', 35000, 9, botol15], ['15ml', 'Platinum', 45000, 11, botol15],
      ['30ml', 'Medium', 55000, 15, botol30], ['30ml', 'Platinum', 85000, 21, botol30],
      ['50ml', 'Medium', 90000, 25, botol50],
    ]) {
      await db.insert('varian', {
        'produk_id': 4, 'nama': 'Aigner Blue PREMIUM',
        'ukuran': v[0], 'kualitas': v[1], 'harga_jual': v[2], 'resep_bibit': v[3], 'resep_botol_id': v[4],
      });
    }

    // Varian: Baccarat, Dior Sauvage, Tom Ford
    for (final v in [
      [5, 'Baccarat Rouge PREMIUM', '30ml', 'Medium', 55000, 15, botol30],
      [5, 'Baccarat Rouge PREMIUM', '30ml', 'Platinum', 85000, 21, botol30],
      [6, 'Dior Sauvage PREMIUM', '30ml', 'Medium', 55000, 15, botol30],
      [6, 'Dior Sauvage PREMIUM', '30ml', 'Platinum', 85000, 21, botol30],
      [8, 'Tom Ford PREMIUM', '30ml', 'Medium', 75000, 15, botol30],
      [8, 'Tom Ford PREMIUM', '30ml', 'Platinum', 120000, 21, botol30],
    ]) {
      await db.insert('varian', {
        'produk_id': v[0], 'nama': v[1], 'ukuran': v[2], 'kualitas': v[3],
        'harga_jual': v[4], 'resep_bibit': v[5], 'resep_botol_id': v[6],
      });
    }

    // Pengeluaran awal
    await db.insert('pengeluaran', {'kategori': 'Gaji', 'keterangan': 'Gaji Kasir 1 - Maret', 'jumlah': 2000000, 'tanggal': '2026-03-25'});
    await db.insert('pengeluaran', {'kategori': 'Operasional', 'keterangan': 'Listrik Maret', 'jumlah': 350000, 'tanggal': '2026-03-15'});
    await db.insert('pengeluaran', {'kategori': 'Operasional', 'keterangan': 'Uang Sampah', 'jumlah': 50000, 'tanggal': '2026-03-01'});
    await db.insert('pengeluaran', {'kategori': 'Operasional', 'keterangan': 'Sabun & Tisu', 'jumlah': 55000, 'tanggal': '2026-03-05'});
  }

  // ==================== USERS ====================
  Future<List<Map<String, dynamic>>> getUsers() async {
    return await (await db).query('users', orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> loginByPin(String pin) async {
    final result = await (await db).query('users', where: 'pin = ?', whereArgs: [pin]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> insertUser(Map<String, dynamic> data) async {
    return await (await db).insert('users', data);
  }

  Future<void> deleteUser(int id) async {
    await (await db).delete('users', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== PRODUK ====================
  Future<List<Map<String, dynamic>>> getProduk({String? kategori, String? search}) async {
    final database = await db;
    String where = '1=1';
    List<dynamic> args = [];
    if (kategori != null && kategori != 'semua') {
      where += ' AND kategori = ?';
      args.add(kategori);
    }
    if (search != null && search.isNotEmpty) {
      where += ' AND nama LIKE ?';
      args.add('%$search%');
    }
    return await database.query('produk', where: where, whereArgs: args, orderBy: 'nama ASC');
  }

  Future<Map<String, dynamic>?> getProdukById(int id) async {
    final result = await (await db).query('produk', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<List<Map<String, dynamic>>> getLowStock() async {
    return await (await db).query('produk', where: 'stok <= min_stok', orderBy: 'stok ASC');
  }

  Future<int> insertProduk(Map<String, dynamic> data) async {
    data['created_at'] = DateTime.now().toIso8601String();
    return await (await db).insert('produk', data);
  }

  Future<void> updateProduk(int id, Map<String, dynamic> data) async {
    await (await db).update('produk', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteProduk(int id) async {
    final database = await db;
    await database.delete('varian', where: 'produk_id = ? OR resep_botol_id = ?', whereArgs: [id, id]);
    await database.delete('produk', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== VARIAN ====================
  Future<List<Map<String, dynamic>>> getVarian({int? produkId}) async {
    if (produkId != null) {
      return await (await db).query('varian', where: 'produk_id = ?', whereArgs: [produkId], orderBy: 'ukuran ASC, kualitas ASC');
    }
    return await (await db).query('varian', orderBy: 'nama ASC, ukuran ASC');
  }

  Future<Map<String, dynamic>?> getVarianById(int id) async {
    final result = await (await db).query('varian', where: 'id = ?', whereArgs: [id]);
    return result.isNotEmpty ? result.first : null;
  }

  Future<int> insertVarian(Map<String, dynamic> data) async {
    return await (await db).insert('varian', data);
  }

  Future<void> deleteVarian(int id) async {
    await (await db).delete('varian', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== TRANSAKSI + BOM ====================
  Future<double> hitungHPP(int varianId, int qty) async {
    final v = await getVarianById(varianId);
    if (v == null) return 0;
    final bibit = await getProdukById(v['produk_id'] as int);
    final botol = v['resep_botol_id'] != null ? await getProdukById(v['resep_botol_id'] as int) : null;
    final hppBibit = (bibit?['harga_beli'] ?? 0) as num;
    final resepBibit = (v['resep_bibit'] ?? 0) as num;
    final hppBotol = (botol?['harga_beli'] ?? 0) as num;
    return ((hppBibit * resepBibit + hppBotol) * qty).toDouble();
  }

  Future<int> prosesTransaksi({
    required String noNota,
    required String userNama,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double diskon,
    required double total,
    required double bayar,
    required double kembalian,
    required String metode,
  }) async {
    final database = await db;
    return await database.transaction((txn) async {
      double totalHPP = 0;

      // Insert transaksi
      final trxId = await txn.insert('transaksi', {
        'no_nota': noNota,
        'tanggal': DateTime.now().toIso8601String(),
        'user_nama': userNama,
        'subtotal': subtotal,
        'diskon': diskon,
        'total': total,
        'bayar': bayar,
        'kembalian': kembalian,
        'metode': metode,
        'hpp_total': 0,
      });

      for (final item in items) {
        final varianId = item['varian_id'] as int;
        final qty = item['qty'] as int;
        final hargaJual = (item['harga_jual'] as num).toDouble();

        // Ambil data varian
        final varianList = await txn.query('varian', where: 'id = ?', whereArgs: [varianId]);
        if (varianList.isEmpty) continue;
        final v = varianList.first;

        // Hitung HPP
        final bibitList = await txn.query('produk', where: 'id = ?', whereArgs: [v['produk_id']]);
        final bibit = bibitList.isNotEmpty ? bibitList.first : null;
        final botolList = v['resep_botol_id'] != null
            ? await txn.query('produk', where: 'id = ?', whereArgs: [v['resep_botol_id']])
            : <Map<String, dynamic>>[];
        final botol = botolList.isNotEmpty ? botolList.first : null;

        final hppBibit = ((bibit?['harga_beli'] ?? 0) as num).toDouble();
        final resepBibit = ((v['resep_bibit'] ?? 0) as num).toDouble();
        final hppBotol = ((botol?['harga_beli'] ?? 0) as num).toDouble();
        final hppPerItem = hppBibit * resepBibit + hppBotol;
        totalHPP += hppPerItem * qty;

        // Insert detail
        await txn.insert('detail_transaksi', {
          'transaksi_id': trxId,
          'varian_id': varianId,
          'nama_item': '${v['nama']} ${v['ukuran']} ${v['kualitas']}',
          'qty': qty,
          'harga_jual': hargaJual,
          'hpp_per_item': hppPerItem,
        });

        // Potong stok bibit (BOM auto-deduct)
        if (bibit != null) {
          final stokLama = ((bibit['stok'] ?? 0) as num).toDouble();
          final potong = resepBibit * qty;
          final stokBaru = stokLama - potong;
          await txn.update('produk', {'stok': stokBaru}, where: 'id = ?', whereArgs: [v['produk_id']]);

          await txn.insert('stok_movement', {
            'produk_id': v['produk_id'],
            'tipe': 'penjualan',
            'qty': -potong,
            'stok_sebelum': stokLama,
            'stok_sesudah': stokBaru,
            'keterangan': 'Jual ${v['nama']} ${v['ukuran']} ${v['kualitas']} x$qty',
            'tanggal': DateTime.now().toIso8601String().substring(0, 10),
            'user_nama': userNama,
          });
        }

        // Potong stok botol + catat movement (sama seperti bibit)
        if (botol != null) {
          final stokLama = ((botol['stok'] ?? 0) as num).toDouble();
          final stokBaru = stokLama - qty;
          await txn.update('produk', {'stok': stokBaru}, where: 'id = ?', whereArgs: [v['resep_botol_id']]);
          await txn.insert('stok_movement', {
            'produk_id': v['resep_botol_id'],
            'tipe': 'penjualan',
            'qty': -qty.toDouble(),
            'stok_sebelum': stokLama,
            'stok_sesudah': stokBaru,
            'keterangan': 'Botol untuk ${v['nama']} ${v['ukuran']} x$qty',
            'tanggal': DateTime.now().toIso8601String().substring(0, 10),
            'user_nama': userNama,
          });
        }
      }

      // Update HPP total
      await txn.update('transaksi', {'hpp_total': totalHPP}, where: 'id = ?', whereArgs: [trxId]);
      return trxId;
    });
  }

  // ==================== QUERY TRANSAKSI ====================
  Future<List<Map<String, dynamic>>> getTransaksi({String? tanggalMulai, String? tanggalAkhir, int limit = 500}) async {
    final database = await db;
    if (tanggalMulai != null && tanggalAkhir != null) {
      return await database.query('transaksi',
          where: "tanggal >= ? AND tanggal <= ?",
          whereArgs: ['$tanggalMulai 00:00:00', '$tanggalAkhir 23:59:59'],
          orderBy: 'tanggal DESC', limit: limit);
    }
    return await database.query('transaksi', orderBy: 'tanggal DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getDetailTransaksi(int trxId) async {
    return await (await db).query('detail_transaksi', where: 'transaksi_id = ?', whereArgs: [trxId]);
  }

  // ==================== STOK MOVEMENT ====================
  Future<List<Map<String, dynamic>>> getStokMovement({String? tipe, int limit = 500}) async {
    final database = await db;
    if (tipe != null && tipe != 'semua') {
      return await database.query('stok_movement', where: 'tipe = ?', whereArgs: [tipe], orderBy: 'id DESC', limit: limit);
    }
    return await database.query('stok_movement', orderBy: 'id DESC', limit: limit);
  }

  Future<Map<String, double>> getPergerakanProduk(int produkId) async {
    final database = await db;
    final masuk = await database.rawQuery("SELECT COALESCE(SUM(ABS(qty)),0) as total FROM stok_movement WHERE produk_id = ? AND tipe = 'masuk'", [produkId]);
    final jual = await database.rawQuery("SELECT COALESCE(SUM(ABS(qty)),0) as total FROM stok_movement WHERE produk_id = ? AND tipe = 'penjualan'", [produkId]);
    final keluar = await database.rawQuery("SELECT COALESCE(SUM(ABS(qty)),0) as total FROM stok_movement WHERE produk_id = ? AND tipe = 'keluar'", [produkId]);
    final ret = await database.rawQuery("SELECT COALESCE(SUM(ABS(qty)),0) as total FROM stok_movement WHERE produk_id = ? AND tipe = 'return'", [produkId]);
    return {
      'masuk': ((masuk.first['total'] ?? 0) as num).toDouble(),
      'penjualan': ((jual.first['total'] ?? 0) as num).toDouble(),
      'keluar': ((keluar.first['total'] ?? 0) as num).toDouble(),
      'return': ((ret.first['total'] ?? 0) as num).toDouble(),
    };
  }

  // ==================== STOK MASUK ====================
  Future<void> tambahStokMasuk(int produkId, double qty, String userNama) async {
    final database = await db;
    final produk = await getProdukById(produkId);
    if (produk == null) return;
    final stokLama = ((produk['stok'] ?? 0) as num).toDouble();
    final stokBaru = stokLama + qty;

    await database.update('produk', {'stok': stokBaru}, where: 'id = ?', whereArgs: [produkId]);
    await database.insert('stok_masuk', {
      'produk_id': produkId,
      'nama_produk': produk['nama'],
      'qty': qty,
      'tanggal': DateTime.now().toIso8601String().substring(0, 10),
      'user_nama': userNama,
    });
    await database.insert('stok_movement', {
      'produk_id': produkId,
      'tipe': 'masuk',
      'qty': qty,
      'stok_sebelum': stokLama,
      'stok_sesudah': stokBaru,
      'keterangan': 'Stok masuk: ${produk['nama']}',
      'tanggal': DateTime.now().toIso8601String().substring(0, 10),
      'user_nama': userNama,
    });
  }

  Future<List<Map<String, dynamic>>> getStokMasuk() async {
    return await (await db).query('stok_masuk', orderBy: 'id DESC');
  }

  // ==================== PENGELUARAN ====================
  Future<List<Map<String, dynamic>>> getPengeluaran({String? tanggalMulai, String? tanggalAkhir}) async {
    final database = await db;
    if (tanggalMulai != null && tanggalAkhir != null) {
      return await database.query('pengeluaran',
          where: 'tanggal >= ? AND tanggal <= ?', whereArgs: [tanggalMulai, tanggalAkhir], orderBy: 'tanggal DESC');
    }
    return await database.query('pengeluaran', orderBy: 'tanggal DESC');
  }

  Future<int> insertPengeluaran(Map<String, dynamic> data) async {
    return await (await db).insert('pengeluaran', data);
  }

  Future<void> deletePengeluaran(int id) async {
    await (await db).delete('pengeluaran', where: 'id = ?', whereArgs: [id]);
  }

  // ==================== LAPORAN ====================
  Future<Map<String, double>> getLaporanKeuangan(String tanggalMulai, String tanggalAkhir) async {
    final database = await db;
    final pendResult = await database.rawQuery(
        "SELECT COALESCE(SUM(total),0) as total, COALESCE(SUM(hpp_total),0) as hpp FROM transaksi WHERE tanggal >= ? AND tanggal <= ?",
        ['$tanggalMulai 00:00:00', '$tanggalAkhir 23:59:59']);
    final pendapatan = ((pendResult.first['total'] ?? 0) as num).toDouble();
    final hpp = ((pendResult.first['hpp'] ?? 0) as num).toDouble();
    final pengResult = await database.rawQuery(
        "SELECT COALESCE(SUM(jumlah),0) as total FROM pengeluaran WHERE tanggal >= ? AND tanggal <= ?",
        [tanggalMulai, tanggalAkhir]);
    final pengeluaran = ((pengResult.first['total'] ?? 0) as num).toDouble();
    return {
      'pendapatan': pendapatan, 'hpp': hpp, 'laba_kotor': pendapatan - hpp,
      'pengeluaran': pengeluaran, 'laba_bersih': pendapatan - hpp - pengeluaran,
    };
  }

  Future<Map<String, double>> getPembayaranSummary(String tanggalMulai, String tanggalAkhir) async {
    final result = await (await db).rawQuery(
        "SELECT metode, COALESCE(SUM(total),0) as total FROM transaksi WHERE tanggal >= ? AND tanggal <= ? GROUP BY metode",
        ['$tanggalMulai 00:00:00', '$tanggalAkhir 23:59:59']);
    final map = <String, double>{};
    for (final row in result) {
      map[row['metode'] as String] = ((row['total'] ?? 0) as num).toDouble();
    }
    return map;
  }

  Future<List<Map<String, dynamic>>> getTopProduk({int limit = 10, String? tanggalMulai, String? tanggalAkhir}) async {
    final database = await db;
    String dateFilter = '';
    List<dynamic> args = [];
    if (tanggalMulai != null && tanggalAkhir != null) {
      dateFilter = "AND t.tanggal >= ? AND t.tanggal <= ?";
      args = ['$tanggalMulai 00:00:00', '$tanggalAkhir 23:59:59'];
    }
    return await database.rawQuery('''
      SELECT dt.nama_item, SUM(dt.qty) as terjual, SUM(dt.harga_jual * dt.qty) as revenue,
             SUM(dt.hpp_per_item * dt.qty) as hpp, SUM((dt.harga_jual - dt.hpp_per_item) * dt.qty) as laba
      FROM detail_transaksi dt
      JOIN transaksi t ON dt.transaksi_id = t.id
      WHERE 1=1 $dateFilter
      GROUP BY dt.nama_item ORDER BY terjual DESC LIMIT ?
    ''', [...args, limit]);
  }

  // ==================== PENGATURAN ====================
  Future<String?> getSetting(String key) async {
    final result = await (await db).query('pengaturan', where: 'key = ?', whereArgs: [key]);
    return result.isNotEmpty ? result.first['value'] as String : null;
  }

  Future<void> setSetting(String key, String value) async {
    final database = await db;
    await database.insert('pengaturan', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== EXPORT ====================
  Future<Map<String, dynamic>> exportAllData() async {
    final database = await db;
    return {
      'exported_at': DateTime.now().toIso8601String(),
      'version': 3,
      'app': 'KS Parfume ERP v3',
      'produk': await database.query('produk'),
      'varian': await database.query('varian'),
      'transaksi': await database.query('transaksi'),
      'detail_transaksi': await database.query('detail_transaksi'),
      'pengeluaran': await database.query('pengeluaran'),
      'stok_masuk': await database.query('stok_masuk'),
      'stok_movement': await database.query('stok_movement'),
      'users': await database.query('users'),
    };
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class Api {
  static SupabaseClient get client => Supabase.instance.client;

  /// Resep botol dari varian: null jika kosong (hindari '' yang membuat RPC/UI salah).
  static String? normBotolId(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    return s.isEmpty ? null : s;
  }

  // ══════ PIN HASH ══════
  static String hashPin(String pin) {
    return sha256.convert(utf8.encode('ksparfume_salt_$pin')).toString();
  }

  // ══════ TOKO ══════
  static Future<Map<String, dynamic>?> getToko() async {
    final r = await client.from('toko').select().limit(1).maybeSingle();
    return r;
  }

  static Future<List<Map<String, dynamic>>> getAllToko() async {
    return await client.from('toko').select().order('nama');
  }

  static Future<void> updateTokoNama(String tokoId, String nama, {String? alamat}) async {
    final data = <String, dynamic>{'nama': nama};
    if (alamat != null) data['alamat'] = alamat;
    await client.from('toko').update(data).eq('id', tokoId);
  }

  // Laporan per cabang (ringkasan)
  static Future<Map<String, dynamic>> getLaporanCabang(String tokoId, String mulai, String akhir) async {
    final trx = await getTransaksi(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir, limit: 5000);
    final peng = await getPengeluaran(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir);
    final pendapatan = trx.fold(0.0, (double s, t) => s + ((t['total'] ?? 0) as num).toDouble());
    final pengeluaran = peng.fold(0.0, (double s, p) => s + ((p['jumlah'] ?? 0) as num).toDouble());
    return {
      'pendapatan': pendapatan,
      'pengeluaran': pengeluaran,
      'laba': pendapatan - pengeluaran,
      'transaksi': trx.length,
    };
  }

  // ══════ BATCH HPP (hindari N+1 query) ══════
  static Future<double> getHppTotal(String tokoId, String mulai, String akhir) async {
    try {
      final trx = await getTransaksi(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir, limit: 5000);
      if (trx.isEmpty) return 0;
      final trxIds = trx.map((t) => t['id'] as String).toList();
      // Batch fetch all items at once
      double totalHpp = 0;
      for (int i = 0; i < trxIds.length; i += 50) {
        final batch = trxIds.sublist(i, i + 50 > trxIds.length ? trxIds.length : i + 50);
        final items = await client.from('transaksi_item').select().inFilter('transaksi_id', batch);
        for (final item in items) {
          totalHpp += ((item['hpp'] ?? 0) as num).toDouble(); // hpp per-unit, tidak perlu x qty
        }
      }
      return totalHpp;
    } catch (_) { return 0; }
  }

  // ══════ AI INSIGHT ══════
  static Future<Map<String, dynamic>> getAIInsights(String tokoId) async {
    try {
      final now = DateTime.now();
      final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final yesterday = '${now.subtract(const Duration(days: 1)).year}-${now.subtract(const Duration(days: 1)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 1)).day.toString().padLeft(2, '0')}';
      final weekAgo = '${now.subtract(const Duration(days: 7)).year}-${now.subtract(const Duration(days: 7)).month.toString().padLeft(2, '0')}-${now.subtract(const Duration(days: 7)).day.toString().padLeft(2, '0')}';

      // Phase 1: semua query jalan serentak
      final res = await Future.wait<List<Map<String, dynamic>>>([
        getTransaksi(tokoId, tanggalMulai: today, tanggalAkhir: today, limit: 1000),
        getTransaksi(tokoId, tanggalMulai: yesterday, tanggalAkhir: yesterday, limit: 1000),
        getTransaksi(tokoId, tanggalMulai: weekAgo, tanggalAkhir: today, limit: 500),
        getProduk(tokoId),
        getStokMovement(tokoId, tipe: 'penjualan', limit: 500),
      ]);
      final trxToday     = res[0]; final trxYesterday = res[1];
      final trxWeek      = res[2]; final produk       = res[3]; final movements = res[4];
      // Filter lowStok dari produk yang sudah diambil — tanpa request tambahan
      final lowStok      = produk.where((p) => ((p['stok'] ?? 0) as num) <= ((p['min_stok'] ?? 0) as num)).toList();
      final todayTotal     = trxToday.fold(0.0, (double s, t) => s + ((t['total'] ?? 0) as num).toDouble());
      final yesterdayTotal = trxYesterday.fold(0.0, (double s, t) => s + ((t['total'] ?? 0) as num).toDouble());
      final growthPct = yesterdayTotal > 0 ? ((todayTotal - yesterdayTotal) / yesterdayTotal * 100) : 0.0;

      // Phase 2: 1 batch query gantikan N+1 (dulu 50 request, sekarang 1)
      String topProduk = '-';
      if (trxWeek.isNotEmpty) {
        final ids = trxWeek.take(50).map((t) => t['id'] as String).toList();
        final allItems = await client.from('transaksi_item').select().inFilter('transaksi_id', ids);
        final itemCount = <String, int>{};
        for (final item in allItems) {
          final nama = (item['nama_item'] ?? '-').toString().split(' ').take(3).join(' ');
          itemCount[nama] = (itemCount[nama] ?? 0) + ((item['qty'] ?? 1) as num).toInt();
        }
        if (itemCount.isNotEmpty) {
          topProduk = itemCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        }
      }

      // Prediksi habis — pakai produk & movements yang sudah diambil di Phase 1
      final stokPrediksi = <String, int>{};
      for (final p in produk) {
        final sales = movements.where((m) => m['produk_id'] == p['id']).toList();
        if (sales.isEmpty) continue;
        double totalSold = sales.fold(0.0, (double s, m) => s + ((m['qty'] ?? 0) as num).abs().toDouble());
        final days = sales.isNotEmpty ? (now.difference(DateTime.tryParse(sales.last['created_at']?.toString() ?? '') ?? now).inDays).clamp(1, 30) : 1;
        final avgPerDay = totalSold / days;
        if (avgPerDay > 0) {
          final stokNow = ((p['stok'] ?? 0) as num).toDouble();
          final hariSampaiHabis = (stokNow / avgPerDay).round();
          if (hariSampaiHabis <= 7 && hariSampaiHabis > 0) {
            final nama = (p['nama'] ?? '').toString().split(' ').take(3).join(' ');
            stokPrediksi[nama] = hariSampaiHabis;
          }
        }
      }

      return {
        'todayTotal': todayTotal,
        'yesterdayTotal': yesterdayTotal,
        'growthPct': growthPct,
        'todayTrxCount': trxToday.length,
        'topProduk': topProduk,
        'lowStokCount': lowStok.length,
        'stokPrediksi': stokPrediksi,
      };
    } catch (e) {
      return {'todayTotal': 0.0, 'yesterdayTotal': 0.0, 'growthPct': 0.0, 'todayTrxCount': 0, 'topProduk': '-', 'lowStokCount': 0, 'stokPrediksi': <String, int>{}};
    }
  }

  // ══════ USERS ══════
  static Future<List<Map<String, dynamic>>> getUsers(String tokoId) async {
    return await client.from('users').select().eq('toko_id', tokoId).eq('aktif', true).order('nama');
  }

  static Future<Map<String, dynamic>?> loginPin(String tokoId, String pin) async {
    // Brute force protection — client-side lockout
    final prefs = await SharedPreferences.getInstance();
    final lockKey = 'lockout_$tokoId';
    final lockUntil = prefs.getInt(lockKey) ?? 0;
    if (lockUntil > DateTime.now().millisecondsSinceEpoch) {
      final secondsLeft = ((lockUntil - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
      throw 'Terkunci! Coba lagi dalam $secondsLeft detik';
    }

    // Try hash first, fallback to plaintext (for migration)
    final hashedPin = hashPin(pin);
    Map<String, dynamic>? user;
    try {
      user = await client.from('users').select()
        .eq('toko_id', tokoId).eq('pin_hash', hashedPin).eq('aktif', true).maybeSingle();
    } catch (_) {}

    // Fallback to plaintext (legacy users)
    if (user == null) {
      try {
        user = await client.from('users').select()
          .eq('toko_id', tokoId).eq('pin', pin).eq('aktif', true).maybeSingle();
        // Auto-upgrade to hash on successful plaintext login
        if (user != null) {
          try {
            await client.from('users').update({'pin_hash': hashedPin}).eq('id', user['id']);
          } catch (_) {}
        }
      } catch (_) {}
    }

    if (user == null) {
      // Track failed attempts
      final failKey = 'fail_count_$tokoId';
      final fails = (prefs.getInt(failKey) ?? 0) + 1;
      await prefs.setInt(failKey, fails);
      if (fails >= 5) {
        // Lockout 60 seconds
        await prefs.setInt(lockKey, DateTime.now().millisecondsSinceEpoch + 60000);
        await prefs.setInt(failKey, 0);
        throw 'PIN salah 5x. Terkunci 60 detik!';
      }
      return null;
    }

    // Reset fail count on success
    await prefs.setInt('fail_count_$tokoId', 0);
    return user;
  }

  static Future<void> addUser(String tokoId, String nama, String pin, String peran) async {
    await client.from('users').insert({
      'toko_id': tokoId, 'nama': nama,
      'pin': pin, // legacy
      'pin_hash': hashPin(pin),
      'peran': peran,
    });
  }

  static Future<void> deleteUser(String id) async {
    await client.from('users').delete().eq('id', id);
  }

  // ══════ PRODUK ══════
  static Future<List<Map<String, dynamic>>> getProduk(String tokoId, {String? kategori}) async {
    var q = client.from('produk').select().eq('toko_id', tokoId).eq('aktif', true).order('nama');
    if (kategori != null && kategori != 'semua') q = client.from('produk').select().eq('toko_id', tokoId).eq('aktif', true).eq('kategori', kategori).order('nama');
    return await q;
  }

  static Future<Map<String, dynamic>?> getProdukById(String id) async {
    return await client.from('produk').select().eq('id', id).maybeSingle();
  }

  static Future<List<Map<String, dynamic>>> getLowStock(String tokoId) async {
    final all = await client.from('produk').select().eq('toko_id', tokoId).eq('aktif', true).order('stok');
    return all.where((p) => (p['stok'] as num) <= (p['min_stok'] as num)).toList();
  }

  static Future<void> addProduk(Map<String, dynamic> data) async {
    await client.from('produk').insert(data);
  }

  static Future<void> updateProduk(String id, Map<String, dynamic> data) async {
    await client.from('produk').update(data).eq('id', id);
  }

  static Future<void> deleteProduk(String id) async {
    await client.from('produk').update({'aktif': false}).eq('id', id);
  }

  // ══════ VARIAN ══════
  static Future<List<Map<String, dynamic>>> getVarian(String tokoId) async {
    final produkIds = (await client.from('produk').select('id').eq('toko_id', tokoId).eq('aktif', true))
        .map((p) => p['id'] as String).toList();
    if (produkIds.isEmpty) return [];
    // Chunk 20 produk_id per request — Supabase free tier max 1000 rows/request,
    // 20 produk × maks 27 varian = 540, aman di bawah limit
    final chunks = <List<String>>[];
    for (int i = 0; i < produkIds.length; i += 20) {
      chunks.add(produkIds.sublist(i, (i + 20).clamp(0, produkIds.length)));
    }
    final chunkResults = await Future.wait(
      chunks.map((c) => client.from('varian').select().inFilter('produk_id', c).eq('aktif', true))
    );
    final result = chunkResults.expand((r) => r.cast<Map<String, dynamic>>()).toList();
    result.sort((a, b) => (a['nama'] ?? '').toString().compareTo((b['nama'] ?? '').toString()));
    return result;
  }

  static Future<int> getVarianCountByIds(List<String> produkIds) async {
    if (produkIds.isEmpty) return 0;
    final chunks = <List<String>>[];
    for (int i = 0; i < produkIds.length; i += 20) {
      chunks.add(produkIds.sublist(i, (i + 20).clamp(0, produkIds.length)));
    }
    final results = await Future.wait(
      chunks.map((c) => client.from('varian').select('id').inFilter('produk_id', c).eq('aktif', true))
    );
    return results.fold<int>(0, (s, r) => s + r.length);
  }

  static Future<List<Map<String, dynamic>>> getVarianByProduk(String produkId) async {
    return await client.from('varian').select().eq('produk_id', produkId).eq('aktif', true).order('ukuran');
  }

  static Future<void> addVarian(Map<String, dynamic> data) async {
    // Auto-apply template resep jika resep_bibit belum diisi
    if (data['resep_bibit'] == null || data['resep_bibit'] == 0) {
      final ukuran = (data['ukuran'] ?? '').toString();
      final kualitas = (data['kualitas'] ?? '').toString();
      final tpl = await getResepTemplateBy(ukuran, kualitas);
      if (tpl != null) {
        data['resep_bibit'] = tpl['qty_bibit'];
      }
    }
    await client.from('varian').insert(data);
  }

  static Future<void> deleteVarian(String id) async {
    await client.from('varian').update({'aktif': false}).eq('id', id);
  }

  // ══════ TRANSAKSI + BOM AUTO-DEDUCT ══════
  static Future<String> prosesTransaksi({
    required String tokoId,
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> items, // [{varian, qty}]
    required double subtotal,
    required double diskon,
    required double total,
    required double bayar,
    required double kembalian,
    required String metode,
    String? pelangganNama,
    String? pelangganId,
    double diskonMemberDipakai = 0,
    List<Map<String, dynamic>>? produkList,
  }) async {
    // Build items payload untuk RPC
    final itemsPayload = items.map((item) {
      final v = item['varian'] as Map<String, dynamic>;
      final qty = item['qty'] as int;
      final hargaJual = (v['harga_jual'] as num).toDouble();
      final resepBibit = (v['resep_bibit'] as num?)?.toDouble() ?? 0;
      final produkId = v['produk_id'];
      String? botolId = normBotolId(v['resep_botol_id']);
      // Auto-lookup botol by ukuran when resep_botol_id is missing
      if (botolId == null && resepBibit > 0 && produkList != null) {
        final ukuran = (v['ukuran'] ?? '').toString().toUpperCase();
        if (ukuran.isNotEmpty) {
          final matchBotol = produkList.firstWhere(
            (p) => (p['nama'] ?? '').toString().toUpperCase().contains('BOTOL') &&
                   (p['nama'] ?? '').toString().toUpperCase().contains(ukuran),
            orElse: () => {});
          if (matchBotol.isNotEmpty) botolId = matchBotol['id'].toString();
        }
      }
      double hppBibit = 0, hppBotol = 0;
      if (produkList != null) {
        final bibit = produkList.firstWhere((p) => p['id'] == produkId, orElse: () => {});
        if (bibit.isNotEmpty) hppBibit = ((bibit['harga_beli'] ?? 0) as num).toDouble();
        if (botolId != null) {
          final botol = produkList.firstWhere((p) => p['id'] == botolId, orElse: () => {});
          if (botol.isNotEmpty) hppBotol = ((botol['harga_beli'] ?? 0) as num).toDouble();
        }
      }
      final hppPerItem = hppBibit * resepBibit + hppBotol;

      return {
        'varian_id': v['id'],
        'produk_id': produkId,
        'botol_id': botolId ?? '',
        'nama_item': '${v['nama']} ${v['ukuran']} ${v['kualitas']}',
        'qty': qty,
        'harga_satuan': hargaJual,
        'resep_bibit': resepBibit,
        'hpp': hppPerItem,
      };
    }).toList();

    try {
      // Call atomic RPC (anti race condition + anti duplikat nota)
      final params = <String, dynamic>{
        'p_toko_id': tokoId,
        'p_user_id': user['id'],
        'p_user_nama': user['nama'],
        'p_pelanggan': pelangganNama ?? 'Walk-in',
        'p_subtotal': subtotal,
        'p_diskon': diskon,
        'p_total': total,
        'p_bayar': bayar,
        'p_kembalian': kembalian,
        'p_metode': metode,
        'p_items': itemsPayload,
      };
      if (pelangganId != null) params['p_pelanggan_id'] = pelangganId;
      if (diskonMemberDipakai > 0) params['p_diskon_member_dipakai'] = diskonMemberDipakai;
      final result = await client.rpc('proses_transaksi_atomic', params: params);
      return result?.toString() ?? 'INV${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      // Fallback ke legacy flow jika RPC belum di-install
      return _prosesTransaksiLegacy(tokoId: tokoId, user: user, items: items,
        subtotal: subtotal, diskon: diskon, total: total, bayar: bayar,
        kembalian: kembalian, metode: metode, pelangganNama: pelangganNama,
        pelangganId: pelangganId, diskonMemberDipakai: diskonMemberDipakai,
        produkList: produkList);
    }
  }

  // Legacy flow (fallback jika RPC belum ada di Supabase)
  static Future<String> _prosesTransaksiLegacy({
    required String tokoId,
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> items,
    required double subtotal,
    required double diskon,
    required double total,
    required double bayar,
    required double kembalian,
    required String metode,
    String? pelangganNama,
    String? pelangganId,
    double diskonMemberDipakai = 0,
    List<Map<String, dynamic>>? produkList,
  }) async {
    final now = DateTime.now();
    final dateStr = '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seq = now.millisecondsSinceEpoch % 99999;
    final noNota = 'INV$dateStr${seq.toString().padLeft(5, '0')}';

    final trxPayload = <String, dynamic>{
      'toko_id': tokoId, 'no_nota': noNota,
      'user_id': user['id'], 'user_nama': user['nama'],
      'pelanggan_nama': pelangganNama ?? 'Walk-in',
      'subtotal': subtotal, 'diskon': diskon, 'total': total,
      'bayar': bayar, 'kembalian': kembalian, 'metode': metode, 'status': 'selesai',
    };
    if (pelangganId != null) trxPayload['pelanggan_id'] = pelangganId;
    final trxResult = await client.from('transaksi').insert(trxPayload).select().single();
    final trxId = trxResult['id'];

    // Update stats pelanggan
    if (pelangganId != null) {
      try {
        final p = await client.from('pelanggan').select('total_belanja,diskon_dipakai,jumlah_transaksi')
          .eq('id', pelangganId).maybeSingle();
        if (p != null) {
          await client.from('pelanggan').update({
            'total_belanja': ((p['total_belanja'] ?? 0) as num).toDouble() + total,
            'diskon_dipakai': ((p['diskon_dipakai'] ?? 0) as num).toDouble() + diskonMemberDipakai,
            'jumlah_transaksi': ((p['jumlah_transaksi'] ?? 0) as num).toInt() + 1,
          }).eq('id', pelangganId);
        }
      } catch (_) {}
    }

    for (final item in items) {
      final v = item['varian'] as Map<String, dynamic>;
      final qty = item['qty'] as int;
      final hargaJual = (v['harga_jual'] as num).toDouble();
      final resepBibit = (v['resep_bibit'] as num?)?.toDouble() ?? 0;
      final produkId = v['produk_id'] as String;
      String? botolId = normBotolId(v['resep_botol_id']);
      // Auto-lookup botol by ukuran when resep_botol_id is missing
      if (botolId == null && resepBibit > 0 && produkList != null) {
        final ukuran = (v['ukuran'] ?? '').toString().toUpperCase();
        if (ukuran.isNotEmpty) {
          final matchBotol = produkList.firstWhere(
            (p) => (p['nama'] ?? '').toString().toUpperCase().contains('BOTOL') &&
                   (p['nama'] ?? '').toString().toUpperCase().contains(ukuran),
            orElse: () => {});
          if (matchBotol.isNotEmpty) botolId = matchBotol['id'].toString();
        }
      }
      double hppBibit = 0, hppBotol = 0;
      if (produkList != null) {
        final bibit = produkList.firstWhere((p) => p['id'] == produkId, orElse: () => {});
        if (bibit.isNotEmpty) hppBibit = ((bibit['harga_beli'] ?? 0) as num).toDouble();
        if (botolId != null) {
          final botol = produkList.firstWhere((p) => p['id'] == botolId, orElse: () => {});
          if (botol.isNotEmpty) hppBotol = ((botol['harga_beli'] ?? 0) as num).toDouble();
        }
      }
      final hppPerItem = hppBibit * resepBibit + hppBotol;

      await client.from('transaksi_item').insert({
        'transaksi_id': trxId, 'varian_id': v['id'], 'produk_id': produkId, 'botol_id': botolId,
        'nama_item': '${v['nama']} ${v['ukuran']} ${v['kualitas']}',
        'qty': qty, 'harga_satuan': hargaJual, 'subtotal': hargaJual * qty,
        'resep_bibit': resepBibit, 'hpp': hppPerItem,
      });

      final bibitData = await getProdukById(produkId);
      if (bibitData != null) {
        final stokLama = (bibitData['stok'] as num).toDouble();
        final potong = resepBibit * qty;
        await client.from('stok_movement').insert({
          'toko_id': tokoId, 'produk_id': produkId, 'tipe': 'penjualan',
          'qty': -potong, 'stok_sebelum': stokLama, 'stok_sesudah': stokLama - potong,
          'keterangan': 'Jual ${v['nama']} ${v['ukuran']} ${v['kualitas']} x$qty',
          'user_id': user['id'],
        });
        // Update stok bibit langsung di produk
        await client.from('produk').update({'stok': stokLama - potong}).eq('id', produkId);
      }
      if (botolId != null) {
        final botolData = await getProdukById(botolId);
        if (botolData != null) {
          final stokLama = (botolData['stok'] as num).toDouble();
          await client.from('stok_movement').insert({
            'toko_id': tokoId, 'produk_id': botolId, 'tipe': 'penjualan',
            'qty': -qty.toDouble(), 'stok_sebelum': stokLama, 'stok_sesudah': stokLama - qty,
            'keterangan': 'Botol untuk ${v['nama']} ${v['ukuran']} x$qty',
            'user_id': user['id'],
          });
          // Update stok botol langsung di produk
          await client.from('produk').update({'stok': stokLama - qty}).eq('id', botolId);
        }
      }
    }
    return noNota;
  }

  // ══════ TRANSAKSI QUERY ══════
  static Future<List<Map<String, dynamic>>> getTransaksi(String tokoId, {int limit = 100, String? tanggalMulai, String? tanggalAkhir}) async {
    var q = client.from('transaksi').select().eq('toko_id', tokoId).eq('status', 'selesai').order('created_at', ascending: false).limit(limit);
    if (tanggalMulai != null) q = client.from('transaksi').select().eq('toko_id', tokoId).eq('status', 'selesai').gte('created_at', '${tanggalMulai}T00:00:00').lte('created_at', '${tanggalAkhir ?? DateTime.now().toIso8601String().substring(0, 10)}T23:59:59').order('created_at', ascending: false).limit(limit);
    final trx = await q;
    // Exclude transaksi yang sudah dibatalkan (ada di tabel pembatalan)
    try {
      final batal = await client.from('pembatalan').select('transaksi_id').eq('toko_id', tokoId);
      final batalIds = batal.map((p) => (p['transaksi_id'] ?? '').toString()).toSet();
      if (batalIds.isEmpty) return trx;
      return trx.where((t) => !batalIds.contains((t['id'] ?? '').toString())).toList();
    } catch (_) { return trx; }
  }

  // Semua transaksi + tandai yang dibatalkan (ada di tabel pembatalan)
  static Future<List<Map<String, dynamic>>> getTransaksiAll(String tokoId, {int limit = 100, String? tanggalMulai, String? tanggalAkhir}) async {
    var q = client.from('transaksi').select().eq('toko_id', tokoId).order('created_at', ascending: false).limit(limit);
    if (tanggalMulai != null) q = client.from('transaksi').select().eq('toko_id', tokoId).gte('created_at', '${tanggalMulai}T00:00:00').lte('created_at', '${tanggalAkhir ?? DateTime.now().toIso8601String().substring(0, 10)}T23:59:59').order('created_at', ascending: false).limit(limit);
    final trx = await q;
    try {
      final batal = await client.from('pembatalan').select('transaksi_id').eq('toko_id', tokoId);
      final batalIds = batal.map((p) => (p['transaksi_id'] ?? '').toString()).toSet();
      if (batalIds.isEmpty) return trx;
      return trx.map((t) {
        if (batalIds.contains((t['id'] ?? '').toString())) {
          return <String, dynamic>{...t, 'status': 'dibatalkan'};
        }
        return t;
      }).toList();
    } catch (_) { return trx; }
  }

  static Future<List<Map<String, dynamic>>> getTransaksiItems(String trxId) async {
    return await client.from('transaksi_item').select().eq('transaksi_id', trxId);
  }

  // Batch fetch items untuk banyak transaksi sekaligus (hindari N+1 di laporan)
  static Future<List<Map<String, dynamic>>> getTransaksiItemsBatch(List<String> trxIds) async {
    if (trxIds.isEmpty) return [];
    return await client.from('transaksi_item').select().inFilter('transaksi_id', trxIds);
  }

  // ══════ PEMBATALAN TRANSAKSI ══════
  static Future<void> batalkanTransaksi({
    required String tokoId,
    required String transaksiId,
    required Map<String, dynamic> user,
  }) async {
    final items = await client.from('transaksi_item').select().eq('transaksi_id', transaksiId);

    for (final item in items) {
      final produkId = item['produk_id']?.toString();
      final varianId = item['varian_id'];
      final botolId = item['botol_id']?.toString();
      final qty = (item['qty'] as num).toInt();
      final resepBibit = (item['resep_bibit'] as num?)?.toDouble() ?? 0;

      if (varianId != null) {
        // Parfum: kembalikan stok bibit (qty × resepBibit ml) + botol (qty pcs)
        if (produkId != null && resepBibit > 0) {
          final bibit = await getProdukById(produkId);
          if (bibit != null) {
            final stokLama = (bibit['stok'] as num).toDouble();
            await client.from('produk').update({'stok': stokLama + resepBibit * qty}).eq('id', produkId);
          }
        }
        if (botolId != null && botolId.isNotEmpty) {
          final botol = await getProdukById(botolId);
          if (botol != null) {
            final botolStok = (botol['stok'] as num).toDouble();
            await client.from('produk').update({'stok': botolStok + qty}).eq('id', botolId);
          }
        }
      } else if (produkId != null) {
        // Bibit langsung: kembalikan stok bibit
        final bibit = await getProdukById(produkId);
        if (bibit != null) {
          final stokLama = (bibit['stok'] as num).toDouble();
          await client.from('produk').update({'stok': stokLama + qty}).eq('id', produkId);
        }
        // Kembalikan stok botol jika ada
        if (botolId != null && botolId.isNotEmpty) {
          final botol = await getProdukById(botolId);
          if (botol != null) {
            final botolStok = (botol['stok'] as num).toDouble();
            await client.from('produk').update({'stok': botolStok + qty}).eq('id', botolId);
          }
        }
      }
    }

    // Catat di tabel pembatalan (tidak ubah status transaksi agar tidak kena constraint)
    await client.from('pembatalan').insert({
      'toko_id': tokoId,
      'transaksi_id': transaksiId,
      'user_id': user['id'],
      'user_nama': user['nama'],
      'alasan': 'Dibatalkan oleh ${user['nama']}',
    });
  }

  // ══════ STOK MOVEMENT ══════
  static Future<List<Map<String, dynamic>>> getStokMovement(String tokoId, {String? tipe, int limit = 200}) async {
    var q = client.from('stok_movement').select().eq('toko_id', tokoId).order('created_at', ascending: false).limit(limit);
    if (tipe != null && tipe != 'semua') q = client.from('stok_movement').select().eq('toko_id', tokoId).eq('tipe', tipe).order('created_at', ascending: false).limit(limit);
    return await q;
  }

  static Future<void> tambahStokMasuk(String tokoId, String produkId, double qty, String userId, {String? keterangan, DateTime? tanggal}) async {
    final p = await getProdukById(produkId);
    if (p == null) return;
    final stokLama = (p['stok'] as num).toDouble();
    final tglStr = (tanggal ?? DateTime.now()).toIso8601String();
    await client.from('stok_movement').insert({
      'toko_id': tokoId,
      'produk_id': produkId,
      'tipe': 'masuk',
      'qty': qty,
      'stok_sebelum': stokLama,
      'stok_sesudah': stokLama + qty,
      'keterangan': keterangan ?? "Stok masuk: ${p['nama']}",
      'user_id': userId,
      'created_at': tglStr,
    });
    // Update stok aktual di tabel produk
    await client.from('produk').update({'stok': stokLama + qty}).eq('id', produkId);
  }

  // ══════ PERGERAKAN (View) ══════
  static Future<List<Map<String, dynamic>>> getPergerakan(String tokoId) async {
    // Filter pergerakan hanya produk milik toko ini
    final produkIds = (await client.from('produk').select('id').eq('toko_id', tokoId))
        .map((p) => p['id']).toSet();
    final all = await client.from('v_pergerakan_stok').select();
    return all.where((r) => produkIds.contains(r['produk_id'])).toList();
  }

  // ══════ PENGELUARAN ══════
  // onlyVisible: kalau true, filter hide_kasir = false (untuk akun kasir)
  static Future<List<Map<String, dynamic>>> getPengeluaran(String tokoId, {String? tanggalMulai, String? tanggalAkhir, bool onlyVisible = false}) async {
    final all = await _getPengeluaranRaw(tokoId, tanggalMulai: tanggalMulai, tanggalAkhir: tanggalAkhir);
    if (!onlyVisible) return all;
    // Filter di Dart (lebih tahan kalau kolom hide_kasir belum ada di DB lama)
    return all.where((p) {
      final v = p['hide_kasir'];
      return v == null || v == false;
    }).toList();
  }

  static Future<List<Map<String, dynamic>>> _getPengeluaranRaw(String tokoId, {String? tanggalMulai, String? tanggalAkhir}) async {
    var q = client.from('pengeluaran').select().eq('toko_id', tokoId).order('tanggal', ascending: false);
    if (tanggalMulai != null) q = client.from('pengeluaran').select().eq('toko_id', tokoId).gte('tanggal', tanggalMulai).lte('tanggal', tanggalAkhir ?? DateTime.now().toIso8601String().substring(0, 10)).order('tanggal', ascending: false);
    return await q;
  }

  // Toggle hide_kasir untuk satu pengeluaran
  static Future<void> setPengeluaranHideKasir(String id, bool hide) async {
    try {
      await client.from('pengeluaran').update({'hide_kasir': hide}).eq('id', id);
    } catch (_) {}
  }

  static Future<void> addPengeluaran(Map<String, dynamic> data) async {
    await client.from('pengeluaran').insert(data);
  }

  static Future<void> deletePengeluaran(String id) async {
    await client.from('pengeluaran').delete().eq('id', id);
  }

  // ══════ LAPORAN ══════
  static Future<List<Map<String, dynamic>>> getPenjualanHarian(String tokoId) async {
    return await client.from('v_penjualan_harian').select().eq('toko_id', tokoId).order('tanggal', ascending: false).limit(30);
  }

  static Future<List<Map<String, dynamic>>> getProdukTerlaris(String tokoId) async {
    // Ambil varian_id milik toko ini
    final produkIds = (await client.from('produk').select('id').eq('toko_id', tokoId))
        .map((p) => p['id'] as String).toList();
    if (produkIds.isEmpty) return [];
    final varianIds = (await client.from('varian').select('id').inFilter('produk_id', produkIds))
        .map((v) => v['id'] as String).toSet();
    final all = await client.from('v_produk_terlaris').select().order('total_terjual', ascending: false).limit(100);
    return all.where((r) => varianIds.contains(r['varian_id'])).take(20).toList();
  }

  // ══════ SUPPLIER ══════
  static Future<List<Map<String, dynamic>>> getSupplier(String tokoId) async {
    return await client.from('supplier').select().eq('toko_id', tokoId).order('nama');
  }

  static Future<void> addSupplier(Map<String, dynamic> data) async {
    await client.from('supplier').insert(data);
  }

  // ══════ PELANGGAN / MEMBER LOYALTY ══════
  static Future<List<Map<String, dynamic>>> getPelanggan(String tokoId) async {
    return await client.from('pelanggan').select().eq('toko_id', tokoId).order('nama');
  }

  static Future<void> addPelanggan(Map<String, dynamic> data) async {
    await client.from('pelanggan').insert(data);
  }

  // Tambah pelanggan baru, return record-nya (untuk dapat ID)
  static Future<Map<String, dynamic>?> tambahPelangganBaru(String tokoId, String nama, {String? hp}) async {
    try {
      return await tambahPelangganBaruStrict(tokoId, nama, hp: hp);
    } catch (_) { return null; }
  }

  // Versi STRICT: throw error kalau gagal (untuk UI yang butuh feedback)
  // Auto-fallback: kalau insert dengan hp gagal (kolom tidak ada), retry tanpa hp
  static Future<Map<String, dynamic>> tambahPelangganBaruStrict(String tokoId, String nama, {String? hp}) async {
    final payload = <String, dynamic>{
      'toko_id': tokoId,
      'nama': nama.trim(),
    };
    if (hp != null && hp.isNotEmpty) payload['hp'] = hp.trim();
    try {
      final r = await client.from('pelanggan').insert(payload).select().single();
      return r;
    } catch (e) {
      // Kalau gagal karena kolom 'hp' tidak ada di skema lama → retry tanpa hp
      final msg = e.toString().toLowerCase();
      if (hp != null && hp.isNotEmpty && (msg.contains('hp') || msg.contains('column'))) {
        final r = await client.from('pelanggan').insert({
          'toko_id': tokoId, 'nama': nama.trim(),
        }).select().single();
        return r;
      }
      rethrow;
    }
  }

  // Cari pelanggan by nama exact (atau buat baru kalau belum ada)
  static Future<Map<String, dynamic>?> findOrCreatePelanggan(String tokoId, String nama) async {
    try {
      final namaTrim = nama.trim();
      if (namaTrim.isEmpty || namaTrim.toLowerCase() == 'walk-in') return null;
      final rows = await client.from('pelanggan').select()
        .eq('toko_id', tokoId).ilike('nama', namaTrim).limit(1);
      if (rows.isNotEmpty) return Map<String, dynamic>.from(rows.first);
      return await tambahPelangganBaru(tokoId, namaTrim);
    } catch (_) { return null; }
  }

  // Hitung diskon tersedia untuk pelanggan (kelipatan 500rb → 50rb)
  // Berulang tiap kelipatan, kumulatif seumur hidup
  static double hitungDiskonTersedia(Map<String, dynamic> pelanggan) {
    final totalBelanja = ((pelanggan['total_belanja'] ?? 0) as num).toDouble();
    final dipakai = ((pelanggan['diskon_dipakai'] ?? 0) as num).toDouble();
    final eligible = (totalBelanja / 500000).floor() * 50000.0;
    final tersedia = eligible - dipakai;
    return tersedia > 0 ? tersedia : 0;
  }

  // Refresh data pelanggan tunggal
  static Future<Map<String, dynamic>?> getPelangganById(String id) async {
    try {
      return await client.from('pelanggan').select().eq('id', id).maybeSingle();
    } catch (_) { return null; }
  }

  // Ambil riwayat transaksi pelanggan
  static Future<List<Map<String, dynamic>>> getTransaksiPelanggan(String pelangganId, {int limit = 20}) async {
    try {
      return await client.from('transaksi').select()
        .eq('pelanggan_id', pelangganId)
        .order('created_at', ascending: false).limit(limit);
    } catch (_) { return []; }
  }

  // Update data pelanggan (nama, hp, alamat)
  static Future<void> updatePelanggan(String id, Map<String, dynamic> data) async {
    await client.from('pelanggan').update(data).eq('id', id);
  }

  // Hapus pelanggan. Transaksi lama otomatis pelanggan_id-nya jadi NULL
  // (karena ON DELETE SET NULL di skema v3.7) — transaksi tidak ikut terhapus.
  static Future<void> deletePelanggan(String id) async {
    await client.from('pelanggan').delete().eq('id', id);
  }

  // ══════ BULK IMPORT ══════
  static Future<int> importProduk(String tokoId, List<Map<String, dynamic>> rows) async {
    int count = 0;
    for (final row in rows) {
      try {
        await client.from('produk').insert({...row, 'toko_id': tokoId});
        count++;
      } catch (_) {}
    }
    return count;
  }

  static Future<int> importVarian(List<Map<String, dynamic>> rows) async {
    int count = 0;
    for (final row in rows) {
      try {
        await client.from('varian').insert(row);
        count++;
      } catch (_) {}
    }
    return count;
  }

  // ══════ QRIS (local storage) ══════
  static String? _qrisPath;
  static Future<String?> getQrisPath() async {
    if (_qrisPath != null) return _qrisPath;
    try {
      final prefs = await SharedPreferences.getInstance();
      _qrisPath = prefs.getString('qris_path');
    } catch (_) {}
    return _qrisPath;
  }
  static Future<void> saveQrisPath(String path) async {
    _qrisPath = path;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('qris_path', path);
    } catch (_) {}
  }

  // ══════ SHIFT MANAGEMENT ══════
  static Future<Map<String, dynamic>?> getActiveShift(String tokoId, String userId) async {
    return await client.from('shift').select().eq('toko_id', tokoId).eq('user_id', userId).eq('status', 'aktif').maybeSingle();
  }

  static Future<Map<String, dynamic>> startShift(String tokoId, String userId, String userNama, double kasAwal) async {
    return await client.from('shift').insert({
      'toko_id': tokoId, 'user_id': userId, 'user_nama': userNama,
      'kas_awal': kasAwal, 'status': 'aktif',
    }).select().single();
  }

  static Future<void> endShift(String shiftId, double kasAktual) async {
    // Hitung totals
    final shift = await client.from('shift').select().eq('id', shiftId).single();
    final mulai = shift['mulai'];

    // Transaksi selama shift
    final shiftTrx = await client.from('transaksi').select()
        .eq('toko_id', shift['toko_id']).eq('status', 'selesai')
        .gte('created_at', mulai);
    final kasPenjualan = shiftTrx.where((t) => t['metode'] == 'Cash').fold(0.0, (double s, t) => s + ((t['total'] ?? 0) as num).toDouble());

    // Kas masuk/keluar
    final kasList = await client.from('shift_kas').select().eq('shift_id', shiftId);
    double kasMasuk = 0, kasKeluar = 0;
    for (final k in kasList) {
      if (k['tipe'] == 'masuk') {
        kasMasuk += ((k['jumlah'] ?? 0) as num).toDouble();
      } else {
        kasKeluar += ((k['jumlah'] ?? 0) as num).toDouble();
      }
    }

    // Pembatalan
    final voidList = await client.from('pembatalan').select().eq('shift_id', shiftId);
    final kasPembatalan = voidList.fold(0.0, (double s, v) => s + ((v['total'] ?? 0) as num).toDouble());

    final kasAwal = (shift['kas_awal'] as num).toDouble();
    final kasMasukKeluar = kasMasuk - kasKeluar;
    final totalDiharapkan = kasAwal + kasPenjualan - kasPembatalan + kasMasukKeluar;
    final selisih = kasAktual - totalDiharapkan;

    await client.from('shift').update({
      'selesai': DateTime.now().toIso8601String(),
      'kas_penjualan': kasPenjualan,
      'kas_pembatalan': kasPembatalan,
      'kas_masuk_keluar': kasMasukKeluar,
      'total_diharapkan': totalDiharapkan,
      'kas_aktual': kasAktual,
      'selisih': selisih,
      'status': 'selesai',
    }).eq('id', shiftId);
  }

  static Future<List<Map<String, dynamic>>> getShiftHistory(String tokoId, {int limit = 20}) async {
    return await client.from('shift').select().eq('toko_id', tokoId).order('created_at', ascending: false).limit(limit);
  }

  // ══════ KAS MASUK/KELUAR ══════
  static Future<void> addShiftKas(String shiftId, String tokoId, String tipe, double jumlah, String keterangan, String userId) async {
    await client.from('shift_kas').insert({
      'shift_id': shiftId, 'toko_id': tokoId, 'tipe': tipe,
      'jumlah': jumlah, 'keterangan': keterangan, 'user_id': userId,
    });
  }

  static Future<List<Map<String, dynamic>>> getShiftKas(String shiftId) async {
    return await client.from('shift_kas').select().eq('shift_id', shiftId).order('created_at', ascending: false);
  }

  // ══════ PEMBATALAN (VOID) ══════
  static Future<void> addPembatalan({
    required String tokoId, String? shiftId, String? transaksiId,
    String? varianId, String? produkId, required String namaItem,
    required int qty, required double harga, required String alasan,
    required String userId, required String userNama,
  }) async {
    await client.from('pembatalan').insert({
      'toko_id': tokoId, 'shift_id': shiftId, 'transaksi_id': transaksiId,
      'varian_id': varianId, 'produk_id': produkId, 'nama_item': namaItem,
      'qty': qty, 'harga': harga, 'total': harga * qty,
      'alasan': alasan, 'user_id': userId, 'user_nama': userNama,
    });
  }

  static Future<List<Map<String, dynamic>>> getPembatalan(String tokoId, {String? tanggalMulai, String? tanggalAkhir}) async {
    var q = client.from('pembatalan').select().eq('toko_id', tokoId).order('created_at', ascending: false);
    if (tanggalMulai != null) q = client.from('pembatalan').select().eq('toko_id', tokoId).gte('created_at', '${tanggalMulai}T00:00:00').lte('created_at', '${tanggalAkhir ?? DateTime.now().toIso8601String().substring(0, 10)}T23:59:59').order('created_at', ascending: false);
    return await q;
  }

  // ══════ STOK KELUAR (manual: rusak, hilang, sample) ══════
  static Future<void> tambahStokKeluar(String tokoId, String produkId, double qty, String userId, String keterangan) async {
    final p = await getProdukById(produkId);
    if (p == null) return;
    final stokLama = (p['stok'] as num).toDouble();
    await client.from('stok_movement').insert({
      'toko_id': tokoId, 'produk_id': produkId, 'tipe': 'keluar',
      'qty': -qty, 'stok_sebelum': stokLama, 'stok_sesudah': stokLama - qty,
      'keterangan': keterangan, 'user_id': userId,
    });
    // Update stok aktual di tabel produk
    await client.from('produk').update({'stok': stokLama - qty}).eq('id', produkId);
  }

  // ══════ JUAL BIBIT LANGSUNG ══════
  static Future<String> jualBibitLangsung({
    required String tokoId, required Map<String, dynamic> user,
    required String produkId, required int qty, required double hargaJual,
    required double bayar, required String metode, String? shiftId,
    String? botolId, // optional: potong 1 botol juga
  }) async {
    final now = DateTime.now();
    final seq = now.millisecondsSinceEpoch % 99999;
    final noNota = 'BIB${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${seq.toString().padLeft(5, '0')}';
    final p = await getProdukById(produkId);
    if (p == null) throw Exception('Produk tidak ditemukan');
    final hargaBeli = ((p['harga_beli'] ?? 0) as num).toDouble();

    final trx = await client.from('transaksi').insert({
      'toko_id': tokoId, 'no_nota': noNota, 'user_id': user['id'], 'user_nama': user['nama'],
      'pelanggan_nama': 'Walk-in', 'subtotal': hargaJual * qty, 'diskon': 0,
      'total': hargaJual * qty, 'bayar': bayar, 'kembalian': bayar - (hargaJual * qty),
      'metode': metode, 'status': 'selesai',
    }).select().single();

    await client.from('transaksi_item').insert({
      'transaksi_id': trx['id'], 'produk_id': produkId,
      'nama_item': '${p['nama']} (bibit langsung)', 'qty': qty,
      'harga_satuan': hargaJual, 'subtotal': hargaJual * qty,
      'resep_bibit': qty.toDouble(), 'hpp': hargaBeli * qty,
    });

    // Potong stok bibit
    final stokLama = (p['stok'] as num).toDouble();
    await client.from('stok_movement').insert({
      'toko_id': tokoId, 'produk_id': produkId, 'tipe': 'penjualan',
      'qty': -qty.toDouble(), 'stok_sebelum': stokLama, 'stok_sesudah': stokLama - qty,
      'keterangan': 'Jual bibit langsung: ${p['nama']} x$qty', 'user_id': user['id'],
    });
    await client.from('produk').update({'stok': stokLama - qty}).eq('id', produkId);
    // Potong stok botol - WAJIB jika botolId ada
    if (botolId != null && botolId.isNotEmpty) {
      final botol = await getProdukById(botolId);
      if (botol != null) {
        final botolStok = (botol['stok'] as num).toDouble();
        await client.from('stok_movement').insert({
          'toko_id': tokoId, 'produk_id': botolId, 'tipe': 'penjualan',
          'qty': -1.0, 'stok_sebelum': botolStok, 'stok_sesudah': botolStok - 1,
          'keterangan': 'Jual bibit langsung (botol): ${botol['nama']}', 'user_id': user['id'],
        });
        await client.from('produk').update({'stok': botolStok - 1}).eq('id', botolId);
      }
    }
    return noNota;
  }

  // ══════ JUAL BIBIT MULTI (keranjang bibit) ══════
  static Future<String> jualBibitMulti({
    required String tokoId,
    required Map<String, dynamic> user,
    required List<Map<String, dynamic>> items, // [{produkId, qty, hargaJual, botolId?}]
    required double totalBayar,
    required double bayar,
    required String metode,
    double diskon = 0,
    String? shiftId,
    String? pelangganNama,
    String? pelangganId,
    double diskonMemberDipakai = 0,
  }) async {
    final now = DateTime.now();
    final dateStr = '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final seq = now.millisecondsSinceEpoch % 99999;
    final noNota = 'BBT$dateStr${seq.toString().padLeft(5, '0')}';
    final totalSetelahDiskon = (totalBayar - diskon).clamp(0.0, double.infinity);

    final trxPayload = <String, dynamic>{
      'toko_id': tokoId, 'no_nota': noNota,
      'user_id': user['id'], 'user_nama': user['nama'],
      'pelanggan_nama': pelangganNama ?? 'Walk-in',
      'subtotal': totalBayar, 'diskon': diskon, 'total': totalSetelahDiskon,
      'bayar': bayar, 'kembalian': (bayar - totalSetelahDiskon).clamp(0.0, double.infinity),
      'metode': metode, 'status': 'selesai',
    };
    if (pelangganId != null) trxPayload['pelanggan_id'] = pelangganId;
    final trxResult = await client.from('transaksi').insert(trxPayload).select().single();

    // Update stats pelanggan (akumulasi total belanja & diskon dipakai)
    if (pelangganId != null) {
      try {
        final p = await client.from('pelanggan').select('total_belanja,diskon_dipakai,jumlah_transaksi')
          .eq('id', pelangganId).maybeSingle();
        if (p != null) {
          await client.from('pelanggan').update({
            'total_belanja': ((p['total_belanja'] ?? 0) as num).toDouble() + totalSetelahDiskon,
            'diskon_dipakai': ((p['diskon_dipakai'] ?? 0) as num).toDouble() + diskonMemberDipakai,
            'jumlah_transaksi': ((p['jumlah_transaksi'] ?? 0) as num).toInt() + 1,
          }).eq('id', pelangganId);
        }
      } catch (_) {}
    }

    for (final item in items) {
      final produkId = item['produkId'] as String;
      final qty = (item['qty'] as num).toInt();
      final hargaJual = (item['hargaJual'] as num).toDouble();
      final botolId = item['botolId'] as String?;

      final bibit = await getProdukById(produkId);
      if (bibit == null) throw 'Produk bibit tidak ditemukan: $produkId';

      final stokLama = (bibit['stok'] as num).toDouble();
      // Stok diizinkan minus — owner butuh tau perlu restock, transaksi tidak diblokir.

      // Insert transaksi_item dulu (konsisten dengan jualBibitLangsung)
      await client.from('transaksi_item').insert({
        'transaksi_id': trxResult['id'],
        'produk_id': produkId,
        'botol_id': botolId,
        'nama_item': '${bibit['nama']} (bibit langsung)',
        'qty': qty, 'harga_satuan': hargaJual, 'subtotal': hargaJual * qty,
        'hpp': ((bibit['harga_beli'] ?? 0) as num).toDouble(),
      });

      // Potong stok bibit
      await client.from('stok_movement').insert({
        'toko_id': tokoId, 'produk_id': produkId, 'tipe': 'penjualan',
        'qty': -qty.toDouble(), 'stok_sebelum': stokLama, 'stok_sesudah': stokLama - qty,
        'keterangan': 'Jual bibit: ${bibit['nama']} x$qty', 'user_id': user['id'],
      });
      await client.from('produk').update({'stok': stokLama - qty}).eq('id', produkId);

      // Potong stok botol (kalau dipilih)
      if (botolId != null && botolId.isNotEmpty) {
        final botol = await getProdukById(botolId);
        if (botol != null) {
          final botolStok = (botol['stok'] as num).toDouble();
          await client.from('stok_movement').insert({
            'toko_id': tokoId, 'produk_id': botolId, 'tipe': 'penjualan',
            'qty': -qty.toDouble(), 'stok_sebelum': botolStok, 'stok_sesudah': botolStok - qty,
            'keterangan': 'Botol untuk bibit: ${botol['nama']} x$qty', 'user_id': user['id'],
          });
          await client.from('produk').update({'stok': botolStok - qty}).eq('id', botolId);
        }
      }
    }

    return noNota;
  }

  // ══════ CACHED AI INSIGHT (1x per hari, reset 00:00) ══════
  static Future<Map<String, dynamic>?> getCachedInsight(String tokoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDate = prefs.getString('insight_date_$tokoId');
      final today = DateTime.now().toString().substring(0, 10);
      if (savedDate == today) {
        final data = prefs.getString('insight_data_$tokoId');
        if (data != null) return Map<String, dynamic>.from(jsonDecode(data));
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveCachedInsight(String tokoId, Map<String, dynamic> insight) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toString().substring(0, 10);
      await prefs.setString('insight_date_$tokoId', today);
      // Flatten Map<String,int> to Map<String,dynamic> for JSON
      final safe = <String, dynamic>{};
      insight.forEach((k, v) {
        if (v is Map) {
          safe[k] = Map<String, dynamic>.from(v.map((mk, mv) => MapEntry(mk.toString(), mv)));
        } else {
          safe[k] = v;
        }
      });
      await prefs.setString('insight_data_$tokoId', jsonEncode(safe));
    } catch (_) {}
  }

  // ══════ SHIFT KAS PER TOKO (untuk laporan) ══════
  static Future<List<Map<String, dynamic>>> getShiftKasByToko(String tokoId, {String? tanggalMulai, String? tanggalAkhir}) async {
    var q = client.from('shift_kas').select().eq('toko_id', tokoId).order('created_at', ascending: false);
    if (tanggalMulai != null) q = client.from('shift_kas').select().eq('toko_id', tokoId).gte('created_at', '${tanggalMulai}T00:00:00').lte('created_at', '${tanggalAkhir ?? DateTime.now().toIso8601String().substring(0, 10)}T23:59:59').order('created_at', ascending: false);
    return await q;
  }

  // ══════ RESEP TEMPLATE ══════
  static Future<List<Map<String, dynamic>>> getResepTemplate() async {
    return await client.from('resep_template').select().order('ukuran').order('kualitas');
  }

  static Future<Map<String, dynamic>?> getResepTemplateBy(String ukuran, String kualitas) async {
    try {
      return await client.from('resep_template').select()
        .eq('ukuran', ukuran.toUpperCase())
        .eq('kualitas', kualitas.toUpperCase())
        .maybeSingle();
    } catch (_) { return null; }
  }

  static Future<void> addResepTemplate(Map<String, dynamic> data) async {
    await client.from('resep_template').insert(data);
  }

  static Future<void> updateResepTemplate(String id, Map<String, dynamic> data) async {
    await client.from('resep_template').update(data).eq('id', id);
  }

  static Future<void> deleteResepTemplate(String id) async {
    await client.from('resep_template').delete().eq('id', id);
  }

  // ══════ UPDATE VARIAN ══════
  static Future<void> updateVarian(String id, Map<String, dynamic> data) async {
    await client.from('varian').update(data).eq('id', id);
  }

  // ══════ UPDATE USER (ganti PIN) ══════
  static Future<void> updateUserPin(String userId, String newPin) async {
    await client.from('users').update({
      'pin': newPin, // legacy backup
      'pin_hash': hashPin(newPin),
    }).eq('id', userId);
  }

  static Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await client.from('users').update(data).eq('id', userId);
  }

  // ══════ SALDO AWAL BULANAN ══════
  static Future<Map<String, double>> getSaldoAwal(String tokoId, int bulan, int tahun) async {
    try {
      final rows = await client.from('saldo_awal').select()
        .eq('toko_id', tokoId).eq('periode_bulan', bulan).eq('periode_tahun', tahun);
      final map = <String, double>{};
      for (final r in rows) {
        map[r['produk_id'].toString()] = ((r['saldo'] ?? 0) as num).toDouble();
      }
      return map;
    } catch (_) { return {}; }
  }

  static Future<void> simpanSaldoAwalBulanIni(String tokoId) async {
    try {
      final now = DateTime.now();
      final produk = await getProduk(tokoId);
      for (final p in produk) {
        await client.from('saldo_awal').upsert({
          'toko_id': tokoId,
          'produk_id': p['id'],
          'periode_bulan': now.month,
          'periode_tahun': now.year,
          'saldo': p['stok'] ?? 0,
        }, onConflict: 'toko_id,produk_id,periode_bulan,periode_tahun');
      }
    } catch (_) {}
  }

  // Auto-snapshot: pastikan saldo awal bulan SEKARANG ada.
  // Kalau belum ada (artinya bulan baru), snapshot stok saat ini sebagai saldo awal.
  // Idempotent: dipanggil setiap kali app/screen pergerakan dibuka.
  // Return: true kalau snapshot baru dibuat (bulan baru), false kalau sudah ada.
  static Future<bool> autoSnapshotSaldoAwalJikaBulanBaru(String tokoId) async {
    try {
      final now = DateTime.now();
      // Cek apakah saldo awal bulan ini sudah pernah disimpan
      final ada = await client.from('saldo_awal').select('id')
        .eq('toko_id', tokoId)
        .eq('periode_bulan', now.month)
        .eq('periode_tahun', now.year).limit(1);
      if (ada.isNotEmpty) return false; // Sudah ada, skip

      // Belum ada → snapshot stok saat ini (= sisa stok dari bulan lalu)
      await simpanSaldoAwalBulanIni(tokoId);
      return true;
    } catch (_) { return false; }
  }

  // ══════ CETAK ULANG STRUK (get transaksi + items) ══════
  static Future<Map<String, dynamic>?> getTransaksiWithItems(String trxId) async {
    try {
      final trx = await client.from('transaksi').select().eq('id', trxId).maybeSingle();
      if (trx == null) return null;
      final items = await client.from('transaksi_item').select().eq('transaksi_id', trxId);
      return {...trx, 'items': items};
    } catch (_) { return null; }
  }

  // ══════ IMPORT KATALOG PRODUK (format Olsera xlsx) ══════
  // Handles 3 row types: BIBIT rows (name starts with "BIBIT "), BOTOL/SPRAY rows, VARIAN rows
  // Parse "15ML,MEDIUM" atau "15ML;SUPER" atau "15ML PLATINUM" → [ukuran, kualitas]
  static List<String> _parseVariantParts(String s) {
    s = s.trim();
    for (final sep in [',', ';', '|', '/']) {
      final p = s.split(sep).map((x) => x.trim()).where((x) => x.isNotEmpty).toList();
      if (p.length >= 2) return p;
    }
    // Coba pisah spasi: "15ML SUPER" → ["15ML", "SUPER"]
    final bySpace = s.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (bySpace.length >= 2) return bySpace;
    return [];
  }

  static String _normLoose(String s) {
    return s
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _normUkuran(String s) {
    return s
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('MILI', 'ML')
        .replaceAll('MILILITER', 'ML');
  }

  static String _normKualitas(String s) {
    final k = _normLoose(s);
    const alias = <String, String>{
      'EX': 'EXTRA',
      'EXTR': 'EXTRA',
      'PLAT': 'PLATINUM',
      'PLTNM': 'PLATINUM',
      'MD': 'MEDIUM',
      'MID': 'MEDIUM',
    };
    return alias[k] ?? k;
  }

    static Future<Map<String, dynamic>> importKatalogOlsera(String tokoId, List<Map<String, dynamic>> rows, {void Function(int done, int total)? onProgress}) async {
    int produkBaru = 0, varianBaru = 0, skipped = 0, updated = 0, bibitBaru = 0, botolBaru = 0;
    final errors = <String>[];

    // ── PHASE 1: Classify rows (no DB access, always safe) ──────────────────────
    final bibitRows  = <Map<String, dynamic>>[];
    final botolRows  = <Map<String, dynamic>>[];
    final varianRows = <Map<String, dynamic>>[];

    for (final row in rows) {
      final name = (row['name'] ?? '').toString().trim();
      if (name.isEmpty) { skipped++; continue; }
      final category     = (row['category'] ?? '').toString().toUpperCase();
      final variantNames = (row['variant_names'] ?? '').toString().trim();
      final nameUp       = name.toUpperCase();

      if (nameUp.startsWith('BIBIT ') && variantNames.isEmpty) {
        bibitRows.add(row);
      } else if (category.contains('BOTOL') || category.contains('SPRAY') ||
                 nameUp.contains('BOTOL') || nameUp.contains('SPRAY')) {
        botolRows.add(row);
      } else if (variantNames.isNotEmpty) {
        varianRows.add(row);
      } else {
        skipped++;
      }
    }

    // ── PHASE 2: Load ALL existing data once (fatal if fails — propagate) ─────────
    final existingProduk = await getProduk(tokoId);
    final existingVarian = await getVarian(tokoId);
    final templates      = await getResepTemplate();

    final bibitMap = <String, String>{}; // NAMA_UPPERCASE -> produk.id
    final botolMap = <String, String>{}; // NAMA_UPPERCASE -> produk.id
    for (final p in existingProduk) {
      final kat = (p['kategori'] ?? '').toString();
      final nm  = (p['nama'] ?? '').toString().toUpperCase();
      if (kat == 'STOCK PARFUME') {
        bibitMap[nm] = p['id'].toString();
      } else if (kat == 'STOK BOTOL' || kat == 'STOK SPRAY') {
        botolMap[nm] = p['id'].toString();
      }
    }
    // varianMap key: "produkId|ukuran|kualitas" (all lowercase) -> varian row
    final varianMap = <String, Map<String, dynamic>>{};
    for (final v in existingVarian) {
      final key = '${v['produk_id']}|${(v['ukuran'] ?? '').toString().toLowerCase()}'
                  '|${(v['kualitas'] ?? '').toString().toLowerCase()}';
      varianMap[key] = v;
    }

    // Helper: convert empty string to null (prevents unique-constraint failures on sku/barcode)
    String? nn(dynamic v) { final s = v?.toString().trim() ?? ''; return s.isEmpty ? null : s; }

    // ── PHASE 3: BOTOL — deduplicate, classify new vs existing, batch-insert ─────
    final newBotolList = <Map<String, dynamic>>[];
    final seenBotol    = <String>{};  // deduplicate within this file
    for (final row in botolRows) {
      final name    = (row['name'] ?? '').toString().trim();
      final nameUp  = name.toUpperCase();
      final stok    = ((row['stock_qty'] ?? 0) as num).toDouble();
      final minStok = ((row['low_stock_alert'] ?? row['low_stock_warning'] ?? 5) as num).toDouble();
      final hb      = ((row['buy_price'] ?? 0) as num).toDouble();
      final kat     = nameUp.contains('SPRAY') || (row['category'] ?? '').toString().toUpperCase().contains('SPRAY')
                      ? 'STOK SPRAY' : 'STOK BOTOL';
      if (botolMap.containsKey(nameUp)) {
        try {
          // Update harga & min_stok saja, JANGAN overwrite stok
          final upd = <String, dynamic>{'min_stok': minStok};
          if (hb > 0) upd['harga_beli'] = hb;
          await client.from('produk').update(upd).eq('id', botolMap[nameUp]!);
          updated++;
        } catch (_) { skipped++; }
      } else if (!seenBotol.contains(nameUp)) {
        seenBotol.add(nameUp);
        newBotolList.add({'toko_id': tokoId, 'nama': name, 'kategori': kat,
            'harga_beli': hb, 'stok': stok, 'min_stok': minStok, 'satuan': 'pcs', 'aktif': true});
      } else { skipped++; }
    }
    // Batch insert new botol (chunks of 100; individual fallback on error)
    for (int i = 0; i < newBotolList.length; i += 100) {
      final chunk = newBotolList.sublist(i, (i + 100).clamp(0, newBotolList.length));
      try {
        final inserted = await client.from('produk').insert(chunk).select();
        for (final r in inserted) {
          botolMap[(r['nama'] ?? '').toString().toUpperCase()] = r['id'].toString();
          botolBaru++;
          produkBaru++;
        }
      } catch (e) {
        errors.add('botol-batch: $e');
        for (final item in chunk) {
          try {
            final r = await client.from('produk').insert(item).select().single();
            botolMap[(r['nama'] ?? '').toString().toUpperCase()] = r['id'].toString();
            botolBaru++; produkBaru++;
          } catch (_) { skipped++; }
        }
      }
    }

    // ── PHASE 4: BIBIT — deduplicate, classify new vs existing, batch-insert ─────
    final newBibitList = <Map<String, dynamic>>[];
    final seenBibit    = <String>{};
    for (final row in bibitRows) {
      final name      = (row['name'] ?? '').toString().trim();
      final nameUp    = name.toUpperCase();
      final stok      = ((row['stock_qty'] ?? 0) as num).toDouble();
      final hb        = ((row['buy_price'] ?? 0) as num).toDouble();
      final sellPrice = ((row['sell_price'] ?? row['pos_sell_price'] ?? 0) as num).toDouble();
      final minStok   = ((row['low_stock_alert'] ?? row['low_stock_warning'] ?? 50) as num).toDouble();
      if (bibitMap.containsKey(nameUp)) {
        try {
          // Update harga & min_stok saja — JANGAN overwrite stok (kelola via Stok Masuk)
          final upd = <String, dynamic>{'min_stok': minStok};
          if (hb > 0)        upd['harga_beli']      = hb;
          if (sellPrice > 0) upd['harga_jual_bibit'] = sellPrice.round();
          await client.from('produk').update(upd).eq('id', bibitMap[nameUp]!);
          updated++;
        } catch (_) { skipped++; }
      } else if (!seenBibit.contains(nameUp)) {
        seenBibit.add(nameUp);
        newBibitList.add({'toko_id': tokoId, 'nama': name, 'kategori': 'STOCK PARFUME',
            'harga_beli': hb, 'harga_jual_bibit': sellPrice.round(),
            'stok': stok, 'min_stok': minStok, 'satuan': 'ml', 'aktif': true});
      } else { skipped++; }
    }
    // Batch insert new bibit (chunks of 100; individual fallback on error)
    int totalWork = newBibitList.length + botolRows.length + 1;
    int doneWork = 0;
    final initialTotal = totalWork < 1 ? 1 : (totalWork > 999999 ? 999999 : totalWork);
    onProgress?.call(0, initialTotal);
    for (int i = 0; i < newBibitList.length; i += 100) {
      final chunk = newBibitList.sublist(i, (i + 100).clamp(0, newBibitList.length));
      try {
        final inserted = await client.from('produk').insert(chunk).select();
        for (final r in inserted) {
          bibitMap[(r['nama'] ?? '').toString().toUpperCase()] = r['id'].toString();
          bibitBaru++; produkBaru++;
        }
      } catch (e) {
        errors.add('bibit-batch: $e');
        for (final item in chunk) {
          try {
            final r = await client.from('produk').insert(item).select().single();
            bibitMap[(r['nama'] ?? '').toString().toUpperCase()] = r['id'].toString();
            bibitBaru++; produkBaru++;
          } catch (_) {
            // Fallback: insert tanpa harga_jual_bibit (kalau kolom belum ada di DB)
            try {
              final safe = Map<String, dynamic>.from(item)..remove('harga_jual_bibit');
              final r = await client.from('produk').insert(safe).select().single();
              bibitMap[(r['nama'] ?? '').toString().toUpperCase()] = r['id'].toString();
              bibitBaru++; produkBaru++;
            } catch (_) { skipped++; }
          }
        }
      }
    }

    // ── PHASE 5: VARIAN — deduplicate, build lists, batch-insert new ─────────────
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in varianRows) {
      grouped.putIfAbsent((row['name'] ?? '').toString().trim(), () => []).add(row);
    }

    final newVarianList    = <Map<String, dynamic>>[];
    final updateVarianList = <Map<String, dynamic>>[]; // {id, data}
    final seenVarian       = <String>{};  // deduplicate within this file

    for (final entry in grouped.entries) {
      final parfumName = entry.key;
      final bibitNama  = 'BIBIT ${parfumName.toUpperCase()}';
      String? bibitId  = bibitMap[bibitNama];

      // Auto-create placeholder BIBIT if not found
      if (bibitId == null) {
        try {
          final r = await client.from('produk').insert({
            'toko_id': tokoId, 'nama': bibitNama, 'kategori': 'STOCK PARFUME',
            'harga_beli': 0, 'stok': 0, 'min_stok': 50, 'satuan': 'ml', 'aktif': true,
          }).select().single();
          bibitId = r['id'].toString();
          bibitMap[bibitNama] = bibitId;
          produkBaru++;
        } catch (_) {
          try {
            final ex = await client.from('produk').select()
                .eq('toko_id', tokoId).eq('nama', bibitNama).eq('aktif', true).maybeSingle();
            if (ex != null) { bibitId = ex['id'].toString(); bibitMap[bibitNama] = bibitId; }
          } catch (_) {}
        }
      }

      if (bibitId == null) { skipped += entry.value.length; continue; }

      for (final row in entry.value) {
        final variantName = (row['variant_names'] ?? '').toString();
        final parts = _parseVariantParts(variantName);
        if (parts.length < 2) { skipped++; continue; }
        final ukuran    = parts[0].toLowerCase();
        final kualitas  = _titleCase(parts[1]);
        final hargaJual = ((row['sell_price'] ?? row['pos_sell_price'] ?? 0) as num).toDouble();

        final tpl = templates.firstWhere(
          (t) => (t['ukuran'] ?? '').toString().toUpperCase() == parts[0].toUpperCase()
              && (t['kualitas'] ?? '').toString().toUpperCase() == parts[1].toUpperCase(),
          orElse: () => {});

        final rowResepBibit = ((row['resep_bibit_ml'] ?? 0) as num).toDouble();
        final rowResepBotol = (row['resep_botol'] ?? '').toString().trim();
        final qtyBibit = rowResepBibit > 0 ? rowResepBibit
            : (tpl.isNotEmpty ? ((tpl['qty_bibit'] ?? 0) as num).toDouble() : 15.0);
        final botolKat = rowResepBotol.isNotEmpty ? rowResepBotol
            : (tpl.isNotEmpty ? (tpl['botol_kategori'] ?? 'STOK BOTOL 30ML').toString() : 'STOK BOTOL 30ML');
        String? botolId = botolMap[botolKat.toUpperCase()];
        if (botolId == null) {
          final botolKatUp = botolKat.toUpperCase();
          for (final e in botolMap.entries) {
            if (e.key.contains(botolKatUp) || botolKatUp.contains(e.key)) {
              botolId = e.value;
              break;
            }
          }
        }

        final vKey = '$bibitId|$ukuran|${kualitas.toLowerCase()}';
        if (seenVarian.contains(vKey)) { skipped++; continue; } // in-file duplicate

        final existingV = varianMap[vKey];
        if (existingV != null) {
          final upd = <String, dynamic>{};
          if (hargaJual > 0) upd['harga_jual'] = hargaJual;
          if (botolId != null) upd['resep_botol_id'] = botolId;
          if (upd.isNotEmpty) updateVarianList.add({'id': existingV['id'], 'data': upd});
        } else {
          seenVarian.add(vKey);
          newVarianList.add({
            'produk_id': bibitId, 'nama': parfumName, 'ukuran': ukuran, 'kualitas': kualitas,
            'harga_jual': hargaJual, 'resep_bibit': qtyBibit, 'resep_botol_id': botolId,
            'kode': nn(row['sku']), 'barcode': nn(row['barcode']), 'aktif': true,
          });
        }
      }
    }

    totalWork += newVarianList.length;

    // Helper: build varianMap key dari map data
    String vkFromMap(Map<String, dynamic> m) =>
        '${m['produk_id']}|${(m['ukuran'] ?? '').toString().toLowerCase()}'
        '|${(m['kualitas'] ?? '').toString().toLowerCase()}';

    // Batch insert new varian (chunks of 50; individual + minimal fallback)
    for (int i = 0; i < newVarianList.length; i += 50) {
      final chunk = newVarianList.sublist(i, (i + 50).clamp(0, newVarianList.length));
      doneWork += chunk.length;
      final safeDone = doneWork < 0 ? 0 : (doneWork > totalWork ? totalWork : doneWork);
      final safeTotal = totalWork < 1 ? 1 : (totalWork > 999999 ? 999999 : totalWork);
      onProgress?.call(safeDone, safeTotal);
      try {
        // Pakai .select() supaya varianMap ter-update — cegah duplikat di batch berikutnya
        final inserted = await client.from('varian').insert(chunk).select('id, produk_id, ukuran, kualitas');
        for (final r in inserted) { varianMap[vkFromMap(r)] = r; }
        varianBaru += inserted.length;
      } catch (e) {
        if (errors.length < 20) errors.add('varian-batch[$i]: batch gagal, retry per-item');
        for (final v in chunk) {
          final vKey = vkFromMap(v);
          // Kalau sudah ada di varianMap (dari file sebelumnya atau batch sebelumnya) — UPDATE saja
          if (varianMap.containsKey(vKey)) {
            try {
              final upd2 = <String, dynamic>{};
              if ((v['harga_jual'] as num?) != null && (v['harga_jual'] as num) > 0) upd2['harga_jual'] = v['harga_jual'];
              if (v['resep_botol_id'] != null) upd2['resep_botol_id'] = v['resep_botol_id'];
              if (upd2.isNotEmpty) await client.from('varian').update(upd2).eq('id', varianMap[vKey]!['id']);
              updated++;
            } catch (_) { skipped++; }
            continue;
          }
          try {
            final r = await client.from('varian').insert(v).select().single();
            varianBaru++;
            varianMap[vKey] = r;
          } catch (_) {
            // Fallback minimal: tanpa kode/barcode/resep_botol_id
            if (varianMap.containsKey(vKey)) {
              // Race: muncul di DB setelah insert gagal — skip, jangan duplikat
              skipped++;
            } else {
              try {
                final r2 = await client.from('varian').insert({
                  'produk_id': v['produk_id'],
                  'nama': v['nama'],
                  'ukuran': v['ukuran'],
                  'kualitas': v['kualitas'],
                  'harga_jual': (v['harga_jual'] as num?) ?? 0,
                  'resep_bibit': (v['resep_bibit'] as num?) ?? 15,
                  'aktif': true,
                }).select().single();
                varianBaru++;
                varianMap[vKey] = r2;
              } catch (e2) {
                skipped++;
                if (errors.length < 20) errors.add('varian-skip: ${v['nama']} ${v['ukuran']} ${v['kualitas']}');
              }
            }
          }
        }
      }
    }

    // Update existing varian
    for (final upd in updateVarianList) {
      try {
        await client.from('varian').update(upd['data'] as Map<String, dynamic>).eq('id', upd['id']);
        updated++;
      } catch (_) { skipped++; }
    }

    return {
      'produk_baru': produkBaru, 'varian_baru': varianBaru,
      'skipped': skipped, 'updated': updated,
      'bibit_baru': bibitBaru, 'botol_baru': botolBaru,
      // Diagnostics
      '_bibit_rows': bibitRows.length,
      '_botol_rows': botolRows.length,
      '_varian_rows': varianRows.length,
      '_errors': errors.isEmpty ? '' : errors.take(20).join('\n'),
      '_errors_count': errors.length,
    };
  }

  // ══════ IMPORT RESEP/BOM (format Olsera, xlsx atau CSV separator ";") ══════
  // Olsera BOM format (9 kolom):
  //   [0]to_all_store_id [1]to_store_url_id [2]product_name [3]product_variant_name
  //   [4]material_product_name [5]material_variant_name [6]qty [7]uom [8]uom_conversion
  static Future<Map<String, int>> importResepOlsera(String tokoId, List<List<dynamic>> csvRows, {void Function(int done, int total)? onProgress}) async {
    int updated = 0, skipped = 0, skippedVarian = 0, skippedBotol = 0;
    try {
      if (csvRows.length < 2) return {'updated': 0, 'skipped': 0};

      // Strip BOM and detect header format
      final rawHeader = csvRows.first
          .map((c) => c.toString().replaceAll('\uFEFF', '').toLowerCase().trim())
          .toList();

      bool isOlseraFormat = false;
      int dataStart = 0;
      int colProduct = 1, colVariant = -1, colMaterial = 2, colQty = 3;

      final hasHeader = rawHeader.any((c) =>
          c.contains('name') || c.contains('product') || c.contains('qty'));
      if (hasHeader) {
        dataStart = 1;
        if (rawHeader.any((c) =>
            c == 'product_variant_name' || c == 'material_product_name')) {
          isOlseraFormat = true;
          colProduct  = 2; // product_name
          colVariant  = 3; // product_variant_name e.g. "15ML,SUPER"
          colMaterial = 4; // material_product_name
          colQty      = 6; // qty
        }
      }

      final allProduk = await getProduk(tokoId);
      final allVarian = await getVarian(tokoId);

      // Maps: NAMA_UPPER -> id
      final bibitMap = <String, String>{};
      final bibitByNorm = <String, String>{}; // normalized bare name -> id
      final botolMap = <String, String>{};
      for (final p in allProduk) {
        final kat = (p['kategori'] ?? '').toString();
        final nm  = (p['nama'] ?? '').toString().toUpperCase().trim();
        if (kat == 'STOCK PARFUME') {
          bibitMap[nm] = p['id'].toString();
          final bare = nm.startsWith('BIBIT ') ? nm.substring(6).trim() : nm;
          bibitByNorm[_normLoose(bare)] = p['id'].toString();
        } else if (kat == 'STOK BOTOL' || kat == 'STOK SPRAY') {
          botolMap[nm] = p['id'].toString();
        }
      }

      // ── AUTO-CREATE botol yang ada di CSV tapi belum di DB ──────────────────
      // Scan semua material_product_name dari CSV, cari yang STOK BOTOL/SPRAY
      // tapi tidak ada di botolMap → insert otomatis agar resep bisa tersimpan
      final missingBotolNames = <String>{};
      for (int i = dataStart; i < csvRows.length; i++) {
        final row = csvRows[i];
        final maxIdx = isOlseraFormat ? 6 : 3;
        if (row.length <= maxIdx) continue;
        final matUp = row[colMaterial].toString().toUpperCase().trim();
        if (matUp.isEmpty) continue;
        if (!matUp.startsWith('BIBIT ') && !botolMap.containsKey(matUp)) {
          // Cek partial match dulu sebelum tandai "missing"
          final hasPartial = botolMap.keys.any(
            (k) => k.contains(matUp) || matUp.contains(k));
          if (!hasPartial) missingBotolNames.add(matUp);
        }
      }
      // Insert botol yang benar-benar hilang
      for (final nameUp in missingBotolNames) {
        // Gunakan Title Case untuk nama produk
        final namePretty = nameUp.split(' ').map((w) =>
          w.isEmpty ? w : w[0] + w.substring(1).toLowerCase()).join(' ');
        final kat = nameUp.contains('SPRAY') ? 'STOK SPRAY' : 'STOK BOTOL';
        try {
          final inserted = await client.from('produk').insert({
            'toko_id': tokoId, 'nama': namePretty, 'kategori': kat,
            'harga_beli': 0, 'stok': 0, 'min_stok': 5, 'satuan': 'pcs', 'aktif': true,
          }).select().single();
          botolMap[nameUp] = inserted['id'].toString();
        } catch (_) {
          // Produk mungkin sudah ada (race/duplicate) — coba ambil ID-nya
          try {
            final existing = await client.from('produk')
              .select('id').eq('toko_id', tokoId).eq('nama', namePretty).single();
            botolMap[nameUp] = existing['id'].toString();
          } catch (_) {}
        }
      }
      // ── END AUTO-CREATE ─────────────────────────────────────────────────────

      // Index varian by bibitId -> list (primary: more reliable than name-only lookup)
      final varianByBibit = <String, List<Map<String, dynamic>>>{};
      // Secondary: by "nama ukuran kualitas" key and by SKU
      final varianByKey = <String, Map<String, dynamic>>{};
      final varianByNormKey = <String, Map<String, dynamic>>{};
      for (final v in allVarian) {
        final pid = v['produk_id']?.toString() ?? '';
        if (pid.isNotEmpty) varianByBibit.putIfAbsent(pid, () => []).add(v);
        // Key: "NAMA UKURAN KUALITAS" all uppercase
        final key = '${v['nama'] ?? ''} ${v['ukuran'] ?? ''} ${v['kualitas'] ?? ''}'
            .toUpperCase().trim().replaceAll(RegExp(r'\s+'), ' ');
        varianByKey[key] = v;
        final normKey = '${_normLoose((v['nama'] ?? '').toString())} ${_normUkuran((v['ukuran'] ?? '').toString())} ${_normKualitas((v['kualitas'] ?? '').toString())}'
            .trim();
        if (normKey.isNotEmpty) varianByNormKey[normKey] = v;
        final sku = (v['sku'] ?? '').toString().trim();
        if (sku.isNotEmpty) varianByKey[sku.toUpperCase()] = v;
      }

      // Helper: resolve varian from product_name + variant_str ("15ML,SUPER")
      // Strategy 1: find bibit by "BIBIT "+productName → lookup varian by ukuran+kualitas
      // Strategy 2: fuzzy bibit name match
      // Strategy 3: "nama ukuran kualitas" key (original approach, fallback)
      Map<String, dynamic>? findVarian(String productName, String variantStr) {
        final parts = _parseVariantParts(variantStr);
        if (parts.isEmpty) return null;
        final productUp = productName.toUpperCase().trim();
        final productNorm = _normLoose(productName);
        final ukuranNorm = parts.isNotEmpty ? _normUkuran(parts[0]) : '';
        final kualitasNorm = parts.length >= 2 ? _normKualitas(parts[1]) : '';
        final ukuranUp = ukuranNorm;
        final kualitasUp = kualitasNorm;

        // Find bibit produk: DB name = "BIBIT " + productName
        final bibitKeyExact = 'BIBIT $productUp';
        String? bibitId = bibitMap[bibitKeyExact];
        bibitId ??= bibitByNorm[productNorm];

        // Fuzzy: strip "BIBIT " prefix from bibitMap keys and compare
        if (bibitId == null) {
          for (final entry in bibitMap.entries) {
            final bare = entry.key.startsWith('BIBIT ')
                ? entry.key.substring(6).trim() : entry.key;
            if (_normLoose(bare) == productNorm) { bibitId = entry.value; break; }
          }
        }

        // Contains match (handles slight name differences)
        if (bibitId == null) {
          for (final entry in bibitMap.entries) {
            final bare = entry.key.startsWith('BIBIT ')
                ? entry.key.substring(6).trim() : entry.key;
            final bareNorm = _normLoose(bare);
            if (bareNorm.contains(productNorm) || productNorm.contains(bareNorm)) {
              bibitId = entry.value; break;
            }
          }
        }

        if (bibitId != null) {
          for (final v in (varianByBibit[bibitId] ?? [])) {
            final vUkuran = _normUkuran((v['ukuran'] ?? '').toString());
            final vKualitas = _normKualitas((v['kualitas'] ?? '').toString());
            if (vUkuran == ukuranUp && vKualitas == kualitasUp) return v;
          }
          if (ukuranUp.isNotEmpty && kualitasUp.isNotEmpty) {
            for (final v in (varianByBibit[bibitId] ?? [])) {
              final vUkuran = _normUkuran((v['ukuran'] ?? '').toString());
              final vKualitas = _normKualitas((v['kualitas'] ?? '').toString());
              if (vUkuran == ukuranUp && vKualitas.contains(kualitasUp)) return v;
            }
          }
        }

        // Fallback: "nama ukuran kualitas" key
        if (ukuranUp.isNotEmpty && kualitasUp.isNotEmpty) {
          final key1 = '${productName.toUpperCase()} $ukuranUp $kualitasUp'
              .replaceAll(RegExp(r'\s+'), ' ').trim();
          if (varianByKey.containsKey(key1)) return varianByKey[key1];
          // Also try lowercase ukuran
          final key2 = '${productName.toUpperCase()} ${ukuranUp.toLowerCase()} $kualitasUp'
              .replaceAll(RegExp(r'\s+'), ' ').trim();
          if (varianByKey.containsKey(key2)) return varianByKey[key2];
        }
        final normKey = '$productNorm $ukuranUp $kualitasUp'.trim();
        if (varianByNormKey.containsKey(normKey)) return varianByNormKey[normKey];
        // No variant str: match any varian with this name
        return varianByNormKey['$productNorm  '.trim()] ?? varianByKey[productUp];
      }

      // Kumpulkan semua update dulu, baru kirim batch → hindari timeout 10000+ await
      final bibitUpdates  = <String, Map<String, dynamic>>{}; // varianId → {resep_bibit, produk_id}
      final botolUpdates  = <String, String>{};               // varianId → botolId

      for (int i = dataStart; i < csvRows.length; i++) {
        final row = csvRows[i];
        final maxIdx = isOlseraFormat ? 6 : 3;
        if (row.length <= maxIdx) { skipped++; continue; }

        final productName  = row[colProduct].toString().trim();
        final materialName = row[colMaterial].toString().trim();
        final qty = double.tryParse(row[colQty].toString().replaceAll(',', '.')) ?? 0;
        if (materialName.isEmpty || qty <= 0 || productName.isEmpty) { skipped++; continue; }

        Map<String, dynamic>? varian;
        if (isOlseraFormat && colVariant >= 0 && row.length > colVariant) {
          varian = findVarian(productName, row[colVariant].toString().trim());
        } else {
          varian = findVarian(productName, '');
        }
        if (varian == null) { skipped++; skippedVarian++; continue; }

        final varId = varian['id'].toString();
        final matUp = materialName.toUpperCase().trim();

        if (matUp.startsWith('BIBIT ')) {
          final upd = <String, dynamic>{'resep_bibit': qty};
          if (bibitMap[matUp] != null) upd['produk_id'] = bibitMap[matUp];
          bibitUpdates[varId] = upd;
        } else {
          String? botolId = botolMap[matUp];
          if (botolId == null) {
            final match = botolMap.entries.firstWhere(
              (e) => e.key.contains(matUp) || matUp.contains(e.key),
              orElse: () => const MapEntry('', ''));
            if (match.value.isNotEmpty) botolId = match.value;
          }
          if (botolId != null) {
            botolUpdates[varId] = botolId;
          } else {
            skipped++; skippedBotol++;
          }
        }
      }

      // Batch update bibit (chunk 50 — satu update per varian_id)
      final bibitEntries = bibitUpdates.entries.toList();
      final botolEntries = botolUpdates.entries.toList();
      final totalResep = (bibitEntries.length + botolEntries.length).clamp(1, 999999);
      int doneResep = 0;
      onProgress?.call(0, totalResep);

      for (int i = 0; i < bibitEntries.length; i += 50) {
        final chunk = bibitEntries.sublist(i, (i + 50).clamp(0, bibitEntries.length));
        for (final e in chunk) {
          try {
            await client.from('varian').update(e.value).eq('id', e.key);
            updated++;
          } catch (_) { skipped++; }
          doneResep++;
        }
        onProgress?.call(doneResep, totalResep);
      }

      // Batch update botol (chunk 50)
      for (int i = 0; i < botolEntries.length; i += 50) {
        final chunk = botolEntries.sublist(i, (i + 50).clamp(0, botolEntries.length));
        for (final e in chunk) {
          try {
            await client.from('varian').update({'resep_botol_id': e.value}).eq('id', e.key);
            updated++;
          } catch (_) { skipped++; }
          doneResep++;
        }
        onProgress?.call(doneResep, totalResep);
      }
    } catch (e) {
      // Rethrow so caller (import_screen) can show the actual error in log
      rethrow;
    }
    return {'updated': updated, 'skipped': skipped, 'skipped_varian': skippedVarian, 'skipped_botol': skippedBotol};
  }

  // ══════ EXPORT RESEP CSV (format Olsera BOM) ══════
  static Future<List<List<dynamic>>> exportResepCSVRows(String tokoId) async {
    final rows = <List<dynamic>>[
      ['recipe_code', 'product_name', 'material_product_name', 'qty', 'unit'],
    ];
    try {
      final allProduk = await getProduk(tokoId);
      final allVarian = await getVarian(tokoId);
      final produkById = <String, Map<String, dynamic>>{};
      for (final p in allProduk) {
        produkById[p['id'].toString()] = p;
      }

      for (final v in allVarian) {
        final bibit = produkById[v['produk_id']?.toString() ?? ''];
        if (bibit == null || (bibit['kategori'] ?? '') != 'STOCK PARFUME') continue;
        final sku        = (v['sku'] ?? '').toString();
        final parfumName = '${v['nama'] ?? ''} ${v['ukuran'] ?? ''} ${v['kualitas'] ?? ''}'.trim();
        final resepBibit = (v['resep_bibit'] as num?)?.toDouble() ?? 0;
        final botolId    = v['resep_botol_id']?.toString() ?? '';
        if (resepBibit > 0) {
          rows.add([sku, parfumName, bibit['nama'] ?? '', resepBibit.toStringAsFixed(0), 'ml']);
        }
        if (botolId.isNotEmpty) {
          final botol = produkById[botolId];
          if (botol != null) rows.add([sku, parfumName, botol['nama'] ?? '', 1, 'pcs']);
        }
      }
    } catch (_) {}
    return rows;
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    }).join(' ');
  }

  // ══════ BULK DELETE KATALOG ══════
  static Future<void> hapusSemuaVarianProduk(String produkId) async {
    await client.from('varian').update({'aktif': false}).eq('produk_id', produkId);
    await client.from('produk').update({'aktif': false}).eq('id', produkId);
  }

  // ══════ RESET / HAPUS DATA ══════

  // Reset semua resep: set resep_bibit=0 dan resep_botol_id=null di semua varian toko ini
  static Future<void> resetSemuaResep(String tokoId) async {
    final produkList = await client.from('produk').select('id').eq('toko_id', tokoId);
    final produkIds = (produkList as List).map((p) => p['id'] as String).toList();
    if (produkIds.isEmpty) return;
    for (int i = 0; i < produkIds.length; i += 50) {
      final batch = produkIds.sublist(i, i + 50 > produkIds.length ? produkIds.length : i + 50);
      await client.from('varian').update({'resep_bibit': 0, 'resep_botol_id': null}).inFilter('produk_id', batch);
    }
  }

  // Hapus semua produk + varian (bukan transaksi)
  static Future<void> hapusSemuaProduk(String tokoId) async {
    final produkList = await client.from('produk').select('id').eq('toko_id', tokoId);
    final produkIds = (produkList as List).map((p) => p['id'] as String).toList();
    if (produkIds.isEmpty) return;

    // Kumpulkan semua varian_id dulu
    final varianIds = <String>[];
    for (int i = 0; i < produkIds.length; i += 50) {
      final batch = produkIds.sublist(i, (i + 50).clamp(0, produkIds.length));
      final vList = await client.from('varian').select('id').inFilter('produk_id', batch);
      varianIds.addAll((vList as List).map((v) => v['id'] as String));
    }

    // PENTING: Hapus transaksi_item yang referensikan varian ini DULU
    // (fix foreign key constraint "transaksi_item_varian_id_fkey")
    for (int i = 0; i < varianIds.length; i += 50) {
      final batch = varianIds.sublist(i, (i + 50).clamp(0, varianIds.length));
      await client.from('transaksi_item').delete().inFilter('varian_id', batch);
    }

    // Sekarang aman hapus varian, stok_movement, lalu produk
    for (int i = 0; i < produkIds.length; i += 50) {
      final batch = produkIds.sublist(i, (i + 50).clamp(0, produkIds.length));
      await client.from('varian').delete().inFilter('produk_id', batch);
      await client.from('stok_movement').delete().inFilter('produk_id', batch);
    }
    await client.from('produk').delete().eq('toko_id', tokoId);
  }

  // Reset semua data: hapus produk, varian, stok_movement, transaksi, pengeluaran cabang ini
  static Future<void> resetSemuaData(String tokoId) async {
    // Hapus transaksi_item + transaksi DULU sebelum hapusProduk
    // (karena transaksi_item punya FK ke varian, dan FK ke transaksi)
    final trxList = await client.from('transaksi').select('id').eq('toko_id', tokoId);
    final trxIds = (trxList as List).map((t) => t['id'] as String).toList();
    if (trxIds.isNotEmpty) {
      for (int i = 0; i < trxIds.length; i += 50) {
        final batch = trxIds.sublist(i, (i + 50).clamp(0, trxIds.length));
        await client.from('transaksi_item').delete().inFilter('transaksi_id', batch);
      }
      await client.from('transaksi').delete().eq('toko_id', tokoId);
    }
    // Sekarang hapusProduk aman (transaksi_item sudah kosong)
    await hapusSemuaProduk(tokoId);
    await client.from('pengeluaran').delete().eq('toko_id', tokoId);
  }
}

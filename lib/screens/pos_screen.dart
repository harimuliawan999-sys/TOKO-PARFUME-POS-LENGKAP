import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'dart:io';
import '../services/api.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/offline_cache.dart';
import 'bluetooth_printer_screen.dart';

class POSScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const POSScreen({super.key, required this.toko, required this.user});
  @override State<POSScreen> createState() => _POSScreenState();
}

class _POSScreenState extends State<POSScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _produk = [], _varian = [], _pelangganList = [];
  final List<Map<String, dynamic>> _cart = [];
  String _search = '', _metode = 'Cash';
  String _filterKelas = 'semua';
  double _diskon = 0;
  Map<String, dynamic>? _pelanggan; // pelanggan terpilih untuk transaksi ini
  double _diskonMemberDipakai = 0; // berapa rupiah diskon member yg dipakai
  final _bayarCtrl = TextEditingController();
  bool _processing = false, _offline = false;
  int _pendingSync = 0;
  late StreamSubscription<List<ConnectivityResult>> _connSub;
  String? _qrisPath;
  String get tokoId => widget.toko['id'];

  @override
  void initState() {
    super.initState();
    _load();
    _loadQris();
    _loadPelanggan();
    _checkPending();
    // Auto-detect perubahan koneksi
    _connSub = Connectivity().onConnectivityChanged.listen((results) async {
      final isOnline = !results.contains(ConnectivityResult.none);
      if (!isOnline) {
        // Internet mati saat POS terbuka → langsung switch ke offline mode
        if (mounted) setState(() => _offline = true);
      } else if (_offline) {
        // Internet balik → tunggu stabil, reload, lalu sync
        await Future.delayed(const Duration(seconds: 2));
        await _load();
        if (!_offline) await _syncQueue();
      }
    });
  }

  @override
  void dispose() {
    _connSub.cancel();
    _bayarCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkPending() async {
    final q = await OfflineCache.getQueue();
    if (mounted) setState(() => _pendingSync = q.length);
  }

  Future<void> _syncQueue() async {
    final queue = await OfflineCache.getQueue();
    if (queue.isEmpty) return;
    int synced = 0;
    final failed = <Map<String, dynamic>>[];
    String? lastError;
    for (final trx in queue) {
      try {
        // Deep-cast items dari JSON — varian nested map harus di-cast ulang
        final rawItems = trx['items'] as List<dynamic>;
        final items = rawItems.map((i) {
          final m = Map<String, dynamic>.from(i as Map);
          m['varian'] = Map<String, dynamic>.from(m['varian'] as Map);
          return m;
        }).toList();

        await Api.prosesTransaksi(
          tokoId: trx['tokoId'] as String,
          user: Map<String, dynamic>.from(trx['user'] as Map),
          items: items,
          subtotal: (trx['subtotal'] as num).toDouble(),
          diskon: (trx['diskon'] as num).toDouble(),
          total: (trx['total'] as num).toDouble(),
          bayar: (trx['bayar'] as num).toDouble(),
          kembalian: (trx['kembalian'] as num).toDouble(),
          metode: trx['metode'] as String,
          pelangganNama: trx['pelangganNama'] as String?,
          pelangganId: trx['pelangganId'] as String?,
          diskonMemberDipakai: ((trx['diskonMemberDipakai'] ?? 0) as num).toDouble(),
          produkList: _produk,
        );
        synced++;
      } catch (e) {
        lastError = e.toString();
        failed.add(trx);
      }
    }
    await OfflineCache.clearQueue();
    for (final f in failed) { await OfflineCache.queueTransaction(f); }
    if (mounted) {
      setState(() => _pendingSync = failed.length);
      if (synced > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$synced transaksi offline berhasil disync ke Supabase!'),
          backgroundColor: const Color(0xFF27AE60), duration: const Duration(seconds: 4)));
        _load();
      } else if (failed.isNotEmpty && lastError != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sync gagal: $lastError'),
          backgroundColor: Colors.red, duration: const Duration(seconds: 6)));
      }
    }
  }

  Future<void> _load() async {
    // Cek koneksi
    try {
      final conn = await Connectivity().checkConnectivity();
      final isOnline = !conn.contains(ConnectivityResult.none);
      if (isOnline) {
        final res = await Future.wait([Api.getProduk(tokoId), Api.getVarian(tokoId)]);
        final p = res[0]; final v = res[1];
        // Simpan ke cache
        await Future.wait([OfflineCache.save('produk_$tokoId', p), OfflineCache.save('varian_$tokoId', v)]);
        if (mounted) setState(() { _produk = p; _varian = v; _offline = false; });
      } else {
        throw Exception('offline');
      }
    } catch (_) {
      // Fallback ke cache lokal
      final cp = await OfflineCache.load('produk_$tokoId');
      final cv = await OfflineCache.load('varian_$tokoId');
      if (mounted) {
        setState(() {
        _produk = cp != null ? List<Map<String, dynamic>>.from(cp) : [];
        _varian = cv != null ? List<Map<String, dynamic>>.from(cv) : [];
        _offline = true;
      });
      }
    }
  }

  Future<void> _loadQris() async {
    final path = await Api.getQrisPath();
    if (mounted) setState(() => _qrisPath = path);
  }

  Future<void> _loadPelanggan() async {
    try {
      final list = await Api.getPelanggan(tokoId);
      if (mounted) setState(() => _pelangganList = list);
    } catch (_) {}
  }

  double get _sub => _cart.fold(0, (s, c) => s + (c['hj'] as num) * (c['qty'] as int));
  double get _totalDiskon => _diskon + _diskonMemberDipakai;
  double get _total => (_sub - _totalDiskon).clamp(0, double.infinity);
  double get _bayar => double.tryParse(_bayarCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  double get _diskonMemberTersedia => _pelanggan == null ? 0 : Api.hitungDiskonTersedia(_pelanggan!);

  // ═══ DIALOG PILIH / TAMBAH PELANGGAN ═══
  Future<void> _pilihPelanggan() async {
    String search = '';
    final namaBaruCtrl = TextEditingController();
    final hpBaruCtrl = TextEditingController();
    bool modeBaru = false;
    bool saving = false;
    String? saveError;

    final hasil = await showDialog<Map<String, dynamic>?>(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) {
      final filtered = search.isEmpty ? _pelangganList :
        _pelangganList.where((p) => (p['nama'] ?? '').toString().toLowerCase().contains(search.toLowerCase())).toList();
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(modeBaru ? 'Tambah Pelanggan' : 'Pilih Pelanggan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context)),
        ]),
        content: SizedBox(width: double.maxFinite, child: modeBaru
          ? Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: namaBaruCtrl, autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama Pelanggan*', border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(controller: hpBaruCtrl, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'No. HP (opsional)', border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontSize: 13)),
              if (saveError != null) ...[
                const SizedBox(height: 8),
                Container(padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.error_outline, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(saveError!, style: const TextStyle(fontSize: 10, color: Colors.red))),
                  ])),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: saving ? null : () => setD(() { modeBaru = false; saveError = null; }),
                  child: const Text('< Kembali', style: TextStyle(fontSize: 11)))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: saving ? null : () async {
                  final nama = namaBaruCtrl.text.trim();
                  if (nama.isEmpty) {
                    setD(() => saveError = 'Nama wajib diisi');
                    return;
                  }
                  setD(() { saving = true; saveError = null; });
                  try {
                    final p = await Api.tambahPelangganBaruStrict(tokoId, nama, hp: hpBaruCtrl.text.trim());
                    if (!mounted) return;
                    await _loadPelanggan();
                    if (mounted) Navigator.pop(context, p);
                  } catch (e) {
                    setD(() { saving = false; saveError = 'Gagal simpan: $e'; });
                  }
                }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60)),
                  child: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Simpan', style: TextStyle(fontSize: 12)))),
              ]),
            ])
          : Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(onChanged: (v) => setD(() => search = v), autofocus: true,
                decoration: const InputDecoration(hintText: 'Cari nama pelanggan...', prefixIcon: Icon(Icons.search, size: 18), border: OutlineInputBorder(), isDense: true),
                style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              SizedBox(height: 260, child: filtered.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(16),
                    child: Text('Belum ada pelanggan.\nKlik tombol di bawah untuk tambah baru.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Color(0xFFA09080)))))
                : ListView.builder(itemCount: filtered.length, itemBuilder: (_, i) {
                    final p = filtered[i];
                    final tersedia = Api.hitungDiskonTersedia(p);
                    final totalBelanja = ((p['total_belanja'] ?? 0) as num).toDouble();
                    final jumlahTrx = ((p['jumlah_transaksi'] ?? 0) as num).toInt();
                    return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
                      onTap: () => Navigator.pop(context, p),
                      leading: CircleAvatar(radius: 16, backgroundColor: const Color(0xFFD4A574).withOpacity(0.2),
                        child: Text((p['nama'] ?? '?').toString()[0].toUpperCase(),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
                      title: Text(p['nama'] ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      subtitle: Text('$jumlahTrx trx · ${cur.format(totalBelanja)}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                      trailing: tersedia > 0
                        ? Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFF27AE60), borderRadius: BorderRadius.circular(4)),
                            child: Text(cur.format(tersedia), style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)))
                        : null,
                    ));
                  })),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton.icon(
                onPressed: () => setD(() => modeBaru = true),
                icon: const Icon(Icons.person_add, size: 14),
                label: const Text('+ Tambah Pelanggan Baru', style: TextStyle(fontSize: 11)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 8)))),
            ])),
      );
    }));

    if (hasil != null) {
      setState(() {
        _pelanggan = hasil;
        _diskonMemberDipakai = 0; // reset kalau ganti pelanggan
      });
    }
  }

  void _togglePakaiDiskonMember() {
    if (_pelanggan == null) return;
    if (_diskonMemberDipakai > 0) {
      setState(() => _diskonMemberDipakai = 0);
      return;
    }
    final tersedia = _diskonMemberTersedia;
    if (tersedia < 50000) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Belum ada diskon. Total belanja: ${cur.format(((_pelanggan!['total_belanja'] ?? 0) as num).toDouble())} (butuh kelipatan 500rb)'),
        backgroundColor: const Color(0xFFE67E22), duration: const Duration(seconds: 3)));
      return;
    }
    // Pakai 1 unit diskon = 50rb. Bisa pakai lebih kalau eligible.
    setState(() => _diskonMemberDipakai = 50000);
  }

  // ═══ CEK STOK SEBELUM TAMBAH KE KERANJANG ═══
  // Fuzzy token match: exact substring → 1-char-diff sliding window → subsequence
  bool _fuzzyTok(String haystack, String tok) {
    if (haystack.contains(tok)) return true;
    if (tok.length < 2) return false;
    // Sliding window: 1 typo allowed for token length >= 4
    if (tok.length >= 4) {
      final winLen = tok.length;
      for (int i = 0; i <= haystack.length - winLen; i++) {
        int diff = 0;
        for (int j = 0; j < winLen; j++) {
          if (haystack[i + j] != tok[j]) diff++;
          if (diff > 1) break;
        }
        if (diff <= 1) return true;
      }
    }
    // Subsequence: all chars of tok appear in order in haystack
    int j = 0;
    for (int i = 0; i < haystack.length && j < tok.length; i++) {
      if (haystack[i] == tok[j]) j++;
    }
    return j == tok.length;
  }

  bool _cekStokCukup(Map<String, dynamic> v, Map<String, dynamic> bibit, {int tambahQty = 1}) {
    final resepBibit = (v['resep_bibit'] as num?) ?? 0;
    final stokBibit = (bibit['stok'] as num?) ?? 0;
    // Hitung total bibit yang sudah di keranjang untuk produk ini
    double sudahDiKeranjang = 0;
    for (final c in _cart) {
      final cv = c['varian'] as Map<String, dynamic>?;
      if (cv != null && cv['produk_id'] == v['produk_id']) {
        sudahDiKeranjang += ((cv['resep_bibit'] as num?) ?? 0) * (c['qty'] as int);
      }
    }
    final totalButuh = sudahDiKeranjang + (resepBibit * tambahQty);
    return stokBibit >= totalButuh;
  }

  // Hitung daftar peringatan stok minus untuk cart parfum (tanpa blokir transaksi).
  // Return list pesan ringkas; kosong = aman.
  List<String> _hitungWarningParfum() {
    final perBibit = <String, double>{}; // produkId -> total bibit dibutuh
    final perBotol = <String, int>{};    // botolId -> total qty
    for (final c in _cart) {
      final v = c['varian'] as Map<String, dynamic>?;
      if (v == null) continue;
      final qty = (c['qty'] as int);
      final pid = v['produk_id']?.toString();
      final resep = ((v['resep_bibit'] as num?) ?? 0).toDouble();
      if (pid != null && resep > 0) {
        perBibit[pid] = (perBibit[pid] ?? 0) + resep * qty;
      }
      String? botolId = (v['resep_botol_id'] ?? '').toString();
      if (botolId.isEmpty) {
        // Auto-lookup botol by ukuran (samakan dgn api.dart)
        final ukuran = (v['ukuran'] ?? '').toString().toUpperCase();
        if (ukuran.isNotEmpty) {
          final mb = _produk.firstWhere(
            (p) => (p['nama'] ?? '').toString().toUpperCase().contains('BOTOL') &&
                   (p['nama'] ?? '').toString().toUpperCase().contains(ukuran),
            orElse: () => {});
          if (mb.isNotEmpty) botolId = mb['id'].toString();
        }
      }
      if (botolId.isNotEmpty) {
        perBotol[botolId] = (perBotol[botolId] ?? 0) + qty;
      }
    }
    final warns = <String>[];
    perBibit.forEach((pid, butuh) {
      final p = _produk.firstWhere((x) => x['id'].toString() == pid, orElse: () => {});
      if (p.isEmpty) return;
      final stok = ((p['stok'] ?? 0) as num).toDouble();
      if (stok < butuh) {
        final sisa = (stok - butuh);
        warns.add('${p['nama']}: stok ${stok.toInt()}ml, butuh ${butuh.toInt()}ml (jadi ${sisa.toInt()}ml)');
      }
    });
    perBotol.forEach((bid, butuh) {
      final b = _produk.firstWhere((x) => x['id'].toString() == bid, orElse: () => {});
      if (b.isEmpty) return;
      final stok = ((b['stok'] ?? 0) as num).toInt();
      if (stok < butuh) {
        warns.add('${b['nama']}: stok $stok pcs, butuh $butuh pcs (jadi ${stok - butuh})');
      }
    });
    return warns;
  }

  void _showWarningStokMinus(List<String> warns) {
    if (warns.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: const Color(0xFFE67E22),
      duration: const Duration(seconds: 6),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.warning_amber, color: Colors.white, size: 16),
          SizedBox(width: 6),
          Text('Stok minus — segera restock!', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
        ]),
        const SizedBox(height: 4),
        ...warns.take(4).map((w) => Padding(
          padding: const EdgeInsets.only(left: 22, top: 1),
          child: Text('• $w', style: const TextStyle(fontSize: 11)))),
        if (warns.length > 4) Padding(
          padding: const EdgeInsets.only(left: 22, top: 2),
          child: Text('+ ${warns.length - 4} item lain', style: const TextStyle(fontSize: 10))),
      ]),
    ));
  }

  void _pilihVarian(String produkId) async {
    final vs = _varian.where((v) => v['produk_id']?.toString() == produkId.toString()).toList();
    final bibit = _produk.firstWhere((p) => p['id'] == produkId, orElse: () => {});
    if (vs.isEmpty) return;

    // Sort ukuran by ml value (15ml, 20ml, 25ml, 30ml...)
    int ukuranValue(String uk) {
      final m = RegExp(r'(\d+)').firstMatch(uk);
      return m != null ? int.parse(m.group(1)!) : 9999;
    }
    final uks = vs.map((v) => (v['ukuran'] ?? '').toString()).toSet().toList()
      ..sort((a, b) => ukuranValue(a).compareTo(ukuranValue(b)));

    // Sort kualitas by fixed order
    const kualitasOrder = ['Medium', 'Super', 'Platinum', 'Full Bibit'];
    int kualitasIdx(String k) {
      final i = kualitasOrder.indexWhere((q) => q.toLowerCase() == k.toLowerCase());
      return i < 0 ? 999 : i;
    }
    
    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (_, ctrl) => Padding(padding: const EdgeInsets.all(20), child: ListView(controller: ctrl, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Pilih Ukuran & Kualitas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]),
          // Info stok bibit — hanya untuk OWNER (kasir tidak perlu lihat angka stok)
          if (bibit.isNotEmpty && widget.user['peran'] == 'owner') Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
            child: Text('Stok bibit: ${bibit['stok']} ${bibit['satuan'] ?? 'ml'}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: (bibit['stok'] as num) <= 0 ? Colors.red : (bibit['stok'] as num) <= (bibit['min_stok'] as num) ? Colors.orange : Colors.green))),
          for (final uk in uks) ...[
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(6)),
              child: Text(uk, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B5B4B)))),
            Wrap(spacing: 8, runSpacing: 8, children: (vs.where((v) => v['ukuran'] == uk).toList()
              ..sort((a, b) => kualitasIdx(a['kualitas'] ?? '').compareTo(kualitasIdx(b['kualitas'] ?? ''))))
              .map((v) {
              final stokCukup = bibit.isNotEmpty && _cekStokCukup(v, bibit);
              return GestureDetector(
                onTap: () {
                  _addCart(v);
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('OK ${v['nama']} ${v['ukuran']} ${v['kualitas']} ditambahkan${stokCukup ? '' : ' (STOK MINUS)'}'),
                    backgroundColor: stokCukup ? const Color(0xFF27AE60) : Colors.orange, duration: const Duration(seconds: 1)));
                },
                child: Container(width: 110, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: stokCukup ? const Color(0xFFE8E0D8) : Colors.red.withOpacity(0.5))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(v['kualitas'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text(cur.format(v['harga_jual'] ?? 0), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
                    Text('Bibit: ${v['resep_bibit']}ml${stokCukup ? '' : ' !'}', style: TextStyle(fontSize: 9, color: stokCukup ? const Color(0xFFA09080) : Colors.red)),
                    if (!stokCukup) const Text('HABIS', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.red)),
                  ])));
            }).toList()),
            const SizedBox(height: 12),
          ],
        ]))));
  }

  void _addCart(Map<String, dynamic> v) {
    final idx = _cart.indexWhere((c) => c['vid'] == v['id']);
    setState(() {
      if (idx >= 0) { _cart[idx] = {..._cart[idx], 'qty': (_cart[idx]['qty'] as int) + 1}; }
      else { _cart.add({'vid': v['id'], 'varian': v, 'nama': '${v['nama']} ${v['ukuran']} ${v['kualitas']}', 'hj': (v['harga_jual'] as num).toDouble(), 'qty': 1}); }
    });
  }

  // ═══ TAMPILKAN QRIS ═══
  void _showQris() {
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Scan QRIS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFD4A574), borderRadius: BorderRadius.circular(8)),
          child: Text('Total: ${cur.format(_total)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white))),
        const SizedBox(height: 12),
        if (_qrisPath != null && File(_qrisPath!).existsSync())
          ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_qrisPath!), height: 280, fit: BoxFit.contain))
        else
          Container(height: 200, decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8E0D8))),
            child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.qr_code_2, size: 50, color: Color(0xFFA09080)),
              SizedBox(height: 8),
              Text('QRIS belum di-setup', style: TextStyle(fontSize: 12, color: Color(0xFFA09080))),
              Text('Buka Pengaturan → Upload QRIS', style: TextStyle(fontSize: 10, color: Color(0xFFA09080)))]))),
        const SizedBox(height: 12),
        const Text('Minta customer scan QR di atas', style: TextStyle(fontSize: 11, color: Color(0xFF6B5B4B))),
      ]),
      actions: [
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: () { Navigator.pop(context); _bayarSekarang(); },
          child: const Text('Sudah Bayar', style: TextStyle(fontWeight: FontWeight.w700)))),
      ]));
  }

  Future<void> _bayarSekarang() async {
    if (_cart.isEmpty || _processing) return;
    // Untuk QRIS & Transfer, tidak perlu input bayar
    if (_metode == 'Cash' && _bayar < _total) return;
    final bayarFinal = _metode == 'Cash' ? _bayar : _total;

    // ─── OFFLINE MODE: simpan ke antrian, cetak tetap jalan ───
    if (_offline) {
      final nota = 'OFF-${DateFormat('HHmmss').format(DateTime.now())}';
      await OfflineCache.queueTransaction({
        'tokoId': tokoId,
        'user': widget.user,
        'items': _cart.map((c) => {'varian': c['varian'], 'qty': c['qty']}).toList(),
        'subtotal': _sub, 'diskon': _totalDiskon, 'total': _total,
        'bayar': bayarFinal, 'kembalian': bayarFinal - _total, 'metode': _metode,
        if (_pelanggan != null) 'pelangganId': _pelanggan!['id'],
        if (_pelanggan != null) 'pelangganNama': _pelanggan!['nama'],
        if (_diskonMemberDipakai > 0) 'diskonMemberDipakai': _diskonMemberDipakai,
      });
      await _checkPending();
      if (!mounted) return;
      final jamNow = DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(DateTime.now());
      final cartCopy = List<Map<String, dynamic>>.from(_cart);
      final totalCopy = _total; final metodeCopy = _metode;
      final subCopy = _sub; final diskonCopy = _totalDiskon;
      final pelangganCopy = _pelanggan?['nama']?.toString();
      final bayarCopy = bayarFinal; final kembalianCopy = bayarFinal - _total;
      showDialog(context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 50, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: const Color(0xFFC0392B)),
            child: const Center(child: Text('KS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)))),
          const SizedBox(height: 6),
          const Text('KS PARFUME', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 3, color: Color(0xFF3A2E24))),
          const Divider(height: 16),
          const Icon(Icons.check_circle_outline, color: Color(0xFFE67E22), size: 50), const SizedBox(height: 8),
          const Text('Transaksi Disimpan (Offline)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFE67E22))),
          Text('$nota — akan sync otomatis saat online', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
          Text(jamNow, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
          const SizedBox(height: 8),
          Text(cur.format(totalCopy), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF27AE60))),
          if (metodeCopy == 'Cash' && kembalianCopy > 0) Text('Kembalian: ${cur.format(kembalianCopy)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFD4A574))),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(flex: 2, child: ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                final btService = BluetoothPrinterService();
                final savedName = await btService.getSavedName();
                if (savedName != null) {
                  _cetakBluetooth(nota, totalCopy, bayarCopy, kembalianCopy, metodeCopy, cartCopy, subtotal: subCopy, diskon: diskonCopy, pelanggan: pelangganCopy);
                } else {
                  _cetakStrukSaved(nota, totalCopy, metodeCopy, cartCopy, subtotal: subCopy, diskon: diskonCopy, pelanggan: pelangganCopy);
                }
              },
              icon: const Icon(Icons.print, size: 18), label: const Text('Cetak Struk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 10)))),
            const SizedBox(width: 6),
            Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup', style: TextStyle(fontSize: 11)))),
          ]),
        ])));
      setState(() { _cart.clear(); _bayarCtrl.clear(); _diskon = 0; _pelanggan = null; _diskonMemberDipakai = 0; });
      return;
    }

    // Tampilkan warning kalau ada item yang akan bikin stok minus (TIDAK blokir)
    final warnsParfum = _hitungWarningParfum();

    setState(() => _processing = true);
    try {
      final nota = await Api.prosesTransaksi(tokoId: tokoId, user: widget.user,
        items: _cart.map((c) => {'varian': c['varian'], 'qty': c['qty']}).toList(),
        subtotal: _sub, diskon: _totalDiskon, total: _total, bayar: bayarFinal, kembalian: bayarFinal - _total, metode: _metode,
        pelangganNama: _pelanggan?['nama'],
        pelangganId: _pelanggan?['id'],
        diskonMemberDipakai: _diskonMemberDipakai,
        produkList: _produk);
      if (mounted) {
        final jamNow = DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(DateTime.now());
        final cartCopy = List<Map<String, dynamic>>.from(_cart);
        final totalCopy = _total;
        final subCopy = _sub;
        final diskonCopy = _totalDiskon;
        final pelangganCopy = _pelanggan?['nama']?.toString();
        final metodeCopy = _metode;
        final bayarCopy = bayarFinal;
        final kembalianCopy = bayarFinal - _total;
        showDialog(context: context, builder: (_) => AlertDialog(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            // Logo KS
            Container(width: 50, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)])),
              child: const Center(child: Text('KS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)))),
            const SizedBox(height: 6),
            const Text('KS PARFUME', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 3, color: Color(0xFF3A2E24))),
            const Divider(height: 16),
            const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 50), const SizedBox(height: 8),
            const Text('Pembayaran Berhasil!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(nota, style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
            Text(jamNow, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            const SizedBox(height: 8),
            Text(cur.format(totalCopy), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF27AE60))),
            if (metodeCopy == 'Cash' && bayarFinal - totalCopy > 0) Text('Kembalian: ${cur.format(bayarFinal - totalCopy)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFD4A574))),
            const SizedBox(height: 4),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: const Color(0xFFD4A574).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: Text(metodeCopy, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD4A574)))),
            const SizedBox(height: 16),
            // ── Tombol Cetak Smart (BT > PDF fallback) ──
            Row(children: [
              Expanded(flex: 2, child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(context);
                  // Try Bluetooth first
                  final btService = BluetoothPrinterService();
                  final savedName = await btService.getSavedName();
                  if (savedName != null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Mencoba Bluetooth...'), duration: Duration(seconds: 2), backgroundColor: Color(0xFF2980B9)));
                    }
                    _cetakBluetooth(nota, totalCopy, bayarCopy, kembalianCopy, metodeCopy, cartCopy, subtotal: subCopy, diskon: diskonCopy, pelanggan: pelangganCopy);
                  } else {
                    // Fallback to PDF
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Printer BT belum diatur — pakai PDF'), duration: Duration(seconds: 2), backgroundColor: Color(0xFFE67E22)));
                    }
                    _cetakStrukSaved(nota, totalCopy, metodeCopy, cartCopy, subtotal: subCopy, diskon: diskonCopy, pelanggan: pelangganCopy);
                  }
                },
                icon: const Icon(Icons.print, size: 18), label: const Text('Cetak Struk', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 10)))),
              const SizedBox(width: 6),
              Expanded(child: OutlinedButton.icon(
                onPressed: () => _cetakStrukSaved(nota, totalCopy, metodeCopy, cartCopy, subtotal: subCopy, diskon: diskonCopy, pelanggan: pelangganCopy),
                icon: const Icon(Icons.picture_as_pdf, size: 14), label: const Text('PDF', style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574))))),
              const SizedBox(width: 6),
              Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup', style: TextStyle(fontSize: 11)))),
            ]),
          ])));
        setState(() { _cart.clear(); _bayarCtrl.clear(); _diskon = 0; _pelanggan = null; _diskonMemberDipakai = 0; });
        _load();
        _loadPelanggan(); // refresh data pelanggan agar total_belanja terupdate
        if (warnsParfum.isNotEmpty) _showWarningStokMinus(warnsParfum);
      }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red)); }
    setState(() => _processing = false);
  }

  // ═══ CETAK STRUK BLUETOOTH ═══
  Future<void> _cetakBluetooth(String nota, double total, double bayar, double kembalian, String metode, List<Map<String, dynamic>> cartItems, {double? subtotal, double? diskon, String? pelanggan}) async {
    final jamStr  = DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now());
    final kasir   = widget.user['nama'] ?? 'Kasir';
    final alamat  = widget.toko['alamat'] ?? '';

    // Tampilkan loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Row(children: [SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 12), Text('Mengirim ke printer...')]),
        duration: Duration(seconds: 10), backgroundColor: Color(0xFF2980B9)));
    }

    final err = await BluetoothPrinterService().printStruk(
      nota: nota, tokoNama: widget.toko['nama'] ?? 'KS Parfume',
      tokoAlamat: alamat, items: cartItems,
      subtotal: subtotal, diskon: diskon, pelanggan: pelanggan,
      total: total, bayar: bayar, kembalian: kembalian,
      metode: metode, jam: jamStr, kasir: kasir);

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Struk berhasil dicetak!'), backgroundColor: Color(0xFF27AE60)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), backgroundColor: Colors.red, duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Setup Printer', textColor: Colors.white,
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothPrinterScreen()));
            })));
    }
  }

  // ═══ CETAK STRUK PDF ═══
  Future<void> _cetakStrukSaved(String nota, double total, String metode, List<Map<String, dynamic>> cartItems, {double? subtotal, double? diskon, String? pelanggan}) async {
    final pdf = pw.Document();
    final jamStr = DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(DateTime.now());
    final showDiskon = diskon != null && diskon > 0;
    final showPelanggan = pelanggan != null && pelanggan.isNotEmpty && pelanggan.toLowerCase() != 'walk-in';
    pdf.addPage(pw.Page(pageFormat: const PdfPageFormat(72 * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
        pw.Text('KS PARFUME', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(widget.toko['nama'] ?? '', style: const pw.TextStyle(fontSize: 8)),
        pw.Divider(), pw.SizedBox(height: 4),
        pw.Text(nota, style: const pw.TextStyle(fontSize: 8)),
        pw.Text(jamStr, style: const pw.TextStyle(fontSize: 8)),
        if (showPelanggan) pw.Text('Pelanggan: $pelanggan', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 4), pw.Divider(),
        ...cartItems.map((c) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Expanded(child: pw.Text(c['nama'], style: const pw.TextStyle(fontSize: 7))),
          pw.Text('x${c['qty']}', style: const pw.TextStyle(fontSize: 7)),
          pw.Text(cur.format((c['hj'] as num) * (c['qty'] as int)), style: const pw.TextStyle(fontSize: 7)),
        ])),
        pw.Divider(),
        if (showDiskon) ...[
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 8)),
            pw.Text(cur.format(subtotal ?? (total + diskon)), style: const pw.TextStyle(fontSize: 8))]),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Diskon', style: const pw.TextStyle(fontSize: 8)),
            pw.Text('- ${cur.format(diskon)}', style: const pw.TextStyle(fontSize: 8))]),
        ],
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
          pw.Text(cur.format(total), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))]),
        pw.SizedBox(height: 2),
        pw.Text('Bayar: $metode', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 8),
        pw.Text('Terima kasih!', style: const pw.TextStyle(fontSize: 8)),
      ])));
    await Printing.layoutPdf(onLayout: (_) async => pdf.save());
  }

  // ═══ VOID / PEMBATALAN ═══
  void _voidItem(int index) {
    final c = _cart[index];
    final alasanCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Batal Pesanan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Apakah alasan pembatalan item ini?', style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        const SizedBox(height: 6),
        Text(c['nama'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(controller: alasanCtrl, maxLines: 2,
          decoration: InputDecoration(hintText: 'Alasan pembatalan...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('BATAL')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(context);
          // Catat pembatalan ke DB
          try {
            final v = c['varian'] as Map<String, dynamic>?;
            await Api.addPembatalan(
              tokoId: tokoId, namaItem: c['nama'], qty: c['qty'] as int,
              harga: (c['hj'] as num).toDouble(), alasan: alasanCtrl.text.isEmpty ? 'Tidak jadi beli' : alasanCtrl.text,
              userId: widget.user['id'], userNama: widget.user['nama'],
              varianId: v?['id'], produkId: v?['produk_id']);
          } catch (_) {}
          setState(() => _cart.removeAt(index));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item dibatalkan'), backgroundColor: Color(0xFFC0392B)));
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
          child: const Text('KONFIRMASI')),
      ]));
  }

  // ═══ JUAL BIBIT LANGSUNG ═══
  void _jualBibit() {
    final bibitList = _produk.where((p) => p['kategori'] == 'STOCK PARFUME').toList();
    final botolList = _produk.where((p) => p['kategori'] == 'STOK BOTOL').toList();
    String? selectedId;
    String? selectedBotolId;
    String searchBibit = '';
    final qtyCtrl = TextEditingController(text: '1');
    final hargaCtrl = TextEditingController();
    final bayarBibitCtrl = TextEditingController();
    final diskonBibitCtrl = TextEditingController();
    String metodeBibit = 'Cash';
    double diskonBibit = 0;
    Map<String, dynamic>? pelangganBibit;
    double diskonMemberBibit = 0;
    final keranjangBibit = <Map<String, dynamic>>[];

    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) {
      final filteredBibit = searchBibit.isEmpty
          ? bibitList
          : bibitList.where((p) {
              final nm = (p['nama'] ?? '').toString().toLowerCase();
              final q = searchBibit.toLowerCase();
              return q.split(' ').every((kata) => nm.contains(kata));
            }).toList();
      final selectedBibit = selectedId != null
          ? bibitList.firstWhere((p) => p['id'].toString() == selectedId, orElse: () => {})
          : {};

      void bayarSekarang() async {
        final totalK = keranjangBibit.fold(0.0, (double s, item) => s + (item['harga'] as double) * (item['qty'] as int));
        final totalDiskonBibit = diskonBibit + diskonMemberBibit;
        final totalSetelahDiskon = (totalK - totalDiskonBibit).clamp(0.0, double.infinity);
        final bayarAmt = metodeBibit == 'Cash'
            ? (double.tryParse(bayarBibitCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0)
            : totalSetelahDiskon;
        if (metodeBibit == 'Cash' && bayarAmt < totalSetelahDiskon) return;

        // Hitung peringatan stok minus (TIDAK blokir)
        final warnsBibit = <String>[];
        final perBibit = <String, int>{};
        final perBotol = <String, int>{};
        for (final item in keranjangBibit) {
          final pid = item['produkId'] as String;
          final qty = item['qty'] as int;
          perBibit[pid] = (perBibit[pid] ?? 0) + qty;
          final bid = item['botolId'] as String?;
          if (bid != null && bid.isNotEmpty) perBotol[bid] = (perBotol[bid] ?? 0) + qty;
        }
        perBibit.forEach((pid, butuh) {
          final p = _produk.firstWhere((x) => x['id'].toString() == pid, orElse: () => {});
          if (p.isEmpty) return;
          final stok = ((p['stok'] ?? 0) as num).toInt();
          if (stok < butuh) {
            warnsBibit.add('${p['nama']}: stok $stok ml, butuh $butuh ml (jadi ${stok - butuh})');
          }
        });
        perBotol.forEach((bid, butuh) {
          final b = _produk.firstWhere((x) => x['id'].toString() == bid, orElse: () => {});
          if (b.isEmpty) return;
          final stok = ((b['stok'] ?? 0) as num).toInt();
          if (stok < butuh) {
            warnsBibit.add('${b['nama']}: stok $stok pcs, butuh $butuh pcs (jadi ${stok - butuh})');
          }
        });

        Navigator.pop(context);
        try {
          final items = keranjangBibit.map((item) => {
            'produkId': item['produkId'] as String,
            'qty': item['qty'] as int,
            'hargaJual': item['harga'] as double,
            'botolId': item['botolId'] as String?,
          }).toList();
          final nota = await Api.jualBibitMulti(
            tokoId: tokoId, user: widget.user,
            items: items, totalBayar: totalK,
            diskon: totalDiskonBibit,
            bayar: bayarAmt, metode: metodeBibit,
            pelangganNama: pelangganBibit?['nama'],
            pelangganId: pelangganBibit?['id'],
            diskonMemberDipakai: diskonMemberBibit);
          _load();
          _loadPelanggan();
          if (mounted && warnsBibit.isNotEmpty) _showWarningStokMinus(warnsBibit);
          if (!mounted) return;
          final jamNow = DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(DateTime.now());
          final cartItems = keranjangBibit.map((item) => {
            'nama': '${item['nama']} (bibit)', 'hj': item['harga'], 'qty': item['qty']
          }).toList();
          showDialog(context: context, builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 50, height: 50,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)])),
                child: const Center(child: Text('KS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)))),
              const SizedBox(height: 6),
              const Text('KS PARFUME', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 3, color: Color(0xFF3A2E24))),
              const Divider(height: 16),
              const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 50),
              const SizedBox(height: 8),
              const Text('Bibit Terjual!', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              Text(nota, style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
              Text(jamNow, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
              const SizedBox(height: 8),
              if (totalDiskonBibit > 0) ...[
                Text(cur.format(totalK), style: const TextStyle(fontSize: 14, color: Color(0xFFA09080), decoration: TextDecoration.lineThrough)),
                Text('Diskon: -${cur.format(totalDiskonBibit)}', style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
              ],
              if (pelangganBibit != null) Text('Pelanggan: ${pelangganBibit?['nama']}', style: const TextStyle(fontSize: 11, color: Color(0xFFD4A574), fontWeight: FontWeight.w600)),
              Text(cur.format(totalSetelahDiskon), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF27AE60))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _cetakBluetooth(nota, totalSetelahDiskon, bayarAmt, (bayarAmt - totalSetelahDiskon).clamp(0, double.infinity), metodeBibit, cartItems, subtotal: totalK, diskon: totalDiskonBibit, pelanggan: pelangganBibit?['nama']?.toString());
                  },
                  icon: const Icon(Icons.print, size: 16), label: const Text('Cetak', style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574))))),
                const SizedBox(width: 8),
                Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))),
              ]),
            ])));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
        }
      }

      // Hitung diskon member tersedia
      final diskonMemberTersediaBibit = pelangganBibit == null ? 0.0 : Api.hitungDiskonTersedia(pelangganBibit!);

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Jual Bibit Langsung', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          // ═══ PELANGGAN ═══
          InkWell(
            onTap: () async {
              await _pilihPelanggan();
              setD(() {
                pelangganBibit = _pelanggan;
                diskonMemberBibit = 0;
                _pelanggan = null; // reset di parent agar tidak bentrok
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: pelangganBibit != null ? const Color(0xFFD4A574).withOpacity(0.08) : const Color(0xFFFAF8F5),
                border: Border.all(color: pelangganBibit != null ? const Color(0xFFD4A574) : const Color(0xFFE8E0D8)),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(pelangganBibit != null ? Icons.person : Icons.person_outline, size: 16,
                  color: pelangganBibit != null ? const Color(0xFFD4A574) : const Color(0xFFA09080)),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(pelangganBibit?['nama'] ?? 'Pilih Pelanggan (opsional)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: pelangganBibit != null ? const Color(0xFF3A2E24) : const Color(0xFFA09080))),
                  if (pelangganBibit != null)
                    Text('Total: ${cur.format(((pelangganBibit!['total_belanja'] ?? 0) as num).toDouble())} · Diskon: ${cur.format(diskonMemberTersediaBibit)}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                ])),
                if (pelangganBibit != null) IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => setD(() { pelangganBibit = null; diskonMemberBibit = 0; }),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24)),
              ]))),
          if (pelangganBibit != null && (diskonMemberTersediaBibit >= 50000 || diskonMemberBibit > 0))
            Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () {
                if (diskonMemberBibit > 0) {
                  setD(() => diskonMemberBibit = 0);
                } else if (diskonMemberTersediaBibit >= 50000) {
                  setD(() => diskonMemberBibit = 50000);
                }
              },
              icon: Icon(diskonMemberBibit > 0 ? Icons.check_box : Icons.check_box_outline_blank, size: 14),
              label: Text(diskonMemberBibit > 0
                ? 'Diskon Member: -${cur.format(diskonMemberBibit)} (klik batal)'
                : 'Pakai Diskon Member 50rb',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF27AE60),
                side: const BorderSide(color: Color(0xFF27AE60)),
                padding: const EdgeInsets.symmetric(vertical: 6))))),

          // Search bibit
          TextField(
            onChanged: (v) => setD(() { searchBibit = v; selectedId = null; hargaCtrl.clear(); }),
            decoration: const InputDecoration(
              labelText: 'Cari Bibit', prefixIcon: Icon(Icons.search, size: 18),
              border: OutlineInputBorder(), isDense: true, hintText: 'Ketik nama bibit...'),
            style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),

          // Selected bibit card or filtered list
          if (selectedBibit.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFD4A574).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD4A574))),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${selectedBibit['nama']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Row(children: [
                    Text('Stok: ${selectedBibit['stok']} ml', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                    const SizedBox(width: 8),
                    Builder(builder: (_) {
                      final hj2 = ((selectedBibit['harga_jual_bibit'] ?? 0) as num).toDouble();
                      final hb2 = ((selectedBibit['harga_beli'] ?? 0) as num).toDouble();
                      final dsp = hj2 > 0 ? hj2 : hb2;
                      return Text(dsp > 0 ? 'Jual: ${cur.format(dsp)}/ml' : 'Harga belum diset',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                          color: dsp > 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B)));
                    }),
                  ]),
                ])),
                IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setD(() { selectedId = null; hargaCtrl.clear(); })),
              ]))
          else
            SizedBox(
              height: filteredBibit.isEmpty ? 40 : (filteredBibit.length * 44.0).clamp(44, 180),
              child: filteredBibit.isEmpty
                ? const Center(child: Text('Tidak ada bibit', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredBibit.length,
                    itemBuilder: (_, i) {
                      final p = filteredBibit[i];
                      final hj = ((p['harga_jual_bibit'] ?? 0) as num).toDouble();
                      final hb = ((p['harga_beli'] ?? 0) as num).toDouble();
                      final displayHarga = hj > 0 ? hj : hb;
                      return InkWell(
                        onTap: () => setD(() {
                          selectedId = p['id'].toString();
                          if (displayHarga > 0) hargaCtrl.text = displayHarga.toStringAsFixed(0);
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0EBE4)))),
                          child: Row(children: [
                            Expanded(child: Text('${p['nama']}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                              Text('${p['stok']} ml', style: const TextStyle(fontSize: 9, color: Color(0xFF27AE60))),
                              Text(displayHarga > 0 ? cur.format(displayHarga) : '-', style: const TextStyle(fontSize: 9, color: Color(0xFFD4A574))),
                            ]),
                          ])));
                    })),
          const SizedBox(height: 10),

          // Botol dropdown
          DropdownButtonFormField<String>(
            value: selectedBotolId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Pilih Botol (opsional)',
              prefixIcon: Icon(Icons.local_drink, size: 18),
              border: OutlineInputBorder(), isDense: true),
            style: const TextStyle(fontSize: 12, color: Colors.black),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('-- Tanpa Botol --', style: TextStyle(fontSize: 11))),
              ...botolList.map((b) => DropdownMenuItem<String>(
                value: b['id'].toString(),
                child: Text('${b['nama']}  (stok: ${b['stok']})',
                  style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setD(() => selectedBotolId = v),
          ),
          const SizedBox(height: 10),
          TextField(controller: qtyCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Qty (ml)', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 10),
          TextField(controller: hargaCtrl, keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Harga Jual (Rp/ml)', border: OutlineInputBorder(), isDense: true,
              hintText: 'Auto dari sell_price bibit'),
            style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 10),

          // Tambah ke Keranjang
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () {
              if (selectedId == null || hargaCtrl.text.isEmpty) return;
              final qty = int.tryParse(qtyCtrl.text) ?? 1;
              final harga = double.tryParse(hargaCtrl.text) ?? 0;
              if (qty <= 0 || harga <= 0) return;
              final bibit = bibitList.firstWhere((p) => p['id'].toString() == selectedId, orElse: () => {'nama': 'Bibit'});
              setD(() {
                keranjangBibit.add({
                  'produkId': selectedId!,
                  'nama': bibit['nama'] ?? 'Bibit',
                  'qty': qty,
                  'harga': harga,
                  'botolId': selectedBotolId,
                });
                selectedId = null;
                selectedBotolId = null;
                hargaCtrl.clear();
                qtyCtrl.text = '1';
              });
            },
            icon: const Icon(Icons.add_shopping_cart, size: 16),
            label: const Text('Tambah ke Keranjang', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 8)),
          )),

          // Keranjang section
          if (keranjangBibit.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Keranjang (${keranjangBibit.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
              TextButton(onPressed: () => setD(() => keranjangBibit.clear()), child: const Text('Hapus Semua', style: TextStyle(fontSize: 10, color: Colors.red))),
            ]),
            ...keranjangBibit.asMap().entries.map((e) {
              final idx = e.key;
              final item = e.value;
              final subtotal = (item['harga'] as double) * (item['qty'] as int);
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${item['nama']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    Text('${item['qty']} ml × ${cur.format(item['harga'])} = ${cur.format(subtotal)}',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF6B5B4B))),
                    if (item['botolId'] != null) Builder(builder: (_) {
                      final botol = botolList.firstWhere((b) => b['id'].toString() == item['botolId'], orElse: () => {});
                      return Text('Botol: ${botol.isNotEmpty ? botol['nama'] : '-'}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080)));
                    }),
                  ])),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                    onPressed: () => setD(() => keranjangBibit.removeAt(idx)),
                    iconSize: 20, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28)),
                ]));
            }),
            const Divider(),
            Builder(builder: (_) {
              final totalK = keranjangBibit.fold(0.0, (double s, item) => s + (item['harga'] as double) * (item['qty'] as int));
              final totalSetelahDiskon = (totalK - diskonBibit).clamp(0.0, double.infinity);
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('TOTAL', style: TextStyle(fontSize: 13, color: Color(0xFF6B5B4B))),
                  Text(cur.format(totalK), style: const TextStyle(fontSize: 13, color: Color(0xFF6B5B4B))),
                ]),
                const SizedBox(height: 6),
                Row(children: [
                  const Text('Diskon  ', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
                  Expanded(child: TextField(
                    controller: diskonBibitCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setD(() => diskonBibit = double.tryParse(v.replaceAll(RegExp(r'[^\d]'), '')) ?? 0),
                    decoration: InputDecoration(
                      hintText: '0', prefixText: 'Rp ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), isDense: true),
                    style: const TextStyle(fontSize: 11))),
                ]),
                if (diskonBibit > 0) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Diskon', style: TextStyle(fontSize: 11, color: Color(0xFFC0392B))),
                    Text('-${cur.format(diskonBibit)}', style: const TextStyle(fontSize: 11, color: Color(0xFFC0392B))),
                  ]),
                ],
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('BAYAR', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
                  Text(cur.format(totalSetelahDiskon), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
                ]),
              ]);
            }),
            const SizedBox(height: 10),
            Row(children: ['Cash', 'QRIS', 'Transfer'].map((m) => Expanded(child: GestureDetector(
              onTap: () => setD(() => metodeBibit = m),
              child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: metodeBibit == m ? const Color(0xFFD4A574) : const Color(0xFFE8E0D8)),
                  color: metodeBibit == m ? const Color(0xFFD4A574) : Colors.white),
                child: Center(child: Text(m, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                  color: metodeBibit == m ? Colors.white : const Color(0xFF6B5B4B)))))))).toList()),
            if (metodeBibit == 'Cash') ...[
              const SizedBox(height: 8),
              TextField(
                controller: bayarBibitCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => setD(() {}),
                decoration: const InputDecoration(
                  labelText: 'Jumlah Bayar', prefixText: 'Rp ',
                  border: OutlineInputBorder(), isDense: true),
                style: const TextStyle(fontSize: 13)),
            ],
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: bayarSekarang,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
              child: const Text('Bayar Sekarang', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ]);
    }));
  }

  @override
  Widget build(BuildContext context) {
    final pids = _varian.map((v) => v['produk_id']?.toString() ?? '').toSet();
    // Fuzzy search: toleran typo, any word order, strip BIBIT prefix
    final searchTokens = _search.toLowerCase().trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final prods = _produk.where((p) {
      if (!pids.contains(p['id']?.toString() ?? '')) return false;
      // Filter PREMIUM / REGULER
      if (_filterKelas != 'semua') {
        final nama = (p['nama'] ?? '').toString().toUpperCase();
        final kelas = (p['kelas'] ?? '').toString().toUpperCase();
        final isPremium = nama.contains('PREMIUM') || kelas == 'PREMIUM';
        if (_filterKelas == 'PREMIUM' && !isPremium) return false;
        if (_filterKelas == 'REGULER' && isPremium) return false;
      }
      if (searchTokens.isEmpty) return true;
      final nama = (p['nama'] ?? '').toString().toLowerCase().replaceFirst('bibit ', '');
      return searchTokens.every((tok) => _fuzzyTok(nama, tok));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir / POS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.person_outline, size: 20), onPressed: _pilihPelanggan, tooltip: 'Pilih Pelanggan'),
          IconButton(icon: const Icon(Icons.science, size: 20), onPressed: _jualBibit, tooltip: 'Jual Bibit'),
        ]),
      body: Column(children: [
        if (_offline) Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
          color: const Color(0xFFC0392B),
          child: Row(children: [
            const Icon(Icons.cloud_off, color: Colors.white, size: 14), const SizedBox(width: 6),
            Expanded(child: Text('Mode Offline${_pendingSync > 0 ? ' · $_pendingSync trx pending' : ''}', style: const TextStyle(color: Colors.white, fontSize: 11))),
            GestureDetector(
              onTap: () async { await _load(); if (!_offline) await _syncQueue(); },
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                child: const Text('Sync', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)))),
          ])),
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child:
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final k in ['semua', 'PREMIUM', 'REGULER'])
              Padding(padding: const EdgeInsets.only(right: 6), child: ChoiceChip(
                label: Text(k == 'semua' ? 'Semua' : k,
                  style: TextStyle(fontSize: 10, color: _filterKelas == k ? Colors.white : const Color(0xFF4A4A4A))),
                selected: _filterKelas == k,
                selectedColor: k == 'PREMIUM' ? const Color(0xFFB8860B) : k == 'REGULER' ? const Color(0xFF2980B9) : const Color(0xFF6B5B4B),
                backgroundColor: const Color(0xFFF0EDE8),
                onSelected: (_) => setState(() => _filterKelas = k),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )),
          ]))),
        Padding(padding: const EdgeInsets.all(12), child: TextField(onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(hintText: 'Cari parfum...', prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true), style: const TextStyle(fontSize: 13))),
        Expanded(child: GridView.builder(padding: const EdgeInsets.symmetric(horizontal: 12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 1.9, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: prods.length,
          itemBuilder: (_, i) { final p = prods[i]; final low = (p['stok'] as num) <= (p['min_stok'] as num); final habis = (p['stok'] as num) <= 0;
            final varHarga = _varian.where((v) => v['produk_id']?.toString() == p['id']?.toString()).map((v) => (v['harga_jual'] as num?)?.toDouble() ?? 0).where((h) => h > 0).toList();
            final minH = varHarga.isEmpty ? 0.0 : varHarga.reduce((a, b) => a < b ? a : b);
            final maxH = varHarga.isEmpty ? 0.0 : varHarga.reduce((a, b) => a > b ? a : b);
            final priceRange = varHarga.isEmpty ? 'Belum ada harga' : minH == maxH ? cur.format(minH) : '${cur.format(minH)} - ${cur.format(maxH)}';
            return GestureDetector(
              onTap: () => _pilihVarian(p['id']),
              child: Card(child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text((_varian.firstWhere((v) => v['produk_id']?.toString() == p['id']?.toString(), orElse: () => {'nama': p['nama']})['nama'] ?? p['nama']).toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(priceRange, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: varHarga.isEmpty ? const Color(0xFFC0392B) : const Color(0xFFD4A574)), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(habis ? 'HABIS' : low ? 'Stok rendah' : 'Tersedia', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: habis ? Colors.red : low ? Colors.orange : Colors.green)),
              ]))));
          })),
        // ═══ KERANJANG ═══
        if (_cart.isNotEmpty) Container(
          padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE8E0D8), width: 2))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Keranjang (${_cart.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              GestureDetector(onTap: () => setState(() => _cart.clear()), child: const Text('Hapus', style: TextStyle(fontSize: 11, color: Colors.red)))]),
            const SizedBox(height: 6),
            SizedBox(height: _cart.length > 2 ? 80 : null, child: ListView(shrinkWrap: _cart.length <= 2, children: _cart.asMap().entries.map((e) { final c = e.value; final i = e.key;
              return Row(children: [
                Expanded(child: Text(c['nama'], style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                IconButton(icon: const Icon(Icons.remove, size: 14), onPressed: () { setState(() { _cart[i] = {...c, 'qty': (c['qty'] as int) - 1}; if ((_cart[i]['qty'] as int) <= 0) _cart.removeAt(i); }); }, iconSize: 18, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28)),
                Text('${c['qty']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                IconButton(icon: const Icon(Icons.add, size: 14), onPressed: () => setState(() => _cart[i] = {...c, 'qty': (c['qty'] as int) + 1}), iconSize: 18, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28)),
                Text(cur.format((c['hj'] as num) * (c['qty'] as int)), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                IconButton(icon: const Icon(Icons.cancel, size: 14, color: Color(0xFFC0392B)), onPressed: () => _voidItem(i), iconSize: 16, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24)),
              ]);
            }).toList())),
            const Divider(),
            // ═══ PELANGGAN / MEMBER ═══
            InkWell(onTap: _pilihPelanggan, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: _pelanggan != null ? const Color(0xFFD4A574).withOpacity(0.08) : const Color(0xFFFAF8F5),
                border: Border.all(color: _pelanggan != null ? const Color(0xFFD4A574) : const Color(0xFFE8E0D8)),
                borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(_pelanggan != null ? Icons.person : Icons.person_outline, size: 16, color: _pelanggan != null ? const Color(0xFFD4A574) : const Color(0xFFA09080)),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(_pelanggan?['nama'] ?? 'Pilih Pelanggan (opsional)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: _pelanggan != null ? const Color(0xFF3A2E24) : const Color(0xFFA09080))),
                  if (_pelanggan != null)
                    Text('Total: ${cur.format(((_pelanggan!['total_belanja'] ?? 0) as num).toDouble())} · Diskon tersedia: ${cur.format(_diskonMemberTersedia)}',
                      style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                ])),
                if (_pelanggan != null) IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () => setState(() { _pelanggan = null; _diskonMemberDipakai = 0; }),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24)),
              ]))),
            if (_pelanggan != null && (_diskonMemberTersedia >= 50000 || _diskonMemberDipakai > 0))
              Padding(padding: const EdgeInsets.only(bottom: 6), child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: _togglePakaiDiskonMember,
                icon: Icon(_diskonMemberDipakai > 0 ? Icons.check_box : Icons.check_box_outline_blank, size: 14),
                label: Text(_diskonMemberDipakai > 0
                  ? 'Diskon Member: -${cur.format(_diskonMemberDipakai)} (klik batal)'
                  : 'Pakai Diskon Member 50rb',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF27AE60),
                  side: const BorderSide(color: Color(0xFF27AE60)),
                  padding: const EdgeInsets.symmetric(vertical: 6))))),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))), Text(cur.format(_sub), style: const TextStyle(fontSize: 11))]),
            const SizedBox(height: 4),
            Row(children: [
              const Text('Diskon  ', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
              Expanded(child: TextField(
                keyboardType: TextInputType.number,
                onChanged: (v) => setState(() => _diskon = double.tryParse(v.replaceAll(RegExp(r'[^\d]'), '')) ?? 0),
                decoration: InputDecoration(hintText: '0', prefixText: 'Rp ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), isDense: true),
                style: const TextStyle(fontSize: 11))),
            ]),
            if (_diskonMemberDipakai > 0)
              Padding(padding: const EdgeInsets.only(top: 4), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Diskon Member', style: TextStyle(fontSize: 11, color: Color(0xFF27AE60))),
                Text('- ${cur.format(_diskonMemberDipakai)}', style: const TextStyle(fontSize: 11, color: Color(0xFF27AE60), fontWeight: FontWeight.w600)),
              ])),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('TOTAL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))), Text(cur.format(_total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))]),
            const SizedBox(height: 8),
            Row(children: ['Cash', 'QRIS', 'Transfer'].map((m) => Expanded(child: GestureDetector(onTap: () => setState(() => _metode = m),
              child: Container(margin: const EdgeInsets.symmetric(horizontal: 2), padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), border: Border.all(color: _metode == m ? const Color(0xFFD4A574) : const Color(0xFFE8E0D8)), color: _metode == m ? const Color(0xFFD4A574) : Colors.white),
                child: Center(child: Text(m, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: _metode == m ? Colors.white : const Color(0xFF6B5B4B)))))))).toList()),
            const SizedBox(height: 6),
            if (_metode == 'Cash') ...[
              TextField(controller: _bayarCtrl, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: 'Jumlah bayar...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true), style: const TextStyle(fontSize: 13)),
              if (_bayar >= _total && _bayar > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Kembalian: ${cur.format(_bayar - _total)}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF27AE60)))),
            ],
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: _processing ? null : (_metode == 'QRIS') ? _showQris : (_metode == 'Transfer') ? _bayarSekarang : (_cart.isNotEmpty && _bayar >= _total) ? _bayarSekarang : null,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: Text(_processing ? 'Memproses...' : _metode == 'QRIS' ? 'Tampilkan QRIS' : 'Bayar Sekarang', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
          ])),
      ]),
    );
  }
}

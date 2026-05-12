import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/api.dart';
import '../widgets/dev_contact.dart';
import '../services/bluetooth_printer_service.dart';
import 'login_screen.dart';
import 'pos_screen.dart';
import 'shift_screen.dart';
import 'inventory_screen.dart';
import 'pergerakan_screen.dart';
import 'stok_masuk_screen.dart';
import 'varian_screen.dart';
import 'katalog_produk_screen.dart';
import 'resep_template_screen.dart';
import 'pengeluaran_screen.dart';
import 'laporan_screen.dart';
import 'laporan_cabang_screen.dart';
import 'import_screen.dart';
import 'settings_screen.dart';
import 'stok_keluar_screen.dart';
import 'panduan_screen.dart';
import 'bluetooth_printer_screen.dart';
import 'pelanggan_screen.dart';

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const HomeScreen({super.key, required this.toko, required this.user});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  bool _loading = true, _online = true;
  int _produkCount = 0, _varianCount = 0, _trxCount = 0;
  double _pendapatan = 0, _pengeluaran = 0;
  List<Map<String, dynamic>> _lowStok = [], _recentTrx = [];
  // Filter riwayat transaksi
  DateTime _recentDate = DateTime.now();
  bool _showAllRecent = false;
  bool _loadingRecent = false;
  // AI Insight
  Map<String, dynamic> _insight = {};
  bool get isOwner => widget.user['peran'] == 'owner';
  String get tokoId => widget.toko['id'];

  @override void initState() { super.initState(); _checkConn(); _load();
    // Auto-snapshot saldo awal kalau bulan baru (fire-and-forget, tidak block UI)
    Api.autoSnapshotSaldoAwalJikaBulanBaru(tokoId).then((_) {}).catchError((_) {});
  }

  Future<void> _checkConn() async {
    try {
      final r = await Connectivity().checkConnectivity();
      setState(() => _online = !r.contains(ConnectivityResult.none));
    } catch (_) {}
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final today      = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final monthStart = DateFormat('yyyy-MM-01').format(DateTime.now());
      // Phase 1: semua query yang tidak saling bergantung jalan serentak
      final recentDateStr = DateFormat('yyyy-MM-dd').format(_recentDate);
      final res = await Future.wait<List<Map<String, dynamic>>>([
        Api.getProduk(tokoId),
        Api.getTransaksi(tokoId, tanggalMulai: today, tanggalAkhir: today),
        Api.getTransaksi(tokoId, tanggalMulai: recentDateStr, tanggalAkhir: recentDateStr, limit: 1000),
        Api.getPengeluaran(tokoId, tanggalMulai: monthStart, tanggalAkhir: today),
      ]);
      final produk    = res[0]; final trx = res[1];
      final recentTrx = res[2]; final peng = res[3];
      // Phase 2: varian chunks semua tembak serentak pakai produkIds dari phase 1
      final varianCount = await Api.getVarianCountByIds(produk.map((p) => p['id'] as String).toList());
      final lowStok   = produk.where((p) => ((p['stok'] ?? 0) as num) <= ((p['min_stok'] ?? 0) as num)).toList();
      final pendapatan = trx.fold(0.0, (double s, t) => s + ((t['total'] ?? 0) as num).toDouble());
      final totalPeng  = peng.fold(0.0, (double s, p) => s + ((p['jumlah'] ?? 0) as num).toDouble());
      if (mounted) {
        setState(() {
          _produkCount = produk.length; _varianCount = varianCount;
          _trxCount = trx.length; _pendapatan = pendapatan; _pengeluaran = totalPeng;
          _lowStok = lowStok; _recentTrx = recentTrx; _loading = false;
        });
      }

      // AI Insight: cache 1x per hari, reset jam 00:00
      if (isOwner) {
        final cached = await Api.getCachedInsight(tokoId);
        if (cached != null) {
          if (mounted) setState(() => _insight = cached);
        } else {
          Api.getAIInsights(tokoId).then((insight) async {
            await Api.saveCachedInsight(tokoId, insight);
            if (mounted) setState(() => _insight = insight);
          }).catchError((_) {});
        }
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _go(Widget s) { Navigator.push(context, MaterialPageRoute(builder: (_) => s)).then((_) => _load()); }

  // Reload list transaksi sesuai tanggal yang dipilih (cuma fetch ulang recentTrx)
  Future<void> _reloadRecent() async {
    setState(() => _loadingRecent = true);
    try {
      final tglStr = DateFormat('yyyy-MM-dd').format(_recentDate);
      final list = await Api.getTransaksi(tokoId, tanggalMulai: tglStr, tanggalAkhir: tglStr, limit: 1000);
      if (mounted) setState(() { _recentTrx = list; _loadingRecent = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingRecent = false);
    }
  }

  Future<void> _pilihTanggalRecent() async {
    final picked = await showDatePicker(context: context,
      initialDate: _recentDate,
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) {
      setState(() { _recentDate = picked; _showAllRecent = false; });
      _reloadRecent();
    }
  }

  void _setQuickRecent(String p) {
    final now = DateTime.now();
    setState(() {
      if (p == 'hari') { _recentDate = now; }
      else if (p == 'kemarin') { _recentDate = now.subtract(const Duration(days: 1)); }
      _showAllRecent = false;
    });
    _reloadRecent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      drawer: _drawer(),
      body: RefreshIndicator(onRefresh: _load, child: CustomScrollView(slivers: [
        SliverAppBar(expandedHeight: 130, pinned: true, backgroundColor: const Color(0xFF1A1510),
          leading: Builder(builder: (c) => IconButton(icon: const Icon(Icons.menu, color: Color(0xFFD4A574)), onPressed: () => Scaffold.of(c).openDrawer())),
          actions: [
            if (!_online) const Padding(padding: EdgeInsets.only(right: 8, top: 14), child: Icon(Icons.cloud_off, color: Color(0xFFC0392B), size: 18)),
            IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF8B7355), size: 20), onPressed: _load),
          ],
          flexibleSpace: FlexibleSpaceBar(background: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1510), Color(0xFF2A2118)])),
            child: SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 48, 20, 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              Text('Halo, ${widget.user['nama']}!', style: const TextStyle(color: Color(0xFFD4A574), fontSize: 18, fontWeight: FontWeight.w600)),
              Text('${isOwner ? 'Owner' : 'Kasir'} - ${widget.toko['nama'] ?? ''} - ${DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now())}', style: const TextStyle(color: Color(0xFF8B7355), fontSize: 10)),
            ])))))),
        SliverPadding(padding: const EdgeInsets.all(16), sliver: SliverList(delegate: SliverChildListDelegate([
          if (_loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFFD4A574))))
          else ...[
            // ═══ AI INSIGHT CARD ═══
            if (_insight.isNotEmpty && isOwner) _aiInsightCard(),
            if (_lowStok.isNotEmpty) _alertCard(),
            const SizedBox(height: 8),
            _kpiGrid(),
            const SizedBox(height: 16),
            _menuGrid(),
            const SizedBox(height: 16),
            // ═══ RIWAYAT TRANSAKSI (filter tanggal + lihat semua) ═══
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Riwayat Transaksi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('${_recentTrx.length} trx', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            ]),
            const SizedBox(height: 8),
            // Quick filter & date picker
            Row(children: [
              Expanded(child: Wrap(spacing: 4, children: [
                ActionChip(
                  label: Text('Hari Ini', style: TextStyle(fontSize: 9, color: DateUtils.isSameDay(_recentDate, DateTime.now()) ? Colors.white : const Color(0xFF6B5B4B))),
                  backgroundColor: DateUtils.isSameDay(_recentDate, DateTime.now()) ? const Color(0xFFD4A574) : const Color(0xFFFAF8F5),
                  onPressed: () => _setQuickRecent('hari'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ActionChip(
                  label: Text('Kemarin', style: TextStyle(fontSize: 9, color: DateUtils.isSameDay(_recentDate, DateTime.now().subtract(const Duration(days: 1))) ? Colors.white : const Color(0xFF6B5B4B))),
                  backgroundColor: DateUtils.isSameDay(_recentDate, DateTime.now().subtract(const Duration(days: 1))) ? const Color(0xFFD4A574) : const Color(0xFFFAF8F5),
                  onPressed: () => _setQuickRecent('kemarin'),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              ])),
              GestureDetector(onTap: _pilihTanggalRecent,
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(6)),
                  child: Row(children: [
                    const Icon(Icons.calendar_today, size: 12, color: Color(0xFFD4A574)),
                    const SizedBox(width: 4),
                    Text(DateFormat('dd MMM yyyy', 'id_ID').format(_recentDate), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                  ]))),
            ]),
            const SizedBox(height: 8),
            if (_loadingRecent)
              const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Color(0xFFD4A574))))
            else if (_recentTrx.isEmpty)
              Padding(padding: const EdgeInsets.all(16),
                child: Center(child: Text('Tidak ada transaksi di tanggal ini', style: TextStyle(fontSize: 11, color: Colors.grey[600]))))
            else ...[
              ...(_showAllRecent ? _recentTrx : _recentTrx.take(5)).map(_trxItem),
              if (_recentTrx.length > 5)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showAllRecent = !_showAllRecent),
                    icon: Icon(_showAllRecent ? Icons.expand_less : Icons.expand_more, size: 16),
                    label: Text(_showAllRecent
                      ? 'Tampilkan lebih sedikit'
                      : 'Tampilkan semua (${_recentTrx.length} transaksi)',
                      style: const TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD4A574),
                      side: const BorderSide(color: Color(0xFFD4A574)))))),
            ],
          ],
          const SizedBox(height: 80),
        ]))),
      ])),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _go(POSScreen(toko: widget.toko, user: widget.user)),
        backgroundColor: const Color(0xFFD4A574), icon: const Icon(Icons.add_shopping_cart, color: Colors.white),
        label: const Text('Transaksi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
    );
  }

  // ═══ AI INSIGHT CARD ═══
  Widget _aiInsightCard() {
    final growth = (_insight['growthPct'] as num? ?? 0).toDouble();
    final todayTot = (_insight['todayTotal'] as num? ?? 0).toDouble();
    final topProd = (_insight['topProduk'] ?? '-').toString();
    final lowCount = (_insight['lowStokCount'] as num? ?? 0).toInt();
    final prediksi = (_insight['stokPrediksi'] as Map<String, dynamic>?) ?? {};
    final isUp = growth >= 0;

    return Card(margin: const EdgeInsets.only(bottom: 12), child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(colors: [Color(0xFF1A1510), Color(0xFF2A2520)])),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: const Color(0xFFD4A574), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          const Text('Smart Insight', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
          const Text('Update setiap jam 00:00', style: TextStyle(fontSize: 8, color: Color(0xFF8B7355))),
        ]),
        const SizedBox(height: 12),
        // Penjualan hari ini
        Row(children: [
          Icon(isUp ? Icons.trending_up : Icons.trending_down, color: isUp ? const Color(0xFF27AE60) : const Color(0xFFC0392B), size: 18),
          const SizedBox(width: 6),
          Expanded(child: RichText(text: TextSpan(style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4)), children: [
            const TextSpan(text: 'Hari ini '),
            TextSpan(text: cur.format(todayTot), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
            if (growth != 0) TextSpan(text: ' (${isUp ? '+' : ''}${growth.toStringAsFixed(0)}%)', style: TextStyle(fontWeight: FontWeight.w600, color: isUp ? const Color(0xFF27AE60) : const Color(0xFFC0392B))),
          ]))),
        ]),
        const SizedBox(height: 6),
        // Produk terlaris
        if (topProd != '-') Row(children: [
          const Icon(Icons.local_fire_department, color: Color(0xFFE67E22), size: 18),
          const SizedBox(width: 6),
          Expanded(child: Text('Paling laku: $topProd', style: const TextStyle(fontSize: 12, color: Color(0xFFD4D4D4)))),
        ]),
        // Stok warning
        if (lowCount > 0) Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
          const Icon(Icons.warning_amber, color: Color(0xFFC0392B), size: 18),
          const SizedBox(width: 6),
          Text('$lowCount produk stok rendah', style: const TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
        ])),
        // Prediksi habis
        if (prediksi.isNotEmpty) ...[
          const SizedBox(height: 6),
          ...prediksi.entries.take(3).map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [
            const Icon(Icons.schedule, color: Color(0xFFE67E22), size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text('${e.key} habis dalam ~${e.value} hari', style: const TextStyle(fontSize: 11, color: Color(0xFFE67E22)))),
          ]))),
        ],
      ])));
  }

  Widget _alertCard() => GestureDetector(onTap: isOwner ? () => _go(InventoryScreen(toko: widget.toko, isOwner: isOwner)) : null,
    child: Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFDF0E8), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE8C9A8))),
      child: Row(children: [const Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B), size: 22), const SizedBox(width: 10),
        Expanded(child: Text('${_lowStok.length} produk stok rendah!', style: const TextStyle(fontSize: 12, color: Color(0xFF991B1B)))),
        if (isOwner) const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFFC0392B))])));

  Widget _kpiGrid() {
    final items = <List>[
      ['Pendapatan', cur.format(_pendapatan), const Color(0xFF27AE60), Icons.trending_up],
      ['Transaksi', '$_trxCount Nota', const Color(0xFF2980B9), Icons.receipt_outlined],
      if (isOwner) ['Pengeluaran', cur.format(_pengeluaran), const Color(0xFFC0392B), Icons.money_off],
      ['Produk', '$_produkCount + $_varianCount', const Color(0xFFE67E22), Icons.inventory_2],
    ];
    return GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.7,
      children: items.map((x) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: (x[2] as Color).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(x[3] as IconData, color: x[2] as Color, size: 18)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(x[0] as String, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
          Text(x[1] as String, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: x[2] as Color), overflow: TextOverflow.ellipsis),
        ]),
      ])))).toList());
  }

  Widget _menuGrid() {
    final m = <List>[
      ['Kasir / POS', Icons.point_of_sale, const Color(0xFFD4A574), () => _go(POSScreen(toko: widget.toko, user: widget.user))],
      ['Pelanggan', Icons.people, const Color(0xFF8E44AD), () => _go(PelangganScreen(toko: widget.toko, user: widget.user))],
      ['Shift', Icons.access_time, const Color(0xFF16A085), () => _go(ShiftScreen(toko: widget.toko, user: widget.user))],
      ['Pengeluaran', Icons.receipt_long, const Color(0xFFC0392B), () => _go(PengeluaranScreen(toko: widget.toko, user: widget.user))],
      if (isOwner) ...[
        ['Katalog', Icons.menu_book, const Color(0xFFD4A574), () => _go(KatalogProdukScreen(toko: widget.toko))],
        ['Inventori', Icons.inventory_2, const Color(0xFF2980B9), () => _go(InventoryScreen(toko: widget.toko, isOwner: isOwner))],
        ['Pergerakan', Icons.swap_vert, const Color(0xFF27AE60), () => _go(PergerakanScreen(toko: widget.toko))],
        ['Stok Masuk', Icons.add_box, const Color(0xFF16A085), () => _go(StokMasukScreen(toko: widget.toko, user: widget.user))],
        ['Stok Keluar', Icons.remove_circle, const Color(0xFFC0392B), () => _go(StokKeluarScreen(toko: widget.toko, user: widget.user))],
        ['Produk', Icons.style, const Color(0xFFE67E22), () => _go(VarianScreen(toko: widget.toko))],
        ['Template Resep', Icons.rule, const Color(0xFF8E44AD), () => _go(const ResepTemplateScreen())],
        ['Laporan', Icons.bar_chart, const Color(0xFF8E44AD), () => _go(LaporanScreen(toko: widget.toko, user: widget.user))],
        ['Cabang', Icons.store, const Color(0xFF0984E3), () => _go(LaporanCabangScreen(toko: widget.toko))],
        ['Import', Icons.file_copy, const Color(0xFF6B5B4B), () => _go(ImportScreen(toko: widget.toko))],
        ['Setting', Icons.settings, const Color(0xFF6B5B4B), () => _go(SettingsScreen(toko: widget.toko))],
        ['Panduan', Icons.menu_book_outlined, const Color(0xFFD4A574), () => _go(const PanduanScreen())],
        ['Bluetooth', Icons.bluetooth, const Color(0xFF2980B9), () => _go(const BluetoothPrinterScreen())],
      ],
    ];
    return GridView.count(crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.95,
      children: m.map((x) => GestureDetector(onTap: x[3] as VoidCallback, child: Card(child: Container(
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: [(x[2] as Color).withOpacity(0.08), (x[2] as Color).withOpacity(0.02)])),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: x[2] as Color, borderRadius: BorderRadius.circular(10)),
            child: Icon(x[1] as IconData, color: Colors.white, size: 22)),
          const SizedBox(height: 6),
          Text(x[0] as String, style: TextStyle(fontWeight: FontWeight.w600, color: x[2] as Color, fontSize: 11), textAlign: TextAlign.center),
        ]))))).toList());
  }

  Widget _trxItem(Map<String, dynamic> t) {
    final tgl = DateTime.tryParse(t['tanggal']?.toString() ?? '')?.toLocal();
    final jam = tgl != null ? DateFormat('HH:mm').format(tgl) : '';
    return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
      leading: CircleAvatar(radius: 16, backgroundColor: const Color(0xFFF0EBE4), child: Text((t['metode'] ?? 'C')[0], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
      title: Text(t['no_nota'] ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      subtitle: Text('${t['user_nama'] ?? '-'} - ${t['metode'] ?? '-'} $jam', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(cur.format(t['total'] ?? 0), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
        const SizedBox(width: 4),
        IconButton(icon: const Icon(Icons.receipt_long, size: 18, color: Color(0xFF27AE60)),
          onPressed: () => _previewTrx(t), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28), tooltip: 'Lihat Item'),
        IconButton(icon: const Icon(Icons.print, size: 18, color: Color(0xFF2980B9)),
          onPressed: () => _cetakUlangTrx(t), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28), tooltip: 'Cetak Ulang'),
      ])));
  }

  Future<void> _cetakUlangTrx(Map<String, dynamic> trx) async {
    try {
      final full = await Api.getTransaksiWithItems(trx['id']);
      if (full == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data transaksi tidak ditemukan'))); return; }
      final items = (full['items'] as List?) ?? [];
      final tgl = DateTime.tryParse(full['tanggal']?.toString() ?? full['created_at']?.toString() ?? '')?.toLocal();
      final jamStr = tgl != null ? DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(tgl) : '-';
      final btService = BluetoothPrinterService();
      final savedName = await btService.getSavedName();
      if (savedName != null) {
        final itemsList = items.map<Map<String, dynamic>>((i) => {'nama': i['nama_item'] ?? '-', 'qty': ((i['qty'] ?? 1) as num).toInt(), 'hj': ((i['harga_satuan'] ?? 0) as num).toDouble()}).toList();
        final err = await btService.printStruk(
          nota: '${full['no_nota'] ?? '-'} (ULANG)', tokoNama: widget.toko['nama'] ?? 'KS Parfume',
          tokoAlamat: widget.toko['alamat'] ?? '', items: itemsList,
          subtotal: ((full['subtotal'] ?? 0) as num).toDouble(),
          diskon: ((full['diskon'] ?? 0) as num).toDouble(),
          pelanggan: full['pelanggan_nama']?.toString(),
          total: ((full['total'] ?? 0) as num).toDouble(), bayar: ((full['bayar'] ?? 0) as num).toDouble(),
          kembalian: ((full['kembalian'] ?? 0) as num).toDouble(), metode: full['metode']?.toString() ?? 'Cash',
          jam: jamStr, kasir: full['user_nama']?.toString() ?? '-');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err == null ? 'Struk dicetak via Bluetooth' : 'BT gagal: $err'),
          backgroundColor: err == null ? const Color(0xFF27AE60) : Colors.red));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Printer Bluetooth belum diatur.\nBuka Setting → Printer Bluetooth.'),
          backgroundColor: Colors.orange, duration: Duration(seconds: 3)));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _previewTrx(Map<String, dynamic> trx) async {
    try {
      final full = await Api.getTransaksiWithItems(trx['id']);
      if (full == null) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data tidak ditemukan'))); return; }
      final items = (full['items'] as List?) ?? [];
      final tgl = DateTime.tryParse(full['tanggal']?.toString() ?? full['created_at']?.toString() ?? '')?.toLocal();
      final tglStr = tgl != null ? DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(tgl) : '-';
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          title: Text(full['no_nota'] ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${full['user_nama'] ?? '-'} · ${full['metode'] ?? '-'}', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
              Text(tglStr, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
              const Divider(height: 16),
              if (items.isEmpty)
                const Text('Tidak ada item', style: TextStyle(fontSize: 12, color: Color(0xFFA09080)))
              else
                ...items.map((i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Expanded(child: Text('${((i['qty'] ?? 1) as num).toInt()}x ${i['nama_item'] ?? '-'}', style: const TextStyle(fontSize: 12))),
                    Text(cur.format(((i['harga_satuan'] ?? 0) as num).toDouble()), style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
                  ]),
                )),
              const Divider(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(cur.format(((full['total'] ?? 0) as num).toDouble()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
              ]),
              const SizedBox(height: 4),
            ])),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _drawer() => Drawer(backgroundColor: const Color(0xFF1A1510), child: SafeArea(child: Column(children: [
    Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)])),
        child: const Center(child: Text('KS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)))),
      const SizedBox(height: 12),
      const Text('KS PARFUME', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFF5E6D3), letterSpacing: 2)),
      const SizedBox(height: 4),
      Text('${widget.toko['nama'] ?? ''}', style: const TextStyle(fontSize: 11, color: Color(0xFFD4A574))),
      Text('${widget.user['nama']} (${widget.user['peran']})', style: const TextStyle(fontSize: 10, color: Color(0xFF8B7355))),
    ])),
    const Divider(color: Color(0xFF2A2520), height: 1),
    Expanded(child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
      _di(Icons.home, 'Beranda', () => Navigator.pop(context)),
      _di(Icons.point_of_sale, 'Kasir / POS', () { Navigator.pop(context); _go(POSScreen(toko: widget.toko, user: widget.user)); }),
      _di(Icons.access_time, 'Shift', () { Navigator.pop(context); _go(ShiftScreen(toko: widget.toko, user: widget.user)); }),
      _di(Icons.receipt_long, 'Pengeluaran', () { Navigator.pop(context); _go(PengeluaranScreen(toko: widget.toko, user: widget.user)); }),
      if (isOwner) ...[
        _di(Icons.inventory_2, 'Inventori', () { Navigator.pop(context); _go(InventoryScreen(toko: widget.toko, isOwner: isOwner)); }),
        _di(Icons.swap_vert, 'Pergerakan Stok', () { Navigator.pop(context); _go(PergerakanScreen(toko: widget.toko)); }),
        _di(Icons.add_box, 'Stok Masuk', () { Navigator.pop(context); _go(StokMasukScreen(toko: widget.toko, user: widget.user)); }),
        _di(Icons.remove_circle, 'Stok Keluar', () { Navigator.pop(context); _go(StokKeluarScreen(toko: widget.toko, user: widget.user)); }),
        _di(Icons.menu_book, 'Katalog Produk', () { Navigator.pop(context); _go(KatalogProdukScreen(toko: widget.toko)); }),
        _di(Icons.style, 'Produk & Varian', () { Navigator.pop(context); _go(VarianScreen(toko: widget.toko)); }),
        _di(Icons.rule, 'Template Resep', () { Navigator.pop(context); _go(const ResepTemplateScreen()); }),
        _di(Icons.bar_chart, 'Laporan', () { Navigator.pop(context); _go(LaporanScreen(toko: widget.toko, user: widget.user)); }),
        _di(Icons.store, 'Laporan Cabang', () { Navigator.pop(context); _go(LaporanCabangScreen(toko: widget.toko)); }),
        _di(Icons.file_copy, 'Import / Export', () { Navigator.pop(context); _go(ImportScreen(toko: widget.toko)); }),
        _di(Icons.settings, 'Pengaturan', () { Navigator.pop(context); _go(SettingsScreen(toko: widget.toko)); }),
        _di(Icons.menu_book_outlined, 'Panduan', () { Navigator.pop(context); _go(const PanduanScreen()); }),
        _di(Icons.bluetooth, 'Bluetooth Printer', () { Navigator.pop(context); _go(const BluetoothPrinterScreen()); }),
      ],
    ])),
    Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      ElevatedButton.icon(onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(toko: widget.toko))),
        icon: const Icon(Icons.logout, size: 18), label: const Text('Keluar'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3A3530), foregroundColor: const Color(0xFF8B7355))),
      const SizedBox(height: 12),
      const DevContact(compact: true),
    ])),
  ])));

  Widget _di(IconData ic, String lb, VoidCallback fn) => ListTile(leading: Icon(ic, color: const Color(0xFF8B7355), size: 20), title: Text(lb, style: const TextStyle(color: Color(0xFFD4A574), fontSize: 13)), onTap: fn, dense: true);
}

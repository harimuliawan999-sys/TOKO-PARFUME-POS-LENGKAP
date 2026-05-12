import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/api.dart';
import '../services/bluetooth_printer_service.dart';

class LaporanScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  final Map<String, dynamic> user;
  const LaporanScreen({super.key, required this.toko, required this.user});
  @override State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
  final timeFmt = DateFormat('HH:mm', 'id_ID');

  DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _sampai = DateTime.now();

  List<Map<String, dynamic>> _trx = [], _displayTrx = [], _peng = [], _terlaris = [], _shiftKasKeluar = [];
  double _income = 0, _hpp = 0, _grossProfit = 0, _expenses = 0, _nettProfit = 0;
  double _botolTerpakai = 0, _bibitTerpakai = 0;
  Map<String, double> _metodeMap = {};
  Map<String, double> _harian = {};
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final mulai = DateFormat('yyyy-MM-dd').format(_dari);
    final akhir = DateFormat('yyyy-MM-dd').format(_sampai);
    final tokoId = widget.toko['id'];
    try {
      // ── PARALEL: semua query independen jalan serentak (sebelumnya sequential) ──
      // getTransaksi di-derive dari getTransaksiAll → hemat 1 query.
      final allTrxFut = Api.getTransaksiAll(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir, limit: 5000);
      final pengFut = Api.getPengeluaran(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir);
      final terlarisFut = Api.getProdukTerlaris(tokoId);
      final hppFut = Api.getHppTotal(tokoId, mulai, akhir);
      final shiftKasFut = Api.getShiftKasByToko(tokoId, tanggalMulai: mulai, tanggalAkhir: akhir)
          .catchError((_) => <Map<String, dynamic>>[]);
      final movementsFut = Api.getStokMovement(tokoId, tipe: 'penjualan', limit: 5000);
      final produkFut = Api.getProduk(tokoId);

      final allTrx = await allTrxFut;
      final peng = await pengFut;
      final terlaris = await terlarisFut;
      final hpp = await hppFut;
      final allShiftKas = await shiftKasFut;
      final movements = await movementsFut;
      final produk = await produkFut;

      // Derive _trx (selesai & belum dibatalkan) dari allTrx — hasil identik dgn getTransaksi
      final trx = allTrx.where((t) => t['status'] == 'selesai').toList();

      // Income / metode / harian
      double income = 0;
      final metode = <String, double>{};
      final harian = <String, double>{};
      for (final t in trx) {
        final tot = ((t['total'] ?? 0) as num).toDouble();
        income += tot;
        final m = (t['metode'] ?? 'Cash').toString();
        metode[m] = (metode[m] ?? 0) + tot;
        final tgl = DateTime.tryParse((t['created_at'] ?? t['tanggal'] ?? '').toString())?.toLocal();
        if (tgl != null) {
          final key = DateFormat('dd/MM').format(tgl);
          harian[key] = (harian[key] ?? 0) + tot;
        }
      }

      // Pengeluaran + kas keluar shift
      final shiftKasKeluar = allShiftKas.where((k) => k['tipe'] == 'keluar').toList();
      final shiftKasKeluarTotal = shiftKasKeluar.fold(0.0, (double s, k) => s + ((k['jumlah'] ?? 0) as num).toDouble());
      final expenses = peng.fold(0.0, (double s, p) => s + ((p['jumlah'] ?? 0) as num).toDouble());
      final totalExpenses = expenses + shiftKasKeluarTotal;
      final grossProfit = income - hpp;
      final nettProfit = grossProfit - totalExpenses;

      // Hitung botol & bibit terpakai net
      double botolPakai = 0, bibitPakai = 0;
      try {
        final dariDt = DateTime.parse('${mulai}T00:00:00');
        final sampaiDt = DateTime.parse('${akhir}T23:59:59');
        // Index produk by id untuk O(1) lookup
        final produkById = <String, Map<String, dynamic>>{
          for (final p in produk) p['id'].toString(): p,
        };
        for (final m in movements) {
          final tgl = DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal();
          if (tgl == null) continue;
          if (tgl.isBefore(dariDt) || tgl.isAfter(sampaiDt)) continue;
          final p = produkById[m['produk_id']?.toString()] ?? const {};
          final kat = (p['kategori'] ?? '').toString();
          final qty = ((m['qty'] ?? 0) as num).abs().toDouble();
          if (kat.contains('BOTOL') || kat.contains('SPRAY')) { botolPakai += qty; }
          else if (kat.contains('PARFUME')) { bibitPakai += qty; }
        }
        // Batch fetch items dari transaksi yang dibatalkan (hindari N+1)
        final cancelledIds = allTrx.where((t) => t['status'] == 'dibatalkan').map((t) => t['id'].toString()).toList();
        if (cancelledIds.isNotEmpty) {
          final cancelledItems = await Api.getTransaksiItemsBatch(cancelledIds);
          for (final item in cancelledItems) {
            final varianId = item['varian_id'];
            final produkId = item['produk_id']?.toString();
            final botolId = item['botol_id']?.toString();
            final qty = ((item['qty'] ?? 0) as num).toInt();
            final resepBibit = ((item['resep_bibit'] ?? 0) as num).toDouble();
            if (varianId != null) {
              if (produkId != null && resepBibit > 0) {
                final p = produkById[produkId] ?? const {};
                if ((p['kategori'] ?? '').toString().contains('PARFUME')) bibitPakai -= resepBibit * qty;
              }
              if (botolId != null && botolId.isNotEmpty) {
                final b = produkById[botolId] ?? const {};
                final bk = (b['kategori'] ?? '').toString();
                if (bk.contains('BOTOL') || bk.contains('SPRAY')) botolPakai -= qty;
              }
            } else if (produkId != null) {
              final p = produkById[produkId] ?? const {};
              if ((p['kategori'] ?? '').toString().contains('PARFUME')) bibitPakai -= qty;
              if (botolId != null && botolId.isNotEmpty) {
                final b = produkById[botolId] ?? const {};
                final bk = (b['kategori'] ?? '').toString();
                if (bk.contains('BOTOL') || bk.contains('SPRAY')) botolPakai -= qty;
              }
            }
          }
        }
        bibitPakai = bibitPakai.clamp(0.0, double.infinity);
        botolPakai = botolPakai.clamp(0.0, double.infinity);
      } catch (_) {}

      if (mounted) { setState(() {
        _trx = trx; _displayTrx = allTrx; _peng = peng; _terlaris = terlaris; _shiftKasKeluar = shiftKasKeluar;
        _income = income; _hpp = hpp; _grossProfit = grossProfit;
        _expenses = totalExpenses; _nettProfit = nettProfit;
        _botolTerpakai = botolPakai; _bibitTerpakai = bibitPakai;
        _metodeMap = metode; _harian = harian; _loading = false;
      }); }
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _pilihTanggal(bool isDari) async {
    final picked = await showDatePicker(context: context, initialDate: isDari ? _dari : _sampai, firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) { setState(() { if (isDari) { _dari = picked; } else { _sampai = picked; } }); _load(); }
  }

  void _setQuick(String p) {
    final now = DateTime.now();
    setState(() {
      if (p == 'hari') { _dari = now; _sampai = now; }
      else if (p == 'bulan') { _dari = DateTime(now.year, now.month, 1); _sampai = now; }
      else if (p == 'tahun') { _dari = DateTime(now.year, 1, 1); _sampai = now; }
      else { _dari = DateTime(2024, 1, 1); _sampai = now; }
    });
    _load();
  }

  // ═══ EXPORT PDF ═══
  Future<void> _exportPdf() async {
    final pdf = pw.Document();
    final periodeStr = '${dateFmt.format(_dari)} - ${dateFmt.format(_sampai)}';
    final jamStr = DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(DateTime.now());

    pdf.addPage(pw.MultiPage(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40),
      build: (ctx) => [
        pw.Center(child: pw.Column(children: [
          pw.Container(width: 50, height: 50, decoration: pw.BoxDecoration(color: PdfColor.fromHex('#D4A574'), borderRadius: pw.BorderRadius.circular(12)),
            child: pw.Center(child: pw.Text('KS', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white)))),
          pw.SizedBox(height: 6),
          pw.Text('KS PARFUME', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, letterSpacing: 4)),
          pw.Text('Laporan Laba Rugi', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
          pw.Text(periodeStr, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
          pw.Text('Dicetak: $jamStr', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
        ])),
        pw.SizedBox(height: 20), pw.Divider(), pw.SizedBox(height: 10),
        _pdfSection('A. Income (Pendapatan)', _income),
        _pdfRow('  SALES - POINT OF SALE', cur.format(_income)),
        pw.SizedBox(height: 8),
        _pdfSection('B. Cost of Goods Sold (HPP)', _hpp),
        _pdfRow('  Total Sales (Cost Price)', cur.format(_hpp)),
        pw.SizedBox(height: 8),
        _pdfSection('C. Gross Profit (Laba Kotor)', _grossProfit),
        pw.SizedBox(height: 8),
        _pdfSection('D. Expenses (Pengeluaran)', _expenses),
        ..._peng.map((p) => _pdfRow('  ${p['keterangan'] ?? '-'}', cur.format(p['jumlah'] ?? 0))),
        pw.SizedBox(height: 8),
        _pdfRow('E. Stock Terpakai', ''),
        _pdfRow('  Bibit (ml)', '${_bibitTerpakai.round()}'),
        _pdfRow('  Botol (pcs)', '${_botolTerpakai.round()}'),
        pw.SizedBox(height: 8),
        pw.Divider(thickness: 2),
        _pdfSection('G. Nett Profit (Laba Bersih)', _nettProfit),
        pw.SizedBox(height: 16),
        pw.Text('Payment By Method', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        ..._metodeMap.entries.map((e) => _pdfRow('  ${e.key}', cur.format(e.value))),
      ]));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/laporan_ks_parfume_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Laporan KS Parfume $periodeStr');
  }

  pw.Widget _pdfSection(String label, double value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.Text(cur.format(value), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
    ]));

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
      pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
    ]));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Laporan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [IconButton(icon: const Icon(Icons.picture_as_pdf, size: 20), onPressed: _loading ? null : _exportPdf)]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
          // Quick filter
          Wrap(spacing: 6, children: ['hari', 'bulan', 'tahun', 'semua'].map((p) => ActionChip(
            label: Text({'hari': 'Hari', 'bulan': 'Bulan', 'tahun': 'Tahun', 'semua': 'Semua'}[p]!, style: const TextStyle(fontSize: 10)),
            onPressed: () => _setQuick(p), backgroundColor: const Color(0xFFFAF8F5))).toList()),
          const SizedBox(height: 10),
          // Date picker
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => _pilihTanggal(true),
              child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_dari), style: const TextStyle(fontSize: 11))])))),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
            Expanded(child: GestureDetector(onTap: () => _pilihTanggal(false),
              child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_sampai), style: const TextStyle(fontSize: 11))])))),
          ]),
          const SizedBox(height: 16),

          // ═══ PROFIT LOSS (OLSERA STYLE) ═══
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Profit Loss', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Divider(height: 20),
            _plRow('A. Income', _income, bold: true),
            _plSub('SALES - POINT OF SALE', _income),
            const SizedBox(height: 8),
            _plRow('B. Cost of Goods Sold', _hpp, bold: true),
            _plSub('Total Sales (Cost Price)', _hpp),
            const SizedBox(height: 8),
            _plRow('C. Gross Profit', _grossProfit, bold: true, color: const Color(0xFF27AE60)),
            const SizedBox(height: 8),
            _plRow('D. Expenses', _expenses, bold: true),
            ..._peng.map((p) => _plSub(p['keterangan'] ?? '-', ((p['jumlah'] ?? 0) as num).toDouble())),
            if (_shiftKasKeluar.isNotEmpty) ...[
              _plSub('--- Kas Keluar Shift ---', 0),
              ..._shiftKasKeluar.map((k) => _plSub('*${k['keterangan'] ?? '-'}', ((k['jumlah'] ?? 0) as num).toDouble())),
            ],
            const SizedBox(height: 8),
            _plRow('E. Stock Terpakai', 0, bold: true),
            _plSub('Bibit (ml)', _bibitTerpakai),
            _plSub('Botol (pcs)', _botolTerpakai),
            const Divider(height: 20, thickness: 2),
            _plRow('G. Nett Profit', _nettProfit, bold: true, color: _nettProfit >= 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B)),
          ]))),
          const SizedBox(height: 16),

          // ═══ GRAFIK PENDAPATAN HARIAN ═══
          if (_harian.isNotEmpty) ...[
            const Text('Grafik Pendapatan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(height: 200,
              child: BarChart(BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: _harian.values.fold(0.0, (a, b) => a > b ? a : b) * 1.2,
                barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (g, gi, r, ri) => BarTooltipItem(cur.format(r.toY), const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)))),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30,
                    getTitlesWidget: (v, m) {
                      final keys = _harian.keys.toList();
                      if (v.toInt() < keys.length) return Text(keys[v.toInt()], style: const TextStyle(fontSize: 8, color: Color(0xFFA09080)));
                      return const Text('');
                    }))),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: _harian.entries.toList().asMap().entries.map((e) => BarChartGroupData(x: e.key,
                  barRods: [BarChartRodData(toY: e.value.value, color: const Color(0xFFD4A574), width: 14, borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))])).toList(),
              ))))),
            const SizedBox(height: 16),
          ],

          // ═══ PIE CHART METODE PEMBAYARAN ═══
          if (_metodeMap.isNotEmpty) ...[
            const Text('Payment By Method', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
              SizedBox(width: 140, height: 140, child: PieChart(PieChartData(
                sectionsSpace: 2, centerSpaceRadius: 28,
                sections: _metodeMap.entries.toList().asMap().entries.map((e) {
                  final colors = [const Color(0xFF27AE60), const Color(0xFF2980B9), const Color(0xFFD4A574), const Color(0xFF8E44AD)];
                  final pct = _income > 0 ? (e.value.value / _income * 100) : 0.0;
                  return PieChartSectionData(value: e.value.value, color: colors[e.key % colors.length], radius: 36,
                    title: '${pct.round()}%', titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white));
                }).toList()))),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ..._metodeMap.entries.toList().asMap().entries.map((e) {
                  final colors = [const Color(0xFF27AE60), const Color(0xFF2980B9), const Color(0xFFD4A574), const Color(0xFF8E44AD)];
                  final trxCount = _trx.where((t) => t['metode'] == e.value.key).length;
                  return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                    Container(width: 12, height: 12, decoration: BoxDecoration(color: colors[e.key % colors.length], borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.value.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('$trxCount trx - ${cur.format(e.value.value)}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                    ])),
                  ]));
                }),
                const Divider(),
                Text('Total: ${cur.format(_income)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
              ])),
            ]))),
            const SizedBox(height: 16),
          ],

          // ═══ DETAIL PENGELUARAN ═══
          if (_peng.isNotEmpty) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Detail Pengeluaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(cur.format(_expenses), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
            ]),
            const SizedBox(height: 8),
            ..._peng.map((p) => Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
              leading: Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFC0392B).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.remove_circle_outline, color: Color(0xFFC0392B), size: 16)),
              title: Text('${p['keterangan'] ?? '-'}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              subtitle: Text('${p['kategori'] ?? '-'} - ${p['tanggal'] ?? '-'}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
              trailing: Text('- ${cur.format(p['jumlah'] ?? 0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC0392B)))))),
            const SizedBox(height: 16),
          ],

          // ═══ PRODUK TERLARIS ═══
          if (_terlaris.isNotEmpty) ...[
            const Text('Product Sales', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._terlaris.take(10).toList().asMap().entries.map((e) { final t = e.value;
              return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
                leading: CircleAvatar(radius: 14, backgroundColor: const Color(0xFFF0EBE4), child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
                title: Text('${t['nama']} ${t['ukuran']} ${t['kualitas']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${t['total_terjual']} pcs', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                  Text(cur.format(t['total_pendapatan'] ?? 0), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFD4A574)))])));
            }),
            const SizedBox(height: 16),
          ],

          // ═══ TRANSAKSI ═══
          if (_displayTrx.isNotEmpty) ...[
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Cash Transactions (${_trx.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text('Tampil: ${_displayTrx.length}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            ]),
            const SizedBox(height: 8),
            ..._displayTrx.map((t) {
              final tgl = DateTime.tryParse((t['created_at'] ?? t['tanggal'] ?? '').toString())?.toLocal();
              final tglStr = tgl != null ? '${dateFmt.format(tgl)} ${timeFmt.format(tgl)}' : '-';
              final isBatal = t['status'] == 'dibatalkan';
              final isOwner = widget.user['peran'] == 'owner';
              return Card(
                margin: const EdgeInsets.only(bottom: 4),
                color: isBatal ? const Color(0xFFFFF0F0) : null,
                child: ListTile(dense: true,
                  leading: CircleAvatar(radius: 14,
                    backgroundColor: isBatal ? const Color(0xFFFFCDD2) : const Color(0xFFF0EBE4),
                    child: Text(isBatal ? 'X' : (t['metode'] ?? 'C')[0],
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: isBatal ? const Color(0xFFC0392B) : const Color(0xFFD4A574)))),
                  title: Row(children: [
                    Text(t['no_nota'] ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    if (isBatal) ...[
                      const SizedBox(width: 6),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFC0392B), borderRadius: BorderRadius.circular(4)),
                        child: const Text('BATAL', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700))),
                    ],
                  ]),
                  subtitle: Text('${t['user_nama'] ?? '-'} - $tglStr', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(cur.format(t['total'] ?? 0),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                        color: isBatal ? const Color(0xFF999999) : const Color(0xFF27AE60),
                        decoration: isBatal ? TextDecoration.lineThrough : null)),
                    if (!isBatal) IconButton(icon: const Icon(Icons.print, size: 16, color: Color(0xFF2980B9)),
                      onPressed: () => _cetakUlang(t), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28), tooltip: 'Cetak Ulang'),
                    if (!isBatal && isOwner) IconButton(
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Color(0xFFC0392B)),
                      onPressed: () => _konfirmasiBatal(t),
                      padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28), tooltip: 'Batalkan Transaksi'),
                  ])));
            }),
          ],

          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _exportPdf, icon: const Icon(Icons.picture_as_pdf, size: 18), label: const Text('Download PDF'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574)), padding: const EdgeInsets.symmetric(vertical: 14)))),
          const SizedBox(height: 20),
        ])));
  }

  Widget _plRow(String label, double value, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color ?? const Color(0xFF3A2E24))),
      Text(cur.format(value), style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color ?? const Color(0xFF3A2E24)))]));

  Widget _plSub(String label, double value) => Padding(
    padding: const EdgeInsets.only(left: 16, top: 2, bottom: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B))),
      Text(cur.format(value), style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B)))]));

  // ═══ BATALKAN TRANSAKSI ═══
  Future<void> _konfirmasiBatal(Map<String, dynamic> trx) async {
    final konfirmasi = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Batalkan Transaksi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No. Nota: ${trx['no_nota'] ?? '-'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Total: ${cur.format(trx['total'] ?? 0)}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          const Text('Yakin batalkan transaksi ini? Stok bibit dan botol akan dikembalikan. Tindakan ini tidak bisa dibatalkan.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B5B4B))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('TIDAK')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            child: const Text('YA, BATALKAN')),
        ]));
    if (konfirmasi != true) return;
    try {
      await Api.batalkanTransaksi(
        tokoId: widget.toko['id'],
        transaksiId: trx['id'],
        user: widget.user);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transaksi berhasil dibatalkan. Stok sudah dikembalikan.'),
          backgroundColor: Color(0xFF27AE60)));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal membatalkan: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ═══ CETAK ULANG STRUK ═══
  Future<void> _cetakUlang(Map<String, dynamic> trx) async {
    try {
      final full = await Api.getTransaksiWithItems(trx['id']);
      if (full == null) throw 'Transaksi tidak ditemukan';
      final items = (full['items'] as List?) ?? [];
      final tgl = DateTime.tryParse(full['tanggal']?.toString() ?? full['created_at']?.toString() ?? '')?.toLocal();
      final jamStr = tgl != null ? DateFormat('dd/MM/yyyy HH:mm', 'id_ID').format(tgl) : '-';

      final subtotalTrx = ((full['subtotal'] ?? 0) as num).toDouble();
      final diskonTrx = ((full['diskon'] ?? 0) as num).toDouble();
      final totalTrx = ((full['total'] ?? 0) as num).toDouble();
      final pelangganTrx = full['pelanggan_nama']?.toString();

      // Try Bluetooth first
      final btService = BluetoothPrinterService();
      final savedName = await btService.getSavedName();
      if (savedName != null) {
        final itemsList = items.map<Map<String, dynamic>>((i) => {
          'nama': i['nama_item'] ?? '-',
          'qty': ((i['qty'] ?? 1) as num).toInt(),
          'hj': ((i['harga_satuan'] ?? 0) as num).toDouble(),
        }).toList();
        final err = await btService.printStruk(
          nota: '${full['no_nota'] ?? '-'} (ULANG)',
          tokoNama: widget.toko['nama'] ?? 'KS Parfume',
          tokoAlamat: widget.toko['alamat'] ?? '',
          items: itemsList,
          subtotal: subtotalTrx,
          diskon: diskonTrx,
          pelanggan: pelangganTrx,
          total: totalTrx,
          bayar: ((full['bayar'] ?? 0) as num).toDouble(),
          kembalian: ((full['kembalian'] ?? 0) as num).toDouble(),
          metode: full['metode']?.toString() ?? 'Cash',
          jam: jamStr,
          kasir: full['user_nama']?.toString() ?? '-',
        );
        if (err == null) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Struk dicetak via Bluetooth'), backgroundColor: Color(0xFF27AE60)));
          return;
        }
      }

      // Fallback to system print (PDF)
      final pdf = pw.Document();
      pdf.addPage(pw.Page(pageFormat: const PdfPageFormat(72 * PdfPageFormat.mm, double.infinity, marginAll: 5 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Text('KS PARFUME', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text(widget.toko['nama'] ?? '', style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          pw.Text('${full['no_nota'] ?? '-'} (CETAK ULANG)', style: const pw.TextStyle(fontSize: 8)),
          pw.Text(jamStr, style: const pw.TextStyle(fontSize: 8)),
          if (pelangganTrx != null && pelangganTrx.isNotEmpty && pelangganTrx.toLowerCase() != 'walk-in')
            pw.Text('Pelanggan: $pelangganTrx', style: const pw.TextStyle(fontSize: 8)),
          pw.Divider(),
          ...items.map((item) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Expanded(child: pw.Text('${item['nama_item'] ?? '-'}', style: const pw.TextStyle(fontSize: 7))),
            pw.Text('x${item['qty']}', style: const pw.TextStyle(fontSize: 7)),
            pw.Text(cur.format(item['subtotal'] ?? 0), style: const pw.TextStyle(fontSize: 7)),
          ])),
          pw.Divider(),
          if (diskonTrx > 0) ...[
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Subtotal', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(cur.format(subtotalTrx), style: const pw.TextStyle(fontSize: 8))]),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Diskon', style: const pw.TextStyle(fontSize: 8)),
              pw.Text('- ${cur.format(diskonTrx)}', style: const pw.TextStyle(fontSize: 8))]),
          ],
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text(cur.format(totalTrx), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))]),
          pw.SizedBox(height: 8),
          pw.Text('Terima kasih!', style: const pw.TextStyle(fontSize: 8)),
        ])));
      await Printing.layoutPdf(onLayout: (_) async => pdf.save());
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
    }
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as xl;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/api.dart';

class PergerakanScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const PergerakanScreen({super.key, required this.toko});
  @override State<PergerakanScreen> createState() => _PergerakanScreenState();
}

class _PergerakanScreenState extends State<PergerakanScreen> {
  final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
  List<Map<String, dynamic>> _ringkasan = [], _detail = [], _produk = [], _batalItems = [];
  Map<String, double> _saldoAwal = {};
  String _tipe = 'semua', _search = '';
  DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _sampai = DateTime.now();

  @override void initState() { super.initState(); _initAndLoad(); }

  Future<void> _initAndLoad() async {
    // Auto-snapshot saldo awal kalau ini bulan baru (tgl 30 April → tgl 1 Mei otomatis)
    try {
      final dibuat = await Api.autoSnapshotSaldoAwalJikaBulanBaru(widget.toko['id']);
      if (dibuat && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Saldo awal ${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())} otomatis tersimpan dari sisa stok bulan lalu'),
          backgroundColor: const Color(0xFF27AE60),
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    try { // try/catch for network errors
    final detail = await Api.getStokMovement(widget.toko['id'], tipe: _tipe == 'semua' ? null : _tipe);
    final produk = await Api.getProduk(widget.toko['id']);
    final saldoAwal = await Api.getSaldoAwal(widget.toko['id'], _dari.month, _dari.year);
    // Filter detail by date range
    final filtered = detail.where((m) {
      final tgl = DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal();
      if (tgl == null) return true;
      return !tgl.isBefore(DateTime(_dari.year, _dari.month, _dari.day)) && !tgl.isAfter(DateTime(_sampai.year, _sampai.month, _sampai.day, 23, 59, 59));
    }).toList();
    // Hitung ringkasan: mulai dari SEMUA produk (yang punya saldo awal ATAU ada movement)
    final ringkasanMap = <String, Map<String, dynamic>>{};
    // Seed dari semua produk supaya yang tidak ada movement tetap muncul (kalau punya saldo awal)
    for (final p in produk) {
      final pid = p['id'].toString();
      final sa = (saldoAwal[pid] ?? 0).toDouble();
      // Tampilkan kalau ada saldo awal > 0 ATAU ada movement (di-cek nanti)
      if (sa > 0) {
        ringkasanMap[pid] = {
          'produk_id': pid,
          'produk_nama': p['nama'] ?? '?',
          'masuk': 0.0, 'penjualan': 0.0, 'keluar': 0.0,
          'saldo_awal_val': sa,
        };
      }
    }
    // Tambah dari movement (untuk produk yang belum di-seed)
    for (final m in filtered) {
      final pid = (m['produk_id'] ?? '').toString();
      if (pid.isEmpty) continue;
      ringkasanMap.putIfAbsent(pid, () => {
        'produk_id': pid,
        'produk_nama': m['nama_produk'] ?? produk.firstWhere((p) => p['id'].toString() == pid, orElse: () => {'nama': '?'})['nama'],
        'masuk': 0.0, 'penjualan': 0.0, 'keluar': 0.0,
        'saldo_awal_val': (saldoAwal[pid] ?? 0).toDouble(),
      });
      final qty = ((m['qty'] ?? 0) as num).toDouble().abs();
      final tipe = (m['tipe'] ?? '').toString();
      if (tipe == 'masuk') {
        ringkasanMap[pid]!['masuk'] = (ringkasanMap[pid]!['masuk'] as double) + qty;
      } else if (tipe == 'penjualan') {
        ringkasanMap[pid]!['penjualan'] = (ringkasanMap[pid]!['penjualan'] as double) + qty;
      } else {
        ringkasanMap[pid]!['keluar'] = (ringkasanMap[pid]!['keluar'] as double) + qty;
      }
    }
    // ═══ RUMUS SISA: Saldo Awal + Masuk - Jual - Keluar ═══
    for (final r in ringkasanMap.values) {
      final saldoAwalVal = (r['saldo_awal_val'] as num).toDouble();
      final masuk = (r['masuk'] as num).toDouble();
      final jual = (r['penjualan'] as num).toDouble();
      final keluar = (r['keluar'] as num).toDouble();
      r['stok_sekarang'] = saldoAwalVal + masuk - jual - keluar;
    }
    final ringkasan = ringkasanMap.values.toList();
    // Ambil items dari transaksi yang dibatalkan untuk koreksi BIBIT/BOTOL TERPAKAI
    final batalItems = <Map<String, dynamic>>[];
    try {
      final mulai = DateFormat('yyyy-MM-dd').format(_dari);
      final akhir = DateFormat('yyyy-MM-dd').format(_sampai);
      final allTrx = await Api.getTransaksiAll(widget.toko['id'], tanggalMulai: mulai, tanggalAkhir: akhir, limit: 1000);
      final cancelledIds = allTrx.where((t) => t['status'] == 'dibatalkan').map((t) => t['id'].toString()).toList();
      for (final id in cancelledIds) {
        final items = await Api.getTransaksiItems(id);
        batalItems.addAll(items);
      }
    } catch (_) {}
    if (mounted) setState(() { _ringkasan = ringkasan; _detail = filtered; _produk = produk; _saldoAwal = saldoAwal; _batalItems = batalItems; });
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e'), backgroundColor: Colors.red)); }
  }

  Future<void> _simpanSaldoAwal() async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Simpan Saldo Awal?', style: TextStyle(fontSize: 14)),
      content: Text('Stok saat ini akan disimpan sebagai saldo awal bulan ${DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now())}. Lakukan ini setiap awal bulan.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Simpan')),
      ]));
    if (confirm == true) {
      await Api.simpanSaldoAwalBulanIni(widget.toko['id']);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saldo awal tersimpan!'), backgroundColor: Color(0xFF27AE60)));
    }
  }

  Future<void> _pilihTanggal(bool isDari) async {
    final picked = await showDatePicker(context: context, initialDate: isDari ? _dari : _sampai, firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) { setState(() { if (isDari) {
      _dari = picked;
    } else {
      _sampai = picked;
    } }); _load(); }
  }

  // ═══ EXPORT EXCEL — RAPI ═══
  Future<void> _exportExcel() async {
    if (_ringkasan.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Tidak ada data untuk di-export'), backgroundColor: Color(0xFFE67E22)));
      return;
    }

    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
          SizedBox(width: 12), Text('Membuat Excel...'),
        ]),
        duration: Duration(seconds: 5), backgroundColor: Color(0xFF2980B9)));

      final excel = xl.Excel.createExcel();
      excel.delete('Sheet1');
      final sheet = excel['Pergerakan Stok'];

      // ═══ STYLE ═══
      final headerStyle = xl.CellStyle(
        bold: true,
        fontSize: 11,
        backgroundColorHex: xl.ExcelColor.fromHexString('#D4A574'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
        verticalAlign: xl.VerticalAlign.Center,
      );
      final titleStyle = xl.CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: xl.ExcelColor.fromHexString('#3A2E24'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final subTitleStyle = xl.CellStyle(
        fontSize: 10,
        italic: true,
        fontColorHex: xl.ExcelColor.fromHexString('#6B5B4B'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final numberStyle = xl.CellStyle(
        fontSize: 10,
        horizontalAlign: xl.HorizontalAlign.Right,
      );
      final textStyle = xl.CellStyle(fontSize: 10);
      final totalStyle = xl.CellStyle(
        bold: true,
        fontSize: 11,
        backgroundColorHex: xl.ExcelColor.fromHexString('#FAF8F5'),
        horizontalAlign: xl.HorizontalAlign.Right,
      );

      // ═══ HEADER LAPORAN ═══
      sheet.merge(xl.CellIndex.indexByString('A1'), xl.CellIndex.indexByString('G1'));
      final cTitle = sheet.cell(xl.CellIndex.indexByString('A1'));
      cTitle.value = xl.TextCellValue('KS PARFUME');
      cTitle.cellStyle = titleStyle;

      sheet.merge(xl.CellIndex.indexByString('A2'), xl.CellIndex.indexByString('G2'));
      final cSub = sheet.cell(xl.CellIndex.indexByString('A2'));
      cSub.value = xl.TextCellValue('Laporan Pergerakan Stok');
      cSub.cellStyle = subTitleStyle;

      sheet.merge(xl.CellIndex.indexByString('A3'), xl.CellIndex.indexByString('G3'));
      final cPeriode = sheet.cell(xl.CellIndex.indexByString('A3'));
      cPeriode.value = xl.TextCellValue('Periode: ${dateFmt.format(_dari)} — ${dateFmt.format(_sampai)}');
      cPeriode.cellStyle = subTitleStyle;

      sheet.merge(xl.CellIndex.indexByString('A4'), xl.CellIndex.indexByString('G4'));
      final cToko = sheet.cell(xl.CellIndex.indexByString('A4'));
      cToko.value = xl.TextCellValue('Toko: ${widget.toko['nama'] ?? '-'}  ·  Dicetak: ${DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(DateTime.now())}');
      cToko.cellStyle = subTitleStyle;

      // Row 5 kosong (spacer)

      // ═══ HEADER TABEL (row 6) ═══
      const headers = ['No', 'Produk', 'Saldo Awal', 'Masuk', 'Jual', 'Keluar', 'Sisa'];
      for (var i = 0; i < headers.length; i++) {
        final c = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 5));
        c.value = xl.TextCellValue(headers[i]);
        c.cellStyle = headerStyle;
      }

      // ═══ DATA ROWS ═══
      // Sort by produk_nama
      final sorted = List<Map<String, dynamic>>.from(_ringkasan)
        ..sort((a, b) => (a['produk_nama'] ?? '').toString().compareTo((b['produk_nama'] ?? '').toString()));

      double tSaldoAwal = 0, tMasuk = 0, tJual = 0, tKeluar = 0, tSisa = 0;

      for (var i = 0; i < sorted.length; i++) {
        final r = sorted[i];
        final rowIdx = 6 + i;
        final saldoAwal = ((r['saldo_awal_val'] ?? 0) as num).toDouble();
        final masuk = ((r['masuk'] ?? 0) as num).toDouble();
        final jual = ((r['penjualan'] ?? 0) as num).toDouble();
        final keluar = ((r['keluar'] ?? 0) as num).toDouble();
        final sisa = ((r['stok_sekarang'] ?? 0) as num).toDouble();

        tSaldoAwal += saldoAwal;
        tMasuk += masuk;
        tJual += jual;
        tKeluar += keluar;
        tSisa += sisa;

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIdx))
          ..value = xl.IntCellValue(i + 1)
          ..cellStyle = numberStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIdx))
          ..value = xl.TextCellValue((r['produk_nama'] ?? '-').toString())
          ..cellStyle = textStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIdx))
          ..value = xl.DoubleCellValue(saldoAwal)
          ..cellStyle = numberStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIdx))
          ..value = xl.DoubleCellValue(masuk)
          ..cellStyle = numberStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIdx))
          ..value = xl.DoubleCellValue(jual)
          ..cellStyle = numberStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIdx))
          ..value = xl.DoubleCellValue(keluar)
          ..cellStyle = numberStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIdx))
          ..value = xl.DoubleCellValue(sisa)
          ..cellStyle = numberStyle;
      }

      // ═══ TOTAL ROW ═══
      final totalRow = 6 + sorted.length;
      sheet.merge(
        xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow),
        xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: totalRow));
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: totalRow))
        ..value = xl.TextCellValue('TOTAL')
        ..cellStyle = totalStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: totalRow))
        ..value = xl.DoubleCellValue(tSaldoAwal)
        ..cellStyle = totalStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow))
        ..value = xl.DoubleCellValue(tMasuk)
        ..cellStyle = totalStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: totalRow))
        ..value = xl.DoubleCellValue(tJual)
        ..cellStyle = totalStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: totalRow))
        ..value = xl.DoubleCellValue(tKeluar)
        ..cellStyle = totalStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: totalRow))
        ..value = xl.DoubleCellValue(tSisa)
        ..cellStyle = totalStyle;

      // ═══ COLUMN WIDTH ═══
      sheet.setColumnWidth(0, 6);   // No
      sheet.setColumnWidth(1, 32);  // Produk
      sheet.setColumnWidth(2, 14);  // Saldo Awal
      sheet.setColumnWidth(3, 12);  // Masuk
      sheet.setColumnWidth(4, 12);  // Jual
      sheet.setColumnWidth(5, 12);  // Keluar
      sheet.setColumnWidth(6, 14);  // Sisa

      // ═══ SAVE & SHARE ═══
      final bytes = excel.save();
      if (bytes == null) throw 'Gagal generate Excel';
      final dir = await getTemporaryDirectory();
      final periodeStr = '${DateFormat('yyyyMMdd').format(_dari)}_${DateFormat('yyyyMMdd').format(_sampai)}';
      final file = File('${dir.path}/pergerakan_stok_${widget.toko['nama'] ?? 'toko'}_$periodeStr.xlsx'
        .replaceAll(' ', '_'));
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await Share.shareXFiles([XFile(file.path)],
        text: 'Pergerakan Stok ${dateFmt.format(_dari)} - ${dateFmt.format(_sampai)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal export: $e'), backgroundColor: Colors.red));
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pergerakan Stok', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.file_download, size: 20), onPressed: _exportExcel, tooltip: 'Export Excel'),
          IconButton(icon: const Icon(Icons.bookmark_add, size: 20), onPressed: _simpanSaldoAwal, tooltip: 'Simpan Saldo Awal Bulan Ini'),
        ]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        // Search
        TextField(onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(hintText: 'Cari produk...', prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true), style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        // Quick filter
        Wrap(spacing: 6, children: ['hari', 'bulan', 'tahun', 'semua'].map((p) => ActionChip(label: Text({'hari': 'Hari Ini', 'bulan': 'Bulan Ini', 'tahun': 'Tahun Ini', 'semua': 'Semua'}[p]!, style: const TextStyle(fontSize: 10)),
          onPressed: () => _setQuick(p), backgroundColor: const Color(0xFFFAF8F5))).toList()),
        const SizedBox(height: 10),

        // Date picker
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => _pilihTanggal(true),
            child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_dari), style: const TextStyle(fontSize: 11))])))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-', style: TextStyle(color: Color(0xFFA09080)))),
          Expanded(child: GestureDetector(onTap: () => _pilihTanggal(false),
            child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_sampai), style: const TextStyle(fontSize: 11))])))),
        ]),
        const SizedBox(height: 12),

        // Tipe filter
        Wrap(spacing: 6, children: ['semua', 'masuk', 'penjualan', 'keluar'].map((t) => ChoiceChip(label: Text(t == 'semua' ? 'Semua' : t[0].toUpperCase() + t.substring(1), style: TextStyle(fontSize: 11, color: _tipe == t ? Colors.white : const Color(0xFF6B5B4B))),
          selected: _tipe == t, onSelected: (_) { setState(() => _tipe = t); _load(); }, selectedColor: const Color(0xFFD4A574))).toList()),
        const SizedBox(height: 16),

        // ═══ SUMMARY: BOTOL & BIBIT TERPAKAI ═══
        Builder(builder: (_) {
          double totalBotolJual = 0, totalBibitJual = 0;
          double totalBotolSisa = 0, totalBibitSisa = 0;
          for (final r in _ringkasan) {
            final pid = r['produk_id'];
            final p = _produk.firstWhere((x) => x['id'] == pid, orElse: () => {});
            final kat = (p['kategori'] ?? '').toString();
            final jual = ((r['penjualan'] ?? 0) as num).toDouble();
            final sisa = ((r['stok_sekarang'] ?? 0) as num).toDouble();
            if (kat.contains('BOTOL') || kat.contains('SPRAY')) {
              totalBotolJual += jual;
              totalBotolSisa += sisa;
            } else if (kat.contains('PARFUME')) {
              totalBibitJual += jual;
              totalBibitSisa += sisa;
            }
          }
          // Kurangi transaksi yang dibatalkan agar angka net akurat
          for (final item in _batalItems) {
            final varianId = item['varian_id'];
            final produkId = item['produk_id']?.toString();
            final botolId = item['botol_id']?.toString();
            final qty = ((item['qty'] ?? 0) as num).toInt();
            final resepBibit = ((item['resep_bibit'] ?? 0) as num).toDouble();
            if (varianId != null) {
              if (produkId != null && resepBibit > 0) {
                final p = _produk.firstWhere((x) => x['id'].toString() == produkId, orElse: () => {});
                if ((p['kategori'] ?? '').toString().contains('PARFUME')) totalBibitJual -= resepBibit * qty;
              }
              if (botolId != null && botolId.isNotEmpty) {
                final b = _produk.firstWhere((x) => x['id'].toString() == botolId, orElse: () => {});
                final bk = (b['kategori'] ?? '').toString();
                if (bk.contains('BOTOL') || bk.contains('SPRAY')) totalBotolJual -= qty;
              }
            } else if (produkId != null) {
              final p = _produk.firstWhere((x) => x['id'].toString() == produkId, orElse: () => {});
              if ((p['kategori'] ?? '').toString().contains('PARFUME')) totalBibitJual -= qty;
              if (botolId != null && botolId.isNotEmpty) {
                final b = _produk.firstWhere((x) => x['id'].toString() == botolId, orElse: () => {});
                final bk = (b['kategori'] ?? '').toString();
                if (bk.contains('BOTOL') || bk.contains('SPRAY')) totalBotolJual -= qty;
              }
            }
          }
          totalBibitJual = totalBibitJual.clamp(0.0, double.infinity);
          totalBotolJual = totalBotolJual.clamp(0.0, double.infinity);
          return Row(children: [
            Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              const Icon(Icons.science, color: Color(0xFFD4A574), size: 22),
              const SizedBox(height: 4),
              const Text('BIBIT TERPAKAI', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Color(0xFFA09080), letterSpacing: 1)),
              Text('${totalBibitJual.round()} ml', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
              Text('Sisa: ${totalBibitSisa.round()} ml', style: const TextStyle(fontSize: 10, color: Color(0xFF27AE60))),
            ])))),
            Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
              const Icon(Icons.local_drink, color: Color(0xFF2980B9), size: 22),
              const SizedBox(height: 4),
              const Text('BOTOL TERPAKAI', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Color(0xFFA09080), letterSpacing: 1)),
              Text('${totalBotolJual.round()} pcs', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
              Text('Sisa: ${totalBotolSisa.round()} pcs', style: const TextStyle(fontSize: 10, color: Color(0xFF27AE60))),
            ])))),
          ]);
        }),
        const SizedBox(height: 16),

        // Ringkasan tabel with Saldo Awal
        Text('Ringkasan (${_ringkasan.where((r) => _search.isEmpty || (r['produk_nama'] ?? '').toString().toLowerCase().contains(_search.toLowerCase())).length} item)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
          columnSpacing: 12, headingRowHeight: 36, dataRowMinHeight: 36, dataRowMaxHeight: 44,
          columns: ['Produk', 'Saldo Awal', 'Masuk', 'Jual', 'Keluar', 'Sisa'].map((c) => DataColumn(label: Text(c, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600)), numeric: c != 'Produk')).toList(),
          rows: _ringkasan.where((r) => _search.isEmpty || (r['produk_nama'] ?? '').toString().toLowerCase().contains(_search.toLowerCase())).map((r) {
            final saldoAwal = _saldoAwal[r['produk_id'].toString()] ?? 0;
            return DataRow(cells: [
              DataCell(Text('${r['produk_nama']}', style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis)),
              DataCell(Text(saldoAwal.round().toString(), style: TextStyle(fontSize: 11, color: saldoAwal > 0 ? const Color(0xFF8E44AD) : Colors.grey, fontWeight: saldoAwal > 0 ? FontWeight.w600 : FontWeight.w400))),
              DataCell(Text('${((r['masuk'] ?? 0) as num).round()}', style: TextStyle(fontSize: 11, color: (r['masuk'] as num? ?? 0) > 0 ? Colors.green : Colors.grey, fontWeight: (r['masuk'] as num? ?? 0) > 0 ? FontWeight.w600 : FontWeight.w400))),
              DataCell(Text('${((r['penjualan'] ?? 0) as num).round()}', style: TextStyle(fontSize: 11, color: (r['penjualan'] as num? ?? 0) > 0 ? const Color(0xFF2980B9) : Colors.grey, fontWeight: (r['penjualan'] as num? ?? 0) > 0 ? FontWeight.w600 : FontWeight.w400))),
              DataCell(Text('${((r['keluar'] ?? 0) as num).round()}', style: TextStyle(fontSize: 11, color: (r['keluar'] as num? ?? 0) > 0 ? Colors.orange : Colors.grey))),
              DataCell(Text('${((r['stok_sekarang'] ?? 0) as num).round()}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
            ]);
          }).toList())),

        const SizedBox(height: 24),
        Text('Detail Log (${_detail.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._detail.take(80).map((m) { final p = _produk.firstWhere((x) => x['id'] == m['produk_id'], orElse: () => {'nama': '?'}); final q = (m['qty'] as num? ?? 0).toDouble();
          final tgl = DateTime.tryParse((m['created_at'] ?? '').toString())?.toLocal();
          final tglStr = tgl != null ? DateFormat('d MMM yyyy HH:mm', 'id_ID').format(tgl) : '-';
          return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
            leading: Icon(q >= 0 ? Icons.arrow_downward : Icons.arrow_upward, color: q >= 0 ? Colors.green : const Color(0xFF2980B9), size: 18),
            title: Text('${p['nama']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            subtitle: Text('$tglStr - ${m['keterangan'] ?? '-'}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
            trailing: Text('${q >= 0 ? '+' : ''}${q.round()}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: q >= 0 ? Colors.green : Colors.red))));
        }),
      ])),
    );
  }
}

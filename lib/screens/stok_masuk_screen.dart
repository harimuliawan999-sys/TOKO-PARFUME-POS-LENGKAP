import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../services/api.dart';

class StokMasukScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const StokMasukScreen({super.key, required this.toko, required this.user});
  @override State<StokMasukScreen> createState() => _StokMasukScreenState();
}

class _StokMasukScreenState extends State<StokMasukScreen> with SingleTickerProviderStateMixin {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd-MMM-yyyy', 'id_ID');
  late TabController _tab;
  List<Map<String, dynamic>> _produk = [], _riwayat = [], _varian = [];
  DateTime _tglMasuk = DateTime.now();
  final TextEditingController _hargaBeliCtrl = TextEditingController();
  String _searchMasuk = '';
  String get tokoId => widget.toko['id'];

  // Stok Masuk form
  String? _mProdukId;
  String _mQty = '';
  // Stok Keluar form
  String? _kProdukId;
  String _kQty = '', _kKeterangan = 'Rusak';
  bool _saving = false;
  // Batch items for PDF
  final List<Map<String, dynamic>> _batchItems = [];

  @override void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tab.dispose(); _hargaBeliCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final produk = await Api.getProduk(tokoId);
      final riwayat = await Api.getStokMovement(tokoId, limit: 100);
      final varian = await Api.getVarian(tokoId);
      if (mounted) {
        setState(() {
        _produk = produk.where((p) => ['STOCK PARFUME', 'STOK BOTOL', 'STOK SPRAY'].contains(p['kategori'])).toList();
        _riwayat = riwayat;
        _varian = varian;
      });
      }
    } catch (_) {}
  }

  Future<void> _simpanMasuk() async {
    if (_mProdukId == null || _mQty.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih produk dan isi qty!'))); return; }
    setState(() => _saving = true);
    try {
      final qty = double.tryParse(_mQty) ?? 0;
      final p = _produk.firstWhere((x) => x['id'].toString() == _mProdukId, orElse: () => {'nama': '-', 'harga_beli': 0});
      await Api.tambahStokMasuk(tokoId, _mProdukId!, qty, widget.user['id'], tanggal: _tglMasuk);
      final hargaBeli = double.tryParse(_hargaBeliCtrl.text.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0;
      if (hargaBeli > 0) await Api.updateProduk(_mProdukId!, {'harga_beli': hargaBeli});
      final finalHarga = hargaBeli > 0 ? hargaBeli : ((p['harga_beli'] ?? 0) as num).toDouble();
      // Add to batch for PDF
      _batchItems.add({'nama': p['nama'], 'qty': qty, 'harga_beli': finalHarga, 'amount': qty * finalHarga});
      setState(() { _mQty = ''; _hargaBeliCtrl.clear(); _mProdukId = null; });
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok masuk berhasil!'), backgroundColor: Color(0xFF27AE60)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    setState(() => _saving = false);
  }

  Future<void> _simpanKeluar() async {
    if (_kProdukId == null || _kQty.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pilih produk dan isi qty!'))); return; }
    setState(() => _saving = true);
    try {
      final qty = double.tryParse(_kQty) ?? 0;
      await Api.tambahStokKeluar(tokoId, _kProdukId!, qty, widget.user['id'], _kKeterangan);
      setState(() { _kQty = ''; _kKeterangan = 'Rusak'; _kProdukId = null; });
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stok keluar dicatat!'), backgroundColor: Color(0xFFD4A574)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    setState(() => _saving = false);
  }

  String _produkLabel(String? id) {
    if (id == null) return 'Pilih produk';
    final p = _produk.firstWhere((x) => x['id'].toString() == id, orElse: () => {});
    return p.isEmpty ? 'Pilih produk' : '${p['nama']} (stok: ${p['stok']})';
  }

  void _showProdukPicker({required String? currentId, required void Function(String, Map<String, dynamic>) onPick}) {
    String q = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final list = q.isEmpty ? _produk : _produk.where((p) => (p['nama'] ?? '').toString().toLowerCase().contains(q.toLowerCase())).toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(children: [
              Container(margin: const EdgeInsets.only(top: 10, bottom: 6), width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
              const Text('Pilih Produk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  autofocus: true,
                  onChanged: (v) => setS(() => q = v),
                  decoration: InputDecoration(
                    hintText: 'Cari nama produk...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true, fillColor: Colors.grey[50],
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 6),
              const Divider(height: 1),
              Expanded(
                child: list.isEmpty
                  ? const Center(child: Text('Produk tidak ditemukan', style: TextStyle(color: Colors.grey, fontSize: 12)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final isSel = p['id'].toString() == currentId;
                        return ListTile(
                          dense: true,
                          selected: isSel,
                          selectedTileColor: const Color(0xFFD4A574).withOpacity(0.1),
                          title: Text('${p['nama']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          subtitle: Text('Stok: ${p['stok']}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                          trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFFD4A574), size: 18) : null,
                          onTap: () { Navigator.pop(ctx); onPick(p['id'].toString(), p); },
                        );
                      }),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ═══ IMPORT CSV MASAL ═══
  Future<void> _importCsv() async {
    try {
      // withData:true wajib di Android (scoped storage — path bisa null)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'txt'], withData: true);
      if (result == null) return;
      final f = result.files.single;
      final text = f.bytes != null
          ? utf8.decode(f.bytes!, allowMalformed: true)
          : await File(f.path!).readAsString();
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File kosong atau format salah'))); return; }

      final hdr = lines[0].split(RegExp(r'[,\t;]'));
      final nameIdx = hdr.indexWhere((h) => h.toLowerCase().contains('nama') || h.toLowerCase().contains('product') || h.toLowerCase().contains('name'));
      final qtyIdx = hdr.indexWhere((h) => h.toLowerCase().contains('qty') || h.toLowerCase().contains('jumlah'));
      final priceIdx = hdr.indexWhere((h) => h.toLowerCase().contains('harga') || h.toLowerCase().contains('price') || h.toLowerCase().contains('beli'));

      if (nameIdx < 0 || qtyIdx < 0) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kolom nama/qty tidak ditemukan'), backgroundColor: Colors.red)); return; }

      int count = 0;
      for (int i = 1; i < lines.length; i++) {
        final cols = lines[i].split(RegExp(r'[,\t;]'));
        final nama = cols.length > nameIdx ? cols[nameIdx].trim() : '';
        final qty = cols.length > qtyIdx ? (double.tryParse(cols[qtyIdx].trim()) ?? 0) : 0.0;
        final harga = priceIdx >= 0 && cols.length > priceIdx ? (double.tryParse(cols[priceIdx].trim()) ?? 0) : 0.0;
        if (nama.isEmpty || qty <= 0) continue;

        // Cari produk matching
        final match = _produk.firstWhere((p) => (p['nama'] ?? '').toString().toLowerCase().contains(nama.toLowerCase()), orElse: () => {});
        if (match.isNotEmpty) {
          await Api.tambahStokMasuk(tokoId, match['id'].toString(), qty, widget.user['id']);
          if (harga > 0) await Api.updateProduk(match['id'].toString(), {'harga_beli': harga});
          _batchItems.add({'nama': match['nama'], 'qty': qty, 'harga_beli': harga > 0 ? harga : ((match['harga_beli'] ?? 0) as num).toDouble(), 'amount': qty * (harga > 0 ? harga : ((match['harga_beli'] ?? 0) as num).toDouble())});
          count++;
        }
      }
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('OK: $count item diimport!'), backgroundColor: const Color(0xFF27AE60)));
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red)); }
  }

  // ═══ EXPORT CSV ═══
  Future<void> _exportCsv() async {
    try {
      final masuk = _riwayat.where((r) => r['tipe'] == 'masuk').toList();
      String csv = 'No,Produk,Qty,Tanggal\n';
      for (int i = 0; i < masuk.length; i++) {
        final r = masuk[i];
        final p = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {'nama': '?'});
        csv += '${i + 1},${p['nama']},${((r['qty'] ?? 0) as num).abs().round()},${r['created_at'] ?? '-'}\n';
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/stok_masuk_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles([XFile(file.path)], text: 'Data Stok Masuk KS Parfume');
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red)); }
  }

  // ═══ PDF FAKTUR (INCOMING STOCK — format Olsera) ═══
  Future<void> _cetakFakturPdf() async {
    if (_batchItems.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Belum ada item stok masuk hari ini'))); return; }
    final pdf = pw.Document();
    final now = DateTime.now();
    final noFaktur = '#IN${DateFormat('yyMMdd').format(now)}${now.millisecondsSinceEpoch % 99999}'.padRight(18, '0');
    final totalQty = _batchItems.fold(0.0, (double s, i) => s + ((i['qty'] as num?) ?? 0).toDouble());
    final totalAmount = _batchItems.fold(0.0, (double s, i) => s + ((i['amount'] as num?) ?? 0).toDouble());

    pdf.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(40),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        // Header
        pw.Container(width: 60, height: 40, decoration: pw.BoxDecoration(color: PdfColor.fromHex('#1A1510'), borderRadius: pw.BorderRadius.circular(4)),
          child: pw.Center(child: pw.Text('KS', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.white)))),
        pw.SizedBox(height: 12),
        pw.Text('Incoming Stock No. $noFaktur ${widget.toko['nama'] ?? ''}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('Date : ${dateFmt.format(now)}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.Text('Posted : ksparfume13@gmail.com', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 16),
        // Table
        pw.Table(border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {0: const pw.FixedColumnWidth(30), 1: const pw.FlexColumnWidth(3), 2: const pw.FixedColumnWidth(60), 3: const pw.FixedColumnWidth(80), 4: const pw.FixedColumnWidth(90)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('#', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Product', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Qty', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Buy Price', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Amount', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
            ]),
            ..._batchItems.asMap().entries.map((e) => pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e.key + 1}', style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${e.value['nama']}', style: const pw.TextStyle(fontSize: 9))),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${((e.value['qty'] as num?) ?? 0).round()}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cur.format(e.value['harga_beli'] ?? 0), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cur.format(e.value['amount'] ?? 0), style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.right)),
            ])),
            // Total row
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey100), children: [
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Total', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${totalQty.round()}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('')),
              pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(cur.format(totalAmount), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.red), textAlign: pw.TextAlign.right)),
            ]),
          ]),
      ])));

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/incoming_stock_${DateFormat('yyyyMMdd_HHmm').format(now)}.pdf');
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)], text: 'Incoming Stock KS Parfume');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Faktur PDF dibuat!'), backgroundColor: Color(0xFF27AE60)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stok Masuk / Keluar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: TabBar(controller: _tab, indicatorColor: const Color(0xFFD4A574), labelColor: const Color(0xFFD4A574), unselectedLabelColor: const Color(0xFF8B7355),
          tabs: const [Tab(text: 'Stok Masuk'), Tab(text: 'Stok Keluar')])),
      body: TabBarView(controller: _tab, children: [
        // ═══ TAB STOK MASUK ═══
        RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
          // Action buttons
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: _importCsv, icon: const Icon(Icons.upload_file, size: 16),
              label: const Text('Import CSV', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2980B9), side: const BorderSide(color: Color(0xFF2980B9))))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(onPressed: _exportCsv, icon: const Icon(Icons.download, size: 16),
              label: const Text('Export CSV', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF27AE60), side: const BorderSide(color: Color(0xFF27AE60))))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(onPressed: _cetakFakturPdf, icon: const Icon(Icons.picture_as_pdf, size: 16),
              label: const Text('PDF Faktur', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574))))),
          ]),
          const SizedBox(height: 6),
          if (_batchItems.isNotEmpty) Container(
            padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(color: const Color(0xFFD4A574).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_batchItems.length} item masuk hari ini', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD4A574))),
              GestureDetector(onTap: () => setState(() => _batchItems.clear()), child: const Text('Reset', style: TextStyle(fontSize: 10, color: Color(0xFFC0392B)))),
            ])),
          // Tanggal hari ini
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFF27AE60).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context, initialDate: _tglMasuk,
                    firstDate: DateTime(2024), lastDate: DateTime.now(),
                  );
                  if (picked != null && mounted) setState(() => _tglMasuk = picked);
                },
                child: Row(children: [
                  const Icon(Icons.calendar_today, size: 14, color: Color(0xFF27AE60)),
                  const SizedBox(width: 8),
                  Text('Tanggal: ${DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(_tglMasuk)}',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF27AE60), fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  const Icon(Icons.edit_calendar, size: 13, color: Color(0xFF27AE60)),
                ])),
            ])),
          // Form
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Catat Pembelian Bahan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showProdukPicker(
                currentId: _mProdukId,
                onPick: (id, p) {
                  final hb = ((p['harga_beli'] ?? 0) as num).toDouble();
                  setState(() {
                    _mProdukId = id;
                    if (hb > 0) _hargaBeliCtrl.text = hb.toStringAsFixed(0);
                  });
                },
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade600), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  Expanded(child: Text(_produkLabel(_mProdukId), style: TextStyle(fontSize: 12, color: _mProdukId != null ? Colors.black87 : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.search, size: 16, color: Color(0xFFD4A574)),
                ]),
              ),
            ),
            const SizedBox(height: 6),
            if (_mProdukId != null) Builder(builder: (_) {
              final varianProduk = _varian.where((v) => v['produk_id'] == _mProdukId).toList();
              if (varianProduk.isEmpty) return const SizedBox();
              final hargaList = varianProduk.map((v) => (v['harga_jual'] as num?)?.toDouble() ?? 0).where((h) => h > 0).toList();
              if (hargaList.isEmpty) return const SizedBox();
              final minH = hargaList.reduce((a, b) => a < b ? a : b);
              final maxH = hargaList.reduce((a, b) => a > b ? a : b);
              final range = minH == maxH ? cur.format(minH) : '${cur.format(minH)} - ${cur.format(maxH)}';
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(color: const Color(0xFFD4A574).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Harga Jual Varian:', style: TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                  Text(range, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD4A574))),
                ]));
            }),
            const SizedBox(height: 6),
            TextField(onChanged: (v) => _mQty = v, keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Qty (ml/pcs)')),
            const SizedBox(height: 10),
            TextField(controller: _hargaBeliCtrl, keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Harga Beli (Rp)', hintText: 'Opsional -- isi saat pertama atau berubah')),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _saving ? null : _simpanMasuk, icon: const Icon(Icons.add_circle, size: 18),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan Stok Masuk'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)))),
          ]))),
          const SizedBox(height: 12),
          // Import info
          const Card(child: Padding(padding: EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Format Import CSV:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('Kolom: nama/product, qty/jumlah, harga/price', style: TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            Text('Contoh: BIBIT Avril, 100, 500', style: TextStyle(fontSize: 10, color: Color(0xFFA09080))),
          ]))),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Riwayat Stok Masuk', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('${_riwayat.where((r) => r['tipe'] == 'masuk').length} catatan', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
          ]),
          const SizedBox(height: 6),
          TextField(
            onChanged: (v) => setState(() => _searchMasuk = v),
            decoration: InputDecoration(
              hintText: 'Cari nama produk...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true, fillColor: Colors.white,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),
          ..._riwayat.where((r) {
            if (r['tipe'] != 'masuk') return false;
            if (_searchMasuk.isEmpty) return true;
            final p = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {});
            return (p['nama'] ?? '').toString().toLowerCase().contains(_searchMasuk.toLowerCase());
          }).take(50).map((r) {
            final p = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {'nama': '?', 'harga_beli': 0});
            final tgl = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
            final hb = ((p['harga_beli'] ?? 0) as num).toDouble();
            return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
              leading: const Icon(Icons.add_circle, color: Color(0xFF27AE60), size: 20),
              title: Text('${p['nama']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              subtitle: Text('${tgl != null ? DateFormat('d MMM yyyy HH:mm', 'id_ID').format(tgl) : 'Tanggal tidak tersedia'}${hb > 0 ? ' · Beli: ${cur.format(hb)}' : ''}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
              trailing: Text('+${((r['qty'] ?? 0) as num).abs().round()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF27AE60)))));
          }),
        ])),

        // ═══ TAB STOK KELUAR ═══
        RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Catat Stok Keluar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const Text('Untuk barang rusak, hilang, sample, dll', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _showProdukPicker(
                currentId: _kProdukId,
                onPick: (id, p) => setState(() => _kProdukId = id),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade600), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  Expanded(child: Text(_produkLabel(_kProdukId), style: TextStyle(fontSize: 12, color: _kProdukId != null ? Colors.black87 : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.search, size: 16, color: Color(0xFFC0392B)),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            TextField(onChanged: (v) => _kQty = v, keyboardType: TextInputType.number,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Qty')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(value: _kKeterangan,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, labelText: 'Alasan'),
              items: ['Rusak', 'Hilang', 'Sample', 'Expired', 'Transfer', 'Lainnya'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
              onChanged: (v) => setState(() => _kKeterangan = v!)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _saving ? null : _simpanKeluar, icon: const Icon(Icons.remove_circle, size: 18),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan Stok Keluar'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B), padding: const EdgeInsets.symmetric(vertical: 12)))),
          ]))),
          const SizedBox(height: 16),
          const Text('Riwayat Stok Keluar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._riwayat.where((r) => r['tipe'] == 'keluar').take(20).map((r) {
            final p = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {'nama': '?'});
            final tgl = DateTime.tryParse((r['created_at'] ?? '').toString())?.toLocal();
            return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
              leading: const Icon(Icons.remove_circle, color: Color(0xFFC0392B), size: 20),
              title: Text('${p['nama']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
              subtitle: Text('${r['keterangan'] ?? '-'} ${tgl != null ? DateFormat('dd/MM HH:mm', 'id_ID').format(tgl) : ''}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
              trailing: Text('${((r['qty'] ?? 0) as num).round()}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC0392B)))));
          }),
        ])),
      ]),
    );
  }
}

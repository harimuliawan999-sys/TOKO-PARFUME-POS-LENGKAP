import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'dart:typed_data';
import '../services/api.dart';

class KatalogProdukScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const KatalogProdukScreen({super.key, required this.toko});
  @override State<KatalogProdukScreen> createState() => _KatalogProdukScreenState();
}

class _KatalogProdukScreenState extends State<KatalogProdukScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _produk = [], _varian = [], _allProduk = [];
  Map<String, List<Map<String, dynamic>>> _grouped = {};
  String _search = '';
  bool _loading = true, _importing = false;
  double _progressImport = 0;
  String _progressLabel = '';
  final Set<String> _expandedResep = {};
  String get tokoId => widget.toko['id'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final produk = await Api.getProduk(tokoId);
      final varian = await Api.getVarian(tokoId);
      final grouped = <String, List<Map<String, dynamic>>>{};
      for (final v in varian) {
        grouped.putIfAbsent(v['produk_id'].toString(), () => []).add(v);
      }
      if (mounted) {
        setState(() {
        _allProduk = produk;
        _produk = produk.where((p) => p['kategori'] == 'STOCK PARFUME').toList();
        _varian = varian;
        _grouped = grouped;
        _loading = false;
      });
      }
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  // ═══ IMPORT XLSX FORMAT OLSERA ═══
  // Patch xlsx bytes: hapus kolom > 9 agar tidak error "Reached Max 16384" (Olsera export)
  Uint8List _patchXlsxCols(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();
      for (final f in archive.files) {
        if (!f.isFile) continue;
        List<int> content = List<int>.from(f.content as List<int>);
        if (f.name.startsWith('xl/worksheets/') && f.name.endsWith('.xml')) {
          String xml = utf8.decode(content, allowMalformed: true);
          xml = xml.replaceAll(RegExp(r'<dimension[^/]*/?>'), '');
          xml = xml.replaceAll(RegExp(r'<c r="(?:[J-Z]|[A-Z]{2,})\d+"[^>]*/>', dotAll: true), '');
          xml = xml.replaceAll(RegExp(r'<c r="(?:[J-Z]|[A-Z]{2,})\d+"[^>]*>.*?</c>', dotAll: true), '');
          content = utf8.encode(xml);
        }
        newArchive.addFile(ArchiveFile(f.name, content.length, content));
      }
      final encoded = ZipEncoder().encode(newArchive);
      if (encoded != null) return Uint8List.fromList(encoded);
    } catch (_) {}
    return bytes;
  }


  // ─── Import Produk dari CSV ─────────────────────────────────────────────────
  Future<void> _importCsvProduk() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'txt'], withData: true);
      if (result == null) return;
      setState(() { _importing = true; _progressImport = 0; _progressLabel = 'Membaca CSV...'; });

      final f0 = result.files.single;
      final bytes = f0.bytes ?? (f0.path != null ? await File(f0.path!).readAsBytes() : null);
      if (bytes == null || bytes.isEmpty) throw 'File tidak dapat dibaca';
      String raw = utf8.decode(bytes, allowMalformed: true);
      if (raw.codeUnitAt(0) == 0xFEFF) raw = raw.substring(1);

      final sep = raw.split('\n').first.contains(';') ? ';' : ',';
      final csvRows = CsvToListConverter(fieldDelimiter: sep, eol: '\n').convert(raw);
      if (csvRows.length < 2) throw 'File kosong';

      final headerRow = csvRows.first.map((c) => c.toString().toLowerCase().trim()).toList();
      final headers = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) { if (headerRow[i].isNotEmpty) headers[headerRow[i]] = i; }

      final nameIdx = headers['name'] ?? headers['nama'] ?? headers['product_name'];
      final variantNamesIdx = headers['variant_names'] ?? headers['variants'] ?? headers['variant'] ?? headers['product_variant_name'];
      if (nameIdx == null) throw 'Kolom "name" tidak ditemukan';

      String? cs(int? idx, List row) { if (idx == null || idx >= row.length) return null; final v = row[idx].toString().trim(); return v.isEmpty ? null : v; }
      double cn(int? idx, List row) { if (idx == null || idx >= row.length) return 0; return double.tryParse(row[idx].toString().replaceAll(',', '.')) ?? 0; }

      final rows = <Map<String, dynamic>>[];
      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];
        final name = cs(nameIdx, row) ?? ''; if (name.isEmpty) continue;
        rows.add({
          'name': name, 'variant_names': cs(variantNamesIdx, row) ?? '',
          'category': cs(headers['category'] ?? headers['kategori'], row) ?? '',
          'sku': cs(headers['sku'], row), 'barcode': cs(headers['barcode'], row),
          'buy_price': cn(headers['buy_price'] ?? headers['harga_beli'], row),
          'sell_price': cn(headers['sell_price'] ?? headers['harga_jual'], row),
          'pos_sell_price': cn(headers['pos_sell_price'], row),
          'stock_qty': cn(headers['stock_qty'] ?? headers['stok'], row),
          'low_stock_warning': cn(headers['low_stock_alert'] ?? headers['low_stock_warning'], row),
          'resep_bibit_ml': 0, 'resep_botol': '',
        });
      }
      if (rows.isEmpty) throw 'Tidak ada data';

      setState(() { _progressImport = 0.1; _progressLabel = 'Mengirim ke database...'; });
      final result2 = await Api.importKatalogOlsera(tokoId, rows,
        onProgress: (done, total) {
          if (mounted) { setState(() {
            _progressImport = 0.1 + (done / total.clamp(1, 999999)) * 0.9;
            _progressLabel = '$done / $total (${ (_progressImport * 100).toStringAsFixed(0)}%)';
          }); }
        },
      );
      setState(() { _importing = false; _progressImport = 0; _progressLabel = ''; });
      _load();
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Import CSV OK: ${result2['bibit_baru']} bibit, ${result2['varian_baru']} varian, ${result2['botol_baru']} botol'),
        backgroundColor: const Color(0xFF27AE60), duration: const Duration(seconds: 4))); }
    } catch (e) {
      setState(() { _importing = false; _progressImport = 0; _progressLabel = ''; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL CSV: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _importXlsx() async {
    try {
      // withData:true wajib di Android (scoped storage — path bisa null)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (result == null) return;
      setState(() => _importing = true);

      final f0 = result.files.single;
      final rawBytes = f0.bytes != null ? f0.bytes! : (f0.path != null ? await File(f0.path!).readAsBytes() : Uint8List(0));
      if (rawBytes.isEmpty) throw 'File tidak dapat dibaca';
      // Patch dulu sebelum di-parse (fix error "Reached Max 16384" pada file Olsera)
      final bytes = _patchXlsxCols(rawBytes);
      final excel = xlsx.Excel.decodeBytes(bytes);

      // Safe sheet detection — rows getter may throw on malformed xlsx
      String sheetName = '';
      for (final k in excel.tables.keys) {
        try {
          if (excel.tables[k]?.rows.isNotEmpty ?? false) { sheetName = k.trim(); break; }
        } catch (_) { continue; }
      }
      if (sheetName.isEmpty && excel.tables.isNotEmpty) sheetName = excel.tables.keys.first.trim();
      if (sheetName.isEmpty) throw 'File kosong / tidak ada sheet';
      final sheet = excel.tables[sheetName]!;

      // Collect all rows via iterator to catch "Reached Max (16384)" mid-iteration
      List<List<xlsx.Data?>> rawRows;
      try { rawRows = sheet.rows; } catch (_) { rawRows = []; }
      if (rawRows.isEmpty) {
        rawRows = [];
        final it = sheet.rows.iterator;
        while (true) {
          bool moved = false;
          try { moved = it.moveNext(); } catch (_) { break; }
          if (!moved) break;
          try { rawRows.add(it.current); } catch (_) { continue; }
        }
      }
      if (rawRows.length < 2) throw 'Sheet kosong';

      // Parse header row
      final headerRow = rawRows.first;
      final headers = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final h = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';
        if (h.isNotEmpty) headers[h] = i;
      }

      // Expected columns (Olsera format)
      final nameIdx = headers['name'];
      final variantNamesIdx = headers['variant_names'];
      final categoryIdx = headers['category'];
      final skuIdx = headers['sku'];
      final barcodeIdx = headers['barcode'];
      final buyPriceIdx = headers['buy_price'];
      final sellPriceIdx = headers['sell_price'];
      final posPriceIdx = headers['pos_sell_price'];
      final stockIdx = headers['stock_qty'];
      final lowStockIdx = headers['low_stock_alert'] ?? headers['low_stock_warning'] ?? headers['min_stok'];
      // Extra resep columns (from KS export or manual)
      final resepBibitIdx = headers['resep_bibit_ml'] ?? headers['bibit_ml'] ?? headers['bibit_qty'];
      final resepBotolIdx = headers['resep_botol'] ?? headers['botol'];

      if (nameIdx == null || variantNamesIdx == null) {
        throw 'Kolom name / variant_names tidak ditemukan. Pastikan format xlsx Olsera.';
      }

      String? cellStr(int? idx, List<xlsx.Data?> row) {
        if (idx == null || idx >= row.length) return null;
        return row[idx]?.value?.toString().trim();
      }
      double cellNum(int? idx, List<xlsx.Data?> row) {
        if (idx == null || idx >= row.length) return 0;
        final v = row[idx]?.value;
        if (v == null) return 0;
        if (v is xlsx.IntCellValue)    return v.value.toDouble();
        if (v is xlsx.DoubleCellValue) return v.value;
        return double.tryParse(v.toString()) ?? 0;
      }

      // Parse rows
      final rows = <Map<String, dynamic>>[];
      for (int i = 1; i < rawRows.length; i++) {
        final row = rawRows[i];
        final name = cellStr(nameIdx, row) ?? '';
        if (name.isEmpty) continue;
        rows.add({
          'name': name,
          'variant_names': cellStr(variantNamesIdx, row) ?? '',
          'category': cellStr(categoryIdx, row) ?? '',
          'sku': cellStr(skuIdx, row),
          'barcode': cellStr(barcodeIdx, row),
          'buy_price': cellNum(buyPriceIdx, row),
          'sell_price': cellNum(sellPriceIdx, row),
          'pos_sell_price': cellNum(posPriceIdx, row),
          'stock_qty': cellNum(stockIdx, row),
          'low_stock_warning': cellNum(lowStockIdx, row),
          'resep_bibit_ml': cellNum(resepBibitIdx, row),
          'resep_botol': cellStr(resepBotolIdx, row) ?? '',
        });
      }

      if (rows.isEmpty) throw 'Tidak ada data di file';

      setState(() { _progressImport = 0.05; _progressLabel = 'Mengirim ke database...'; });
      final result2 = await Api.importKatalogOlsera(tokoId, rows,
        onProgress: (done, total) {
          if (mounted) { setState(() {
            _progressImport = 0.1 + (done / total.clamp(1, 999999)) * 0.9;
            _progressLabel = '$done / $total (${ (_progressImport * 100).toStringAsFixed(0)}%)';
          }); }
        },
      );
      setState(() { _importing = false; _progressImport = 0; _progressLabel = ''; });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Import OK: ${result2['produk_baru']} produk, ${result2['varian_baru']} varian (skip: ${result2['skipped']})'),
        backgroundColor: const Color(0xFF27AE60), duration: const Duration(seconds: 4)));
      }
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══ EXPORT XLSX FORMAT OLSERA ═══
  Future<void> _exportXlsx() async {
    try {
      final excel = xlsx.Excel.createExcel();
      final sheet = excel['product'];
      // Remove default sheet
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');

      // Headers (41 cols Olsera format + 2 resep columns)
      final headers = ['name','alternative_name','classification_id','category','variant_label','variant_names',
        'alternative_variant_names','collections','brand','condition_id','sku','barcode','buy_price',
        'market_price','sell_price','pos_sell_price','pos_sell_price_dynamic','comission','track_inventory',
        'stock_qty','hold_qty','low_stock_alert','uom','qty_fast_moving','weight_kg','loyalty_points',
        'published','pos_hidden','description','photo_1','photo_2','photo_3','photo_4','photo_5','photo_6',
        'photo_7','photo_8','photo_9','photo_10','notes','tax_free_item',
        'resep_bibit_ml','resep_botol'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = xlsx.TextCellValue(headers[i]);
      }

      int rowIdx = 1;
      for (final entry in _grouped.entries) {
        final p = _produk.firstWhere((x) => x['id'].toString() == entry.key, orElse: () => {'nama': '-', 'stok': 0, 'harga_beli': 0, 'kelas': 'PREMIUM'});
        final namaDisplay = (p['nama'] ?? '').toString().replaceFirst('BIBIT ', '');
        for (final v in entry.value) {
          final variantName = '${(v['ukuran'] ?? '').toString().toUpperCase()},${(v['kualitas'] ?? '').toString().toUpperCase()}';
          void setCell(int col, dynamic value) {
            xlsx.CellValue cv;
            if (value is num) {
              cv = xlsx.DoubleCellValue(value.toDouble());
            } else {
              cv = xlsx.TextCellValue(value?.toString() ?? '');
            }
            sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx)).value = cv;
          }
          final botolId = v['resep_botol_id'];
          final botol = botolId != null ? _allProduk.firstWhere((x) => x['id'].toString() == botolId.toString(), orElse: () => <String, dynamic>{}) : <String, dynamic>{};
          setCell(0, namaDisplay);
          setCell(3, p['kelas'] ?? 'PREMIUM');
          setCell(4, 'SIZE,VARIAN');
          setCell(5, variantName);
          setCell(10, v['sku'] ?? '');
          setCell(11, v['barcode'] ?? '');
          setCell(12, (p['harga_beli'] ?? 0));
          setCell(14, (v['harga_jual'] ?? 0));
          setCell(15, (v['harga_jual'] ?? 0));
          setCell(19, (p['stok'] ?? 0));
          setCell(22, 'ml');
          setCell(41, (v['resep_bibit'] ?? 0));
          setCell(42, botol.isEmpty ? '' : (botol['nama'] ?? '').toString());
          rowIdx++;
        }
      }

      final bytes = excel.save();
      if (bytes == null) throw 'Export gagal';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/katalog_ks_parfume_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Katalog Produk KS Parfume');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══ EXPORT RESEP CSV (format Olsera BOM) ═══
  Future<void> _exportResepCsv() async {
    try {
      final resepRows = await Api.exportResepCSVRows(tokoId);
      // Olsera uses ";" separator
      final lines = resepRows.map((r) => r.map((c) => c.toString()).join(';')).join('\n');
      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/resep_bom_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv');
      await file.writeAsString(lines);
      await Share.shareXFiles([XFile(file.path)], text: 'Resep/BOM KS Parfume');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Resep CSV di-share (${resepRows.length - 1} baris)'),
          backgroundColor: const Color(0xFF8E44AD)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ═══ EDIT VARIAN ═══
  void _editVarian(Map<String, dynamic> v) {
    final hjCtrl = TextEditingController(text: '${v['harga_jual'] ?? 0}');
    final skuCtrl = TextEditingController(text: '${v['sku'] ?? ''}');
    final barcodeCtrl = TextEditingController(text: '${v['barcode'] ?? ''}');
    final bibitCtrl = TextEditingController(text: '${v['resep_bibit'] ?? 0}');
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Edit ${v['nama']} ${v['ukuran']} ${v['kualitas']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: hjCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga Jual', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: bibitCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Resep Bibit (ml)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: skuCtrl,
          decoration: const InputDecoration(labelText: 'SKU', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: barcodeCtrl,
          decoration: const InputDecoration(labelText: 'Barcode', border: OutlineInputBorder(), isDense: true)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.updateVarian(v['id'], {
            'harga_jual': double.tryParse(hjCtrl.text) ?? 0,
            'resep_bibit': double.tryParse(bibitCtrl.text) ?? 0,
            'sku': skuCtrl.text,
            'barcode': barcodeCtrl.text,
          });
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, child: const Text('Simpan')),
      ]));
  }

  void _hapusVarian(Map<String, dynamic> v) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Hapus Varian?', style: TextStyle(fontSize: 14)),
      content: Text('${v['nama']} ${v['ukuran']} ${v['kualitas']} akan dihapus.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.deleteVarian(v['id']);
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus')),
      ]));
  }

  // ═══ EDIT RESEP (qty bibit + pilih botol) ═══
  void _editResepVarian(Map<String, dynamic> v) {
    final botolList = _allProduk.where((p) => p['kategori'] == 'STOK BOTOL').toList();
    final bibitCtrl = TextEditingController(text: '${v['resep_bibit'] ?? 0}');
    String? selectedBotolId = v['resep_botol_id']?.toString();
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Resep ${(v['ukuran'] ?? '').toString().toUpperCase()} ${(v['kualitas'] ?? '').toString().toUpperCase()}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: bibitCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Qty Bibit (ml)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: selectedBotolId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Botol', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 12, color: Colors.black),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('-- Tidak ada --', style: TextStyle(fontSize: 11))),
            ...botolList.map((b) => DropdownMenuItem<String>(
              value: b['id'].toString(),
              child: Text('${b['nama']}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))),
          ],
          onChanged: (val) => setD(() => selectedBotolId = val),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          final data = <String, dynamic>{
            'resep_bibit': double.tryParse(bibitCtrl.text) ?? 0,
            'resep_botol_id': selectedBotolId,
          };
          await Api.updateVarian(v['id'], data);
          if (!mounted) return;
          Navigator.pop(context);
          _load();
        }, child: const Text('Simpan')),
      ])));
  }

  // ═══ EDIT STOK BIBIT LANGSUNG (dari katalog) ═══
  void _editStokBibit(Map<String, dynamic> p) {
    final stokCtrl = TextEditingController(text: '${p['stok'] ?? 0}');
    final hargaCtrl = TextEditingController(text: '${p['harga_beli'] ?? 0}');
    final nm = ((p['nama'] ?? '') as String).replaceFirst('BIBIT ', '');
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Stok Bibit: $nm', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: stokCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Stok (ml)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: hargaCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga Beli (Rp/ml)', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.updateProduk(p['id'], {
            'stok': double.tryParse(stokCtrl.text) ?? 0,
            'harga_beli': double.tryParse(hargaCtrl.text) ?? 0,
          });
          if (!mounted) return;
          Navigator.pop(context);
          _load();
        }, child: const Text('Simpan')),
      ]));
  }

  void _hapusProduk(Map<String, dynamic> p) {
    final vs = _grouped[p['id'].toString()] ?? [];
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Hapus Produk & Semua Varian?', style: TextStyle(fontSize: 14)),
      content: Text('${p['nama']} (${vs.length} varian) akan dihapus semua.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.hapusSemuaVarianProduk(p['id']);
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus')),
      ]));
  }

  // ═══ SECTION STOK BIBIT ═══
  Widget _buildBibitSection() {
    if (_produk.isEmpty) return const SizedBox(height: 20);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 20),
      // Header
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1510), Color(0xFF2A2118)]),
          borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.science, size: 18, color: Color(0xFFD4A574)),
          const SizedBox(width: 8),
          Text('Stok Bibit  (${_produk.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
          const Spacer(),
          // Ringkasan rendah
          Builder(builder: (_) {
            final rendah = _produk.where((p) => (p['stok'] as num) <= (p['min_stok'] as num) && (p['stok'] as num) > 0).length;
            final habis = _produk.where((p) => (p['stok'] as num) <= 0).length;
            return Row(children: [
              if (habis > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                child: Text('$habis habis', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white))),
              if (habis > 0 && rendah > 0) const SizedBox(width: 4),
              if (rendah > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                child: Text('$rendah rendah', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white))),
            ]);
          }),
        ])),
      const SizedBox(height: 8),
      // List bibit
      ..._produk.map((p) {
        final nm = ((p['nama'] ?? '') as String).replaceFirst('BIBIT ', '');
        final stok = (p['stok'] as num).toDouble();
        final minStok = (p['min_stok'] as num).toDouble();
        final hargaBeli = (p['harga_beli'] as num?)?.toDouble() ?? 0;
        final habis = stok <= 0;
        final low = !habis && stok <= minStok;
        final ok = !habis && !low;

        // Hitung berapa varian/batch yang bisa dibuat dari stok ini
        final vsForThis = _varian.where((v) => v['produk_id'] == p['id']).toList();
        final resepAngka = vsForThis.isEmpty ? 0.0
            : vsForThis.map((v) => (v['resep_bibit'] as num?)?.toDouble() ?? 0).where((r) => r > 0).fold(0.0, (a, b) => a + b) / vsForThis.where((v) => ((v['resep_bibit'] as num?)?.toDouble() ?? 0) > 0).length.clamp(1, 999);

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          elevation: habis ? 2 : 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: habis ? Colors.red.withOpacity(0.4) : low ? Colors.orange.withOpacity(0.4) : const Color(0xFFE8E0D8),
              width: habis || low ? 1.2 : 0.8)),
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: Row(children: [
            // Ikon status
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: habis ? Colors.red.withOpacity(0.08) : low ? Colors.orange.withOpacity(0.08) : const Color(0xFFFAF8F5),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.science,
                color: habis ? Colors.red : low ? Colors.orange : const Color(0xFFD4A574),
                size: 22)),
            const SizedBox(width: 12),
            // Info
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nm, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF3A2E24)), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: habis ? Colors.red : low ? Colors.orange : const Color(0xFF27AE60),
                    borderRadius: BorderRadius.circular(5)),
                  child: Text('${p['stok']} ml', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white))),
                const SizedBox(width: 6),
                Text('/ min ${p['min_stok']} ml', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
              ]),
              const SizedBox(height: 3),
              Row(children: [
                const Icon(Icons.attach_money, size: 11, color: Color(0xFF6B5B4B)),
                Text('${cur.format(hargaBeli)}/ml', style: const TextStyle(fontSize: 10, color: Color(0xFF6B5B4B))),
                if (hargaBeli > 0 && stok > 0) ...[
                  const SizedBox(width: 6),
                  Text('· nilai: ${cur.format(hargaBeli * stok)}', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                ],
              ]),
              if (vsForThis.isNotEmpty && resepAngka > 0)
                Text('Cukup untuk ±${(stok / resepAngka).floor()} parfum', style: TextStyle(fontSize: 9, color: ok ? const Color(0xFF27AE60) : low ? Colors.orange : Colors.red, fontWeight: FontWeight.w600)),
              if (habis) const Text('HABIS — segera restock!', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.red))
              else if (low) const Text('STOK RENDAH', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.orange)),
            ])),
            // Tombol edit
            IconButton(
              icon: const Icon(Icons.edit, size: 18, color: Color(0xFF2980B9)),
              onPressed: () => _editStokBibit(p),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
          ])));
      }),
      const SizedBox(height: 24),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _grouped.entries.where((e) {
      if (_search.isEmpty) return true;
      final p = _produk.firstWhere((x) => x['id'].toString() == e.key, orElse: () => {});
      final nm = ((p['nama'] ?? '') as String).toLowerCase();
      return nm.contains(_search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Katalog Produk', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          TextField(onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(hintText: 'Cari nama produk...', prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true),
            style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _importing ? null : _importXlsx,
              icon: _importing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2980B9))) : const Icon(Icons.upload_file, size: 16),
              label: const Text('Import .xlsx', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF2980B9), side: const BorderSide(color: Color(0xFF2980B9))))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(
              onPressed: _importing ? null : _importCsvProduk,
              icon: _importing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1A6B3A))) : const Icon(Icons.table_rows, size: 16),
              label: const Text('Import .csv', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1A6B3A), side: const BorderSide(color: Color(0xFF1A6B3A))))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(
              onPressed: _exportXlsx,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Export Excel', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF27AE60), side: const BorderSide(color: Color(0xFF27AE60))))),
            const SizedBox(width: 6),
            Expanded(child: OutlinedButton.icon(
              onPressed: _exportResepCsv,
              icon: const Icon(Icons.science, size: 16),
              label: const Text('Export Resep', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF8E44AD), side: const BorderSide(color: Color(0xFF8E44AD))))),
          ]),
          if (_importing) ...[
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(_progressLabel.isEmpty ? 'Mengimport...' : _progressLabel,
                style: const TextStyle(fontSize: 10, color: Color(0xFF2980B9)), overflow: TextOverflow.ellipsis)),
              Text('${(_progressImport * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 12, color: Color(0xFF2980B9), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: _progressImport > 0 ? _progressImport : null,
                color: const Color(0xFF2980B9), backgroundColor: const Color(0xFFD0E8F8), minHeight: 6)),
          ],
          const SizedBox(height: 6),
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
            child: Text('${filtered.length} produk, ${_varian.length} varian', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080)))),
        ])),
        Expanded(child: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
          : filtered.isEmpty ? const Center(child: Text('Belum ada produk\nImport Excel untuk mulai', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFA09080))))
          : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: filtered.length + 1,
            itemBuilder: (_, i) {
              if (i == filtered.length) return _buildBibitSection();
              final e = filtered[i];
              final p = _produk.firstWhere((x) => x['id'].toString() == e.key, orElse: () => {'nama': '?', 'stok': 0, 'harga_beli': 0});
              final vs = e.value;
              final nm = ((p['nama'] ?? '') as String).replaceFirst('BIBIT ', '');

              final produkKey = p['id'].toString();
              return Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 40, height: 40, decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.local_mall, color: Color(0xFFD4A574), size: 20)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(nm, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                      GestureDetector(
                        onTap: () => _editStokBibit(p),
                        child: Text('Stok bibit: ${p['stok']} ml · Beli: ${cur.format(p['harga_beli'] ?? 0)}/ml [edit]',
                          style: const TextStyle(fontSize: 9, color: Color(0xFF2980B9), decoration: TextDecoration.underline))),
                      Text('${vs.length} varian', style: const TextStyle(fontSize: 9, color: Color(0xFF27AE60), fontWeight: FontWeight.w600)),
                    ])),
                    IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      onPressed: () => _hapusProduk(p), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ]),
                  const Divider(height: 14),
                  // Variant table
                  SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
                    columnSpacing: 10, headingRowHeight: 26, dataRowMinHeight: 28, dataRowMaxHeight: 36,
                    columns: const [
                      DataColumn(label: Text('Variant', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('SKU', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Harga Jual', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('Bibit', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700))),
                      DataColumn(label: Text('', style: TextStyle(fontSize: 9))),
                    ],
                    rows: vs.map((v) => DataRow(cells: [
                      DataCell(Text('${v['ukuran']?.toString().toUpperCase() ?? '-'},${v['kualitas']?.toString().toUpperCase() ?? '-'}',
                        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF2980B9)))),
                      DataCell(Text('${v['sku'] ?? '-'}', style: const TextStyle(fontSize: 9))),
                      DataCell(Text(cur.format(v['harga_jual'] ?? 0), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFD4A574)))),
                      DataCell(Text('${v['resep_bibit'] ?? 0} ml', style: const TextStyle(fontSize: 9))),
                      DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.edit, size: 14, color: Color(0xFF2980B9)),
                          onPressed: () => _editVarian(v), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24)),
                        IconButton(icon: const Icon(Icons.close, size: 14, color: Colors.red),
                          onPressed: () => _hapusVarian(v), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24)),
                      ])),
                    ])).toList())),
                  // Section Bahan/Resep (collapsible)
                  const Divider(height: 10),
                  Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      dense: true,
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.science_outlined, size: 14, color: Color(0xFF6B5B4B)),
                      title: const Text('Bahan / Resep', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6B5B4B))),
                      initiallyExpanded: _expandedResep.contains(produkKey),
                      onExpansionChanged: (exp) => setState(() {
                        if (exp) {
                          _expandedResep.add(produkKey);
                        } else {
                          _expandedResep.remove(produkKey);
                        }
                      }),
                      children: vs.map((v) {
                        final botolId = v['resep_botol_id'];
                        final botol = botolId != null
                            ? _allProduk.firstWhere((x) => x['id'].toString() == botolId.toString(), orElse: () => <String, dynamic>{})
                            : <String, dynamic>{};
                        final varLabel = '${v['ukuran']?.toString().toUpperCase() ?? '-'},${v['kualitas']?.toString().toUpperCase() ?? '-'}';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFAF8F5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE8E0D8)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(varLabel, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF2980B9))),
                              GestureDetector(
                                onTap: () => _editResepVarian(v),
                                child: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF2980B9))),
                            ]),
                            const SizedBox(height: 4),
                            Row(children: [
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('BIBIT', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFFA09080))),
                                Text(nm, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                Text('Qty ${v['resep_bibit'] ?? 0}ml', style: const TextStyle(fontSize: 9, color: Color(0xFF27AE60))),
                              ])),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Text('STOK BOTOL', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Color(0xFFA09080))),
                                Text(botol.isEmpty ? '-' : (botol['nama'] ?? '-').toString(), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                if (botol.isNotEmpty) const Text('Qty 1', style: TextStyle(fontSize: 9, color: Color(0xFF27AE60))),
                              ])),
                            ]),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ])));
            })),
      ]),
    );
  }
}

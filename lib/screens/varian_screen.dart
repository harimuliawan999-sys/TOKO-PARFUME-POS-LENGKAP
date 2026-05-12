import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as xlsx;
import 'package:archive/archive.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../services/api.dart';

class VarianScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const VarianScreen({super.key, required this.toko});
  @override State<VarianScreen> createState() => _VarianScreenState();
}

class _VarianScreenState extends State<VarianScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _produk = [], _varian = [];
  Map<String, List<Map<String, dynamic>>> _grouped = {};
  String _search = '';
  bool _importing = false;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final p = await Api.getProduk(widget.toko['id']);
    final v = await Api.getVarian(widget.toko['id']);
    final g = <String, List<Map<String, dynamic>>>{};
    for (final x in v) { g.putIfAbsent(x['produk_id'], () => []).add(x); }
    if (mounted) setState(() { _produk = p; _varian = v; _grouped = g; });
  }

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

  Future<void> _importXlsx() async {
    try {
      // withData:true wajib di Android (scoped storage — path bisa null)
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (result == null) return;
      setState(() => _importing = true);
      final rawBytes = result.files.single.bytes
          ?? (result.files.single.path != null ? await File(result.files.single.path!).readAsBytes() : Uint8List(0));
      // Patch dulu sebelum di-parse (fix error "Reached Max 16384" pada file Olsera)
      final bytes = _patchXlsxCols(rawBytes);
      final excel = xlsx.Excel.decodeBytes(bytes);

      // Safe sheet detection
      String sheetName = '';
      for (final k in excel.tables.keys) {
        try {
          if (excel.tables[k]?.rows.isNotEmpty ?? false) { sheetName = k.trim(); break; }
        } catch (_) { continue; }
      }
      if (sheetName.isEmpty && excel.tables.isNotEmpty) sheetName = excel.tables.keys.first.trim();
      if (sheetName.isEmpty) throw 'File kosong / tidak ada sheet';
      final sheet = excel.tables[sheetName]!;

      // Iterator-safe row collection
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

      final headerRow = rawRows.first;
      final headers = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final h = headerRow[i]?.value?.toString().toLowerCase().trim() ?? '';
        if (h.isNotEmpty) headers[h] = i;
      }
      final nameIdx = headers['name'];
      final variantNamesIdx = headers['variant_names'];
      if (nameIdx == null || variantNamesIdx == null) throw 'Kolom name / variant_names tidak ditemukan. Pastikan format xlsx Olsera.';

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

      final rows = <Map<String, dynamic>>[];
      for (int i = 1; i < rawRows.length; i++) {
        final row = rawRows[i];
        final name = cellStr(nameIdx, row) ?? '';
        if (name.isEmpty) continue;
        rows.add({
          'name': name,
          'variant_names': cellStr(variantNamesIdx, row) ?? '',
          'category': cellStr(headers['category'], row) ?? '',
          'sku': cellStr(headers['sku'], row),
          'barcode': cellStr(headers['barcode'], row),
          'buy_price': cellNum(headers['buy_price'], row),
          'sell_price': cellNum(headers['sell_price'], row),
          'pos_sell_price': cellNum(headers['pos_sell_price'], row),
          'stock_qty': cellNum(headers['stock_qty'], row),
          'low_stock_warning': cellNum(headers['low_stock_alert'] ?? headers['low_stock_warning'], row),
        });
      }
      if (rows.isEmpty) throw 'Tidak ada data di file';
      final res = await Api.importKatalogOlsera(widget.toko['id'], rows);
      setState(() => _importing = false);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import OK: ${res['produk_baru']} produk, ${res['varian_baru']} varian (skip: ${res['skipped']})'), backgroundColor: const Color(0xFF27AE60), duration: const Duration(seconds: 4)));
    } catch (e) {
      setState(() => _importing = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _exportXlsx() async {
    try {
      final excel = xlsx.Excel.createExcel();
      final sheet = excel['product'];
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
      final headers = ['name','alternative_name','classification_id','category','variant_label','variant_names','alternative_variant_names','collections','brand','condition_id','sku','barcode','buy_price','market_price','sell_price','pos_sell_price','pos_sell_price_dynamic','comission','track_inventory','stock_qty','hold_qty','low_stock_alert','uom','qty_fast_moving','weight_kg','loyalty_points','published','pos_hidden','description','photo_1','photo_2','photo_3','photo_4','photo_5','photo_6','photo_7','photo_8','photo_9','photo_10','notes','tax_free_item'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = xlsx.TextCellValue(headers[i]);
      }
      int rowIdx = 1;
      for (final entry in _grouped.entries) {
        final p = _produk.firstWhere((x) => x['id'].toString() == entry.key, orElse: () => {'nama': '-', 'stok': 0, 'harga_beli': 0, 'kelas': 'PREMIUM'});
        final namaDisplay = (p['nama'] ?? '').toString().replaceFirst('BIBIT ', '');
        for (final v in entry.value) {
          final variantName = '${(v['ukuran'] ?? '').toString().toUpperCase()},${(v['kualitas'] ?? '').toString().toUpperCase()}';
          void setCell(int col, dynamic value) { xlsx.CellValue cv; if (value is num) {
            cv = xlsx.DoubleCellValue(value.toDouble());
          } else {
            cv = xlsx.TextCellValue(value?.toString() ?? '');
          } sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIdx)).value = cv; }
          setCell(0, namaDisplay); setCell(3, p['kelas'] ?? 'PREMIUM'); setCell(4, 'SIZE,VARIAN'); setCell(5, variantName);
          setCell(10, v['sku'] ?? ''); setCell(11, v['barcode'] ?? ''); setCell(12, (p['harga_beli'] ?? 0)); setCell(14, (v['harga_jual'] ?? 0)); setCell(15, (v['harga_jual'] ?? 0)); setCell(19, (p['stok'] ?? 0)); setCell(22, 'ml');
          rowIdx++;
        }
      }
      final bytes = excel.save();
      if (bytes == null) throw 'Export gagal';
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/varian_ks_parfume_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Produk & Varian KS Parfume');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
    }
  }

  void _tambah() {
    final bibitList = _produk.where((p) => p['kategori'] == 'STOCK PARFUME').toList();
    final botolList = _produk.where((p) => p['kategori'] == 'STOK BOTOL').toList();
    String? pid, bid;
    String uk = '30ml', ku = 'Medium', hj = '', rb = '';
    final rbCtrl = TextEditingController();

    // Auto-fill from template
    Future<void> applyTemplate(String ukuran, String kualitas, StateSetter setD) async {
      final tpl = await Api.getResepTemplateBy(ukuran, kualitas);
      if (tpl != null) {
        final qty = ((tpl['qty_bibit'] ?? 0) as num).toString();
        setD(() {
          rb = qty;
          rbCtrl.text = qty;
        });
      }
    }

    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (c, setD) => AlertDialog(
      title: const Text('Tambah Varian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: pid, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Pilih Bibit', border: OutlineInputBorder(), isDense: true),
          items: bibitList.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text('${p['nama']}', style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setD(() => pid = v), style: const TextStyle(fontSize: 12, color: Colors.black)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DropdownButtonFormField<String>(value: uk,
            decoration: const InputDecoration(labelText: 'Ukuran', border: OutlineInputBorder(), isDense: true),
            items: ['15ml','20ml','25ml','30ml','35ml','40ml','50ml','55ml','60ml','100ml'].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
            onChanged: (v) { setD(() => uk = v!); applyTemplate(uk, ku, setD); }, style: const TextStyle(fontSize: 12, color: Colors.black))),
          const SizedBox(width: 8),
          Expanded(child: DropdownButtonFormField<String>(value: ku,
            decoration: const InputDecoration(labelText: 'Kualitas', border: OutlineInputBorder(), isDense: true),
            items: ['Medium','Super','Platinum','Full Bibit'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: (v) { setD(() => ku = v!); applyTemplate(uk, ku, setD); }, style: const TextStyle(fontSize: 12, color: Colors.black))),
        ]),
        const SizedBox(height: 10),
        TextField(onChanged: (v) => hj = v, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga Jual (Rp)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: rbCtrl, onChanged: (v) => rb = v, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bibit (ml) — auto dari template', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(value: bid, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Botol', border: OutlineInputBorder(), isDense: true),
          items: botolList.map((b) => DropdownMenuItem(value: b['id'] as String, child: Text('${b['nama']}', style: const TextStyle(fontSize: 11)))).toList(),
          onChanged: (v) => setD(() => bid = v), style: const TextStyle(fontSize: 12, color: Colors.black)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          if (pid == null || hj.isEmpty) return;
          final bibit = _produk.firstWhere((p) => p['id'] == pid);
          await Api.addVarian({
            'produk_id': pid,
            'nama': (bibit['nama'] as String).replaceFirst('BIBIT ', ''),
            'ukuran': uk, 'kualitas': ku,
            'harga_jual': double.tryParse(hj) ?? 0,
            'resep_bibit': double.tryParse(rb) ?? 0,
            'resep_botol_id': bid, 'aktif': true});
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, child: const Text('Simpan')),
      ])));
  }

  void _edit(Map<String, dynamic> v) {
    final hjCtrl = TextEditingController(text: '${v['harga_jual'] ?? 0}');
    final rbCtrl = TextEditingController(text: '${v['resep_bibit'] ?? 0}');
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text('Edit ${v['nama']} ${v['ukuran']} ${v['kualitas']}', style: const TextStyle(fontSize: 13)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: hjCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga Jual', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: rbCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bibit (ml)', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.updateVarian(v['id'], {
            'harga_jual': double.tryParse(hjCtrl.text) ?? 0,
            'resep_bibit': double.tryParse(rbCtrl.text) ?? 0,
          });
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, child: const Text('Simpan')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final filteredEntries = _grouped.entries.where((e) {
      if (_search.isEmpty) return true;
      final p = _produk.firstWhere((x) => x['id'] == e.key, orElse: () => {});
      return (p['nama'] ?? '').toString().toLowerCase().contains(_search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Produk & Varian', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_importing) const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
          IconButton(icon: const Icon(Icons.upload_file, size: 20), onPressed: _importing ? null : _importXlsx, tooltip: 'Import Excel Olsera'),
          IconButton(icon: const Icon(Icons.download, size: 20), onPressed: _exportXlsx, tooltip: 'Export Excel Olsera'),
          IconButton(icon: const Icon(Icons.add), onPressed: _tambah),
        ]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(onChanged: (v) => setState(() => _search = v),
          decoration: InputDecoration(hintText: 'Cari produk...', prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 10),
        Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
          child: Text('${filteredEntries.length} parfum, ${_varian.length} varian', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080)))),
        const SizedBox(height: 12),
        ...filteredEntries.map((e) {
          final p = _produk.firstWhere((x) => x['id'] == e.key, orElse: () => {'nama': '?', 'stok': 0, 'min_stok': 0});
          final vs = e.value;
          return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(vs.isNotEmpty ? '${vs.first['nama']}' : '?', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text('Stok: ${p['stok']} ml', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: (p['stok'] as num) <= (p['min_stok'] as num) ? Colors.red : Colors.green)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: vs.map((v) => Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v['ukuran']} · ${v['kualitas']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                    Text(cur.format(v['harga_jual']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
                    Text('Bibit: ${v['resep_bibit']}ml', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080)))]),
                  const SizedBox(width: 8),
                  GestureDetector(onTap: () => _edit(v), child: const Icon(Icons.edit, size: 14, color: Color(0xFF2980B9))),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: () async { await Api.deleteVarian(v['id']); _load(); },
                    child: const Icon(Icons.close, size: 14, color: Colors.red)),
                ]))).toList()),
            ])));
        }),
      ])));
  }
}

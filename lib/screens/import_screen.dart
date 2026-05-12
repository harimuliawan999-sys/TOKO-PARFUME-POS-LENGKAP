import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as xlsx;
import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import '../services/api.dart';

class ImportScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const ImportScreen({super.key, required this.toko});
  @override State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final List<String> _log = [];
  bool _importingXlsx = false, _importingBom = false, _exporting = false;
  int _totalProduk = 0, _totalVarian = 0, _totalTrx = 0;
  double _progressXlsx = 0; // 0.0 - 1.0
  double _progressBom  = 0;
  String _progressLabel = '';

  @override void initState() { super.initState(); _loadStats(); }

  Future<void> _loadStats() async {
    try {
      final p = await Api.getProduk(widget.toko['id']);
      final v = await Api.getVarian(widget.toko['id']);
      final t = await Api.getTransaksi(widget.toko['id'], limit: 99999);
      if (mounted) setState(() { _totalProduk = p.length; _totalVarian = v.length; _totalTrx = t.length; });
    } catch (_) {}
  }

  // ─── Import Produk & Varian (xlsx Olsera) ───────────────────────────────────
  Future<void> _importXlsx() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['xlsx', 'xls'],
      withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    _addLog('Membaca ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)...');
    setState(() => _importingXlsx = true);

    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final excel = xlsx.Excel.decodeBytes(bytes);
      // Find first non-empty sheet (safe: guard against rows getter throwing)
      String sheetName = '';
      for (final k in excel.tables.keys) {
        try {
          if (excel.tables[k]?.rows.isNotEmpty ?? false) { sheetName = k; break; }
        } catch (_) { continue; }
      }
      if (sheetName.isEmpty && excel.tables.isNotEmpty) sheetName = excel.tables.keys.first;
      if (sheetName.isEmpty) { _addLog('GAGAL: File kosong / tidak ada sheet'); setState(() => _importingXlsx = false); return; }

      final sheet = excel.tables[sheetName]!;
      List<List<xlsx.Data?>> rawRows;
      try { rawRows = sheet.rows; } catch (_) { rawRows = []; }
      if (rawRows.isEmpty) {
        // Try collecting row by row via iterator
        rawRows = [];
        final it = sheet.rows.iterator;
        while (true) {
          bool moved = false;
          try { moved = it.moveNext(); } catch (_) { break; }
          if (!moved) break;
          try { rawRows.add(it.current); } catch (_) { continue; }
        }
      }
      if (rawRows.length < 2) { _addLog('GAGAL: Sheet kosong'); setState(() => _importingXlsx = false); return; }

      // Parse header row → build column index map
      final headerRow = rawRows.first;
      final headers = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        final h = (headerRow[i]?.value?.toString() ?? '').toLowerCase().trim();
        if (h.isNotEmpty) headers[h] = i;
      }
      _addLog('Header: ${headers.keys.take(8).join(', ')}...');

      // Resolve known column indices (Olsera 41-col format)
      final nameIdx         = headers['name']         ?? headers['nama']         ?? headers['product_name'];
      final categoryIdx     = headers['category']     ?? headers['kategori'];
      final variantNamesIdx = headers['variant_names'] ?? headers['variants'] ?? headers['variant'] ?? headers['product_variant_name'];
      final skuIdx          = headers['sku'];
      final barcodeIdx      = headers['barcode'];
      final buyPriceIdx     = headers['buy_price']    ?? headers['harga_beli']   ?? headers['purchase_price'];
      final sellPriceIdx    = headers['sell_price']   ?? headers['harga_jual']   ?? headers['selling_price'];
      final posSellIdx      = headers['pos_sell_price'];
      final stockQtyIdx     = headers['stock_qty']    ?? headers['stok']         ?? headers['quantity'];
      final lowStockIdx     = headers['low_stock_alert'] ?? headers['low_stock_warning'] ?? headers['min_stok'];
      final resepBibitIdx   = headers['resep_bibit_ml'] ?? headers['bibit_ml'];
      final resepBotolIdx   = headers['resep_botol']  ?? headers['botol'];

      if (nameIdx == null) { _addLog('GAGAL: Kolom "name" tidak ditemukan'); setState(() => _importingXlsx = false); return; }

      String? cellStr(int? idx, List<xlsx.Data?> row) {
        if (idx == null || idx >= row.length) return null;
        return row[idx]?.value?.toString().trim();
      }
      double? cellNum(int? idx, List<xlsx.Data?> row) {
        if (idx == null || idx >= row.length) return null;
        final v = row[idx]?.value;
        if (v == null) return null;
        if (v is xlsx.IntCellValue)    return v.value.toDouble();
        if (v is xlsx.DoubleCellValue) return v.value;
        return double.tryParse(v.toString().replaceAll(',', '.'));
      }

      final parsedRows = <Map<String, dynamic>>[];
      for (int i = 1; i < rawRows.length; i++) {
        final row = rawRows[i];
        final name = cellStr(nameIdx, row) ?? '';
        if (name.isEmpty) continue;
        parsedRows.add({
          'name':            name,
          'category':        cellStr(categoryIdx, row) ?? '',
          'variant_names':   cellStr(variantNamesIdx, row) ?? '',
          'sku':             cellStr(skuIdx, row),
          'barcode':         cellStr(barcodeIdx, row),
          'buy_price':       cellNum(buyPriceIdx, row) ?? 0,
          'sell_price':      cellNum(sellPriceIdx, row) ?? 0,
          'pos_sell_price':  cellNum(posSellIdx, row) ?? 0,
          'stock_qty':       cellNum(stockQtyIdx, row) ?? 0,
          'low_stock_warning': cellNum(lowStockIdx, row) ?? 0,
          'resep_bibit_ml':  cellNum(resepBibitIdx, row) ?? 0,
          'resep_botol':     cellStr(resepBotolIdx, row) ?? '',
        });
      }

      // Pre-call classification preview (diagnose before hitting DB)
      final prevBibit  = parsedRows.where((r) {
        final n = (r['name'] ?? '').toString().toUpperCase();
        final v = (r['variant_names'] ?? '').toString().trim();
        return n.startsWith('BIBIT ') && v.isEmpty;
      }).length;
      final prevVarian = parsedRows.where((r) =>
          (r['variant_names'] ?? '').toString().trim().isNotEmpty).length;
      final prevBotol  = parsedRows.where((r) {
        final n = (r['name'] ?? '').toString().toUpperCase();
        final c = (r['category'] ?? '').toString().toUpperCase();
        final v = (r['variant_names'] ?? '').toString().trim();
        return v.isEmpty && (c.contains('BOTOL') || c.contains('SPRAY') ||
                             n.contains('BOTOL') || n.contains('SPRAY'));
      }).length;
      _addLog('${parsedRows.length} baris terbaca → $prevBibit bibit, $prevBotol botol, $prevVarian varian');
      if (prevVarian == 0 && prevBibit == 0 && parsedRows.isNotEmpty) {
        _addLog('  [!] Semua baris terbaca sebagai "lainnya" — periksa kolom variant_names di file');
      }

      setState(() { _progressXlsx = 0.1; _progressLabel = 'Mengirim ke database...'; });
      final res = await Api.importKatalogOlsera(widget.toko['id'], parsedRows,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
            _progressXlsx = 0.1 + (done / total) * 0.9;
            _progressLabel = '$done / $total baris (${ ((_progressXlsx)*100).toStringAsFixed(0)}%)';
          });
          }
        },
      );
      final bibitN  = (res['bibit_baru']  ?? 0) as int;
      final botolN  = (res['botol_baru']  ?? 0) as int;
      final varianN = (res['varian_baru'] ?? 0) as int;
      final updN    = (res['updated']     ?? 0) as int;
      final skipN   = (res['skipped']     ?? 0) as int;
      final errStr  = (res['_errors']     ?? '').toString();
      final errCount = (res['_errors_count'] ?? 0) as int;
      _addLog('OK: $bibitN bibit baru, $varianN varian baru, $botolN botol baru');
      if (updN  > 0) _addLog('  Diperbarui: $updN item (harga/stok)');
      if (skipN > 0) _addLog('  Dilewati  : $skipN baris');
      if (errCount > 0) {
        _addLog('[!] $errCount error saat import — lihat detail di bawah');
        for (final line in errStr.split('\n').take(20)) {
          if (line.trim().isNotEmpty) _addLog('  ERR: $line');
        }
      }
      _loadStats();
      if (errCount > 0 && mounted) {
        _showImportErrorDialog(bibitN, varianN, botolN, updN, skipN, errStr, errCount);
      }
    } catch (e) { _addLog('GAGAL: $e'); }
    setState(() => _importingXlsx = false);
  }


  // ─── Import Produk dari CSV (lebih cepat, tidak error kolom 16384) ──────────
  Future<void> _importCsvProduk() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv', 'txt'],
      withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    _addLog('Membaca CSV: ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)...');
    setState(() => _importingXlsx = true);

    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      String raw = utf8.decode(bytes, allowMalformed: true);
      // Strip BOM
      if (raw.codeUnitAt(0) == 0xFEFF) raw = raw.substring(1);

      // Auto-detect separator
      final firstLine = raw.split('\n').first;
      final sep = firstLine.contains(';') ? ';' : ',';
      final csvRows = CsvToListConverter(fieldDelimiter: sep, eol: '\n').convert(raw);
      if (csvRows.length < 2) {
        _addLog('GAGAL: File kosong'); setState(() => _importingXlsx = false); return;
      }

      // Build header map
      final headerRow = csvRows.first.map((c) => c.toString().toLowerCase().trim()).toList();
      final headers = <String, int>{};
      for (int i = 0; i < headerRow.length; i++) {
        if (headerRow[i].isNotEmpty) headers[headerRow[i]] = i;
      }
      _addLog('Header: ${headers.keys.take(6).join(", ")}...');

      final nameIdx         = headers['name']          ?? headers['nama']        ?? headers['product_name'];
      final categoryIdx     = headers['category']      ?? headers['kategori'];
      final variantNamesIdx = headers['variant_names'] ?? headers['variants']    ?? headers['variant'] ?? headers['product_variant_name'];
      final buyPriceIdx     = headers['buy_price']     ?? headers['harga_beli']  ?? headers['purchase_price'];
      final sellPriceIdx    = headers['sell_price']    ?? headers['harga_jual']  ?? headers['selling_price'];
      final posSellIdx      = headers['pos_sell_price'];
      final stockQtyIdx     = headers['stock_qty']     ?? headers['stok']        ?? headers['quantity'];
      final lowStockIdx     = headers['low_stock_alert'] ?? headers['low_stock_warning'] ?? headers['min_stok'];
      final skuIdx          = headers['sku'];
      final barcodeIdx      = headers['barcode'];

      if (nameIdx == null) {
        _addLog('GAGAL: Kolom "name" tidak ditemukan. Header: ${headerRow.take(5).join(", ")}');
        setState(() => _importingXlsx = false); return;
      }

      String? cs(int? idx, List row) {
        if (idx == null || idx >= row.length) return null;
        final v = row[idx].toString().trim(); return v.isEmpty ? null : v;
      }
      double? cn(int? idx, List row) {
        if (idx == null || idx >= row.length) return null;
        return double.tryParse(row[idx].toString().replaceAll(',', '.'));
      }

      final parsedRows = <Map<String, dynamic>>[];
      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];
        final name = cs(nameIdx, row) ?? ''; if (name.isEmpty) continue;
        parsedRows.add({
          'name': name, 'category': cs(categoryIdx, row) ?? '',
          'variant_names': cs(variantNamesIdx, row) ?? '',
          'sku': cs(skuIdx, row), 'barcode': cs(barcodeIdx, row),
          'buy_price': cn(buyPriceIdx, row) ?? 0,
          'sell_price': cn(sellPriceIdx, row) ?? 0,
          'pos_sell_price': cn(posSellIdx, row) ?? 0,
          'stock_qty': cn(stockQtyIdx, row) ?? 0,
          'low_stock_warning': cn(lowStockIdx, row) ?? 0,
          'resep_bibit_ml': 0, 'resep_botol': '',
        });
      }

      final prevBibit  = parsedRows.where((r) => (r['name'] ?? '').toString().toUpperCase().startsWith('BIBIT ') && (r['variant_names'] ?? '').toString().trim().isEmpty).length;
      final prevVarian = parsedRows.where((r) => (r['variant_names'] ?? '').toString().trim().isNotEmpty).length;
      final prevBotol  = parsedRows.where((r) {
        final n = (r['name'] ?? '').toString().toUpperCase();
        final c2 = (r['category'] ?? '').toString().toUpperCase();
        final v = (r['variant_names'] ?? '').toString().trim();
        return v.isEmpty && (c2.contains('BOTOL') || c2.contains('SPRAY') || n.contains('BOTOL') || n.contains('SPRAY'));
      }).length;
      _addLog('${parsedRows.length} baris → $prevBibit bibit, $prevBotol botol, $prevVarian varian');
      if (prevVarian == 0 && prevBibit == 0 && parsedRows.isNotEmpty) {
        _addLog('  Peringatan: kolom variant_names kosong — cek format CSV');
      }

      setState(() { _progressXlsx = 0.1; _progressLabel = 'Mengirim ke database...'; });
      final res = await Api.importKatalogOlsera(widget.toko['id'], parsedRows,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
            _progressXlsx = 0.1 + (done / total) * 0.9;
            _progressLabel = '$done / $total baris (${ ((_progressXlsx)*100).toStringAsFixed(0)}%)';
          });
          }
        },
      );
      _addLog('OK: ${res["bibit_baru"] ?? 0} bibit baru, ${res["varian_baru"] ?? 0} varian baru, ${res["botol_baru"] ?? 0} botol baru');
      if ((res['updated'] ?? 0) > 0) _addLog('  Diperbarui: ${res["updated"]} item');
      if ((res['skipped'] ?? 0) > 0) _addLog('  Dilewati  : ${res["skipped"]} baris');
      if ((res['_errors'] ?? '').toString().isNotEmpty) _addLog('  Error: ${res["_errors"].toString().substring(0, 120.clamp(0, res["_errors"].toString().length))}');
      _loadStats();
    } catch (e) { _addLog('GAGAL CSV: $e'); }
    setState(() { _importingXlsx = false; _progressXlsx = 0; _progressLabel = ''; });
  }

  // ─── Dialog detail error setelah import ─────────────────────────────────────
  void _showImportErrorDialog(int bibit, int varian, int botol, int upd, int skip, String errStr, int errCount) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Row(children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        const Expanded(child: Text('Ringkasan Import', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
      ]),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('Berhasil: $bibit bibit, $varian varian, $botol botol', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
        if (upd > 0) Text('Diperbarui: $upd item', style: const TextStyle(fontSize: 12)),
        if (skip > 0) Text('Dilewati: $skip baris', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        Text('$errCount error — beberapa varian gagal masuk:', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.withOpacity(0.05), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.withOpacity(0.3))),
          child: Text(errStr.isEmpty ? '-' : errStr, style: const TextStyle(fontSize: 10, color: Colors.red, fontFamily: 'monospace'))),
        const SizedBox(height: 8),
        const Text('Tips: Cek tombol "Cek Data" untuk melihat produk tanpa varian.', style: TextStyle(fontSize: 10, color: Colors.grey)),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    ));
  }

  // ─── Cek data diagnostik ────────────────────────────────────────────────────
  Future<void> _cekData() async {
    _addLog('Memeriksa data...');
    try {
      final produk = await Api.getProduk(widget.toko['id']);
      final varian = await Api.getVarian(widget.toko['id']);

      final bibit = produk.where((p) => p['kategori'] == 'STOCK PARFUME').toList();
      final varianProdukIds = varian.map((v) => v['produk_id'].toString()).toSet();
      final bibitTanpaVarian = bibit.where((p) => !varianProdukIds.contains(p['id'].toString())).toList();

      // Deteksi varian duplikat (produk_id+ukuran+kualitas)
      final seenKeys = <String>{};
      final duplikatNama = <String>[];
      for (final v in varian) {
        final key = '${v['produk_id']}|${v['ukuran']}|${v['kualitas']}';
        if (seenKeys.contains(key)) duplikatNama.add('${v['nama']} ${v['ukuran']} ${v['kualitas']}');
        else seenKeys.add(key);
      }

      _addLog('Cek selesai: ${produk.length} produk, ${varian.length} varian, ${bibitTanpaVarian.length} bibit tanpa varian, ${duplikatNama.length} duplikat');

      if (!mounted) return;
      showDialog(context: context, builder: (_) => AlertDialog(
        title: const Text('Cek Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('Total produk: ${produk.length}', style: const TextStyle(fontSize: 12)),
          Text('Total varian: ${varian.length}', style: const TextStyle(fontSize: 12)),
          Text('Total bibit (STOCK PARFUME): ${bibit.length}', style: const TextStyle(fontSize: 12)),
          const Divider(),
          Text('Bibit tanpa varian: ${bibitTanpaVarian.length}',
            style: TextStyle(fontSize: 12, color: bibitTanpaVarian.isNotEmpty ? Colors.orange : Colors.green, fontWeight: FontWeight.w600)),
          if (bibitTanpaVarian.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...bibitTanpaVarian.take(15).map((p) => Text('  • ${p['nama']}', style: const TextStyle(fontSize: 11, color: Colors.orange))),
            if (bibitTanpaVarian.length > 15) Text('  ... +${bibitTanpaVarian.length - 15} lainnya', style: const TextStyle(fontSize: 11, color: Colors.orange)),
          ],
          const SizedBox(height: 4),
          Text('Varian duplikat: ${duplikatNama.length}',
            style: TextStyle(fontSize: 12, color: duplikatNama.isNotEmpty ? Colors.red : Colors.green, fontWeight: FontWeight.w600)),
          if (duplikatNama.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...duplikatNama.take(10).map((n) => Text('  • $n', style: const TextStyle(fontSize: 11, color: Colors.red))),
            if (duplikatNama.length > 10) Text('  ... +${duplikatNama.length - 10} lainnya', style: const TextStyle(fontSize: 11, color: Colors.red)),
          ],
          if (bibitTanpaVarian.isEmpty && duplikatNama.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Data bersih! Semua produk punya varian dan tidak ada duplikat.', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600))),
        ]))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
      ));
    } catch (e) {
      _addLog('GAGAL cek data: $e');
    }
  }

  // ─── Import Resep/BOM (xlsx atau CSV Olsera, separator ";") ─────────────────
  Future<void> _importBomFile() async {
    // BUG 2 FIX: validasi produk dulu
    if (_totalProduk == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Belum ada produk! Import produk dulu (Langkah 1) sebelum import resep.'),
          backgroundColor: Colors.red, duration: Duration(seconds: 5)));
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['csv', 'txt', 'xls', 'xlsx'],
      withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    _addLog('Membaca BOM: ${file.name} (${(file.size / 1024).toStringAsFixed(1)} KB)...');
    setState(() => _importingBom = true);

    try {
      List<List<dynamic>> csvRows = [];
      final ext = file.name.toLowerCase();

      if (ext.endsWith('.xlsx') || ext.endsWith('.xls')) {
        final bytes = file.bytes ?? await File(file.path!).readAsBytes();
        bool xlsxOk = false;
        try {
          final excelObj = xlsx.Excel.decodeBytes(bytes);
          // Safe sheet detection
          String sheetName = '';
          for (final k in excelObj.tables.keys) {
            try {
              if (excelObj.tables[k]?.rows.isNotEmpty ?? false) { sheetName = k; break; }
            } catch (_) { continue; }
          }
          if (sheetName.isEmpty && excelObj.tables.isNotEmpty) sheetName = excelObj.tables.keys.first;

          if (sheetName.isNotEmpty) {
            final iter = excelObj.tables[sheetName]!.rows.iterator;
            while (true) {
              bool moved = false;
              try { moved = iter.moveNext(); } catch (_) { break; }
              if (!moved) break;
              try {
                final row = iter.current;
                final rowData = row.take(9).map((cell) => cell?.value?.toString().trim() ?? '').toList();
                if (rowData.any((c) => c.isNotEmpty)) csvRows.add(rowData);
              } catch (_) { continue; }
            }
            if (csvRows.isNotEmpty) xlsxOk = true;
          }
        } catch (xlsxErr) {
          _addLog('xlsx parse gagal ($xlsxErr), mencoba sebagai CSV...');
        }

        // CSV fallback ONLY when xlsx produced no rows at all
        if (!xlsxOk && csvRows.isEmpty) {
          // Fallback: beberapa Olsera .xls sebenarnya CSV
          try {
            String content = utf8.decode(bytes, allowMalformed: true);
            if (content.isNotEmpty && content.codeUnitAt(0) == 0xFEFF) content = content.substring(1);
            if (content.contains(';')) {
              csvRows = const CsvToListConverter(fieldDelimiter: ';', eol: '\n').convert(content);
            } else {
              csvRows = const CsvToListConverter().convert(content, eol: '\n');
            }
            if (csvRows.isNotEmpty) _addLog('File dibaca sebagai CSV (${csvRows.length} baris)');
          } catch (_) {}
        }
      } else {
        // CSV / TXT
        String content;
        if (file.bytes != null) {
          content = utf8.decode(file.bytes!, allowMalformed: true);
        } else {
          content = await File(file.path!).readAsString(encoding: utf8);
        }
        if (content.contains(';')) {
          csvRows = const CsvToListConverter(fieldDelimiter: ';', eol: '\n').convert(content);
        } else {
          csvRows = const CsvToListConverter().convert(content, eol: '\n');
        }
      }

      if (csvRows.isEmpty) { _addLog('GAGAL: File kosong'); setState(() => _importingBom = false); return; }
      _addLog('${csvRows.length - 1} baris BOM ditemukan, memproses...');

      _addLog('Mengirim ke database (${csvRows.length - 1} baris)...');
      setState(() { _progressBom = 0.1; _progressLabel = 'Memproses resep...'; });
      final res = await Api.importResepOlsera(widget.toko['id'], csvRows,
        onProgress: (done, total) {
          if (mounted) {
            setState(() {
            _progressBom = 0.1 + (done / total) * 0.9;
            _progressLabel = '$done / $total resep (${ ((_progressBom)*100).toStringAsFixed(0)}%)';
          });
          }
        },
      );
      final updN  = res['updated'] ?? 0;
      final skipN = res['skipped'] ?? 0;
      if (updN > 0) {
        _addLog('OK: $updN resep berhasil disimpan, $skipN dilewati');
      } else {
        _addLog('GAGAL: 0 resep tersimpan, $skipN dilewati');
        _addLog('  Hint: Import produk xlsx dulu, baru import resep');
      }
      if (skipN > 0 && updN > 0) {
        final sv = res['skipped_varian'] ?? 0;
        final sb = res['skipped_botol']  ?? 0;
        if (sv > 0) _addLog('  [!] $sv dilewati: nama parfum tidak cocok di database');
        if (sb > 0) _addLog('  [!] $sb dilewati: botol tidak ditemukan (sudah di-auto-create)');
      }
      _loadStats();
    } catch (e) { _addLog('GAGAL: $e'); }
    setState(() { _importingBom = false; _progressBom = 0; _progressLabel = ''; });
  }

  // ─── Hapus semua produk & varian ────────────────────────────────────────────
  Future<void> _hapusSemuaProduk() async {
    final step1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Hapus Semua Produk?', style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.w700)),
      content: const Text('Ini akan menghapus SEMUA produk & varian cabang ini.\nStok movement juga akan dihapus.\nTidak dapat dibatalkan!', style: TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Lanjut')),
      ]));
    if (step1 != true) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: const Text('Ketik HAPUS untuk konfirmasi', style: TextStyle(fontSize: 13, color: Colors.red)),
      content: TextField(controller: ctrl, onChanged: (_) => setD(() {}),
        decoration: const InputDecoration(hintText: 'HAPUS', border: OutlineInputBorder(), isDense: true),
        style: const TextStyle(fontSize: 13, letterSpacing: 2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: ctrl.text == 'HAPUS' ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus Semua')),
      ])));
    if (confirmed != true) return;
    try {
      await Api.hapusSemuaProduk(widget.toko['id']);
      _loadStats();
      _addLog('OK: Semua produk & varian dihapus');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua produk & varian telah dihapus'), backgroundColor: Colors.red));
      }
    } catch (e) {
      _addLog('GAGAL hapus: $e');
    }
  }

  // ─── Reset semua resep ───────────────────────────────────────────────────────
  Future<void> _resetSemuaResep() async {
    final confirmed = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reset Semua Resep?', style: TextStyle(fontSize: 14, color: Color(0xFFE67E22), fontWeight: FontWeight.w700)),
      content: const Text('Semua resep_bibit dan resep_botol di varian akan di-reset ke 0/null.\nGunakan sebelum import resep baru dari Olsera.', style: TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)), child: const Text('Reset')),
      ]));
    if (confirmed != true) return;
    try {
      await Api.resetSemuaResep(widget.toko['id']);
      _addLog('OK: Semua resep di-reset');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua resep di-reset'), backgroundColor: Color(0xFFE67E22)));
      }
    } catch (e) {
      _addLog('GAGAL reset resep: $e');
    }
  }

  // ─── Download template xlsx ─────────────────────────────────────────────────
  Future<void> _downloadTemplateXlsx() async {
    try {
      final excel = xlsx.Excel.createExcel();
      final sheet = excel['product'];
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');

      // Header: minimal Olsera columns
      final headers = [
        'name','category','variant_names','sku','barcode',
        'buy_price','sell_price','stock_qty','low_stock_warning',
        'resep_bibit_ml','resep_botol',
      ];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
            xlsx.TextCellValue(headers[i]);
      }

      // Example BIBIT row
      final exBibit = ['BIBIT CONTOH PARFUM','STOCK PARFUME','','','',700,0,500,50,'',''];
      for (int i = 0; i < exBibit.length; i++) {
        final v = exBibit[i];
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value =
            v is String ? xlsx.TextCellValue(v) : xlsx.IntCellValue(v as int);
      }

      // Example BOTOL row
      final exBotol = ['BOTOL 30ML','STOK BOTOL','','','',2000,0,100,5,'',''];
      for (int i = 0; i < exBotol.length; i++) {
        final v = exBotol[i];
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 2)).value =
            v is String ? xlsx.TextCellValue(v) : xlsx.IntCellValue(v as int);
      }

      // Example VARIAN rows
      final exV1 = ['Contoh Parfum','STOCK PARFUME','15ML,MEDIUM','SKU001','',0,45000,0,0,15,'BOTOL 30ML'];
      final exV2 = ['Contoh Parfum','STOCK PARFUME','15ML,PLATINUM','SKU002','',0,75000,0,0,15,'BOTOL 30ML'];
      for (int i = 0; i < exV1.length; i++) {
        final v1 = exV1[i]; final v2 = exV2[i];
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 3)).value =
            v1 is String ? xlsx.TextCellValue(v1) : xlsx.IntCellValue(v1 as int);
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4)).value =
            v2 is String ? xlsx.TextCellValue(v2) : xlsx.IntCellValue(v2 as int);
      }

      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/template_produk_ksparfume.xlsx';
      final bytes = excel.save()!;
      await File(path).writeAsBytes(bytes);
      await Share.shareXFiles([XFile(path)], text: 'Template Import Produk KS Parfume');
      _addLog('OK: Template xlsx di-share');
    } catch (e) { _addLog('GAGAL template xlsx: $e'); }
  }

  // ─── Download template BOM xlsx (format Olsera 9 kolom) ────────────────────
  Future<void> _downloadTemplateBomXlsx() async {
    try {
      final excel = xlsx.Excel.createExcel();
      final sheet = excel['bom'];
      if (excel.tables.containsKey('Sheet1')) excel.delete('Sheet1');
      final headers = ['to_all_store_id','to_store_url_id','product_name','product_variant_name',
        'material_product_name','material_variant_name','qty','uom','uom_conversion'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value =
            xlsx.TextCellValue(headers[i]);
      }
      final exRows = [
        ['','namatoko','Contoh Parfum','15ML,MEDIUM','BIBIT CONTOH PARFUM','','15','ml','1'],
        ['','namatoko','Contoh Parfum','15ML,MEDIUM','BOTOL 30ML','','1','pcs','1'],
        ['','namatoko','Contoh Parfum','15ML,SUPER','BIBIT CONTOH PARFUM','','15','ml','1'],
        ['','namatoko','Contoh Parfum','15ML,SUPER','BOTOL 30ML','','1','pcs','1'],
      ];
      for (int r = 0; r < exRows.length; r++) {
        for (int c = 0; c < exRows[r].length; c++) {
          sheet.cell(xlsx.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value =
              xlsx.TextCellValue(exRows[r][c]);
        }
      }
      final dir  = await getTemporaryDirectory();
      final path = '${dir.path}/template_bom_ksparfume.xlsx';
      await File(path).writeAsBytes(excel.save()!);
      await Share.shareXFiles([XFile(path)], text: 'Template BOM/Resep KS Parfume');
      _addLog('OK: Template BOM xlsx di-share (format Olsera 9 kolom)');
    } catch (e) { _addLog('GAGAL template BOM: $e'); }
  }

  // ─── Export ─────────────────────────────────────────────────────────────────
  Future<void> _exportData(String type) async {
    setState(() => _exporting = true);
    try {
      final dir     = await getTemporaryDirectory();
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (type == 'json') {
        final produk = await Api.getProduk(widget.toko['id']);
        final varian = await Api.getVarian(widget.toko['id']);
        final trx    = await Api.getTransaksi(widget.toko['id'], limit: 99999);
        final peng   = await Api.getPengeluaran(widget.toko['id']);
        final data   = jsonEncode({'app': 'KS Parfume v3.1', 'exported_at': DateTime.now().toIso8601String(), 'produk': produk, 'varian': varian, 'transaksi': trx, 'pengeluaran': peng});
        final file   = File('${dir.path}/ks_parfume_backup_$dateStr.json');
        await file.writeAsString(data);
        await Share.shareXFiles([XFile(file.path)], text: 'Backup KS Parfume $dateStr');
        _addLog('OK: Backup JSON di-share');
      } else if (type == 'csv_trx') {
        final trx  = await Api.getTransaksi(widget.toko['id'], limit: 99999);
        final rows = [['No Nota', 'Tanggal', 'Kasir', 'Total', 'Diskon', 'Metode']];
        for (final t in trx) { rows.add([t['no_nota'] ?? '', t['tanggal'] ?? '', t['user_nama'] ?? '', '${t['total'] ?? 0}', '${t['diskon'] ?? 0}', t['metode'] ?? '']); }
        final file = File('${dir.path}/transaksi_$dateStr.csv');
        await file.writeAsString(const ListToCsvConverter().convert(rows));
        await Share.shareXFiles([XFile(file.path)], text: 'Transaksi KS Parfume $dateStr');
        _addLog('OK: Transaksi CSV di-share (${trx.length} nota)');
      } else if (type == 'csv_produk') {
        final produk = await Api.getProduk(widget.toko['id']);
        final rows   = [['Nama', 'Kategori', 'Harga Beli', 'Stok', 'Min Stok', 'Satuan']];
        for (final p in produk) { rows.add([p['nama'] ?? '', p['kategori'] ?? '', '${p['harga_beli'] ?? 0}', '${p['stok'] ?? 0}', '${p['min_stok'] ?? 0}', p['satuan'] ?? '']); }
        final file = File('${dir.path}/produk_$dateStr.csv');
        await file.writeAsString(const ListToCsvConverter().convert(rows));
        await Share.shareXFiles([XFile(file.path)], text: 'Produk KS Parfume $dateStr');
        _addLog('OK: Produk CSV di-share (${produk.length} item)');
      } else if (type == 'resep_csv') {
        final resepRows = await Api.exportResepCSVRows(widget.toko['id']);
        // Use ";" separator to match Olsera format
        final lines = resepRows.map((r) => r.map((c) => c.toString()).join(';')).join('\n');
        final file = File('${dir.path}/resep_bom_$dateStr.csv');
        await file.writeAsString(lines);
        await Share.shareXFiles([XFile(file.path)], text: 'Resep/BOM KS Parfume $dateStr');
        _addLog('OK: Resep CSV di-share (${resepRows.length - 1} baris)');
      }
    } catch (e) { _addLog('GAGAL Export: $e'); }
    setState(() => _exporting = false);
  }

  void _addLog(String msg) => setState(() => _log.insert(0, msg));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import / Export', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ─── Stats ──────────────────────────────────────────────────────────────
        Row(children: [
          _stat('Produk', '$_totalProduk', const Color(0xFF2980B9)),
          _stat('Varian', '$_totalVarian', const Color(0xFFD4A574)),
          _stat('Transaksi', '$_totalTrx', const Color(0xFF27AE60)),
        ]),
        const SizedBox(height: 16),

        // ─── LANGKAH 1: Import Produk (xlsx) ─────────────────────────────────────
        _sectionLabel('LANGKAH 1', 'Import Produk & Varian dulu', const Color(0xFF2980B9)),
        const SizedBox(height: 6),
        Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF2980B9), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.table_chart, color: Colors.white, size: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Import Produk & Varian', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2980B9)))),
          ]),
          const SizedBox(height: 12),
          _step('1', 'Ekspor produk dari Olsera (.xlsx atau .csv)'),
          _step('2', 'Klik "Pilih File .csv" untuk impor lebih cepat & stabil'),
          _step('3', 'Atau "Pilih File .xlsx" jika tidak ada versi CSV'),
          _step('4', 'Ulangi untuk semua file — data tidak duplikat'),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF0F7FF), borderRadius: BorderRadius.circular(6)),
            child: const Text('Format: BIBIT (name="BIBIT X"), VARIAN (variant_names="15ML,MEDIUM"), BOTOL (name="BOTOL X")',
              style: TextStyle(fontSize: 9, color: Color(0xFF2980B9)))),
          const SizedBox(height: 12),
          // Tombol xlsx
          SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
            onPressed: (_importingXlsx || _importingBom) ? null : _importXlsx,
            icon: Icon(_importingXlsx ? Icons.hourglass_empty : Icons.upload_file, size: 20),
            label: Text(_importingXlsx ? 'Mengimport...' : 'Pilih File .xlsx',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2980B9), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(height: 8),
          // Tombol CSV (lebih cepat, tidak ada masalah kolom)
          SizedBox(width: double.infinity, height: 46, child: ElevatedButton.icon(
            onPressed: (_importingXlsx || _importingBom) ? null : _importCsvProduk,
            icon: Icon(_importingXlsx ? Icons.hourglass_empty : Icons.table_rows, size: 20),
            label: Text(_importingXlsx ? 'Mengimport...' : 'Pilih File .csv (lebih cepat)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1A6B3A), foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          )),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: _importingXlsx ? null : _downloadTemplateXlsx,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Download Template', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF27AE60), side: const BorderSide(color: Color(0xFF27AE60)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(
              onPressed: (_importingXlsx || _importingBom) ? null : _cekData,
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Cek Data', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF8E44AD), side: const BorderSide(color: Color(0xFF8E44AD)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )),
          ]),
          if (_importingXlsx) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_progressLabel.isEmpty ? 'Membaca file...' : _progressLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFF2980B9), fontWeight: FontWeight.w600)),
              Text('${(_progressXlsx * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, color: Color(0xFF2980B9), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child:
              LinearProgressIndicator(value: _progressXlsx > 0 ? _progressXlsx : null,
                color: const Color(0xFF2980B9), backgroundColor: const Color(0xFFD0E8F8), minHeight: 8)),
            const SizedBox(height: 4),
            const Text('Jangan tutup app / tekan Home saja kalau mau ke menu lain',
              style: TextStyle(fontSize: 9, color: Color(0xFF888888))),
          ],
        ]))),
        const SizedBox(height: 10),

        // ─── LANGKAH 2: Import Resep/BOM ─────────────────────────────────────────
        _sectionLabel('LANGKAH 2', 'Import Resep/BOM setelah produk berhasil masuk', const Color(0xFF8E44AD)),
        const SizedBox(height: 6),
        Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF8E44AD), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.receipt_long, color: Colors.white, size: 20)),
            const SizedBox(width: 10),
            const Expanded(child: Text('Import Bahan/Resep', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF8E44AD)))),
          ]),
          const SizedBox(height: 8),
          if (_totalProduk == 0)
            Container(padding: const EdgeInsets.all(8), margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.red.withOpacity(0.4))),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.red, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text('Import produk dulu (Langkah 1) sebelum import resep!', style: TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600))),
              ])),
          _step('1', 'Pastikan Langkah 1 selesai (produk sudah ada)'),
          _step('2', 'Ekspor file BOM/Resep dari Olsera (.xlsx atau .csv)'),
          _step('3', 'Klik "Pilih File Resep" dan pilih file'),
          _step('4', 'Log tampilkan: "X varian diperbarui"'),
          const SizedBox(height: 4),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFF8F0FF), borderRadius: BorderRadius.circular(6)),
            child: const Text('Format Olsera 9 kolom (.xlsx atau .csv separator ";"):\n'
                'product_name | product_variant_name | material_product_name | qty',
              style: TextStyle(fontSize: 9, color: Color(0xFF8E44AD)))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 3, child: SizedBox(height: 46, child: ElevatedButton.icon(
              onPressed: (_importingBom || _importingXlsx) ? null : _importBomFile,
              icon: Icon(_importingBom ? Icons.hourglass_empty : Icons.upload_file, size: 20),
              label: Text(_importingBom ? 'Mengimport...' : 'Pilih File Resep',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8E44AD), foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: SizedBox(height: 46, child: OutlinedButton.icon(
              onPressed: _importingBom ? null : _downloadTemplateBomXlsx,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('Template', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF27AE60), side: const BorderSide(color: Color(0xFF27AE60)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
          ]),
          if (_importingBom) ...[
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_progressLabel.isEmpty ? 'Membaca file resep...' : _progressLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFF8E44AD), fontWeight: FontWeight.w600)),
              Text('${(_progressBom * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, color: Color(0xFF8E44AD), fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4), child:
              LinearProgressIndicator(value: _progressBom > 0 ? _progressBom : null,
                color: const Color(0xFF8E44AD), backgroundColor: const Color(0xFFEDD8F8), minHeight: 8)),
            const SizedBox(height: 4),
            const Text('Jangan tutup app / tekan Home saja kalau mau ke menu lain',
              style: TextStyle(fontSize: 9, color: Color(0xFF888888))),
          ],
          const SizedBox(height: 10),
          // Hapus/Reset buttons
          Row(children: [
            Expanded(child: SizedBox(height: 40, child: OutlinedButton.icon(
              onPressed: (_importingBom || _importingXlsx) ? null : _hapusSemuaProduk,
              icon: const Icon(Icons.delete_forever, size: 16),
              label: const Text('Hapus Produk', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
            const SizedBox(width: 8),
            Expanded(child: SizedBox(height: 40, child: OutlinedButton.icon(
              onPressed: (_importingBom || _importingXlsx) ? null : _resetSemuaResep,
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('Reset Resep', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFE67E22), side: const BorderSide(color: Color(0xFFE67E22)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            ))),
          ]),
        ]))),
        const SizedBox(height: 16),

        // ─── Export ──────────────────────────────────────────────────────────────
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.ios_share, color: Color(0xFF27AE60), size: 20), SizedBox(width: 8),
            Text('Export & Share', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))]),
          const SizedBox(height: 12),
          _expBtn(Icons.backup,       'Backup Semua (JSON)',  'json',       const Color(0xFFD4A574)),
          const SizedBox(height: 8),
          _expBtn(Icons.receipt_long, 'Transaksi (CSV)',      'csv_trx',    const Color(0xFF2980B9)),
          const SizedBox(height: 8),
          _expBtn(Icons.inventory_2,  'Data Produk (CSV)',    'csv_produk', const Color(0xFF27AE60)),
          const SizedBox(height: 8),
          _expBtn(Icons.science,      'Resep/BOM (CSV)',      'resep_csv',  const Color(0xFF8E44AD)),
        ]))),

        // ─── Log ─────────────────────────────────────────────────────────────────
        if (_log.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Log', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            GestureDetector(onTap: () => setState(() => _log.clear()),
              child: const Text('Hapus', style: TextStyle(fontSize: 11, color: Colors.red))),
          ]),
          const SizedBox(height: 8),
          Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _log.take(30).map((l) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: TextStyle(fontSize: 11,
                color: l.startsWith('OK') ? Colors.green
                    : (l.startsWith('GAGAL') || l.startsWith('  ERR:') || l.startsWith('[!]')) ? Colors.red
                    : l.startsWith('  [!]') ? Colors.orange
                    : const Color(0xFF6B5B4B)))
            )).toList()))),
        ],
        const SizedBox(height: 20),
      ]),
    );
  }

  Widget _sectionLabel(String badge, String text, Color color) => Row(children: [
    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600))),
  ]);

  Widget _step(String n, String text) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 20, height: 20, decoration: BoxDecoration(color: const Color(0xFFD4A574), borderRadius: BorderRadius.circular(10)),
      child: Center(child: Text(n, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
    const SizedBox(width: 8),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 11, color: Color(0xFF4A4A4A)))),
  ]));

  Widget _stat(String lb, String v, Color c) => Expanded(child: Card(child: Padding(padding: const EdgeInsets.all(10),
    child: Column(children: [Text(lb, style: TextStyle(fontSize: 9, color: Colors.grey[500])),
      Text(v, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c))]))));

  Widget _expBtn(IconData ic, String title, String type, Color c) => GestureDetector(
    onTap: _exporting ? null : () => _exportData(type),
    child: Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withOpacity(0.06), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.2))),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(8)), child: Icon(ic, color: Colors.white, size: 16)),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c))),
        Icon(Icons.share, color: c, size: 16),
      ])));
}

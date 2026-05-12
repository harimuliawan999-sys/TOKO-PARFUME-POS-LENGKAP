import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:io';
import '../services/api.dart';

class ResepTemplateScreen extends StatefulWidget {
  const ResepTemplateScreen({super.key});
  @override State<ResepTemplateScreen> createState() => _ResepTemplateScreenState();
}

class _ResepTemplateScreenState extends State<ResepTemplateScreen> {
  List<Map<String, dynamic>> _templates = [];
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final t = await Api.getResepTemplate();
      if (mounted) setState(() { _templates = t; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _editTemplate(Map<String, dynamic>? existing) {
    final ukuranCtrl = TextEditingController(text: existing?['ukuran']?.toString() ?? '');
    final kualitasCtrl = TextEditingController(text: existing?['kualitas']?.toString() ?? '');
    final bibitCtrl = TextEditingController(text: '${existing?['qty_bibit'] ?? ''}');
    final botolCtrl = TextEditingController(text: '${existing?['qty_botol'] ?? 1}');
    final katBotolCtrl = TextEditingController(text: existing?['botol_kategori']?.toString() ?? '');

    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(existing == null ? 'Tambah Template' : 'Edit Template', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Expanded(child: TextField(controller: ukuranCtrl,
            decoration: const InputDecoration(labelText: 'Ukuran', border: OutlineInputBorder(), isDense: true, hintText: '15ML'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: kualitasCtrl,
            decoration: const InputDecoration(labelText: 'Kualitas', border: OutlineInputBorder(), isDense: true, hintText: 'MEDIUM'))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: bibitCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Qty Bibit (ml)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: botolCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Qty Botol (pcs)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: katBotolCtrl,
          decoration: const InputDecoration(labelText: 'Kategori Botol', border: OutlineInputBorder(), isDense: true, hintText: 'STOK BOTOL 15ML')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          final data = {
            'ukuran': ukuranCtrl.text.toUpperCase(),
            'kualitas': kualitasCtrl.text.toUpperCase(),
            'qty_bibit': double.tryParse(bibitCtrl.text) ?? 0,
            'qty_botol': double.tryParse(botolCtrl.text) ?? 1,
            'botol_kategori': katBotolCtrl.text.toUpperCase(),
          };
          try {
            if (existing == null) {
              await Api.addResepTemplate(data);
            } else {
              await Api.updateResepTemplate(existing['id'], data);
            }
            if (!mounted) return;
            Navigator.pop(context); _load();
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e')));
          }
        }, child: const Text('Simpan')),
      ]));
  }

  void _hapusTemplate(Map<String, dynamic> t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Hapus Template?', style: TextStyle(fontSize: 14)),
      content: Text('${t['ukuran']} ${t['kualitas']} akan dihapus'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.deleteResepTemplate(t['id']);
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus')),
      ]));
  }

  // ═══ IMPORT CSV RESEP (format 01_csv.xls) ═══
  Future<void> _importCsvResep() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'xls', 'txt'], withData: true);
      if (result == null) return;
      final f = result.files.single;
      final text = f.bytes != null
          ? utf8.decode(f.bytes!, allowMalformed: true)
          : await File(f.path!).readAsString();
      final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) throw 'File kosong';

      // Parse header (separator ;)
      final hdr = lines[0].split(';');
      final variantIdx = hdr.indexWhere((h) => h.trim() == 'product_variant_name');
      final matIdx = hdr.indexWhere((h) => h.trim() == 'material_product_name');
      final qtyIdx = hdr.indexWhere((h) => h.trim() == 'qty');

      if (variantIdx < 0 || matIdx < 0 || qtyIdx < 0) throw 'Format CSV tidak sesuai';

      // Parse & build templates
      final templates = <String, Map<String, dynamic>>{};
      for (int i = 1; i < lines.length; i++) {
        final cols = lines[i].split(';');
        if (cols.length < 7) continue;
        final variant = cols.length > variantIdx ? cols[variantIdx].trim() : '';
        final material = cols.length > matIdx ? cols[matIdx].trim() : '';
        final qty = cols.length > qtyIdx ? (double.tryParse(cols[qtyIdx].trim()) ?? 0) : 0;
        if (variant.isEmpty) continue;

        final parts = variant.split(',');
        if (parts.length < 2) continue;
        final ukuran = parts[0].trim().toUpperCase();
        final kualitas = parts[1].trim().toUpperCase();
        final key = '$ukuran|$kualitas';

        templates.putIfAbsent(key, () => {'ukuran': ukuran, 'kualitas': kualitas, 'qty_bibit': 0, 'qty_botol': 1, 'botol_kategori': ''});

        if (material.toUpperCase().contains('BIBIT')) {
          templates[key]!['qty_bibit'] = qty;
        } else if (material.toUpperCase().contains('BOTOL') || material.toUpperCase().contains('STOK BOTOL')) {
          templates[key]!['qty_botol'] = qty;
          templates[key]!['botol_kategori'] = material.toUpperCase();
        }
      }

      // Upsert ke DB
      int count = 0;
      for (final t in templates.values) {
        try {
          // Cek existing
          final existing = await Api.getResepTemplateBy(t['ukuran'], t['kualitas']);
          if (existing != null) {
            await Api.updateResepTemplate(existing['id'], t);
          } else {
            await Api.addResepTemplate(t);
          }
          count++;
        } catch (_) {}
      }

      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Import OK: $count template'), backgroundColor: const Color(0xFF27AE60)));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GAGAL: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Template Resep', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.upload_file, size: 20), onPressed: _importCsvResep, tooltip: 'Import CSV'),
          IconButton(icon: const Icon(Icons.add, size: 22), onPressed: () => _editTemplate(null)),
        ]),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(12), children: [
          Container(padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Template Resep Otomatis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${_templates.length} template aktif. Saat bikin varian baru, rumus bibit otomatis pakai template ini.',
                style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            ])),
          const SizedBox(height: 12),
          ..._templates.map((t) => Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
            leading: Container(padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFD4A574).withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
              child: Text('${t['ukuran']}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
            title: Text('${t['ukuran']} ${t['kualitas']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: Text('${t['qty_bibit']} ml bibit + ${t['qty_botol']} ${t['botol_kategori'] ?? 'botol'}',
              style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.edit, size: 16, color: Color(0xFF2980B9)), onPressed: () => _editTemplate(t)),
              IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () => _hapusTemplate(t)),
            ])))),
        ])),
    );
  }
}

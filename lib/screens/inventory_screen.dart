import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class InventoryScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  final bool isOwner;
  const InventoryScreen({super.key, required this.toko, required this.isOwner});
  @override State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  List<Map<String, dynamic>> _produk = [];
  String _filter = 'semua', _searchInv = '';
  bool _showAdd = false;
  String _addNama = '', _addBeli = '', _addStok = '0', _addKat = 'STOCK PARFUME', _addSat = 'ml';
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async { try { final p = await Api.getProduk(widget.toko['id'], kategori: _filter == 'semua' ? null : _filter); if (mounted) setState(() => _produk = p); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e'), backgroundColor: Colors.red)); } }

  void _editProduk(Map<String, dynamic> p) {
    final stokCtrl = TextEditingController(text: '${p['stok']}');
    final hargaCtrl = TextEditingController(text: '${p['harga_beli']}');
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('${p['nama']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: stokCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Stok', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: hargaCtrl, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Harga Beli (Rp)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 6),
        const Text('Harga beli disimpan permanen, tidak perlu input ulang', style: TextStyle(fontSize: 9, color: Color(0xFFA09080))),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          await Api.updateProduk(p['id'], {
            'stok': double.tryParse(stokCtrl.text) ?? 0,
            'harga_beli': double.tryParse(hargaCtrl.text) ?? 0,
          });
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, child: const Text('Simpan'))]));
  }

  Future<void> _addProduk() async {
    if (_addNama.isEmpty || _addBeli.isEmpty) return;
    await Api.addProduk({'toko_id': widget.toko['id'], 'nama': _addNama, 'kategori': _addKat, 'harga_beli': double.tryParse(_addBeli) ?? 0, 'stok': double.tryParse(_addStok) ?? 0, 'min_stok': 50, 'satuan': _addSat});
    setState(() { _showAdd = false; _addNama = ''; _addBeli = ''; _addStok = '0'; }); _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventori', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [if (widget.isOwner) IconButton(icon: Icon(_showAdd ? Icons.close : Icons.add), onPressed: () => setState(() => _showAdd = !_showAdd))]),
      body: RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          onChanged: (v) => setState(() => _searchInv = v),
          decoration: InputDecoration(hintText: 'Cari nama produk...', prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: ['semua', 'STOCK PARFUME', 'STOK BOTOL'].map((k) => ChoiceChip(label: Text(k == 'semua' ? 'Semua' : k, style: TextStyle(fontSize: 11, color: _filter == k ? Colors.white : const Color(0xFF6B5B4B))),
          selected: _filter == k, onSelected: (_) { setState(() => _filter = k); _load(); }, selectedColor: const Color(0xFFD4A574))).toList()),
        if (_showAdd) Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          TextField(onChanged: (v) => _addNama = v, decoration: const InputDecoration(labelText: 'Nama Produk', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: DropdownButtonFormField<String>(value: _addKat, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true), style: const TextStyle(fontSize: 12, color: Colors.black),
            items: ['STOCK PARFUME', 'STOK BOTOL'].map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 12)))).toList(), onChanged: (v) => setState(() => _addKat = v!))),
            const SizedBox(width: 8),
            SizedBox(width: 80, child: DropdownButtonFormField<String>(value: _addSat, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: ['ml', 'pcs'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _addSat = v!)))]),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: TextField(onChanged: (v) => _addBeli = v, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Harga Beli', border: OutlineInputBorder(), isDense: true))),
            const SizedBox(width: 8),
            Expanded(child: TextField(onChanged: (v) => _addStok = v, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stok Awal', border: OutlineInputBorder(), isDense: true)))]),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _addProduk, child: const Text('Simpan'))),
        ]))),
        const SizedBox(height: 12),
        ...(_searchInv.isEmpty ? _produk : _produk.where((p) => (p['nama'] ?? '').toString().toLowerCase().contains(_searchInv.toLowerCase())).toList()).map((p) { final low = (p['stok'] as num) <= (p['min_stok'] as num);
          return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
            title: Text('${p['nama']}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
            subtitle: Text('${p['kategori']} · ${cur.format(p['harga_beli'])}/unit', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${p['stok']} ${p['satuan']}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: low ? Colors.red : const Color(0xFF3A2E24))),
              if (widget.isOwner) ...[const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.edit, size: 16), onPressed: () => _editProduk(p), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () async {
                  if (await showDialog<bool>(context: context, builder: (_) => AlertDialog(title: const Text('Hapus?', style: TextStyle(fontSize: 14)),
                    actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
                      ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus'))])) == true) { await Api.deleteProduk(p['id']); _load(); }
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints())]])));
        }),
      ])),
    );
  }
}

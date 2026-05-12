import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class StokKeluarScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const StokKeluarScreen({super.key, required this.toko, required this.user});
  @override State<StokKeluarScreen> createState() => _StokKeluarScreenState();
}

class _StokKeluarScreenState extends State<StokKeluarScreen> {
  final cur     = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('d MMM yyyy HH:mm', 'id_ID');
  final _qtyCtrl   = TextEditingController();
  final _notesCtrl = TextEditingController();

  List<Map<String, dynamic>> _produk = [], _riwayat = [];
  String? _produkId;
  String  _alasan    = 'Rusak';
  bool    _saving    = false;
  String  _searchRw  = '';

  static const _alasanList = ['Rusak', 'Hilang', 'Sample/Tester', 'Koreksi Stok', 'Lainnya'];

  String get tokoId => widget.toko['id'];

  @override void initState() { super.initState(); _load(); }
  @override void dispose()   { _qtyCtrl.dispose(); _notesCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    try {
      final produk  = await Api.getProduk(tokoId);
      final riwayat = await Api.getStokMovement(tokoId, tipe: 'keluar', limit: 100);
      if (mounted) {
        setState(() {
        _produk  = produk.where((p) =>
          ['STOCK PARFUME', 'STOK BOTOL', 'STOK SPRAY'].contains(p['kategori'])).toList();
        _riwayat = riwayat;
      });
      }
    } catch (_) {}
  }

  Future<void> _simpan() async {
    if (_produkId == null || _qtyCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih produk dan isi jumlah!')));
      return;
    }
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Qty harus > 0'))); return; }

    final p = _produk.firstWhere((x) => x['id'].toString() == _produkId, orElse: () => {});
    final stokSaat = ((p['stok'] ?? 0) as num).toDouble();
    if (qty > stokSaat) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stok tidak cukup! Saat ini: ${stokSaat.toStringAsFixed(0)} ${p['satuan'] ?? ''}')));
      return;
    }

    setState(() => _saving = true);
    try {
      final keterangan = _notesCtrl.text.trim().isEmpty
          ? _alasan : '$_alasan — ${_notesCtrl.text.trim()}';
      await Api.tambahStokKeluar(tokoId, _produkId!, qty, widget.user['id'], keterangan);
      setState(() { _qtyCtrl.clear(); _notesCtrl.clear(); _produkId = null; _alasan = 'Rusak'; });
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok keluar dicatat!'), backgroundColor: Color(0xFFD4A574)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
    setState(() => _saving = false);
  }

  String _produkLabel(String? id) {
    if (id == null) return 'Pilih Produk';
    final p = _produk.firstWhere((x) => x['id'].toString() == id, orElse: () => {});
    if (p.isEmpty) return 'Pilih Produk';
    final stok = ((p['stok'] ?? 0) as num).toDouble();
    final sat  = p['satuan'] ?? '';
    return '${p['nama']}  (stok: ${stok.toStringAsFixed(0)} $sat)';
  }

  void _showProdukPicker() {
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
                        final isSel = p['id'].toString() == _produkId;
                        return ListTile(
                          dense: true,
                          selected: isSel,
                          selectedTileColor: const Color(0xFFC0392B).withOpacity(0.08),
                          title: Text('${p['nama']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          subtitle: Text('Stok: ${((p['stok'] ?? 0) as num).toStringAsFixed(0)} ${p['satuan'] ?? ''}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                          trailing: isSel ? const Icon(Icons.check_circle, color: Color(0xFFC0392B), size: 18) : null,
                          onTap: () { Navigator.pop(ctx); setState(() => _produkId = p['id'].toString()); },
                        );
                      }),
              ),
            ]),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredRw = _searchRw.isEmpty
        ? _riwayat
        : _riwayat.where((r) {
            final p = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {});
            final nama = (p['nama'] ?? '').toString().toLowerCase();
            final ket  = (r['keterangan'] ?? '').toString().toLowerCase();
            return nama.contains(_searchRw.toLowerCase()) || ket.contains(_searchRw.toLowerCase());
          }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Keluar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFFC0392B),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [

          // Tanggal hari ini
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFC0392B).withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.calendar_today, size: 14, color: Color(0xFFC0392B)),
              const SizedBox(width: 8),
              Text('Tanggal: ${DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(DateTime.now())}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFC0392B), fontWeight: FontWeight.w600)),
            ])),

          // ─── Form ────────────────────────────────────────────────────────────
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [

            Row(children: [
              Container(padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFC0392B), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.remove_circle, color: Colors.white, size: 18)),
              const SizedBox(width: 10),
              const Text('Catat Stok Keluar',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 14),

            // Produk dropdown
            GestureDetector(
              onTap: _showProdukPicker,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade600), borderRadius: BorderRadius.circular(4)),
                child: Row(children: [
                  const Icon(Icons.inventory_2, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_produkLabel(_produkId), style: TextStyle(fontSize: 12, color: _produkId != null ? Colors.black87 : Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                  const Icon(Icons.search, size: 16, color: Color(0xFFC0392B)),
                ]),
              ),
            ),
            const SizedBox(height: 10),

            // Qty
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), isDense: true,
                labelText: 'Jumlah / Qty', prefixIcon: Icon(Icons.onetwothree, size: 18)),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),

            // Alasan
            DropdownButtonFormField<String>(
              value: _alasan,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), isDense: true,
                labelText: 'Alasan', prefixIcon: Icon(Icons.label_outline, size: 18)),
              style: const TextStyle(fontSize: 12, color: Colors.black),
              items: _alasanList.map((a) =>
                DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => setState(() => _alasan = v ?? 'Rusak'),
            ),
            const SizedBox(height: 10),

            // Catatan
            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(), isDense: true,
                labelText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.notes, size: 18)),
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 14),

            SizedBox(width: double.infinity, child: ElevatedButton.icon(
              onPressed: _saving ? null : _simpan,
              icon: Icon(_saving ? Icons.hourglass_empty : Icons.remove_circle, size: 18),
              label: Text(_saving ? 'Menyimpan...' : 'Catat Keluar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC0392B), foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            )),
          ]))),
          const SizedBox(height: 16),

          // ─── Riwayat ─────────────────────────────────────────────────────────
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Riwayat Stok Keluar',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            Text('${filteredRw.length} catatan',
              style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
          ]),
          const SizedBox(height: 6),

          // Search riwayat
          TextField(
            onChanged: (v) => setState(() => _searchRw = v),
            decoration: InputDecoration(
              hintText: 'Cari produk atau keterangan...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              filled: true, fillColor: Colors.white,
            ),
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 8),

          if (filteredRw.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(24),
              child: Text('Belum ada catatan stok keluar',
                style: TextStyle(color: Color(0xFFA09080), fontSize: 12))))
          else
            ...filteredRw.map((r) {
              final p    = _produk.firstWhere((x) => x['id'] == r['produk_id'], orElse: () => {});
              final nama = (p['nama'] ?? 'Produk?').toString();
              final sat  = (p['satuan'] ?? '').toString();
              final qty  = ((r['qty'] ?? 0) as num).abs().toDouble();
              final ket  = (r['keterangan'] ?? '').toString();
              final tgl  = DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal();
              final tglStr = tgl != null ? dateFmt.format(tgl) : 'Tanggal tidak tersedia';

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFFFDF0E8),
                    child: Icon(_alasanIcon(ket), color: const Color(0xFFC0392B), size: 16)),
                  title: Text(nama,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(ket, style: const TextStyle(fontSize: 10, color: Color(0xFF8B7355))),
                    Text(tglStr, style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                  ]),
                  trailing: Text('-${qty.toStringAsFixed(0)} $sat',
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
                ),
              );
            }),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }

  IconData _alasanIcon(String ket) {
    final k = ket.toLowerCase();
    if (k.contains('rusak'))   return Icons.broken_image;
    if (k.contains('hilang'))  return Icons.search_off;
    if (k.contains('sample') || k.contains('tester')) return Icons.science;
    if (k.contains('koreksi')) return Icons.edit;
    return Icons.remove_circle_outline;
  }
}

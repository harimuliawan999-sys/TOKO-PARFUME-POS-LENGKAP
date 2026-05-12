import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class PelangganScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const PelangganScreen({super.key, required this.toko, required this.user});
  @override State<PelangganScreen> createState() => _PelangganScreenState();
}

class _PelangganScreenState extends State<PelangganScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
  List<Map<String, dynamic>> _list = [];
  String _search = '';
  bool _loading = true;
  String get tokoId => widget.toko['id'];

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await Api.getPelanggan(tokoId);
      if (mounted) setState(() { _list = l; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // ═══ DIALOG TAMBAH PELANGGAN BARU ═══
  Future<void> _tambahBaru() async {
    final namaCtrl = TextEditingController();
    final hpCtrl = TextEditingController();
    final alamatCtrl = TextEditingController();
    bool saving = false;
    String? saveError;

    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Tambah Pelanggan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: namaCtrl, autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama Pelanggan*', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        TextField(controller: hpCtrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'No. HP (opsional)', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        TextField(controller: alamatCtrl, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Alamat (opsional)', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        if (saveError != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(child: Text(saveError!, style: const TextStyle(fontSize: 10, color: Colors.red))),
            ])),
        ],
      ])),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: saving ? null : () async {
          final nama = namaCtrl.text.trim();
          if (nama.isEmpty) {
            setD(() => saveError = 'Nama wajib diisi');
            return;
          }
          setD(() { saving = true; saveError = null; });
          try {
            final payload = <String, dynamic>{'toko_id': tokoId, 'nama': nama};
            if (hpCtrl.text.trim().isNotEmpty) payload['hp'] = hpCtrl.text.trim();
            if (alamatCtrl.text.trim().isNotEmpty) payload['alamat'] = alamatCtrl.text.trim();
            await Api.addPelanggan(payload);
            if (mounted) Navigator.pop(context);
            await _load();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Pelanggan ditambahkan'), backgroundColor: Color(0xFF27AE60)));
          } catch (e) {
            setD(() { saving = false; saveError = 'Gagal simpan: $e'; });
          }
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60)),
          child: saving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Simpan')),
      ],
    )));
  }

  // ═══ DIALOG EDIT PELANGGAN ═══
  Future<void> _editPelanggan(Map<String, dynamic> p) async {
    final namaCtrl = TextEditingController(text: p['nama']?.toString() ?? '');
    final hpCtrl = TextEditingController(text: p['hp']?.toString() ?? '');
    final alamatCtrl = TextEditingController(text: p['alamat']?.toString() ?? '');
    bool saving = false;
    String? saveError;

    await showDialog(context: context, builder: (_) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Edit Pelanggan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
      content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: namaCtrl, autofocus: true,
          decoration: const InputDecoration(labelText: 'Nama*', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        TextField(controller: hpCtrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'No. HP', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 8),
        TextField(controller: alamatCtrl, maxLines: 2,
          decoration: const InputDecoration(labelText: 'Alamat', border: OutlineInputBorder(), isDense: true),
          style: const TextStyle(fontSize: 13)),
        if (saveError != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 14, color: Colors.red),
              const SizedBox(width: 6),
              Expanded(child: Text(saveError!, style: const TextStyle(fontSize: 10, color: Colors.red))),
            ])),
        ],
      ])),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: saving ? null : () async {
          final nama = namaCtrl.text.trim();
          if (nama.isEmpty) {
            setD(() => saveError = 'Nama wajib diisi');
            return;
          }
          setD(() { saving = true; saveError = null; });
          try {
            final payload = <String, dynamic>{'nama': nama};
            payload['hp'] = hpCtrl.text.trim().isEmpty ? null : hpCtrl.text.trim();
            payload['alamat'] = alamatCtrl.text.trim().isEmpty ? null : alamatCtrl.text.trim();
            await Api.updatePelanggan(p['id'].toString(), payload);
            if (mounted) Navigator.pop(context);
            await _load();
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Data pelanggan diperbarui'), backgroundColor: Color(0xFF27AE60)));
          } catch (e) {
            setD(() { saving = false; saveError = 'Gagal update: $e'; });
          }
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A574)),
          child: saving
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Simpan')),
      ],
    )));
  }

  // ═══ KONFIRMASI HAPUS (2x, destructive) ═══
  Future<void> _hapusPelanggan(Map<String, dynamic> p) async {
    final nama = p['nama']?.toString() ?? '-';
    final totalBelanja = ((p['total_belanja'] ?? 0) as num).toDouble();
    final jumlahTrx = ((p['jumlah_transaksi'] ?? 0) as num).toInt();
    final diskonTersedia = Api.hitungDiskonTersedia(p);
    final diskonDipakai = ((p['diskon_dipakai'] ?? 0) as num).toDouble();
    final adaLoyalty = totalBelanja > 0 || diskonTersedia > 0;

    // Konfirmasi 1
    final ok1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.warning_amber_rounded, color: Color(0xFFC0392B)),
        SizedBox(width: 8),
        Text('Hapus Pelanggan?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Banner BAHAYA kalau ada diskon tersedia
        if (diskonTersedia > 0) Container(
          padding: const EdgeInsets.all(10), margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: const Color(0xFFC0392B), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            const Icon(Icons.report_problem, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚠ PELANGGAN PUNYA DISKON AKTIF', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
              Text('${cur.format(diskonTersedia)} akan HANGUS!',
                style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700)),
            ])),
          ])),

        Text('Nama: $nama', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total Belanja:', style: TextStyle(fontSize: 11)),
          Text(cur.format(totalBelanja), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: totalBelanja > 0 ? const Color(0xFFD4A574) : Colors.grey)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Jumlah Transaksi:', style: TextStyle(fontSize: 11)),
          Text('$jumlahTrx', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: jumlahTrx > 0 ? const Color(0xFF2980B9) : Colors.grey)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Diskon Tersedia:', style: TextStyle(fontSize: 11)),
          Text(cur.format(diskonTersedia), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: diskonTersedia > 0 ? const Color(0xFFC0392B) : Colors.grey)),
        ]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Diskon Sudah Dipakai:', style: TextStyle(fontSize: 11)),
          Text(cur.format(diskonDipakai), style: const TextStyle(fontSize: 11, color: Color(0xFF8E44AD))),
        ]),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(6)),
          child: const Text(
            'Yang akan terjadi setelah hapus:\n'
            '• Nama, HP, alamat pelanggan HILANG permanen\n'
            '• Total belanja & sisa diskon HILANG\n'
            '• Transaksi struk lama TETAP ada (aman, jadi "Walk-in")\n'
            '• Kalau ditambah lagi nama yang sama, mulai dari 0',
            style: TextStyle(fontSize: 10, color: Color(0xFF856404)))),
        if (adaLoyalty) const SizedBox(height: 8),
        if (adaLoyalty) const Text(
          '💡 Tip: Kalau cuma mau ganti nama/HP, pakai "Edit" saja jangan dihapus.',
          style: TextStyle(fontSize: 10, color: Color(0xFF27AE60), fontStyle: FontStyle.italic)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
          child: const Text('Lanjut Hapus')),
      ]));
    if (ok1 != true) return;

    // Konfirmasi 2 (extra paranoia karena destructive)
    final ok2 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Yakin?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hapus permanen pelanggan "$nama"?', style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        const Text('Tindakan ini TIDAK BISA dibatalkan.', style: TextStyle(fontSize: 11, color: Color(0xFFC0392B), fontWeight: FontWeight.w600)),
        if (diskonTersedia > 0) ...[
          const SizedBox(height: 8),
          Text('Diskon ${cur.format(diskonTersedia)} akan hangus.',
            style: const TextStyle(fontSize: 11, color: Color(0xFFC0392B), fontWeight: FontWeight.w700)),
        ],
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('TIDAK')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
          child: const Text('YA, HAPUS')),
      ]));
    if (ok2 != true) return;

    try {
      await Api.deletePelanggan(p['id'].toString());
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pelanggan "$nama" dihapus'),
        backgroundColor: const Color(0xFF27AE60)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Gagal hapus: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══ DETAIL & RIWAYAT TRANSAKSI ═══
  Future<void> _lihatDetail(Map<String, dynamic> p) async {
    showModalBottomSheet(context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
        builder: (_, ctrl) => FutureBuilder<List<Map<String, dynamic>>>(
          future: Api.getTransaksiPelanggan(p['id'].toString(), limit: 100),
          builder: (ctx, snap) {
            final tersedia = Api.hitungDiskonTersedia(p);
            final totalBelanja = ((p['total_belanja'] ?? 0) as num).toDouble();
            final jumlahTrx = ((p['jumlah_transaksi'] ?? 0) as num).toInt();
            final diskonDipakai = ((p['diskon_dipakai'] ?? 0) as num).toDouble();
            return ListView(controller: ctrl, padding: const EdgeInsets.all(20), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['nama'] ?? '-', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  if (p['hp'] != null && p['hp'].toString().isNotEmpty)
                    Text('📞 ${p['hp']}', style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B))),
                  if (p['alamat'] != null && p['alamat'].toString().isNotEmpty)
                    Text('📍 ${p['alamat']}', style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B))),
                ])),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ]),
              const Divider(),
              // Stats card
              Row(children: [
                Expanded(child: _statCard('Total Belanja', cur.format(totalBelanja), const Color(0xFFD4A574))),
                const SizedBox(width: 8),
                Expanded(child: _statCard('Transaksi', '$jumlahTrx', const Color(0xFF2980B9))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _statCard('Diskon Tersedia', cur.format(tersedia), const Color(0xFF27AE60))),
                const SizedBox(width: 8),
                Expanded(child: _statCard('Diskon Dipakai', cur.format(diskonDipakai), const Color(0xFF8E44AD))),
              ]),
              const SizedBox(height: 16),
              const Text('Riwayat Transaksi', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              if (snap.connectionState == ConnectionState.waiting)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: Color(0xFFD4A574))))
              else if (snap.data == null || snap.data!.isEmpty)
                const Padding(padding: EdgeInsets.all(16),
                  child: Center(child: Text('Belum ada transaksi', style: TextStyle(fontSize: 11, color: Color(0xFFA09080)))))
              else
                ...snap.data!.map((t) {
                  final tgl = DateTime.tryParse((t['created_at'] ?? '').toString())?.toLocal();
                  final tglStr = tgl != null ? DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(tgl) : '-';
                  return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
                    leading: CircleAvatar(radius: 14, backgroundColor: const Color(0xFFF0EBE4),
                      child: Text((t['metode'] ?? 'C').toString()[0],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
                    title: Text(t['no_nota'] ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    subtitle: Text(tglStr, style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
                    trailing: Text(cur.format(t['total'] ?? 0),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF27AE60))),
                  ));
                }),
              const SizedBox(height: 20),
            ]);
          })));
  }

  Widget _statCard(String label, String value, Color color) => Card(
    child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFA09080))),
      const SizedBox(height: 4),
      Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color), overflow: TextOverflow.ellipsis),
    ])));

  @override
  Widget build(BuildContext context) {
    final filtered = _search.isEmpty ? _list :
      _list.where((p) {
        final q = _search.toLowerCase();
        return (p['nama'] ?? '').toString().toLowerCase().contains(q) ||
               (p['hp'] ?? '').toString().toLowerCase().contains(q);
      }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daftar Pelanggan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _load, tooltip: 'Refresh'),
        ]),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
        : Column(children: [
            // Search bar
            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Cari nama / no. HP...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true),
                style: const TextStyle(fontSize: 13))),

            // Summary count
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${filtered.length} pelanggan', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
                Text('Total ${_list.length}', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
              ])),
            const SizedBox(height: 8),

            // List
            Expanded(child: filtered.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.people_outline, size: 64, color: Color(0xFFE8E0D8)),
                  const SizedBox(height: 8),
                  Text(_search.isEmpty ? 'Belum ada pelanggan' : 'Tidak ditemukan',
                    style: const TextStyle(fontSize: 13, color: Color(0xFFA09080))),
                ]))
              : RefreshIndicator(onRefresh: _load, child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final p = filtered[i];
                    final tersedia = Api.hitungDiskonTersedia(p);
                    final totalBelanja = ((p['total_belanja'] ?? 0) as num).toDouble();
                    final jumlahTrx = ((p['jumlah_transaksi'] ?? 0) as num).toInt();
                    return Card(margin: const EdgeInsets.only(bottom: 6), child: InkWell(
                      onTap: () => _lihatDetail(p),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                        CircleAvatar(radius: 20, backgroundColor: const Color(0xFFD4A574).withOpacity(0.2),
                          child: Text((p['nama'] ?? '?').toString()[0].toUpperCase(),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFD4A574)))),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(p['nama'] ?? '-',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                            if (tersedia > 0)
                              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF27AE60), borderRadius: BorderRadius.circular(4)),
                                child: Text('Diskon ${cur.format(tersedia)}',
                                  style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700))),
                          ]),
                          const SizedBox(height: 2),
                          if (p['hp'] != null && p['hp'].toString().isNotEmpty)
                            Text('📞 ${p['hp']}', style: const TextStyle(fontSize: 10, color: Color(0xFF6B5B4B))),
                          Text('$jumlahTrx trx · ${cur.format(totalBelanja)}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                        ])),
                        // Action buttons
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF6B5B4B)),
                          padding: EdgeInsets.zero,
                          onSelected: (v) {
                            if (v == 'detail') _lihatDetail(p);
                            else if (v == 'edit') _editPelanggan(p);
                            else if (v == 'hapus') _hapusPelanggan(p);
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'detail', height: 36,
                              child: Row(children: [Icon(Icons.receipt_long, size: 14, color: Color(0xFF2980B9)),
                                SizedBox(width: 8), Text('Detail & Riwayat', style: TextStyle(fontSize: 12))])),
                            const PopupMenuItem(value: 'edit', height: 36,
                              child: Row(children: [Icon(Icons.edit, size: 14, color: Color(0xFFD4A574)),
                                SizedBox(width: 8), Text('Edit', style: TextStyle(fontSize: 12))])),
                            const PopupMenuItem(value: 'hapus', height: 36,
                              child: Row(children: [Icon(Icons.delete, size: 14, color: Color(0xFFC0392B)),
                                SizedBox(width: 8), Text('Hapus', style: TextStyle(fontSize: 12, color: Color(0xFFC0392B)))])),
                          ]),
                      ]))));
                  }))),
          ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _tambahBaru,
        backgroundColor: const Color(0xFF27AE60),
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
    );
  }
}

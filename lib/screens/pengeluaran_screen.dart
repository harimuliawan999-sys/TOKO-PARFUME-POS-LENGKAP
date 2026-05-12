import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class PengeluaranScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const PengeluaranScreen({super.key, required this.toko, required this.user});
  @override State<PengeluaranScreen> createState() => _PengeluaranScreenState();
}

class _PengeluaranScreenState extends State<PengeluaranScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');
  List<Map<String, dynamic>> _list = [];
  bool _showForm = false;
  String _kat = 'Operasional', _ket = '', _jml = '';
  bool _hideKasir = false;
  DateTime _tanggalInput = DateTime.now();
  DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _sampai = DateTime.now();

  bool get isOwner => widget.user['peran'] == 'owner';

  // Kategori yang ditandai sensitif (default auto-hide dari kasir)
  static const _kategoriSensitif = {'Gaji', 'Insentif'};

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final mulai = DateFormat('yyyy-MM-dd').format(_dari);
      final akhir = DateFormat('yyyy-MM-dd').format(_sampai);
      // Kasir cuma lihat yang TIDAK hide; Owner lihat semua
      final l = await Api.getPengeluaran(widget.toko['id'], tanggalMulai: mulai, tanggalAkhir: akhir, onlyVisible: !isOwner);
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal memuat: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _simpan() async {
    if (_ket.isEmpty || _jml.isEmpty) return;
    await Api.addPengeluaran({
      'toko_id': widget.toko['id'], 'kategori': _kat, 'keterangan': _ket,
      'jumlah': double.tryParse(_jml) ?? 0,
      'tanggal': DateFormat('yyyy-MM-dd').format(_tanggalInput),
      'user_id': widget.user['id'],
      'hide_kasir': _hideKasir,
    });
    setState(() {
      _ket = ''; _jml = ''; _showForm = false;
      _tanggalInput = DateTime.now();
      _hideKasir = false;
    });
    _load();
  }

  Future<void> _toggleHide(Map<String, dynamic> p) async {
    if (!isOwner) return;
    final newVal = !((p['hide_kasir'] ?? false) as bool);
    await Api.setPengeluaranHideKasir(p['id'].toString(), newVal);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(newVal ? 'Disembunyikan dari kasir' : 'Ditampilkan ke kasir'),
        backgroundColor: const Color(0xFF27AE60), duration: const Duration(seconds: 2)));
    }
    _load();
  }

  void _onKategoriChanged(String? v) {
    if (v == null) return;
    setState(() {
      _kat = v;
      // Default auto-checked untuk kategori sensitif (Gaji/Insentif)
      _hideKasir = _kategoriSensitif.contains(v);
    });
  }

  Future<void> _pilihTanggal(bool isDari) async {
    final picked = await showDatePicker(context: context,
      initialDate: isDari ? _dari : _sampai,
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) {
      setState(() { if (isDari) { _dari = picked; } else { _sampai = picked; } });
      _load();
    }
  }

  Future<void> _pilihTanggalInput() async {
    final picked = await showDatePicker(context: context,
      initialDate: _tanggalInput,
      firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) setState(() => _tanggalInput = picked);
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
    final total = _list.fold(0.0, (s, p) => s + ((p['jumlah'] ?? 0) as num).toDouble());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengeluaran', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [IconButton(icon: Icon(_showForm ? Icons.close : Icons.add), onPressed: () => setState(() => _showForm = !_showForm))]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        // ═══ FILTER TANGGAL ═══
        Wrap(spacing: 6, children: ['hari', 'bulan', 'tahun', 'semua'].map((p) => ActionChip(
          label: Text({'hari': 'Hari Ini', 'bulan': 'Bulan Ini', 'tahun': 'Tahun Ini', 'semua': 'Semua'}[p]!, style: const TextStyle(fontSize: 10)),
          onPressed: () => _setQuick(p),
          backgroundColor: const Color(0xFFFAF8F5))).toList()),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: GestureDetector(onTap: () => _pilihTanggal(true),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)),
                const SizedBox(width: 6), Text(dateFmt.format(_dari), style: const TextStyle(fontSize: 11))])))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
          Expanded(child: GestureDetector(onTap: () => _pilihTanggal(false),
            child: Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)),
                const SizedBox(width: 6), Text(dateFmt.format(_sampai), style: const TextStyle(fontSize: 11))])))),
        ]),
        const SizedBox(height: 12),

        // ═══ TOTAL ═══
        Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          const Text('TOTAL PERIODE', style: TextStyle(fontSize: 9, color: Color(0xFFA09080), fontWeight: FontWeight.w600)),
          Text(cur.format(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFC0392B))),
          Text('${_list.length} pengeluaran${!isOwner ? " (yang terlihat)" : ""}',
            style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
        ]))),

        // ═══ FORM TAMBAH ═══
        if (_showForm) Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          DropdownButtonFormField<String>(value: _kat,
            decoration: const InputDecoration(labelText: 'Kategori', border: OutlineInputBorder(), isDense: true),
            items: ['Gaji','Insentif','Operasional','Listrik & Air','Pembelian Bahan','Sewa','Lain-lain']
              .map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
            onChanged: _onKategoriChanged),
          const SizedBox(height: 8),
          TextField(onChanged: (v) => _ket = v,
            decoration: const InputDecoration(labelText: 'Keterangan', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 8),
          TextField(onChanged: (v) => _jml = v, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Jumlah (Rp)', border: OutlineInputBorder(), isDense: true)),
          const SizedBox(height: 8),
          GestureDetector(onTap: _pilihTanggalInput,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(4)),
              child: Row(children: [
                const Icon(Icons.calendar_today, size: 16, color: Color(0xFFD4A574)),
                const SizedBox(width: 8),
                Text('Tanggal: ${dateFmt.format(_tanggalInput)}', style: const TextStyle(fontSize: 13)),
                const Spacer(),
                const Icon(Icons.edit, size: 14, color: Color(0xFFA09080)),
              ]))),
          const SizedBox(height: 8),
          // Toggle hide_kasir (hanya untuk owner)
          if (isOwner) Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _hideKasir ? const Color(0xFFFEF3C7) : const Color(0xFFFAF8F5),
              border: Border.all(color: _hideKasir ? const Color(0xFFD97706) : const Color(0xFFE8E0D8)),
              borderRadius: BorderRadius.circular(6)),
            child: SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Row(children: [
                Icon(_hideKasir ? Icons.visibility_off : Icons.visibility,
                  size: 16, color: _hideKasir ? const Color(0xFFD97706) : const Color(0xFF6B5B4B)),
                const SizedBox(width: 8),
                Expanded(child: Text(_hideKasir ? 'Disembunyikan dari Kasir' : 'Terlihat oleh Kasir',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
              ]),
              subtitle: const Text('Switch ON = kasir tidak bisa lihat pengeluaran ini',
                style: TextStyle(fontSize: 9, color: Color(0xFFA09080))),
              value: _hideKasir,
              activeColor: const Color(0xFFD97706),
              onChanged: (v) => setState(() => _hideKasir = v))),
          if (isOwner) const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _simpan, child: const Text('Simpan'))),
        ]))),
        const SizedBox(height: 12),

        // ═══ LIST ═══
        if (_list.isEmpty)
          Padding(padding: const EdgeInsets.all(24),
            child: Center(child: Text('Tidak ada pengeluaran di periode ini',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]))))
        else
          ..._list.map((p) {
            final hide = (p['hide_kasir'] ?? false) as bool;
            return Card(margin: const EdgeInsets.only(bottom: 4),
              color: hide ? const Color(0xFFFEF3C7).withOpacity(0.3) : null,
              child: ListTile(dense: true,
                leading: hide && isOwner
                  ? const Icon(Icons.visibility_off, size: 18, color: Color(0xFFD97706))
                  : null,
                title: Row(children: [
                  Expanded(child: Text('${p['keterangan']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                  if (hide && isOwner) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: const Color(0xFFD97706), borderRadius: BorderRadius.circular(3)),
                    child: const Text('HIDE', style: TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.w700))),
                ]),
                subtitle: Text('${p['kategori']} · ${p['tanggal']}',
                  style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('- ${cur.format(p['jumlah'])}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC0392B))),
                  if (isOwner) PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 16, color: Color(0xFF6B5B4B)),
                    padding: EdgeInsets.zero,
                    onSelected: (v) async {
                      if (v == 'toggle') await _toggleHide(p);
                      else if (v == 'hapus') {
                        await Api.deletePengeluaran(p['id']);
                        _load();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(value: 'toggle', height: 36,
                        child: Row(children: [
                          Icon(hide ? Icons.visibility : Icons.visibility_off,
                            size: 14, color: const Color(0xFFD97706)),
                          const SizedBox(width: 8),
                          Text(hide ? 'Tampilkan ke Kasir' : 'Hide dari Kasir',
                            style: const TextStyle(fontSize: 12)),
                        ])),
                      const PopupMenuItem(value: 'hapus', height: 36,
                        child: Row(children: [
                          Icon(Icons.delete, size: 14, color: Color(0xFFC0392B)),
                          SizedBox(width: 8),
                          Text('Hapus', style: TextStyle(fontSize: 12, color: Color(0xFFC0392B))),
                        ])),
                    ]),
                ])));
          }),
      ]));
  }
}

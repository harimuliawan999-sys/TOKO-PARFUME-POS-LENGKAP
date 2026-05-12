import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class ShiftScreen extends StatefulWidget {
  final Map<String, dynamic> toko, user;
  const ShiftScreen({super.key, required this.toko, required this.user});
  @override State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> with SingleTickerProviderStateMixin {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy, HH:mm', 'id_ID');
  late TabController _tab;
  Map<String, dynamic>? _activeShift;
  List<Map<String, dynamic>> _kasList = [], _history = [], _shiftTrx = [];
  bool _loading = true;
  String get tokoId => widget.toko['id'];

  @override void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final active = await Api.getActiveShift(tokoId, widget.user['id']);
      List<Map<String, dynamic>> kas = [], trx = [];
      if (active != null) {
        kas = await Api.getShiftKas(active['id']);
        // Fetch transaksi selama shift
        final mulai = active['mulai']?.toString() ?? '';
        if (mulai.isNotEmpty) {
          trx = await Api.getTransaksi(tokoId, limit: 500);
          final mulaiDt = DateTime.tryParse(mulai)?.toLocal();
          if (mulaiDt != null) trx = trx.where((t) { final td = DateTime.tryParse(t['created_at']?.toString() ?? '')?.toLocal(); return td != null && td.isAfter(mulaiDt); }).toList();
        }
      }
      final history = await Api.getShiftHistory(tokoId);
      if (mounted) setState(() { _activeShift = active; _kasList = kas; _shiftTrx = trx; _history = history; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  // ═══ START SHIFT ═══
  void _startShift() {
    final ctrl = TextEditingController(text: '0');
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Mulai Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(12)),
          child: const Column(children: [
            Icon(Icons.point_of_sale, size: 40, color: Color(0xFFD4A574)),
            SizedBox(height: 8),
            Text('Kas Awal di Laci', style: TextStyle(fontSize: 12, color: Color(0xFFA09080))),
          ])),
        const SizedBox(height: 16),
        TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(prefixText: 'Rp ', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          final kasAwal = double.tryParse(ctrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          Navigator.pop(context);
          await Api.startShift(tokoId, widget.user['id'], widget.user['nama'], kasAwal);
          _load();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift dimulai!'), backgroundColor: Color(0xFF27AE60)));
        }, child: const Text('Start Shift')),
      ]));
  }

  // ═══ END SHIFT ═══
  void _endShift() {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Akhiri Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Hitung uang kas di laci sekarang:', style: TextStyle(fontSize: 12, color: Color(0xFF6B5B4B))),
        const SizedBox(height: 12),
        TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          decoration: InputDecoration(prefixText: 'Rp ', labelText: 'Kas Aktual', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          final kasAktual = double.tryParse(ctrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          Navigator.pop(context);
          await Api.endShift(_activeShift!['id'], kasAktual);
          _load();
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shift berakhir!'), backgroundColor: Color(0xFFD4A574)));
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B)), child: const Text('Shift Berakhir')),
      ]));
  }

  // ═══ KAS MASUK/KELUAR ═══
  void _addKas(String tipe) {
    final jmlCtrl = TextEditingController();
    final ketCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(tipe == 'masuk' ? 'Kas Masuk (+)' : 'Kas Keluar (-)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: jmlCtrl, keyboardType: TextInputType.number,
          decoration: InputDecoration(prefixText: 'Rp ', labelText: 'Jumlah', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
        const SizedBox(height: 10),
        TextField(controller: ketCtrl,
          decoration: InputDecoration(labelText: 'Keterangan (contoh: tisu, sampah)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          final jml = double.tryParse(jmlCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
          if (jml <= 0) return;
          Navigator.pop(context);
          await Api.addShiftKas(_activeShift!['id'], tokoId, tipe, jml, ketCtrl.text, widget.user['id']);
          _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: tipe == 'masuk' ? const Color(0xFF27AE60) : const Color(0xFFC0392B)),
          child: Text(tipe == 'masuk' ? 'Tambah' : 'Kurangi')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Shift', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        bottom: TabBar(controller: _tab, indicatorColor: const Color(0xFFD4A574), labelColor: const Color(0xFFD4A574), unselectedLabelColor: const Color(0xFF8B7355),
          tabs: const [Tab(text: 'Saat Ini'), Tab(text: 'Riwayat')])),
      body: _loading ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
        : TabBarView(controller: _tab, children: [_currentTab(), _historyTab()]),
    );
  }

  // ═══ TAB SAAT INI ═══
  Widget _currentTab() {
    if (_activeShift == null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.point_of_sale, size: 60, color: Color(0xFFD4A574)),
        const SizedBox(height: 16),
        const Text('Belum ada shift aktif', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text('Mulai shift untuk mencatat kas', style: TextStyle(fontSize: 12, color: Color(0xFFA09080))),
        const SizedBox(height: 24),
        ElevatedButton.icon(onPressed: _startShift, icon: const Icon(Icons.play_arrow), label: const Text('Start Shift'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14))),
      ]));
    }

    final s = _activeShift!;
    final mulai = DateTime.tryParse(s['mulai']?.toString() ?? '')?.toLocal();
    final kasAwal = ((s['kas_awal'] ?? 0) as num).toDouble();

    // Hitung realtime
    double totalMasuk = 0, totalKeluar = 0;
    for (final k in _kasList) {
      if (k['tipe'] == 'masuk') {
        totalMasuk += ((k['jumlah'] ?? 0) as num).toDouble();
      } else {
        totalKeluar += ((k['jumlah'] ?? 0) as num).toDouble();
      }
    }
    // Penjualan per metode
    double kasCash = 0, kasQris = 0, kasTransfer = 0;
    for (final t in _shiftTrx) {
      final tot = ((t['total'] ?? 0) as num).toDouble();
      final m = (t['metode'] ?? 'Cash').toString();
      if (m == 'Cash') {
        kasCash += tot;
      } else if (m == 'QRIS') {
        kasQris += tot;
      } else {
        kasTransfer += tot;
      }
    }

    return RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
      // Shift info
      Card(child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: [const Color(0xFF27AE60).withOpacity(0.1), const Color(0xFF27AE60).withOpacity(0.03)])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF27AE60), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.access_time, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Shift: ${s['user_nama'] ?? '-'}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('Mulai: ${mulai != null ? dateFmt.format(mulai) : '-'}', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
            ])),
          ]),
        ]))),
      const SizedBox(height: 12),

      // Kas summary detail
      Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        _shiftRow('Awal di Laci', kasAwal, Colors.black87),
        const Divider(height: 16),
        _shiftRow('Kas Penjualan (Cash)', kasCash, const Color(0xFF27AE60)),
        _shiftRow('QRIS', kasQris, const Color(0xFF2980B9)),
        _shiftRow('Transfer', kasTransfer, const Color(0xFFD4A574)),
        const Divider(height: 12),
        _shiftRow('Kas Masuk (+)', totalMasuk, const Color(0xFF27AE60)),
        _shiftRow('Kas Keluar (-)', -totalKeluar, const Color(0xFFC0392B)),
        const Divider(height: 16),
        _shiftRow('Total di Laci (Cash)', kasAwal + kasCash + totalMasuk - totalKeluar, const Color(0xFFD4A574), bold: true),
        _shiftRow('Total Penjualan', kasCash + kasQris + kasTransfer, const Color(0xFF27AE60), bold: true),
      ]))),
      const SizedBox(height: 12),

      // Action buttons
      Row(children: [
        Expanded(child: ElevatedButton.icon(
          onPressed: () => _addKas('masuk'),
          icon: const Icon(Icons.add_circle, size: 18),
          label: const Text('Kas Masuk'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 12)))),
        const SizedBox(width: 10),
        Expanded(child: ElevatedButton.icon(
          onPressed: () => _addKas('keluar'),
          icon: const Icon(Icons.remove_circle, size: 18),
          label: const Text('Kas Keluar'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B), padding: const EdgeInsets.symmetric(vertical: 12)))),
      ]),
      const SizedBox(height: 16),

      // Kas masuk/keluar list
      if (_kasList.isNotEmpty) ...[
        const Text('Kas Masuk-Keluar', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        ..._kasList.map((k) {
          final isMasuk = k['tipe'] == 'masuk';
          final tgl = DateTime.tryParse(k['created_at']?.toString() ?? '')?.toLocal();
          return Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
            leading: Icon(isMasuk ? Icons.arrow_downward : Icons.arrow_upward, color: isMasuk ? const Color(0xFF27AE60) : const Color(0xFFC0392B), size: 18),
            title: Text(k['keterangan'] ?? '-', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            subtitle: Text(tgl != null ? dateFmt.format(tgl) : '-', style: const TextStyle(fontSize: 9, color: Color(0xFFA09080))),
            trailing: Text('${isMasuk ? '+' : '-'}${cur.format(k['jumlah'] ?? 0)}',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isMasuk ? const Color(0xFF27AE60) : const Color(0xFFC0392B)))));
        }),
      ],

      const SizedBox(height: 24),
      // End Shift
      SizedBox(width: double.infinity, child: ElevatedButton.icon(
        onPressed: _endShift, icon: const Icon(Icons.stop_circle, size: 20), label: const Text('Shift Berakhir'),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFC0392B), padding: const EdgeInsets.symmetric(vertical: 14), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)))),
      const SizedBox(height: 20),
    ]));
  }

  Widget _shiftRow(String label, double value, Color color, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 12, color: const Color(0xFF6B5B4B), fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      Text(cur.format(value.abs()), style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w600, color: color)),
    ]));

  // ═══ TAB RIWAYAT ═══
  Widget _historyTab() {
    final completed = _history.where((s) => s['status'] == 'selesai').toList();
    if (completed.isEmpty) return const Center(child: Text('Belum ada riwayat shift', style: TextStyle(color: Color(0xFFA09080))));

    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: completed.length, itemBuilder: (_, i) {
      final s = completed[i];
      final mulai = DateTime.tryParse(s['mulai']?.toString() ?? '')?.toLocal();
      final selesai = DateTime.tryParse(s['selesai']?.toString() ?? '')?.toLocal();
      final kasAwal = ((s['kas_awal'] ?? 0) as num).toDouble();
      final kasPenjualan = ((s['kas_penjualan'] ?? 0) as num).toDouble();
      final kasPembatalan = ((s['kas_pembatalan'] ?? 0) as num).toDouble();
      final kasMasukKeluar = ((s['kas_masuk_keluar'] ?? 0) as num).toDouble();
      final totalDiharapkan = ((s['total_diharapkan'] ?? 0) as num).toDouble();
      final kasAktual = ((s['kas_aktual'] ?? 0) as num).toDouble();
      final selisih = ((s['selisih'] ?? 0) as num).toDouble();

      return Card(margin: const EdgeInsets.only(bottom: 10), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(s['user_nama'] ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: const Color(0xFFA09080).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Text('Selesai', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFFA09080)))),
        ]),
        Text('${mulai != null ? dateFmt.format(mulai) : '-'} s/d ${selesai != null ? dateFmt.format(selesai) : '-'}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
        const Divider(height: 16),
        _shiftRow('Awal di Laci', kasAwal, Colors.black87),
        _shiftRow('Kas Penjualan', kasPenjualan, const Color(0xFF27AE60)),
        _shiftRow('Kas Pembatalan', kasPembatalan, const Color(0xFFC0392B)),
        _shiftRow('Kas Masuk-Keluar', kasMasukKeluar, kasMasukKeluar >= 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B)),
        const Divider(height: 12),
        _shiftRow('Total Diharapkan', totalDiharapkan, const Color(0xFFD4A574), bold: true),
        _shiftRow('Kas Aktual', kasAktual, const Color(0xFF2980B9), bold: true),
        if (selisih != 0) _shiftRow('Selisih', selisih, selisih >= 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B), bold: true),
      ])));
    });
  }
}

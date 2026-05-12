import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

class LaporanCabangScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const LaporanCabangScreen({super.key, required this.toko});
  @override State<LaporanCabangScreen> createState() => _LaporanCabangScreenState();
}

class _LaporanCabangScreenState extends State<LaporanCabangScreen> {
  final cur = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final dateFmt = DateFormat('dd MMM yyyy', 'id_ID');

  DateTime _dari = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _sampai = DateTime.now();

  List<Map<String, dynamic>> _tokoList = [];
  Map<String, Map<String, dynamic>> _laporan = {};
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final tokoList = await Api.getAllToko();
      final mulai = DateFormat('yyyy-MM-dd').format(_dari);
      final akhir = DateFormat('yyyy-MM-dd').format(_sampai);

      Map<String, Map<String, dynamic>> laporan = {};
      for (final toko in tokoList) {
        laporan[toko['id']] = await Api.getLaporanCabang(toko['id'], mulai, akhir);
      }

      if (mounted) setState(() { _tokoList = tokoList; _laporan = laporan; _loading = false; });
    } catch (e) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _pilihTanggal(bool isDari) async {
    final picked = await showDatePicker(context: context, initialDate: isDari ? _dari : _sampai, firstDate: DateTime(2024), lastDate: DateTime.now(),
      builder: (c, w) => Theme(data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFD4A574))), child: w!));
    if (picked != null) { setState(() { if (isDari) {
      _dari = picked;
    } else {
      _sampai = picked;
    } }); _load(); }
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
    // Hitung total semua cabang
    double totalPendapatan = 0, totalPengeluaran = 0, totalLaba = 0;
    int totalTrx = 0;
    for (final l in _laporan.values) {
      totalPendapatan += (l['pendapatan'] as num? ?? 0).toDouble();
      totalPengeluaran += (l['pengeluaran'] as num? ?? 0).toDouble();
      totalLaba += (l['laba'] as num? ?? 0).toDouble();
      totalTrx += (l['transaksi'] as num? ?? 0).toInt();
    }

    final gradients = [
      [const Color(0xFFD4A574), const Color(0xFFB8860B)],
      [const Color(0xFF2980B9), const Color(0xFF1A5276)],
      [const Color(0xFF27AE60), const Color(0xFF1E8449)],
      [const Color(0xFF8E44AD), const Color(0xFF6C3483)],
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Laporan Semua Cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A574)))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: [
            // Quick filter
            Wrap(spacing: 6, children: ['hari', 'bulan', 'tahun', 'semua'].map((p) => ActionChip(
              label: Text({'hari': 'Hari Ini', 'bulan': 'Bulan Ini', 'tahun': 'Tahun Ini', 'semua': 'Semua'}[p]!, style: const TextStyle(fontSize: 10)),
              onPressed: () => _setQuick(p), backgroundColor: const Color(0xFFFAF8F5))).toList()),
            const SizedBox(height: 10),

            // Date picker
            Row(children: [
              Expanded(child: GestureDetector(onTap: () => _pilihTanggal(true),
                child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_dari), style: const TextStyle(fontSize: 11))])))),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-', style: TextStyle(color: Color(0xFFA09080)))),
              Expanded(child: GestureDetector(onTap: () => _pilihTanggal(false),
                child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE8E0D8)), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [const Icon(Icons.calendar_today, size: 14, color: Color(0xFFD4A574)), const SizedBox(width: 6), Text(dateFmt.format(_sampai), style: const TextStyle(fontSize: 11))])))),
            ]),
            const SizedBox(height: 20),

            // ═══ TOTAL SEMUA CABANG ═══
            Card(child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(colors: [const Color(0xFFD4A574).withOpacity(0.1), const Color(0xFFD4A574).withOpacity(0.03)])),
              child: Column(children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFD4A574), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.store, color: Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('TOTAL SEMUA CABANG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1, color: Color(0xFFA09080))),
                    Text('${_tokoList.length} cabang', style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B))),
                  ]),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  _totalBox('Pendapatan', totalPendapatan, const Color(0xFF27AE60)),
                  _totalBox('Pengeluaran', totalPengeluaran, const Color(0xFFC0392B)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _totalBox('Laba Bersih', totalLaba, totalLaba >= 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B)),
                  _totalBox('Transaksi', totalTrx.toDouble(), const Color(0xFF2980B9), suffix: ' nota'),
                ]),
              ]))),
            const SizedBox(height: 20),

            // ═══ PER CABANG ═══
            const Text('Detail Per Cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),

            ..._tokoList.asMap().entries.map((entry) {
              final i = entry.key;
              final toko = entry.value;
              final l = _laporan[toko['id']] ?? {};
              final pend = (l['pendapatan'] as num? ?? 0).toDouble();
              final peng = (l['pengeluaran'] as num? ?? 0).toDouble();
              final laba = (l['laba'] as num? ?? 0).toDouble();
              final trx = (l['transaksi'] as num? ?? 0).toInt();
              final grad = gradients[i % gradients.length];
              final isMyCabang = toko['id'] == widget.toko['id'];

              return Card(margin: const EdgeInsets.only(bottom: 12), child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(colors: [grad[0].withOpacity(0.08), grad[1].withOpacity(0.02)])),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 36, height: 36,
                      decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(10)),
                      child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(toko['nama'] ?? '-', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: grad[0])),
                        if (isMyCabang) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(color: grad[0], borderRadius: BorderRadius.circular(8)),
                          child: const Text('Anda', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w600))),
                      ]),
                      Text(toko['alamat'] ?? '-', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
                    ])),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _cabangBox('Pendapatan', pend, const Color(0xFF27AE60)),
                    _cabangBox('Pengeluaran', peng, const Color(0xFFC0392B)),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    _cabangBox('Laba', laba, laba >= 0 ? const Color(0xFF27AE60) : const Color(0xFFC0392B)),
                    _cabangBox('Transaksi', trx.toDouble(), const Color(0xFF2980B9), suffix: ' nota'),
                  ]),
                ])));
            }),

            const SizedBox(height: 20),
          ])),
    );
  }

  Widget _totalBox(String lb, double v, Color c, {String suffix = ''}) => Expanded(child: Container(
    margin: const EdgeInsets.all(3), padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
    child: Column(children: [Text(lb, style: const TextStyle(fontSize: 9, color: Color(0xFFA09080), fontWeight: FontWeight.w600)),
      Text(suffix.isNotEmpty ? '${v.round()}$suffix' : cur.format(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c), overflow: TextOverflow.ellipsis)])));

  Widget _cabangBox(String lb, double v, Color c, {String suffix = ''}) => Expanded(child: Container(
    margin: const EdgeInsets.all(2), padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(6)),
    child: Column(children: [Text(lb, style: const TextStyle(fontSize: 8, color: Color(0xFFA09080), fontWeight: FontWeight.w600)),
      Text(suffix.isNotEmpty ? '${v.round()}$suffix' : cur.format(v), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c), overflow: TextOverflow.ellipsis)])));
}

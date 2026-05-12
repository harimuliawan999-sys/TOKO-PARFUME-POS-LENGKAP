import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/api.dart';
import '../services/bluetooth_printer_service.dart';
import '../widgets/dev_contact.dart';
import 'panduan_screen.dart';
import 'bluetooth_printer_screen.dart';

class SettingsScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const SettingsScreen({super.key, required this.toko});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<Map<String, dynamic>> _users = [];
  String? _qrisPath;
  String? _btPrinterName;

  @override void initState() { super.initState(); _load(); _loadQris(); _loadBtPrinter(); }

  Future<void> _loadBtPrinter() async {
    final name = await BluetoothPrinterService().getSavedName();
    if (mounted) setState(() => _btPrinterName = name);
  }
  Future<void> _load() async { try { final u = await Api.getUsers(widget.toko['id']); if (mounted) setState(() => _users = u); } catch(_) {} }
  Future<void> _loadQris() async { final p = await Api.getQrisPath(); if (mounted) setState(() => _qrisPath = p); }

  void _tambahUser() {
    String nama = '', pin = '', peran = 'kasir';
    showDialog(context: context, builder: (_) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: const Text('Tambah User', style: TextStyle(fontSize: 14)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(onChanged: (v) => nama = v, decoration: const InputDecoration(labelText: 'Nama', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(onChanged: (v) => pin = v, maxLength: 4, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'PIN (4 digit)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(value: peran, decoration: const InputDecoration(labelText: 'Peran', border: OutlineInputBorder(), isDense: true),
          items: ['kasir', 'owner'].map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(), onChanged: (v) => setD(() => peran = v!)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          if (nama.isEmpty || pin.length != 4) return;
          await Api.addUser(widget.toko['id'], nama, pin, peran);
          if (!mounted) return;
          Navigator.pop(context); _load();
        }, child: const Text('Simpan'))])));
  }

  void _gantiPin(Map<String, dynamic> user) {
    final oldCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confCtrl = TextEditingController();
    showDialog(context: context, builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Ganti PIN ${user['nama']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: oldCtrl, maxLength: 4, keyboardType: TextInputType.number, obscureText: true,
          decoration: const InputDecoration(labelText: 'PIN Lama', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: newCtrl, maxLength: 4, keyboardType: TextInputType.number, obscureText: true,
          decoration: const InputDecoration(labelText: 'PIN Baru (4 digit)', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: confCtrl, maxLength: 4, keyboardType: TextInputType.number, obscureText: true,
          decoration: const InputDecoration(labelText: 'Konfirmasi PIN Baru', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          if (oldCtrl.text != user['pin'].toString()) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN lama salah!'), backgroundColor: Colors.red));
            return;
          }
          if (newCtrl.text.length != 4) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN baru harus 4 digit!'), backgroundColor: Colors.red));
            return;
          }
          if (newCtrl.text != confCtrl.text) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Konfirmasi PIN tidak cocok!'), backgroundColor: Colors.red));
            return;
          }
          try {
            await Api.updateUserPin(user['id'], newCtrl.text);
            if (!mounted) return;
            Navigator.pop(context); _load();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN berhasil diganti!'), backgroundColor: Color(0xFF27AE60)));
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
          }
        }, child: const Text('Simpan')),
      ]));
  }

  Future<void> _uploadQris() async {
    // withData:true wajib di Android (scoped storage — path bisa null)
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.first;
    final dir = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/qris_ks_parfume.jpg');
    if (picked.bytes != null) {
      await dest.writeAsBytes(picked.bytes!);
    } else if (picked.path != null) {
      await File(picked.path!).copy(dest.path);
    }
    await Api.saveQrisPath(dest.path);
    if (mounted) { setState(() => _qrisPath = dest.path);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QRIS berhasil di-upload!'), backgroundColor: Color(0xFF27AE60))); }
  }

  void _editNamaCabang() {
    String nama = widget.toko['nama'] ?? '';
    String alamat = widget.toko['alamat'] ?? '';
    showDialog(context: context, builder: (_) => AlertDialog(
      title: const Text('Edit Nama Cabang', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(initialValue: nama, onChanged: (v) => nama = v,
          decoration: const InputDecoration(labelText: 'Nama Cabang', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 8),
        TextFormField(initialValue: alamat, onChanged: (v) => alamat = v,
          decoration: const InputDecoration(labelText: 'Alamat', border: OutlineInputBorder(), isDense: true)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        ElevatedButton(onPressed: () async {
          if (nama.isEmpty) return;
          await Api.updateTokoNama(widget.toko['id'], nama, alamat: alamat);
          if (!mounted) return;
          widget.toko['nama'] = nama;
          widget.toko['alamat'] = alamat;
          Navigator.pop(context);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nama cabang diperbarui!'), backgroundColor: Color(0xFF27AE60)));
        }, child: const Text('Simpan')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Pengaturan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ═══ PANDUAN ═══
        GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PanduanScreen())),
          child: Card(child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), gradient: LinearGradient(colors: [const Color(0xFFD4A574).withOpacity(0.1), const Color(0xFFD4A574).withOpacity(0.03)])),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: const Color(0xFFD4A574), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.menu_book, color: Colors.white, size: 22)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Panduan Penggunaan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFD4A574))),
                Text('Cara menggunakan semua fitur app', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
              ])),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFD4A574)),
            ])))),
        const SizedBox(height: 16),

        // ═══ NAMA CABANG ═══
        const Text('Nama Cabang', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF2980B9), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.store, color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.toko['nama'] ?? '-', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text(widget.toko['alamat'] ?? '-', style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
          ])),
          IconButton(icon: const Icon(Icons.edit, size: 18, color: Color(0xFFD4A574)), onPressed: _editNamaCabang),
        ]))),
        const SizedBox(height: 16),

        // ═══ PRINTER BLUETOOTH ═══
        const Text('Printer Bluetooth', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const BluetoothPrinterScreen()));
            _loadBtPrinter(); // refresh nama printer setelah kembali
          },
          child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
            Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF2980B9), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.bluetooth, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_btPrinterName != null && _btPrinterName!.isNotEmpty ? _btPrinterName! : 'Belum ada printer',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text(_btPrinterName != null && _btPrinterName!.isNotEmpty ? 'Tekan untuk kelola atau test print' : 'Tekan untuk setup printer thermal 58mm',
                style: const TextStyle(fontSize: 11, color: Color(0xFFA09080))),
            ])),
            Icon(Icons.arrow_forward_ios, size: 16, color: _btPrinterName != null && _btPrinterName!.isNotEmpty ? const Color(0xFF2980B9) : const Color(0xFFA09080)),
          ])))),
        const SizedBox(height: 16),

        // ═══ QRIS ═══
        const Text('QRIS Pembayaran', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          if (_qrisPath != null && File(_qrisPath!).existsSync()) ...[
            ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(File(_qrisPath!), height: 180, fit: BoxFit.contain)),
            const SizedBox(height: 8),
            const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle, size: 14, color: Color(0xFF27AE60)),
              SizedBox(width: 4),
              Text('QRIS aktif — akan muncul saat bayar', style: TextStyle(fontSize: 10, color: Color(0xFF27AE60))),
            ]),
          ] else ...[
            Container(height: 100, decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(10)),
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.qr_code_2, size: 36, color: Color(0xFFA09080)),
                Text('Belum ada QRIS', style: TextStyle(fontSize: 11, color: Color(0xFFA09080)))]))),
          ],
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _uploadQris,
            icon: const Icon(Icons.upload, size: 18),
            label: Text(_qrisPath != null ? 'Ganti Gambar QRIS' : 'Upload Gambar QRIS'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574))))),
          const SizedBox(height: 6),
          const Text('Upload foto QRIS dari bank/e-wallet (BCA, BRI, Dana, OVO, dll)', style: TextStyle(fontSize: 9, color: Color(0xFFA09080))),
        ]))),

        // ═══ USERS ═══
        const SizedBox(height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Kelola Pengguna', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          IconButton(icon: const Icon(Icons.add_circle, color: Color(0xFFD4A574)), onPressed: _tambahUser)]),
        const SizedBox(height: 8),
        ..._users.map((u) => Card(margin: const EdgeInsets.only(bottom: 4), child: ListTile(dense: true,
          leading: CircleAvatar(radius: 16, backgroundColor: u['peran'] == 'owner' ? const Color(0xFFD4A574) : const Color(0xFF2980B9),
            child: Text('${u['nama']}'[0], style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
          title: Text('${u['nama']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('PIN: ${'*' * (u['pin']?.toString().length ?? 4)} · ${u['peran']}', style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.key, size: 16, color: Color(0xFF2980B9)), onPressed: () => _gantiPin(u), tooltip: 'Ganti PIN'),
            if (u['peran'] != 'owner') IconButton(icon: const Icon(Icons.delete, size: 16, color: Colors.red), onPressed: () async { await Api.deleteUser(u['id']); _load(); }),
          ])))),

        // ═══ SYSTEM INFO ═══
        const SizedBox(height: 24),
        const Text('Informasi Sistem', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          for (final item in [['Aplikasi', 'KS Parfume v3.6'], ['Mode', 'Smart POS Multi-Cabang'], ['Database', 'Supabase Cloud'], ['Cabang', widget.toko['nama'] ?? '-']])
            Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(item[0], style: const TextStyle(fontSize: 12, color: Color(0xFFA09080))),
              Text(item[1], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))])),
        ]))),

        // ═══ DANGER ZONE ═══
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.4)),
            color: Colors.red.withOpacity(0.04)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
              SizedBox(width: 8),
              Text('Danger Zone', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.red)),
            ]),
            const SizedBox(height: 4),
            const Text('Tindakan di bawah tidak dapat dibatalkan', style: TextStyle(fontSize: 10, color: Color(0xFFA09080))),
            const SizedBox(height: 12),
            _dangerBtn(Icons.restart_alt, 'Reset Semua Resep', 'Hapus resep_bibit & botol di semua varian', const Color(0xFFE67E22), _resetResep),
            const SizedBox(height: 8),
            _dangerBtn(Icons.delete_forever, 'Hapus Semua Produk & Varian', 'Hapus semua data produk cabang ini', Colors.red, _hapusProduk),
            const SizedBox(height: 8),
            _dangerBtn(Icons.delete_sweep, 'RESET SEMUA DATA', 'Hapus produk, transaksi, pengeluaran cabang ini', const Color(0xFF8B0000), _resetSemuaData),
          ])),

        const SizedBox(height: 24),
        const DevContact(compact: false),
        const SizedBox(height: 16),
      ]));
  }

  Widget _dangerBtn(IconData ic, String title, String sub, Color c, VoidCallback fn) =>
    GestureDetector(onTap: fn, child: Container(padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withOpacity(0.07), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withOpacity(0.3))),
      child: Row(children: [
        Icon(ic, color: c, size: 18),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c)),
          Text(sub, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
        ])),
        Icon(Icons.chevron_right, color: c, size: 18),
      ])));

  Future<void> _resetResep() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Reset Semua Resep?', style: TextStyle(fontSize: 14, color: Color(0xFFE67E22), fontWeight: FontWeight.w700)),
      content: const Text('resep_bibit dan resep_botol semua varian akan di-reset ke 0/null.\nLakukan ini sebelum import resep baru dari Olsera.', style: TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE67E22)), child: const Text('Reset')),
      ]));
    if (ok != true) return;
    try {
      await Api.resetSemuaResep(widget.toko['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua resep di-reset'), backgroundColor: Color(0xFFE67E22)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _hapusProduk() async {
    final step1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Hapus Semua Produk?', style: TextStyle(fontSize: 14, color: Colors.red, fontWeight: FontWeight.w700)),
      content: const Text('Semua produk & varian cabang ini akan dihapus permanen.\nTidak dapat dibatalkan!', style: TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Lanjut')),
      ]));
    if (step1 != true) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: const Text('Ketik HAPUS untuk konfirmasi', style: TextStyle(fontSize: 13, color: Colors.red)),
      content: TextField(controller: ctrl, onChanged: (_) => setD(() {}),
        decoration: const InputDecoration(hintText: 'HAPUS', border: OutlineInputBorder(), isDense: true),
        style: const TextStyle(fontSize: 13, letterSpacing: 2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: ctrl.text == 'HAPUS' ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Hapus Semua')),
      ])));
    if (ok != true) return;
    try {
      await Api.hapusSemuaProduk(widget.toko['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua produk & varian telah dihapus'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _resetSemuaData() async {
    final step1 = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('RESET SEMUA DATA?', style: TextStyle(fontSize: 14, color: Color(0xFF8B0000), fontWeight: FontWeight.w700)),
      content: const Text('Ini akan menghapus SEMUA:\n• Produk & Varian\n• Transaksi\n• Pengeluaran\n\nCabang ini akan menjadi kosong total.\nTidak dapat dibatalkan!', style: TextStyle(fontSize: 12)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B0000)), child: const Text('Lanjut')),
      ]));
    if (step1 != true) return;
    if (!mounted) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (_) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      title: const Text('Ketik RESET untuk konfirmasi', style: TextStyle(fontSize: 13, color: Color(0xFF8B0000))),
      content: TextField(controller: ctrl, onChanged: (_) => setD(() {}),
        decoration: const InputDecoration(hintText: 'RESET', border: OutlineInputBorder(), isDense: true),
        style: const TextStyle(fontSize: 13, letterSpacing: 2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
        ElevatedButton(onPressed: ctrl.text == 'RESET' ? () => Navigator.pop(context, true) : null,
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B0000)), child: const Text('RESET')),
      ])));
    if (ok != true) return;
    try {
      await Api.resetSemuaData(widget.toko['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua data telah di-reset'), backgroundColor: Color(0xFF8B0000), duration: Duration(seconds: 4)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: $e'), backgroundColor: Colors.red));
      }
    }
  }
}

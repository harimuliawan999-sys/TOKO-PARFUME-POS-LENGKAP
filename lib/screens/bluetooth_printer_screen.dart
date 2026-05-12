import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import '../services/bluetooth_printer_service.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  const BluetoothPrinterScreen({super.key});
  @override State<BluetoothPrinterScreen> createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  final _svc = BluetoothPrinterService();
  List<BluetoothInfo> _devices = [];
  BluetoothInfo? _saved;
  bool _connected = false;
  bool _loading    = false;
  String? _status;
  bool _permGranted = false;

  @override void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    setState(() { _loading = true; _status = null; });

    // Request Bluetooth permissions (Android 12+)
    final granted = await _requestPermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() { _loading = false; _permGranted = false; _status = 'Izin Bluetooth ditolak. Mohon aktifkan di Pengaturan Aplikasi.'; });
      return;
    }
    setState(() => _permGranted = true);

    final saved   = await _svc.loadSavedDevice();
    final devices = await _svc.getBondedDevices();
    final conn    = await _svc.isConnected();
    if (mounted) setState(() { _saved = saved; _devices = devices; _connected = conn; _loading = false; });
  }

  Future<bool> _requestPermissions() async {
    // Android 12+ needs BLUETOOTH_CONNECT + BLUETOOTH_SCAN
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    return !denied;
  }

  Future<void> _selectAndConnect(BluetoothInfo d) async {
    setState(() { _loading = true; _status = null; });
    // Disconnect old connection first
    await _svc.disconnect();
    await _svc.saveDevice(d);
    final ok   = await _svc.connect();
    final conn = await _svc.isConnected();
    if (mounted) {
      setState(() {
      _loading = false;
      _saved   = d;
      _connected = conn;
      _status = ok ? 'Terhubung ke ${d.name}' : 'Gagal terhubung ke ${d.name}.\nPastikan printer menyala.';
    });
    }
  }

  Future<void> _reconnect() async {
    if (_saved == null) return;
    setState(() { _loading = true; _status = null; });
    await _svc.disconnect();
    final ok   = await _svc.connect();
    final conn = await _svc.isConnected();
    if (mounted) {
      setState(() {
      _loading   = false;
      _connected = conn;
      _status    = ok ? 'Terhubung kembali ke ${_saved!.name}' : 'Gagal reconnect. Coba lagi.';
    });
    }
  }

  Future<void> _testPrint() async {
    setState(() { _loading = true; _status = null; });
    final now = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    final err = await _svc.printStruk(
      nota: 'TEST-001',
      tokoNama: 'KS PARFUME',
      tokoAlamat: 'Test Print Bluetooth',
      items: [
        {'nama': 'Parfum Rose Gold 30ml', 'qty': 2, 'hj': 55000.0},
        {'nama': 'Parfum Oud 10ml',       'qty': 1, 'hj': 35000.0},
      ],
      total: 145000,
      bayar: 150000,
      kembalian: 5000,
      metode: 'Cash',
      jam: now,
      kasir: 'Admin',
    );
    if (mounted) {
      setState(() {
      _loading = false;
      _status  = err ?? 'Test print berhasil!';
    });
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printer Bluetooth', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _init, tooltip: 'Refresh')]),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Status Card ───────────────────────────────────────────────
        _buildStatusCard(),
        const SizedBox(height: 12),

        // ── Tombol aksi ───────────────────────────────────────────────
        if (_permGranted && _saved != null && !_connected)
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: _loading ? null : _reconnect,
            icon: const Icon(Icons.bluetooth_searching, size: 18),
            label: const Text('Reconnect Printer'),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD4A574), side: const BorderSide(color: Color(0xFFD4A574))))),
        if (_permGranted && _connected) ...[
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _loading ? null : _testPrint,
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Test Print Struk', style: TextStyle(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF27AE60), padding: const EdgeInsets.symmetric(vertical: 12)))),
        ],
        if (!_permGranted)
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: () => openAppSettings(),
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Buka Pengaturan Izin'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange))),
        const SizedBox(height: 20),

        // ── Daftar bonded devices ─────────────────────────────────────
        if (_permGranted) ...[
          const Text('Perangkat Bluetooth (Sudah Di-Pair)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Hanya menampilkan perangkat yang sudah di-pair. Pair dulu di Pengaturan Bluetooth HP.', style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
          const SizedBox(height: 10),
          if (_devices.isEmpty && !_loading)
            _buildEmptyDevices()
          else
            ..._devices.map((d) => _buildDeviceTile(d)),
          const SizedBox(height: 24),
        ],

        // ── Panduan ───────────────────────────────────────────────────
        _buildPanduan(),
        const SizedBox(height: 24),
      ]),
    );
  }

  Widget _buildStatusCard() {
    final hasDevice = _saved != null;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(
            color: _connected ? const Color(0xFF27AE60).withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.bluetooth, color: _connected ? const Color(0xFF27AE60) : const Color(0xFFA09080), size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hasDevice ? (_saved!.name.isEmpty ? 'Printer' : _saved!.name) : 'Belum ada printer dipilih',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            if (hasDevice) Text(_saved!.macAdress, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _connected ? const Color(0xFF27AE60).withOpacity(0.1) : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
            child: Text(_connected ? 'Terhubung' : 'Terputus',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: _connected ? const Color(0xFF27AE60) : Colors.grey))),
        ]),
        if (_loading) ...[const SizedBox(height: 10), const LinearProgressIndicator()],
        if (_status != null) ...[
          const SizedBox(height: 8),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(
            color: (_status!.contains('berhasil') || _status!.contains('Terhubung'))
              ? const Color(0xFF27AE60).withOpacity(0.08)
              : Colors.red.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8)),
            child: Text(_status!, style: TextStyle(fontSize: 11,
              color: (_status!.contains('berhasil') || _status!.contains('Terhubung'))
                ? const Color(0xFF27AE60) : Colors.red))),
        ],
      ])));
  }

  Widget _buildDeviceTile(BluetoothInfo d) {
    final isSelected = _saved?.macAdress == d.macAdress;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: isSelected ? const Color(0xFFD4A574) : Colors.transparent, width: 2)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFD4A574) : const Color(0xFFF5F0EC),
          borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.print, size: 20, color: isSelected ? Colors.white : const Color(0xFFA09080))),
        title: Text(d.name.isEmpty ? 'Unknown Device' : d.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(d.macAdress, style: const TextStyle(fontSize: 10, color: Color(0xFFA09080))),
        trailing: isSelected && _connected
          ? const Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 22)
          : OutlinedButton(
            onPressed: _loading ? null : () => _selectAndConnect(d),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD4A574),
              side: const BorderSide(color: Color(0xFFD4A574)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
            child: Text(isSelected ? 'Reconnect' : 'Pilih', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
      ));
  }

  Widget _buildEmptyDevices() {
    return const Card(child: Padding(padding: EdgeInsets.all(24), child: Column(children: [
      Icon(Icons.bluetooth_disabled, size: 44, color: Color(0xFFA09080)),
      SizedBox(height: 10),
      Text('Tidak ada perangkat Bluetooth', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      SizedBox(height: 6),
      Text('Pair printer RPP02N terlebih dahulu melalui Pengaturan Bluetooth di HP, kemudian tekan ikon refresh di atas.',
        textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Color(0xFFA09080))),
    ])));
  }

  Widget _buildPanduan() {
    return Card(color: const Color(0xFFFAF8F5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xFFD4A574)),
          SizedBox(width: 8),
          Text('Cara Pairing Printer RPP02N', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6B5B4B))),
        ]),
        const SizedBox(height: 10),
        for (final step in [
          '1. Nyalakan printer RPP02N (tahan tombol power ±3 detik)',
          '2. Buka Pengaturan → Bluetooth di HP Android',
          '3. Scan dan pair perangkat bernama "RPP02N" atau "BT Printer"',
          '4. Kembali ke layar ini, tekan Refresh (ikon atas kanan)',
          '5. Pilih printer dari daftar lalu tekan "Pilih"',
          '6. Tekan "Test Print Struk" untuk memastikan koneksi',
        ]) Padding(padding: const EdgeInsets.only(bottom: 5),
          child: Text(step, style: const TextStyle(fontSize: 11, color: Color(0xFF6B5B4B)))),
        const SizedBox(height: 6),
        const Divider(),
        const Text('Catatan: Printer harus terhubung via Bluetooth Classic (SPP), bukan BLE. RPP02N 58mm sudah didukung secara native.',
          style: TextStyle(fontSize: 10, color: Color(0xFFA09080))),
      ])));
  }
}

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BluetoothPrinterService {
  static final BluetoothPrinterService _instance = BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  static const _kAddress = 'bt_printer_address';
  static const _kName    = 'bt_printer_name';

  BluetoothInfo? _device;
  BluetoothInfo? get device => _device;

  // ─── Bonded devices ────────────────────────────────────────────────────────
  Future<List<BluetoothInfo>> getBondedDevices() async {
    try { return await PrintBluetoothThermal.pairedBluetooths; }
    catch (_) { return []; }
  }

  // ─── Save & load selected printer ─────────────────────────────────────────
  Future<void> saveDevice(BluetoothInfo d) async {
    _device = d;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAddress, d.macAdress);
    await p.setString(_kName,    d.name);
  }

  Future<BluetoothInfo?> loadSavedDevice() async {
    final p = await SharedPreferences.getInstance();
    final addr = p.getString(_kAddress) ?? '';
    final name = p.getString(_kName)    ?? '';
    if (addr.isEmpty) return null;
    _device = BluetoothInfo(name: name, macAdress: addr);
    return _device;
  }

  Future<String?> getSavedName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_kName);
  }

  // ─── Connection with retry ────────────────────────────────────────────────
  Future<bool> connect() async {
    if (_device == null) return false;
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final already = await PrintBluetoothThermal.connectionStatus;
        if (already) return true;
        await PrintBluetoothThermal.connect(macPrinterAddress: _device!.macAdress);
        await Future.delayed(const Duration(milliseconds: 1500));
        final ok = await PrintBluetoothThermal.connectionStatus;
        if (ok) return true;
        await PrintBluetoothThermal.disconnect;
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      } catch (_) {
        try { await PrintBluetoothThermal.disconnect; } catch (_) {}
        await Future.delayed(Duration(milliseconds: 600 * attempt));
      }
    }
    return false;
  }

  Future<void> disconnect() async {
    try { await PrintBluetoothThermal.disconnect; } catch (_) {}
  }

  Future<bool> isConnected() async {
    try { return await PrintBluetoothThermal.connectionStatus; }
    catch (_) { return false; }
  }

  // ─── Print Struk ──────────────────────────────────────────────────────────
  /// Returns null on success, or error message string on failure.
  Future<String?> printStruk({
    required String nota,
    required String tokoNama,
    required String tokoAlamat,
    required List<Map<String, dynamic>> items,
    required double total,
    required double bayar,
    required double kembalian,
    required String metode,
    required String jam,
    required String kasir,
    double? subtotal,
    double? diskon,
    String? pelanggan,
  }) async {
    try {
      if (_device == null) await loadSavedDevice();
      if (_device == null) {
        return 'Printer belum dipilih.\nBuka Pengaturan → Printer Bluetooth.';
      }
      final ok = await connect();
      if (!ok) {
        return 'Gagal terhubung ke printer.\nPastikan printer menyala dan Bluetooth aktif.';
      }

      final List<int> bytes = [];

      // Initialize printer
      bytes.addAll([0x1B, 0x40]);

      // ── Header ──────────────────────────────────────────────────────
      bytes.addAll([0x0A]);                          // blank line
      bytes.addAll([0x1B, 0x61, 0x01]);             // center
      bytes.addAll([0x1D, 0x21, 0x11]);             // double size
      bytes.addAll([0x1B, 0x45, 0x01]);             // bold on
      bytes.addAll(_enc('KS PARFUME\n'));
      bytes.addAll([0x1D, 0x21, 0x00]);             // normal size (bold still on)
      bytes.addAll(_enc('${_trim(tokoNama, 32)}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);             // bold off
      if (tokoAlamat.isNotEmpty) bytes.addAll(_enc('${_trim(tokoAlamat, 32)}\n'));
      bytes.addAll([0x1B, 0x61, 0x00]);             // left
      bytes.addAll(_enc('--------------------------------\n'));
      bytes.addAll(_enc('${_lr("No:", nota)}\n'));
      bytes.addAll(_enc('${_lr("Tgl:", jam)}\n'));
      bytes.addAll(_enc('${_lr("Kasir:", kasir)}\n'));
      if (pelanggan != null && pelanggan.isNotEmpty && pelanggan.toLowerCase() != 'walk-in') {
        bytes.addAll(_enc('${_lr("Pelanggan:", _trim(pelanggan, 22))}\n'));
      }
      bytes.addAll(_enc('--------------------------------\n'));

      // ── Item baris ──────────────────────────────────────────────────
      for (final c in items) {
        final nama = (c['nama'] as String?) ?? '';
        final qty  = (c['qty'] as int?)    ?? 1;
        final hj   = (c['hj']  as num?)?.toDouble() ?? 0;
        final sub  = hj * qty;
        bytes.addAll(_enc('${_trim(nama, 32)}\n'));
        bytes.addAll(_enc('${_lr("  ${qty}x ${_fmt(hj)}", _fmt(sub))}\n'));
      }

      // ── Footer ──────────────────────────────────────────────────────
      bytes.addAll(_enc('--------------------------------\n'));
      if (diskon != null && diskon > 0) {
        final sub = subtotal ?? (total + diskon);
        bytes.addAll(_enc('${_lr("Subtotal", _fmt(sub))}\n'));
        bytes.addAll(_enc('${_lr("Diskon", "- ${_fmt(diskon)}")}\n'));
      }
      bytes.addAll([0x1B, 0x45, 0x01]);             // bold on
      bytes.addAll(_enc('${_lr("TOTAL", _fmt(total))}\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);             // bold off
      bytes.addAll(_enc('================================\n'));
      bytes.addAll(_enc('${_lr("Bayar ($metode)", _fmt(bayar))}\n'));
      if (kembalian > 0) bytes.addAll(_enc('${_lr("Kembalian", _fmt(kembalian))}\n'));
      bytes.addAll([0x0A]);                          // blank line
      bytes.addAll([0x1B, 0x61, 0x01]);             // center
      bytes.addAll([0x1B, 0x45, 0x01]);             // bold on
      bytes.addAll(_enc('** Terima Kasih **\n'));
      bytes.addAll([0x1B, 0x45, 0x00]);             // bold off
      bytes.addAll(_enc('Kunjungi kami lagi :)\n'));
      bytes.addAll([0x1B, 0x64, 0x03]);             // feed 3 lines
      bytes.addAll([0x1B, 0x61, 0x00]);             // left

      final sent = await PrintBluetoothThermal.writeBytes(bytes);
      return sent ? null : 'Gagal mengirim data ke printer.';
    } catch (e) {
      return 'Error printer: $e';
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  // Map string to ESC/POS-safe byte list (non-latin chars → '?')
  List<int> _enc(String s) => s.codeUnits.map((c) => c > 255 ? 63 : c).toList();

  String _trim(String s, int max) => s.length > max ? '${s.substring(0, max - 2)}..' : s;

  // Left-right justified at exactly 32 columns (58mm thermal paper)
  String _lr(String left, String right, {int width = 32}) {
    final rLen = right.length;
    final maxLeft = width - rLen - 1;
    if (maxLeft <= 0) return _trim(right, width);
    final l = left.length > maxLeft ? '${left.substring(0, maxLeft > 2 ? maxLeft - 2 : maxLeft)}..' : left;
    return l.padRight(width - rLen) + right;
  }

  String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer('Rp');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

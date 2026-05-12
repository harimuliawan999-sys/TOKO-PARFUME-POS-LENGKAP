import 'package:flutter/material.dart';
import '../services/api.dart';
import '../widgets/dev_contact.dart';
import 'home_screen.dart';
import 'pilih_cabang_screen.dart';

class LoginScreen extends StatefulWidget {
  final Map<String, dynamic> toko;
  const LoginScreen({super.key, required this.toko});
  @override State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  String _pin = '', _error = '';

  void _onKey(String k) {
    if (k == 'DEL') { if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1)); }
    else if (_pin.length < 4) { final np = _pin + k; setState(() => _pin = np); if (np.length == 4) _check(np); }
  }

  Future<void> _check(String pin) async {
    try {
      final u = await Api.loginPin(widget.toko['id'], pin);
      if (u != null && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen(toko: widget.toko, user: u)));
      } else { setState(() { _error = 'PIN salah!'; _pin = ''; }); Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _error = ''); }); }
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() { _error = msg.contains('Terkunci') || msg.contains('salah') ? msg : 'Koneksi gagal'; _pin = ''; });
      Future.delayed(const Duration(seconds: 3), () { if (mounted) setState(() => _error = ''); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(backgroundColor: const Color(0xFF1A1510), body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      // Logo
      Container(width: 70, height: 70, decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)]),
        boxShadow: [BoxShadow(color: const Color(0xFFD4A574).withOpacity(0.3), blurRadius: 16)]),
        child: const Center(child: Text('KS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)))),
      const SizedBox(height: 16),
      const Text('KS PARFUME', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 6, color: Color(0xFFD4A574))),
      const SizedBox(height: 4),
      Text(widget.toko['nama'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF8B7355))),
      const SizedBox(height: 8),
      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF27AE60).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_done, color: Color(0xFF27AE60), size: 12), SizedBox(width: 4),
          Text('ONLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF27AE60), letterSpacing: 2)),
        ])),
      const SizedBox(height: 28),

      // PIN Box
      Container(padding: const EdgeInsets.all(28), decoration: BoxDecoration(color: const Color(0xFF2A2520), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF3A3530)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
        child: Column(children: [
          const Text('Masukkan PIN untuk login', style: TextStyle(fontSize: 13, color: Color(0xFFD4A574), fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          // PIN dots
          Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) => AnimatedContainer(
            duration: const Duration(milliseconds: 200), width: 42, height: 50, margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: i < _pin.length ? const Color(0xFFD4A574).withOpacity(0.2) : const Color(0xFF1A1510),
              border: Border.all(color: i < _pin.length ? const Color(0xFFD4A574) : const Color(0xFF3A3530), width: 2),
              boxShadow: i < _pin.length ? [BoxShadow(color: const Color(0xFFD4A574).withOpacity(0.2), blurRadius: 8)] : null),
            child: Center(child: Text(i < _pin.length ? '●' : '', style: const TextStyle(fontSize: 20, color: Color(0xFFD4A574))))))),
          const SizedBox(height: 20),
          // Keypad
          SizedBox(width: 230, child: GridView.count(crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.2,
            children: ['1','2','3','4','5','6','7','8','9','','0','DEL'].map((n) {
              if (n.isEmpty) return const SizedBox();
              return GestureDetector(onTap: () => _onKey(n), child: Container(decoration: BoxDecoration(color: n == 'DEL' ? Colors.transparent : const Color(0xFF1A1510), borderRadius: BorderRadius.circular(10)),
                child: Center(child: Text(n == 'DEL' ? '⌫' : n, style: TextStyle(fontSize: n == 'DEL' ? 18 : 22, fontWeight: FontWeight.w600, color: n == 'DEL' ? const Color(0xFF8B7355) : const Color(0xFFD4A574))))));
            }).toList())),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error, style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 12), textAlign: TextAlign.center)),
        ])),

      const SizedBox(height: 24),
      // Ganti Cabang
      GestureDetector(
        onTap: () async {
          final list = await Api.getAllToko();
          if (!context.mounted) return;
          if (list.length > 1) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PilihCabangScreen(tokoList: list)));
          }
        },
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF3A3530)), borderRadius: BorderRadius.circular(20)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.swap_horiz, color: Color(0xFF8B7355), size: 14), SizedBox(width: 6),
            Text('Ganti Cabang', style: TextStyle(fontSize: 10, color: Color(0xFF8B7355), fontWeight: FontWeight.w500)),
          ]))),
      const SizedBox(height: 16),
      const DevContact(compact: true),
    ]))));
  }
}

import 'package:flutter/material.dart';
import 'login_screen.dart';

class PilihCabangScreen extends StatelessWidget {
  final List<Map<String, dynamic>> tokoList;
  const PilihCabangScreen({super.key, required this.tokoList});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1510),
      body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Logo
        Container(width: 70, height: 70,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)]),
            boxShadow: [BoxShadow(color: const Color(0xFFD4A574).withOpacity(0.3), blurRadius: 16)]),
          child: const Center(child: Text('KS', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 2)))),
        const SizedBox(height: 16),
        const Text('KS PARFUME', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w300, letterSpacing: 6, color: Color(0xFFD4A574))),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(color: const Color(0xFF27AE60).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_done, color: Color(0xFF27AE60), size: 12), SizedBox(width: 4),
            Text('ONLINE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFF27AE60), letterSpacing: 2)),
          ])),
        const SizedBox(height: 36),

        // Title
        const Text('Pilih Cabang', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFFD4A574))),
        const SizedBox(height: 4),
        Text('${tokoList.length} cabang tersedia', style: const TextStyle(fontSize: 11, color: Color(0xFF8B7355))),
        const SizedBox(height: 20),

        // Branch cards
        ...tokoList.asMap().entries.map((entry) {
          final i = entry.key;
          final toko = entry.value;
          final colors = [
            [const Color(0xFFD4A574), const Color(0xFFB8860B)],
            [const Color(0xFF2980B9), const Color(0xFF1A5276)],
            [const Color(0xFF27AE60), const Color(0xFF1E8449)],
          ];
          final grad = colors[i % colors.length];

          return GestureDetector(
            onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(toko: toko))),
            child: Container(
              width: double.infinity, margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [grad[0].withOpacity(0.15), grad[1].withOpacity(0.05)]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: grad[0].withOpacity(0.3)),
              ),
              child: Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: grad), borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: grad[0].withOpacity(0.3), blurRadius: 8)]),
                  child: Center(child: Text('${i + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(toko['nama'] ?? 'Cabang ${i + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: grad[0])),
                  Text(toko['alamat'] ?? '-', style: const TextStyle(fontSize: 11, color: Color(0xFF8B7355))),
                ])),
                Icon(Icons.arrow_forward_ios, size: 16, color: grad[0]),
              ]),
            ),
          );
        }),
      ]))),
    );
  }
}

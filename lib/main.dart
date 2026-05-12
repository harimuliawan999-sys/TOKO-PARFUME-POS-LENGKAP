import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/login_screen.dart';
import 'screens/pilih_cabang_screen.dart';
import 'services/offline_cache.dart';
import 'widgets/dev_contact.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',       // ← Ganti dengan URL Supabase project kamu
    anonKey: 'YOUR_SUPABASE_ANON_KEY', // ← Ganti dengan anon key Supabase kamu
  );
  runApp(const KSParfumeApp());
}

class KSParfumeApp extends StatelessWidget {
  const KSParfumeApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KS Parfume',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFD4A574), primary: const Color(0xFF3A2E24), secondary: const Color(0xFFD4A574), surface: const Color(0xFFFAF8F5)),
        useMaterial3: true, fontFamily: 'Roboto', scaffoldBackgroundColor: const Color(0xFFFAF8F5),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1A1510), foregroundColor: Color(0xFFD4A574), elevation: 0, centerTitle: true),
        elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD4A574), foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20))),
        cardTheme: CardTheme(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Color(0xFFE8E0D8))), color: Colors.white),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  String _status = 'Menghubungkan ke server...';
  bool _error = false;
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _init();
  }

  @override void dispose() { _anim.dispose(); super.dispose(); }

  Future<void> _init() async {
    try {
      // Check connectivity first
      final conn = await Connectivity().checkConnectivity();
      final hasNet = !conn.contains(ConnectivityResult.none);

      List<dynamic> tokoList = [];
      if (hasNet) {
        try {
          tokoList = await Supabase.instance.client.from('toko').select().order('nama');
          // Cache it for offline fallback
          await OfflineCache.save('toko_list', tokoList);
        } catch (e) {
          // Network available but server down - try cache
          final cached = await OfflineCache.load('toko_list');
          if (cached != null) {
            tokoList = List<dynamic>.from(cached);
            setState(() => _status = 'Server bermasalah, pakai data lokal...');
          } else {
            rethrow;
          }
        }
      } else {
        // No network - try cache
        final cached = await OfflineCache.load('toko_list');
        if (cached != null) {
          tokoList = List<dynamic>.from(cached);
          setState(() => _status = 'Mode Offline — data dari cache');
        } else {
          setState(() { _status = 'Tidak ada internet\ndan belum pernah sync data'; _error = true; });
          return;
        }
      }

      if (tokoList.isEmpty) {
        setState(() { _status = 'Toko belum di-setup di database'; _error = true; });
        return;
      }
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      if (tokoList.length == 1) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginScreen(toko: Map<String, dynamic>.from(tokoList.first))));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => PilihCabangScreen(tokoList: tokoList.map((t) => Map<String, dynamic>.from(t)).toList())));
      }
    } catch (e) {
      setState(() { _status = 'Gagal koneksi: $e'; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1510),
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Logo with glow
        Container(width: 80, height: 80,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(colors: [Color(0xFFD4A574), Color(0xFFB8860B)]),
            boxShadow: [BoxShadow(color: const Color(0xFFD4A574).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)]),
          child: const Center(child: Text('KS', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 3)))),
        const SizedBox(height: 20),
        const Text('KS PARFUME', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w300, letterSpacing: 8, color: Color(0xFFD4A574))),
        const SizedBox(height: 36),
        if (!_error) SizedBox(width: 140, height: 3, child: AnimatedBuilder(animation: _anim, builder: (_, __) =>
          LinearProgressIndicator(value: _anim.value, color: const Color(0xFFD4A574), backgroundColor: const Color(0xFF2A2520)))),
        if (_error) ...[
          const Icon(Icons.cloud_off, color: Color(0xFFE74C3C), size: 40),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Text(_status, style: TextStyle(fontSize: 11, color: _error ? const Color(0xFFE74C3C) : const Color(0xFF5C4A3A)), textAlign: TextAlign.center),
        if (_error) ...[
          const SizedBox(height: 16),
          ElevatedButton.icon(icon: const Icon(Icons.refresh, size: 18), label: const Text('Coba Lagi'),
            onPressed: () { setState(() { _error = false; _status = 'Menghubungkan...'; }); _init(); }),
          const SizedBox(height: 12),
          GestureDetector(onTap: DevContact.openWhatsApp,
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat, color: Color(0xFF25D366), size: 14), SizedBox(width: 6),
                Text('Ada kendala? Hubungi Developer', style: TextStyle(fontSize: 10, color: Color(0xFF25D366), fontWeight: FontWeight.w600)),
              ]))),
        ],
        const SizedBox(height: 40),
        const Text('Developer: Hari Muliawan, S.Mat', style: TextStyle(fontSize: 9, color: Color(0xFF5C4A3A))),
        GestureDetector(onTap: DevContact.openWhatsApp,
          child: const Text('WA: 083113177107', style: TextStyle(fontSize: 9, color: Color(0xFF25D366), decoration: TextDecoration.underline))),
      ])),
    );
  }
}

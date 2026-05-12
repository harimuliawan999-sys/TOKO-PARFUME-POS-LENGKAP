import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget kontak developer — bisa diklik langsung ke WhatsApp
class DevContact extends StatelessWidget {
  final bool compact;
  const DevContact({super.key, this.compact = false});

  static Future<void> openWhatsApp() async {
    final uri = Uri.parse('https://wa.me/6283113177107?text=Halo%20Pak%20Hari%2C%20saya%20butuh%20bantuan%20untuk%20app%20KS%20Parfume...');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: openWhatsApp,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xFF25D366).withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.chat, color: Color(0xFF25D366), size: 14),
            SizedBox(width: 6),
            Text('Ada kendala? Hubungi Dev', style: TextStyle(fontSize: 9, color: Color(0xFF25D366), fontWeight: FontWeight.w600)),
          ]),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.code, size: 16, color: Color(0xFFD4A574)),
            SizedBox(width: 8),
            Text('Developer', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3A2E24))),
          ]),
          const SizedBox(height: 10),
          const Text('Hari Muliawan, S.Mat', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF3A2E24))),
          const SizedBox(height: 12),

          GestureDetector(
            onTap: openWhatsApp,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: const Color(0xFF25D366).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.chat, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Hubungi via WhatsApp', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          const Center(child: Text('WA: 083113177107', style: TextStyle(fontSize: 10, color: Color(0xFFA09080)))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: const Color(0xFFFAF8F5), borderRadius: BorderRadius.circular(8)),
            child: const Text(
              'Ada kendala, butuh fitur tambahan, atau ingin custom app?\nHubungi developer langsung via WhatsApp.',
              style: TextStyle(fontSize: 10, color: Color(0xFFA09080), height: 1.4),
              textAlign: TextAlign.center,
            ),
          ),
        ]),
      ),
    );
  }
}

/// Online/Offline status indicator
class ConnectionBadge extends StatelessWidget {
  final bool online;
  final int pendingSync;
  const ConnectionBadge({super.key, required this.online, this.pendingSync = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: online ? const Color(0xFF27AE60).withOpacity(0.15) : const Color(0xFFE74C3C).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: online ? const Color(0xFF27AE60) : const Color(0xFFE74C3C))),
        const SizedBox(width: 6),
        Text(
          online ? (pendingSync > 0 ? 'Online · $pendingSync pending' : 'Online') : 'Offline Mode',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: online ? const Color(0xFF27AE60) : const Color(0xFFE74C3C)),
        ),
      ]),
    );
  }
}

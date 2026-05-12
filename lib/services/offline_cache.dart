import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Cache lokal — simpan data terakhir dari Supabase
/// Kalau internet mati, ambil dari cache ini
class OfflineCache {
  static const _prefix = 'cache_';

  static Future<void> save(String key, dynamic data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(data));
    await prefs.setString('$_prefix${key}_time', DateTime.now().toIso8601String());
  }

  static Future<dynamic> load(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix$key');
    if (raw == null) return null;
    return jsonDecode(raw);
  }

  static Future<String?> lastSynced(String key) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_prefix${key}_time');
  }

  /// Simpan transaksi offline (antrian)
  static Future<void> queueTransaction(Map<String, dynamic> trx) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefix}offline_queue') ?? '[]';
    final queue = List<Map<String, dynamic>>.from(jsonDecode(raw));
    queue.add({...trx, 'queued_at': DateTime.now().toIso8601String()});
    await prefs.setString('${_prefix}offline_queue', jsonEncode(queue));
  }

  static Future<List<Map<String, dynamic>>> getQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('${_prefix}offline_queue') ?? '[]';
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  static Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_prefix}offline_queue', '[]');
  }
}

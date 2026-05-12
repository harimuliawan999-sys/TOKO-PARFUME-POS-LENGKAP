import 'dart:convert';
import '../database/db_helper.dart';

class BackupService {
  static Future<String> exportJSON() async {
    final db = DBHelper();
    final data = await db.exportAllData();
    return jsonEncode(data);
  }
}

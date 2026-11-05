import 'dart:convert';
import 'package:android_id/android_id.dart';
import 'package:crypto/crypto.dart';

class LicenseService {
  static const String _secretKey = "TIMBANGAN_SAWIT_FAKKIN_2026";

  /// ID unik perangkat, format XXXX-XXXX-XXXX.
  static Future<String> getDeviceId() async {
    final raw = await const AndroidId().getId() ?? 'UNKNOWN';
    final hex = sha256.convert(utf8.encode(raw)).toString().toUpperCase().substring(0, 12);
    return '${hex.substring(0, 4)}-${hex.substring(4, 8)}-${hex.substring(8, 12)}';
  }

  /// Kode lisensi lifetime: 16 karakter, tampil sebagai XXXXXXXX-XXXXXXXX.
  /// Dipakai admin untuk membuat kode dari Device ID pelanggan.
  static String generateKey(String deviceId) {
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    return hmac.convert(utf8.encode('LIFETIME|$deviceId')).toString().substring(0, 16).toUpperCase();
  }

  static String _bersihkan(String s) => s.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();

  static bool validateKey(String deviceId, String rawKey) =>
      _bersihkan(rawKey) == generateKey(deviceId);
}
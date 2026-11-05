import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'db_helper.dart';
import 'license_service.dart';
import 'activation_screen.dart';
import 'license_database.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.light);
String? currentUser;
const List<String> kNamaBulan = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
  'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
];

const int kLisensiKritis = 7;
const int kLisensiWaspada = 30;

enum LicenseLevel { aman, waspada, kritis, kadaluarsa }
final ValueNotifier<LicenseInfo?> licenseInfoNotifier = ValueNotifier(null);

class LicenseInfo {
  final DateTime expired;

  const LicenseInfo(this.expired);
  int get sisaHari {
    final now = DateTime.now();
    final hariIni = DateTime(now.year, now.month, now.day);
    final akhir = DateTime(expired.year, expired.month, expired.day);
    return akhir.difference(hariIni).inDays;
  }

  LicenseLevel get level {
    final sisa = sisaHari;
    if (sisa < 0) return LicenseLevel.kadaluarsa;
    if (sisa <= kLisensiKritis) return LicenseLevel.kritis;
    if (sisa <= kLisensiWaspada) return LicenseLevel.waspada;
    return LicenseLevel.aman;
  }
  String get tanggalPanjang => '${expired.day} ${kNamaBulan[expired.month - 1]} ${expired.year}';
  String get tanggalRingkas => DateFormat('dd/MM/yyyy').format(expired);
  String get ringkasan {
    switch (level) {
      case LicenseLevel.kadaluarsa:
        return 'KADALUARSA';
      case LicenseLevel.kritis:
        return sisaHari == 0 ? 'HABIS HARI INI' : 'SISA $sisaHari HARI';
      case LicenseLevel.waspada:
        return 'SISA $sisaHari HARI';
      case LicenseLevel.aman:
        return 's/d $tanggalRingkas';
    }
  }
  String get keterangan {
    switch (level) {
      case LicenseLevel.kadaluarsa:
        return 'Lisensi berakhir pada $tanggalPanjang. Hubungi penyedia aplikasi untuk memperpanjang.';
      case LicenseLevel.kritis:
        return sisaHari == 0
            ? 'Lisensi berakhir hari ini, $tanggalPanjang. Segera lakukan perpanjangan agar aplikasi tetap bisa dipakai.'
            : 'Lisensi berakhir $sisaHari hari lagi, pada $tanggalPanjang. Segera lakukan perpanjangan.';
      case LicenseLevel.waspada:
        return 'Lisensi masih berlaku $sisaHari hari lagi, sampai $tanggalPanjang. Siapkan perpanjangan dari sekarang.';
      case LicenseLevel.aman:
        return 'Lisensi aktif sampai $tanggalPanjang ($sisaHari hari lagi).';
    }
  }
  Color get warna {
    switch (level) {
      case LicenseLevel.kadaluarsa:
      case LicenseLevel.kritis:
        return const Color(0xFFFCA5A5); // merah muda terang
      case LicenseLevel.waspada:
        return const Color(0xFFFCD34D); // kuning
      case LicenseLevel.aman:
        return const Color(0xFF86EFAC); // hijau terang
    }
  }

  Color get warnaPekat {
    switch (level) {
      case LicenseLevel.kadaluarsa:
      case LicenseLevel.kritis:
        return const Color(0xFFB91C1C);
      case LicenseLevel.waspada:
        return const Color(0xFFB45309);
      case LicenseLevel.aman:
        return AppTheme.primaryGreen;
    }
  }

  IconData get ikon {
    switch (level) {
      case LicenseLevel.kadaluarsa:
        return Icons.gpp_bad_rounded;
      case LicenseLevel.kritis:
        return Icons.error_rounded;
      case LicenseLevel.waspada:
        return Icons.warning_amber_rounded;
      case LicenseLevel.aman:
        return Icons.verified_rounded;
    }
  }

  static LicenseInfo? fromResult(Map<String, dynamic> result) {
    const kunci = [
      'expiredDate', 'expired_date', 'expiredAt', 'expired_at', 'expired',
      'expiryDate', 'expiry_date', 'expiry', 'expiresAt', 'expires_at',
      'validUntil', 'valid_until', 'endDate', 'end_date',
      'tanggalKadaluarsa', 'tanggal_kadaluarsa', 'kadaluarsa',
      'masaAktif', 'masa_aktif', 'berlakuSampai', 'berlaku_sampai',
    ];

    for (final k in kunci) {
      if (!result.containsKey(k)) continue;
      final dt = _parseTanggal(result[k]);
      if (dt != null) return LicenseInfo(dt);
    }

    // Sebagian backend hanya mengirim sisa hari, bukan tanggal.
    const kunciHari = ['daysLeft', 'days_left', 'sisaHari', 'sisa_hari', 'remainingDays'];
    for (final k in kunciHari) {
      if (!result.containsKey(k)) continue;
      final v = result[k];
      final hari = v is num ? v.toInt() : int.tryParse('${v ?? ''}');
      if (hari != null) {
        final now = DateTime.now();
        return LicenseInfo(DateTime(now.year, now.month, now.day).add(Duration(days: hari)));
      }
    }
    return null;
  }

  static DateTime? _parseTanggal(dynamic nilai) {
    if (nilai == null) return null;
    if (nilai is DateTime) return nilai;

    // Angka besar dianggap epoch (detik atau milidetik).
    if (nilai is num) {
      final n = nilai.toInt();
      if (n > 100000000000) return DateTime.fromMillisecondsSinceEpoch(n);
      if (n > 1000000000) return DateTime.fromMillisecondsSinceEpoch(n * 1000);
      return null;
    }

    final teks = nilai.toString().trim();
    if (teks.isEmpty) return null;

    // ISO 8601, 'yyyy-MM-dd', dan 'yyyy-MM-dd HH:mm:ss' ditangani tryParse.
    final iso = DateTime.tryParse(teks);
    if (iso != null) return iso;

    for (final pola in ['dd/MM/yyyy', 'dd-MM-yyyy', 'd/M/yyyy', 'yyyy/MM/dd', 'dd/MM/yyyy HH:mm:ss']) {
      try {
        return DateFormat(pola).parseStrict(teks);
      } catch (_) {
        // coba pola berikutnya
      }
    }
    return null;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLicensed = false;
  bool _isLoading = true;
  String? _licenseErrorMsg;

  @override
  void initState() {
    super.initState();
    _checkLicense();
  }

  Future<void> _checkLicense() async {
    bool valid = false;
    String? message;

    try {
      final deviceId = await LicenseService.getDeviceId();
      valid = await LicenseDatabase.instance.isLicensed(deviceId);
      if (!valid) message = 'Perangkat belum teraktivasi';
    } catch (e) {
      message = 'Gagal memeriksa lisensi: $e';
    }

    if (!mounted) return;
    setState(() {
      _isLicensed = valid;
      _licenseErrorMsg = message;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder + theme/darkTheme/themeMode membuat AppTheme
    // benar-benar dipakai dan tombol terang/gelap bekerja di seluruh aplikasi
    // (termasuk layar loading dan layar aktivasi).
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final Widget home;
        if (_isLoading) {
          home = const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (_isLicensed) {
          // Sudah terlisensi -> halaman login, lalu MainPage (masuk/keluar/riwayat).
          home = const LoginScreen();
        } else {
          home = ActivationScreen(
            initialErrorMessage: _licenseErrorMsg,
            onActivated: () {
              setState(() => _isLicensed = true);
              // Segarkan masa aktif setelah aktivasi berhasil.
              _checkLicense();
            },
          );
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Aplikasi Timbangan Sawit',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: mode,
          home: home,
        );
      },
    );
  }
}

/// Badge masa aktif lisensi untuk header bergradasi. Warnanya mengikuti sisa
/// hari: hijau (aman), kuning (mendekati habis), merah (kritis / kadaluarsa).
/// Diketuk akan membuka dialog detail.
class LicenseBadge extends StatelessWidget {
  /// Bila true, kondisi "aman" hanya ditulis "AKTIF" agar hemat ruang.
  final bool ringkas;
  const LicenseBadge({super.key, this.ringkas = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LicenseInfo?>(
      valueListenable: licenseInfoNotifier,
      builder: (context, info, _) {
        if (info == null) return const SizedBox.shrink();
        final color = info.warna;
        final teks = (ringkas && info.level == LicenseLevel.aman) ? 'AKTIF' : info.ringkasan;

        return Tooltip(
          message: info.keterangan,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => tampilkanDetailLisensi(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(info.ikon, size: 12, color: color),
                  const SizedBox(width: 4),
                  Text(
                    teks,
                    style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dialog detail lisensi: sisa hari, bilah progres, dan saran tindakan.
Future<void> tampilkanDetailLisensi(BuildContext context) async {
  final info = licenseInfoNotifier.value;
  if (info == null) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final sisa = info.sisaHari;
      // Bilah progres memakai acuan satu tahun agar ada gambaran visual
      // seberapa banyak masa aktif yang tersisa.
      final persen = (sisa / 365).clamp(0.0, 1.0).toDouble();
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        icon: Icon(info.ikon, color: info.warnaPekat, size: 32),
        title: const Text('Masa Aktif Lisensi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              sisa < 0 ? 'Sudah berakhir' : '$sisa hari lagi',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: info.warnaPekat),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: sisa < 0 ? 1.0 : persen,
                minHeight: 7,
                backgroundColor: info.warnaPekat.withOpacity(0.15),
                valueColor: AlwaysStoppedAnimation<Color>(info.warnaPekat),
              ),
            ),
            const SizedBox(height: 16),
            Text(info.keterangan, textAlign: TextAlign.center, style: Theme.of(dialogContext).textTheme.bodyLarge),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('TUTUP'),
          ),
        ],
      );
    },
  );
}

/// Bilah peringatan di atas konten, muncul hanya saat lisensi sudah masuk
/// tahap waspada atau kritis. Selagi masih aman ia tidak tampil sama sekali,
/// supaya tidak menambah gangguan visual pada kondisi normal.
class LicenseWarningBar extends StatelessWidget {
  const LicenseWarningBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LicenseInfo?>(
      valueListenable: licenseInfoNotifier,
      builder: (context, info, _) {
        if (info == null || info.level == LicenseLevel.aman) return const SizedBox.shrink();
        final color = info.warnaPekat;
        return Material(
          color: color.withOpacity(0.12),
          child: InkWell(
            onTap: () => tampilkanDetailLisensi(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(info.ikon, size: 18, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      info.level == LicenseLevel.kadaluarsa
                          ? 'Lisensi telah berakhir pada ${info.tanggalPanjang}.'
                          : 'Masa aktif lisensi tinggal ${info.sisaHari} hari (sampai ${info.tanggalRingkas}).',
                      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: color),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// =======================================================================
// THEME — palet warna industri (hijau tua, oranye aksen, abu gelap),
// tipografi tebal & tegas agar terbaca jelas di lapangan / lingkungan terang.
// =======================================================================
class AppTheme {
  static const Color primaryGreen = Color(0xFF166534);
  static const Color primaryGreenDeep = Color(0xFF0E4429);
  static const Color accentOrange = Color(0xFFEA7C17);
  static const Color accentAmber = Color(0xFFFFB020);
  static const Color slate900 = Color(0xFF0B1210);
  static const Color slate800 = Color(0xFF16201C);
  static const Color slate700 = Color(0xFF223028);
  static const Color lightBg = Color(0xFFF1F5F2);
  static const Color lightCard = Color(0xFFFFFFFF);

  static const String fontFamily = 'Roboto';

  static const LinearGradient headerGradient = LinearGradient(
    colors: [primaryGreenDeep, primaryGreen],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static TextTheme _textTheme(Color onSurface) {
    return TextTheme(
      displaySmall: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 30,
          letterSpacing: 0.5,
          color: onSurface),
      titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 20,
          letterSpacing: 0.3,
          color: onSurface),
      titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: 0.2,
          color: onSurface),
      bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: 15,
          color: onSurface),
      bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
          color: onSurface.withOpacity(0.75)),
      labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 13,
          letterSpacing: 1.1,
          color: onSurface.withOpacity(0.85)),
    );
  }

  static ThemeData get light {
    final base = ColorScheme.fromSeed(seedColor: primaryGreen, brightness: Brightness.light);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: base.copyWith(secondary: accentOrange),
      scaffoldBackgroundColor: lightBg,
      fontFamily: fontFamily,
      textTheme: _textTheme(const Color(0xFF16201C)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 1.5,
        shadowColor: Colors.black.withOpacity(0.08),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: Colors.grey.shade300, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryGreen, width: 2),
        ),
        labelStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: 0.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: primaryGreen.withOpacity(0.14),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 11.5),
        ),
        elevation: 3,
      ),
    );
  }

  static ThemeData get dark {
    final base = ColorScheme.fromSeed(seedColor: primaryGreen, brightness: Brightness.dark);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: base.copyWith(secondary: accentOrange, surface: slate800),
      scaffoldBackgroundColor: slate900,
      fontFamily: fontFamily,
      textTheme: _textTheme(const Color(0xFFEDEFF0)),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: 0.3,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: slate800,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: slate700)),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(color: slate700, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: slate700,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.greenAccent, width: 2),
        ),
        labelStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, color: Colors.white70),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w800, fontSize: 15.5, letterSpacing: 0.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: slate800,
        indicatorColor: Colors.greenAccent.withOpacity(0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 11.5),
        ),
        elevation: 3,
      ),
    );
  }
}

// Ubah IP sesuai IP laptop kamu saat tes (misal: '192.168.1.15:8000')
// Nanti kalau disambung ke ESP32 asli ganti jadi '192.168.4.1'
String ipArduino = '172.20.10.2:8000';

// Kapasitas maksimum jembatan timbang, dipakai untuk gauge visual (kg).
const int kKapasitasMaksimum = 20000;

/// Mengambil berat terkini dari perangkat timbangan.
/// Mengembalikan null jika perangkat tidak terjangkau atau respons tidak valid,
/// sehingga tampilan tetap memakai nilai terakhir yang berhasil dibaca.
/// (Dipakai bersama oleh layar Timbang Masuk & Timbang Keluar.)
Future<int?> ambilBeratPerangkat() async {
  try {
    final res = await http.get(Uri.parse('http://$ipArduino/berat')).timeout(const Duration(seconds: 1));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final berat = data['berat'];
      if (berat is num) return berat.round(); // aman untuk int maupun double
      if (berat is String) return int.tryParse(berat);
    }
  } catch (_) {}
  return null;
}

// =======================================================================
// 0. HALAMAN LOGIN
// =======================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _shake = false;

  late final AnimationController _entrance =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
  Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _entrance.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _login() {
    final String user = _usernameCtrl.text.trim().toLowerCase();
    final String pass = _passwordCtrl.text;

    if (user == 'admin' && pass == 'admin') {
      // Catat siapa yang sedang masuk, dipakai pada dialog konfirmasi keluar.
      currentUser = user;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (context, animation, secondary) => const MainPage(),
          transitionsBuilder: (context, animation, secondary, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    } else {
      // Kosongkan kata sandi agar pengguna tidak perlu menghapusnya manual.
      _passwordCtrl.clear();
      setState(() => _shake = true);
      Future.delayed(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => _shake = false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama pengguna atau kata sandi salah.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppTheme.headerGradient),
          ),
          const Positioned(
            top: -60,
            right: -60,
            child: _DecorCircle(size: 220, opacity: 0.08),
          ),
          const Positioned(
            bottom: -80,
            left: -80,
            child: _DecorCircle(size: 260, opacity: 0.07),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withOpacity(0.14),
                            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
                          ),
                          child: const Icon(Icons.scale_rounded, size: 38, color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'TIMBANGAN',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'SISTEM TIMBANGAN PORTABLE',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          transform: Matrix4.translationValues(_shake ? 8 : 0, 0, 0),
                          child: Card(
                            color: isDark ? AppTheme.slate800 : Colors.white,
                            elevation: 10,
                            shadowColor: Colors.black.withOpacity(0.3),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            child: Padding(
                              padding: const EdgeInsets.all(22.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('MASUK KE SISTEM', style: Theme.of(context).textTheme.labelLarge),
                                  const SizedBox(height: 16),
                                  TextField(
                                    controller: _usernameCtrl,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Nama Pengguna',
                                      prefixIcon: Icon(Icons.person_outline_rounded),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  TextField(
                                    controller: _passwordCtrl,
                                    obscureText: _obscure,
                                    onSubmitted: (_) => _login(),
                                    decoration: InputDecoration(
                                      labelText: 'Kata Sandi',
                                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                                      suffixIcon: IconButton(
                                        icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                                        onPressed: () => setState(() => _obscure = !_obscure),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  ElevatedButton.icon(
                                    onPressed: _login,
                                    icon: const Icon(Icons.login_rounded),
                                    label: const Text('MASUK'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryGreen,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Masa aktif lisensi ditampilkan sejak halaman masuk,
                        // supaya petugas tahu kondisinya sebelum mulai bekerja.
                        const LicenseBadge(),
                        const SizedBox(height: 14),
                        Text(
                          'v1.0 · 2026',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Tombol tema ditaruh PALING AKHIR di Stack supaya berada di lapisan
          // teratas. Sebelumnya ia berada di bawah Center + ScrollView (yang
          // memenuhi layar), sehingga ketukan tidak pernah sampai ke tombol.
          const SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(right: 6, top: 4),
                child: ThemeToggleButton(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DecorCircle extends StatelessWidget {
  final double size;
  final double opacity;
  const _DecorCircle({required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(opacity)),
    );
  }
}

// =======================================================================
// MAIN PAGE — navigasi bawah gaya Material 3 dengan transisi halaman animasi
// =======================================================================
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    TimbangMasukScreen(),
    TimbangKeluarScreen(),
    RiwayatScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // PopScope: tombol "kembali" perangkat tidak lagi melempar pengguna keluar
    // dari aplikasi begitu saja, tapi menawarkan keluar akun lebih dulu.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        konfirmasiLogout(context);
      },
      child: Scaffold(
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final slide = Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(animation);
            return FadeTransition(opacity: animation, child: SlideTransition(position: slide, child: child));
          },
          child: KeyedSubtree(
            key: ValueKey<int>(_selectedIndex),
            child: _pages[_selectedIndex],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) => setState(() => _selectedIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.login_rounded), label: 'MASUK'),
            NavigationDestination(icon: Icon(Icons.logout_rounded), label: 'KELUAR'),
            NavigationDestination(icon: Icon(Icons.receipt_long_rounded), label: 'RIWAYAT'),
          ],
        ),
      ),
    );
  }
}

// =======================================================================
// HEADER — app bar bergradasi dengan judul, subjudul, dan badge lisensi
// =======================================================================
class IndustrialHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;

  const IndustrialHeader({super.key, required this.title, required this.subtitle, this.actions = const []});

  @override
  Size get preferredSize => const Size.fromHeight(78);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppTheme.headerGradient,
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 14, offset: Offset(0, 6))],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 10, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 19, letterSpacing: 0.3)),
                    const SizedBox(height: 3),
                    // Baris kedua: subjudul + badge masa aktif lisensi.
                    // Badge ditaruh di sini (bukan di `actions`) supaya deretan
                    // ikon di kanan tidak bertambah padat pada layar ponsel.
                    Row(
                      children: [
                        Flexible(
                          child: Text(subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: Colors.white.withOpacity(0.78), fontWeight: FontWeight.w500, fontSize: 12.5)),
                        ),
                        const SizedBox(width: 8),
                        const LicenseBadge(ringkas: true),
                      ],
                    ),
                  ],
                ),
              ),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

// =======================================================================
// WIDGET UMUM
// =======================================================================

/// Tombol aksi untuk toggle mode gelap/terang, dipasang di setiap AppBar.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: isDark ? 'Mode Terang' : 'Mode Gelap',
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => RotationTransition(turns: anim, child: child),
        child: Icon(
          isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
          key: ValueKey<bool>(isDark),
          color: Colors.white,
        ),
      ),
      onPressed: () {
        themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
      },
    );
  }
}

/// Tombol keluar akun di AppBar. Ikonnya sengaja BUKAN `logout_rounded`
/// supaya tidak tertukar dengan menu "KELUAR" (timbang keluar) di navigasi bawah.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Keluar Akun',
      icon: const Icon(Icons.power_settings_new_rounded, color: Colors.white),
      onPressed: () => konfirmasiLogout(context),
    );
  }
}
/// Menu titik tiga di header: gabungan tema, status lisensi, dan keluar akun.
/// Menggantikan ThemeToggleButton + LogoutButton yang sebelumnya terpisah,
/// supaya deretan ikon di appbar tidak penuh.
class HeaderOverflowMenu extends StatelessWidget {
  const HeaderOverflowMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ValueListenableBuilder<LicenseInfo?>(
      valueListenable: licenseInfoNotifier,
      builder: (context, info, _) {
        return PopupMenuButton<String>(
          tooltip: 'Menu',
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          offset: const Offset(0, 46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onSelected: (value) {
            switch (value) {
              case 'theme':
                themeModeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
                break;
              case 'license':
                tampilkanDetailLisensi(context);
                break;
              case 'logout':
                konfirmasiLogout(context);
                break;
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'theme',
              child: _HeaderMenuRow(
                icon: isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                label: isDark ? 'Mode Terang' : 'Mode Gelap',
              ),
            ),
            if (info != null)
              PopupMenuItem(
                value: 'license',
                child: _HeaderMenuRow(
                  icon: info.ikon,
                  iconColor: info.warnaPekat,
                  label: 'Lisensi: ${info.ringkasan}',
                ),
              ),
            const PopupMenuDivider(height: 8),
            const PopupMenuItem(
              value: 'logout',
              child: _HeaderMenuRow(
                icon: Icons.power_settings_new_rounded,
                iconColor: AppTheme.accentOrange,
                label: 'Keluar Akun',
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HeaderMenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;
  const _HeaderMenuRow({required this.icon, required this.label, this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

/// Menampilkan dialog konfirmasi, lalu mengembalikan pengguna ke halaman login
/// bila disetujui. Seluruh riwayat navigasi dibuang agar sesi benar-benar berakhir.
Future<void> konfirmasiLogout(BuildContext context) async {
  final bool? setuju = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      icon: const Icon(Icons.power_settings_new_rounded, color: AppTheme.accentOrange, size: 32),
      title: const Text('Keluar Akun?'),
      content: Text(
        currentUser == null
            ? 'Anda akan kembali ke halaman masuk.'
            : 'Anda masuk sebagai "$currentUser". Kembali ke halaman masuk?',
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('BATAL'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: const Text('KELUAR'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentOrange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ],
    ),
  );

  if (setuju != true) return;
  if (!context.mounted) return;

  currentUser = null;
  // pushAndRemoveUntil membuang semua halaman sebelumnya, sehingga tombol
  // "kembali" perangkat tidak bisa masuk lagi tanpa login ulang.
  Navigator.of(context).pushAndRemoveUntil(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (_, __, ___) => const LoginScreen(),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
    ),
        (route) => false,
  );
}

/// Titik indikator berdenyut untuk menandakan koneksi perangkat aktif (live).
class PulseDot extends StatefulWidget {
  final Color color;
  const PulseDot({super.key, this.color = Colors.greenAccent});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(color: widget.color.withOpacity(0.55 * (1 - t)), blurRadius: 6 + (t * 8), spreadRadius: t * 3),
            ],
          ),
        );
      },
    );
  }
}

/// Gauge setengah lingkaran ala panel HMI industri, menunjukkan beban
/// relatif terhadap kapasitas maksimum jembatan timbang.
///
/// Memakai AspectRatio (bukan LayoutBuilder) karena widget ini dipakai di
/// dalam IntrinsicHeight pada layout lebar (tablet/landscape), dan
/// LayoutBuilder tidak mendukung perhitungan intrinsic (akan melempar error).
class WeighGauge extends StatelessWidget {
  final int berat;
  final int kapasitas;
  final Color color;

  const WeighGauge({super.key, required this.berat, this.kapasitas = kKapasitasMaksimum, this.color = Colors.greenAccent});

  @override
  Widget build(BuildContext context) {
    final target = (berat / kapasitas).clamp(0.0, 1.0).toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: const Duration(milliseconds: 650),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return AspectRatio(
          aspectRatio: 1.85,
          child: CustomPaint(painter: _GaugePainter(percent: value, color: color)),
        );
      },
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double percent;
  final Color color;
  _GaugePainter({required this.percent, required this.color});

  static const double _strokeWidth = 12.0;
  static const double _tickAllowance = 14.0; // ruang di bawah garis pusat untuk tanda batas

  @override
  void paint(Canvas canvas, Size size) {
    // Radius dibatasi oleh lebar DAN tinggi kanvas, sehingga busur tidak
    // pernah meluber keluar area gambarnya sendiri.
    final radius = math.min(
      (size.width - _strokeWidth) / 2,
      size.height - _strokeWidth / 2 - _tickAllowance,
    );
    final center = Offset(size.width / 2, _strokeWidth / 2 + radius);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = Colors.white.withOpacity(0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    final value = Paint()
      ..shader = LinearGradient(colors: [color.withOpacity(0.55), color]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, track);
    canvas.drawArc(rect, math.pi, math.pi * percent.clamp(0.0, 1.0).toDouble(), false, value);

    // Tanda batas kiri/kanan: diletakkan tepat di bawah UJUNG busur, yaitu
    // pada garis pusat (center.dy). Sebelumnya memakai rect.bottom yang
    // adalah dasar lingkaran penuh, sehingga tanda tergambar di luar kanvas.
    final tick = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(center.dx - radius, center.dy + 7), Offset(center.dx - radius, center.dy + 13), tick);
    canvas.drawLine(Offset(center.dx + radius, center.dy + 7), Offset(center.dx + radius, center.dy + 13), tick);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.percent != percent || oldDelegate.color != color;
}

/// Panel display berat ala panel HMI industri — angka besar, kontras tinggi,
/// gauge kapasitas animasi, mudah dibaca dari jarak jauh / di bawah sinar matahari.
class LiveWeightDisplay extends StatelessWidget {
  final int berat;
  final String label;
  final Color accent;

  const LiveWeightDisplay({super.key, required this.berat, this.label = 'Berat Masuk Real-Time', this.accent = Colors.greenAccent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 22),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.black.withOpacity(0.4), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 14, offset: const Offset(0, 7))],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PulseDot(color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 1.6)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              '$berat',
              style: TextStyle(color: accent, fontSize: 56, fontWeight: FontWeight.w900, fontFamily: 'monospace', letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 2),
          const Text('KILOGRAM', style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 2)),
          const SizedBox(height: 16),
          WeighGauge(berat: berat, color: accent),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('0 KG', style: TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w700)),
              Text('KAPASITAS ${kKapasitasMaksimum ~/ 1000} TON',
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Chip status transaksi (PENDING / SELESAI) dengan warna solid dan tegas,
/// disertai denyut halus selagi status masih menunggu.
class StatusChip extends StatelessWidget {
  final bool isSelesai;
  const StatusChip({super.key, required this.isSelesai});

  @override
  Widget build(BuildContext context) {
    final color = isSelesai ? const Color(0xFF16A34A) : const Color(0xFFEA7C17);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSelesai ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded, size: 14, color: color),
          const SizedBox(width: 5),
          Text(isSelesai ? 'SELESAI' : 'MENUNGGU',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.4)),
        ],
      ),
    );
    if (isSelesai) return chip;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.85, end: 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: chip,
    );
  }
}

/// Baris ringkasan angka di dalam kartu ringkasan (label kiri, nilai kanan).
class SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  const SummaryRow({super.key, required this.label, required this.value, this.emphasize = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = emphasize ? AppTheme.primaryGreen : theme.textTheme.bodyLarge?.color;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: Padding(
        key: ValueKey<String>('$label-$value'),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              flex: 2,
              child: Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: emphasize ? 20 : 15, fontWeight: FontWeight.w800, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Diagram alur proses penimbangan (MASUK → ISI MUATAN → KELUAR → SELESAI),
/// tahap aktif disorot dan tersambung dengan garis progres animasi.
class ProcessStepper extends StatelessWidget {
  final int activeStep; // 0..3
  const ProcessStepper({super.key, required this.activeStep});

  static const _steps = ['MASUK', 'ISI MUATAN', 'KELUAR', 'SELESAI'];
  static const _icons = [
    Icons.local_shipping_rounded,
    Icons.inventory_2_rounded,
    Icons.exit_to_app_rounded,
    Icons.task_alt_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(_steps.length * 2 - 1, (i) {
            if (i.isOdd) {
              // Garis penghubung antar tahap — diberi flex lebih kecil & dijaga
              // agar tidak pernah memaksa Row melebihi lebar layar (anti "offside").
              final leftStepDone = (i ~/ 2) < activeStep;
              return Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    height: 3,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: leftStepDone ? AppTheme.primaryGreen : (isDark ? AppTheme.slate700 : Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              );
            }
            final idx = i ~/ 2;
            final isDone = idx < activeStep;
            final isActive = idx == activeStep;
            final color = isDone || isActive ? AppTheme.primaryGreen : (isDark ? AppTheme.slate700 : Colors.grey.shade300);
            // Setiap tahap juga dibungkus Expanded (flex lebih besar dari garis
            // penghubung) sehingga labelnya tidak pernah overflow ke luar Card,
            // berapa pun lebar layar / panjang teks labelnya.
            return Expanded(
              flex: 3,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutBack,
                    width: isActive ? 38 : 32,
                    height: isActive ? 38 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone ? AppTheme.primaryGreen : (isActive ? color.withOpacity(0.16) : Colors.transparent),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(isDone ? Icons.check_rounded : _icons[idx], size: isActive ? 18 : 15, color: isDone ? Colors.white : color),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _steps[idx],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                          letterSpacing: 0.4,
                          color: isDone || isActive ? AppTheme.primaryGreen : theme.textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Bungkus konten agar tampilan tetap rapi & responsif di layar lebar
/// (tablet / desktop), dengan lebar maksimum dan padding adaptif.
class ResponsiveScaffold extends StatelessWidget {
  final Widget child;
  const ResponsiveScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 680;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 900 : constraints.maxWidth),
            child: Padding(padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 0), child: child),
          ),
        );
      },
    );
  }
}

/// Animasi masuk (fade + slide) bertahap untuk item daftar, memberi kesan halus.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, required this.index});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
  Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
  }
}

// =======================================================================
// 1. SCREEN TIMBANG MASUK (TARA & INPUT FORM LENGKAP)
// =======================================================================
class TimbangMasukScreen extends StatefulWidget {
  const TimbangMasukScreen({super.key});

  @override
  State<TimbangMasukScreen> createState() => _TimbangMasukScreenState();
}

class _TimbangMasukScreenState extends State<TimbangMasukScreen> {
  final _nopolCtrl = TextEditingController();
  final _tipeCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _supirCtrl = TextEditingController();
  final _produkCtrl = TextEditingController();

  int beratLive = 0;
  bool _menyimpan = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchBeratArduino());
    fetchBeratArduino();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nopolCtrl.dispose();
    _tipeCtrl.dispose();
    _customerCtrl.dispose();
    _supirCtrl.dispose();
    _produkCtrl.dispose();
    super.dispose();
  }

  Future<void> fetchBeratArduino() async {
    final berat = await ambilBeratPerangkat();
    if (berat != null && mounted) setState(() => beratLive = berat);
  }

  Future<void> simpanTara() async {
    if (_nopolCtrl.text.trim().isEmpty ||
        _tipeCtrl.text.trim().isEmpty ||
        _customerCtrl.text.trim().isEmpty ||
        _supirCtrl.text.trim().isEmpty ||
        _produkCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harap lengkapi seluruh data pada form.')),
      );
      return;
    }

    // Cegah tara tersimpan sebagai 0 KG karena timbangan belum terbaca / terputus.
    if (beratLive <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berat belum terbaca (0 KG). Pastikan perangkat timbangan terhubung.')),
      );
      return;
    }

    // Kunci tombol selagi menyimpan supaya ketukan ganda tidak membuat
    // dua catatan tara untuk satu kendaraan yang sama.
    setState(() => _menyimpan = true);
    try {
      await DatabaseHelper.instance.insertTimbangMasuk(
        nopol: _nopolCtrl.text.trim(),
        tipeKendaraan: _tipeCtrl.text.trim(),
        customer: _customerCtrl.text.trim(),
        supir: _supirCtrl.text.trim(),
        produk: _produkCtrl.text.trim(),
        tara: beratLive,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan data: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _menyimpan = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Data timbang masuk berhasil disimpan.')),
    );

    _nopolCtrl.clear();
    _tipeCtrl.clear();
    _customerCtrl.clear();
    _supirCtrl.clear();
    _produkCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const IndustrialHeader(
        title: 'TIMBANG MASUK',
        subtitle: 'Berat masuk & data kendaraan',
        actions: [HeaderOverflowMenu(), SizedBox(width: 4)],
      ),
      body: Column(
        children: [
          const LicenseWarningBar(),
          Expanded(
            child: ResponsiveScaffold(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 640;
                    final display = LiveWeightDisplay(berat: beratLive);
                    final form = _buildFormCard();
                    if (!isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const ProcessStepper(activeStep: 0),
                          const SizedBox(height: 16),
                          display,
                          const SizedBox(height: 24),
                          form,
                          const SizedBox(height: 22),
                          _buildSubmitButton(),
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ProcessStepper(activeStep: 0),
                        const SizedBox(height: 16),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: display),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [form, const SizedBox(height: 22), _buildSubmitButton()],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DATA KENDARAAN & MUATAN', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 14),
            TextField(
              controller: _nopolCtrl,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nomor Polisi (Nopol)', prefixIcon: Icon(Icons.local_shipping_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _tipeCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Tipe Kendaraan (mis. Engkel / Fuso)', prefixIcon: Icon(Icons.fire_truck_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _customerCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nama Customer', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _supirCtrl,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nama Supir', prefixIcon: Icon(Icons.badge_outlined)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _produkCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => simpanTara(),
              decoration: const InputDecoration(labelText: 'Nama Produk (mis. TBS Sawit)', prefixIcon: Icon(Icons.eco_outlined)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return ElevatedButton.icon(
      onPressed: _menyimpan ? null : simpanTara,
      icon: _menyimpan
          ? const SizedBox(
          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.save_rounded),
      label: Text(_menyimpan ? 'MENYIMPAN...' : 'SIMPAN DATA'),
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen, foregroundColor: Colors.white),
    );
  }
}

// =======================================================================
// 2. SCREEN TIMBANG KELUAR (BRUTO & NETTO)
// =======================================================================
class TimbangKeluarScreen extends StatefulWidget {
  const TimbangKeluarScreen({super.key});

  @override
  State<TimbangKeluarScreen> createState() => _TimbangKeluarScreenState();
}

class _TimbangKeluarScreenState extends State<TimbangKeluarScreen> {
  int beratLive = 0;
  List<Map<String, dynamic>> listPending = [];
  int? selectedId;
  bool _menyimpan = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => fetchBeratArduino());
    fetchBeratArduino();
    loadTrukPending();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> fetchBeratArduino() async {
    final berat = await ambilBeratPerangkat();
    if (berat != null && mounted) setState(() => beratLive = berat);
  }

  Future<void> loadTrukPending() async {
    final data = await DatabaseHelper.instance.getTrukPending();
    if (!mounted) return;
    setState(() {
      listPending = data;
      if (!listPending.any((element) => element['id'] == selectedId)) {
        selectedId = null;
      }
    });
  }

  Future<void> simpanBruto() async {
    if (selectedId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih kendaraan yang berstatus menunggu terlebih dahulu.')),
      );
      return;
    }

    final trukSelected = listPending.firstWhere((element) => element['id'] == selectedId);
    final tara = (trukSelected['tara'] as num?)?.toInt() ?? 0;

    // Berat keluar (bruto) harus lebih besar dari berat masuk (tara),
    // kalau tidak netto menjadi nol/negatif.
    if (beratLive <= tara) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Berat keluar ($beratLive KG) harus lebih besar dari berat masuk ($tara KG).')),
      );
      return;
    }

    setState(() => _menyimpan = true);
    try {
      await DatabaseHelper.instance.updateTimbangKeluar(selectedId!, beratLive, tara);
    } catch (e) {
      if (!mounted) return;
      setState(() => _menyimpan = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan penimbangan keluar: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _menyimpan = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Penimbangan keluar berhasil. Transaksi selesai.')),
    );
    loadTrukPending();
  }

  Future<void> _pilihKendaraan() async {
    if (listPending.isEmpty) return;
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // Padding viewInsets agar sheet naik di atas keyboard saat mengetik pencarian.
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _KendaraanSearchSheet(daftar: listPending),
      ),
    );
    if (result != null && mounted) {
      setState(() => selectedId = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? selectedTrukData;
    if (selectedId != null) {
      final match = listPending.where((e) => e['id'] == selectedId);
      if (match.isNotEmpty) selectedTrukData = match.first;
    }

    final int taraVal = (selectedTrukData?['tara'] as num?)?.toInt() ?? 0;
    final int nettoVal = selectedTrukData != null ? (beratLive - taraVal) : 0;

    return Scaffold(
      appBar: IndustrialHeader(
        title: 'TIMBANG KELUAR',
        subtitle: 'Berat keluar & netto',
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: loadTrukPending, tooltip: 'Muat Ulang'),
          const HeaderOverflowMenu(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const LicenseWarningBar(),
          Expanded(
            child: ResponsiveScaffold(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(18.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 640;
                    final display = LiveWeightDisplay(berat: beratLive, label: 'BERAT BRUTO REAL-TIME', accent: AppTheme.accentAmber);
                    final panel = _buildSelectionAndSummary(selectedTrukData, taraVal, nettoVal);
                    if (!isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ProcessStepper(activeStep: selectedId == null ? 1 : 2),
                          const SizedBox(height: 16),
                          display,
                          const SizedBox(height: 20),
                          panel,
                        ],
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ProcessStepper(activeStep: selectedId == null ? 1 : 2),
                        const SizedBox(height: 16),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [Expanded(child: display), const SizedBox(width: 18), Expanded(child: panel)],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionAndSummary(Map<String, dynamic>? selectedTrukData, int taraVal, int nettoVal) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('PILIH KENDARAAN (STATUS MENUNGGU)', style: Theme.of(context).textTheme.labelLarge)),
            if (listPending.isNotEmpty)
              Text('${listPending.length} MENUNGGU',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 10),
        // Selector kendaraan dengan pencarian: menghindari perlu scroll panjang
        // pada dropdown biasa ketika truk yang menunggu jumlahnya banyak.
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: listPending.isEmpty ? null : _pilihKendaraan,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_rounded, color: Theme.of(context).textTheme.bodyMedium?.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nomor Polisi Kendaraan', style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          selectedTrukData != null
                              ? '${selectedTrukData['nopol']} — ${selectedTrukData['customer']} (${selectedTrukData['produk']})'
                              : (listPending.isEmpty
                              ? 'Tidak ada kendaraan berstatus menunggu'
                              : 'Ketuk untuk mencari & memilih kendaraan'),
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.search_rounded, color: listPending.isEmpty ? Colors.grey : AppTheme.primaryGreen),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('RINGKASAN HASIL PENIMBANGAN', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              children: [
                SummaryRow(label: 'Nomor Polisi', value: '${selectedTrukData?['nopol'] ?? '—'}'),
                const Divider(),
                SummaryRow(
                  label: 'Tipe / Supir',
                  value: '${selectedTrukData?['tipe_kendaraan'] ?? '—'} / ${selectedTrukData?['supir'] ?? '—'}',
                ),
                const Divider(),
                SummaryRow(
                  label: 'Produk / Customer',
                  value: '${selectedTrukData?['produk'] ?? '—'} / ${selectedTrukData?['customer'] ?? '—'}',
                ),
                const Divider(),
                SummaryRow(label: 'Berat Keluar', value: '$beratLive KG'),
                const Divider(),
                SummaryRow(label: 'Berat Masuk', value: '$taraVal KG'),
                const Divider(),
                SummaryRow(label: 'BERAT NETTO', value: '$nettoVal KG', emphasize: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        ElevatedButton.icon(
          onPressed: _menyimpan ? null : simpanBruto,
          icon: _menyimpan
              ? const SizedBox(
              width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_rounded),
          label: Text(_menyimpan ? 'MENYIMPAN...' : 'SIMPAN & SELESAIKAN'),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accentOrange, foregroundColor: Colors.white),
        ),
      ],
    );
  }
}

/// Bottom sheet berisi kotak pencarian + daftar kendaraan berstatus menunggu.
/// Dipakai agar user tidak perlu men-scroll dropdown panjang saat truk banyak,
/// cukup ketik nopol / customer / supir / produk untuk menyaring daftar.
class _KendaraanSearchSheet extends StatefulWidget {
  final List<Map<String, dynamic>> daftar;
  const _KendaraanSearchSheet({required this.daftar});

  @override
  State<_KendaraanSearchSheet> createState() => _KendaraanSearchSheetState();
}

class _KendaraanSearchSheetState extends State<_KendaraanSearchSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<Map<String, dynamic>> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.daftar;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    final q = query.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = widget.daftar;
      } else {
        _filtered = widget.daftar.where((item) {
          final gabungan = [
            item['nopol'],
            item['customer'],
            item['supir'],
            item['produk'],
            item['tipe_kendaraan'],
          ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
          return gabungan.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.slate800 : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                child: Row(
                  children: [
                    Expanded(child: Text('CARI KENDARAAN', style: theme.textTheme.titleLarge)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Ketik nopol, customer, supir, atau produk...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'Kendaraan tidak ditemukan.',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
                    : ListView.separated(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _filtered[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppTheme.primaryGreen.withOpacity(0.12),
                        foregroundColor: AppTheme.primaryGreen,
                        child: const Icon(Icons.local_shipping_rounded, size: 20),
                      ),
                      title: Text('${item['nopol']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${item['customer']} · ${item['produk']} · Supir: ${item['supir']}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, item['id'] as int),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =======================================================================
// 3. SCREEN RIWAYAT & EXPORT EXCEL & PRINT BLUETOOTH
// =======================================================================
class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  List<Map<String, dynamic>> listTransaksi = [];
  bool _loading = true;

  final TextEditingController _searchCtrl = TextEditingController();

  // Nilai filter status disamakan PERSIS dengan yang tersimpan di database
  // ('PENDING' / 'SELESAI').
  String _filterStatus = 'SEMUA'; // SEMUA, PENDING, SELESAI
  int? _filterTahun; // null = semua tahun
  int? _filterBulan; // null = semua bulan (1-12)

  @override
  void initState() {
    super.initState();
    loadRiwayat();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Menampilkan '—' untuk kolom yang belum terisi (transaksi masih menunggu),
  /// supaya tidak muncul tulisan "null KG" pada kartu riwayat.
  String _kg(dynamic nilai) => nilai == null ? '—' : '$nilai KG';

  /// Mengurai string 'waktu' (format 'yyyy-MM-dd HH:mm:ss') menjadi DateTime.
  /// Mengembalikan null jika formatnya tak terduga, supaya filter tanggal
  /// tidak pernah membuat aplikasi error.
  DateTime? _parseWaktu(dynamic waktu) {
    if (waktu == null) return null;
    try {
      return DateFormat('yyyy-MM-dd HH:mm:ss').parseStrict(waktu.toString());
    } catch (_) {
      return null;
    }
  }

  /// Daftar tahun yang benar-benar ada pada data, untuk mengisi dropdown
  /// filter tahun (diurutkan dari yang terbaru).
  List<int> get _tahunTersedia {
    final tahunSet = <int>{};
    for (final item in listTransaksi) {
      final dt = _parseWaktu(item['waktu']);
      if (dt != null) tahunSet.add(dt.year);
    }
    final list = tahunSet.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Daftar transaksi setelah disaring berdasarkan kata kunci pencarian
  /// (nopol / customer / supir / produk / tipe kendaraan), status, dan
  /// periode tanggal (tahun & bulan).
  List<Map<String, dynamic>> get _filteredTransaksi {
    final query = _searchCtrl.text.trim().toLowerCase();
    return listTransaksi.where((item) {
      if (_filterStatus != 'SEMUA' && item['status'] != _filterStatus) return false;

      if (_filterTahun != null || _filterBulan != null) {
        final dt = _parseWaktu(item['waktu']);
        if (dt == null) return false;
        if (_filterTahun != null && dt.year != _filterTahun) return false;
        if (_filterBulan != null && dt.month != _filterBulan) return false;
      }

      if (query.isEmpty) return true;
      final gabungan = [
        item['nopol'],
        item['customer'],
        item['supir'],
        item['produk'],
        item['tipe_kendaraan'],
      ].map((e) => (e ?? '').toString().toLowerCase()).join(' ');
      return gabungan.contains(query);
    }).toList();
  }

  bool get _adaFilterAktif =>
      _filterStatus != 'SEMUA' ||
          _filterTahun != null ||
          _filterBulan != null ||
          _searchCtrl.text.trim().isNotEmpty;

  void _resetFilter() {
    setState(() {
      _searchCtrl.clear();
      _filterStatus = 'SEMUA';
      _filterTahun = null;
      _filterBulan = null;
    });
  }

  Future<void> loadRiwayat() async {
    setState(() => _loading = true);
    final data = await DatabaseHelper.instance.getSemuaTransaksi();
    if (!mounted) return;
    setState(() {
      listTransaksi = data;
      // Kalau tahun yang sedang difilter sudah tidak ada pada data terbaru,
      // kosongkan filternya agar DropdownButton tidak error nilai tak dikenal.
      if (_filterTahun != null && !_tahunTersedia.contains(_filterTahun)) {
        _filterTahun = null;
      }
      _loading = false;
    });
  }

  void _showSnack(String message, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: duration ?? const Duration(seconds: 4)),
    );
  }

  Future<void> cetakBluetooth(Map<String, dynamic> item) async {
    try {
      final isConnected = await PrintBluetoothThermal.connectionStatus;
      if (!isConnected) {
        final List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
        if (devices.isEmpty) {
          _showSnack('Tidak ditemukan printer Bluetooth yang terhubung.');
          return;
        }
        final ok = await PrintBluetoothThermal.connect(macPrinterAddress: devices.first.macAdress);
        if (!ok) {
          _showSnack('Gagal terhubung ke printer Bluetooth.');
          return;
        }
      }

      final List<int> bytes = [];
      bytes.addAll(utf8.encode("      SISTEM TIMBANGAN PORTABLE\n"));
      bytes.addAll(utf8.encode("         NOTA TIMBANGAN\n"));
      bytes.addAll(utf8.encode("================================\n"));
      bytes.addAll(utf8.encode("No. Transaksi : TMB-${item['id']}\n"));
      bytes.addAll(utf8.encode("Waktu         : ${item['waktu'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("No. Kendaraan : ${item['nopol'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("Tipe Kend.    : ${item['tipe_kendaraan'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("Customer      : ${item['customer'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("Supir         : ${item['supir'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("Produk        : ${item['produk'] ?? '-'}\n"));
      bytes.addAll(utf8.encode("--------------------------------\n"));
      bytes.addAll(utf8.encode("Berat Keluar  : ${item['bruto'] ?? 0} KG\n"));
      bytes.addAll(utf8.encode("Berat Masuk   : ${item['tara'] ?? 0} KG\n"));
      bytes.addAll(utf8.encode("BERAT NETTO   : ${item['netto'] ?? 0} KG\n"));
      bytes.addAll(utf8.encode("================================\n"));
      bytes.addAll(utf8.encode("Sopir                  Petugas\n\n\n"));
      bytes.addAll(utf8.encode("(...........)         (...........)\n\n\n"));

      await PrintBluetoothThermal.writeBytes(bytes);
      _showSnack('Mencetak nota timbangan via Bluetooth...');
    } catch (e) {
      _showSnack('Gagal mencetak nota: $e');
    }
  }

  // Export mengikuti filter yang sedang aktif (status, tanggal, dan kata
  // kunci pencarian), bukan lagi selalu seluruh data di database.
  Future<void> exportExcel() async {
    final dataToExport = _filteredTransaksi;
    if (dataToExport.isEmpty) {
      _showSnack('Tidak ada data pada filter saat ini untuk diekspor.');
      return;
    }

    final String? path = await DatabaseHelper.instance.exportToExcel(data: dataToExport);
    if (path != null) {
      _showSnack('Berkas Excel (${dataToExport.length} data sesuai filter) tersimpan di: $path');
    } else {
      _showSnack('Gagal mengekspor data atau data masih kosong.');
    }
  }

  /// Bilah pencarian, filter status, filter periode (tahun & bulan), dan
  /// ringkasan jumlah data — ditampilkan di atas daftar riwayat supaya
  /// transaksi tertentu bisa langsung ditemukan tanpa menggulir panjang.
  Widget _buildSearchFilterBar() {
    final tahunTersedia = _tahunTersedia;
    final jumlahFiltered = _filteredTransaksi.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cari nopol, customer, supir, atau produk...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _filterChip('SEMUA', 'Semua'),
                const SizedBox(width: 8),
                _filterChip('PENDING', 'Menunggu'),
                const SizedBox(width: 8),
                _filterChip('SELESAI', 'Selesai'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildDropdownFilter<int?>(
                  value: _filterTahun,
                  icon: Icons.calendar_today_rounded,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Semua Tahun')),
                    ...tahunTersedia.map((t) => DropdownMenuItem<int?>(value: t, child: Text('$t'))),
                  ],
                  onChanged: (v) => setState(() => _filterTahun = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildDropdownFilter<int?>(
                  value: _filterBulan,
                  icon: Icons.event_rounded,
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Semua Bulan')),
                    ...List.generate(
                      12,
                          (i) => DropdownMenuItem<int?>(value: i + 1, child: Text(kNamaBulan[i])),
                    ),
                  ],
                  onChanged: (v) => setState(() => _filterBulan = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Menampilkan $jumlahFiltered dari ${listTransaksi.length} transaksi',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (_adaFilterAktif)
                TextButton.icon(
                  onPressed: _resetFilter,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                  label: const Text('RESET'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Kotak dropdown bergaya seragam dengan input lain di halaman ini,
  /// dipakai untuk filter tahun dan bulan.
  Widget _buildDropdownFilter<T>({
    required T value,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.slate700 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? AppTheme.slate700 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: theme.textTheme.bodyMedium?.color),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                value: value,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filterStatus == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filterStatus = value),
      selectedColor: AppTheme.primaryGreen.withOpacity(0.18),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? AppTheme.primaryGreen : Theme.of(context).textTheme.bodyLarge?.color,
      ),
      side: BorderSide(color: selected ? AppTheme.primaryGreen : Colors.grey.shade400),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: IndustrialHeader(
        title: 'RIWAYAT TRANSAKSI',
        subtitle: 'Catatan penimbangan',
        actions: [
          IconButton(icon: const Icon(Icons.file_download_rounded, color: Colors.white), onPressed: exportExcel, tooltip: 'Ekspor ke Excel'),
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white), onPressed: loadRiwayat, tooltip: 'Muat Ulang'),
          const HeaderOverflowMenu(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const LicenseWarningBar(),
          Expanded(
            child: ResponsiveScaffold(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : listTransaksi.isEmpty
                  ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inbox_rounded, size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text('Belum ada transaksi tercatat', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text('Data akan muncul setelah proses timbang selesai', style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              )
                  : Builder(
                builder: (context) {
                  final filtered = _filteredTransaksi;
                  return Column(
                    children: [
                      _buildSearchFilterBar(),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Tidak ada transaksi yang cocok', style: Theme.of(context).textTheme.titleMedium),
                                const SizedBox(height: 4),
                                Text('Coba ubah kata kunci atau filter status',
                                    style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        )
                            : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final bool isSelesai = item['status'] == 'SELESAI';
                            return FadeSlideIn(
                              index: index,
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${item['nopol']} · ${item['tipe_kendaraan']}',
                                                    style: Theme.of(context).textTheme.titleMedium),
                                                const SizedBox(height: 2),
                                                Text('${item['produk']} — ${item['customer']}',
                                                    style: Theme.of(context).textTheme.bodyMedium),
                                              ],
                                            ),
                                          ),
                                          StatusChip(isSelesai: isSelesai),
                                        ],
                                      ),
                                      const Divider(height: 22),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('Supir: ${item['supir']}', style: Theme.of(context).textTheme.bodyMedium),
                                                const SizedBox(height: 3),
                                                Text('Tara: ${_kg(item['tara'])} · Bruto: ${_kg(item['bruto'])}',
                                                    style: Theme.of(context).textTheme.bodyMedium),
                                                const SizedBox(height: 3),
                                                Text('${item['waktu']}', style: Theme.of(context).textTheme.bodyMedium),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                _kg(item['netto']),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 17,
                                                  color: isSelesai ? AppTheme.primaryGreen : Colors.grey,
                                                ),
                                              ),
                                              const Text('NETTO',
                                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.6)),
                                            ],
                                          ),
                                        ],
                                      ),
                                      if (isSelesai) ...[
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: OutlinedButton.icon(
                                            onPressed: () => cetakBluetooth(item),
                                            icon: const Icon(Icons.print_rounded, size: 18),
                                            label: const Text('CETAK NOTA'),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: AppTheme.primaryGreen,
                                              side: const BorderSide(color: AppTheme.primaryGreen),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
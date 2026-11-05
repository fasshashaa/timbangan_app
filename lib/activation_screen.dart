import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'license_service.dart';
import 'license_database.dart';
import 'main.dart'; // reuse AppTheme, ThemeToggleButton & palet warna SIWEIGH

class ActivationScreen extends StatefulWidget {
  final VoidCallback onActivated;
  final String? initialErrorMessage;

  const ActivationScreen({
    super.key,
    required this.onActivated,
    this.initialErrorMessage,
  });

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> with SingleTickerProviderStateMixin {
  String _deviceId = "Memuat ID Perangkat...";
  final TextEditingController _keyController = TextEditingController();
  String? _errorMessage;
  bool _isLoading = false;
  bool _copied = false;

  late final AnimationController _entrance =
  AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
  late final Animation<double> _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
  late final Animation<Offset> _slide =
  Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _errorMessage = widget.initialErrorMessage;
    _loadDeviceId();
  }

  @override
  void dispose() {
    _entrance.dispose();
    _keyController.dispose();
    super.dispose();
  }

  void _loadDeviceId() async {
    String id = await LicenseService.getDeviceId();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
    });
  }

  Future<void> _copyDeviceId() async {
    await Clipboard.setData(ClipboardData(text: _deviceId));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Device ID berhasil disalin!')),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _verifyAndActivate() async {
    FocusScope.of(context).unfocus();

    final inputKey = _keyController.text.trim().replaceAll('-', '').replaceAll(' ', '').toUpperCase();

    if (inputKey.length != 16) {
      setState(() => _errorMessage = "Kode Lisensi harus 16 karakter!");
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    if (!LicenseService.validateKey(_deviceId, inputKey)) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Kode Lisensi tidak valid untuk perangkat ini!";
      });
      return;
    }

    await LicenseDatabase.instance.saveLicense(_deviceId, inputKey);
    if (!mounted) return;
    widget.onActivated();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Stack(
        children: [
          Container(decoration: const BoxDecoration(gradient: AppTheme.headerGradient)),
          Positioned(top: -70, right: -50, child: _DecorCircle(size: 200, opacity: 0.08)),
          Positioned(bottom: -90, left: -70, child: _DecorCircle(size: 260, opacity: 0.07)),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, top: 4),
                child: const ThemeToggleButton(),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(
                  position: _slide,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
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
                          child: const Icon(Icons.verified_user_rounded, size: 38, color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'AKTIVASI PERANGKAT',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'AKTIVASI SEKALI UNTUK MENGUNCI LISENSI KE PERANGKAT INI',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 26),
                        Card(
                          color: isDark ? AppTheme.slate800 : Colors.white,
                          elevation: 10,
                          shadowColor: Colors.black.withOpacity(0.3),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          child: Padding(
                            padding: const EdgeInsets.all(22.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildStepGuide(context),
                                const SizedBox(height: 22),
                                Text('DEVICE ID PERANGKAT', style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 10),
                                _buildDeviceIdBox(context),
                                const SizedBox(height: 22),
                                Text('KODE LISENSI', style: Theme.of(context).textTheme.labelLarge),
                                const SizedBox(height: 10),
                                _buildKeyField(context),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  alignment: Alignment.topCenter,
                                  child: _errorMessage == null
                                      ? const SizedBox(width: double.infinity, height: 0)
                                      : Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: _buildErrorBanner(context),
                                  ),
                                ),
                                const SizedBox(height: 22),
                                _buildActivateButton(),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Simpan baik-baik Kode Lisensi Anda.',
                          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Panduan singkat 3 langkah aktivasi. Setiap langkah & garis penghubung
  /// dibungkus Expanded (rasio 3:2) dan labelnya pakai FittedBox agar tidak
  /// pernah overflow, berapa pun lebar layarnya.
  Widget _buildStepGuide(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      (Icons.copy_rounded, 'SALIN ID'),
      (Icons.send_rounded, 'KIRIM ADMIN'),
      (Icons.key_rounded, 'MASUKKAN KODE'),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                color: AppTheme.primaryGreen.withOpacity(0.35),
              ),
            ),
          );
        }
        final (icon, label) = steps[i ~/ 2];
        return Expanded(
          flex: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.primaryGreen.withOpacity(0.14),
                  border: Border.all(color: AppTheme.primaryGreen, width: 1.6),
                ),
                child: Icon(icon, size: 16, color: AppTheme.primaryGreen),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                      color: theme.textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildDeviceIdBox(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final loaded = !_deviceId.startsWith('Memuat');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.slate700 : const Color(0xFFF1F5F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppTheme.slate700 : Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.memory_rounded, size: 20, color: AppTheme.primaryGreen),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _deviceId,
              style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.6),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: loaded ? _copyDeviceId : null,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                child: Icon(
                  _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
                  key: ValueKey<bool>(_copied),
                  size: 20,
                  color: _copied ? AppTheme.primaryGreen : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyField(BuildContext context) {
    return TextField(
      controller: _keyController,
      textCapitalization: TextCapitalization.characters,
      maxLength: 17, // 16 karakter kode + 1 tanda pisah otomatis
      inputFormatters: [_LicenseKeyFormatter()],
      onChanged: (_) {
        if (_errorMessage != null) setState(() => _errorMessage = null);
      },
      onSubmitted: (_) => _isLoading ? null : _verifyAndActivate(),
      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w800, letterSpacing: 1.1),
      decoration: const InputDecoration(
        labelText: 'Kode Lisensi',
        hintText: 'YYYYMMDD-XXXXXXXX',
        counterText: '',
        prefixIcon: Icon(Icons.vpn_key_rounded),
        border: OutlineInputBorder(),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 18, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage ?? '',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivateButton() {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _verifyAndActivate,
      icon: _isLoading
          ? const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
      )
          : const Icon(Icons.lock_open_rounded),
      label: Text(_isLoading ? 'MEMVERIFIKASI...' : 'AKTIFKAN LISENSI'),
      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryGreen, foregroundColor: Colors.white),
    );
  }
}

/// Lingkaran dekoratif transparan di latar gradient, senada dengan LoginScreen.
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

/// Memformat input kode lisensi secara otomatis: huruf besar semua, tanpa
/// spasi/strip ganda, dan menyisipkan satu tanda pisah setelah 8 karakter
/// pertama (YYYYMMDD-XXXXXXXX) supaya lebih mudah dibaca saat mengetik.
class _LicenseKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll('-', '').replaceAll(' ', '').toUpperCase();
    if (text.length > 16) text = text.substring(0, 16);

    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 8) buffer.write('-');
      buffer.write(text[i]);
    }
    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
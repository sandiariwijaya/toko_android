import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/notify.dart';

/// Scan barcode memakai kamera HP.
/// [continuous] = true: kamera tetap terbuka untuk scan banyak barang
/// (setiap hasil dikirim ke [onCode], hasilnya berupa pesan singkat di layar).
class ScannerPage extends StatefulWidget {
  final bool continuous;
  final Future<String?> Function(String code)? onCode;
  final String title;
  const ScannerPage({super.key, this.continuous = false, this.onCode, this.title = 'Scan Barcode'});

  /// Scan satu kali, kembalikan kode
  static Future<String?> scanOnce(BuildContext context, {String title = 'Scan Barcode'}) async {
    if (!await _permission()) return null;
    if (!context.mounted) return null;
    return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => ScannerPage(title: title)));
  }

  /// Scan terus-menerus
  static Future<void> scanMany(BuildContext context, Future<String?> Function(String code) onCode, {String title = 'Scan Barcode'}) async {
    if (!await _permission()) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScannerPage(continuous: true, onCode: onCode, title: title)));
  }

  static Future<bool> _permission() async {
    final st = await Permission.camera.request();
    if (st.isGranted) return true;
    Notify.error('Izin kamera ditolak. Aktifkan di Pengaturan HP > Aplikasi > Izin.');
    if (st.isPermanentlyDenied) await openAppSettings();
    return false;
  }

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final MobileScannerController _c = MobileScannerController(detectionSpeed: DetectionSpeed.normal);
  String _last = '';
  DateTime _lastAt = DateTime(2000);
  bool _busy = false;
  bool _done = false;
  String _msg = '';
  int _count = 0;
  bool _torch = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture cap) async {
    if (_busy || _done) return;
    String? code;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v != null && v.trim().isNotEmpty) {
        code = v.trim();
        break;
      }
    }
    if (code == null) return;
    final now = DateTime.now();
    if (code == _last && now.difference(_lastAt).inMilliseconds < 1800) return;
    _last = code;
    _lastAt = now;
    HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
    if (!widget.continuous) {
      _done = true;
      Navigator.of(context).pop(code);
      return;
    }
    _busy = true;
    final m = await widget.onCode?.call(code);
    _count++;
    if (mounted) setState(() => _msg = m ?? code!);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Lampu',
            icon: Icon(_torch ? Icons.flash_on_rounded : Icons.flash_off_rounded),
            onPressed: () async {
              await _c.toggleTorch();
              setState(() => _torch = !_torch);
            },
          ),
          IconButton(tooltip: 'Ganti kamera', icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _c.switchCamera()),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(child: MobileScanner(controller: _c, onDetect: _onDetect)),
          Center(
            child: Container(
              width: 280,
              height: 170,
              decoration: BoxDecoration(
                border: Border.all(color: cs.primary, width: 3),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                if (_msg.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                    child: Row(children: [
                      Icon(Icons.check_circle_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_msg, style: const TextStyle(fontWeight: FontWeight.w600))),
                    ]),
                  ),
                const SizedBox(height: 10),
                Text(
                  widget.continuous ? 'Arahkan kamera ke barcode. Sudah scan: $_count' : 'Arahkan kamera ke barcode',
                  style: const TextStyle(color: Colors.white70),
                ),
                if (widget.continuous) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.done_rounded),
                    label: const Text('Selesai'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

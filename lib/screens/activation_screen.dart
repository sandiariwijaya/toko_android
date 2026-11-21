import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../db/database.dart';
import '../services/activation.dart';
import '../utils/notify.dart';
import 'login_screen.dart';

/// Halaman pertama setelah install: memasukkan alamat server & kode aktivasi (butuh internet sekali).
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _kode = TextEditingController();
  final _url = TextEditingController();
  bool _proses = false;
  String? _error;
  String _id = '';

  @override
  void initState() {
    super.initState();
    Activation.deviceId().then((v) {
      if (mounted) setState(() => _id = v);
    });
    Activation.urlTersimpan().then((v) {
      if (mounted && _url.text.isEmpty) _url.text = v;
    });
  }

  @override
  void dispose() {
    _kode.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _aktifkan() async {
    if (_url.text.trim().isEmpty) {
      setState(() => _error = 'Isi alamat server aktivasi');
      return;
    }
    if (_kode.text.trim().length < 4) {
      setState(() => _error = 'Masukkan kode aktivasi');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _proses = true;
      _error = null;
    });
    try {
      final info = await Activation.aktifkan(_kode.text, url: _url.text);
      Activity.user = 'Sistem';
      await Activity.log('akses', 'Aktivasi aplikasi', 'Kode ${info.kode} • ${info.nama}');
      Activity.user = '';
      Notify.success('Aktivasi berhasil. Terdaftar atas nama ${info.nama}');
      final hasUser = await Repo.userCount() > 0;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => hasUser ? const LoginScreen() : const SetupOwnerScreen()),
      );
    } on AktivasiGagal catch (e) {
      if (mounted) setState(() => _error = e.pesan);
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.35)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/logo.png', width: 120, height: 120),
                  ),
                  const SizedBox(height: 12),
                  const Text('AKTIVASI APLIKASI',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 4),
                  Text('${AppConfig.appName} • sekali saja, butuh internet',
                      style: TextStyle(color: Colors.white.withAlpha(215), fontSize: 13)),
                  const SizedBox(height: 18),
                  Card(
                    elevation: 8,
                    color: cs.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Masukkan alamat server & kode aktivasi dari admin',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _url,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 13.5),
                          decoration: const InputDecoration(
                            labelText: 'Alamat server aktivasi',
                            hintText: 'domainanda.com/aktivasi-toko',
                            prefixIcon: Icon(Icons.link_rounded),
                            helperText: '/api.php ditambahkan otomatis (bisa http:// atau https://)',
                            helperStyle: TextStyle(fontSize: 10.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _kode,
                          textCapitalization: TextCapitalization.characters,
                          autocorrect: false,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]'))],
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                          decoration: const InputDecoration(
                            labelText: 'Kode aktivasi',
                            hintText: 'TOKO-XXXX-XXXX',
                            prefixIcon: Icon(Icons.vpn_key_rounded),
                          ),
                          onSubmitted: (_) => _aktifkan(),
                        ),
                        if (_error != null)
                          Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              Icon(Icons.error_outline_rounded, color: Colors.red.shade700, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!, style: TextStyle(color: Colors.red.shade900, fontSize: 12.5, height: 1.15)),
                              ),
                            ]),
                          ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 48,
                          child: FilledButton.icon(
                            onPressed: _proses ? null : _aktifkan,
                            icon: _proses
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.verified_user_rounded),
                            label: Text(_proses ? 'Menghubungi server...' : 'AKTIFKAN'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        InkWell(
                          onTap: _id.isEmpty
                              ? null
                              : () {
                                  Clipboard.setData(ClipboardData(text: _id));
                                  Notify.info('ID perangkat disalin');
                                },
                          child: Text('ID perangkat: $_id', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.5, color: cs.outline)),
                        ),
                        if (kKontakAdmin.isNotEmpty)
                          Text('Belum punya kode? Hubungi $kKontakAdmin',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: cs.outline)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Setelah aktif, aplikasi dapat dipakai tanpa internet.',
                      style: TextStyle(color: Colors.white.withAlpha(200), fontSize: 11.5)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

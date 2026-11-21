import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../config.dart';
import 'native.dart';

class InfoLisensi {
  final String kode;
  final String nama;
  final String tanggal;
  const InfoLisensi(this.kode, this.nama, this.tanggal);
}

class AktivasiGagal implements Exception {
  final String pesan;
  AktivasiGagal(this.pesan);
  @override
  String toString() => pesan;
}

/// Aktivasi sekali online (versi sederhana):
/// aplikasi mengirim kode + ID perangkat ke api.php, server mengecek kode di database,
/// jika "ok" aplikasi menyimpan status aktif di HP. Sesudahnya tidak perlu online lagi.
/// Status disimpan dengan checksum sederhana agar tidak mudah diubah manual.
/// Disimpan di file terpisah (tidak ikut backup database).
class Activation {
  static Map<String, dynamic>? _data;

  /// URL bawaan dari config.dart (kosong jika masih contoh).
  static String get urlBawaan => kAktivasiUrl.contains('DOMAIN-ANDA') ? '' : kAktivasiUrl;

  static Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File(p.join(d.path, 'aktivasi.json'));
  }

  static Future<Map<String, dynamic>> _load() async {
    if (_data != null) return _data!;
    try {
      final f = await _file();
      if (await f.exists()) {
        _data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return _data!;
      }
    } catch (_) {}
    _data = <String, dynamic>{};
    return _data!;
  }

  static Future<void> _save() async {
    final f = await _file();
    await f.writeAsString(jsonEncode(_data ?? {}), flush: true);
  }

  /// URL terakhir yang dipakai / diketik, atau URL bawaan.
  static Future<String> urlTersimpan() async {
    final m = await _load();
    final u = (m['url'] ?? '').toString();
    return u.isEmpty ? urlBawaan : u;
  }

  /// Rapikan URL ketikan: tambah https:// dan /api.php bila perlu.
  static String rapikanUrl(String u) {
    var s = u.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    if (!s.toLowerCase().endsWith('.php')) {
      s = s.endsWith('/') ? '${s}api.php' : '$s/api.php';
    }
    return s;
  }

  /// ID unik perangkat. Memakai ID Android (tetap sama walau aplikasi diinstal ulang,
  /// jadi install ulang di HP yang sama tidak menghabiskan kuota kode).
  static Future<String> deviceId() async {
    final m = await _load();
    var id = (m['device_id'] ?? '').toString();
    if (id.length >= 8) return id;
    final android = (await NativeX.deviceId()).replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (android.length >= 8) {
      id = 'TOKO-${android.toUpperCase()}';
    } else {
      final r = Random.secure();
      String hex(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
      id = 'TOKO-${hex(8)}-${hex(8)}-${hex(8)}'.toUpperCase();
    }
    m['device_id'] = id;
    await _save();
    return id;
  }

  /// Checksum lokal sederhana (bukan pengaman kuat).
  static String _cek(String data) => sha256.convert(utf8.encode('aplikasitoko-lokal-2026|$data')).toString();

  static InfoLisensi? _urai(String payload, String id) {
    final b = payload.split('|');
    // TOKO|v1|KODE|DEVICE|NAMA|TANGGAL
    if (b.length < 6 || b[0] != 'TOKO' || b[1] != 'v1') return null;
    if (b[3] != id) return null; // data aktivasi milik HP lain
    return InfoLisensi(b[2], b[4], b[5]);
  }

  /// Dipanggil saat aplikasi dibuka (offline). null = belum / tidak aktif.
  static Future<InfoLisensi?> cek() async {
    if (!kWajibAktivasi) return const InfoLisensi('-', 'Tanpa aktivasi', '-');
    final m = await _load();
    final payload = m['payload']?.toString();
    final sig = m['sig']?.toString();
    if (payload == null || sig == null) return null;
    final id = await deviceId();
    final info = _urai(payload, id);
    if (info == null || sig != _cek(payload)) return null;
    return info;
  }

  static Future<bool> isActive() async => (await cek()) != null;

  /// Aktivasi online (sekali). Melempar [AktivasiGagal] bila gagal.
  static Future<InfoLisensi> aktifkan(String kode, {String? url}) async {
    final alamat = rapikanUrl(url ?? await urlTersimpan());
    if (alamat.isEmpty) throw AktivasiGagal('Isi alamat server aktivasi.');
    final uri = Uri.tryParse(alamat);
    if (uri == null || uri.host.isEmpty) throw AktivasiGagal('Alamat server tidak valid.');
    final id = await deviceId();
    var model = await NativeX.deviceModel();
    if (model.trim().isEmpty) model = 'Android ${Platform.operatingSystemVersion}';
    if (model.length > 120) model = model.substring(0, 120);
    http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
            body: jsonEncode({
              'kode': kode.trim().toUpperCase(),
              'device_id': id,
              'info': model,
              'app': 'aplikasi_toko',
            }),
          )
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      throw AktivasiGagal('Server tidak merespons. Periksa koneksi internet lalu coba lagi.');
    } on SocketException {
      throw AktivasiGagal('Tidak ada koneksi internet / server tidak bisa dihubungi.');
    } catch (e) {
      throw AktivasiGagal('Gagal menghubungi server: $e');
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw AktivasiGagal('Balasan server tidak valid (HTTP ${res.statusCode}). Periksa alamat: $alamat');
    }
    if (j['ok'] != true) {
      throw AktivasiGagal((j['pesan'] ?? 'Aktivasi ditolak').toString());
    }
    String bersih(Object? v) => (v ?? '').toString().replaceAll('|', ' ').trim();
    final kodeOk = bersih(j['kode']).isEmpty ? kode.trim().toUpperCase() : bersih(j['kode']);
    final payload = 'TOKO|v1|$kodeOk|$id|${bersih(j['nama'])}|${bersih(j['tanggal'])}';
    final m = await _load();
    m['url'] = alamat;
    m['payload'] = payload;
    m['sig'] = _cek(payload);
    await _save();
    return _urai(payload, id)!;
  }

  /// Info untuk halaman Tentang
  static Future<Map<String, String>> info() async {
    final l = await cek();
    return {
      'code': l?.kode ?? '',
      'customer': l?.nama ?? '',
      'date': l?.tanggal ?? '',
      'device': await deviceId(),
      'url': await urlTersimpan(),
    };
  }
}

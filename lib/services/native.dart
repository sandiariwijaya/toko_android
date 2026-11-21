import 'dart:io';

import 'package:flutter/services.dart';

class BtDevice {
  final String name;
  final String address;
  BtDevice(this.name, this.address);
}

/// Jembatan ke kode Android (Kotlin) - Bluetooth klasik & file.
class Native {
  static const MethodChannel _ch = MethodChannel('toko/native');

  static Future<int> sdkInt() async {
    if (!Platform.isAndroid) return 0;
    try {
      return (await _ch.invokeMethod<int>('sdkInt')) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> btEnabled() async {
    try {
      return (await _ch.invokeMethod<bool>('btEnabled')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<BtDevice>> btPaired() async {
    final r = await _ch.invokeMethod<List<dynamic>>('btPaired');
    return (r ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => BtDevice((m['name'] ?? '').toString(), (m['address'] ?? '').toString()))
        .toList();
  }

  static Future<bool> btConnect(String address) async {
    try {
      return (await _ch.invokeMethod<bool>('btConnect', {'address': address})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> btIsConnected(String address) async {
    try {
      return (await _ch.invokeMethod<bool>('btIsConnected', {'address': address})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> btWrite(Uint8List data, {int chunk = 256, int delay = 20}) async {
    try {
      return (await _ch.invokeMethod<bool>('btWrite', {'data': data, 'chunk': chunk, 'delay': delay})) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> btDisconnect() async {
    try {
      await _ch.invokeMethod('btDisconnect');
    } catch (_) {}
  }

  static Future<String?> saveToDownloads(String path, String name,
      {String folder = 'AplikasiToko', String mime = 'application/octet-stream'}) async {
    return _ch.invokeMethod<String>('saveToDownloads', {'path': path, 'name': name, 'folder': folder, 'mime': mime});
  }

  /// Simpan ke Download/<folder> lalu buka langsung (Android 10+). false = gagal / tidak ada aplikasi penampil.
  static Future<bool> openFile(String path, String name, {String folder = 'AplikasiToko', required String mime}) async {
    try {
      return (await _ch.invokeMethod<bool>('openFile', {'path': path, 'name': name, 'folder': folder, 'mime': mime})) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Membuka pemilih file Android, mengembalikan path salinan file di cache
  static Future<String?> pickFile() async {
    return _ch.invokeMethod<String>('pickFile');
  }
}

/// Tambahan: identitas perangkat & notifikasi sistem
class NativeX {
  static const MethodChannel _ch = MethodChannel('toko/native');

  static Future<String> deviceId() async {
    try {
      return (await _ch.invokeMethod<String>('deviceId')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> deviceModel() async {
    try {
      return (await _ch.invokeMethod<String>('deviceModel')) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<bool> notify(int id, String title, String body) async {
    try {
      return (await _ch.invokeMethod<bool>('notify', {'id': id, 'title': title, 'body': body})) ?? false;
    } catch (_) {
      return false;
    }
  }
}

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../config.dart';
import '../db/database.dart';
import '../utils/format.dart';
import 'native.dart';

class BackupResult {
  final bool ok;
  final int slot;
  final String localPath;
  final String? publicPath;
  final String? error;
  BackupResult({required this.ok, this.slot = 0, this.localPath = '', this.publicPath, this.error});
}

/// Backup otomatis berputar 2 file (tidak menumpuk):
/// backup_toko_1.db -> backup_toko_2.db -> kembali ke backup_toko_1.db (ditimpa) -> ...
class BackupService {
  static const int slots = 2;
  static const String folderName = '${AppConfig.folder}/Backup';

  static String fileNameFor(int slot) => 'backup_toko_$slot.db';

  static Future<Directory> backupDir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'backup'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<BackupResult> run(AppState app) async {
    try {
      final last = app.i('backup_last_slot', 0);
      final slot = (last % slots) + 1;
      final name = fileNameFor(slot);

      // simpan info slot dulu agar ikut tersimpan di file backup
      await app.setMany({
        'backup_last_slot': '$slot',
        'backup_last_time': dbDateTime(DateTime.now()),
      });

      final db = await Db.instance;
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}

      final src = File(await Db.path());
      final dir = await backupDir();
      final dst = p.join(dir.path, name);
      await src.copy(dst);

      String? pub;
      try {
        if (Platform.isAndroid) {
          final sdk = await Native.sdkInt();
          var allowed = true;
          if (sdk > 0 && sdk < 29) {
            allowed = (await Permission.storage.request()).isGranted;
          }
          if (allowed) pub = await Native.saveToDownloads(dst, name, folder: folderName);
        }
      } catch (_) {
        pub = null;
      }
      await app.set('backup_last_file', pub ?? dst);
      return BackupResult(ok: true, slot: slot, localPath: dst, publicPath: pub);
    } catch (e) {
      return BackupResult(ok: false, error: e.toString());
    }
  }

  static Future<List<File>> localBackups() async {
    final dir = await backupDir();
    final files = <File>[];
    for (var i = 1; i <= slots; i++) {
      final f = File(p.join(dir.path, fileNameFor(i)));
      if (await f.exists()) files.add(f);
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<bool> _isSqlite(File f) async {
    try {
      final raf = await f.open();
      final head = await raf.read(16);
      await raf.close();
      return String.fromCharCodes(head).startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  /// Restore database dari file. return null = sukses, selain itu pesan error.
  static Future<String?> restore(String path) async {
    final f = File(path);
    if (!await f.exists()) return 'File tidak ditemukan';
    if (!await _isSqlite(f)) return 'File bukan backup database yang valid';

    // salin ke temp lalu validasi isi
    final tmpDir = await getTemporaryDirectory();
    final tmp = File(p.join(tmpDir.path, 'restore_check.db'));
    await f.copy(tmp.path);
    if (!await Db.isValidAppDb(tmp.path)) return 'File bukan backup Aplikasi Toko';

    final dbPath = await Db.path();
    final safety = File(p.join(tmpDir.path, 'sebelum_restore.db'));
    await Db.close();
    try {
      final cur = File(dbPath);
      if (await cur.exists()) await cur.copy(safety.path);
      await tmp.copy(dbPath);
      for (final s in ['-wal', '-shm', '-journal']) {
        final x = File('$dbPath$s');
        if (await x.exists()) await x.delete();
      }
      await Db.instance;
      return null;
    } catch (e) {
      // kembalikan database lama bila gagal
      try {
        await Db.close();
        if (await safety.exists()) await safety.copy(dbPath);
        await Db.instance;
      } catch (_) {}
      return 'Restore gagal: $e';
    }
  }
}

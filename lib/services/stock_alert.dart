import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import 'native.dart';

/// Notifikasi barang yang akan habis (notifikasi HP + pemberitahuan di layar)
class StockAlert {
  static bool _asked = false;

  static Future<void> askPermission() async {
    if (_asked) return;
    _asked = true;
    try {
      if (await Native.sdkInt() >= 33) await Permission.notification.request();
    } catch (_) {}
  }

  /// Dipanggil setelah penjualan / perubahan stok
  static Future<void> afterChange(AppState app, Iterable<Product> items) async {
    await app.refreshLowStock();
    if (!app.b('notif_stock')) return;
    final low = <int, Product>{};
    for (final p in items) {
      if (p.isLow && p.id != null) low[p.id!] = p;
    }
    if (low.isEmpty) return;
    final list = low.values.toList();
    final body = list.map((p) => p.stock <= 0 ? '${p.name}: HABIS' : '${p.name}: sisa ${fq(p.stock)} ${p.unit}').join('\n');
    final title = list.length == 1 ? 'Stok menipis: ${list.first.name}' : 'Stok menipis (${list.length} barang)';
    await NativeX.notify(1000 + (list.first.id ?? 0) % 1000, title, body);
    Notify.warning(list.length == 1 ? 'Stok ${list.first.name} tinggal ${fq(list.first.stock)}' : '${list.length} barang stoknya menipis');
  }

  /// Ringkasan saat login
  static Future<void> onLogin(AppState app) async {
    await askPermission();
    await app.refreshLowStock();
    if (!app.b('notif_stock') || app.lowStock == 0) return;
    final low = await Repo.lowStock();
    final names = low.take(6).map((p) => '${p.name} (${fq(p.stock)})').join(', ');
    await NativeX.notify(999, '${low.length} barang akan habis', low.length > 6 ? '$names, dan lainnya' : names);
  }
}

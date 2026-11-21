import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db/database.dart';
import 'services/logo.dart';
import 'models.dart';

class ThemeSeed {
  final String name;
  final Color color;
  const ThemeSeed(this.name, this.color);
}

/// Hak akses kasir yang bisa diatur owner
class KasirPerm {
  final String key;
  final String label;
  final bool def;
  const KasirPerm(this.key, this.label, this.def);
}

class AppState extends ChangeNotifier {
  static const List<ThemeSeed> seeds = [
    ThemeSeed('Biru', Color(0xFF1E88E5)),
    ThemeSeed('Merah', Color(0xFFE53935)),
    ThemeSeed('Oranye', Color(0xFFFB8C00)),
    ThemeSeed('Hijau', Color(0xFF43A047)),
    ThemeSeed('Hijau Toska', Color(0xFF00897B)),
    ThemeSeed('Indigo', Color(0xFF3949AB)),
    ThemeSeed('Ungu', Color(0xFF8E24AA)),
    ThemeSeed('Pink', Color(0xFFD81B60)),
    ThemeSeed('Coklat', Color(0xFF6D4C41)),
    ThemeSeed('Abu Gelap', Color(0xFF455A64)),
  ];

  static const List<KasirPerm> kasirPerms = [
    KasirPerm('perm_edit_price', 'Ubah harga jual di halaman penjualan', true),
    KasirPerm('perm_edit_stock', 'Ubah stok di halaman penjualan', false),
    KasirPerm('perm_discount', 'Memberi diskon', true),
    KasirPerm('perm_purchase', 'Input pembelian (barang masuk)', true),
    KasirPerm('perm_products', 'Tambah / ubah data barang', false),
    KasirPerm('perm_stock', 'Stok opname / penyesuaian stok', false),
    KasirPerm('perm_expense', 'Catat pengeluaran', true),
    KasirPerm('perm_report', 'Lihat laporan penjualan (tanpa laba)', false),
    KasirPerm('perm_reprint', 'Cetak ulang struk', true),
    KasirPerm('perm_buy_price', 'Melihat harga beli / modal', false),
  ];

  static const Map<String, String> defaults = {
    // toko
    'store_name': 'Toko Saya',
    'store_address': '',
    'store_phone': '',
    'store_logo': '', // PNG base64 (sudah diperkecil otomatis)
    'logo_login': '1',
    'login_show_address': '1',
    'rc_show_logo': '1',
    'rc_logo_width': '60', // persen lebar kertas
    'rc_show_name': '1',
    // struk
    'receipt_header': '',
    'receipt_footer': 'Terima kasih atas kunjungan Anda\nBarang yang sudah dibeli tidak dapat ditukar',
    'rc_show_cashier': '1',
    'rc_show_barcode': '0',
    'invoice_prefix': 'TK',
    'pay_methods': 'Tunai,QRIS,Transfer,Debit',
    // stok
    'allow_minus_stock': '1',
    'default_min_stock': '5',
    'notif_stock': '1',
    // printer
    'pr_address': '',
    'pr_name': '',
    'pr_paper': '58', // 58 | 80
    'pr_feed': '3',
    'pr_copies': '1',
    'pr_auto': '0',
    'pr_cut': '0',
    'pr_drawer': '0',
    'bc_height': '60',
    'bc_width': '2',
    'bc_show_price': '1',
    'bc_show_name': '1',
    // tampilan
    'ui_mode': 'auto', // auto | phone | tablet
    'ui_color': '0',
    'ui_custom_color': '',
    'ui_dark': '0', // 0 terang | 1 gelap | 2 sistem
    'ui_text_scale': '1.0',
    'ui_pos_view': 'grid', // grid | list
    'ui_grid_cols': '0', // 0 = otomatis
    'ui_orientation': 'auto', // auto | portrait | landscape
    'ui_sound': '1',
    // backup
    'backup_auto': '1',
    'backup_last_slot': '0',
    'backup_last_time': '',
    'backup_last_file': '',
  };

  final Map<String, String> _s = {};
  AppUser? user;

  Future<void> load() async {
    _s
      ..clear()
      ..addAll(await Repo.loadSettings());
    applyOrientation();
    notifyListeners();
  }

  String get(String k) => _s[k] ?? defaults[k] ?? '';
  bool b(String k) => get(k) == '1';
  int i(String k, [int def = 0]) => int.tryParse(get(k)) ?? def;
  double d(String k, [double def = 0]) => double.tryParse(get(k)) ?? def;

  Future<void> set(String k, String v) => setMany({k: v});

  Future<void> setMany(Map<String, String> kv) async {
    _s.addAll(kv);
    await Repo.saveSettings(kv);
    if (kv.containsKey('ui_orientation')) applyOrientation();
    notifyListeners();
  }

  // ---------------- logo / kop toko ----------------
  String _logoKey = '';
  Uint8List? _logo;

  /// Logo toko yang di-upload (null = pakai ikon bawaan)
  Uint8List? get logo {
    final k = get('store_logo');
    if (k != _logoKey) {
      _logoKey = k;
      _logo = LogoService.decode(k);
    }
    return _logo;
  }

  // ---------------- user & hak akses ----------------
  bool get isOwner => user?.isOwner ?? false;
  String get userName => user?.name ?? '';

  /// Owner selalu boleh. Kasir tergantung pengaturan owner.
  bool can(String perm) {
    if (isOwner) return true;
    final def = kasirPerms.firstWhere((e) => e.key == perm, orElse: () => const KasirPerm('', '', false)).def;
    final v = _s[perm];
    if (v == null) return def;
    return v == '1';
  }

  void setUser(AppUser? u) {
    user = u;
    Activity.user = u?.name ?? '';
    notifyListeners();
  }

  // ---------------- tampilan ----------------
  Color get seedColor {
    final custom = get('ui_custom_color');
    if (custom.isNotEmpty) {
      final v = int.tryParse(custom);
      if (v != null) return Color(v);
    }
    final idx = i('ui_color', 0);
    return seeds[idx.clamp(0, seeds.length - 1).toInt()].color;
  }

  ThemeMode get themeMode => switch (get('ui_dark')) {
        '1' => ThemeMode.dark,
        '2' => ThemeMode.system,
        _ => ThemeMode.light,
      };

  double get textScale => d('ui_text_scale', 1.0).clamp(0.8, 1.4).toDouble();

  /// Mode tablet: diatur manual atau otomatis dari ukuran layar
  bool isTablet(BuildContext context) {
    switch (get('ui_mode')) {
      case 'tablet':
        return true;
      case 'phone':
        return false;
      default:
        return MediaQuery.of(context).size.shortestSide >= 600;
    }
  }

  void applyOrientation() {
    switch (get('ui_orientation')) {
      case 'portrait':
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
        break;
      case 'landscape':
        SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
        break;
      default:
        SystemChrome.setPreferredOrientations([]);
    }
  }

  List<String> get payMethods {
    final l = get('pay_methods').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (!l.any((e) => e.toLowerCase() == 'tunai')) l.insert(0, 'Tunai');
    return l;
  }

  /// Dipanggil saat data berubah dari luar (restore, import) agar layar memuat ulang
  int dataVersion = 0;
  void dataChanged() {
    dataVersion++;
    notifyListeners();
  }

  /// Jumlah barang stok menipis (badge menu)
  int lowStock = 0;
  Future<void> refreshLowStock() async {
    lowStock = await Repo.lowStockCount();
    notifyListeners();
  }
}

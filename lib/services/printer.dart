import 'dart:typed_data';

import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import 'native.dart';

// ======================= ITEM CETAK =======================
abstract class PItem {}

class PText extends PItem {
  final String text;
  final bool bold;
  final bool big; // tinggi ganda
  final bool wide; // lebar ganda
  PText(this.text, {this.bold = false, this.big = false, this.wide = false});
}

/// Barcode CODE128 (dicetak di tengah, angka di bawah barcode)
class PBarcode extends PItem {
  final String code;
  PBarcode(this.code);
}

class PFeed extends PItem {
  final int lines;
  PFeed(this.lines);
}

// ======================= FORMAT TEKS =======================
class TextFmt {
  final int w;
  TextFmt(this.w);

  static const Map<String, String> _map = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'Á': 'A', 'É': 'E', 'Í': 'I',
    'Ó': 'O', 'Ú': 'U', 'Ñ': 'N', '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-',
    '…': '...', '•': '*', '×': 'x', '·': '.', '\t': ' ',
  };

  /// Ubah ke ASCII aman (semua printer thermal mendukung ASCII)
  static String ascii(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (r >= 32 && r < 127) {
        b.write(ch);
      } else if (_map.containsKey(ch)) {
        b.write(_map[ch]);
      } else if (r == 10 || r == 13) {
        b.write(' ');
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  String sep([String c = '-']) => c * w;

  String center(String t, [int? width]) {
    final ww = width ?? w;
    t = t.trim();
    if (t.length >= ww) return t.substring(0, ww);
    final pad = (ww - t.length) ~/ 2;
    return ' ' * pad + t;
  }

  String lr(String l, String r, [int? width]) {
    final ww = width ?? w;
    if (r.length >= ww) return r.substring(0, ww);
    final maxL = ww - r.length - 1;
    if (l.length > maxL) l = l.substring(0, maxL < 0 ? 0 : maxL);
    return l + ' ' * (ww - l.length - r.length) + r;
  }

  String kv(String k, String v, [int keyWidth = 6]) => '${k.padRight(keyWidth)}: $v';

  List<String> wrap(String text, [int? width]) {
    final ww = width ?? w;
    final res = <String>[];
    for (final para in text.split('\n')) {
      var line = '';
      for (var word in para.split(' ')) {
        if (word.isEmpty) continue;
        while (word.length > ww) {
          if (line.isNotEmpty) {
            res.add(line);
            line = '';
          }
          res.add(word.substring(0, ww));
          word = word.substring(ww);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= ww) {
          line = '$line $word';
        } else {
          res.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) res.add(line);
    }
    return res;
  }
}


// ======================= KOMPOSISI STRUK =======================
class Receipts {
  /// 58mm = 32 karakter, 80mm = 48 karakter (Font A)
  static int chars(AppState app) => app.get('pr_paper') == '80' ? 48 : 32;

  static List<PItem> _title(AppState app, TextFmt f, int w) {
    final out = <PItem>[];
    final name = TextFmt.ascii(app.get('store_name')).trim();
    if (name.isNotEmpty) {
      for (final l in f.wrap(name)) {
        out.add(PText(f.center(l), bold: true, big: true));
      }
    }
    return out;
  }

  static List<PItem> header(AppState app) {
    final w = chars(app);
    final f = TextFmt(w);
    final out = _title(app, f, w);
    final addr = TextFmt.ascii(app.get('store_address')).trim();
    if (addr.isNotEmpty) {
      for (final l in f.wrap(addr)) {
        out.add(PText(f.center(l)));
      }
    }
    final phone = TextFmt.ascii(app.get('store_phone')).trim();
    if (phone.isNotEmpty) out.add(PText(f.center('Telp: $phone')));
    final hdr = TextFmt.ascii(app.get('receipt_header')).trim();
    if (hdr.isNotEmpty) {
      for (final line in hdr.split('\n')) {
        for (final l in f.wrap(line)) {
          out.add(PText(f.center(l)));
        }
      }
    }
    return out;
  }

  static List<PItem> sale(AppState app, Sale s, {bool reprint = false}) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = header(app);
    out.add(PText(f.sep()));
    out.add(PText(f.kv('No', s.invoiceNo)));
    out.add(PText(f.kv('Tgl', '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)}')));
    if (app.b('rc_show_cashier') && s.userName.isNotEmpty) out.add(PText(f.kv('Kasir', a(s.userName))));
    if (s.customer.trim().isNotEmpty) out.add(PText(f.kv('Plgn', a(s.customer.trim()))));
    if (reprint) out.add(PText(f.center('** CETAK ULANG **')));
    if (s.isVoid) out.add(PText(f.center('*** DIBATALKAN ***'), bold: true));
    out.add(PText(f.sep()));
    for (final it in s.items) {
      for (final l in f.wrap(a(it.name))) {
        out.add(PText(l));
      }
      out.add(PText(f.lr('  ${fq(it.qty)} x ${nf(it.price)}', nf(it.price * it.qty))));
      if (it.discount > 0) out.add(PText(f.lr('  Diskon', '-${nf(it.discount)}')));
    }
    out.add(PText(f.sep()));
    final itemCount = s.items.fold<double>(0, (x, e) => x + e.qty);
    out.add(PText(f.lr('Subtotal (${fq(itemCount)} item)', nf(s.subtotal))));
    if (s.discount > 0) out.add(PText(f.lr('Diskon', '-${nf(s.discount)}')));
    out.add(PText(f.lr('TOTAL', nf(s.total)), bold: true, big: true));
    out.add(PText(f.lr(a(s.method.isEmpty ? 'Bayar' : s.method), nf(s.paid))));
    if (s.isCash) out.add(PText(f.lr('Kembali', nf(s.change))));
    if (s.note.trim().isNotEmpty) {
      for (final l in f.wrap('Catatan: ${a(s.note.trim())}')) {
        out.add(PText(l));
      }
    }
    final footer = a(app.get('receipt_footer')).trim();
    if (footer.isNotEmpty) {
      out.add(PText(f.sep()));
      for (final line in footer.split('\n')) {
        for (final l in f.wrap(line)) {
          out.add(PText(f.center(l)));
        }
      }
    }
    if (app.b('rc_show_barcode')) out.add(PBarcode(s.invoiceNo));
    return out;
  }

  static List<PItem> purchase(AppState app, Purchase pb) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = _title(app, f, w);
    out.add(PText(f.center('BUKTI PEMBELIAN / BARANG MASUK'), bold: true));
    out.add(PText(f.sep()));
    out.add(PText(f.kv('No', pb.invoiceNo)));
    out.add(PText(f.kv('Tgl', '${fmtDateShort(pb.createdAt)} ${fmtTime(pb.createdAt)}')));
    if (pb.supplierName.isNotEmpty) out.add(PText(f.kv('Suppl', a(pb.supplierName))));
    if (pb.refNo.isNotEmpty) out.add(PText(f.kv('Faktur', a(pb.refNo))));
    out.add(PText(f.kv('Oleh', a(pb.userName))));
    if (pb.isVoid) out.add(PText(f.center('*** DIBATALKAN ***'), bold: true));
    out.add(PText(f.sep()));
    for (final it in pb.items) {
      for (final l in f.wrap(a(it.name))) {
        out.add(PText(l));
      }
      out.add(PText(f.lr('  ${fq(it.qty)} x ${nf(it.buyPrice)}', nf(it.subtotal))));
    }
    out.add(PText(f.sep()));
    out.add(PText(f.lr('TOTAL', nf(pb.total)), bold: true));
    return out;
  }

  static List<PItem> testPage(AppState app) {
    final w = chars(app);
    final f = TextFmt(w);
    final out = header(app);
    out.add(PText(f.sep()));
    out.add(PText(f.center('TES PRINTER'), bold: true));
    final ruler = StringBuffer();
    for (var i = 1; i <= w; i++) {
      ruler.write(i % 10);
    }
    out.add(PText(ruler.toString()));
    out.add(PText(f.lr('Kiri', 'Kanan')));
    out.add(PText(f.lr('Indomie Goreng 2 x 3.500', nf(7000))));
    out.add(PText('Teks tebal', bold: true));
    out.add(PText('Teks besar', big: true));
    out.add(PText(f.sep()));
    out.add(PText('Kertas ${app.get('pr_paper')}mm, $w karakter'));
    out.add(PBarcode('TES12345'));
    out.add(PText(f.center(fmtDateTime(DateTime.now()))));
    return out;
  }

  static String _period(DateTime from, DateTime to) =>
      dbDay(from) == dbDay(to) ? TextFmt.ascii(fmtDayName(from)) : '${fmtDateShort(from)} - ${fmtDateShort(to)}';

  /// Laporan penjualan untuk printer thermal
  static List<PItem> salesReport(AppState app, ReportData d, String printedBy, {List<Sale>? sales, bool withProfit = false}) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = _title(app, f, w);
    final daily = dbDay(d.from) == dbDay(d.to);
    out.add(PText(f.center(daily ? 'LAPORAN PENJUALAN HARIAN' : 'LAPORAN PENJUALAN'), bold: true));
    out.add(PText(f.center(_period(d.from, d.to))));
    out.add(PText(f.sep()));
    out.add(PText(f.lr('Jumlah transaksi', nf(d.trxCount))));
    out.add(PText(f.lr('Item terjual', fq(d.itemsSold))));
    out.add(PText(f.lr('Penjualan kotor', nf(d.gross))));
    if (d.discount > 0) out.add(PText(f.lr('Diskon', '-${nf(d.discount)}')));
    out.add(PText(f.lr('TOTAL PENJUALAN', nf(d.total)), bold: true));
    out.add(PText(f.lr('Rata-rata/transaksi', nf(d.average))));
    if (d.voidCount > 0) out.add(PText(f.lr('Transaksi batal', nf(d.voidCount))));
    out.add(PText(f.sep()));
    out.add(PText('Per metode bayar:', bold: true));
    if (d.byMethod.isEmpty) out.add(PText('  -'));
    for (final m in d.byMethod) {
      out.add(PText(f.lr('  ${a(m.name)} (${m.count})', nf(m.total))));
    }
    if (d.byCashier.isNotEmpty) {
      out.add(PText('Per kasir:', bold: true));
      for (final c in d.byCashier) {
        out.add(PText(f.lr('  ${a(c.name)} (${c.count})', nf(c.total))));
      }
    }
    if (withProfit) {
      out.add(PText(f.sep()));
      out.add(PText(f.lr('Modal (HPP)', nf(d.hpp))));
      out.add(PText(f.lr('Laba kotor', nf(d.grossProfit)), bold: true));
      out.add(PText(f.lr('Pengeluaran', nf(d.expense))));
      out.add(PText(f.lr(d.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', nf(d.net)), bold: true));
    }
    if (d.purchase > 0) {
      out.add(PText(f.sep()));
      out.add(PText(f.lr('Pembelian (${d.purchaseCount})', nf(d.purchase))));
    }
    if (d.topItems.isNotEmpty) {
      out.add(PText(f.sep()));
      out.add(PText(f.lr('Barang terjual', 'Qty'), bold: true));
      for (final t in d.topItems) {
        final qty = fq(t.qty);
        final lines = f.wrap(a(t.name), w - qty.length - 1);
        for (var i = 0; i < lines.length; i++) {
          out.add(PText(i == lines.length - 1 ? f.lr(lines[i], qty) : lines[i]));
        }
      }
    }
    if (sales != null && sales.isNotEmpty) {
      out.add(PText(f.sep()));
      out.add(PText('Daftar transaksi:', bold: true));
      for (final s in sales.reversed) {
        final left = daily ? '${fmtTime(s.createdAt)} ${s.invoiceNo}' : '${fmtDateShort(s.createdAt)} ${s.invoiceNo}';
        out.add(PText(f.lr(left, s.isVoid ? 'BATAL' : nf(s.total))));
      }
    }
    out.add(PText(f.sep()));
    out.add(PText('Dicetak: ${fmtDateShort(DateTime.now())} ${fmtTime(DateTime.now())}'));
    out.add(PText('Oleh   : ${a(printedBy)}'));
    return out;
  }

  /// Daftar stok menipis untuk printer thermal (untuk belanja ke supplier)
  static List<PItem> lowStock(AppState app, List<Product> items) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = _title(app, f, w);
    out.add(PText(f.center('DAFTAR STOK MENIPIS'), bold: true));
    out.add(PText(f.center(a(fmtDayName(DateTime.now())))));
    out.add(PText(f.sep()));
    out.add(PText(f.lr('Barang', 'Sisa/Min'), bold: true));
    for (final p in items) {
      final r = '${fq(p.stock)}/${fq(p.minStock)}';
      final lines = f.wrap(a(p.name), w - r.length - 1);
      for (var i = 0; i < lines.length; i++) {
        out.add(PText(i == lines.length - 1 ? f.lr(lines[i], r) : lines[i]));
      }
    }
    out.add(PText(f.sep()));
    out.add(PText('Total: ${items.length} barang'));
    return out;
  }

  /// Label barcode barang
  static List<PItem> labels(AppState app, List<MapEntry<Product, int>> items) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = <PItem>[];
    for (final e in items) {
      final p = e.key;
      final code = p.barcode.trim();
      if (code.isEmpty) continue;
      for (var i = 0; i < e.value; i++) {
        if (app.b('bc_show_name')) {
          for (final l in f.wrap(a(p.name)).take(2)) {
            out.add(PText(f.center(l), bold: true));
          }
        }
        out.add(PBarcode(code));
        if (app.b('bc_show_price')) out.add(PText(f.center(rp(p.sellPrice)), bold: true, big: true));
        out.add(PFeed(2));
      }
    }
    return out;
  }
}

// ======================= ENCODER ESC/POS =======================
class EscPos {
  static Uint8List encode(AppState app, List<PItem> items, {bool feedEnd = true}) {
    final bytes = <int>[];
    bytes.addAll([0x1B, 0x40]); // ESC @ reset
    bytes.addAll([0x1D, 0x4C, 0x00, 0x00]); // margin kiri 0
    bytes.addAll([0x1B, 0x61, 0x00]); // rata kiri
    for (final it in items) {
      if (it is PText) {
        var mode = 0x00;
        if (it.bold) mode |= 0x08;
        if (it.big) mode |= 0x10;
        if (it.wide) mode |= 0x20;
        bytes.addAll([0x1B, 0x21, mode]);
        if (it.bold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(TextFmt.ascii(it.text).codeUnits);
        bytes.add(0x0A);
        if (it.bold) bytes.addAll([0x1B, 0x45, 0x00]);
        if (mode != 0) bytes.addAll([0x1B, 0x21, 0x00]);
      } else if (it is PBarcode) {
        bytes.addAll(_barcode(app, it.code));
      } else if (it is PFeed) {
        for (var i = 0; i < it.lines; i++) {
          bytes.add(0x0A);
        }
      }
    }
    bytes.addAll([0x1B, 0x21, 0x00]);
    if (feedEnd) {
      final feed = app.i('pr_feed', 3);
      for (var i = 0; i < feed && i < 8; i++) {
        bytes.add(0x0A);
      }
    }
    if (app.b('pr_cut')) bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    return Uint8List.fromList(bytes);
  }

  /// CODE128 via GS k (format B)
  static List<int> _barcode(AppState app, String code) {
    final data = TextFmt.ascii(code).trim();
    if (data.isEmpty) return const [];
    var h = app.i('bc_height', 60);
    if (h < 30) h = 30;
    if (h > 200) h = 200;
    var wd = app.i('bc_width', 2);
    // batasi lebar modul agar barcode muat di kertas
    final maxDots = app.get('pr_paper') == '80' ? 576 : 384;
    final modules = (data.length + 3) * 11 + 35;
    while (wd > 1 && modules * wd > maxDots) {
      wd--;
    }
    if (wd < 1) wd = 1;
    if (wd > 6) wd = 6;
    final payload = [0x7B, 0x42, ...data.codeUnits]; // {B + data
    return [
      0x1B, 0x61, 0x01, // tengah
      0x1D, 0x68, h, // tinggi
      0x1D, 0x77, wd, // lebar modul
      0x1D, 0x48, 0x02, // angka di bawah
      0x1D, 0x66, 0x00, // font angka A
      0x1D, 0x6B, 0x49, payload.length, ...payload,
      0x0A,
      0x1B, 0x61, 0x00, // kembali rata kiri
    ];
  }
}

// ======================= LAYANAN PRINTER =======================
class PrinterService {
  static bool _busy = false;

  static Future<bool> ensurePermission() async {
    final sdk = await Native.sdkInt();
    if (sdk >= 31) {
      final st = await Permission.bluetoothConnect.request();
      if (!st.isGranted) {
        Notify.error('Izin Bluetooth ditolak. Aktifkan di Pengaturan HP > Aplikasi > Izin.');
        if (st.isPermanentlyDenied) await openAppSettings();
        return false;
      }
    }
    return true;
  }

  static Future<List<BtDevice>> pairedDevices() async {
    if (!await ensurePermission()) return [];
    if (!await Native.btEnabled()) {
      Notify.warning('Bluetooth belum aktif. Nyalakan Bluetooth terlebih dahulu.');
      return [];
    }
    try {
      return await Native.btPaired();
    } catch (e) {
      Notify.error('Gagal membaca perangkat: $e');
      return [];
    }
  }

  static Future<bool> printItems(AppState app, List<PItem> items, {int? copies, bool silent = false, String okMsg = 'Berhasil dicetak'}) async {
    if (_busy) {
      Notify.info('Printer sedang mencetak...');
      return false;
    }
    final addr = app.get('pr_address');
    if (addr.isEmpty) {
      Notify.warning('Printer belum dipilih. Atur di Pengaturan > Printer.');
      return false;
    }
    _busy = true;
    try {
      if (!await ensurePermission()) return false;
      if (!await Native.btEnabled()) {
        Notify.warning('Bluetooth belum aktif.');
        return false;
      }
      final data = EscPos.encode(app, items);
      var connected = await Native.btIsConnected(addr);
      if (!connected) connected = await Native.btConnect(addr);
      if (!connected) {
        Notify.error('Tidak bisa terhubung ke printer. Pastikan printer menyala & sudah di-pair.');
        return false;
      }
      var n = copies ?? 1;
      if (n < 1) n = 1;
      if (n > 5) n = 5;
      for (var c = 0; c < n; c++) {
        var ok = await Native.btWrite(data, chunk: 256, delay: 20);
        if (!ok) {
          if (await Native.btConnect(addr)) ok = await Native.btWrite(data, chunk: 256, delay: 20);
        }
        if (!ok) {
          Notify.error('Gagal mengirim data ke printer.');
          return false;
        }
        if (c < n - 1) await Future.delayed(const Duration(milliseconds: 1200));
      }
      if (!silent) Notify.success(okMsg);
      return true;
    } catch (e) {
      Notify.error('Error printer: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  static Future<bool> printSale(AppState app, Sale s, {bool reprint = false}) =>
      printItems(app, Receipts.sale(app, s, reprint: reprint), copies: reprint ? 1 : app.i('pr_copies', 1), okMsg: 'Struk dicetak');

  static Future<bool> testPrint(AppState app) => printItems(app, Receipts.testPage(app), copies: 1);

  /// Teks pratinjau (untuk layar)
  static String preview(List<PItem> items) {
    final b = StringBuffer();
    for (final it in items) {
      if (it is PText) {
        b.writeln(TextFmt.ascii(it.text));
      } else if (it is PBarcode) {
        b.writeln('||||| ${it.code} |||||');
      } else if (it is PFeed) {
        b.writeln();
      }
    }
    return b.toString();
  }
}

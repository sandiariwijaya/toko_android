import 'dart:typed_data';

import '../db/database.dart';
import '../models.dart';
import 'xlsx.dart';

class ImportRow {
  final int line;
  String barcode = '';
  String name = '';
  String category = '';
  String unit = '';
  int buy = 0;
  int sell = 0;
  double stock = 0;
  double minStock = 0;
  bool hasBuy = false;
  bool hasSell = false;
  bool hasStock = false;
  bool hasMin = false;
  String error = '';
  Product? existing;
  ImportRow(this.line);

  bool get isNew => existing == null;
  bool get valid => error.isEmpty;
}

class ImportResult {
  final int added;
  final int updated;
  final int skipped;
  ImportResult(this.added, this.updated, this.skipped);
}

/// Import data barang dari file Excel (.xlsx)
class ProductImport {
  static int _find(List<String> h, List<String> keys) {
    final norm = h.map((e) => e.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '')).toList();
    // prioritas: nama persis dulu, lalu awalan, sesuai urutan kunci
    for (final k in keys) {
      final i = norm.indexOf(k);
      if (i >= 0) return i;
    }
    for (final k in keys) {
      for (var i = 0; i < norm.length; i++) {
        if (norm[i].startsWith(k)) return i;
      }
    }
    return -1;
  }

  static Future<List<ImportRow>> parse(Uint8List bytes) async {
    final reader = XlsxReader(bytes);
    var rows = reader.rows('Data Barang');
    if (rows.isEmpty) rows = reader.rows();
    if (rows.isEmpty) throw const FormatException('Sheet kosong');

    // cari baris judul kolom (yang mengandung "nama")
    var headerIdx = -1;
    for (var i = 0; i < rows.length && i < 10; i++) {
      if (rows[i].any((c) => c.toLowerCase().contains('nama'))) {
        headerIdx = i;
        break;
      }
    }
    int cBarcode = 0, cName = 1, cCat = 2, cUnit = 3, cBuy = 4, cSell = 5, cStock = 6, cMin = 7;
    if (headerIdx >= 0) {
      final h = rows[headerIdx];
      cBarcode = _find(h, ['barcode', 'kodebarang', 'kode', 'sku', 'plu']);
      cName = _find(h, ['namabarang', 'nama', 'produk']);
      cCat = _find(h, ['kategori', 'jenis', 'kelompok']);
      cUnit = _find(h, ['satuan', 'unit']);
      cBuy = _find(h, ['hargabeli', 'modal', 'hpp', 'beli']);
      cSell = _find(h, ['hargajual', 'jual', 'harga']);
      cMin = _find(h, ['stokminimum', 'stokmin', 'minimum', 'minstok', 'min']);
      cStock = -1;
      for (var i = 0; i < h.length; i++) {
        final t = h[i].toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
        if ((t == 'stok' || t == 'stock' || t == 'stokawal' || t == 'jumlah' || t == 'qty') && i != cMin) cStock = i;
      }
      if (cName < 0) throw const FormatException('Kolom "Nama Barang" tidak ditemukan');
    }

    String cell(List<String> r, int c) => c >= 0 && c < r.length ? r[c].trim() : '';

    final existing = await Repo.products(onlyActive: false);
    final byCode = <String, Product>{};
    final byName = <String, Product>{};
    for (final p in existing) {
      if (p.barcode.trim().isNotEmpty) byCode[p.barcode.trim()] = p;
      byName[p.name.trim().toLowerCase()] = p;
    }

    final out = <ImportRow>[];
    final seenCode = <String>{};
    final seenName = <String>{};
    for (var i = headerIdx + 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((c) => c.trim().isEmpty)) continue;
      final x = ImportRow(i + 1);
      x.barcode = excelWholeText(cell(r, cBarcode));
      x.name = cell(r, cName);
      x.category = cell(r, cCat);
      x.unit = cell(r, cUnit);
      final buy = cell(r, cBuy), sell = cell(r, cSell), st = cell(r, cStock), mn = cell(r, cMin);
      x.hasBuy = buy.isNotEmpty;
      x.hasSell = sell.isNotEmpty;
      x.hasStock = st.isNotEmpty;
      x.hasMin = mn.isNotEmpty;
      x.buy = excelNum(buy).round();
      x.sell = excelNum(sell).round();
      x.stock = excelNum(st);
      x.minStock = excelNum(mn);
      if (x.name.isEmpty) {
        x.error = 'Nama barang kosong';
      } else if (x.barcode.isNotEmpty && seenCode.contains(x.barcode)) {
        x.error = 'Barcode dobel di file';
      } else if (seenName.contains(x.name.toLowerCase()) && x.barcode.isEmpty) {
        x.error = 'Nama dobel di file';
      }
      if (x.barcode.isNotEmpty) seenCode.add(x.barcode);
      seenName.add(x.name.toLowerCase());
      x.existing = (x.barcode.isNotEmpty ? byCode[x.barcode] : null) ?? byName[x.name.toLowerCase()];
      if (x.valid && x.existing != null && x.barcode.isNotEmpty && x.existing!.barcode.isNotEmpty && x.existing!.barcode != x.barcode) {
        // nama sama tapi barcode berbeda -> anggap barang baru bila barcode belum dipakai
        if (byCode[x.barcode] == null) x.existing = null;
      }
      out.add(x);
    }
    return out;
  }

  static Future<ImportResult> apply(List<ImportRow> rows, {required bool overwriteStock, required String user, int defaultMin = 0}) async {
    var added = 0, updated = 0, skipped = 0;
    final catCache = <String, int>{};
    Future<int?> cat(String name) async {
      if (name.trim().isEmpty) return null;
      final k = name.trim().toLowerCase();
      if (catCache.containsKey(k)) return catCache[k];
      final id = await Repo.categoryId(name);
      catCache[k] = id;
      return id;
    }

    for (final r in rows) {
      if (!r.valid) {
        skipped++;
        continue;
      }
      final ex = r.existing;
      if (ex == null) {
        final p = Product(
          barcode: r.barcode.isEmpty ? await Repo.newBarcode() : r.barcode,
          name: r.name,
          categoryId: await cat(r.category),
          unit: r.unit.isEmpty ? 'pcs' : r.unit,
          buyPrice: r.buy,
          sellPrice: r.sell,
          stock: r.stock,
          minStock: r.hasMin ? r.minStock : defaultMin.toDouble(),
        );
        await Repo.saveProduct(p, user: user, note: 'Import Excel');
        added++;
      } else {
        final p = (await Repo.productById(ex.id!)) ?? ex;
        p.name = r.name;
        if (r.barcode.isNotEmpty) p.barcode = r.barcode;
        if (r.category.isNotEmpty) p.categoryId = await cat(r.category);
        if (r.unit.isNotEmpty) p.unit = r.unit;
        if (r.hasBuy) p.buyPrice = r.buy;
        if (r.hasSell) p.sellPrice = r.sell;
        if (r.hasMin) p.minStock = r.minStock;
        if (overwriteStock && r.hasStock) p.stock = r.stock;
        p.active = true;
        await Repo.saveProduct(p, user: user, note: 'Import Excel');
        updated++;
      }
    }
    await Activity.log('barang', 'Import barang dari Excel', 'Baru $added, diperbarui $updated, dilewati $skipped');
    return ImportResult(added, updated, skipped);
  }
}

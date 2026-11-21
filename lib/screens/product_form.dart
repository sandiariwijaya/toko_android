import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/stock_alert.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';

/// Ubah cepat harga jual & stok (dipakai di halaman penjualan, barang, stok)
Future<bool> quickEditProduct(BuildContext context, Product p, {String from = 'halaman penjualan'}) async {
  final app = context.read<AppState>();
  final canPrice = app.can('perm_edit_price') || app.can('perm_products');
  final canStock = app.can('perm_edit_stock') || app.can('perm_stock');
  if (!canPrice && !canStock) {
    Notify.warning('Anda tidak punya akses mengubah harga/stok');
    return false;
  }
  final price = TextEditingController(text: nf(p.sellPrice));
  final stock = TextEditingController(text: qtyText(p.stock));
  final note = TextEditingController();
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ProductAvatar(p.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('${p.barcode.isEmpty ? 'Tanpa barcode' : p.barcode} • ${p.unit}', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                if (app.can('perm_buy_price')) Text('Harga beli: ${rp(p.buyPrice)}', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 18),
          MoneyField(controller: price, label: 'Harga jual', icon: Icons.sell_outlined, enabled: canPrice),
          const SizedBox(height: 12),
          TextField(
            controller: stock,
            enabled: canStock,
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            inputFormatters: qtyFormatters,
            decoration: inputDeco('Stok sekarang (hasil hitung fisik)', icon: Icons.inventory_outlined, suffix: p.unit),
          ),
          const SizedBox(height: 12),
          TextField(controller: note, enabled: canStock, decoration: inputDeco('Alasan ubah stok (opsional)', icon: Icons.notes_rounded)),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_rounded),
            label: const Padding(padding: EdgeInsets.all(12), child: Text('SIMPAN')),
          ),
        ]),
      ),
    ),
  );
  var changed = false;
  if (r == true && p.id != null) {
    final newPrice = parseNum(price.text);
    final newStock = parseQty(stock.text);
    if (canPrice && newPrice != p.sellPrice && newPrice > 0) {
      await Repo.setSellPrice(p.id!, newPrice);
      await Activity.log('harga', 'Ubah harga jual', '${p.name}: ${rp(p.sellPrice)} -> ${rp(newPrice)} (dari $from)');
      p.sellPrice = newPrice;
      changed = true;
    }
    if (canStock && newStock != p.stock) {
      final diff = await Repo.setStock(p.id!, newStock,
          user: app.userName, type: 'koreksi', note: note.text.trim().isEmpty ? 'Ubah dari $from' : note.text.trim());
      await Activity.log('stok', 'Ubah stok', '${p.name}: ${fq(p.stock)} -> ${fq(newStock)} (${diff >= 0 ? '+' : ''}${fq(diff)}) dari $from');
      p.stock = newStock;
      changed = true;
      await StockAlert.afterChange(app, [p]);
    }
    if (changed) Notify.success('Data ${p.name} diperbarui');
  }
  disposeLater(price);
  disposeLater(stock);
  disposeLater(note);
  return changed;
}

/// Form tambah / ubah barang
class ProductForm extends StatefulWidget {
  final Product? product;
  final String initialBarcode;
  final String initialName;
  const ProductForm({super.key, this.product, this.initialBarcode = '', this.initialName = ''});

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  late final Product _p;
  final _barcode = TextEditingController();
  final _name = TextEditingController();
  final _unit = TextEditingController();
  final _buy = TextEditingController();
  final _sell = TextEditingController();
  final _stock = TextEditingController();
  final _min = TextEditingController();
  List<Category> _cats = [];
  int? _catId;
  bool _active = true;
  bool _saving = false;

  bool get _isNew => widget.product == null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _p = widget.product?.copy() ?? Product(name: '', minStock: app.d('default_min_stock', 5));
    _barcode.text = _isNew ? widget.initialBarcode : _p.barcode;
    _name.text = _isNew ? widget.initialName : _p.name;
    _unit.text = _p.unit;
    _buy.text = _p.buyPrice == 0 ? '' : nf(_p.buyPrice);
    _sell.text = _p.sellPrice == 0 ? '' : nf(_p.sellPrice);
    _stock.text = qtyText(_p.stock);
    _min.text = qtyText(_p.minStock);
    _catId = _p.categoryId;
    _active = _p.active;
    _loadCats();
  }

  Future<void> _loadCats() async {
    final c = await Repo.categories();
    if (mounted) setState(() => _cats = c);
  }

  @override
  void dispose() {
    for (final c in [_barcode, _name, _unit, _buy, _sell, _stock, _min]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await ScannerPage.scanOnce(context);
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _autoCode() async {
    final c = await Repo.newBarcode();
    setState(() => _barcode.text = c);
  }

  Future<void> _addCat() async {
    final n = await inputDialog(context, title: 'Kategori baru', label: 'Nama kategori');
    if (n == null || n.trim().isEmpty) return;
    final id = await Repo.categoryId(n);
    await _loadCats();
    setState(() => _catId = id);
  }

  Future<void> _save() async {
    if (_saving) return;
    final app = context.read<AppState>();
    if (_name.text.trim().isEmpty) {
      Notify.warning('Nama barang wajib diisi');
      return;
    }
    final code = _barcode.text.trim();
    if (code.isNotEmpty && await Repo.barcodeUsed(code, _p.id)) {
      Notify.error('Barcode $code sudah dipakai barang lain');
      return;
    }
    final sell = parseNum(_sell.text);
    final buy = parseNum(_buy.text);
    if (sell <= 0) {
      Notify.warning('Harga jual wajib diisi');
      return;
    }
    if (buy > sell) {
      final ok = await confirmDialog(context, title: 'Harga jual lebih kecil', message: 'Harga jual di bawah harga beli (rugi). Tetap simpan?');
      if (!ok) return;
    }
    setState(() => _saving = true);
    final old = widget.product;
    _p
      ..barcode = code
      ..name = _name.text.trim()
      ..categoryId = _catId
      ..unit = _unit.text.trim().isEmpty ? 'pcs' : _unit.text.trim()
      ..buyPrice = app.can('perm_buy_price') ? buy : _p.buyPrice
      ..sellPrice = sell
      ..minStock = parseQty(_min.text)
      ..active = _active;
    if (_isNew || app.can('perm_stock')) _p.stock = parseQty(_stock.text);
    await Repo.saveProduct(_p, user: app.userName);
    if (_isNew) {
      await Activity.log('barang', 'Tambah barang', '${_p.name} • ${rp(_p.sellPrice)} • stok ${fq(_p.stock)}');
    } else if (old != null) {
      final ch = <String>[];
      if (old.name != _p.name) ch.add('nama "${old.name}" -> "${_p.name}"');
      if (old.barcode != _p.barcode) ch.add('barcode ${old.barcode} -> ${_p.barcode}');
      if (old.sellPrice != _p.sellPrice) ch.add('harga jual ${rp(old.sellPrice)} -> ${rp(_p.sellPrice)}');
      if (old.buyPrice != _p.buyPrice) ch.add('harga beli ${rp(old.buyPrice)} -> ${rp(_p.buyPrice)}');
      if (old.stock != _p.stock) ch.add('stok ${fq(old.stock)} -> ${fq(_p.stock)}');
      if (old.minStock != _p.minStock) ch.add('stok min ${fq(old.minStock)} -> ${fq(_p.minStock)}');
      if (old.active != _p.active) ch.add(_p.active ? 'diaktifkan' : 'dinonaktifkan');
      await Activity.log('barang', 'Ubah barang', '${_p.name}: ${ch.isEmpty ? 'tanpa perubahan' : ch.join(', ')}');
    }
    final full = await Repo.productById(_p.id!);
    if (full != null) await StockAlert.afterChange(app, [full]);
    if (!mounted) return;
    Notify.success('Barang disimpan');
    Navigator.pop(context, full ?? _p);
  }

  Future<void> _delete() async {
    final app = context.read<AppState>();
    final used = await Repo.productUsed(_p.id!);
    if (!mounted) return;
    if (used) {
      final ok = await confirmDialog(context,
          title: 'Nonaktifkan barang?',
          message: 'Barang ini sudah ada di transaksi sehingga tidak bisa dihapus. Nonaktifkan agar tidak muncul di penjualan?',
          okText: 'Nonaktifkan',
          danger: true);
      if (!ok) return;
      await Repo.setActive(_p.id!, false);
      await Activity.log('barang', 'Nonaktifkan barang', _p.name);
    } else {
      final ok = await confirmDialog(context, title: 'Hapus barang?', message: 'Hapus "${_p.name}" secara permanen?', okText: 'Hapus', danger: true);
      if (!ok) return;
      await Repo.deleteProduct(_p.id!);
      await Activity.log('barang', 'Hapus barang', '${_p.name} (${_p.barcode})');
    }
    await app.refreshLowStock();
    if (!mounted) return;
    Notify.success('Selesai');
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final showBuy = app.can('perm_buy_price');
    final buy = parseNum(_buy.text), sell = parseNum(_sell.text);
    final margin = sell - buy;
    final stockEditable = _isNew || app.can('perm_stock');
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Tambah Barang' : 'Ubah Barang'),
        actions: [
          if (!_isNew && app.isOwner) IconButton(tooltip: 'Hapus', onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded)),
        ],
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _barcode,
              decoration: inputDeco('Barcode', icon: Icons.qr_code_rounded).copyWith(
                suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Scan', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
                  IconButton(tooltip: 'Buat otomatis', onPressed: _autoCode, icon: const Icon(Icons.auto_awesome_rounded)),
                ]),
                helperText: 'Kosongkan bila tidak ada, atau tekan ✨ untuk membuat barcode otomatis',
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: inputDeco('Nama barang *', icon: Icons.label_outline_rounded)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _cats.any((c) => c.id == _catId) ? _catId : null,
                  isExpanded: true,
                  decoration: inputDeco('Kategori', icon: Icons.category_outlined),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('- Tanpa kategori -')),
                    for (final c in _cats) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setState(() => _catId = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(tooltip: 'Kategori baru', onPressed: _addCat, icon: const Icon(Icons.add_rounded)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              SizedBox(
                width: 140,
                child: TextField(controller: _unit, decoration: inputDeco('Satuan', icon: Icons.straighten_rounded)),
              ),
              for (final u in ['pcs', 'bks', 'btl', 'kg', 'dus', 'renteng', 'liter', 'sak'])
                ActionChip(label: Text(u), onPressed: () => setState(() => _unit.text = u)),
            ]),
            const SectionTitle('HARGA'),
            if (showBuy) ...[
              MoneyField(controller: _buy, label: 'Harga beli / modal', icon: Icons.shopping_bag_outlined, onChanged: (_) => setState(() {})),
              const SizedBox(height: 12),
            ],
            MoneyField(controller: _sell, label: 'Harga jual *', icon: Icons.sell_outlined, onChanged: (_) => setState(() {})),
            if (showBuy && buy > 0 && sell > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  'Untung ${rp(margin)} per ${_unit.text.isEmpty ? 'pcs' : _unit.text} (${(margin * 100 / buy).toStringAsFixed(1)}%)',
                  style: TextStyle(color: margin >= 0 ? Colors.green.shade700 : Colors.red, fontWeight: FontWeight.w600),
                ),
              ),
            const SectionTitle('STOK'),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _stock,
                  enabled: stockEditable,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  inputFormatters: qtyFormatters,
                  decoration: inputDeco(_isNew ? 'Stok awal' : 'Stok', icon: Icons.inventory_outlined),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _min,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: qtyFormatters,
                  decoration: inputDeco('Stok minimum', icon: Icons.notifications_active_outlined),
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 6, left: 4),
              child: Text('Notifikasi muncul bila stok sama atau di bawah stok minimum. Isi 0 untuk mematikan.', style: TextStyle(fontSize: 12)),
            ),
            if (!_isNew) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Barang aktif'),
                subtitle: const Text('Barang nonaktif tidak muncul di penjualan'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('SIMPAN BARANG', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/printer.dart';
import '../services/stock_alert.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'product_form.dart';

/// Pembelian / barang masuk dari supplier
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final List<CartLine> _lines = [];
  List<Supplier> _suppliers = [];
  Supplier? _supplier;
  final _ref = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    final s = await Repo.suppliers();
    if (mounted) setState(() => _suppliers = s);
  }

  int get _total => _lines.fold<int>(0, (a, l) => a + l.subtotal);

  Future<void> _addProduct(Product p, {double qty = 1}) async {
    final idx = _lines.indexWhere((l) => l.product.id == p.id);
    if (idx >= 0) {
      setState(() => _lines[idx].qty += qty);
      return;
    }
    setState(() => _lines.insert(0, CartLine(p, qty: qty, price: p.buyPrice)));
  }

  Future<String?> _byCode(String code) async {
    final p = await Repo.productByBarcode(code);
    if (p == null) {
      if (!mounted) return null;
      final app = context.read<AppState>();
      if (!app.can('perm_products')) {
        Notify.error('Barcode $code belum terdaftar');
        return 'Tidak terdaftar: $code';
      }
      final add = await confirmDialog(context, title: 'Barang baru', message: 'Barcode $code belum terdaftar. Tambah barang baru?', okText: 'Tambah');
      if (!add || !mounted) return 'Tidak terdaftar: $code';
      final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(initialBarcode: code)));
      if (r is Product) {
        // stok awal sudah tercatat di form -> qty pembelian mulai 1
        await _addProduct(r);
        return '${r.name} ditambahkan';
      }
      return null;
    }
    await _addProduct(p);
    return '${p.name} (x${fq(_lines.firstWhere((l) => l.product.id == p.id).qty)})';
  }

  Future<void> _pick() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const ProductPicker(),
    );
    if (p != null) await _addProduct(p);
  }

  Future<void> _editLine(CartLine l) async {
    final app = context.read<AppState>();
    final qty = TextEditingController(text: qtyText(l.qty));
    final buy = TextEditingController(text: nf(l.price));
    final sell = TextEditingController(text: nf(l.newSellPrice ?? l.product.sellPrice));
    final total = TextEditingController();
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = parseQty(qty.text);
        final b = parseNum(buy.text);
        final s = parseNum(sell.text);
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l.product.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Stok sekarang ${fq(l.product.stock)} ${l.product.unit} • Harga beli lama ${rp(l.product.buyPrice)}'),
              const SizedBox(height: 14),
              TextField(
                controller: qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: qtyFormatters,
                onChanged: (_) => setS(() {}),
                decoration: inputDeco('Jumlah masuk', icon: Icons.add_box_outlined, suffix: l.product.unit),
              ),
              const SizedBox(height: 10),
              MoneyField(controller: buy, label: 'Harga beli per ${l.product.unit}', icon: Icons.shopping_bag_outlined, onChanged: (_) => setS(() {})),
              const SizedBox(height: 10),
              MoneyField(
                controller: total,
                label: 'atau isi total harga (dibagi otomatis)',
                icon: Icons.calculate_outlined,
                onChanged: (v) {
                  final t = parseNum(v);
                  final qq = parseQty(qty.text);
                  if (qq > 0 && t > 0) buy.text = nf((t / qq).round());
                  setS(() {});
                },
              ),
              const SizedBox(height: 10),
              if (app.can('perm_edit_price') || app.can('perm_products'))
                MoneyField(controller: sell, label: 'Harga jual (boleh diubah)', icon: Icons.sell_outlined, onChanged: (_) => setS(() {})),
              if (b > 0 && s > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Untung per ${l.product.unit}: ${rp(s - b)} (${(((s - b) * 100) / b).toStringAsFixed(1)}%)',
                      style: TextStyle(color: s >= b ? Colors.green.shade700 : Colors.red, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 6),
              Text('Subtotal: ${rp((b * q).round())}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Hapus'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(onPressed: () => Navigator.pop(ctx, 'ok'), icon: const Icon(Icons.check_rounded), label: const Text('OK')),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
    if (r == 'delete') {
      setState(() => _lines.remove(l));
    } else if (r == 'ok') {
      final q = parseQty(qty.text);
      if (q <= 0) {
        setState(() => _lines.remove(l));
      } else {
        final s = parseNum(sell.text);
        setState(() {
          l.qty = q;
          l.price = parseNum(buy.text);
          l.newSellPrice = (s > 0 && s != l.product.sellPrice) ? s : null;
        });
      }
    }
    disposeLater(qty);
    disposeLater(buy);
    disposeLater(sell);
    disposeLater(total);
  }

  Future<void> _addSupplier() async {
    final n = await inputDialog(context, title: 'Supplier baru', label: 'Nama supplier');
    if (n == null || n.trim().isEmpty) return;
    final s = Supplier(name: n.trim());
    await Repo.saveSupplier(s);
    await Activity.log('supplier', 'Tambah supplier', s.name);
    await _loadSuppliers();
    setState(() => _supplier = _suppliers.firstWhere((e) => e.id == s.id, orElse: () => s));
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      Notify.warning('Belum ada barang');
      return;
    }
    if (_lines.any((l) => l.price <= 0)) {
      final ok = await confirmDialog(context, title: 'Harga beli kosong', message: 'Ada barang dengan harga beli Rp0. Tetap simpan?');
      if (!ok) return;
    }
    if (!mounted) return;
    final app = context.read<AppState>();
    setState(() => _saving = true);
    try {
      final lines = List<CartLine>.of(_lines.reversed);
      final pb = await Repo.createPurchase(lines: lines, user: app.userName, supplier: _supplier, refNo: _ref.text, note: _note.text);
      final changed = lines.where((l) => l.newSellPrice != null).map((l) => '${l.product.name} ${rp(l.product.sellPrice)}->${rp(l.newSellPrice!)}').toList();
      await Activity.log('pembelian', 'Pembelian / barang masuk',
          '${pb.invoiceNo} • ${pb.supplierName.isEmpty ? '-' : pb.supplierName} • ${rp(pb.total)} • ${pb.items.length} barang');
      if (changed.isNotEmpty) await Activity.log('harga', 'Ubah harga jual (dari pembelian)', changed.join(', '));
      await app.refreshLowStock();
      app.dataChanged();
      setState(() {
        _lines.clear();
        _ref.clear();
        _note.clear();
        _saving = false;
      });
      if (!mounted) return;
      final print = await confirmDialog(context,
          title: 'Pembelian tersimpan', message: '${pb.invoiceNo}\nTotal ${rp(pb.total)}\nStok barang sudah bertambah.', okText: 'Cetak Bukti', icon: Icons.check_circle_rounded);
      if (print) PrinterService.printItems(app, Receipts.purchase(app, pb));
      final prods = <Product>[];
      for (final l in lines) {
        final p = await Repo.productById(l.product.id ?? 0);
        if (p != null) prods.add(p);
      }
      await StockAlert.afterChange(app, prods);
    } catch (e) {
      setState(() => _saving = false);
      Notify.error('Gagal menyimpan: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tablet = app.isTablet(context);

    final header = Column(children: [
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<int?>(
            value: _supplier?.id,
            isExpanded: true,
            decoration: inputDeco('Supplier', icon: Icons.store_mall_directory_outlined),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('- Tanpa supplier -')),
              for (final s in _suppliers) DropdownMenuItem<int?>(value: s.id, child: Text(s.name)),
            ],
            onChanged: (v) => setState(() => _supplier = v == null ? null : _suppliers.firstWhere((e) => e.id == v)),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(onPressed: _addSupplier, icon: const Icon(Icons.add_rounded), tooltip: 'Supplier baru'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _ref, decoration: inputDeco('No. faktur supplier', icon: Icons.numbers_rounded))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _note, decoration: inputDeco('Catatan', icon: Icons.notes_rounded))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: () => ScannerPage.scanMany(context, _byCode, title: 'Scan Barang Masuk'),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Scan Barcode')),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.tonalIcon(
            onPressed: _pick,
            icon: const Icon(Icons.search_rounded),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Cari Barang')),
          ),
        ),
      ]),
    ]);

    Widget lineCard(CartLine l) => SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          onTap: () => _editLine(l),
          child: Row(children: [
            ProductAvatar(l.product.name, size: 38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.product.name, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
                Text('${fq(l.qty)} ${l.product.unit} x ${rp(l.price)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.2)),
                if (l.newSellPrice != null)
                  Text('Harga jual baru: ${rp(l.newSellPrice!)}', style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
            Text(rp(l.subtotal), style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        );

    const empty = EmptyState(
        icon: Icons.local_shipping_outlined,
        title: 'Belum ada barang masuk',
        subtitle: 'Scan barcode atau cari barang yang dibeli dari supplier. Stok otomatis bertambah setelah disimpan.');

    final list = _lines.isEmpty
        ? empty
        : ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _lines.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) => lineCard(_lines[i]),
          );

    final footer = SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5)))),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${_lines.length} barang', style: TextStyle(color: cs.onSurfaceVariant)),
              Text(rp(_total), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ]),
          ),
          FilledButton.icon(
            onPressed: _saving || _lines.isEmpty ? null : _save,
            icon: const Icon(Icons.save_rounded),
            label: const Padding(padding: EdgeInsets.symmetric(vertical: 12, horizontal: 6), child: Text('SIMPAN', style: TextStyle(fontWeight: FontWeight.w900))),
          ),
        ]),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Pembelian / Barang Masuk')),
      body: tablet
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 380, child: SingleChildScrollView(child: header)),
                const SizedBox(width: 16),
                Expanded(child: list),
              ]),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                header,
                const SizedBox(height: 10),
                if (_lines.isEmpty) const SizedBox(height: 300, child: empty),
                for (final l in _lines) Padding(padding: const EdgeInsets.only(bottom: 6), child: lineCard(l)),
              ],
            ),
      bottomNavigationBar: footer,
    );
  }
}

/// Pemilih barang (pencarian) — dipakai di pembelian & cetak barcode
class ProductPicker extends StatefulWidget {
  const ProductPicker({super.key});

  @override
  State<ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<ProductPicker> {
  List<Product> _all = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    Repo.products().then((v) {
      if (mounted) setState(() => _all = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _q.toLowerCase().trim();
    final list = t.isEmpty ? _all : _all.where((p) => p.name.toLowerCase().contains(t) || p.barcode.contains(t)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'Cari barang...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final p = list[i];
              return ListTile(
                leading: ProductAvatar(p.name, size: 38),
                title: Text(p.name),
                subtitle: Text('${p.barcode.isEmpty ? '-' : p.barcode} • stok ${fq(p.stock)} ${p.unit}'),
                trailing: Text(rp(p.sellPrice), style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => Navigator.pop(context, p),
              );
            },
          ),
        ),
      ]),
    );
  }
}

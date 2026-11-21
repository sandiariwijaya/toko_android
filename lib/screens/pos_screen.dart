import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Keranjang yang disimpan sementara (pelanggan belum selesai belanja)
class HeldCart {
  final String name;
  final DateTime at;
  final List<CartLine> lines;
  final int discount;
  HeldCart(this.name, this.at, this.lines, this.discount);
  int get total => lines.fold<int>(0, (a, l) => a + l.subtotal) - discount;
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  static final List<HeldCart> held = [];

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final List<CartLine> _cart = [];
  int _discount = 0;
  List<Product> _all = [];
  List<Category> _cats = [];
  int? _cat;
  String _q = '';
  bool _loading = true;
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await Repo.products();
    final c = await Repo.categories();
    if (!mounted) return;
    setState(() {
      _all = p;
      _cats = c.where((e) => e.count > 0).toList();
      _loading = false;
    });
  }

  List<Product> get _filtered {
    final t = _q.trim().toLowerCase();
    final words = t.isEmpty ? <String>[] : t.split(RegExp(r'\s+'));
    return _all.where((p) {
      if (_cat != null && p.categoryId != _cat) return false;
      if (words.isEmpty) return true;
      final n = p.name.toLowerCase();
      return words.every((w) => n.contains(w) || p.barcode.contains(w));
    }).toList();
  }

  int get _subtotal => _cart.fold<int>(0, (a, l) => a + l.subtotal);
  int get _total => (_subtotal - _discount) < 0 ? 0 : _subtotal - _discount;
  double get _items => _cart.fold<double>(0, (a, l) => a + l.qty);

  double _inCart(Product p) => _cart.where((l) => l.product.id == p.id).fold<double>(0, (a, l) => a + l.qty);

  bool _add(Product p, {double qty = 1}) {
    final app = context.read<AppState>();
    final want = _inCart(p) + qty;
    if (want > p.stock) {
      if (!app.b('allow_minus_stock')) {
        Notify.error(p.stock <= 0 ? '${p.name} stoknya habis' : 'Stok ${p.name} tinggal ${fq(p.stock)}');
        return false;
      }
      Notify.warning(p.stock <= 0 ? '${p.name}: stok di sistem habis' : '${p.name}: stok di sistem tinggal ${fq(p.stock)}');
    }
    if (p.sellPrice <= 0) Notify.warning('${p.name} belum ada harga jual');
    setState(() {
      final idx = _cart.indexWhere((l) => l.product.id == p.id);
      if (idx >= 0) {
        _cart[idx].qty += qty;
        final l = _cart.removeAt(idx);
        _cart.insert(0, l);
      } else {
        _cart.insert(0, CartLine(p, qty: qty, price: p.sellPrice));
      }
    });
    if (app.b('ui_sound')) {
      HapticFeedback.lightImpact();
      SystemSound.play(SystemSoundType.click);
    }
    return true;
  }

  /// Cari via barcode (scanner kamera / scanner USB-Bluetooth yang mengetik + Enter)
  Future<String?> _byCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty) return null;
    Product? p;
    for (final x in _all) {
      if (x.barcode == code) {
        p = x;
        break;
      }
    }
    p ??= await Repo.productByBarcode(code);
    if (p == null) {
      Notify.error('Barcode $code tidak terdaftar');
      if (!mounted) return 'Tidak terdaftar: $code';
      final app = context.read<AppState>();
      if (app.can('perm_products')) {
        final add = await confirmDialog(context, title: 'Barang belum terdaftar', message: 'Barcode $code belum ada. Tambah sebagai barang baru?', okText: 'Tambah');
        if (add && mounted) {
          final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(initialBarcode: code)));
          if (r is Product) {
            await _load();
            _add(r);
            return '${r.name} ditambahkan';
          }
        }
      }
      return 'Tidak terdaftar: $code';
    }
    if (!p.active) {
      Notify.warning('${p.name} nonaktif');
      return '${p.name} nonaktif';
    }
    final ok = _add(p);
    return ok ? '${p.name} • ${rp(p.sellPrice)} (x${fq(_inCart(p))})' : null;
  }

  Future<void> _onSubmitSearch(String v) async {
    final t = v.trim();
    if (t.isEmpty) return;
    Product? exact;
    for (final x in _all) {
      if (x.barcode.isNotEmpty && x.barcode == t) {
        exact = x;
        break;
      }
    }
    if (exact != null || RegExp(r'^\d{6,}$').hasMatch(t)) {
      await _byCode(t);
      _search.clear();
      setState(() => _q = '');
    } else {
      final f = _filtered;
      if (f.length == 1) {
        _add(f.first);
        _search.clear();
        setState(() => _q = '');
      }
    }
    _searchFocus.requestFocus();
  }

  Future<void> _scanCamera() async {
    await ScannerPage.scanMany(context, _byCode, title: 'Scan Barang');
  }

  Future<void> _quickEdit(Product p) async {
    final changed = await quickEditProduct(context, p);
    if (changed) {
      for (final l in _cart) {
        if (l.product.id == p.id && l.price != p.sellPrice) l.price = p.sellPrice;
      }
      setState(() {});
    }
  }

  // ---------------------------------------------------------------- baris keranjang
  Future<void> _editLine(CartLine l) async {
    final app = context.read<AppState>();
    final p = l.product;
    final qty = TextEditingController(text: qtyText(l.qty));
    final price = TextEditingController(text: nf(l.price));
    final disc = TextEditingController(text: l.discount == 0 ? '' : nf(l.discount));
    var savePrice = false;
    final canPrice = app.can('perm_edit_price');
    final canDisc = app.can('perm_discount');
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Stok: ${fq(p.stock)} ${p.unit}${p.barcode.isEmpty ? '' : ' • ${p.barcode}'}',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Row(children: [
                IconButton.filledTonal(
                  onPressed: () {
                    final v = parseQty(qty.text) - 1;
                    qty.text = qtyText(v < 1 ? 1 : v);
                  },
                  icon: const Icon(Icons.remove_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: qty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: qtyFormatters,
                    decoration: inputDeco('Jumlah', suffix: p.unit),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(onPressed: () => qty.text = qtyText(parseQty(qty.text) + 1), icon: const Icon(Icons.add_rounded)),
              ]),
              const SizedBox(height: 12),
              MoneyField(controller: price, label: 'Harga jual', icon: Icons.sell_outlined, enabled: canPrice),
              if (canPrice)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: savePrice,
                  onChanged: (v) => setS(() => savePrice = v ?? false),
                  title: const Text('Simpan sebagai harga jual baru barang ini'),
                ),
              if (canDisc) ...[
                const SizedBox(height: 4),
                MoneyField(controller: disc, label: 'Diskon untuk barang ini (total)', icon: Icons.discount_outlined),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () => Navigator.pop(ctx, 'delete'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Hapus'),
                  ),
                ),
                const SizedBox(width: 8),
                if (app.can('perm_edit_stock') || app.can('perm_edit_price'))
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx, 'product'),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Ubah stok'),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, 'ok'),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('OK'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (r == 'delete') {
      setState(() => _cart.remove(l));
    } else if (r == 'product') {
      await _quickEdit(p);
    } else if (r == 'ok') {
      final q = parseQty(qty.text);
      if (q <= 0) {
        setState(() => _cart.remove(l));
      } else {
        final otherQty = _inCart(p) - l.qty;
        if (q + otherQty > p.stock && !app.b('allow_minus_stock')) {
          Notify.error('Stok ${p.name} tinggal ${fq(p.stock)}');
        } else {
          l.qty = q;
        }
        final np = parseNum(price.text);
        if (canPrice && np > 0 && np != l.price) {
          await Activity.log('harga', 'Ubah harga di keranjang', '${p.name}: ${rp(l.price)} -> ${rp(np)}${savePrice ? ' (disimpan permanen)' : ''}');
          l.price = np;
        }
        if (canPrice && savePrice && np > 0 && np != p.sellPrice && p.id != null) {
          await Repo.setSellPrice(p.id!, np);
          await Activity.log('harga', 'Ubah harga jual', '${p.name}: ${rp(p.sellPrice)} -> ${rp(np)} (dari halaman penjualan)');
          p.sellPrice = np;
          Notify.success('Harga jual ${p.name} disimpan');
        }
        if (canDisc) {
          final d = parseNum(disc.text);
          l.discount = d > l.gross ? l.gross : d;
        }
        setState(() {});
      }
    }
    disposeLater(qty);
    disposeLater(price);
    disposeLater(disc);
  }

  void _changeQty(CartLine l, double delta) {
    final app = context.read<AppState>();
    final nq = l.qty + delta;
    if (nq <= 0) {
      setState(() => _cart.remove(l));
      return;
    }
    if (delta > 0 && _inCart(l.product) + delta > l.product.stock && !app.b('allow_minus_stock')) {
      Notify.error('Stok ${l.product.name} tinggal ${fq(l.product.stock)}');
      return;
    }
    setState(() => l.qty = nq);
  }

  Future<void> _setDiscount() async {
    final app = context.read<AppState>();
    if (!app.can('perm_discount')) {
      Notify.warning('Anda tidak punya akses memberi diskon');
      return;
    }
    final c = TextEditingController(text: _discount == 0 ? '' : nf(_discount));
    final pct = TextEditingController();
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diskon Nota'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          MoneyField(controller: c, label: 'Diskon (Rp)', autofocus: true),
          const SizedBox(height: 10),
          TextField(
            controller: pct,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: inputDeco('atau Diskon (%)', suffix: '%'),
            onChanged: (v) {
              final p = parseQty(v);
              c.text = nf((_subtotal * p / 100).round());
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 0), child: const Text('Hapus Diskon')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(c.text)), child: const Text('Simpan')),
        ],
      ),
    );
    if (r != null) setState(() => _discount = r > _subtotal ? _subtotal : r);
    disposeLater(c);
    disposeLater(pct);
  }

  // ---------------------------------------------------------------- simpan sementara
  Future<void> _hold() async {
    if (_cart.isEmpty) return;
    final n = await inputDialog(context, title: 'Simpan sementara', label: 'Nama pelanggan / keterangan', initial: 'Pelanggan ${PosScreen.held.length + 1}');
    if (n == null) return;
    PosScreen.held.add(HeldCart(n.trim().isEmpty ? 'Pelanggan' : n.trim(), DateTime.now(), List.of(_cart), _discount));
    setState(() {
      _cart.clear();
      _discount = 0;
    });
    Notify.info('Keranjang disimpan sementara');
  }

  Future<void> _openHeld() async {
    if (PosScreen.held.isEmpty) {
      Notify.info('Tidak ada keranjang tersimpan');
      return;
    }
    final i = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 0, 20, 8), child: Text('Keranjang Tersimpan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          for (var k = 0; k < PosScreen.held.length; k++)
            ListTile(
              leading: const Icon(Icons.shopping_basket_rounded),
              title: Text(PosScreen.held[k].name),
              subtitle: Text('${fmtTime(PosScreen.held[k].at)} • ${PosScreen.held[k].lines.length} barang'),
              trailing: Text(rp(PosScreen.held[k].total), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () => Navigator.pop(ctx, k),
            ),
        ],
      ),
    );
    if (i == null) return;
    final h = PosScreen.held.removeAt(i);
    if (_cart.isNotEmpty) {
      PosScreen.held.add(HeldCart('Keranjang ${fmtTime(DateTime.now())}', DateTime.now(), List.of(_cart), _discount));
    }
    setState(() {
      _cart
        ..clear()
        ..addAll(h.lines);
      _discount = h.discount;
    });
  }

  // ---------------------------------------------------------------- bayar
  Future<void> _pay() async {
    if (_cart.isEmpty) {
      Notify.warning('Keranjang masih kosong');
      return;
    }
    final app = context.read<AppState>();
    final res = await showModalBottomSheet<_PayResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaySheet(total: _total, methods: app.payMethods, printerReady: app.get('pr_address').isNotEmpty, autoPrint: app.b('pr_auto')),
    );
    if (res == null || !mounted) return;
    try {
      final lines = List<CartLine>.of(_cart.reversed);
      final sale = await Repo.createSale(
        lines: lines,
        discount: _discount,
        paid: res.paid,
        method: res.method,
        user: app.userName,
        customer: res.customer,
        note: res.note,
        prefix: app.get('invoice_prefix').isEmpty ? 'TK' : app.get('invoice_prefix'),
      );
      await Activity.log('penjualan', 'Transaksi penjualan', '${sale.invoiceNo} • ${rp(sale.total)} • ${sale.method} • ${sale.items.length} barang');
      setState(() {
        _cart.clear();
        _discount = 0;
      });
      if (res.print) PrinterService.printSale(app, sale);
      await StockAlert.afterChange(app, lines.map((e) => e.product));
      _load();
      if (!mounted) return;
      await _done(sale);
    } catch (e) {
      Notify.error('Gagal menyimpan transaksi: $e');
    }
  }

  Future<void> _done(Sale s) async {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, color: Colors.green, size: 56),
        title: const Text('Transaksi Berhasil', textAlign: TextAlign.center),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.invoiceNo, style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 10),
          Text('Total ${rp(s.total)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          if (s.isCash) ...[
            const SizedBox(height: 6),
            const Text('Kembalian'),
            Text(rp(s.change), style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: cs.primary)),
          ] else
            Text('Dibayar via ${s.method}'),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => PrinterService.printSale(app, s),
            icon: const Icon(Icons.print_rounded),
            label: const Text('Cetak Struk'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Transaksi Baru'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final tablet = app.isTablet(context);
    final products = _filtered;

    final productArea = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          onSubmitted: _onSubmitSearch,
          decoration: InputDecoration(
            hintText: 'Cari nama / ketik barcode lalu Enter',
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              if (_q.isNotEmpty)
                IconButton(
                  onPressed: () {
                    _search.clear();
                    setState(() => _q = '');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              IconButton.filled(tooltip: 'Scan kamera', onPressed: _scanCamera, icon: const Icon(Icons.qr_code_scanner_rounded)),
              const SizedBox(width: 4),
            ]),
          ),
        ),
      ),
      if (_cats.isNotEmpty)
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: const Text('Semua'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
              ),
              for (final c in _cats)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(label: Text(c.name), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
                ),
            ],
          ),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : products.isEmpty
                ? EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: _all.isEmpty ? 'Belum ada barang' : 'Barang tidak ditemukan',
                    subtitle: _all.isEmpty ? 'Tambah barang di menu Barang atau import dari Excel' : null,
                  )
                : _productList(app, products, tablet),
      ),
    ]);

    final title = Row(children: [
      const Expanded(child: Text('Penjualan')),
      if (PosScreen.held.isNotEmpty)
        Badge(
          label: Text('${PosScreen.held.length}'),
          child: IconButton(tooltip: 'Keranjang tersimpan', onPressed: _openHeld, icon: const Icon(Icons.shopping_basket_outlined)),
        )
      else
        IconButton(tooltip: 'Keranjang tersimpan', onPressed: _openHeld, icon: const Icon(Icons.shopping_basket_outlined)),
    ]);

    if (tablet) {
      return Scaffold(
        appBar: AppBar(title: title, actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))]),
        body: Row(children: [
          Expanded(child: productArea),
          Container(
            width: MediaQuery.of(context).size.width >= 1100 ? 420 : 360,
            margin: const EdgeInsets.fromLTRB(0, 4, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
            ),
            child: _cartPanel(app, inSheet: false),
          ),
        ]),
      );
    }

    return Scaffold(
      appBar: AppBar(title: title),
      body: productArea,
      bottomNavigationBar: _cart.isEmpty ? null : _phoneBar(),
    );
  }

  Widget _productList(AppState app, List<Product> products, bool tablet) {
    final grid = app.get('ui_pos_view') != 'list';
    if (!grid) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (_, i) {
          final p = products[i];
          final inCart = _inCart(p);
          return SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            onTap: () => _add(p),
            child: GestureDetector(
              onLongPress: () => _quickEdit(p),
              child: Row(children: [
                inCart > 0
                    ? Badge(label: Text(fq(inCart)), child: ProductAvatar(p.name, size: 42))
                    : ProductAvatar(p.name, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Pill('Stok ${fq(p.stock)}', color: stockColor(context, p.stock, p.minStock)),
                      const SizedBox(width: 6),
                      if (p.barcode.isNotEmpty)
                        Flexible(child: Text(p.barcode, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                    ]),
                  ]),
                ),
                Text(rp(p.sellPrice), style: TextStyle(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.primary)),
              ]),
            ),
          );
        },
      );
    }
    final userCols = app.i('ui_grid_cols', 0);
    return LayoutBuilder(builder: (context, c) {
      final cols = userCols > 0 ? userCols : (c.maxWidth / (tablet ? 170 : 150)).floor().clamp(2, 8).toInt();
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          mainAxisExtent: 168,
        ),
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          final inCart = _inCart(p);
          final cs = Theme.of(context).colorScheme;
          return Material(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _add(p),
              onLongPress: () => _quickEdit(p),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: inCart > 0 ? cs.primary : cs.outlineVariant.withOpacity(0.45), width: inCart > 0 ? 2 : 1),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ProductAvatar(p.name, size: 40),
                    const Spacer(),
                    if (inCart > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(12)),
                        child: Text(fq(inCart), style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 12)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(p.name, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.2)),
                  ),
                  Text(rp(p.sellPrice), style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, fontSize: 15)),
                  const SizedBox(height: 4),
                  Pill(p.stock <= 0 ? 'Habis' : 'Stok ${fq(p.stock)}', color: stockColor(context, p.stock, p.minStock)),
                ]),
              ),
            ),
          );
        },
      );
    });
  }

  Widget _phoneBar() {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Material(
          color: cs.primary,
          borderRadius: BorderRadius.circular(20),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: _openCartSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Badge(
                  label: Text(fq(_items)),
                  backgroundColor: cs.onPrimary,
                  textColor: cs.primary,
                  child: Icon(Icons.shopping_cart_rounded, color: cs.onPrimary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_cart.length} jenis barang', style: TextStyle(color: cs.onPrimary.withOpacity(0.85), fontSize: 12)),
                    Text(rp(_total), style: TextStyle(color: cs.onPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
                  ]),
                ),
                Text('Lihat & Bayar', style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800)),
                Icon(Icons.chevron_right_rounded, color: cs.onPrimary),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCartSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          // panggil setState halaman & sheet sekaligus
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.88,
            child: _CartSheetHost(builder: () => _cartPanel(context.read<AppState>(), inSheet: true, refreshSheet: () => setS(() {}))),
          );
        },
      ),
    );
    setState(() {});
  }

  Widget _cartPanel(AppState app, {required bool inSheet, VoidCallback? refreshSheet}) {
    final cs = Theme.of(context).colorScheme;
    void refresh() {
      setState(() {});
      refreshSheet?.call();
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Row(children: [
          const Icon(Icons.shopping_cart_rounded),
          const SizedBox(width: 8),
          Expanded(child: Text('Keranjang (${fq(_items)})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          IconButton(
            tooltip: 'Simpan sementara',
            onPressed: _cart.isEmpty
                ? null
                : () async {
                    await _hold();
                    refresh();
                    if (inSheet && mounted && _cart.isEmpty) Navigator.of(context).maybePop();
                  },
            icon: const Icon(Icons.pause_circle_outline_rounded),
          ),
          IconButton(
            tooltip: 'Kosongkan',
            onPressed: _cart.isEmpty
                ? null
                : () async {
                    final ok = await confirmDialog(context, title: 'Kosongkan keranjang?', message: 'Semua barang di keranjang dihapus.', danger: true);
                    if (!ok) return;
                    _cart.clear();
                    _discount = 0;
                    refresh();
                  },
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _cart.isEmpty
            ? const EmptyState(icon: Icons.add_shopping_cart_rounded, title: 'Keranjang kosong', subtitle: 'Tap barang atau scan barcode')
            : ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: _cart.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
                itemBuilder: (_, i) {
                  final l = _cart[i];
                  return InkWell(
                    onTap: () async {
                      await _editLine(l);
                      refresh();
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(l.product.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${rp(l.price)}${l.price != l.product.sellPrice ? ' (diubah)' : ''}',
                                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                            if (l.discount > 0) Text('Diskon -${rp(l.discount)}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                            Text(rp(l.subtotal), style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
                          ]),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _changeQty(l, -1);
                            refresh();
                          },
                          icon: const Icon(Icons.remove_circle_outline_rounded),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final q = await qtyDialog(context, title: l.product.name, initial: l.qty, unit: l.product.unit);
                            if (q == null) return;
                            _changeQty(l, q - l.qty);
                            refresh();
                          },
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 34),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                            child: Text(fq(l.qty), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            _changeQty(l, 1);
                            refresh();
                          },
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                      ]),
                    ),
                  );
                },
              ),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Column(children: [
          Row(children: [const Expanded(child: Text('Subtotal')), Text(rp(_subtotal))]),
          InkWell(
            onTap: () async {
              await _setDiscount();
              refresh();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text('Diskon nota', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600))),
                Text(_discount == 0 ? '+ Tambah' : '-${rp(_discount)}', style: TextStyle(color: _discount == 0 ? cs.primary : Colors.red)),
              ]),
            ),
          ),
          Row(children: [
            const Expanded(child: Text('TOTAL', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
            Text(rp(_total), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: cs.primary)),
          ]),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton.icon(
            onPressed: _cart.isEmpty
                ? null
                : () async {
                    if (inSheet) Navigator.of(context).pop();
                    await _pay();
                  },
            icon: const Icon(Icons.payments_rounded),
            label: const Text('BAYAR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    ]);
  }
}

class _CartSheetHost extends StatelessWidget {
  final Widget Function() builder;
  const _CartSheetHost({required this.builder});

  @override
  Widget build(BuildContext context) => builder();
}

// ======================================================================= PEMBAYARAN
class _PayResult {
  final String method;
  final int paid;
  final String customer;
  final String note;
  final bool print;
  _PayResult(this.method, this.paid, this.customer, this.note, this.print);
}

class _PaySheet extends StatefulWidget {
  final int total;
  final List<String> methods;
  final bool printerReady;
  final bool autoPrint;
  const _PaySheet({required this.total, required this.methods, required this.printerReady, required this.autoPrint});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  late String _method = widget.methods.first;
  final _paid = TextEditingController();
  final _customer = TextEditingController();
  final _note = TextEditingController();
  late bool _print = widget.printerReady && widget.autoPrint;

  @override
  void dispose() {
    _paid.dispose();
    _customer.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _cash => _method.toLowerCase() == 'tunai';
  int get _paidVal => _cash ? parseNum(_paid.text) : widget.total;

  List<int> get _quick {
    final t = widget.total;
    final s = <int>{t};
    for (final n in [2000, 5000, 10000, 20000, 50000, 100000]) {
      final v = ((t + n - 1) ~/ n) * n;
      if (v >= t) s.add(v);
    }
    final l = s.toList()..sort();
    return l.take(6).toList();
  }

  void _submit({bool? print}) {
    if (_cash && _paidVal < widget.total) {
      Notify.warning('Uang yang dibayar kurang ${rp(widget.total - _paidVal)}');
      return;
    }
    Navigator.pop(context, _PayResult(_method, _paidVal, _customer.text, _note.text, print ?? _print));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final change = _paidVal - widget.total;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: MaxWidth(
          width: 560,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Pembayaran', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(18)),
              child: Column(children: [
                Text('Total Belanja', style: TextStyle(color: cs.onPrimaryContainer)),
                Text(rp(widget.total), style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: cs.onPrimaryContainer)),
              ]),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in widget.methods)
                ChoiceChip(
                  label: Text(m),
                  avatar: Icon(m.toLowerCase() == 'tunai' ? Icons.payments_rounded : Icons.credit_card_rounded, size: 18),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ]),
            if (_cash) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _paid,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahFormatter()],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _submit(),
                decoration: inputDeco('Uang diterima', icon: Icons.payments_outlined, prefix: 'Rp '),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final q in _quick)
                  ActionChip(
                    label: Text(q == widget.total ? 'Uang pas' : nf(q)),
                    onPressed: () => setState(() => _paid.text = nf(q)),
                  ),
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (change >= 0 ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Text(change >= 0 ? 'Kembalian' : 'Kurang', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(rp(change.abs()),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: change >= 0 ? Colors.green.shade700 : Colors.red)),
                ]),
              ),
            ],
            const SizedBox(height: 12),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nama pelanggan & catatan (opsional)'),
              children: [
                TextField(controller: _customer, decoration: inputDeco('Nama pelanggan', icon: Icons.person_outline_rounded)),
                const SizedBox(height: 8),
                TextField(controller: _note, decoration: inputDeco('Catatan', icon: Icons.notes_rounded)),
                const SizedBox(height: 8),
              ],
            ),
            if (widget.printerReady)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _print,
                onChanged: (v) => setState(() => _print = v),
                title: const Text('Cetak struk'),
                secondary: const Icon(Icons.print_rounded),
              ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () => _submit(),
                icon: const Icon(Icons.check_circle_rounded),
                label: Text(_print ? 'SELESAI & CETAK' : 'SELESAI', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

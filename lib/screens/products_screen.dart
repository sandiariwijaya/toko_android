import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'barcode_screen.dart';
import 'import_screen.dart';
import 'product_form.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _all = [];
  List<Category> _cats = [];
  int? _cat;
  String _q = '';
  String _order = 'name';
  bool _showInactive = false;
  bool _loading = true;
  final _search = TextEditingController();
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await Repo.products(onlyActive: !_showInactive, order: _order);
    final c = await Repo.categories();
    if (!mounted) return;
    setState(() {
      _all = p;
      _cats = c;
      _loading = false;
    });
  }

  List<Product> get _filtered {
    final t = _q.trim().toLowerCase();
    return _all.where((p) {
      if (_cat != null && p.categoryId != _cat) return false;
      if (t.isEmpty) return true;
      return t.split(RegExp(r'\s+')).every((w) => p.name.toLowerCase().contains(w) || p.barcode.contains(w));
    }).toList();
  }

  Future<void> _open(Product? p, {String barcode = ''}) async {
    final app = context.read<AppState>();
    if (!app.can('perm_products')) {
      if (p != null) {
        final ch = await quickEditProduct(context, p, from: 'menu barang');
        if (ch) _load();
      } else {
        Notify.warning('Anda tidak punya akses menambah barang');
      }
      return;
    }
    final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(product: p, initialBarcode: barcode)));
    if (r != null) _load();
  }

  Future<void> _scanFind() async {
    final code = await ScannerPage.scanOnce(context);
    if (code == null || !mounted) return;
    final p = await Repo.productByBarcode(code);
    if (!mounted) return;
    if (p == null) {
      final add = await confirmDialog(context, title: 'Tidak ditemukan', message: 'Barcode $code belum terdaftar. Tambah barang baru?', okText: 'Tambah');
      if (add) _open(null, barcode: code);
    } else {
      _open(p);
    }
  }

  Future<void> _categories() async {
    final app = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
              child: Row(children: [
                const Expanded(child: Text('Kategori Barang', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                FilledButton.tonalIcon(
                  onPressed: () async {
                    final n = await inputDialog(ctx, title: 'Kategori baru', label: 'Nama kategori');
                    if (n == null || n.trim().isEmpty) return;
                    await Repo.categoryId(n);
                    await Activity.log('barang', 'Tambah kategori', n.trim());
                    await _load();
                    setS(() {});
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Tambah'),
                ),
              ]),
            ),
            Expanded(
              child: ListView(children: [
                for (final c in _cats)
                  ListTile(
                    leading: const Icon(Icons.label_outline_rounded),
                    title: Text(c.name),
                    subtitle: Text('${c.count} barang'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          final n = await inputDialog(ctx, title: 'Ubah kategori', initial: c.name);
                          if (n == null || n.trim().isEmpty) return;
                          await Repo.renameCategory(c.id, n);
                          await Activity.log('barang', 'Ubah kategori', '${c.name} -> ${n.trim()}');
                          await _load();
                          setS(() {});
                        },
                      ),
                      if (app.isOwner)
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () async {
                            final ok = await confirmDialog(ctx,
                                title: 'Hapus kategori?', message: '${c.name} dihapus. Barangnya menjadi tanpa kategori.', danger: true, okText: 'Hapus');
                            if (!ok) return;
                            await Repo.deleteCategory(c.id);
                            await Activity.log('barang', 'Hapus kategori', c.name);
                            await _load();
                            setS(() {});
                          },
                        ),
                    ]),
                  ),
              ]),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _menu(String v) async {
    final app = context.read<AppState>();
    switch (v) {
      case 'cat':
        await _categories();
        break;
      case 'import':
        final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportScreen()));
        if (r == true) {
          _load();
          app.dataChanged();
        }
        break;
      case 'template':
        await FileOut.saveAndOpen(ReportExport.templateXlsx(), 'Template_Data_Barang.xlsx', kXlsxMime, sub: 'Template');
        break;
      case 'export':
        final list = await Repo.products(onlyActive: false);
        await FileOut.saveAndOpen(ReportExport.productsXlsx(list, showBuy: app.can('perm_buy_price')), 'Data_Barang_${dbDay(DateTime.now())}.xlsx', kXlsxMime,
            sub: 'Template');
        await Activity.log('data', 'Ekspor data barang ke Excel', '${list.length} barang');
        break;
      case 'barcode':
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const BarcodeScreen()));
        _load();
        break;
      case 'inactive':
        setState(() => _showInactive = !_showInactive);
        _load();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final list = _filtered;
    final tablet = app.isTablet(context);
    final canEdit = app.can('perm_products');
    final showBuy = app.can('perm_buy_price');
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Barang (${_all.length})'),
        actions: [
          IconButton(tooltip: 'Scan cari barang', onPressed: _scanFind, icon: const Icon(Icons.qr_code_scanner_rounded)),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Urutkan',
            onSelected: (v) {
              setState(() => _order = v);
              _load();
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'name', checked: _order == 'name', child: const Text('Nama A-Z')),
              CheckedPopupMenuItem(value: 'stock', checked: _order == 'stock', child: const Text('Stok paling sedikit')),
              CheckedPopupMenuItem(value: 'new', checked: _order == 'new', child: const Text('Terbaru ditambah')),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: _menu,
            itemBuilder: (_) => [
              if (canEdit) const PopupMenuItem(value: 'cat', child: ListTile(leading: Icon(Icons.category_outlined), title: Text('Kategori'))),
              if (canEdit)
                const PopupMenuItem(value: 'import', child: ListTile(leading: Icon(Icons.upload_file_rounded), title: Text('Import dari Excel'))),
              const PopupMenuItem(value: 'template', child: ListTile(leading: Icon(Icons.grid_on_rounded), title: Text('Unduh template Excel'))),
              const PopupMenuItem(value: 'export', child: ListTile(leading: Icon(Icons.file_download_outlined), title: Text('Ekspor barang ke Excel'))),
              const PopupMenuItem(value: 'barcode', child: ListTile(leading: Icon(Icons.qr_code_2_rounded), title: Text('Cetak barcode / label'))),
              CheckedPopupMenuItem(value: 'inactive', checked: _showInactive, child: const Text('Tampilkan barang nonaktif')),
            ],
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(onPressed: () => _open(null), icon: const Icon(Icons.add_rounded), label: const Text('Barang'))
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Cari nama atau barcode',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() => _q = '');
                      },
                      icon: const Icon(Icons.close_rounded)),
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: const Text('Semua'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null)),
            ),
            for (final c in _cats)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text('${c.name} (${c.count})'), selected: _cat == c.id, onSelected: (_) => setState(() => _cat = c.id)),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? EmptyState(
                      icon: Icons.inventory_2_outlined,
                      title: _all.isEmpty ? 'Belum ada barang' : 'Tidak ditemukan',
                      subtitle: _all.isEmpty ? 'Tambah satu per satu, atau isi template Excel lalu import (menu titik tiga).' : null,
                      action: _all.isEmpty && canEdit
                          ? FilledButton.icon(onPressed: () => _menu('import'), icon: const Icon(Icons.upload_file_rounded), label: const Text('Import Excel'))
                          : null,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: tablet ? 520 : 800,
                          mainAxisExtent: 84,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          return SoftCard(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            onTap: () => _open(p),
                            child: Row(children: [
                              ProductAvatar(p.name, size: 46),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontWeight: FontWeight.w700, decoration: p.active ? null : TextDecoration.lineThrough)),
                                  Text(
                                    [if (p.barcode.isNotEmpty) p.barcode, if (p.category.isNotEmpty) p.category, if (showBuy) 'Modal ${nf(p.buyPrice)}'].join(' • '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 3),
                                  Pill('Stok ${fq(p.stock)} ${p.unit}', color: stockColor(context, p.stock, p.minStock)),
                                ]),
                              ),
                              Text(rp(p.sellPrice), style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, fontSize: 15)),
                            ]),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}

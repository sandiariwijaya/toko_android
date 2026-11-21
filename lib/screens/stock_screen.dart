import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../services/printer.dart';
import '../services/stock_alert.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'barcode_screen.dart';
import 'product_form.dart';

const Map<String, String> kMoveLabel = {
  'jual': 'Penjualan',
  'beli': 'Pembelian',
  'opname': 'Stok opname',
  'koreksi': 'Koreksi stok',
  'awal': 'Stok awal',
  'batal-jual': 'Batal penjualan',
  'batal-beli': 'Batal pembelian',
};

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  List<Product> _all = [];
  List<StockMove> _moves = [];
  Map<String, num> _sum = {};
  String _q = '';
  bool _loading = true;
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await Repo.products(order: 'stock');
    final m = await Repo.stockMoves(limit: 300);
    final s = await Repo.stockSummary();
    if (!mounted) return;
    context.read<AppState>().refreshLowStock();
    setState(() {
      _all = p;
      _moves = m;
      _sum = s;
      _loading = false;
    });
  }

  List<Product> get _low => _all.where((p) => p.isLow).toList();

  Future<void> _adjust(Product p) async {
    final ch = await quickEditProduct(context, p, from: 'menu stok');
    if (ch) _load();
  }

  Future<String?> _opnameCode(String code) async {
    final p = await Repo.productByBarcode(code);
    if (p == null) {
      Notify.error('Barcode $code tidak terdaftar');
      return 'Tidak terdaftar: $code';
    }
    if (!mounted) return null;
    final q = await qtyDialog(context, title: 'Stok fisik: ${p.name}\n(sistem: ${fq(p.stock)})', initial: p.stock, unit: p.unit);
    if (q == null) return 'Dilewati: ${p.name}';
    if (q == p.stock) return '${p.name}: sesuai (${fq(q)})';
    final app = context.read<AppState>();
    final diff = await Repo.setStock(p.id!, q, user: app.userName, type: 'opname', note: 'Stok opname (scan)');
    await Activity.log('stok', 'Stok opname', '${p.name}: ${fq(p.stock)} -> ${fq(q)} (${diff >= 0 ? '+' : ''}${fq(diff)})');
    p.stock = q;
    await StockAlert.afterChange(app, [p]);
    return '${p.name}: ${fq(q)} (${diff >= 0 ? '+' : ''}${fq(diff)})';
  }

  Future<void> _history(Product p) async {
    final moves = await Repo.stockMoves(productId: p.id, limit: 200);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kartu Stok', style: TextStyle(color: Theme.of(ctx).colorScheme.primary, fontWeight: FontWeight.w700)),
              Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Stok sekarang: ${fq(p.stock)} ${p.unit}'),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: moves.isEmpty ? const EmptyState(icon: Icons.history_rounded, title: 'Belum ada riwayat') : _moveList(moves, showName: false)),
        ]),
      ),
    );
  }

  Widget _moveList(List<StockMove> moves, {bool showName = true}) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      itemCount: moves.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = moves[i];
        final up = m.qty >= 0;
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 18,
            backgroundColor: (up ? Colors.green : Colors.red).withOpacity(0.14),
            child: Icon(up ? Icons.south_west_rounded : Icons.north_east_rounded, size: 18, color: up ? Colors.green : Colors.red),
          ),
          title: Text(showName ? m.productName : (kMoveLabel[m.type] ?? m.type), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text([
            if (showName) kMoveLabel[m.type] ?? m.type,
            fmtDateTime(m.date),
            if (m.ref.isNotEmpty) m.ref,
            if (m.userName.isNotEmpty) m.userName,
            if (m.note.isNotEmpty) m.note,
          ].join(' • ')),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${up ? '+' : ''}${fq(m.qty)}', style: TextStyle(fontWeight: FontWeight.w900, color: up ? Colors.green.shade700 : Colors.red)),
            Text('sisa ${fq(m.stockAfter)}', style: const TextStyle(fontSize: 11)),
          ]),
        );
      },
    );
  }

  Widget _productList(List<Product> list, {bool lowTab = false}) {
    final cs = Theme.of(context).colorScheme;
    final t = _q.toLowerCase().trim();
    final f = t.isEmpty ? list : list.where((p) => p.name.toLowerCase().contains(t) || p.barcode.contains(t)).toList();
    if (f.isEmpty) {
      return EmptyState(
        icon: lowTab ? Icons.verified_rounded : Icons.inventory_2_outlined,
        title: lowTab ? 'Tidak ada stok menipis' : 'Tidak ada barang',
        subtitle: lowTab ? 'Atur "Stok minimum" di data barang agar peringatan muncul' : null,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
      itemCount: f.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final p = f[i];
        final c = stockColor(context, p.stock, p.minStock);
        return SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: () => _adjust(p),
          child: Row(children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                FittedBox(child: Text(fq(p.stock), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: c))),
                Text(p.unit, style: TextStyle(fontSize: 10.5, color: c)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text('Min ${fq(p.minStock)} • ${p.category.isEmpty ? '-' : p.category}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(tooltip: 'Kartu stok', onPressed: () => _history(p), icon: const Icon(Icons.history_rounded)),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final canStock = app.can('perm_stock');
    final low = _low;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stok Barang'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Cetak / Ekspor',
            onSelected: (v) async {
              switch (v) {
                case 'print_low':
                  await PrinterService.printItems(app, Receipts.lowStock(app, low));
                  break;
                case 'pdf_low':
                  await ReportExport.stock(app, pdf: true, onlyLow: true);
                  break;
                case 'xls_low':
                  await ReportExport.stock(app, pdf: false, onlyLow: true);
                  break;
                case 'pdf_all':
                  await ReportExport.stock(app, pdf: true);
                  break;
                case 'xls_all':
                  await ReportExport.stock(app, pdf: false);
                  break;
                case 'label_low':
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => BarcodeScreen(initial: low)));
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'print_low', child: ListTile(leading: Icon(Icons.print_rounded), title: Text('Cetak stok menipis (thermal)'))),
              PopupMenuItem(value: 'pdf_low', child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded), title: Text('Stok menipis - PDF'))),
              PopupMenuItem(value: 'xls_low', child: ListTile(leading: Icon(Icons.grid_on_rounded), title: Text('Stok menipis - Excel'))),
              PopupMenuItem(value: 'pdf_all', child: ListTile(leading: Icon(Icons.picture_as_pdf_outlined), title: Text('Semua stok - PDF'))),
              PopupMenuItem(value: 'xls_all', child: ListTile(leading: Icon(Icons.grid_on_outlined), title: Text('Semua stok - Excel'))),
            ],
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
        bottom: TabBar(controller: _tab, tabs: [
          const Tab(text: 'Semua'),
          Tab(child: low.isEmpty ? const Text('Menipis') : Badge(label: Text('${low.length}'), child: const Padding(padding: EdgeInsets.only(right: 8), child: Text('Menipis')))),
          const Tab(text: 'Riwayat'),
        ]),
      ),
      floatingActionButton: canStock
          ? FloatingActionButton.extended(
              onPressed: () async {
                await ScannerPage.scanMany(context, _opnameCode, title: 'Stok Opname');
                _load();
              },
              icon: const Icon(Icons.fact_check_rounded),
              label: const Text('Stok Opname'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              SizedBox(
                height: 86,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 4), children: [
                  SizedBox(width: 170, child: StatCard(title: 'Jenis barang', value: nf(_sum['count'] ?? 0), icon: Icons.inventory_2_rounded, color: Colors.blue)),
                  const SizedBox(width: 8),
                  SizedBox(width: 170, child: StatCard(title: 'Menipis', value: nf(_sum['low'] ?? 0), icon: Icons.warning_amber_rounded, color: Colors.orange)),
                  const SizedBox(width: 8),
                  SizedBox(width: 170, child: StatCard(title: 'Habis', value: nf(_sum['empty'] ?? 0), icon: Icons.remove_shopping_cart_rounded, color: Colors.red)),
                  if (app.can('perm_buy_price')) ...[
                    const SizedBox(width: 8),
                    SizedBox(width: 200, child: StatCard(title: 'Nilai stok (modal)', value: rp(_sum['value_buy'] ?? 0), icon: Icons.account_balance_wallet_rounded, color: Colors.purple)),
                  ],
                  const SizedBox(width: 8),
                  SizedBox(width: 200, child: StatCard(title: 'Nilai stok (jual)', value: rp(_sum['value_sell'] ?? 0), icon: Icons.sell_rounded, color: Colors.teal)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                child: TextField(
                  onChanged: (v) => setState(() => _q = v),
                  decoration: const InputDecoration(hintText: 'Cari barang', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                ),
              ),
              Expanded(
                child: TabBarView(controller: _tab, children: [
                  _productList(_all),
                  _productList(low, lowTab: true),
                  _moves.isEmpty ? const EmptyState(icon: Icons.history_rounded, title: 'Belum ada riwayat stok') : _moveList(_moves),
                ]),
              ),
            ]),
    );
  }
}

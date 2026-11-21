import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/scanner.dart';
import 'home_shell.dart';
import 'product_form.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  ReportData? _today;
  ReportData? _week;
  List<Product> _low = [];
  List<Sale> _recent = [];
  bool _loading = true;
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = dayStart(DateTime.now());
    final t = await Repo.report(now, now);
    final w = await Repo.report(now.subtract(const Duration(days: 6)), now);
    final low = await Repo.lowStock();
    final recent = await Repo.sales(now, now);
    if (!mounted) return;
    context.read<AppState>().refreshLowStock();
    setState(() {
      _today = t;
      _week = w;
      _low = low;
      _recent = recent.take(8).toList();
      _loading = false;
    });
  }

  Future<void> _checkPrice() async {
    final code = await ScannerPage.scanOnce(context, title: 'Cek Harga');
    if (code == null || !mounted) return;
    final p = await Repo.productByBarcode(code);
    if (!mounted) return;
    if (p == null) {
      final add = await confirmDialog(context,
          title: 'Barang tidak ditemukan', message: 'Barcode $code belum terdaftar. Tambah barang baru?', okText: 'Tambah');
      if (add && mounted && context.read<AppState>().can('perm_products')) {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => ProductForm(initialBarcode: code)));
        _load();
      }
      return;
    }
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rp(p.sellPrice), style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Theme.of(ctx).colorScheme.primary)),
          const SizedBox(height: 8),
          Text('Barcode: ${p.barcode}'),
          Text('Stok: ${fq(p.stock)} ${p.unit}'),
          if (p.category.isNotEmpty) Text('Kategori: ${p.category}'),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final cs = Theme.of(context).colorScheme;
    final tablet = app.isTablet(context);
    final t = _today;
    final hour = DateTime.now().hour;
    final greet = hour < 11 ? 'Selamat pagi' : (hour < 15 ? 'Selamat siang' : (hour < 18 ? 'Selamat sore' : 'Selamat malam'));
    final nav = HomeNav.of(context);

    final stats = t == null
        ? <Widget>[]
        : [
            StatCard(title: 'Penjualan hari ini', value: rp(t.total), icon: Icons.trending_up_rounded, color: Colors.green),
            StatCard(title: 'Transaksi', value: nf(t.trxCount), icon: Icons.receipt_rounded, color: Colors.blue, sub: '${fq(t.itemsSold)} item terjual'),
            if (app.isOwner) StatCard(title: 'Laba kotor', value: rp(t.grossProfit), icon: Icons.savings_rounded, color: Colors.purple),
            StatCard(
                title: 'Stok menipis',
                value: nf(_low.length),
                icon: Icons.warning_amber_rounded,
                color: _low.isEmpty ? Colors.teal : Colors.orange,
                sub: _low.isEmpty ? 'Semua aman' : 'Perlu belanja'),
          ];

    final actions = <(IconData, String, Color, VoidCallback)>[
      (Icons.point_of_sale_rounded, 'Jual', Colors.blue, () => nav?.go('pos')),
      if (app.can('perm_purchase')) (Icons.local_shipping_rounded, 'Beli', Colors.teal, () => nav?.go('purchase')),
      if (app.can('perm_products'))
        (Icons.add_box_rounded, 'Barang Baru', Colors.orange, () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductForm()));
          _load();
        }),
      (Icons.qr_code_scanner_rounded, 'Cek Harga', Colors.purple, _checkPrice),
      if (app.can('perm_report')) (Icons.insert_chart_rounded, 'Laporan', Colors.pink, () => nav?.go('report')),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$greet, ${app.userName}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(fmtDayName(DateTime.now()), style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500)),
        ]),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  // kartu toko
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.7)!]),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(app.get('store_name'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(rp(t?.total ?? 0), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
                          Text('Total penjualan hari ini', style: TextStyle(color: Colors.white.withOpacity(0.85))),
                        ]),
                      ),
                      ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/logo.png', width: 70, height: 70)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  // aksi cepat
                  Row(children: [
                    for (final a in actions)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: SoftCard(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            onTap: a.$4,
                            child: Column(children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: a.$3.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
                                child: Icon(a.$1, color: a.$3),
                              ),
                              const SizedBox(height: 6),
                              FittedBox(child: Text(a.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
                            ]),
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 6),
                  GridView.count(
                    crossAxisCount: tablet ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: tablet ? 2.3 : 1.75,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    padding: const EdgeInsets.only(top: 10),
                    children: stats,
                  ),
                  if (tablet)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(flex: 3, child: _chart(context)),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: _lowCard(context, nav)),
                    ])
                  else ...[
                    _chart(context),
                    _lowCard(context, nav),
                  ],
                  SectionTitle('TRANSAKSI TERAKHIR HARI INI', trailing: TextButton(onPressed: () => nav?.go('trx'), child: const Text('Semua'))),
                  if (_recent.isEmpty)
                    const SoftCard(child: Text('Belum ada transaksi hari ini'))
                  else
                    SoftCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final s in _recent)
                          ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: (s.isVoid ? Colors.red : Colors.green).withOpacity(0.15),
                              child: Icon(s.isVoid ? Icons.block_rounded : Icons.check_rounded, size: 18, color: s.isVoid ? Colors.red : Colors.green),
                            ),
                            title: Text(s.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${fmtTime(s.createdAt)} • ${s.method} • ${s.userName}'),
                            trailing: Text(rp(s.total),
                                style: TextStyle(fontWeight: FontWeight.w800, decoration: s.isVoid ? TextDecoration.lineThrough : null)),
                          ),
                      ]),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _chart(BuildContext context) {
    final w = _week;
    if (w == null) return const SizedBox();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('PENJUALAN 7 HARI TERAKHIR', trailing: Text(rp(w.total), style: const TextStyle(fontWeight: FontWeight.w800))),
      SoftCard(
        child: MiniBarChart(
          labels: [for (final d in w.daily) fmtDayShort(d.day)],
          values: [for (final d in w.daily) d.total],
          height: 170,
        ),
      ),
    ]);
  }

  Widget _lowCard(BuildContext context, HomeNav? nav) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle('STOK AKAN HABIS', trailing: TextButton(onPressed: () => nav?.go('stock'), child: const Text('Lihat'))),
      SoftCard(
        padding: EdgeInsets.zero,
        child: _low.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.verified_rounded, color: Colors.teal),
                  SizedBox(width: 10),
                  Expanded(child: Text('Semua stok masih aman')),
                ]),
              )
            : Column(children: [
                for (final p in _low.take(6))
                  ListTile(
                    dense: true,
                    leading: ProductAvatar(p.name, size: 36),
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Minimum ${fq(p.minStock)} ${p.unit}'),
                    trailing: Pill(p.stock <= 0 ? 'HABIS' : 'Sisa ${fq(p.stock)}', color: stockColor(context, p.stock, p.minStock)),
                  ),
                if (_low.length > 6)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text('+ ${_low.length - 6} barang lainnya', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
              ]),
      ),
    ]);
  }
}

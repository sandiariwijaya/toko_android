import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  DateTime _from = dayStart(DateTime.now());
  DateTime _to = dayStart(DateTime.now());
  ReportData? _d;
  bool _loading = true;
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await Repo.report(_from, _to);
    if (!mounted) return;
    setState(() {
      _d = d;
      _loading = false;
    });
  }

  Future<void> _print({bool withList = false, bool profit = false}) async {
    final app = context.read<AppState>();
    final d = _d;
    if (d == null) return;
    List<Sale>? sales;
    if (withList) sales = await Repo.sales(_from, _to);
    final ok = await PrinterService.printItems(app, Receipts.salesReport(app, d, app.userName, sales: sales, withProfit: profit),
        okMsg: 'Laporan dicetak');
    if (ok) await Activity.log('data', 'Cetak laporan penjualan (thermal)', ReportExport.period(_from, _to));
  }

  Future<void> _actions() async {
    final app = context.read<AppState>();
    final owner = app.isOwner;
    final r = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text('Periode: ${ReportExport.period(_from, _to)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const _Group('CETAK KE PRINTER THERMAL'),
            _tile(ctx, 'print', Icons.print_rounded, 'Cetak laporan penjualan (ringkas)'),
            _tile(ctx, 'print_list', Icons.receipt_long_rounded, 'Cetak laporan + daftar transaksi'),
            if (owner) _tile(ctx, 'print_profit', Icons.savings_rounded, 'Cetak laporan + laba rugi'),
            const _Group('EKSPOR FILE'),
            _tile(ctx, 'sales_pdf', Icons.picture_as_pdf_rounded, 'Laporan penjualan - PDF', color: Colors.red),
            _tile(ctx, 'sales_xls', Icons.grid_on_rounded, 'Laporan penjualan - Excel', color: Colors.green),
            if (app.can('perm_purchase')) ...[
              _tile(ctx, 'pur_pdf', Icons.picture_as_pdf_outlined, 'Laporan pembelian - PDF', color: Colors.red),
              _tile(ctx, 'pur_xls', Icons.grid_on_outlined, 'Laporan pembelian - Excel', color: Colors.green),
            ],
            _tile(ctx, 'stock_pdf', Icons.inventory_rounded, 'Laporan stok - PDF', color: Colors.red),
            _tile(ctx, 'stock_xls', Icons.inventory_outlined, 'Laporan stok - Excel', color: Colors.green),
            const SizedBox(height: 10),
          ]),
        ),
      ),
    );
    if (r == null) return;
    switch (r) {
      case 'print':
        await _print();
        break;
      case 'print_list':
        await _print(withList: true);
        break;
      case 'print_profit':
        await _print(profit: true);
        break;
      case 'sales_pdf':
        await ReportExport.sales(app, _from, _to, pdf: true);
        break;
      case 'sales_xls':
        await ReportExport.sales(app, _from, _to, pdf: false);
        break;
      case 'pur_pdf':
        await ReportExport.purchases(app, _from, _to, pdf: true);
        break;
      case 'pur_xls':
        await ReportExport.purchases(app, _from, _to, pdf: false);
        break;
      case 'stock_pdf':
        await ReportExport.stock(app, pdf: true);
        break;
      case 'stock_xls':
        await ReportExport.stock(app, pdf: false);
        break;
    }
  }

  Widget _tile(BuildContext ctx, String v, IconData icon, String text, {Color? color}) =>
      ListTile(leading: Icon(icon, color: color), title: Text(text), onTap: () => Navigator.pop(ctx, v));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final d = _d;
    final owner = app.isOwner;
    final tablet = app.isTablet(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan'),
        actions: [
          IconButton(tooltip: 'Cetak', onPressed: () => _print(), icon: const Icon(Icons.print_rounded)),
          FilledButton.tonalIcon(onPressed: _actions, icon: const Icon(Icons.ios_share_rounded), label: const Text('Cetak / Ekspor')),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(children: [
        const SizedBox(height: 6),
        PeriodPicker(
          from: _from,
          to: _to,
          onChanged: (a, b) {
            _from = a;
            _to = b;
            _load();
          },
        ),
        Expanded(
          child: _loading || d == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    GridView.count(
                      crossAxisCount: tablet ? 4 : 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: tablet ? 2.3 : 1.7,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        StatCard(title: 'Total penjualan', value: rp(d.total), icon: Icons.trending_up_rounded, color: Colors.green),
                        StatCard(title: 'Transaksi', value: nf(d.trxCount), icon: Icons.receipt_rounded, color: Colors.blue, sub: 'Rata-rata ${rp(d.average)}'),
                        StatCard(title: 'Item terjual', value: fq(d.itemsSold), icon: Icons.shopping_basket_rounded, color: Colors.orange),
                        StatCard(title: 'Diskon', value: rp(d.discount), icon: Icons.discount_rounded, color: Colors.pink),
                        if (owner) ...[
                          StatCard(title: 'Modal (HPP)', value: rp(d.hpp), icon: Icons.inventory_rounded, color: Colors.brown),
                          StatCard(
                              title: 'Laba kotor', value: rp(d.grossProfit), icon: Icons.savings_rounded, color: Colors.purple, sub: 'Margin ${d.margin.toStringAsFixed(1)}%'),
                          StatCard(title: 'Pengeluaran', value: rp(d.expense), icon: Icons.payments_rounded, color: Colors.red),
                          StatCard(
                              title: d.net >= 0 ? 'Laba bersih' : 'Rugi bersih',
                              value: rp(d.net),
                              icon: Icons.account_balance_wallet_rounded,
                              color: d.net >= 0 ? Colors.teal : Colors.red),
                        ],
                        if (app.can('perm_purchase'))
                          StatCard(title: 'Pembelian barang', value: rp(d.purchase), icon: Icons.local_shipping_rounded, color: Colors.indigo, sub: '${d.purchaseCount} nota'),
                        if (d.voidCount > 0) StatCard(title: 'Transaksi batal', value: nf(d.voidCount), icon: Icons.block_rounded, color: Colors.grey),
                      ],
                    ),
                    if (d.daily.length > 1) ...[
                      const SectionTitle('GRAFIK PENJUALAN HARIAN'),
                      SoftCard(
                        child: MiniBarChart(
                          labels: [for (final e in d.daily) fmtDayShort(e.day)],
                          values: [for (final e in d.daily) e.total],
                        ),
                      ),
                    ],
                    _section('PER METODE BAYAR', d.byMethod, (e) => '${e.count} trx', (e) => rp(e.total)),
                    _section('PER KASIR', d.byCashier, (e) => '${e.count} trx', (e) => rp(e.total)),
                    _section('BARANG TERLARIS', d.topItems.take(30).toList(), (e) => 'Terjual ${fq(e.qty)}', (e) => rp(e.total), numbered: true),
                    if (owner || app.can('perm_expense')) _section('PENGELUARAN', d.expenseByCat, (e) => '${e.count} kali', (e) => rp(e.total)),
                  ]),
                ),
        ),
      ]),
    );
  }

  Widget _section(String title, List<NameTotal> items, String Function(NameTotal) sub, String Function(NameTotal) val, {bool numbered = false}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionTitle(title),
      SoftCard(
        padding: EdgeInsets.zero,
        child: items.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('Tidak ada data'))
            : Column(children: [
                for (var i = 0; i < items.length; i++)
                  ListTile(
                    dense: true,
                    leading: numbered ? CircleAvatar(radius: 14, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))) : null,
                    title: Text(items[i].name.isEmpty ? '-' : items[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(sub(items[i])),
                    trailing: Text(val(items[i]), style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
              ]),
      ),
    ]);
  }
}

class _Group extends StatelessWidget {
  final String text;
  const _Group(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key});

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab;
  DateTime _from = dayStart(DateTime.now());
  DateTime _to = dayStart(DateTime.now());
  String _q = '';
  List<Sale> _sales = [];
  List<Purchase> _purchases = [];
  bool _loading = true;
  bool _showPurchase = false;
  int _ver = -1;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    _showPurchase = app.can('perm_purchase');
    _tab = TabController(length: _showPurchase ? 2 : 1, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await Repo.sales(_from, _to, q: _q);
    final p = _showPurchase ? await Repo.purchases(_from, _to, q: _q) : <Purchase>[];
    if (!mounted) return;
    setState(() {
      _sales = s;
      _purchases = p;
      _loading = false;
    });
  }

  Future<void> _openSale(Sale s0) async {
    final s = await Repo.saleById(s0.id);
    if (s == null || !mounted) return;
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Row(children: [
            Expanded(child: Text(s.invoiceNo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
            if (s.isVoid) const Pill('DIBATALKAN', color: Colors.red),
          ]),
          Text('${fmtDayName(s.createdAt)} ${fmtTime(s.createdAt)} • Kasir ${s.userName}', style: TextStyle(color: cs.onSurfaceVariant)),
          if (s.customer.isNotEmpty) Text('Pelanggan: ${s.customer}'),
          if (s.isVoid) Text('Alasan batal: ${s.voidReason}', style: const TextStyle(color: Colors.red)),
          const Divider(height: 24),
          for (final it in s.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${fq(it.qty)} ${it.unit} x ${rp(it.price)}${it.discount > 0 ? '  (diskon ${rp(it.discount)})' : ''}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  ]),
                ),
                Text(rp(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const Divider(height: 20),
          _kv('Subtotal', rp(s.subtotal)),
          if (s.discount > 0) _kv('Diskon nota', '-${rp(s.discount)}'),
          _kv('TOTAL', rp(s.total), bold: true),
          _kv('Bayar (${s.method})', rp(s.paid)),
          if (s.isCash) _kv('Kembali', rp(s.change)),
          if (app.isOwner) _kv('Laba', rp(s.total - s.hpp)),
          if (s.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Catatan: ${s.note}')),
          const SizedBox(height: 18),
          Row(children: [
            if (app.can('perm_reprint'))
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () async {
                    final ok = await PrinterService.printSale(app, s, reprint: true);
                    if (ok) await Activity.log('penjualan', 'Cetak ulang struk', s.invoiceNo);
                  },
                  icon: const Icon(Icons.print_rounded),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Cetak Ulang')),
                ),
              ),
            if (app.isOwner && !s.isVoid) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    final reason = await inputDialog(ctx, title: 'Batalkan transaksi ${s.invoiceNo}', label: 'Alasan pembatalan');
                    if (reason == null || reason.trim().isEmpty) {
                      if (reason != null) Notify.warning('Alasan wajib diisi');
                      return;
                    }
                    await Repo.voidSale(s, reason.trim(), app.userName);
                    await Activity.log('penjualan', 'Batalkan transaksi',
                        '${s.invoiceNo} • ${rp(s.total)} • alasan: ${reason.trim()} • isi: ${s.items.map((e) => '${fq(e.qty)}x ${e.name}').join(', ')}');
                    await app.refreshLowStock();
                    app.dataChanged();
                    Notify.success('Transaksi dibatalkan, stok dikembalikan');
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  icon: const Icon(Icons.block_rounded),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Batalkan')),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Future<void> _openPurchase(Purchase p0) async {
    final pb = await Repo.purchaseById(p0.id);
    if (pb == null || !mounted) return;
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
          Row(children: [
            Expanded(child: Text(pb.invoiceNo, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900))),
            if (pb.isVoid) const Pill('DIBATALKAN', color: Colors.red),
          ]),
          Text('${fmtDayName(pb.createdAt)} ${fmtTime(pb.createdAt)} • oleh ${pb.userName}', style: TextStyle(color: cs.onSurfaceVariant)),
          if (pb.supplierName.isNotEmpty) Text('Supplier: ${pb.supplierName}'),
          if (pb.refNo.isNotEmpty) Text('No. faktur: ${pb.refNo}'),
          if (pb.isVoid) Text('Alasan batal: ${pb.voidReason}', style: const TextStyle(color: Colors.red)),
          const Divider(height: 24),
          for (final it in pb.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text('${fq(it.qty)} ${it.unit} x ${rp(it.buyPrice)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                  ]),
                ),
                Text(rp(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          const Divider(height: 20),
          _kv('TOTAL', rp(pb.total), bold: true),
          if (pb.note.isNotEmpty) Text('Catatan: ${pb.note}'),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => PrinterService.printItems(app, Receipts.purchase(app, pb)),
                icon: const Icon(Icons.print_rounded),
                label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Cetak')),
              ),
            ),
            if (app.isOwner && !pb.isVoid) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () async {
                    final reason = await inputDialog(ctx, title: 'Batalkan pembelian ${pb.invoiceNo}', label: 'Alasan pembatalan');
                    if (reason == null || reason.trim().isEmpty) return;
                    await Repo.voidPurchase(pb, reason.trim(), app.userName);
                    await Activity.log('pembelian', 'Batalkan pembelian', '${pb.invoiceNo} • ${rp(pb.total)} • alasan: ${reason.trim()}');
                    await app.refreshLowStock();
                    app.dataChanged();
                    Notify.success('Pembelian dibatalkan, stok dikurangi kembali');
                    if (ctx.mounted) Navigator.pop(ctx);
                    _load();
                  },
                  icon: const Icon(Icons.block_rounded),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Batalkan')),
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500, fontSize: bold ? 17 : 14))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: bold ? 18 : 14)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_ver != app.dataVersion) {
      if (_ver != -1) _load();
      _ver = app.dataVersion;
    }
    final cs = Theme.of(context).colorScheme;
    final okSales = _sales.where((s) => !s.isVoid).toList();
    final total = okSales.fold<int>(0, (a, s) => a + s.total);

    Widget salesList() => _sales.isEmpty
        ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Belum ada penjualan', subtitle: 'pada periode ini')
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: _sales.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text('${okSales.length} transaksi • Total ${rp(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                );
              }
              final s = _sales[i - 1];
              return SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () => _openSale(s),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: (s.isVoid ? Colors.red : cs.primary).withOpacity(0.12),
                    child: Icon(s.isVoid ? Icons.block_rounded : Icons.receipt_rounded, color: s.isVoid ? Colors.red : cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)} • ${s.method} • ${s.userName}${s.customer.isEmpty ? '' : ' • ${s.customer}'}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Text(rp(s.total),
                      style: TextStyle(fontWeight: FontWeight.w900, decoration: s.isVoid ? TextDecoration.lineThrough : null, color: s.isVoid ? Colors.red : null)),
                ]),
              );
            },
          );

    Widget purchaseList() => _purchases.isEmpty
        ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Belum ada pembelian', subtitle: 'pada periode ini')
        : ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            itemCount: _purchases.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, i) {
              final p = _purchases[i];
              return SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                onTap: () => _openPurchase(p),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: (p.isVoid ? Colors.red : Colors.teal).withOpacity(0.12),
                    child: Icon(p.isVoid ? Icons.block_rounded : Icons.local_shipping_rounded, color: p.isVoid ? Colors.red : Colors.teal),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text('${fmtDateShort(p.createdAt)} • ${p.supplierName.isEmpty ? 'Tanpa supplier' : p.supplierName}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  Text(rp(p.total), style: TextStyle(fontWeight: FontWeight.w900, decoration: p.isVoid ? TextDecoration.lineThrough : null)),
                ]),
              );
            },
          );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
        bottom: _showPurchase ? TabBar(controller: _tab, tabs: const [Tab(text: 'Penjualan'), Tab(text: 'Pembelian')]) : null,
      ),
      body: Column(children: [
        const SizedBox(height: 6),
        PeriodPicker(
          from: _from,
          to: _to,
          onChanged: (a, b) {
            setState(() {
              _from = a;
              _to = b;
            });
            _load();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: TextField(
            onChanged: (v) {
              _q = v;
              _load();
            },
            decoration: const InputDecoration(hintText: 'Cari no nota / pelanggan / kasir / supplier', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _showPurchase
                  ? TabBarView(controller: _tab, children: [salesList(), purchaseList()])
                  : salesList(),
        ),
      ]),
    );
  }
}

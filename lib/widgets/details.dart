import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../screens/retur_screen.dart';
import 'common.dart';

/// Satu baris data di lembar rincian
class DataItem {
  final String title;
  final String sub;
  final String trailing;
  final Color? color;
  final bool strike;
  final bool bold;
  final VoidCallback? onTap;
  const DataItem(this.title, {this.sub = '', this.trailing = '', this.color, this.strike = false, this.bold = false, this.onTap});
}

/// Lembar rincian data (muncul saat kartu angka ditekan)
Future<void> showDataSheet(
  BuildContext context, {
  required String title,
  String subtitle = '',
  required Future<List<DataItem>> Function() load,
  String? footer,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _DataSheet(title: title, subtitle: subtitle, load: load, footer: footer),
  );
}

class _DataSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final Future<List<DataItem>> Function() load;
  final String? footer;
  const _DataSheet({required this.title, required this.subtitle, required this.load, this.footer});

  @override
  State<_DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends State<_DataSheet> {
  List<DataItem>? _items;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final l = await widget.load();
    if (mounted) setState(() => _items = l);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final all = _items;
    final t = _q.toLowerCase().trim();
    final list = all == null ? <DataItem>[] : (t.isEmpty ? all : all.where((e) => '${e.title} ${e.sub}'.toLowerCase().contains(t)).toList());
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, sc) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(widget.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2)),
                if (widget.subtitle.isNotEmpty)
                  Text(widget.subtitle, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.2)),
              ]),
            ),
            if (all != null) Pill('${all.length} data', color: cs.primary),
          ]),
        ),
        if (all != null && all.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(hintText: 'Cari...', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: all == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.inbox_outlined, title: 'Tidak ada data')
                  : ListView.separated(
                      controller: sc,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14),
                      itemBuilder: (_, i) {
                        final e = list[i];
                        return InkWell(
                          onTap: e.onTap == null
                              ? null
                              : () async {
                                  e.onTap!();
                                },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(e.title,
                                      style: TextStyle(
                                        fontWeight: e.bold ? FontWeight.w900 : FontWeight.w700,
                                        height: 1.2,
                                        decoration: e.strike ? TextDecoration.lineThrough : null,
                                      )),
                                  if (e.sub.isNotEmpty)
                                    Text(e.sub, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.2)),
                                ]),
                              ),
                              const SizedBox(width: 8),
                              Text(e.trailing,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: e.color,
                                    decoration: e.strike ? TextDecoration.lineThrough : null,
                                  )),
                              if (e.onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: cs.outline),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
        if (widget.footer != null)
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              color: cs.primaryContainer,
              child: Text(widget.footer!, style: TextStyle(fontWeight: FontWeight.w800, color: cs.onPrimaryContainer)),
            ),
          ),
      ]),
    );
  }
}

/// Rincian satu nota penjualan (cetak ulang & batal untuk owner)
Future<void> showSaleDetail(BuildContext context, int id, {VoidCallback? onChanged}) async {
  final s = await Repo.saleById(id);
  if (s == null || !context.mounted) return;
  final app = context.read<AppState>();
  final cs = Theme.of(context).colorScheme;
  Widget kv(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w500, fontSize: bold ? 16 : 13.5))),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: bold ? 17 : 13.5)),
        ]),
      );
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Row(children: [
          Expanded(child: Text(s.invoiceNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          if (s.isVoid) const Pill('DIBATALKAN', color: Colors.red),
        ]),
        Text('${fmtDayName(s.createdAt)} ${fmtTime(s.createdAt)} • Kasir ${s.userName}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        if (s.customer.isNotEmpty) Text('Pelanggan: ${s.customer}', style: const TextStyle(fontSize: 12.5)),
        if (s.isVoid) Text('Alasan batal: ${s.voidReason}', style: const TextStyle(color: Colors.red, fontSize: 12.5)),
        const Divider(height: 16),
        for (final it in s.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
                  Text('${fq(it.qty)} ${it.unit} x ${rp(it.price)}${it.discount > 0 ? '  (diskon ${rp(it.discount)})' : ''}',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12, height: 1.2)),
                ]),
              ),
              Text(rp(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const Divider(height: 14),
        kv('Subtotal', rp(s.subtotal)),
        if (s.discount > 0) kv('Diskon nota', '-${rp(s.discount)}'),
        kv('TOTAL', rp(s.total), bold: true),
        kv('Bayar (${s.method})', rp(s.paid)),
        if (s.isCash) kv('Kembali', rp(s.change)),
        if (app.isOwner) kv('Laba', rp(s.total - s.hpp)),
        if (s.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Catatan: ${s.note}')),
        const SizedBox(height: 12),
        if (!s.isVoid && app.can('perm_return'))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final ok = await returnFromSale(context, s.id);
                  if (ok) onChanged?.call();
                },
                icon: const Icon(Icons.assignment_return_rounded),
                label: const Text('Retur Barang dari Nota Ini'),
              ),
            ),
          ),
        Row(children: [
          if (app.can('perm_reprint'))
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () async {
                  final ok = await PrinterService.printSale(app, s, reprint: true);
                  if (ok) await Activity.log('penjualan', 'Cetak ulang struk', s.invoiceNo);
                },
                icon: const Icon(Icons.print_rounded),
                label: const Text('Cetak Ulang'),
              ),
            ),
          if (app.isOwner && !s.isVoid) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final reason = await inputDialog(ctx, title: 'Batalkan transaksi ${s.invoiceNo}', label: 'Alasan pembatalan');
                  if (reason == null) return;
                  if (reason.trim().isEmpty) {
                    Notify.warning('Alasan wajib diisi');
                    return;
                  }
                  await Repo.voidSale(s, reason.trim(), app.userName);
                  await Activity.log('penjualan', 'Batalkan transaksi',
                      '${s.invoiceNo} • ${rp(s.total)} • alasan: ${reason.trim()} • isi: ${s.items.map((e) => '${fq(e.qty)}x ${e.name}').join(', ')}');
                  await app.refreshLowStock();
                  app.dataChanged();
                  Notify.success('Transaksi dibatalkan, stok dikembalikan');
                  if (ctx.mounted) Navigator.pop(ctx);
                  onChanged?.call();
                },
                icon: const Icon(Icons.block_rounded),
                label: const Text('Batalkan'),
              ),
            ),
          ],
        ]),
      ]),
    ),
  );
}

/// Kumpulan isi rincian untuk kartu-kartu angka
class Details {
  static String period(DateTime a, DateTime b) => dbDay(a) == dbDay(b) ? fmtDayName(a) : '${fmtDate(a)} – ${fmtDate(b)}';

  static Future<void> sales(BuildContext context, DateTime from, DateTime to,
      {String title = 'Daftar Transaksi', bool onlyVoid = false, bool onlyDiscount = false, String? method, String? user, String? item}) {
    return showDataSheet(context, title: title, subtitle: period(from, to), load: () async {
      var l = await Repo.sales(from, to, withItems: true);
      if (onlyVoid) l = l.where((s) => s.isVoid).toList();
      if (onlyDiscount) l = l.where((s) => s.discount > 0 || s.items.any((i) => i.discount > 0)).toList();
      if (method != null) l = l.where((s) => !s.isVoid && s.method == method).toList();
      if (user != null) l = l.where((s) => !s.isVoid && s.userName == user).toList();
      if (item != null) l = l.where((s) => !s.isVoid && s.items.any((i) => i.name == item)).toList();
      return l
          .map((s) => DataItem(
                s.invoiceNo,
                sub: '${dbDay(from) == dbDay(to) ? fmtTime(s.createdAt) : '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)}'} • ${s.method} • '
                    '${s.userName} • ${s.items.length} brg${s.discount > 0 ? ' • diskon ${rp(s.discount)}' : ''}${s.isVoid ? ' • BATAL' : ''}',
                trailing: rp(s.total),
                strike: s.isVoid,
                color: s.isVoid ? Colors.red : null,
                onTap: () => showSaleDetail(context, s.id),
              ))
          .toList();
    }, footer: null);
  }

  static Future<void> itemsSold(BuildContext context, DateTime from, DateTime to) {
    return showDataSheet(context, title: 'Barang Terjual', subtitle: period(from, to), load: () async {
      final d = await Repo.report(from, to);
      var i = 0;
      return d.topItems.map((e) {
        i++;
        return DataItem('$i. ${e.name}', sub: 'Terjual ${fq(e.qty)} • ${e.count} transaksi', trailing: rp(e.total));
      }).toList();
    });
  }

  static Future<void> profit(BuildContext context, DateTime from, DateTime to) async {
    final l = await Repo.itemProfit(from, to);
    if (!context.mounted) return;
    final total = l.fold<int>(0, (a, e) => a + e.$4);
    await showDataSheet(context,
        title: 'Laba per Barang',
        subtitle: period(from, to),
        footer: 'Total laba kotor: ${rp(total)}',
        load: () async => l
            .map((e) => DataItem(e.$1,
                sub: 'Terjual ${fq(e.$2)} • omzet ${rp(e.$3)} • modal ${rp(e.$3 - e.$4)}',
                trailing: rp(e.$4),
                color: e.$4 < 0 ? Colors.red : Colors.green.shade700))
            .toList());
  }

  static Future<void> profitLoss(BuildContext context, DateTime from, DateTime to) async {
    final d = await Repo.report(from, to);
    if (!context.mounted) return;
    await showDataSheet(context, title: 'Laba Rugi', subtitle: period(from, to), load: () async {
      return [
        DataItem('Penjualan kotor', sub: '${d.trxCount} transaksi', trailing: rp(d.gross)),
        DataItem('Diskon', trailing: '-${rp(d.discount)}', color: Colors.red),
        if (d.returnSales > 0) DataItem('Retur penjualan', sub: '${d.returnCount} retur', trailing: '-${rp(d.returnSales)}', color: Colors.red),
        DataItem('Penjualan bersih', trailing: rp(d.netSales), bold: true),
        DataItem('Modal barang terjual (HPP)', sub: d.returnHpp > 0 ? 'sudah dikurangi retur ${rp(d.returnHpp)}' : '', trailing: '-${rp(d.hpp - d.returnHpp)}', color: Colors.red),
        DataItem('LABA KOTOR', sub: 'Margin ${d.margin.toStringAsFixed(1)}%', trailing: rp(d.grossProfit), bold: true, color: Colors.green.shade700),
        for (final e in d.expenseByCat) DataItem('Pengeluaran: ${e.name}', sub: '${e.count} kali', trailing: '-${rp(e.total)}', color: Colors.red),
        DataItem(d.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', trailing: rp(d.net), bold: true, color: d.net >= 0 ? Colors.teal : Colors.red),
      ];
    });
  }

  static Future<void> expenses(BuildContext context, DateTime from, DateTime to) {
    return showDataSheet(context, title: 'Pengeluaran', subtitle: period(from, to), load: () async {
      final l = await Repo.expenses(from, to);
      return l
          .map((e) => DataItem(e.category, sub: '${fmtDate(e.date)}${e.note.isEmpty ? '' : ' • ${e.note}'} • ${e.userName}', trailing: rp(e.amount)))
          .toList();
    });
  }

  static Future<void> purchases(BuildContext context, DateTime from, DateTime to) {
    return showDataSheet(context, title: 'Pembelian Barang', subtitle: period(from, to), load: () async {
      final l = await Repo.purchases(from, to, withItems: true);
      return l
          .map((p) => DataItem(
                '${p.invoiceNo}${p.supplierName.isEmpty ? '' : ' • ${p.supplierName}'}',
                sub: '${fmtDateShort(p.createdAt)} • ${p.items.map((i) => '${fq(i.qty)} ${i.name}').join(', ')}',
                trailing: rp(p.total),
                strike: p.isVoid,
              ))
          .toList();
    });
  }

  static Future<void> byGroup(BuildContext context, String title, DateTime from, DateTime to, List<NameTotal> items, String unit) {
    return showDataSheet(context,
        title: title,
        subtitle: period(from, to),
        load: () async => items.map((e) => DataItem(e.name.isEmpty ? '-' : e.name, sub: '${e.count} $unit', trailing: rp(e.total))).toList());
  }

  static Future<void> returns(BuildContext context, DateTime from, DateTime to, {String type = 'jual'}) {
    return showDataSheet(context, title: type == 'jual' ? 'Retur Penjualan' : 'Retur Pembelian', subtitle: period(from, to), load: () async {
      final l = await Repo.returns(from, to, type: type);
      return l
          .map((x) => DataItem(
                '${x.no}${x.refNo.isEmpty ? '' : ' • ${x.refNo}'}',
                sub: '${fmtDateShort(x.createdAt)} • ${x.settleLabel} • ${x.items.map((e) => '${fq(e.qty)} ${e.name}').join(', ')}',
                trailing: rp(x.total),
                strike: x.isVoid,
                onTap: () => showReturnDetail(context, x.id),
              ))
          .toList();
    });
  }

  /// mode: all | low | empty | value
  static Future<void> stock(BuildContext context, {String mode = 'all'}) {
    final app = context.read<AppState>();
    final title = switch (mode) {
      'low' => 'Stok Menipis',
      'empty' => 'Stok Habis',
      'value' => 'Nilai Stok per Barang',
      _ => 'Semua Barang',
    };
    return showDataSheet(context, title: title, subtitle: fmtDayName(DateTime.now()), load: () async {
      var l = await Repo.products(order: mode == 'value' ? 'name' : 'stock');
      if (mode == 'low') l = l.where((p) => p.isLow).toList();
      if (mode == 'empty') l = l.where((p) => p.stock <= 0).toList();
      if (mode == 'value') {
        l = l.where((p) => p.stock > 0).toList()..sort((a, b) => (b.stock * b.buyPrice).compareTo(a.stock * a.buyPrice));
      }
      final showBuy = app.can('perm_buy_price');
      return l
          .map((p) => DataItem(
                p.name,
                sub: mode == 'value'
                    ? '${fq(p.stock)} ${p.unit} x ${rp(showBuy ? p.buyPrice : p.sellPrice)}'
                    : 'Stok ${fq(p.stock)} ${p.unit} • min ${fq(p.minStock)}${p.barcode.isEmpty ? '' : ' • ${p.barcode}'}',
                trailing: mode == 'value' ? rp((p.stock * (showBuy ? p.buyPrice : p.sellPrice)).round()) : rp(p.sellPrice),
                color: mode == 'value' ? null : stockColor(context, p.stock, p.minStock),
              ))
          .toList();
    });
  }
}

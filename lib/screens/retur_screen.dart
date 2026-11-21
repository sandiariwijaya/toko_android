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
import 'pos_screen.dart';
import 'purchase_screen.dart' show ProductPicker;

/// Daftar retur penjualan & pembelian
class ReturScreen extends StatefulWidget {
  const ReturScreen({super.key});

  @override
  State<ReturScreen> createState() => _ReturScreenState();
}

class _ReturScreenState extends State<ReturScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = dayStart(DateTime.now());
  List<ReturnDoc> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final l = await Repo.returns(_from, _to);
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  Future<void> _new() async {
    final type = _tab.index == 0 ? 'jual' : 'beli';
    final ok = await startReturn(context, type);
    if (ok) _load();
  }

  Widget _listFor(String type) {
    final cs = Theme.of(context).colorScheme;
    final l = _list.where((e) => e.type == type).toList();
    final total = l.where((e) => !e.isVoid).fold<int>(0, (a, e) => a + e.total);
    if (l.isEmpty) {
      return EmptyState(
        icon: Icons.assignment_return_outlined,
        title: type == 'jual' ? 'Belum ada retur penjualan' : 'Belum ada retur pembelian',
        subtitle: 'Tekan "Retur Baru" untuk membuat retur',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
      itemCount: l.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.all(4),
            child: Text('${l.where((e) => !e.isVoid).length} retur • Total ${rp(total)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          );
        }
        final x = l[i - 1];
        return SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onTap: () async {
            await showReturnDetail(context, x.id);
            _load();
          },
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: (x.isVoid ? Colors.red : Colors.deepOrange).withOpacity(0.12),
              child: Icon(x.isVoid ? Icons.block_rounded : Icons.assignment_return_rounded, size: 18, color: x.isVoid ? Colors.red : Colors.deepOrange),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.no, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.2)),
                Text(
                  '${fmtDateShort(x.createdAt)} ${fmtTime(x.createdAt)}${x.refNo.isEmpty ? '' : ' • ${x.refNo}'}'
                  '${x.party.isEmpty ? '' : ' • ${x.party}'} • ${x.settleLabel}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.2),
                ),
                Text(x.items.map((e) => '${fq(e.qty)} ${e.name}${e.cond == 'rusak' ? ' (rusak)' : ''}').join(', '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, height: 1.2)),
              ]),
            ),
            Text(rp(x.total), style: TextStyle(fontWeight: FontWeight.w900, decoration: x.isVoid ? TextDecoration.lineThrough : null)),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final canBuy = app.can('perm_purchase') || app.isOwner;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Retur Barang'),
        bottom: TabBar(controller: _tab, tabs: const [Tab(text: 'Retur Penjualan'), Tab(text: 'Retur Pembelian')]),
      ),
      floatingActionButton: (_tab.index == 1 && !canBuy)
          ? null
          : FloatingActionButton.extended(onPressed: _new, icon: const Icon(Icons.add_rounded), label: const Text('Retur Baru')),
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
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(controller: _tab, children: [_listFor('jual'), _listFor('beli')]),
        ),
      ]),
    );
  }
}

// ============================================================================ MULAI RETUR
/// Mulai retur: pilih nota lalu isi form. Mengembalikan true bila retur tersimpan.
Future<bool> startReturn(BuildContext context, String type) async {
  if (type == 'jual') {
    final s = await showModalBottomSheet<Sale>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _SalePicker(),
    );
    if (s == null || !context.mounted) return false;
    return returnFromSale(context, s.id);
  } else {
    final r = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const _PurchasePicker(),
    );
    if (r == null || !context.mounted) return false;
    if (r is Purchase) return returnFromPurchase(context, r.id);
    final x = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const ReturnForm(type: 'beli', lines: [])));
    return x == true;
  }
}

/// Retur dari nota penjualan
Future<bool> returnFromSale(BuildContext context, int saleId) async {
  final s = await Repo.saleById(saleId);
  if (s == null || !context.mounted) return false;
  if (s.isVoid) {
    Notify.warning('Nota ini sudah dibatalkan');
    return false;
  }
  final done = await Repo.returnedQty('jual', s.id);
  // nilai bersih per satuan: sudah termasuk diskon barang & diskon nota (proporsional)
  final ratio = s.subtotal <= 0 ? 1.0 : s.total / s.subtotal;
  final lines = <ReturnLine>[];
  for (final it in s.items) {
    final left = it.qty - (done[it.productId] ?? 0);
    if (left <= 0) continue;
    final unit = it.qty <= 0 ? it.price : (it.subtotal / it.qty * ratio).round();
    lines.add(ReturnLine(
      productId: it.productId,
      name: it.name,
      unit: it.unit,
      maxQty: left,
      price: unit,
      buyPrice: it.buyPrice,
    ));
  }
  if (lines.isEmpty) {
    Notify.info('Semua barang di nota ${s.invoiceNo} sudah diretur');
    return false;
  }
  if (!context.mounted) return false;
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => ReturnForm(type: 'jual', refId: s.id, refNo: s.invoiceNo, party: s.customer, refDate: s.createdAt, lines: lines)),
  );
  return r == true;
}

/// Retur dari nota pembelian
Future<bool> returnFromPurchase(BuildContext context, int purchaseId) async {
  final pb = await Repo.purchaseById(purchaseId);
  if (pb == null || !context.mounted) return false;
  if (pb.isVoid) {
    Notify.warning('Nota pembelian ini sudah dibatalkan');
    return false;
  }
  final done = await Repo.returnedQty('beli', pb.id);
  final lines = <ReturnLine>[];
  for (final it in pb.items) {
    final left = it.qty - (done[it.productId] ?? 0);
    if (left <= 0) continue;
    lines.add(ReturnLine(
      productId: it.productId,
      name: it.name,
      unit: it.unit,
      maxQty: left,
      price: it.buyPrice,
      buyPrice: it.buyPrice,
    ));
  }
  if (lines.isEmpty) {
    Notify.info('Semua barang di nota ${pb.invoiceNo} sudah diretur');
    return false;
  }
  if (!context.mounted) return false;
  final r = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
        builder: (_) => ReturnForm(type: 'beli', refId: pb.id, refNo: pb.invoiceNo, party: pb.supplierName, refDate: pb.createdAt, lines: lines)),
  );
  return r == true;
}

// ============================================================================ PEMILIH NOTA
class _SalePicker extends StatefulWidget {
  const _SalePicker();

  @override
  State<_SalePicker> createState() => _SalePickerState();
}

class _SalePickerState extends State<_SalePicker> {
  List<Sale>? _list;
  String _q = '';
  int _days = 30;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final now = dayStart(DateTime.now());
    final l = await Repo.sales(now.subtract(Duration(days: _days)), now, withItems: true);
    if (mounted) setState(() => _list = l.where((s) => !s.isVoid).toList());
  }

  Future<void> _scan() async {
    final code = await ScannerPage.scanOnce(context, title: 'Scan barcode struk');
    if (code == null || !mounted) return;
    final db = await Db.instance;
    final r = await db.query('sales', columns: ['id'], where: 'invoice_no=?', whereArgs: [code.trim()]);
    if (!mounted) return;
    if (r.isEmpty) {
      Notify.error('Nota $code tidak ditemukan');
      return;
    }
    final s = await Repo.saleById(r.first['id'] as int);
    if (s != null && mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _q.toLowerCase().trim();
    final all = _list;
    final list = all == null
        ? <Sale>[]
        : all
            .where((s) =>
                t.isEmpty ||
                s.invoiceNo.toLowerCase().contains(t) ||
                s.customer.toLowerCase().contains(t) ||
                s.items.any((i) => i.name.toLowerCase().contains(t) || i.barcode.contains(t)))
            .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Pilih Nota Penjualan', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _q = v),
                decoration: const InputDecoration(hintText: 'No nota / pelanggan / nama barang', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(tooltip: 'Scan barcode struk', onPressed: _scan, icon: const Icon(Icons.qr_code_scanner_rounded)),
          ]),
        ),
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
            for (final d in [7, 30, 90])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text('$d hari'),
                  selected: _days == d,
                  onSelected: (_) {
                    setState(() {
                      _days = d;
                      _list = null;
                    });
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: all == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.receipt_long_outlined, title: 'Nota tidak ditemukan')
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14),
                      itemBuilder: (_, i) {
                        final s = list[i];
                        return ListTile(
                          title: Text(s.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)} • ${s.method}${s.customer.isEmpty ? '' : ' • ${s.customer}'}\n'
                            '${s.items.map((e) => '${fq(e.qty)} ${e.name}').join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          trailing: Text(rp(s.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

class _PurchasePicker extends StatefulWidget {
  const _PurchasePicker();

  @override
  State<_PurchasePicker> createState() => _PurchasePickerState();
}

class _PurchasePickerState extends State<_PurchasePicker> {
  List<Purchase>? _list;
  String _q = '';

  @override
  void initState() {
    super.initState();
    final now = dayStart(DateTime.now());
    Repo.purchases(now.subtract(const Duration(days: 120)), now, withItems: true).then((l) {
      if (mounted) setState(() => _list = l.where((p) => !p.isVoid).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _q.toLowerCase().trim();
    final all = _list;
    final list = all == null
        ? <Purchase>[]
        : all
            .where((p) =>
                t.isEmpty ||
                p.invoiceNo.toLowerCase().contains(t) ||
                p.refNo.toLowerCase().contains(t) ||
                p.supplierName.toLowerCase().contains(t) ||
                p.items.any((i) => i.name.toLowerCase().contains(t)))
            .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.88,
      child: Column(children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('Pilih Nota Pembelian', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(hintText: 'No nota / faktur / supplier / barang', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, 'manual'),
              icon: const Icon(Icons.playlist_add_rounded),
              label: const Text('Retur tanpa nota (pilih barang manual)'),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: all == null
              ? const Center(child: CircularProgressIndicator())
              : list.isEmpty
                  ? const EmptyState(icon: Icons.local_shipping_outlined, title: 'Nota pembelian tidak ditemukan')
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, indent: 14, endIndent: 14),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        return ListTile(
                          title: Text('${p.invoiceNo}${p.supplierName.isEmpty ? '' : ' • ${p.supplierName}'}',
                              style: const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                            '${fmtDateShort(p.createdAt)}${p.refNo.isEmpty ? '' : ' • faktur ${p.refNo}'}\n'
                            '${p.items.map((e) => '${fq(e.qty)} ${e.name}').join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          trailing: Text(rp(p.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                          onTap: () => Navigator.pop(context, p),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

// ============================================================================ FORM RETUR
class ReturnForm extends StatefulWidget {
  final String type; // jual | beli
  final int? refId;
  final String refNo;
  final String party;
  final DateTime? refDate;
  final List<ReturnLine> lines;
  const ReturnForm({super.key, required this.type, this.refId, this.refNo = '', this.party = '', this.refDate, required this.lines});

  @override
  State<ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<ReturnForm> {
  late final List<ReturnLine> _lines = List.of(widget.lines);
  late final _party = TextEditingController(text: widget.party);
  final _note = TextEditingController();
  late String _settle = widget.type == 'jual' ? 'uang' : 'potong';
  List<Supplier> _suppliers = [];
  bool _saving = false;

  bool get _sale => widget.type == 'jual';
  bool get _manual => widget.refId == null;
  int get _total => _lines.fold<int>(0, (a, l) => a + l.subtotal);
  double get _count => _lines.fold<double>(0, (a, l) => a + l.qty);

  @override
  void initState() {
    super.initState();
    if (!_sale) {
      Repo.suppliers().then((v) {
        if (mounted) setState(() => _suppliers = v);
      });
    }
  }

  @override
  void dispose() {
    _party.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addManual() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const ProductPicker(),
    );
    if (p == null || p.id == null) return;
    if (_lines.any((l) => l.productId == p.id)) return;
    if (p.stock <= 0) {
      Notify.warning('Stok ${p.name} kosong, tidak bisa diretur');
      return;
    }
    setState(() => _lines.add(ReturnLine(
          productId: p.id!,
          name: p.name,
          unit: p.unit,
          maxQty: p.stock,
          price: p.buyPrice,
          buyPrice: p.buyPrice,
          qty: 1,
        )));
  }

  void _setQty(ReturnLine l, double q) {
    var v = q;
    if (v < 0) v = 0;
    if (v > l.maxQty) {
      v = l.maxQty;
      Notify.info('Maksimal ${fq(l.maxQty)} ${l.unit}');
    }
    setState(() => l.qty = v);
  }

  Future<void> _save() async {
    if (_saving) return;
    final used = _lines.where((l) => l.qty > 0).toList();
    if (used.isEmpty) {
      Notify.warning('Isi jumlah barang yang diretur');
      return;
    }
    final app = context.read<AppState>();
    var info = '${fq(_count)} barang • ${rp(_total)}\n${ReturnDoc.settleLabels[_settle] ?? _settle}';
    if (_sale) {
      if (used.any((l) => l.cond == 'bagus')) info += '\nBarang kondisi bagus kembali ke stok.';
      if (used.any((l) => l.cond == 'rusak')) info += '\nBarang rusak tidak masuk stok.';
    } else {
      info += '\nStok barang berkurang.';
    }
    final ok = await confirmDialog(context, title: 'Simpan retur?', message: info, okText: 'Simpan');
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final x = await Repo.createReturn(
        type: widget.type,
        refId: widget.refId,
        refNo: widget.refNo,
        party: _party.text,
        lines: used,
        settle: _settle,
        note: _note.text,
        user: app.userName,
      );
      await Activity.log(
        _sale ? 'penjualan' : 'pembelian',
        _sale ? 'Retur penjualan' : 'Retur pembelian',
        '${x.no}${x.refNo.isEmpty ? '' : ' (nota ${x.refNo})'} • ${rp(x.total)} • ${x.settleLabel} • '
            '${x.items.map((e) => '${fq(e.qty)}x ${e.name}${e.cond == 'rusak' ? ' (rusak)' : ''}').join(', ')}',
      );
      final prods = <Product>[];
      for (final it in x.items) {
        final p = await Repo.productById(it.productId);
        if (p != null) prods.add(p);
      }
      await StockAlert.afterChange(app, prods);
      app.dataChanged();
      if (_sale && _settle == 'tukar') {
        PosScreen.returCredit = x.total;
        PosScreen.returCreditNo = x.no;
      }
      if (!mounted) return;
      var msg = '${x.no}\nTotal ${rp(x.total)}';
      if (_sale && _settle == 'uang') msg += '\n\nKembalikan uang ${rp(x.total)} ke pelanggan.';
      if (_sale && _settle == 'tukar') msg += '\n\nPotongan ${rp(x.total)} sudah disiapkan di halaman Penjualan untuk barang pengganti.';
      final print = await confirmDialog(context, title: 'Retur tersimpan', message: msg, okText: 'Cetak Nota Retur', icon: Icons.check_circle_rounded);
      if (print) await PrinterService.printItems(app, Receipts.retur(app, x), okMsg: 'Nota retur dicetak');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      Notify.error('Gagal menyimpan retur: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settles = _sale ? ['uang', 'tukar'] : ['potong', 'uang', 'ganti'];
    return Scaffold(
      appBar: AppBar(title: Text(_sale ? 'Retur Penjualan' : 'Retur Pembelian')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: [
          if (widget.refNo.isNotEmpty)
            SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Icon(_sale ? Icons.receipt_long_rounded : Icons.local_shipping_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Nota ${widget.refNo}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (widget.refDate != null)
                      Text(fmtDateTime(widget.refDate!), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          if (_sale)
            TextField(controller: _party, decoration: inputDeco('Nama pelanggan (opsional)', icon: Icons.person_outline_rounded))
          else
            Autocomplete<String>(
              initialValue: TextEditingValue(text: widget.party),
              optionsBuilder: (v) => _suppliers.map((e) => e.name).where((n) => n.toLowerCase().contains(v.text.toLowerCase())),
              onSelected: (v) => _party.text = v,
              fieldViewBuilder: (ctx, c, f, onSubmit) => TextField(
                controller: c,
                focusNode: f,
                onChanged: (v) => _party.text = v,
                decoration: inputDeco('Supplier', icon: Icons.store_mall_directory_outlined),
              ),
            ),
          SectionTitle(_sale ? 'BARANG YANG DIKEMBALIKAN PELANGGAN' : 'BARANG YANG DIKEMBALIKAN KE SUPPLIER',
              trailing: _manual
                  ? TextButton.icon(onPressed: _addManual, icon: const Icon(Icons.add_rounded), label: const Text('Barang'))
                  : null),
          if (_lines.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Tekan "+ Barang" untuk memilih barang yang diretur')),
          for (final l in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SoftCard(
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(l.name, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
                        Text('${rp(l.price)} / ${l.unit} • maks ${fq(l.maxQty)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ]),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setQty(l, l.qty - 1),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final q = await qtyDialog(context, title: l.name, initial: l.qty == 0 ? 1 : l.qty, unit: l.unit);
                        if (q != null) _setQty(l, q);
                      },
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 36),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: l.qty > 0 ? cs.primaryContainer : cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(fq(l.qty), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setQty(l, l.qty + 1),
                      icon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                    if (_manual)
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _lines.remove(l)),
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ]),
                  if (l.qty > 0)
                    Row(children: [
                      Expanded(
                        child: Wrap(spacing: 6, runSpacing: 4, children: [
                          if (_sale) ...[
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('Bagus (masuk stok)'),
                              selected: l.cond == 'bagus',
                              onSelected: (_) => setState(() => l.cond = 'bagus'),
                            ),
                            ChoiceChip(
                              visualDensity: VisualDensity.compact,
                              label: const Text('Rusak'),
                              selected: l.cond == 'rusak',
                              selectedColor: Colors.red.shade100,
                              onSelected: (_) => setState(() => l.cond = 'rusak'),
                            ),
                          ],
                        ]),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8, left: 6),
                        child: Text(rp(l.subtotal), style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
                      ),
                    ]),
                ]),
              ),
            ),
          if (!_manual && _lines.length > 1)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  for (final l in _lines) {
                    l.qty = l.maxQty;
                  }
                }),
                child: const Text('Retur semua barang'),
              ),
            ),
          const SectionTitle('PENYELESAIAN'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in settles)
              ChoiceChip(
                label: Text(ReturnDoc.settleLabels[s] ?? s),
                selected: _settle == s,
                onSelected: (_) => setState(() => _settle = s),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: Text(
              switch (_settle) {
                'uang' => _sale ? 'Uang dikembalikan ke pelanggan sebesar total retur.' : 'Supplier mengembalikan uang sebesar total retur.',
                'tukar' => 'Total retur menjadi potongan di transaksi penjualan berikutnya (barang pengganti).',
                'potong' => 'Total retur memotong tagihan / pembayaran ke supplier berikutnya.',
                _ => 'Supplier mengganti barang. Saat barang pengganti datang, catat lewat menu Pembelian.',
              },
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          TextField(controller: _note, decoration: inputDeco('Alasan / keterangan (mis. kedaluwarsa, kemasan rusak)', icon: Icons.notes_rounded)),
          const SizedBox(height: 80),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(color: cs.surface, border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5)))),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${fq(_count)} barang diretur', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                Text(rp(_total), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              ]),
            ),
            FilledButton.icon(
              onPressed: _saving || _count <= 0 ? null : _save,
              icon: const Icon(Icons.assignment_return_rounded),
              label: const Text('SIMPAN RETUR', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ============================================================================ RINCIAN RETUR
Future<void> showReturnDetail(BuildContext context, int id) async {
  final x = await Repo.returnById(id);
  if (x == null || !context.mounted) return;
  final app = context.read<AppState>();
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), children: [
        Row(children: [
          Expanded(child: Text(x.no, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
          if (x.isVoid) const Pill('DIBATALKAN', color: Colors.red),
        ]),
        Text('${x.isSale ? 'Retur penjualan' : 'Retur pembelian'} • ${fmtDayName(x.createdAt)} ${fmtTime(x.createdAt)} • ${x.userName}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
        if (x.refNo.isNotEmpty) Text('Dari nota: ${x.refNo}', style: const TextStyle(fontSize: 12.5)),
        if (x.party.isNotEmpty) Text('${x.isSale ? 'Pelanggan' : 'Supplier'}: ${x.party}', style: const TextStyle(fontSize: 12.5)),
        Text('Penyelesaian: ${x.settleLabel}', style: const TextStyle(fontSize: 12.5)),
        if (x.note.isNotEmpty) Text('Keterangan: ${x.note}', style: const TextStyle(fontSize: 12.5)),
        if (x.isVoid) Text('Alasan batal: ${x.voidReason}', style: const TextStyle(color: Colors.red, fontSize: 12.5)),
        const Divider(height: 16),
        for (final it in x.items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700, height: 1.2)),
                  Text('${fq(it.qty)} ${it.unit} x ${rp(it.price)}${x.isSale ? ' • ${it.cond == 'rusak' ? 'RUSAK (tidak masuk stok)' : 'bagus (masuk stok)'}' : ''}',
                      style: TextStyle(fontSize: 12, color: it.cond == 'rusak' ? Colors.red : cs.onSurfaceVariant, height: 1.2)),
                ]),
              ),
              Text(rp(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        const Divider(height: 14),
        Row(children: [
          const Expanded(child: Text('TOTAL RETUR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          Text(rp(x.total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: () => PrinterService.printItems(app, Receipts.retur(app, x), okMsg: 'Nota retur dicetak'),
              icon: const Icon(Icons.print_rounded),
              label: const Text('Cetak'),
            ),
          ),
          if (app.isOwner && !x.isVoid) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  final reason = await inputDialog(ctx, title: 'Batalkan retur ${x.no}', label: 'Alasan pembatalan');
                  if (reason == null) return;
                  if (reason.trim().isEmpty) {
                    Notify.warning('Alasan wajib diisi');
                    return;
                  }
                  await Repo.voidReturn(x, reason.trim(), app.userName);
                  await Activity.log(x.isSale ? 'penjualan' : 'pembelian', 'Batalkan retur', '${x.no} • ${rp(x.total)} • alasan: ${reason.trim()}');
                  await app.refreshLowStock();
                  app.dataChanged();
                  Notify.success('Retur dibatalkan, stok dikembalikan seperti semula');
                  if (ctx.mounted) Navigator.pop(ctx);
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

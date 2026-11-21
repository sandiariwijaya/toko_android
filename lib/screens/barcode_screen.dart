import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import 'purchase_screen.dart' show ProductPicker;

/// Cetak barcode / label harga ke printer thermal atau PDF
class BarcodeScreen extends StatefulWidget {
  final List<Product>? initial;
  const BarcodeScreen({super.key, this.initial});

  @override
  State<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends State<BarcodeScreen> {
  final List<MapEntry<Product, int>> _items = [];

  @override
  void initState() {
    super.initState();
    for (final p in widget.initial ?? <Product>[]) {
      _items.add(MapEntry(p, 1));
    }
  }

  Future<void> _add() async {
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => const ProductPicker(),
    );
    if (p == null) return;
    if (_items.any((e) => e.key.id == p.id)) return;
    setState(() => _items.add(MapEntry(p, 1)));
  }

  Future<void> _addNoBarcode() async {
    final all = await Repo.products();
    final no = all.where((p) => p.barcode.trim().isEmpty).toList();
    if (!mounted) return;
    if (no.isEmpty) {
      Notify.info('Semua barang sudah punya barcode');
      return;
    }
    final ok = await confirmDialog(context,
        title: 'Buat barcode otomatis',
        message: '${no.length} barang belum punya barcode. Buatkan barcode otomatis lalu masukkan ke daftar cetak?',
        okText: 'Buat');
    if (!ok) return;
    final app = context.read<AppState>();
    for (final p in no) {
      p.barcode = await Repo.newBarcode();
      await Repo.saveProduct(p, user: app.userName);
      if (!_items.any((e) => e.key.id == p.id)) _items.add(MapEntry(p, 1));
    }
    await Activity.log('barang', 'Buat barcode otomatis', '${no.length} barang');
    setState(() {});
    Notify.success('${no.length} barcode dibuat');
  }

  Future<void> _ensureCode(int i) async {
    final p = _items[i].key;
    if (p.barcode.trim().isNotEmpty) return;
    final app = context.read<AppState>();
    p.barcode = await Repo.newBarcode();
    await Repo.saveProduct(p, user: app.userName);
    await Activity.log('barang', 'Buat barcode otomatis', '${p.name}: ${p.barcode}');
    setState(() {});
  }

  int get _count => _items.where((e) => e.key.barcode.trim().isNotEmpty).fold<int>(0, (a, e) => a + e.value);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Cetak Barcode')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add_rounded), label: const Text('Pilih Barang')),
      body: MaxWidth(
        width: 860,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Isi label', style: TextStyle(fontWeight: FontWeight.w800)),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Tampilkan nama barang'),
                value: app.b('bc_show_name'),
                onChanged: (v) => app.set('bc_show_name', v ? '1' : '0'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Tampilkan harga jual'),
                value: app.b('bc_show_price'),
                onChanged: (v) => app.set('bc_show_price', v ? '1' : '0'),
              ),
              Row(children: [
                const Text('Tinggi barcode (thermal)'),
                Expanded(
                  child: Slider(
                    min: 40,
                    max: 140,
                    divisions: 10,
                    value: app.i('bc_height', 60).clamp(40, 140).toDouble(),
                    label: '${app.i('bc_height', 60)}',
                    onChanged: (v) => app.set('bc_height', '${v.round()}'),
                  ),
                ),
              ]),
              TextButton.icon(
                onPressed: _addNoBarcode,
                icon: const Icon(Icons.auto_awesome_rounded),
                label: const Text('Buat barcode untuk barang yang belum punya'),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (_items.isEmpty)
            const SizedBox(height: 260, child: EmptyState(icon: Icons.qr_code_2_rounded, title: 'Belum ada barang dipilih', subtitle: 'Tekan "Pilih Barang"')),
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_items[i].key.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      _items[i].key.barcode.isEmpty
                          ? TextButton(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                              onPressed: () => _ensureCode(i),
                              child: const Text('Belum ada barcode - buat otomatis'),
                            )
                          : Text('${_items[i].key.barcode} • ${rp(_items[i].key.sellPrice)}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      if (_items[i].value > 1) _items[i] = MapEntry(_items[i].key, _items[i].value - 1);
                    }),
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('${_items[i].value}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  IconButton(
                    onPressed: () => setState(() => _items[i] = MapEntry(_items[i].key, _items[i].value + 1)),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                  IconButton(onPressed: () => setState(() => _items.removeAt(i)), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
            ),
        ]),
      ),
      bottomNavigationBar: _items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => LabelExport.pdf(app, _items),
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('PDF (A4)')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: () async {
                        if (_count == 0) {
                          Notify.warning('Tidak ada barang yang punya barcode');
                          return;
                        }
                        final ok = await PrinterService.printItems(app, Receipts.labels(app, _items), okMsg: '$_count label dicetak');
                        if (ok) await Activity.log('barang', 'Cetak label barcode (thermal)', '$_count label');
                      },
                      icon: const Icon(Icons.print_rounded),
                      label: Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text('Cetak Thermal ($_count)')),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}

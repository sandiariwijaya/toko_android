import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/export.dart';
import '../services/native.dart';
import '../services/product_import.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

/// Upload file Excel berisi nama barang & harga
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  List<ImportRow>? _rows;
  bool _busy = false;
  bool _overwriteStock = false;
  String _file = '';

  Future<void> _pick() async {
    try {
      final path = await Native.pickFile();
      if (path == null) return;
      setState(() => _busy = true);
      final bytes = await File(path).readAsBytes();
      final rows = await ProductImport.parse(bytes);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _file = 'File dipilih (${rows.length} baris)';
        _busy = false;
      });
      if (rows.isEmpty) Notify.warning('Tidak ada data barang di file');
    } on FormatException catch (e) {
      setState(() => _busy = false);
      Notify.error('File tidak bisa dibaca: ${e.message}. Pastikan format .xlsx');
    } catch (e) {
      setState(() => _busy = false);
      Notify.error('Gagal membaca file: $e');
    }
  }

  Future<void> _import() async {
    final rows = _rows;
    if (rows == null) return;
    final app = context.read<AppState>();
    final ok = await confirmDialog(context,
        title: 'Import data barang?',
        message: '${rows.where((r) => r.valid && r.isNew).length} barang baru dan ${rows.where((r) => r.valid && !r.isNew).length} barang diperbarui.',
        okText: 'Import');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      final r = await ProductImport.apply(rows, overwriteStock: _overwriteStock, user: app.userName, defaultMin: app.i('default_min_stock', 0));
      await app.refreshLowStock();
      if (!mounted) return;
      Notify.success('Selesai: ${r.added} baru, ${r.updated} diperbarui${r.skipped > 0 ? ', ${r.skipped} dilewati' : ''}');
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _busy = false);
      Notify.error('Import gagal: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = _rows;
    final valid = rows?.where((r) => r.valid).length ?? 0;
    final news = rows?.where((r) => r.valid && r.isNew).length ?? 0;
    final upd = rows?.where((r) => r.valid && !r.isNew).length ?? 0;
    final err = rows?.where((r) => !r.valid).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Import Barang dari Excel')),
      body: MaxWidth(
        width: 820,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Langkah', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 8),
              const Text('1. Unduh template Excel, lalu isi di Excel / WPS / Google Sheets.\n'
                  '2. Kolom: Barcode, Nama Barang, Kategori, Satuan, Harga Beli, Harga Jual, Stok, Stok Minimum.\n'
                  '3. Simpan sebagai .xlsx lalu pilih file di bawah.\n'
                  '4. Barang dengan barcode/nama yang sudah ada akan diperbarui.'),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => FileOut.saveAndOpen(ReportExport.templateXlsx(), 'Template_Data_Barang.xlsx', kXlsxMime, sub: 'Template'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Unduh Template'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.upload_file_rounded),
                  label: const Text('Pilih File Excel'),
                ),
              ]),
              if (_file.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_file)),
            ]),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          if (rows != null && !_busy) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: StatCard(title: 'Barang baru', value: '$news', icon: Icons.fiber_new_rounded, color: Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: StatCard(title: 'Diperbarui', value: '$upd', icon: Icons.update_rounded, color: Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: StatCard(title: 'Error', value: '$err', icon: Icons.error_outline_rounded, color: Colors.red)),
            ]),
            SwitchListTile(
              value: _overwriteStock,
              onChanged: (v) => setState(() => _overwriteStock = v),
              title: const Text('Timpa stok barang yang sudah ada'),
              subtitle: const Text('Jika mati, stok barang lama tidak diubah (hanya nama, harga, kategori). Barang baru tetap memakai stok dari file.'),
            ),
            const SectionTitle('PRATINJAU'),
            for (final r in rows.take(300))
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    backgroundColor: (!r.valid ? Colors.red : (r.isNew ? Colors.green : Colors.blue)).withOpacity(0.15),
                    child: Text('${r.line}', style: const TextStyle(fontSize: 11)),
                  ),
                  title: Text(r.name.isEmpty ? '(tanpa nama)' : r.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(!r.valid
                      ? r.error
                      : '${r.isNew ? 'BARU' : 'UPDATE'} • ${r.barcode.isEmpty ? 'barcode otomatis' : r.barcode} • ${r.category.isEmpty ? '-' : r.category} • '
                          'beli ${nf(r.buy)} • jual ${nf(r.sell)} • stok ${fq(r.stock)}'),
                ),
              ),
            if (rows.length > 300) Text('... dan ${rows.length - 300} baris lainnya', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 80),
          ],
        ]),
      ),
      bottomNavigationBar: rows == null || valid == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.cloud_done_rounded),
                    label: Text('IMPORT $valid BARANG', style: const TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../services/xlsx.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

const Map<String, (String, IconData, Color)> kLogTypes = {
  'akses': ('Login / Akses', Icons.login_rounded, Colors.blue),
  'penjualan': ('Penjualan', Icons.point_of_sale_rounded, Colors.green),
  'pembelian': ('Pembelian', Icons.local_shipping_rounded, Colors.teal),
  'harga': ('Perubahan harga', Icons.sell_rounded, Colors.orange),
  'stok': ('Perubahan stok', Icons.inventory_rounded, Colors.deepOrange),
  'barang': ('Data barang', Icons.inventory_2_rounded, Colors.indigo),
  'pengeluaran': ('Pengeluaran', Icons.payments_rounded, Colors.red),
  'supplier': ('Supplier', Icons.groups_rounded, Colors.brown),
  'pengguna': ('Pengguna', Icons.manage_accounts_rounded, Colors.purple),
  'pengaturan': ('Pengaturan', Icons.settings_rounded, Colors.blueGrey),
  'data': ('Backup / Ekspor', Icons.cloud_rounded, Colors.cyan),
};

/// Log aktivitas — HANYA OWNER
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  DateTime _from = dayStart(DateTime.now()).subtract(const Duration(days: 6));
  DateTime _to = dayStart(DateTime.now());
  String _type = '';
  String _q = '';
  List<LogEntry> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.logs(from: _from, to: _to, type: _type, q: _q);
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  Future<void> _export() async {
    final wb = XlsxBuilder();
    final s = wb.sheet('Log Aktivitas', [20, 18, 18, 30, 70]);
    s.row([for (final h in ['Waktu', 'Pengguna', 'Jenis', 'Aktivitas', 'Detail']) XC.header(h)]);
    for (final e in _list) {
      s.row([XC.text(dbDateTime(e.date)), XC.text(e.userName), XC.text(kLogTypes[e.type]?.$1 ?? e.type), XC.text(e.action), XC.text(e.detail)]);
    }
    await FileOut.saveAndOpen(wb.build(), 'Log_Aktivitas_${dbDay(_from)}_sd_${dbDay(_to)}.xlsx', kXlsxMime);
  }

  Future<void> _clear() async {
    final ok = await confirmDialog(context,
        title: 'Hapus log lama?', message: 'Log yang lebih lama dari 6 bulan akan dihapus permanen.', danger: true, okText: 'Hapus');
    if (!ok) return;
    final now = DateTime.now();
    final n = await Repo.clearLogs(DateTime(now.year, now.month - 6, now.day));
    await Activity.log('data', 'Hapus log lama', '$n baris');
    Notify.success('$n log lama dihapus');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.isOwner) {
      return Scaffold(
        appBar: AppBar(title: const Text('Log Aktivitas')),
        body: const EmptyState(icon: Icons.lock_rounded, title: 'Khusus owner', subtitle: 'Halaman log hanya bisa dilihat oleh owner'),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Aktivitas'),
        actions: [
          IconButton(tooltip: 'Ekspor Excel', onPressed: _export, icon: const Icon(Icons.grid_on_rounded)),
          IconButton(tooltip: 'Hapus log lama', onPressed: _clear, icon: const Icon(Icons.auto_delete_outlined)),
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
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                  label: const Text('Semua'),
                  selected: _type.isEmpty,
                  onSelected: (_) {
                    _type = '';
                    _load();
                  }),
            ),
            for (final e in kLogTypes.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(e.value.$2, size: 16),
                  label: Text(e.value.$1),
                  selected: _type == e.key,
                  onSelected: (_) {
                    _type = e.key;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: TextField(
            onChanged: (v) {
              _q = v;
              _load();
            },
            decoration: const InputDecoration(hintText: 'Cari aktivitas / pengguna / detail', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _list.isEmpty
                  ? const EmptyState(icon: Icons.history_rounded, title: 'Tidak ada log')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final e = _list[i];
                        final t = kLogTypes[e.type] ?? ('Lainnya', Icons.info_outline_rounded, Colors.grey);
                        final danger = e.action.toLowerCase().contains('batal') ||
                            e.action.toLowerCase().contains('hapus') ||
                            e.action.toLowerCase().contains('gagal') ||
                            e.action.toLowerCase().contains('restore');
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: t.$3.withOpacity(0.14), child: Icon(t.$2, color: t.$3, size: 20)),
                          title: Text(e.action, style: TextStyle(fontWeight: FontWeight.w700, color: danger ? Colors.red : null)),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            if (e.detail.isNotEmpty) Text(e.detail),
                            Text('${fmtDateTime(e.date)} • ${e.userName}', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                          ]),
                          isThreeLine: e.detail.isNotEmpty,
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

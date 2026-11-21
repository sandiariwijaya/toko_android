import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key});

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  List<Supplier> _list = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.suppliers(_q);
    if (mounted) setState(() => _list = l);
  }

  Future<void> _edit([Supplier? s]) async {
    final name = TextEditingController(text: s?.name ?? '');
    final phone = TextEditingController(text: s?.phone ?? '');
    final addr = TextEditingController(text: s?.address ?? '');
    final note = TextEditingController(text: s?.note ?? '');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(s == null ? 'Supplier Baru' : 'Ubah Supplier', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(controller: name, autofocus: s == null, decoration: inputDeco('Nama supplier', icon: Icons.store_rounded)),
            const SizedBox(height: 10),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: inputDeco('No. HP / WA', icon: Icons.phone_rounded)),
            const SizedBox(height: 10),
            TextField(controller: addr, decoration: inputDeco('Alamat', icon: Icons.place_rounded)),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: inputDeco('Catatan (sales, jadwal kirim, dll)', icon: Icons.notes_rounded)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.save_rounded),
              label: const Padding(padding: EdgeInsets.all(12), child: Text('SIMPAN')),
            ),
          ]),
        ),
      ),
    );
    if (ok == true) {
      if (name.text.trim().isEmpty) {
        Notify.warning('Nama supplier wajib diisi');
      } else {
        final x = Supplier(id: s?.id, name: name.text, phone: phone.text, address: addr.text, note: note.text);
        await Repo.saveSupplier(x);
        await Activity.log('supplier', s == null ? 'Tambah supplier' : 'Ubah supplier', x.name.trim());
        _load();
      }
    }
    disposeLater(name);
    disposeLater(phone);
    disposeLater(addr);
    disposeLater(note);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Supplier')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Supplier')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            onChanged: (v) {
              _q = v;
              _load();
            },
            decoration: const InputDecoration(hintText: 'Cari supplier', prefixIcon: Icon(Icons.search_rounded), isDense: true),
          ),
        ),
        Expanded(
          child: _list.isEmpty
              ? const EmptyState(icon: Icons.groups_outlined, title: 'Belum ada supplier')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final s = _list[i];
                    return SoftCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      onTap: () => _edit(s),
                      child: Row(children: [
                        ProductAvatar(s.name, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text([s.phone, s.address, s.note].where((e) => e.isNotEmpty).join(' • '),
                                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ]),
                        ),
                        if (app.isOwner)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final ok = await confirmDialog(context, title: 'Hapus supplier?', message: s.name, danger: true, okText: 'Hapus');
                              if (!ok) return;
                              await Repo.deleteSupplier(s.id!);
                              await Activity.log('supplier', 'Hapus supplier', s.name);
                              _load();
                            },
                          ),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

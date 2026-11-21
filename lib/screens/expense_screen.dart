import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

/// Pengeluaran operasional toko (listrik, gaji, plastik, dll)
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = dayStart(DateTime.now());
  List<Expense> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.expenses(_from, _to);
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  Future<void> _edit([Expense? e]) async {
    final app = context.read<AppState>();
    if (e != null && !app.isOwner) {
      Notify.warning('Hanya owner yang bisa mengubah pengeluaran');
      return;
    }
    final cats = await Repo.expenseCategories();
    if (!mounted) return;
    final amount = TextEditingController(text: e == null ? '' : nf(e.amount));
    final note = TextEditingController(text: e?.note ?? '');
    final cat = TextEditingController(text: e?.category ?? '');
    var date = e?.date ?? DateTime.now();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e == null ? 'Catat Pengeluaran' : 'Ubah Pengeluaran', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              MoneyField(controller: amount, label: 'Nominal', autofocus: e == null, icon: Icons.payments_outlined),
              const SizedBox(height: 10),
              TextField(controller: cat, decoration: inputDeco('Kategori', icon: Icons.category_outlined)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final c in cats) ActionChip(label: Text(c), onPressed: () => setS(() => cat.text = c)),
              ]),
              const SizedBox(height: 10),
              TextField(controller: note, decoration: inputDeco('Keterangan', icon: Icons.notes_rounded)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  final d = await showDatePicker(context: ctx, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDate: date);
                  if (d != null) setS(() => date = DateTime(d.year, d.month, d.day, date.hour, date.minute));
                },
                icon: const Icon(Icons.event_rounded),
                label: Text(fmtDate(date)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.save_rounded),
                label: const Padding(padding: EdgeInsets.all(12), child: Text('SIMPAN')),
              ),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      final v = parseNum(amount.text);
      if (v <= 0 || cat.text.trim().isEmpty) {
        Notify.warning('Isi nominal dan kategori');
      } else {
        await Repo.saveExpense(id: e?.id, date: date, category: cat.text, amount: v, note: note.text, user: app.userName);
        await Activity.log('pengeluaran', e == null ? 'Catat pengeluaran' : 'Ubah pengeluaran', '${cat.text.trim()} • ${rp(v)} • ${note.text.trim()}');
        Notify.success('Pengeluaran disimpan');
        _load();
      }
    }
    disposeLater(amount);
    disposeLater(note);
    disposeLater(cat);
  }

  Future<void> _delete(Expense e) async {
    final ok = await confirmDialog(context, title: 'Hapus pengeluaran?', message: '${e.category} ${rp(e.amount)}', danger: true, okText: 'Hapus');
    if (!ok) return;
    await Repo.deleteExpense(e.id);
    await Activity.log('pengeluaran', 'Hapus pengeluaran', '${e.category} • ${rp(e.amount)} • ${e.note}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final total = _list.fold<int>(0, (a, e) => a + e.amount);
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Catat')),
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: StatCard(title: 'Total pengeluaran', value: rp(total), icon: Icons.payments_rounded, color: Colors.red, sub: '${_list.length} catatan'),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _list.isEmpty
                  ? const EmptyState(icon: Icons.payments_outlined, title: 'Belum ada pengeluaran')
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                      itemCount: _list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final e = _list[i];
                        return SoftCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          onTap: () => _edit(e),
                          child: Row(children: [
                            CircleAvatar(backgroundColor: Colors.red.withOpacity(0.1), child: const Icon(Icons.north_east_rounded, color: Colors.red)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(e.category, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text('${fmtDate(e.date)}${e.note.isEmpty ? '' : ' • ${e.note}'} • ${e.userName}',
                                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                              ]),
                            ),
                            Text(rp(e.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                            if (app.isOwner) IconButton(onPressed: () => _delete(e), icon: const Icon(Icons.delete_outline_rounded)),
                          ]),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

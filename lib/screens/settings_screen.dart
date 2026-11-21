import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../config.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/activation.dart';
import '../services/backup.dart';
import '../services/logo.dart';
import '../services/native.dart';
import '../services/printer.dart';
import '../services/stock_alert.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final owner = app.isOwner;
    void open(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    Widget tile(IconData icon, Color color, String title, String sub, Widget page) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => open(page),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(14)),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(sub, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          if (owner) tile(Icons.storefront_rounded, Colors.blue, 'Profil Toko & Struk', 'Nama, alamat, isi struk, metode bayar', const StoreSettings()),
          tile(Icons.palette_rounded, Colors.pink, 'Tampilan', 'Layout HP / Tablet, warna, mode gelap, ukuran teks', const DisplaySettings()),
          if (owner) tile(Icons.manage_accounts_rounded, Colors.purple, 'Pengguna & Hak Akses', 'Akun owner & kasir, izin kasir', const UsersSettings()),
          tile(Icons.password_rounded, Colors.indigo, 'Ganti Password', 'Password akun ${app.userName}', const ChangePassword()),
          tile(Icons.print_rounded, Colors.teal, 'Printer Thermal', app.get('pr_name').isEmpty ? 'Belum dipilih' : '${app.get('pr_name')} • ${app.get('pr_paper')}mm',
              const PrinterSettings()),
          if (owner) tile(Icons.notifications_active_rounded, Colors.orange, 'Stok & Notifikasi', 'Batas stok minimum, peringatan barang habis', const StockSettings()),
          if (owner)
            tile(Icons.cloud_sync_rounded, Colors.green, 'Backup & Pulihkan',
                app.get('backup_last_time').isEmpty ? 'Belum pernah backup' : 'Terakhir ${app.get('backup_last_time')}', const BackupSettings()),
          tile(Icons.info_rounded, Colors.blueGrey, 'Tentang Aplikasi', 'Versi & aktivasi', const AboutPage()),
        ]),
      ),
    );
  }
}

// =================================================================== PROFIL TOKO
class StoreSettings extends StatefulWidget {
  const StoreSettings({super.key});

  @override
  State<StoreSettings> createState() => _StoreSettingsState();
}

class _StoreSettingsState extends State<StoreSettings> {
  late final AppState app = context.read<AppState>();
  late final _name = TextEditingController(text: app.get('store_name'));
  late final _addr = TextEditingController(text: app.get('store_address'));
  late final _phone = TextEditingController(text: app.get('store_phone'));
  late final _header = TextEditingController(text: app.get('receipt_header'));
  late final _footer = TextEditingController(text: app.get('receipt_footer'));
  late final _prefix = TextEditingController(text: app.get('invoice_prefix'));
  late final _methods = TextEditingController(text: app.get('pay_methods'));

  @override
  void dispose() {
    for (final c in [_name, _addr, _phone, _header, _footer, _prefix, _methods]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      Notify.warning('Nama toko wajib diisi');
      return;
    }
    await app.setMany({
      'store_name': _name.text.trim(),
      'store_address': _addr.text.trim(),
      'store_phone': _phone.text.trim(),
      'receipt_header': _header.text.trim(),
      'receipt_footer': _footer.text.trim(),
      'invoice_prefix': _prefix.text.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), ''),
      'pay_methods': _methods.text,
    });
    await Activity.log('pengaturan', 'Ubah profil toko & struk', _name.text.trim());
    Notify.success('Disimpan');
    if (mounted) Navigator.pop(context);
  }

  bool _busyLogo = false;

  Future<void> _pickLogo() async {
    try {
      final path = await Native.pickFile();
      if (path == null) return;
      setState(() => _busyLogo = true);
      final bytes = await File(path).readAsBytes();
      final b64 = LogoService.fromPicked(bytes);
      await app.set('store_logo', b64);
      await Activity.log('pengaturan', 'Ganti logo / kop toko', 'Ukuran setelah diperkecil ${(b64.length * 3 / 4 / 1024).toStringAsFixed(0)} KB');
      Notify.success('Logo disimpan (otomatis diperkecil)');
    } on FormatException catch (e) {
      Notify.error(e.message);
    } catch (e) {
      Notify.error('Gagal membaca gambar: $e');
    } finally {
      if (mounted) setState(() => _busyLogo = false);
    }
  }

  Future<void> _removeLogo() async {
    final ok = await confirmDialog(context, title: 'Hapus logo?', message: 'Login & struk kembali memakai tampilan tanpa logo.', danger: true, okText: 'Hapus');
    if (!ok) return;
    await app.set('store_logo', '');
    await Activity.log('pengaturan', 'Hapus logo / kop toko');
  }

  Widget _logoCard(AppState a) {
    final cs = Theme.of(context).colorScheme;
    final logo = a.logo;
    return SoftCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Logo / Kop Toko', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 4),
        Text('Dipakai di halaman login dan di bagian atas struk. Foto dari galeri otomatis diperkecil.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Container(
          height: 150,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: _busyLogo
              ? const CircularProgressIndicator()
              : logo == null
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 44, color: cs.outline),
                      const SizedBox(height: 6),
                      Text('Belum ada logo', style: TextStyle(color: cs.outline)),
                    ])
                  : Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _busyLogo ? null : _pickLogo,
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(logo == null ? 'Upload Foto' : 'Ganti Foto'),
            ),
          ),
          if (logo != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _removeLogo,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Hapus'),
            ),
          ],
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tampilkan logo di halaman login'),
          value: a.b('logo_login'),
          onChanged: logo == null ? null : (v) => a.set('logo_login', v ? '1' : '0'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tampilkan alamat & telepon di login'),
          value: a.b('login_show_address'),
          onChanged: (v) => a.set('login_show_address', v ? '1' : '0'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cetak logo di struk'),
          subtitle: const Text('Dicetak hitam-putih di printer thermal'),
          value: a.b('rc_show_logo'),
          onChanged: logo == null ? null : (v) => a.set('rc_show_logo', v ? '1' : '0'),
        ),
        if (logo != null && a.b('rc_show_logo')) ...[
          Row(children: [
            const Text('Lebar logo di struk'),
            Expanded(
              child: Slider(
                min: 30,
                max: 100,
                divisions: 7,
                value: a.i('rc_logo_width', 60).clamp(30, 100).toDouble(),
                label: '${a.i('rc_logo_width', 60)}%',
                onChanged: (v) => a.set('rc_logo_width', '${v.round()}'),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cetak nama toko di bawah logo'),
            subtitle: const Text('Matikan bila nama toko sudah ada di gambar logo'),
            value: a.b('rc_show_name'),
            onChanged: (v) => a.set('rc_show_name', v ? '1' : '0'),
          ),
        ],
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: a.get('pr_address').isEmpty
              ? null
              : () => PrinterService.printItems(a, Receipts.header(a), okMsg: 'Kop dicetak'),
          icon: const Icon(Icons.print_rounded),
          label: Text(a.get('pr_address').isEmpty ? 'Tes cetak kop (pilih printer dulu)' : 'Tes cetak kop struk'),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Profil Toko & Struk')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _logoCard(a),
          const SizedBox(height: 14),
          TextField(controller: _name, decoration: inputDeco('Nama toko', icon: Icons.storefront_rounded)),
          const SizedBox(height: 10),
          TextField(controller: _addr, maxLines: 2, decoration: inputDeco('Alamat', icon: Icons.place_rounded)),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: inputDeco('No. telepon / WA', icon: Icons.phone_rounded)),
          const SectionTitle('STRUK'),
          TextField(controller: _header, maxLines: 2, decoration: inputDeco('Teks atas struk (opsional)', icon: Icons.vertical_align_top_rounded)),
          const SizedBox(height: 10),
          TextField(controller: _footer, maxLines: 3, decoration: inputDeco('Teks bawah struk', icon: Icons.vertical_align_bottom_rounded)),
          const SizedBox(height: 10),
          TextField(controller: _prefix, decoration: inputDeco('Awalan no. nota (mis. TK)', icon: Icons.tag_rounded)),
          SwitchListTile(
            title: const Text('Tampilkan nama kasir di struk'),
            value: a.b('rc_show_cashier'),
            onChanged: (v) => a.set('rc_show_cashier', v ? '1' : '0'),
          ),
          SwitchListTile(
            title: const Text('Cetak barcode no. nota di struk'),
            value: a.b('rc_show_barcode'),
            onChanged: (v) => a.set('rc_show_barcode', v ? '1' : '0'),
          ),
          const SectionTitle('METODE PEMBAYARAN'),
          TextField(
            controller: _methods,
            decoration: inputDeco('Pisahkan dengan koma', icon: Icons.payments_rounded, hint: 'Tunai,QRIS,Transfer,Debit'),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Padding(padding: EdgeInsets.all(12), child: Text('SIMPAN')),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== TAMPILAN
class DisplaySettings extends StatelessWidget {
  const DisplaySettings({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final shortest = MediaQuery.of(context).size.shortestSide;
    Widget seg<T>(T value, List<(T, String, IconData)> items, void Function(T) on) => SegmentedButton<T>(
          segments: [for (final i in items) ButtonSegment<T>(value: i.$1, label: Text(i.$2), icon: Icon(i.$3))],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (s) => on(s.first),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Tampilan')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          const SectionTitle('LAYOUT PERANGKAT'),
          seg<String>(app.get('ui_mode'), const [
            ('auto', 'Otomatis', Icons.auto_mode_rounded),
            ('phone', 'HP', Icons.smartphone_rounded),
            ('tablet', 'Tablet', Icons.tablet_android_rounded),
          ], (v) {
            app.set('ui_mode', v);
            Activity.log('pengaturan', 'Ubah layout', v);
          }),
          Padding(
            padding: const EdgeInsets.all(6),
            child: Text(
              'Otomatis: layar ≥ 600dp memakai layout tablet (layar ini ${shortest.round()}dp → ${shortest >= 600 ? 'Tablet' : 'HP'}).\n'
              'Tablet: menu samping + keranjang di sebelah kanan. HP: menu bawah + keranjang di bawah.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
          seg<String>(app.get('ui_orientation'), const [
            ('auto', 'Bebas', Icons.screen_rotation_rounded),
            ('portrait', 'Tegak', Icons.stay_current_portrait_rounded),
            ('landscape', 'Mendatar', Icons.stay_current_landscape_rounded),
          ], (v) => app.set('ui_orientation', v)),
          const SectionTitle('HALAMAN PENJUALAN'),
          seg<String>(app.get('ui_pos_view'), const [
            ('grid', 'Kotak', Icons.grid_view_rounded),
            ('list', 'Daftar', Icons.view_list_rounded),
          ], (v) => app.set('ui_pos_view', v)),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Jumlah kolom kotak')),
            DropdownButton<int>(
              value: app.i('ui_grid_cols', 0).clamp(0, 8).toInt(),
              items: [
                const DropdownMenuItem(value: 0, child: Text('Otomatis')),
                for (var i = 2; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i kolom')),
              ],
              onChanged: (v) => app.set('ui_grid_cols', '${v ?? 0}'),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Suara & getar saat tambah barang'),
            value: app.b('ui_sound'),
            onChanged: (v) => app.set('ui_sound', v ? '1' : '0'),
          ),
          const SectionTitle('WARNA TEMA'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (var i = 0; i < AppState.seeds.length; i++)
              Tooltip(
                message: AppState.seeds[i].name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => app.setMany({'ui_color': '$i', 'ui_custom_color': ''}),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppState.seeds[i].color,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: app.get('ui_custom_color').isEmpty && app.i('ui_color') == i ? cs.onSurface : Colors.transparent, width: 3),
                    ),
                    child: app.get('ui_custom_color').isEmpty && app.i('ui_color') == i ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(30),
              onTap: () => _customColor(context, app),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.cyan, Colors.blue, Colors.purple, Colors.red]),
                  border: Border.all(color: app.get('ui_custom_color').isNotEmpty ? cs.onSurface : Colors.transparent, width: 3),
                ),
                child: const Icon(Icons.colorize_rounded, color: Colors.white),
              ),
            ),
          ]),
          const SizedBox(height: 14),
          seg<String>(app.get('ui_dark'), const [
            ('0', 'Terang', Icons.light_mode_rounded),
            ('1', 'Gelap', Icons.dark_mode_rounded),
            ('2', 'Ikuti HP', Icons.brightness_auto_rounded),
          ], (v) => app.set('ui_dark', v)),
          const SectionTitle('UKURAN TEKS'),
          Row(children: [
            const Icon(Icons.text_decrease_rounded),
            Expanded(
              child: Slider(
                min: 0.8,
                max: 1.4,
                divisions: 6,
                value: app.textScale,
                label: '${(app.textScale * 100).round()}%',
                onChanged: (v) => app.set('ui_text_scale', v.toStringAsFixed(2)),
              ),
            ),
            const Icon(Icons.text_increase_rounded),
          ]),
          // contoh
          const SectionTitle('CONTOH'),
          SoftCard(
            child: Row(children: [
              const ProductAvatar('Indomie Goreng'),
              const SizedBox(width: 12),
              const Expanded(child: Text('Indomie Goreng 85g', style: TextStyle(fontWeight: FontWeight.w700))),
              Text(rp(3500), style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary)),
            ]),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: () {}, child: const Text('Tombol utama')),
        ]),
      ),
    );
  }

  Future<void> _customColor(BuildContext context, AppState app) async {
    final hsv = HSVColor.fromColor(app.seedColor);
    var h = hsv.hue, s = hsv.saturation.clamp(0.3, 1.0).toDouble(), v = hsv.value.clamp(0.3, 1.0).toDouble();
    final r = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final c = HSVColor.fromAHSV(1, h, s, v).toColor();
        return AlertDialog(
          title: const Text('Pilih warna sendiri'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 60, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 10),
            Row(children: [const SizedBox(width: 70, child: Text('Warna')), Expanded(child: Slider(min: 0, max: 360, value: h, onChanged: (x) => setS(() => h = x)))]),
            Row(children: [const SizedBox(width: 70, child: Text('Pekat')), Expanded(child: Slider(min: 0.3, max: 1, value: s, onChanged: (x) => setS(() => s = x)))]),
            Row(children: [const SizedBox(width: 70, child: Text('Terang')), Expanded(child: Slider(min: 0.3, max: 1, value: v, onChanged: (x) => setS(() => v = x)))]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, c), child: const Text('Pakai')),
          ],
        );
      }),
    );
    if (r != null) await app.set('ui_custom_color', '${r.value}');
  }
}

// =================================================================== PENGGUNA
class UsersSettings extends StatefulWidget {
  const UsersSettings({super.key});

  @override
  State<UsersSettings> createState() => _UsersSettingsState();
}

class _UsersSettingsState extends State<UsersSettings> {
  List<AppUser> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await Repo.users();
    if (mounted) setState(() => _users = u);
  }

  Future<void> _edit([AppUser? u]) async {
    final app = context.read<AppState>();
    final name = TextEditingController(text: u?.name ?? '');
    final user = TextEditingController(text: u?.username ?? '');
    final pass = TextEditingController();
    var role = u?.role ?? 'kasir';
    var active = u?.active ?? true;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(u == null ? 'Pengguna Baru' : 'Ubah Pengguna', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'kasir', label: Text('Kasir'), icon: Icon(Icons.person_rounded)),
                  ButtonSegment(value: 'owner', label: Text('Owner'), icon: Icon(Icons.workspace_premium_rounded)),
                ],
                selected: {role},
                onSelectionChanged: (s) => setS(() => role = s.first),
              ),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: inputDeco('Nama', icon: Icons.badge_outlined)),
              const SizedBox(height: 10),
              TextField(controller: user, autocorrect: false, decoration: inputDeco('Username', icon: Icons.person_outline_rounded)),
              const SizedBox(height: 10),
              TextField(
                controller: pass,
                obscureText: true,
                decoration: inputDeco(u == null ? 'Password' : 'Password baru (kosongkan bila tidak diganti)', icon: Icons.lock_outline_rounded),
              ),
              if (u != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Akun aktif'),
                  value: active,
                  onChanged: (v) => setS(() => active = v),
                ),
              const SizedBox(height: 14),
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
      if (name.text.trim().isEmpty || user.text.trim().isEmpty) {
        Notify.warning('Nama dan username wajib diisi');
      } else if (u == null && pass.text.length < 4) {
        Notify.warning('Password minimal 4 karakter');
      } else if (u != null && u.isOwner && (role != 'owner' || !active) && await Repo.ownerCount() <= 1) {
        Notify.error('Minimal harus ada 1 owner aktif');
      } else {
        final err = await Repo.saveUser(id: u?.id, name: name.text, username: user.text, pass: pass.text, role: role, active: active);
        if (err != null) {
          Notify.error(err);
        } else {
          await Activity.log('pengguna', u == null ? 'Tambah pengguna' : 'Ubah pengguna',
              '${name.text.trim()} (${user.text.trim()}) • ${role == 'owner' ? 'Owner' : 'Kasir'}${pass.text.isNotEmpty && u != null ? ' • password diganti' : ''}${!active ? ' • nonaktif' : ''}');
          if (u != null && u.id == app.user?.id) {
            final me = (await Repo.users()).firstWhere((e) => e.id == u.id, orElse: () => u);
            app.setUser(me);
          }
          Notify.success('Pengguna disimpan');
          _load();
        }
      }
    }
    disposeLater(name);
    disposeLater(user);
    disposeLater(pass);
  }

  Future<void> _delete(AppUser u) async {
    final app = context.read<AppState>();
    if (u.id == app.user?.id) {
      Notify.warning('Tidak bisa menghapus akun yang sedang dipakai');
      return;
    }
    if (u.isOwner && await Repo.ownerCount() <= 1) {
      Notify.error('Minimal harus ada 1 owner');
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(context, title: 'Hapus pengguna?', message: '${u.name} (${u.username})', danger: true, okText: 'Hapus');
    if (!ok) return;
    await Repo.deleteUser(u.id);
    await Activity.log('pengguna', 'Hapus pengguna', '${u.name} (${u.username})');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pengguna & Hak Akses')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.person_add_rounded), label: const Text('Pengguna')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 90), children: [
          const SectionTitle('DAFTAR PENGGUNA'),
          for (final u in _users)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SoftCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                onTap: () => _edit(u),
                child: Row(children: [
                  CircleAvatar(
                    backgroundColor: (u.isOwner ? Colors.amber : cs.primary).withOpacity(0.18),
                    child: Icon(u.isOwner ? Icons.workspace_premium_rounded : Icons.person_rounded, color: u.isOwner ? Colors.amber.shade800 : cs.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u.name, style: TextStyle(fontWeight: FontWeight.w800, decoration: u.active ? null : TextDecoration.lineThrough)),
                      Text('${u.username} • ${u.isOwner ? 'Owner' : 'Kasir'}${u.active ? '' : ' • nonaktif'}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                  IconButton(onPressed: () => _delete(u), icon: const Icon(Icons.delete_outline_rounded)),
                ]),
              ),
            ),
          const SectionTitle('HAK AKSES KASIR'),
          SoftCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final p in AppState.kasirPerms)
                SwitchListTile(
                  title: Text(p.label),
                  value: app.get(p.key).isEmpty ? p.def : app.b(p.key),
                  onChanged: (v) async {
                    await app.set(p.key, v ? '1' : '0');
                    await Activity.log('pengaturan', 'Ubah hak akses kasir', '${p.label}: ${v ? 'boleh' : 'tidak boleh'}');
                  },
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text('Owner selalu bisa semua fitur, termasuk Log Aktivitas, hapus/batalkan transaksi, backup dan pengaturan.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== GANTI PASSWORD
class ChangePassword extends StatefulWidget {
  const ChangePassword({super.key});

  @override
  State<ChangePassword> createState() => _ChangePasswordState();
}

class _ChangePasswordState extends State<ChangePassword> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    final u = app.user;
    if (u == null) return;
    if (await Repo.login(u.username, _old.text) == null) {
      Notify.error('Password lama salah');
      return;
    }
    if (_new.text.length < 4) {
      Notify.warning('Password baru minimal 4 karakter');
      return;
    }
    if (_new.text != _new2.text) {
      Notify.warning('Ulangi password tidak sama');
      return;
    }
    await Repo.saveUser(id: u.id, name: u.name, username: u.username, pass: _new.text, role: u.role, active: true);
    await Activity.log('pengguna', 'Ganti password sendiri', u.username);
    Notify.success('Password diganti');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ganti Password')),
      body: MaxWidth(
        width: 480,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _old, obscureText: true, decoration: inputDeco('Password lama', icon: Icons.lock_clock_outlined)),
          const SizedBox(height: 10),
          TextField(controller: _new, obscureText: true, decoration: inputDeco('Password baru', icon: Icons.lock_outline_rounded)),
          const SizedBox(height: 10),
          TextField(controller: _new2, obscureText: true, decoration: inputDeco('Ulangi password baru', icon: Icons.lock_reset_rounded)),
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Padding(padding: EdgeInsets.all(12), child: Text('SIMPAN'))),
        ]),
      ),
    );
  }
}

// =================================================================== PRINTER
class PrinterSettings extends StatefulWidget {
  const PrinterSettings({super.key});

  @override
  State<PrinterSettings> createState() => _PrinterSettingsState();
}

class _PrinterSettingsState extends State<PrinterSettings> {
  List<BtDevice> _devices = [];
  bool _scanning = false;

  Future<void> _scan() async {
    setState(() => _scanning = true);
    final d = await PrinterService.pairedDevices();
    if (!mounted) return;
    setState(() {
      _devices = d;
      _scanning = false;
    });
    if (d.isEmpty) Notify.info('Tidak ada perangkat. Pair printer dulu di Pengaturan Bluetooth HP.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final sample = Sale(
      id: 0,
      invoiceNo: '${app.get('invoice_prefix')}${DateTime.now().year % 100}0101-0001',
      createdAt: DateTime.now(),
      userName: app.userName,
      subtotal: 17500,
      total: 17500,
      paid: 20000,
      change: 2500,
      items: [
        SaleItem(productId: 0, name: 'Indomie Goreng 85g', qty: 3, price: 3500, subtotal: 10500),
        SaleItem(productId: 0, name: 'Aqua Botol 600ml', qty: 2, price: 3500, subtotal: 7000),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Printer Thermal')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SoftCard(
            child: Row(children: [
              Icon(Icons.print_rounded, color: cs.primary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.get('pr_name').isEmpty ? 'Belum ada printer' : app.get('pr_name'), style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(app.get('pr_address').isEmpty ? 'Pilih printer bluetooth di bawah' : app.get('pr_address')),
                ]),
              ),
              FilledButton.tonal(onPressed: app.get('pr_address').isEmpty ? null : () => PrinterService.testPrint(app), child: const Text('Tes Cetak')),
            ]),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _scanning ? null : _scan,
            icon: const Icon(Icons.bluetooth_searching_rounded),
            label: Text(_scanning ? 'Mencari...' : 'Cari printer (yang sudah di-pair)'),
          ),
          for (final d in _devices)
            ListTile(
              leading: const Icon(Icons.bluetooth_rounded),
              title: Text(d.name),
              subtitle: Text(d.address),
              trailing: app.get('pr_address') == d.address ? Icon(Icons.check_circle_rounded, color: cs.primary) : null,
              onTap: () async {
                await Native.btDisconnect();
                await app.setMany({'pr_address': d.address, 'pr_name': d.name});
                await Activity.log('pengaturan', 'Pilih printer', '${d.name} ${d.address}');
                Notify.success('Printer ${d.name} dipilih');
              },
            ),
          const SectionTitle('KERTAS'),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: '58', label: Text('58 mm')), ButtonSegment(value: '80', label: Text('80 mm'))],
            selected: {app.get('pr_paper')},
            onSelectionChanged: (s) => app.set('pr_paper', s.first),
          ),
          const SizedBox(height: 8),
          Row(children: [
            const Expanded(child: Text('Baris kosong di akhir')),
            DropdownButton<int>(
              value: app.i('pr_feed', 3).clamp(0, 8).toInt(),
              items: [for (var i = 0; i <= 8; i++) DropdownMenuItem(value: i, child: Text('$i'))],
              onChanged: (v) => app.set('pr_feed', '${v ?? 3}'),
            ),
          ]),
          Row(children: [
            const Expanded(child: Text('Jumlah cetak struk')),
            DropdownButton<int>(
              value: app.i('pr_copies', 1).clamp(1, 3).toInt(),
              items: [for (var i = 1; i <= 3; i++) DropdownMenuItem(value: i, child: Text('$i lembar'))],
              onChanged: (v) => app.set('pr_copies', '${v ?? 1}'),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Otomatis cetak struk setelah bayar'),
            value: app.b('pr_auto'),
            onChanged: (v) => app.set('pr_auto', v ? '1' : '0'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Potong kertas otomatis (printer dengan cutter)'),
            value: app.b('pr_cut'),
            onChanged: (v) => app.set('pr_cut', v ? '1' : '0'),
          ),
          const SectionTitle('PRATINJAU STRUK'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
            child: Text(
              PrinterService.preview(Receipts.sale(app, sample)),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: Colors.black, height: 1.25),
            ),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== STOK & NOTIFIKASI
class StockSettings extends StatefulWidget {
  const StockSettings({super.key});

  @override
  State<StockSettings> createState() => _StockSettingsState();
}

class _StockSettingsState extends State<StockSettings> {
  late final AppState app = context.read<AppState>();
  late final _min = TextEditingController(text: app.get('default_min_stock'));

  @override
  void dispose() {
    _min.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Stok & Notifikasi')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SwitchListTile(
            title: const Text('Notifikasi barang akan habis'),
            subtitle: const Text('Muncul di HP saat stok mencapai batas minimum'),
            value: a.b('notif_stock'),
            onChanged: (v) async {
              await a.set('notif_stock', v ? '1' : '0');
              if (v) await StockAlert.askPermission();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_rounded),
            title: const Text('Coba notifikasi'),
            onTap: () async {
              await StockAlert.askPermission();
              final ok = await NativeX.notify(998, 'Contoh: Stok menipis', 'Indomie Goreng: sisa 3 pcs');
              if (!ok) Notify.warning('Notifikasi diblokir. Izinkan notifikasi di Pengaturan HP.');
            },
          ),
          SwitchListTile(
            title: const Text('Boleh menjual walau stok di sistem habis'),
            subtitle: const Text('Jika dimatikan, barang dengan stok 0 tidak bisa dijual'),
            value: a.b('allow_minus_stock'),
            onChanged: (v) async {
              await a.set('allow_minus_stock', v ? '1' : '0');
              await Activity.log('pengaturan', 'Ubah izin stok minus', v ? 'boleh' : 'tidak boleh');
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _min,
            keyboardType: TextInputType.number,
            decoration: inputDeco('Stok minimum default untuk barang baru', icon: Icons.low_priority_rounded),
            onChanged: (v) => a.set('default_min_stock', '${parseQty(v)}'),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== BACKUP
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  bool _busy = false;
  List<File> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await BackupService.localBackups();
    if (mounted) setState(() => _files = f);
  }

  Future<void> _backup() async {
    final app = context.read<AppState>();
    setState(() => _busy = true);
    final r = await BackupService.run(app);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.ok) {
      await Activity.log('data', 'Backup manual', BackupService.fileNameFor(r.slot));
      Notify.success('Backup tersimpan: ${BackupService.fileNameFor(r.slot)}');
    } else {
      Notify.error('Backup gagal: ${r.error}');
    }
    _load();
  }

  Future<void> _restore(String path, String label) async {
    final ok = await confirmDialog(context,
        title: 'Pulihkan data?',
        message: 'Semua data sekarang akan DIGANTI dengan isi backup:\n$label\n\nLanjutkan?',
        danger: true,
        okText: 'Pulihkan');
    if (!ok || !mounted) return;
    final app = context.read<AppState>();
    final who = app.userName;
    setState(() => _busy = true);
    final err = await BackupService.restore(path);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      Notify.error(err);
      return;
    }
    await app.load();
    Activity.user = who;
    await Activity.log('data', 'Restore / pulihkan data', label);
    Notify.success('Data berhasil dipulihkan. Silakan login kembali.');
    app.setUser(null);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => FutureBuilder<int>(
            future: Repo.userCount(),
            builder: (_, s) => !s.hasData ? const Scaffold(body: Center(child: CircularProgressIndicator())) : (s.data! > 0 ? const LoginScreen() : const SetupOwnerScreen()),
          )),
      (_) => false,
    );
  }

  Future<void> _pickRestore() async {
    try {
      final path = await Native.pickFile();
      if (path == null) return;
      await _restore(path, 'File yang dipilih');
    } catch (e) {
      Notify.error('Gagal memilih file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Pulihkan')),
      body: MaxWidth(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.cloud_done_rounded, color: cs.primary, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Backup terakhir', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(app.get('backup_last_time').isEmpty ? 'Belum pernah' : app.get('backup_last_time')),
                    if (app.get('backup_last_file').isNotEmpty) Text(app.get('backup_last_file'), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _backup,
                icon: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.backup_rounded),
                label: const Text('Backup Sekarang'),
              ),
            ]),
          ),
          SwitchListTile(
            title: const Text('Backup otomatis'),
            subtitle: const Text('Setiap login & logout'),
            value: app.b('backup_auto'),
            onChanged: (v) => app.set('backup_auto', v ? '1' : '0'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'File backup hanya 2 dan bergantian ditimpa (tidak menumpuk):\n'
              '${BackupService.fileNameFor(1)} → ${BackupService.fileNameFor(2)} → kembali ke ${BackupService.fileNameFor(1)} …\n'
              'Lokasi: Download/${BackupService.folderName}/\n'
              'Salin file ini ke Google Drive / komputer secara berkala agar aman bila HP rusak.',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
            ),
          ),
          const SectionTitle('PULIHKAN DARI BACKUP'),
          for (final f in _files)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                leading: const Icon(Icons.storage_rounded),
                title: Text(f.path.split('/').last),
                subtitle: Text(fmtDateTime(f.lastModifiedSync())),
                trailing: TextButton(
                  onPressed: _busy ? null : () => _restore(f.path, '${f.path.split('/').last} (${fmtDateTime(f.lastModifiedSync())})'),
                  child: const Text('Pulihkan'),
                ),
              ),
            ),
          if (_files.isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('Belum ada backup di HP ini')),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _pickRestore,
            icon: const Icon(Icons.folder_open_rounded),
            label: const Padding(padding: EdgeInsets.all(10), child: Text('Pilih file backup (.db) — mis. pindah HP')),
          ),
        ]),
      ),
    );
  }
}

// =================================================================== TENTANG
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Tentang Aplikasi')),
      body: FutureBuilder<Map<String, String>>(
        future: Activation.info(),
        builder: (_, s) {
          final m = s.data ?? const <String, String>{};
          final aktif = (m['code'] ?? '').isNotEmpty;
          return MaxWidth(
            width: 520,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Center(child: ClipRRect(borderRadius: BorderRadius.circular(26), child: Image.asset('assets/logo.png', width: 110, height: 110))),
              const SizedBox(height: 12),
              const Center(child: Text(AppConfig.appName, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
              const Center(child: Text('Versi 1.0.0')),
              const SizedBox(height: 18),
              SoftCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Aktivasi', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Status: ${aktif ? 'Aktif' : '-'}'),
                  if (app.isOwner) Text('Kode: ${aktif ? m['code'] : '-'}'),
                  if ((m['customer'] ?? '').isNotEmpty) Text('Terdaftar atas: ${m['customer']}'),
                  Text('Tanggal aktivasi: ${(m['date'] ?? '').isEmpty ? '-' : m['date']}'),
                  if (app.isOwner && (m['url'] ?? '').isNotEmpty) Text('Server: ${m['url']}'),
                  Text('ID perangkat: ${m['device'] ?? '-'}'),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}

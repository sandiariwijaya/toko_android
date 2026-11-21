import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../services/backup.dart';
import '../services/stock_alert.dart';
import '../utils/notify.dart';
import 'home_shell.dart';

/// Dijalankan setelah login berhasil
Future<void> afterLogin(BuildContext context, AppState app) async {
  await Activity.log('akses', 'Login', app.isOwner ? 'Owner' : 'Kasir');
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
  // backup otomatis setiap login
  if (app.b('backup_auto')) {
    BackupService.run(app).then((r) {
      if (!r.ok) Notify.warning('Backup otomatis gagal: ${r.error}');
    });
  }
  Future.delayed(const Duration(milliseconds: 1200), () => StockAlert.onLogin(app));
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final logo = app.logo;
    final useLogo = logo != null && app.b('logo_login');
    return Column(children: [
      Container(
        decoration: BoxDecoration(
          color: useLogo ? Colors.white : null,
          borderRadius: BorderRadius.circular(useLogo ? 24 : 34),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
        ),
        padding: useLogo ? const EdgeInsets.all(12) : EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(useLogo ? 14 : 34),
          child: useLogo
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280, maxHeight: 150, minWidth: 90, minHeight: 90),
                  child: Image.memory(logo!, fit: BoxFit.contain, gaplessPlayback: true),
                )
              : Image.asset('assets/logo.png', width: 140, height: 140),
        ),
      ),
      const SizedBox(height: 16),
      Text(app.get('store_name'),
          textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
      if (app.get('store_address').isNotEmpty && app.b('login_show_address'))
        Text(app.get('store_address'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
      if (app.get('store_phone').isNotEmpty && app.b('login_show_address'))
        Text('Telp. ${app.get('store_phone')}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
    ]);
  }
}

class _Background extends StatelessWidget {
  final Widget child;
  const _Background({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.7)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      Notify.warning('Isi username dan password');
      return;
    }
    setState(() => _busy = true);
    final u = await Repo.login(_user.text, _pass.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (u == null) {
      Activity.user = _user.text.trim();
      await Activity.log('akses', 'Login gagal', 'Username: ${_user.text.trim()}');
      Activity.user = '';
      Notify.error('Username atau password salah');
      return;
    }
    final app = context.read<AppState>();
    app.setUser(u);
    Notify.success('Selamat datang, ${u.name}');
    await afterLogin(context, app);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Background(
      child: Column(children: [
        const _Brand(),
        const SizedBox(height: 26),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Masuk', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(
              controller: _user,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passFocus.requestFocus(),
              decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              focusNode: _passFocus,
              obscureText: _obscure,
              onSubmitted: (_) => _login(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : const Icon(Icons.login_rounded),
                label: const Text('MASUK', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Pertama kali: buat akun owner & nama toko
class SetupOwnerScreen extends StatefulWidget {
  const SetupOwnerScreen({super.key});

  @override
  State<SetupOwnerScreen> createState() => _SetupOwnerScreenState();
}

class _SetupOwnerScreenState extends State<SetupOwnerScreen> {
  final _store = TextEditingController();
  final _addr = TextEditingController();
  final _name = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_store, _addr, _name, _user, _pass, _pass2]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_store.text.trim().isEmpty || _name.text.trim().isEmpty || _user.text.trim().isEmpty) {
      Notify.warning('Lengkapi nama toko, nama owner dan username');
      return;
    }
    if (_pass.text.length < 4) {
      Notify.warning('Password minimal 4 karakter');
      return;
    }
    if (_pass.text != _pass2.text) {
      Notify.warning('Ulangi password tidak sama');
      return;
    }
    setState(() => _busy = true);
    final app = context.read<AppState>();
    await app.setMany({'store_name': _store.text.trim(), 'store_address': _addr.text.trim()});
    final err = await Repo.saveUser(name: _name.text, username: _user.text, pass: _pass.text, role: 'owner');
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      Notify.error(err);
      return;
    }
    final u = await Repo.login(_user.text, _pass.text);
    if (u == null || !mounted) return;
    app.setUser(u);
    await Activity.log('pengguna', 'Membuat akun owner pertama', u.username);
    if (!mounted) return;
    await afterLogin(context, app);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _Background(
      child: Column(children: [
        ClipRRect(borderRadius: BorderRadius.circular(26), child: Image.asset('assets/logo.png', width: 100, height: 100)),
        const SizedBox(height: 12),
        const Text('Pengaturan Awal', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const Text('Buat data toko dan akun owner', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(controller: _store, decoration: const InputDecoration(labelText: 'Nama toko', prefixIcon: Icon(Icons.storefront_rounded))),
            const SizedBox(height: 10),
            TextField(controller: _addr, decoration: const InputDecoration(labelText: 'Alamat toko (opsional)', prefixIcon: Icon(Icons.place_outlined))),
            const Divider(height: 28),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nama owner', prefixIcon: Icon(Icons.badge_outlined))),
            const SizedBox(height: 10),
            TextField(controller: _user, autocorrect: false, decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline_rounded))),
            const SizedBox(height: 10),
            TextField(controller: _pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline_rounded))),
            const SizedBox(height: 10),
            TextField(controller: _pass2, obscureText: true, onSubmitted: (_) => _save(), decoration: const InputDecoration(labelText: 'Ulangi password', prefixIcon: Icon(Icons.lock_reset_rounded))),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.check_rounded),
                label: const Text('SIMPAN & MULAI', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

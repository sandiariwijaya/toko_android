import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../services/backup.dart';
import '../widgets/common.dart';
import 'dashboard_screen.dart';
import 'expense_screen.dart';
import 'log_screen.dart';
import 'login_screen.dart';
import 'pos_screen.dart';
import 'products_screen.dart';
import 'purchase_screen.dart';
import 'report_screen.dart';
import 'retur_screen.dart';
import 'settings_screen.dart';
import 'stock_screen.dart';
import 'supplier_screen.dart';
import 'transactions_screen.dart';

class NavDest {
  final String id;
  final IconData icon;
  final IconData iconOn;
  final String label;
  final Widget Function() page;
  const NavDest(this.id, this.icon, this.iconOn, this.label, this.page);
}

/// Cara pindah halaman dari dalam halaman lain (mis. tombol cepat di beranda)
class HomeNav extends InheritedWidget {
  final void Function(String id) go;
  const HomeNav({super.key, required this.go, required super.child});

  static HomeNav? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<HomeNav>();

  @override
  bool updateShouldNotify(HomeNav oldWidget) => false;
}

Future<void> logout(BuildContext context) async {
  final ok = await confirmDialog(context, title: 'Keluar', message: 'Keluar dari akun ini?', okText: 'Keluar', icon: Icons.logout_rounded);
  if (!ok || !context.mounted) return;
  final app = context.read<AppState>();
  await Activity.log('akses', 'Logout');
  if (app.b('backup_auto')) await BackupService.run(app);
  app.setUser(null);
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _current = 'home';

  List<NavDest> _dests(AppState app) => [
        NavDest('home', Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Beranda', () => const DashboardScreen()),
        NavDest('pos', Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, 'Penjualan', () => const PosScreen()),
        if (app.can('perm_purchase'))
          NavDest('purchase', Icons.local_shipping_outlined, Icons.local_shipping_rounded, 'Pembelian', () => const PurchaseScreen()),
        NavDest('products', Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Barang', () => const ProductsScreen()),
        NavDest('stock', Icons.warehouse_outlined, Icons.warehouse_rounded, 'Stok', () => const StockScreen()),
        NavDest('trx', Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Transaksi', () => const TransactionsScreen()),
        if (app.can('perm_return'))
          NavDest('retur', Icons.assignment_return_outlined, Icons.assignment_return_rounded, 'Retur', () => const ReturScreen()),
        if (app.can('perm_report'))
          NavDest('report', Icons.insert_chart_outlined_rounded, Icons.insert_chart_rounded, 'Laporan', () => const ReportScreen()),
        if (app.can('perm_expense'))
          NavDest('expense', Icons.payments_outlined, Icons.payments_rounded, 'Pengeluaran', () => const ExpenseScreen()),
        if (app.can('perm_purchase'))
          NavDest('supplier', Icons.groups_outlined, Icons.groups_rounded, 'Supplier', () => const SupplierScreen()),
        if (app.isOwner) NavDest('log', Icons.history_outlined, Icons.history_rounded, 'Log Aktivitas', () => const LogScreen()),
        NavDest('settings', Icons.settings_outlined, Icons.settings_rounded, 'Pengaturan', () => const SettingsScreen()),
      ];

  void _go(String id) {
    final app = context.read<AppState>();
    final list = _dests(app);
    if (!list.any((e) => e.id == id)) return;
    if (app.isTablet(context) || _primaryIds(list).contains(id)) {
      setState(() => _current = id);
    } else {
      final d = list.firstWhere((e) => e.id == id);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => HomeNav(go: _go, child: d.page())));
    }
  }

  List<String> _primaryIds(List<NavDest> list) => ['home', 'pos', 'products', 'trx'];

  Widget _badge(Widget icon, int n) => n <= 0 ? icon : Badge(label: Text('$n'), child: icon);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = _dests(app);
    final tablet = app.isTablet(context);
    // 'more' = halaman Menu (khusus layout HP), bukan bagian dari daftar halaman
    final valid = list.any((e) => e.id == _current) || (_current == 'more' && !tablet);
    if (!valid) _current = 'home';
    final cs = Theme.of(context).colorScheme;

    if (tablet) {
      final idx = list.indexWhere((e) => e.id == _current);
      final wide = MediaQuery.of(context).size.width >= 1000;
      return HomeNav(
        go: _go,
        child: Scaffold(
          body: Row(children: [
            SafeArea(
              child: Container(
                color: Theme.of(context).brightness == Brightness.light ? Colors.white : cs.surfaceContainer,
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: IntrinsicHeight(
                        child: NavigationRail(
                          extended: wide,
                          minExtendedWidth: 210,
                          backgroundColor: Colors.transparent,
                          selectedIndex: idx < 0 ? 0 : idx,
                          labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                          onDestinationSelected: (i) => setState(() => _current = list[i].id),
                          leading: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Image.asset('assets/logo.png', width: 48, height: 48),
                            ),
                          ),
                          trailing: Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 12),
                            child: IconButton.filledTonal(
                              tooltip: 'Keluar (${app.userName})',
                              icon: const Icon(Icons.logout_rounded),
                              onPressed: () => logout(context),
                            ),
                          ),
                          destinations: [
                            for (final d in list)
                              NavigationRailDestination(
                                icon: d.id == 'stock' ? _badge(Icon(d.icon), app.lowStock) : Icon(d.icon),
                                selectedIcon: d.id == 'stock' ? _badge(Icon(d.iconOn), app.lowStock) : Icon(d.iconOn),
                                label: Text(d.label),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: KeyedSubtree(key: ValueKey('page_$_current'), child: list[idx < 0 ? 0 : idx].page())),
          ]),
        ),
      );
    }

    // ---------------- HP ----------------
    final primary = list.where((e) => _primaryIds(list).contains(e.id)).toList();
    final isMore = _current == 'more';
    final idx = isMore ? primary.length : primary.indexWhere((e) => e.id == _current);
    Widget body;
    if (isMore) {
      body = _MoreScreen(items: list.where((e) => !_primaryIds(list).contains(e.id)).toList(), onOpen: _go);
    } else {
      body = KeyedSubtree(key: ValueKey('page_$_current'), child: primary[idx < 0 ? 0 : idx].page());
    }
    return HomeNav(
      go: _go,
      child: Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: idx < 0 ? 0 : idx,
          onDestinationSelected: (i) => setState(() => _current = i >= primary.length ? 'more' : primary[i].id),
          destinations: [
            for (final d in primary) NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.iconOn), label: d.label),
            NavigationDestination(
              icon: _badge(const Icon(Icons.apps_outlined), app.lowStock),
              selectedIcon: _badge(const Icon(Icons.apps_rounded), app.lowStock),
              label: 'Menu',
            ),
          ],
        ),
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  final List<NavDest> items;
  final void Function(String id) onOpen;
  const _MoreScreen({required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final colors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.green,
      Colors.red,
      Colors.indigo,
      Colors.brown,
      Colors.pink,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Menu')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SoftCard(
            child: Row(children: [
              CircleAvatar(radius: 24, backgroundColor: cs.primaryContainer, child: Icon(app.isOwner ? Icons.workspace_premium_rounded : Icons.person_rounded, color: cs.primary)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.userName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(app.isOwner ? 'Owner' : 'Kasir', style: TextStyle(color: cs.onSurfaceVariant)),
                ]),
              ),
              FilledButton.tonalIcon(onPressed: () => logout(context), icon: const Icon(Icons.logout_rounded), label: const Text('Keluar')),
            ]),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (var i = 0; i < items.length; i++)
                SoftCard(
                  padding: const EdgeInsets.all(8),
                  onTap: () => onOpen(items[i].id),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colors[i % colors.length].withOpacity(0.14), borderRadius: BorderRadius.circular(16)),
                      child: items[i].id == 'stock' && app.lowStock > 0
                          ? Badge(label: Text('${app.lowStock}'), child: Icon(items[i].iconOn, color: colors[i % colors.length], size: 28))
                          : Icon(items[i].iconOn, color: colors[i % colors.length], size: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(items[i].label, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                  ]),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../utils/format.dart';

const String kDbName = 'aplikasi_toko.db';

String hashPass(String username, String pass) =>
    sha256.convert(utf8.encode('toko::${username.trim().toLowerCase()}::$pass')).toString();

class Db {
  static Database? _db;
  static Future<Database>? _opening;

  static Future<String> path() async => p.join(await getDatabasesPath(), kDbName);

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _opening ??= _open();
    _db = await _opening;
    _opening = null;
    return _db!;
  }

  static Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null) await d.close();
  }

  static Future<Database> _open() async {
    return openDatabase(
      await path(),
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = OFF');
      },
      onCreate: (db, v) async {
        await _create(db);
        await _createV2(db);
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) await _createV2(db);
      },
    );
  }

  /// Versi 2: tabel retur penjualan & pembelian
  static Future<void> _createV2(Database db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS returns(id INTEGER PRIMARY KEY AUTOINCREMENT, return_no TEXT, type TEXT, '
        'ref_id INTEGER, ref_no TEXT, created_at TEXT, user_name TEXT, party TEXT, total INTEGER, settle TEXT, note TEXT, '
        'status INTEGER DEFAULT 0, void_reason TEXT)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ret_date ON returns(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ret_ref ON returns(type, ref_id)');
    await db.execute('CREATE TABLE IF NOT EXISTS return_items(id INTEGER PRIMARY KEY AUTOINCREMENT, return_id INTEGER, product_id INTEGER, '
        'name TEXT, unit TEXT, qty REAL, price INTEGER, buy_price INTEGER, subtotal INTEGER, cond TEXT)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ri_ret ON return_items(return_id)');
  }

  static Future<void> _create(Database db) async {
    final b = db.batch();
    b.execute('CREATE TABLE settings(k TEXT PRIMARY KEY, v TEXT)');
    b.execute('CREATE TABLE users(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, username TEXT UNIQUE, pass TEXT, '
        'role TEXT, active INTEGER DEFAULT 1, created_at TEXT)');
    b.execute('CREATE TABLE categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT UNIQUE)');
    b.execute('CREATE TABLE products(id INTEGER PRIMARY KEY AUTOINCREMENT, barcode TEXT, name TEXT NOT NULL, '
        'category_id INTEGER, unit TEXT DEFAULT \'pcs\', buy_price INTEGER DEFAULT 0, sell_price INTEGER DEFAULT 0, '
        'stock REAL DEFAULT 0, min_stock REAL DEFAULT 0, active INTEGER DEFAULT 1, created_at TEXT, updated_at TEXT)');
    b.execute('CREATE INDEX idx_prod_barcode ON products(barcode)');
    b.execute('CREATE INDEX idx_prod_name ON products(name)');
    b.execute('CREATE TABLE suppliers(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, phone TEXT, address TEXT, note TEXT)');
    b.execute('CREATE TABLE sales(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT, created_at TEXT, user_name TEXT, '
        'customer TEXT, subtotal INTEGER, discount INTEGER, total INTEGER, paid INTEGER, change_amt INTEGER, method TEXT, '
        'note TEXT, status INTEGER DEFAULT 0, void_reason TEXT, hpp INTEGER DEFAULT 0)');
    b.execute('CREATE INDEX idx_sales_date ON sales(created_at)');
    b.execute('CREATE TABLE sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER, product_id INTEGER, name TEXT, '
        'barcode TEXT, unit TEXT, qty REAL, buy_price INTEGER, price INTEGER, discount INTEGER, subtotal INTEGER)');
    b.execute('CREATE INDEX idx_si_sale ON sale_items(sale_id)');
    b.execute('CREATE TABLE purchases(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT, ref_no TEXT, created_at TEXT, '
        'user_name TEXT, supplier_id INTEGER, supplier_name TEXT, total INTEGER, note TEXT, status INTEGER DEFAULT 0, void_reason TEXT)');
    b.execute('CREATE INDEX idx_pur_date ON purchases(created_at)');
    b.execute('CREATE TABLE purchase_items(id INTEGER PRIMARY KEY AUTOINCREMENT, purchase_id INTEGER, product_id INTEGER, '
        'name TEXT, unit TEXT, qty REAL, buy_price INTEGER, subtotal INTEGER)');
    b.execute('CREATE INDEX idx_pi_pur ON purchase_items(purchase_id)');
    b.execute('CREATE TABLE stock_moves(id INTEGER PRIMARY KEY AUTOINCREMENT, product_id INTEGER, product_name TEXT, '
        'created_at TEXT, type TEXT, qty REAL, stock_after REAL, ref TEXT, user_name TEXT, note TEXT)');
    b.execute('CREATE INDEX idx_sm_prod ON stock_moves(product_id)');
    b.execute('CREATE INDEX idx_sm_date ON stock_moves(created_at)');
    b.execute('CREATE TABLE expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT, category TEXT, amount INTEGER, '
        'note TEXT, user_name TEXT)');
    b.execute('CREATE TABLE logs(id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT, user_name TEXT, type TEXT, '
        'action TEXT, detail TEXT)');
    b.execute('CREATE INDEX idx_logs_date ON logs(created_at)');
    for (final c in ['Makanan', 'Minuman', 'Snack', 'Sembako', 'Kebutuhan Rumah', 'Perawatan Diri', 'Rokok', 'Lainnya']) {
      b.insert('categories', {'name': c});
    }
    b.insert('settings', {'k': 'app_signature', 'v': 'aplikasi_toko'});
    await b.commit(noResult: true);
  }

  /// Cek file database backup milik aplikasi ini
  static Future<bool> isValidAppDb(String file) async {
    Database? d;
    try {
      d = await openDatabase(file, readOnly: true, singleInstance: false);
      final r = await d.rawQuery("SELECT v FROM settings WHERE k='app_signature'");
      final t = await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('products','sales','users')");
      return r.isNotEmpty && r.first['v'] == 'aplikasi_toko' && t.length == 3;
    } catch (_) {
      return false;
    } finally {
      try {
        await d?.close();
      } catch (_) {}
    }
  }
}

/// Catatan aktivitas (log) — hanya bisa dilihat owner
class Activity {
  static String user = '';

  static Future<void> log(String type, String action, [String detail = '']) async {
    try {
      final db = await Db.instance;
      await db.insert('logs', {
        'created_at': dbDateTime(DateTime.now()),
        'user_name': user.isEmpty ? 'Sistem' : user,
        'type': type,
        'action': action,
        'detail': detail,
      });
    } catch (_) {}
  }
}

class Repo {
  // ============================ SETTINGS ============================
  static Future<Map<String, String>> loadSettings() async {
    final db = await Db.instance;
    final rows = await db.query('settings');
    return {for (final r in rows) r['k'].toString(): (r['v'] ?? '').toString()};
  }

  static Future<void> saveSettings(Map<String, String> kv) async {
    final db = await Db.instance;
    final b = db.batch();
    kv.forEach((k, v) => b.insert('settings', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace));
    await b.commit(noResult: true);
  }

  // ============================ USERS ============================
  static Future<List<AppUser>> users() async {
    final db = await Db.instance;
    final r = await db.query('users', orderBy: "role='owner' DESC, name");
    return r.map(AppUser.fromMap).toList();
  }

  static Future<int> userCount() async {
    final db = await Db.instance;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM users')) ?? 0;
  }

  static Future<AppUser?> login(String username, String pass) async {
    final db = await Db.instance;
    final r = await db.query('users', where: 'LOWER(username)=? AND active=1', whereArgs: [username.trim().toLowerCase()]);
    if (r.isEmpty) return null;
    final u = AppUser.fromMap(r.first);
    return u.pass == hashPass(username, pass) ? u : null;
  }

  static Future<String?> saveUser({int? id, required String name, required String username, String? pass, required String role, bool active = true}) async {
    final db = await Db.instance;
    final uname = username.trim().toLowerCase();
    final dup = await db.query('users', where: 'LOWER(username)=? AND id<>?', whereArgs: [uname, id ?? -1]);
    if (dup.isNotEmpty) return 'Username sudah dipakai';
    final m = <String, Object?>{'name': name.trim(), 'username': uname, 'role': role, 'active': active ? 1 : 0};
    if (pass != null && pass.isNotEmpty) m['pass'] = hashPass(uname, pass);
    if (id == null) {
      if (pass == null || pass.isEmpty) return 'Password wajib diisi';
      m['created_at'] = dbDateTime(DateTime.now());
      await db.insert('users', m);
    } else {
      await db.update('users', m, where: 'id=?', whereArgs: [id]);
    }
    return null;
  }

  static Future<void> deleteUser(int id) async {
    final db = await Db.instance;
    await db.delete('users', where: 'id=?', whereArgs: [id]);
  }

  static Future<int> ownerCount() async {
    final db = await Db.instance;
    return Sqflite.firstIntValue(await db.rawQuery("SELECT COUNT(*) FROM users WHERE role='owner' AND active=1")) ?? 0;
  }

  // ============================ KATEGORI ============================
  static Future<List<Category>> categories() async {
    final db = await Db.instance;
    final r = await db.rawQuery('SELECT c.id, c.name, (SELECT COUNT(*) FROM products p WHERE p.category_id=c.id AND p.active=1) n '
        'FROM categories c ORDER BY c.name');
    return r.map((m) => Category(m['id'] as int, (m['name'] ?? '').toString(), (m['n'] as int?) ?? 0)).toList();
  }

  static Future<int> categoryId(String name) async {
    final n = name.trim();
    if (n.isEmpty) return 0;
    final db = await Db.instance;
    final r = await db.query('categories', where: 'LOWER(name)=?', whereArgs: [n.toLowerCase()]);
    if (r.isNotEmpty) return r.first['id'] as int;
    return db.insert('categories', {'name': n});
  }

  static Future<void> renameCategory(int id, String name) async {
    final db = await Db.instance;
    await db.update('categories', {'name': name.trim()}, where: 'id=?', whereArgs: [id]);
  }

  static Future<void> deleteCategory(int id) async {
    final db = await Db.instance;
    await db.update('products', {'category_id': null}, where: 'category_id=?', whereArgs: [id]);
    await db.delete('categories', where: 'id=?', whereArgs: [id]);
  }

  // ============================ BARANG ============================
  static const String _prodSel = 'SELECT p.*, IFNULL(c.name, \'\') category FROM products p LEFT JOIN categories c ON c.id=p.category_id';

  static Future<List<Product>> products({String q = '', int? categoryId, bool onlyActive = true, bool onlyLow = false, String order = 'name'}) async {
    final db = await Db.instance;
    final where = <String>[];
    final args = <Object?>[];
    if (onlyActive) where.add('p.active=1');
    if (categoryId != null) {
      where.add('p.category_id=?');
      args.add(categoryId);
    }
    if (onlyLow) where.add('p.min_stock>0 AND p.stock<=p.min_stock');
    final t = q.trim().toLowerCase();
    if (t.isNotEmpty) {
      for (final w in t.split(RegExp(r'\s+'))) {
        where.add('(LOWER(p.name) LIKE ? OR p.barcode LIKE ?)');
        args.add('%$w%');
        args.add('%$w%');
      }
    }
    final ord = switch (order) {
      'stock' => 'p.stock ASC, p.name',
      'new' => 'p.id DESC',
      _ => 'p.name COLLATE NOCASE',
    };
    final sql = '$_prodSel${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY $ord';
    final r = await db.rawQuery(sql, args);
    return r.map(Product.fromMap).toList();
  }

  static Future<Product?> productById(int id) async {
    final db = await Db.instance;
    final r = await db.rawQuery('$_prodSel WHERE p.id=?', [id]);
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  static Future<Product?> productByBarcode(String code) async {
    final c = code.trim();
    if (c.isEmpty) return null;
    final db = await Db.instance;
    final r = await db.rawQuery('$_prodSel WHERE p.barcode=? ORDER BY p.active DESC LIMIT 1', [c]);
    return r.isEmpty ? null : Product.fromMap(r.first);
  }

  static Future<bool> barcodeUsed(String code, int? exceptId) async {
    final c = code.trim();
    if (c.isEmpty) return false;
    final db = await Db.instance;
    final r = await db.query('products', where: 'barcode=? AND id<>?', whereArgs: [c, exceptId ?? -1]);
    return r.isNotEmpty;
  }

  /// Barcode internal unik (EAN-13 diawali 20)
  static Future<String> newBarcode() async {
    final db = await Db.instance;
    final seq = (Sqflite.firstIntValue(await db.rawQuery('SELECT IFNULL(MAX(id),0) FROM products')) ?? 0) + 1;
    var n = seq;
    while (true) {
      final base = '20${n.toString().padLeft(10, '0')}';
      final code = base + _ean13Check(base).toString();
      if (!await barcodeUsed(code, null)) return code;
      n++;
    }
  }

  static int _ean13Check(String twelve) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final d = twelve.codeUnitAt(i) - 48;
      sum += i.isEven ? d : d * 3;
    }
    return (10 - sum % 10) % 10;
  }

  static Future<int> saveProduct(Product p, {String user = '', String note = ''}) async {
    final db = await Db.instance;
    final now = dbDateTime(DateTime.now());
    if (p.id == null) {
      final m = p.toMap()
        ..['created_at'] = now
        ..['updated_at'] = now;
      final id = await db.insert('products', m);
      p.id = id;
      if (p.stock != 0) {
        await _move(db, id, p.name, 'awal', p.stock, p.stock, '', user, note.isEmpty ? 'Stok awal' : note);
      }
      return id;
    } else {
      final old = await productById(p.id!);
      final m = p.toMap()..['updated_at'] = now;
      await db.update('products', m, where: 'id=?', whereArgs: [p.id]);
      if (old != null && old.stock != p.stock) {
        await _move(db, p.id!, p.name, 'koreksi', p.stock - old.stock, p.stock, '', user, note.isEmpty ? 'Ubah data barang' : note);
      }
      return p.id!;
    }
  }

  static Future<void> setActive(int id, bool active) async {
    final db = await Db.instance;
    await db.update('products', {'active': active ? 1 : 0, 'updated_at': dbDateTime(DateTime.now())}, where: 'id=?', whereArgs: [id]);
  }

  static Future<bool> productUsed(int id) async {
    final db = await Db.instance;
    final a = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sale_items WHERE product_id=?', [id])) ?? 0;
    final b = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM purchase_items WHERE product_id=?', [id])) ?? 0;
    return a + b > 0;
  }

  static Future<void> deleteProduct(int id) async {
    final db = await Db.instance;
    await db.delete('products', where: 'id=?', whereArgs: [id]);
    await db.delete('stock_moves', where: 'product_id=?', whereArgs: [id]);
  }

  /// Ubah harga jual saja
  static Future<void> setSellPrice(int id, int price) async {
    final db = await Db.instance;
    await db.update('products', {'sell_price': price, 'updated_at': dbDateTime(DateTime.now())}, where: 'id=?', whereArgs: [id]);
  }

  /// Set stok ke angka tertentu (opname / koreksi)
  static Future<double> setStock(int id, double newStock, {required String user, String type = 'opname', String note = ''}) async {
    final db = await Db.instance;
    return db.transaction((tx) async {
      final r = await tx.query('products', columns: ['name', 'stock'], where: 'id=?', whereArgs: [id]);
      if (r.isEmpty) return 0.0;
      final old = (r.first['stock'] as num?)?.toDouble() ?? 0;
      final name = (r.first['name'] ?? '').toString();
      await tx.update('products', {'stock': newStock, 'updated_at': dbDateTime(DateTime.now())}, where: 'id=?', whereArgs: [id]);
      await _move(tx, id, name, type, newStock - old, newStock, '', user, note);
      return newStock - old;
    });
  }

  static Future<void> _move(DatabaseExecutor ex, int productId, String name, String type, double qty, double after, String ref,
      String user, String note) async {
    await ex.insert('stock_moves', {
      'product_id': productId,
      'product_name': name,
      'created_at': dbDateTime(DateTime.now()),
      'type': type,
      'qty': qty,
      'stock_after': after,
      'ref': ref,
      'user_name': user,
      'note': note,
    });
  }

  static Future<List<StockMove>> stockMoves({int? productId, DateTime? from, DateTime? to, int limit = 500}) async {
    final db = await Db.instance;
    final where = <String>[];
    final args = <Object?>[];
    if (productId != null) {
      where.add('product_id=?');
      args.add(productId);
    }
    if (from != null && to != null) {
      where.add('created_at BETWEEN ? AND ?');
      args.addAll(['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59']);
    }
    final r = await db.query('stock_moves',
        where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'id DESC', limit: limit);
    return r.map(StockMove.fromMap).toList();
  }

  static Future<List<Product>> lowStock() => products(onlyLow: true, order: 'stock');

  static Future<int> lowStockCount() async {
    final db = await Db.instance;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM products WHERE active=1 AND min_stock>0 AND stock<=min_stock')) ??
        0;
  }

  static Future<Map<String, num>> stockSummary() async {
    final db = await Db.instance;
    final r = await db.rawQuery('SELECT COUNT(*) n, IFNULL(SUM(CASE WHEN stock>0 THEN stock*buy_price ELSE 0 END),0) nb, '
        'IFNULL(SUM(CASE WHEN stock>0 THEN stock*sell_price ELSE 0 END),0) ns, '
        'IFNULL(SUM(CASE WHEN stock<=0 THEN 1 ELSE 0 END),0) habis, '
        'IFNULL(SUM(CASE WHEN min_stock>0 AND stock<=min_stock THEN 1 ELSE 0 END),0) low FROM products WHERE active=1');
    final m = r.first;
    return {
      'count': (m['n'] as num?) ?? 0,
      'value_buy': (m['nb'] as num?) ?? 0,
      'value_sell': (m['ns'] as num?) ?? 0,
      'empty': (m['habis'] as num?) ?? 0,
      'low': (m['low'] as num?) ?? 0,
    };
  }

  // ============================ SUPPLIER ============================
  static Future<List<Supplier>> suppliers([String q = '']) async {
    final db = await Db.instance;
    final r = await db.query('suppliers',
        where: q.trim().isEmpty ? null : 'LOWER(name) LIKE ?',
        whereArgs: q.trim().isEmpty ? null : ['%${q.trim().toLowerCase()}%'],
        orderBy: 'name COLLATE NOCASE');
    return r.map(Supplier.fromMap).toList();
  }

  static Future<int> saveSupplier(Supplier s) async {
    final db = await Db.instance;
    if (s.id == null) {
      final id = await db.insert('suppliers', s.toMap());
      s.id = id;
      return id;
    }
    await db.update('suppliers', s.toMap(), where: 'id=?', whereArgs: [s.id]);
    return s.id!;
  }

  static Future<void> deleteSupplier(int id) async {
    final db = await Db.instance;
    await db.delete('suppliers', where: 'id=?', whereArgs: [id]);
  }

  // ============================ PENJUALAN ============================
  static Future<String> _nextNo(DatabaseExecutor ex, String table, String prefix) async {
    final now = DateTime.now();
    final day = '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final n = Sqflite.firstIntValue(
            await ex.rawQuery('SELECT COUNT(*) FROM $table WHERE created_at LIKE ?', ['${dbDay(now)}%'])) ??
        0;
    var seq = n + 1;
    while (true) {
      final no = '$prefix$day-${seq.toString().padLeft(4, '0')}';
      final e = await ex.query(table, columns: ['id'], where: 'invoice_no=?', whereArgs: [no]);
      if (e.isEmpty) return no;
      seq++;
    }
  }

  static Future<Sale> createSale({
    required List<CartLine> lines,
    required int discount,
    required int paid,
    required String method,
    required String user,
    String customer = '',
    String note = '',
    String prefix = 'TK',
  }) async {
    final db = await Db.instance;
    return db.transaction((tx) async {
      final no = await _nextNo(tx, 'sales', prefix);
      final now = DateTime.now();
      final subtotal = lines.fold<int>(0, (a, l) => a + l.subtotal);
      final total = (subtotal - discount) < 0 ? 0 : subtotal - discount;
      final hpp = lines.fold<int>(0, (a, l) => a + (l.product.buyPrice * l.qty).round());
      final change = paid - total < 0 ? 0 : paid - total;
      final id = await tx.insert('sales', {
        'invoice_no': no,
        'created_at': dbDateTime(now),
        'user_name': user,
        'customer': customer.trim(),
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'paid': paid,
        'change_amt': change,
        'method': method,
        'note': note.trim(),
        'status': 0,
        'void_reason': '',
        'hpp': hpp,
      });
      final items = <SaleItem>[];
      for (final l in lines) {
        final pr = l.product;
        final it = SaleItem(
          productId: pr.id ?? 0,
          name: pr.name,
          barcode: pr.barcode,
          unit: pr.unit,
          qty: l.qty,
          buyPrice: pr.buyPrice,
          price: l.price,
          discount: l.discount,
          subtotal: l.subtotal,
        );
        items.add(it);
        await tx.insert('sale_items', {
          'sale_id': id,
          'product_id': it.productId,
          'name': it.name,
          'barcode': it.barcode,
          'unit': it.unit,
          'qty': it.qty,
          'buy_price': it.buyPrice,
          'price': it.price,
          'discount': it.discount,
          'subtotal': it.subtotal,
        });
        if (pr.id != null) {
          await tx.rawUpdate('UPDATE products SET stock=stock-? WHERE id=?', [l.qty, pr.id]);
          final s = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [pr.id]);
          final after = s.isEmpty ? 0.0 : ((s.first['stock'] as num?)?.toDouble() ?? 0);
          pr.stock = after;
          await _move(tx, pr.id!, pr.name, 'jual', -l.qty, after, no, user, '');
        }
      }
      return Sale(
        id: id,
        invoiceNo: no,
        createdAt: now,
        userName: user,
        customer: customer.trim(),
        subtotal: subtotal,
        discount: discount,
        total: total,
        paid: paid,
        change: change,
        method: method,
        note: note.trim(),
        hpp: hpp,
        items: items,
      );
    });
  }

  static Future<List<Sale>> sales(DateTime from, DateTime to, {bool withItems = false, String q = ''}) async {
    final db = await Db.instance;
    final args = <Object?>['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59'];
    var where = 'created_at BETWEEN ? AND ?';
    if (q.trim().isNotEmpty) {
      where += ' AND (invoice_no LIKE ? OR customer LIKE ? OR user_name LIKE ?)';
      final t = '%${q.trim()}%';
      args.addAll([t, t, t]);
    }
    final r = await db.query('sales', where: where, whereArgs: args, orderBy: 'id DESC');
    final list = r.map(Sale.fromMap).toList();
    if (withItems && list.isNotEmpty) {
      final ids = list.map((e) => e.id).join(',');
      final it = await db.rawQuery('SELECT * FROM sale_items WHERE sale_id IN ($ids) ORDER BY id');
      final map = <int, List<SaleItem>>{};
      for (final m in it) {
        map.putIfAbsent(m['sale_id'] as int, () => []).add(SaleItem.fromMap(m));
      }
      for (final s in list) {
        s.items = map[s.id] ?? [];
      }
    }
    return list;
  }

  static Future<Sale?> saleById(int id) async {
    final db = await Db.instance;
    final r = await db.query('sales', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) return null;
    final s = Sale.fromMap(r.first);
    final it = await db.query('sale_items', where: 'sale_id=?', whereArgs: [id], orderBy: 'id');
    s.items = it.map(SaleItem.fromMap).toList();
    return s;
  }

  /// Batalkan penjualan: stok dikembalikan
  static Future<void> voidSale(Sale s, String reason, String user) async {
    final db = await Db.instance;
    await db.transaction((tx) async {
      final cur = await tx.query('sales', columns: ['status'], where: 'id=?', whereArgs: [s.id]);
      if (cur.isEmpty || (cur.first['status'] as int? ?? 0) == 1) return;
      await tx.update('sales', {'status': 1, 'void_reason': reason}, where: 'id=?', whereArgs: [s.id]);
      for (final it in s.items) {
        if (it.productId <= 0) continue;
        await tx.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [it.qty, it.productId]);
        final r = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [it.productId]);
        if (r.isEmpty) continue;
        await _move(tx, it.productId, it.name, 'batal-jual', it.qty, (r.first['stock'] as num?)?.toDouble() ?? 0, s.invoiceNo, user, reason);
      }
    });
  }

  // ============================ PEMBELIAN ============================
  static Future<Purchase> createPurchase({
    required List<CartLine> lines,
    required String user,
    Supplier? supplier,
    String refNo = '',
    String note = '',
    bool updateBuyPrice = true,
  }) async {
    final db = await Db.instance;
    return db.transaction((tx) async {
      final no = await _nextNo(tx, 'purchases', 'PB');
      final now = DateTime.now();
      final total = lines.fold<int>(0, (a, l) => a + l.subtotal);
      final id = await tx.insert('purchases', {
        'invoice_no': no,
        'ref_no': refNo.trim(),
        'created_at': dbDateTime(now),
        'user_name': user,
        'supplier_id': supplier?.id,
        'supplier_name': supplier?.name ?? '',
        'total': total,
        'note': note.trim(),
        'status': 0,
        'void_reason': '',
      });
      final items = <PurchaseItem>[];
      for (final l in lines) {
        final pr = l.product;
        final it = PurchaseItem(productId: pr.id ?? 0, name: pr.name, unit: pr.unit, qty: l.qty, buyPrice: l.price, subtotal: l.subtotal);
        items.add(it);
        await tx.insert('purchase_items', {
          'purchase_id': id,
          'product_id': it.productId,
          'name': it.name,
          'unit': it.unit,
          'qty': it.qty,
          'buy_price': it.buyPrice,
          'subtotal': it.subtotal,
        });
        if (pr.id != null) {
          final upd = <String>['stock=stock+?'];
          final args = <Object?>[l.qty];
          if (updateBuyPrice && l.price > 0) {
            upd.add('buy_price=?');
            args.add(l.price);
          }
          if (l.newSellPrice != null && l.newSellPrice! > 0) {
            upd.add('sell_price=?');
            args.add(l.newSellPrice);
          }
          upd.add('updated_at=?');
          args.add(dbDateTime(now));
          args.add(pr.id);
          await tx.rawUpdate('UPDATE products SET ${upd.join(', ')} WHERE id=?', args);
          final s = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [pr.id]);
          final after = s.isEmpty ? 0.0 : ((s.first['stock'] as num?)?.toDouble() ?? 0);
          await _move(tx, pr.id!, pr.name, 'beli', l.qty, after, no, user, supplier?.name ?? '');
        }
      }
      return Purchase(
        id: id,
        invoiceNo: no,
        refNo: refNo,
        createdAt: now,
        userName: user,
        supplierId: supplier?.id,
        supplierName: supplier?.name ?? '',
        total: total,
        note: note,
        items: items,
      );
    });
  }

  static Future<List<Purchase>> purchases(DateTime from, DateTime to, {bool withItems = false, String q = ''}) async {
    final db = await Db.instance;
    final args = <Object?>['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59'];
    var where = 'created_at BETWEEN ? AND ?';
    if (q.trim().isNotEmpty) {
      where += ' AND (invoice_no LIKE ? OR supplier_name LIKE ? OR ref_no LIKE ?)';
      final t = '%${q.trim()}%';
      args.addAll([t, t, t]);
    }
    final r = await db.query('purchases', where: where, whereArgs: args, orderBy: 'id DESC');
    final list = r.map(Purchase.fromMap).toList();
    if (withItems && list.isNotEmpty) {
      final ids = list.map((e) => e.id).join(',');
      final it = await db.rawQuery('SELECT * FROM purchase_items WHERE purchase_id IN ($ids) ORDER BY id');
      final map = <int, List<PurchaseItem>>{};
      for (final m in it) {
        map.putIfAbsent(m['purchase_id'] as int, () => []).add(PurchaseItem.fromMap(m));
      }
      for (final s in list) {
        s.items = map[s.id] ?? [];
      }
    }
    return list;
  }

  static Future<Purchase?> purchaseById(int id) async {
    final db = await Db.instance;
    final r = await db.query('purchases', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) return null;
    final s = Purchase.fromMap(r.first);
    final it = await db.query('purchase_items', where: 'purchase_id=?', whereArgs: [id], orderBy: 'id');
    s.items = it.map(PurchaseItem.fromMap).toList();
    return s;
  }

  static Future<void> voidPurchase(Purchase pb, String reason, String user) async {
    final db = await Db.instance;
    await db.transaction((tx) async {
      final cur = await tx.query('purchases', columns: ['status'], where: 'id=?', whereArgs: [pb.id]);
      if (cur.isEmpty || (cur.first['status'] as int? ?? 0) == 1) return;
      await tx.update('purchases', {'status': 1, 'void_reason': reason}, where: 'id=?', whereArgs: [pb.id]);
      for (final it in pb.items) {
        if (it.productId <= 0) continue;
        await tx.rawUpdate('UPDATE products SET stock=stock-? WHERE id=?', [it.qty, it.productId]);
        final r = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [it.productId]);
        if (r.isEmpty) continue;
        await _move(tx, it.productId, it.name, 'batal-beli', -it.qty, (r.first['stock'] as num?)?.toDouble() ?? 0, pb.invoiceNo, user, reason);
      }
    });
  }

  // ============================ PENGELUARAN ============================
  static Future<List<Expense>> expenses(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final r = await db.query('expenses',
        where: 'created_at BETWEEN ? AND ?', whereArgs: ['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59'], orderBy: 'created_at DESC, id DESC');
    return r.map(Expense.fromMap).toList();
  }

  static Future<void> saveExpense({int? id, required DateTime date, required String category, required int amount, String note = '', required String user}) async {
    final db = await Db.instance;
    final m = {'created_at': dbDateTime(date), 'category': category.trim(), 'amount': amount, 'note': note.trim(), 'user_name': user};
    if (id == null) {
      await db.insert('expenses', m);
    } else {
      await db.update('expenses', m, where: 'id=?', whereArgs: [id]);
    }
  }

  static Future<void> deleteExpense(int id) async {
    final db = await Db.instance;
    await db.delete('expenses', where: 'id=?', whereArgs: [id]);
  }

  static Future<List<String>> expenseCategories() async {
    final db = await Db.instance;
    final r = await db.rawQuery('SELECT DISTINCT category FROM expenses ORDER BY category');
    final list = r.map((e) => (e['category'] ?? '').toString()).where((e) => e.isNotEmpty).toList();
    for (final d in ['Listrik', 'Air', 'Gaji Karyawan', 'Sewa Tempat', 'Transport', 'Plastik & Kemasan', 'Lain-lain']) {
      if (!list.contains(d)) list.add(d);
    }
    return list;
  }

  // ============================ LAPORAN ============================
  static Future<ReportData> report(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final a = '${dbDay(from)} 00:00:00';
    final b = '${dbDay(to)} 23:59:59';
    final d = ReportData(from, to);

    final s = await db.rawQuery(
        'SELECT COUNT(*) n, IFNULL(SUM(subtotal),0) g, IFNULL(SUM(discount),0) dc, IFNULL(SUM(total),0) t, IFNULL(SUM(hpp),0) h '
        'FROM sales WHERE status=0 AND created_at BETWEEN ? AND ?',
        [a, b]);
    d.trxCount = (s.first['n'] as num?)?.toInt() ?? 0;
    d.gross = (s.first['g'] as num?)?.toInt() ?? 0;
    d.discount = (s.first['dc'] as num?)?.toInt() ?? 0;
    d.total = (s.first['t'] as num?)?.toInt() ?? 0;
    d.hpp = (s.first['h'] as num?)?.toInt() ?? 0;
    d.voidCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sales WHERE status=1 AND created_at BETWEEN ? AND ?', [a, b])) ?? 0;

    final m = await db.rawQuery('SELECT method, COUNT(*) n, SUM(total) t FROM sales WHERE status=0 AND created_at BETWEEN ? AND ? '
        'GROUP BY method ORDER BY t DESC', [a, b]);
    d.byMethod = m.map((e) => NameTotal((e['method'] ?? '-').toString(), (e['n'] as num?)?.toInt() ?? 0, (e['t'] as num?)?.toInt() ?? 0)).toList();

    final c = await db.rawQuery('SELECT user_name, COUNT(*) n, SUM(total) t FROM sales WHERE status=0 AND created_at BETWEEN ? AND ? '
        'GROUP BY user_name ORDER BY t DESC', [a, b]);
    d.byCashier = c.map((e) => NameTotal((e['user_name'] ?? '-').toString(), (e['n'] as num?)?.toInt() ?? 0, (e['t'] as num?)?.toInt() ?? 0)).toList();

    final t = await db.rawQuery('SELECT i.name, COUNT(DISTINCT i.sale_id) n, SUM(i.qty) q, SUM(i.subtotal) t FROM sale_items i '
        'JOIN sales s ON s.id=i.sale_id WHERE s.status=0 AND s.created_at BETWEEN ? AND ? GROUP BY i.name ORDER BY q DESC', [a, b]);
    d.topItems = t
        .map((e) => NameTotal((e['name'] ?? '').toString(), (e['n'] as num?)?.toInt() ?? 0, (e['t'] as num?)?.toInt() ?? 0,
            (e['q'] as num?)?.toDouble() ?? 0))
        .toList();
    d.itemsSold = d.topItems.fold<double>(0, (x, e) => x + e.qty);

    final ex = await db.rawQuery('SELECT category, COUNT(*) n, SUM(amount) t FROM expenses WHERE created_at BETWEEN ? AND ? '
        'GROUP BY category ORDER BY t DESC', [a, b]);
    d.expenseByCat = ex.map((e) => NameTotal((e['category'] ?? '-').toString(), (e['n'] as num?)?.toInt() ?? 0, (e['t'] as num?)?.toInt() ?? 0)).toList();
    d.expense = d.expenseByCat.fold<int>(0, (x, e) => x + e.total);

    final pb = await db.rawQuery('SELECT COUNT(*) n, IFNULL(SUM(total),0) t FROM purchases WHERE status=0 AND created_at BETWEEN ? AND ?', [a, b]);
    d.purchaseCount = (pb.first['n'] as num?)?.toInt() ?? 0;
    d.purchase = (pb.first['t'] as num?)?.toInt() ?? 0;

    final rj = await db.rawQuery(
        "SELECT COUNT(*) n, IFNULL(SUM(total),0) t FROM returns WHERE type='jual' AND status=0 AND created_at BETWEEN ? AND ?", [a, b]);
    d.returnCount = (rj.first['n'] as num?)?.toInt() ?? 0;
    d.returnSales = (rj.first['t'] as num?)?.toInt() ?? 0;
    final rh = await db.rawQuery(
        "SELECT IFNULL(SUM(ri.buy_price*ri.qty),0) h FROM return_items ri JOIN returns r ON r.id=ri.return_id "
        "WHERE r.type='jual' AND r.status=0 AND ri.cond='bagus' AND r.created_at BETWEEN ? AND ?", [a, b]);
    d.returnHpp = (rh.first['h'] as num?)?.round() ?? 0;
    final rb = await db.rawQuery(
        "SELECT IFNULL(SUM(total),0) t FROM returns WHERE type='beli' AND status=0 AND created_at BETWEEN ? AND ?", [a, b]);
    d.returnPurchase = (rb.first['t'] as num?)?.toInt() ?? 0;

    final dl = await db.rawQuery('SELECT substr(created_at,1,10) d, COUNT(*) n, SUM(total) t FROM sales WHERE status=0 AND created_at BETWEEN ? AND ? '
        'GROUP BY substr(created_at,1,10) ORDER BY d', [a, b]);
    final map = {for (final e in dl) e['d'].toString(): e};
    final days = <DayTotal>[];
    var day = dayStart(from);
    final end = dayStart(to);
    var guard = 0;
    while (!day.isAfter(end) && guard < 400) {
      final e = map[dbDay(day)];
      days.add(DayTotal(day, (e?['t'] as num?)?.toInt() ?? 0, (e?['n'] as num?)?.toInt() ?? 0));
      day = DateTime(day.year, day.month, day.day + 1);
      guard++;
    }
    d.daily = days;
    return d;
  }

  /// Laba per barang: (nama, qty, omzet, laba)
  static Future<List<(String, double, int, int)>> itemProfit(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final r = await db.rawQuery(
        'SELECT i.name, SUM(i.qty) q, SUM(i.subtotal) t, SUM(i.subtotal - CAST(ROUND(i.buy_price * i.qty) AS INTEGER)) l FROM sale_items i '
        'JOIN sales s ON s.id=i.sale_id WHERE s.status=0 AND s.created_at BETWEEN ? AND ? GROUP BY i.name ORDER BY l DESC',
        ['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59']);
    return r
        .map((e) => ((e['name'] ?? '').toString(), (e['q'] as num?)?.toDouble() ?? 0, (e['t'] as num?)?.toInt() ?? 0,
            (e['l'] as num?)?.toInt() ?? 0))
        .toList();
  }

  // ============================ RETUR ============================
  /// Jumlah yang sudah diretur per barang untuk satu nota (product_id -> qty)
  static Future<Map<int, double>> returnedQty(String type, int refId) async {
    final db = await Db.instance;
    final r = await db.rawQuery(
        'SELECT ri.product_id, SUM(ri.qty) q FROM return_items ri JOIN returns r ON r.id=ri.return_id '
        'WHERE r.type=? AND r.ref_id=? AND r.status=0 GROUP BY ri.product_id',
        [type, refId]);
    return {for (final e in r) (e['product_id'] as int? ?? 0): (e['q'] as num?)?.toDouble() ?? 0};
  }

  static Future<ReturnDoc> createReturn({
    required String type, // jual | beli
    int? refId,
    String refNo = '',
    String party = '',
    required List<ReturnLine> lines,
    required String settle,
    String note = '',
    required String user,
  }) async {
    final db = await Db.instance;
    return db.transaction((tx) async {
      final now = DateTime.now();
      final prefix = type == 'jual' ? 'RJ' : 'RB';
      final day = '${now.year % 100}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final n = Sqflite.firstIntValue(
              await tx.rawQuery('SELECT COUNT(*) FROM returns WHERE type=? AND created_at LIKE ?', [type, '${dbDay(now)}%'])) ??
          0;
      var seq = n + 1;
      var no = '$prefix$day-${seq.toString().padLeft(3, '0')}';
      while ((await tx.query('returns', columns: ['id'], where: 'return_no=?', whereArgs: [no])).isNotEmpty) {
        seq++;
        no = '$prefix$day-${seq.toString().padLeft(3, '0')}';
      }
      final used = lines.where((l) => l.qty > 0).toList();
      final total = used.fold<int>(0, (a, l) => a + l.subtotal);
      final id = await tx.insert('returns', {
        'return_no': no,
        'type': type,
        'ref_id': refId,
        'ref_no': refNo,
        'created_at': dbDateTime(now),
        'user_name': user,
        'party': party.trim(),
        'total': total,
        'settle': settle,
        'note': note.trim(),
        'status': 0,
        'void_reason': '',
      });
      final items = <ReturnItem>[];
      for (final l in used) {
        final it = ReturnItem(
          productId: l.productId,
          name: l.name,
          unit: l.unit,
          qty: l.qty,
          price: l.price,
          buyPrice: l.buyPrice,
          subtotal: l.subtotal,
          cond: type == 'jual' ? l.cond : 'bagus',
        );
        items.add(it);
        await tx.insert('return_items', {
          'return_id': id,
          'product_id': it.productId,
          'name': it.name,
          'unit': it.unit,
          'qty': it.qty,
          'price': it.price,
          'buy_price': it.buyPrice,
          'subtotal': it.subtotal,
          'cond': it.cond,
        });
        if (it.productId <= 0) continue;
        // retur jual kondisi bagus: stok bertambah. retur beli: stok berkurang. rusak: stok tetap.
        double change = 0;
        if (type == 'jual' && it.cond == 'bagus') change = it.qty;
        if (type == 'beli') change = -it.qty;
        if (change == 0) continue;
        await tx.rawUpdate('UPDATE products SET stock=stock+?, updated_at=? WHERE id=?', [change, dbDateTime(now), it.productId]);
        final r = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [it.productId]);
        if (r.isEmpty) continue;
        await _move(tx, it.productId, it.name, type == 'jual' ? 'retur-jual' : 'retur-beli', change,
            (r.first['stock'] as num?)?.toDouble() ?? 0, no, user, refNo);
      }
      return ReturnDoc(
        id: id,
        no: no,
        type: type,
        refId: refId,
        refNo: refNo,
        createdAt: now,
        userName: user,
        party: party.trim(),
        total: total,
        settle: settle,
        note: note.trim(),
        items: items,
      );
    });
  }

  static Future<List<ReturnDoc>> returns(DateTime from, DateTime to, {String type = '', bool withItems = true}) async {
    final db = await Db.instance;
    final args = <Object?>['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59'];
    var where = 'created_at BETWEEN ? AND ?';
    if (type.isNotEmpty) {
      where += ' AND type=?';
      args.add(type);
    }
    final r = await db.query('returns', where: where, whereArgs: args, orderBy: 'id DESC');
    final list = r.map(ReturnDoc.fromMap).toList();
    if (withItems && list.isNotEmpty) {
      final ids = list.map((e) => e.id).join(',');
      final it = await db.rawQuery('SELECT * FROM return_items WHERE return_id IN ($ids) ORDER BY id');
      final map = <int, List<ReturnItem>>{};
      for (final m in it) {
        map.putIfAbsent(m['return_id'] as int, () => []).add(ReturnItem.fromMap(m));
      }
      for (final x in list) {
        x.items = map[x.id] ?? [];
      }
    }
    return list;
  }

  static Future<List<ReturnDoc>> returnsForRef(String type, int refId) async {
    final db = await Db.instance;
    final r = await db.query('returns', where: 'type=? AND ref_id=?', whereArgs: [type, refId], orderBy: 'id');
    return r.map(ReturnDoc.fromMap).toList();
  }

  static Future<ReturnDoc?> returnById(int id) async {
    final db = await Db.instance;
    final r = await db.query('returns', where: 'id=?', whereArgs: [id]);
    if (r.isEmpty) return null;
    final x = ReturnDoc.fromMap(r.first);
    final it = await db.query('return_items', where: 'return_id=?', whereArgs: [id], orderBy: 'id');
    x.items = it.map(ReturnItem.fromMap).toList();
    return x;
  }

  /// Batalkan retur: perubahan stok dikembalikan seperti semula
  static Future<void> voidReturn(ReturnDoc x, String reason, String user) async {
    final db = await Db.instance;
    await db.transaction((tx) async {
      final cur = await tx.query('returns', columns: ['status'], where: 'id=?', whereArgs: [x.id]);
      if (cur.isEmpty || (cur.first['status'] as int? ?? 0) == 1) return;
      await tx.update('returns', {'status': 1, 'void_reason': reason}, where: 'id=?', whereArgs: [x.id]);
      for (final it in x.items) {
        if (it.productId <= 0) continue;
        double change = 0;
        if (x.isSale && it.cond == 'bagus') change = -it.qty;
        if (!x.isSale) change = it.qty;
        if (change == 0) continue;
        await tx.rawUpdate('UPDATE products SET stock=stock+? WHERE id=?', [change, it.productId]);
        final r = await tx.query('products', columns: ['stock'], where: 'id=?', whereArgs: [it.productId]);
        if (r.isEmpty) continue;
        await _move(tx, it.productId, it.name, 'batal-retur', change, (r.first['stock'] as num?)?.toDouble() ?? 0, x.no, user, reason);
      }
    });
  }

  // ============================ LOG ============================
  static Future<List<LogEntry>> logs({DateTime? from, DateTime? to, String type = '', String q = '', int limit = 1000}) async {
    final db = await Db.instance;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null && to != null) {
      where.add('created_at BETWEEN ? AND ?');
      args.addAll(['${dbDay(from)} 00:00:00', '${dbDay(to)} 23:59:59']);
    }
    if (type.isNotEmpty) {
      where.add('type=?');
      args.add(type);
    }
    if (q.trim().isNotEmpty) {
      where.add('(action LIKE ? OR detail LIKE ? OR user_name LIKE ?)');
      final t = '%${q.trim()}%';
      args.addAll([t, t, t]);
    }
    final r = await db.query('logs', where: where.isEmpty ? null : where.join(' AND '), whereArgs: args, orderBy: 'id DESC', limit: limit);
    return r.map(LogEntry.fromMap).toList();
  }

  static Future<int> clearLogs(DateTime before) async {
    final db = await Db.instance;
    return db.delete('logs', where: 'created_at < ?', whereArgs: ['${dbDay(before)} 00:00:00']);
  }
}

import 'utils/format.dart';

int _i(Object? v) => v == null ? 0 : (v is int ? v : (v is num ? v.round() : int.tryParse(v.toString()) ?? 0));
double _d(Object? v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
String _s(Object? v) => v?.toString() ?? '';

class AppUser {
  final int id;
  final String name;
  final String username;
  final String role; // owner | kasir
  final bool active;
  final String pass;
  AppUser({required this.id, required this.name, required this.username, required this.role, this.active = true, this.pass = ''});

  bool get isOwner => role == 'owner';

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: _i(m['id']),
        name: _s(m['name']),
        username: _s(m['username']),
        role: _s(m['role']),
        active: _i(m['active']) == 1,
        pass: _s(m['pass']),
      );
}

class Category {
  final int id;
  final String name;
  final int count;
  Category(this.id, this.name, [this.count = 0]);
}

class Product {
  int? id;
  String barcode;
  String name;
  int? categoryId;
  String category;
  String unit;
  int buyPrice;
  int sellPrice;
  double stock;
  double minStock;
  bool active;

  Product({
    this.id,
    this.barcode = '',
    required this.name,
    this.categoryId,
    this.category = '',
    this.unit = 'pcs',
    this.buyPrice = 0,
    this.sellPrice = 0,
    this.stock = 0,
    this.minStock = 0,
    this.active = true,
  });

  bool get isLow => minStock > 0 && stock <= minStock;
  bool get isEmpty => stock <= 0;
  int get margin => sellPrice - buyPrice;
  double get marginPct => buyPrice <= 0 ? 0 : (sellPrice - buyPrice) * 100 / buyPrice;

  factory Product.fromMap(Map<String, Object?> m) => Product(
        id: _i(m['id']),
        barcode: _s(m['barcode']),
        name: _s(m['name']),
        categoryId: m['category_id'] == null ? null : _i(m['category_id']),
        category: _s(m['category']),
        unit: _s(m['unit']).isEmpty ? 'pcs' : _s(m['unit']),
        buyPrice: _i(m['buy_price']),
        sellPrice: _i(m['sell_price']),
        stock: _d(m['stock']),
        minStock: _d(m['min_stock']),
        active: _i(m['active']) == 1,
      );

  Map<String, Object?> toMap() => {
        'barcode': barcode.trim(),
        'name': name.trim(),
        'category_id': categoryId,
        'unit': unit.trim().isEmpty ? 'pcs' : unit.trim(),
        'buy_price': buyPrice,
        'sell_price': sellPrice,
        'stock': stock,
        'min_stock': minStock,
        'active': active ? 1 : 0,
      };

  Product copy() => Product(
        id: id,
        barcode: barcode,
        name: name,
        categoryId: categoryId,
        category: category,
        unit: unit,
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        stock: stock,
        minStock: minStock,
        active: active,
      );
}

class Supplier {
  int? id;
  String name;
  String phone;
  String address;
  String note;
  Supplier({this.id, required this.name, this.phone = '', this.address = '', this.note = ''});

  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
        id: _i(m['id']),
        name: _s(m['name']),
        phone: _s(m['phone']),
        address: _s(m['address']),
        note: _s(m['note']),
      );

  Map<String, Object?> toMap() => {'name': name.trim(), 'phone': phone.trim(), 'address': address.trim(), 'note': note.trim()};
}

/// Baris keranjang (penjualan / pembelian)
class CartLine {
  final Product product;
  double qty;
  int price; // harga jual (penjualan) atau harga beli (pembelian)
  int discount; // diskon total baris (Rp)
  int? newSellPrice; // khusus pembelian: ubah harga jual
  CartLine(this.product, {this.qty = 1, required this.price, this.discount = 0, this.newSellPrice});

  int get gross => (price * qty).round();
  int get subtotal => gross - discount;
}

class SaleItem {
  final int productId;
  final String name;
  final String barcode;
  final String unit;
  final double qty;
  final int buyPrice;
  final int price;
  final int discount;
  final int subtotal;
  SaleItem({
    required this.productId,
    required this.name,
    this.barcode = '',
    this.unit = '',
    required this.qty,
    this.buyPrice = 0,
    required this.price,
    this.discount = 0,
    required this.subtotal,
  });

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        productId: _i(m['product_id']),
        name: _s(m['name']),
        barcode: _s(m['barcode']),
        unit: _s(m['unit']),
        qty: _d(m['qty']),
        buyPrice: _i(m['buy_price']),
        price: _i(m['price']),
        discount: _i(m['discount']),
        subtotal: _i(m['subtotal']),
      );
}

class Sale {
  final int id;
  final String invoiceNo;
  final DateTime createdAt;
  final String userName;
  final String customer;
  final int subtotal;
  final int discount;
  final int total;
  final int paid;
  final int change;
  final String method;
  final String note;
  final int status; // 0 normal, 1 dibatalkan
  final String voidReason;
  final int hpp;
  List<SaleItem> items;

  Sale({
    required this.id,
    required this.invoiceNo,
    required this.createdAt,
    this.userName = '',
    this.customer = '',
    required this.subtotal,
    this.discount = 0,
    required this.total,
    required this.paid,
    this.change = 0,
    this.method = 'Tunai',
    this.note = '',
    this.status = 0,
    this.voidReason = '',
    this.hpp = 0,
    List<SaleItem>? items,
  }) : items = items ?? [];

  bool get isVoid => status == 1;
  bool get isCash => method.toLowerCase() == 'tunai';
  int get profit => total - hpp;

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
        id: _i(m['id']),
        invoiceNo: _s(m['invoice_no']),
        createdAt: parseDb(_s(m['created_at'])),
        userName: _s(m['user_name']),
        customer: _s(m['customer']),
        subtotal: _i(m['subtotal']),
        discount: _i(m['discount']),
        total: _i(m['total']),
        paid: _i(m['paid']),
        change: _i(m['change_amt']),
        method: _s(m['method']),
        note: _s(m['note']),
        status: _i(m['status']),
        voidReason: _s(m['void_reason']),
        hpp: _i(m['hpp']),
      );
}

class PurchaseItem {
  final int productId;
  final String name;
  final String unit;
  final double qty;
  final int buyPrice;
  final int subtotal;
  PurchaseItem({required this.productId, required this.name, this.unit = '', required this.qty, required this.buyPrice, required this.subtotal});

  factory PurchaseItem.fromMap(Map<String, Object?> m) => PurchaseItem(
        productId: _i(m['product_id']),
        name: _s(m['name']),
        unit: _s(m['unit']),
        qty: _d(m['qty']),
        buyPrice: _i(m['buy_price']),
        subtotal: _i(m['subtotal']),
      );
}

class Purchase {
  final int id;
  final String invoiceNo;
  final String refNo;
  final DateTime createdAt;
  final String userName;
  final int? supplierId;
  final String supplierName;
  final int total;
  final String note;
  final int status;
  final String voidReason;
  List<PurchaseItem> items;

  Purchase({
    required this.id,
    required this.invoiceNo,
    this.refNo = '',
    required this.createdAt,
    this.userName = '',
    this.supplierId,
    this.supplierName = '',
    required this.total,
    this.note = '',
    this.status = 0,
    this.voidReason = '',
    List<PurchaseItem>? items,
  }) : items = items ?? [];

  bool get isVoid => status == 1;

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
        id: _i(m['id']),
        invoiceNo: _s(m['invoice_no']),
        refNo: _s(m['ref_no']),
        createdAt: parseDb(_s(m['created_at'])),
        userName: _s(m['user_name']),
        supplierId: m['supplier_id'] == null ? null : _i(m['supplier_id']),
        supplierName: _s(m['supplier_name']),
        total: _i(m['total']),
        note: _s(m['note']),
        status: _i(m['status']),
        voidReason: _s(m['void_reason']),
      );
}

class Expense {
  final int id;
  final DateTime date;
  final String category;
  final int amount;
  final String note;
  final String userName;
  Expense({required this.id, required this.date, required this.category, required this.amount, this.note = '', this.userName = ''});

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: _i(m['id']),
        date: parseDb(_s(m['created_at'])),
        category: _s(m['category']),
        amount: _i(m['amount']),
        note: _s(m['note']),
        userName: _s(m['user_name']),
      );
}

class StockMove {
  final int id;
  final int productId;
  final String productName;
  final DateTime date;
  final String type; // jual | beli | opname | koreksi | batal-jual | batal-beli | awal | import
  final double qty;
  final double stockAfter;
  final String ref;
  final String userName;
  final String note;
  StockMove({
    required this.id,
    required this.productId,
    required this.productName,
    required this.date,
    required this.type,
    required this.qty,
    required this.stockAfter,
    this.ref = '',
    this.userName = '',
    this.note = '',
  });

  factory StockMove.fromMap(Map<String, Object?> m) => StockMove(
        id: _i(m['id']),
        productId: _i(m['product_id']),
        productName: _s(m['product_name']),
        date: parseDb(_s(m['created_at'])),
        type: _s(m['type']),
        qty: _d(m['qty']),
        stockAfter: _d(m['stock_after']),
        ref: _s(m['ref']),
        userName: _s(m['user_name']),
        note: _s(m['note']),
      );
}

class LogEntry {
  final int id;
  final DateTime date;
  final String userName;
  final String type;
  final String action;
  final String detail;
  LogEntry({required this.id, required this.date, required this.userName, required this.type, required this.action, this.detail = ''});

  factory LogEntry.fromMap(Map<String, Object?> m) => LogEntry(
        id: _i(m['id']),
        date: parseDb(_s(m['created_at'])),
        userName: _s(m['user_name']),
        type: _s(m['type']),
        action: _s(m['action']),
        detail: _s(m['detail']),
      );
}

class NameTotal {
  final String name;
  final int count;
  final int total;
  final double qty;
  NameTotal(this.name, this.count, this.total, [this.qty = 0]);
}

class DayTotal {
  final DateTime day;
  final int total;
  final int count;
  DayTotal(this.day, this.total, this.count);
}

class ReportData {
  final DateTime from;
  final DateTime to;
  int trxCount = 0;
  int gross = 0; // subtotal sebelum diskon nota
  int discount = 0;
  int total = 0; // penjualan bersih
  int hpp = 0;
  int expense = 0;
  int purchase = 0;
  int purchaseCount = 0;
  int voidCount = 0;
  double itemsSold = 0;
  List<NameTotal> byMethod = [];
  List<NameTotal> byCashier = [];
  List<NameTotal> topItems = [];
  List<NameTotal> expenseByCat = [];
  List<DayTotal> daily = [];

  ReportData(this.from, this.to);

  int get grossProfit => total - hpp;
  int get net => grossProfit - expense;
  int get average => trxCount == 0 ? 0 : (total / trxCount).round();
  double get margin => total == 0 ? 0 : grossProfit * 100 / total;
}

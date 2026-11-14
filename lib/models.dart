import 'dart:typed_data';

int toInt(Object? v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String toStr(Object? v) => v?.toString() ?? '';

Uint8List? toBytes(Object? v) {
  if (v == null) return null;
  if (v is Uint8List) return v.isEmpty ? null : v;
  if (v is List<int>) return v.isEmpty ? null : Uint8List.fromList(v);
  return null;
}

class AppUser {
  final int id;
  final String username;
  final String name;
  final String role; // owner | kasir
  final bool active;

  AppUser({
    required this.id,
    required this.username,
    required this.name,
    required this.role,
    required this.active,
  });

  bool get isOwner => role == 'owner';

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        id: toInt(m['id']),
        username: toStr(m['username']),
        name: toStr(m['name']),
        role: toStr(m['role']),
        active: toInt(m['active']) == 1,
      );
}

class Category {
  final int id;
  final String name;
  final int sort;

  Category({required this.id, required this.name, required this.sort});

  factory Category.fromMap(Map<String, Object?> m) =>
      Category(id: toInt(m['id']), name: toStr(m['name']), sort: toInt(m['sort']));
}

class MenuItem {
  int? id;
  String name;
  int? categoryId;
  String categoryName;
  int price;
  Uint8List? image;
  bool available;
  int sort;

  MenuItem({
    this.id,
    required this.name,
    this.categoryId,
    this.categoryName = '',
    required this.price,
    this.image,
    this.available = true,
    this.sort = 0,
  });

  factory MenuItem.fromMap(Map<String, Object?> m) => MenuItem(
        id: toInt(m['id']),
        name: toStr(m['name']),
        categoryId: m['category_id'] == null ? null : toInt(m['category_id']),
        categoryName: toStr(m['category_name']),
        price: toInt(m['price']),
        image: toBytes(m['image']),
        available: toInt(m['available']) == 1,
        sort: toInt(m['sort']),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'category_id': categoryId,
        'price': price,
        'image': image,
        'available': available ? 1 : 0,
        'sort': sort,
      };
}

class PayMethod {
  int? id;
  String name;
  bool isCash;
  bool active;
  int sort;

  PayMethod({this.id, required this.name, this.isCash = false, this.active = true, this.sort = 0});

  bool get isQris => name.toUpperCase().contains('QRIS');

  factory PayMethod.fromMap(Map<String, Object?> m) => PayMethod(
        id: toInt(m['id']),
        name: toStr(m['name']),
        isCash: toInt(m['is_cash']) == 1,
        active: toInt(m['active']) == 1,
        sort: toInt(m['sort']),
      );
}

class CartItem {
  final int menuId;
  final String name;
  final int price;
  int qty;
  String note;

  CartItem({required this.menuId, required this.name, required this.price, this.qty = 1, this.note = ''});

  int get subtotal => price * qty;

  Map<String, Object?> toJson() =>
      {'menuId': menuId, 'name': name, 'price': price, 'qty': qty, 'note': note};

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
        menuId: toInt(j['menuId']),
        name: toStr(j['name']),
        price: toInt(j['price']),
        qty: toInt(j['qty']) < 1 ? 1 : toInt(j['qty']),
        note: toStr(j['note']),
      );
}

class SaleItem {
  final int? menuId;
  final String name;
  final int price;
  final int qty;
  final String note;
  final int subtotal;

  SaleItem({this.menuId, required this.name, required this.price, required this.qty, this.note = '', required this.subtotal});

  factory SaleItem.fromMap(Map<String, Object?> m) => SaleItem(
        menuId: m['menu_id'] == null ? null : toInt(m['menu_id']),
        name: toStr(m['name']),
        price: toInt(m['price']),
        qty: toInt(m['qty']),
        note: toStr(m['note']),
        subtotal: toInt(m['subtotal']),
      );
}

class Sale {
  int id;
  String invoiceNo;
  DateTime createdAt;
  String userName;
  String customer;
  String orderType;
  int subtotal;
  int discount;
  int service;
  int tax;
  int total;
  String paymentMethod;
  bool isCash;
  int paid;
  int change;
  String reference;
  String status;
  String voidReason;
  List<SaleItem> items;

  Sale({
    this.id = 0,
    this.invoiceNo = '',
    required this.createdAt,
    this.userName = '',
    this.customer = '',
    this.orderType = '',
    this.subtotal = 0,
    this.discount = 0,
    this.service = 0,
    this.tax = 0,
    this.total = 0,
    this.paymentMethod = '',
    this.isCash = true,
    this.paid = 0,
    this.change = 0,
    this.reference = '',
    this.status = 'paid',
    this.voidReason = '',
    List<SaleItem>? items,
  }) : items = items ?? [];

  bool get isVoid => status == 'void';

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
        id: toInt(m['id']),
        invoiceNo: toStr(m['invoice_no']),
        createdAt: DateTime.tryParse(toStr(m['created_at'])) ?? DateTime.now(),
        userName: toStr(m['user_name']),
        customer: toStr(m['customer']),
        orderType: toStr(m['order_type']),
        subtotal: toInt(m['subtotal']),
        discount: toInt(m['discount']),
        service: toInt(m['service']),
        tax: toInt(m['tax']),
        total: toInt(m['total']),
        paymentMethod: toStr(m['payment_method']),
        isCash: toInt(m['is_cash']) == 1,
        paid: toInt(m['paid']),
        change: toInt(m['change_amount']),
        reference: toStr(m['reference']),
        status: toStr(m['status']).isEmpty ? 'paid' : toStr(m['status']),
        voidReason: toStr(m['void_reason']),
      );
}

class Expense {
  int? id;
  DateTime date;
  String category;
  String description;
  int amount;
  String method;
  String userName;

  Expense({
    this.id,
    required this.date,
    required this.category,
    required this.description,
    required this.amount,
    this.method = 'Tunai',
    this.userName = '',
  });

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
        id: toInt(m['id']),
        date: DateTime.tryParse(toStr(m['date'])) ?? DateTime.now(),
        category: toStr(m['category']),
        description: toStr(m['description']),
        amount: toInt(m['amount']),
        method: toStr(m['method']),
        userName: toStr(m['user_name']),
      );
}

class HeldOrder {
  final int id;
  final String label;
  final DateTime createdAt;
  final String data;

  HeldOrder({required this.id, required this.label, required this.createdAt, required this.data});

  factory HeldOrder.fromMap(Map<String, Object?> m) => HeldOrder(
        id: toInt(m['id']),
        label: toStr(m['label']),
        createdAt: DateTime.tryParse(toStr(m['created_at'])) ?? DateTime.now(),
        data: toStr(m['data']),
      );
}

class NameValue {
  final String name;
  final int count;
  final int qty;
  final int total;
  NameValue(this.name, {this.count = 0, this.qty = 0, this.total = 0});
}

class ReportData {
  final DateTime from;
  final DateTime to;
  int trxCount = 0;
  int voidCount = 0;
  int gross = 0; // subtotal
  int discount = 0;
  int tax = 0;
  int service = 0;
  int total = 0;
  int expense = 0;
  List<NameValue> byMethod = [];
  List<NameValue> byCashier = [];
  List<NameValue> topItems = [];
  List<NameValue> daily = [];
  List<NameValue> expenseByCat = [];

  ReportData(this.from, this.to);

  int get average => trxCount == 0 ? 0 : (total / trxCount).round();
  int get net => total - expense;
}

class ActivityLog {
  final int id;
  final DateTime createdAt;
  final String userName;
  final String category;
  final String action;
  final String detail;

  ActivityLog({
    required this.id,
    required this.createdAt,
    required this.userName,
    required this.category,
    required this.action,
    required this.detail,
  });

  factory ActivityLog.fromMap(Map<String, Object?> m) => ActivityLog(
        id: toInt(m['id']),
        createdAt: DateTime.tryParse(toStr(m['created_at'])) ?? DateTime.now(),
        userName: toStr(m['user_name']),
        category: toStr(m['category']),
        action: toStr(m['action']),
        detail: toStr(m['detail']),
      );
}

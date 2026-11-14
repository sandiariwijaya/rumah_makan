import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'models.dart';

class Totals {
  final int subtotal;
  final int discount;
  final int service;
  final int tax;
  final int total;
  const Totals(this.subtotal, this.discount, this.service, this.tax, this.total);
}

class CartState extends ChangeNotifier {
  final List<CartItem> items = [];
  String customer = '';
  String orderType = '';
  int discountValue = 0;
  bool discountPercent = false;
  int? heldId;
  String heldLabel = '';

  bool get isEmpty => items.isEmpty;
  int get count => items.fold(0, (a, b) => a + b.qty);
  int get subtotal => items.fold(0, (a, b) => a + b.subtotal);

  int qtyOf(int menuId) => items.where((e) => e.menuId == menuId).fold(0, (a, b) => a + b.qty);

  int get discountAmount {
    final sub = subtotal;
    int d = discountPercent ? (sub * discountValue / 100).round() : discountValue;
    if (d > sub) d = sub;
    if (d < 0) d = 0;
    return d;
  }

  Totals totals(double taxPct, double servicePct) {
    final sub = subtotal;
    final disc = discountAmount;
    final base = sub - disc;
    final service = servicePct > 0 ? (base * servicePct / 100).round() : 0;
    final tax = taxPct > 0 ? ((base + service) * taxPct / 100).round() : 0;
    return Totals(sub, disc, service, tax, base + service + tax);
  }

  void add(MenuItem m) {
    if (m.id == null) return;
    final idx = items.indexWhere((e) => e.menuId == m.id && e.note.isEmpty);
    if (idx >= 0) {
      items[idx].qty++;
    } else {
      items.add(CartItem(menuId: m.id!, name: m.name, price: m.price));
    }
    notifyListeners();
  }

  void inc(CartItem it) {
    it.qty++;
    notifyListeners();
  }

  void dec(CartItem it) {
    if (it.qty <= 1) {
      items.remove(it);
    } else {
      it.qty--;
    }
    notifyListeners();
  }

  void update(CartItem it, {required int qty, required String note}) {
    if (qty <= 0) {
      items.remove(it);
    } else {
      it.qty = qty;
      it.note = note.trim();
    }
    notifyListeners();
  }

  void remove(CartItem it) {
    items.remove(it);
    notifyListeners();
  }

  void setDiscount(int value, bool percent) {
    discountValue = value < 0 ? 0 : value;
    discountPercent = percent;
    if (percent && discountValue > 100) discountValue = 100;
    notifyListeners();
  }

  void setCustomer(String v) {
    customer = v;
  }

  void setOrderType(String v) {
    orderType = v;
    notifyListeners();
  }

  void clear() {
    items.clear();
    customer = '';
    discountValue = 0;
    discountPercent = false;
    heldId = null;
    heldLabel = '';
    notifyListeners();
  }

  String toJsonString() => jsonEncode({
        'items': items.map((e) => e.toJson()).toList(),
        'customer': customer,
        'orderType': orderType,
        'discountValue': discountValue,
        'discountPercent': discountPercent,
      });

  void loadHeld(HeldOrder h) {
    items.clear();
    try {
      final j = jsonDecode(h.data) as Map<String, dynamic>;
      for (final e in (j['items'] as List? ?? const [])) {
        items.add(CartItem.fromJson(Map<String, dynamic>.from(e as Map)));
      }
      customer = toStr(j['customer']);
      orderType = toStr(j['orderType']);
      discountValue = toInt(j['discountValue']);
      discountPercent = j['discountPercent'] == true;
    } catch (_) {}
    heldId = h.id;
    heldLabel = h.label;
    notifyListeners();
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kasir_rumah_makan/cart_state.dart';
import 'package:kasir_rumah_makan/models.dart';
import 'package:kasir_rumah_makan/services/export.dart';
import 'package:kasir_rumah_makan/services/printer.dart';
import 'package:kasir_rumah_makan/utils/format.dart';

void main() {
  test('parseNum', () {
    expect(parseNum('Rp15.000'), 15000);
    expect(parseNum(''), 0);
  });

  test('hitung total keranjang', () {
    final c = CartState();
    c.add(MenuItem(id: 1, name: 'Nasi', price: 10000));
    c.add(MenuItem(id: 1, name: 'Nasi', price: 10000));
    c.setDiscount(10, true);
    final t = c.totals(10, 5);
    expect(t.subtotal, 20000);
    expect(t.discount, 2000);
    expect(t.service, 900); // 5% x 18.000
    expect(t.tax, 1890); // 10% x 18.900
    expect(t.total, 20790);
  });

  test('format baris struk', () {
    final f = TextFmt(32);
    expect(f.lr('TOTAL', '20.000').length, 32);
    expect(f.wrap('Nasi Goreng Spesial Pakai Telur Dadar Dan Kerupuk').every((l) => l.length <= 32), true);
  });

  test('xlsx valid zip', () {
    final wb = XlsxBuilder();
    final sh = wb.sheet('Tes', [20, 10]);
    sh.row([XC.header('Menu'), XC.header('Qty')]);
    sh.row([XC.text('Nasi & <Es>'), XC.number(3)]);
    final b = wb.build();
    expect(String.fromCharCodes(b.sublist(0, 2)), 'PK');
  });

  test('laba rugi', () {
    final d = ReportData(DateTime(2026, 1, 1), DateTime(2026, 1, 1))
      ..gross = 100000
      ..discount = 5000
      ..service = 0
      ..tax = 9500
      ..expenseByCat = [NameValue('Bahan Baku', total: 40000), NameValue('Listrik', total: 10000)];
    final pl = ProfitLoss.from(d, ['bahan baku']);
    expect(pl.revenue, 95000);
    expect(pl.hpp, 40000);
    expect(pl.grossProfit, 55000);
    expect(pl.opex, 10000);
    expect(pl.net, 45000);
  });
}

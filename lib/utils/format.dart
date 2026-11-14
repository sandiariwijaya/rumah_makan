import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _nf = NumberFormat.decimalPattern('id_ID');

/// Format rupiah: Rp15.000
String rp(num v) => v < 0 ? '-Rp${_nf.format(v.abs())}' : 'Rp${_nf.format(v)}';

/// Format angka ribuan: 15.000
String nf(num v) => _nf.format(v);

String fmtDate(DateTime d) => DateFormat('dd MMM yyyy', 'id_ID').format(d);
String fmtDateShort(DateTime d) => DateFormat('dd/MM/yy', 'id_ID').format(d);
String fmtDateTime(DateTime d) => DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(d);
String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
String fmtDayName(DateTime d) => DateFormat('EEEE, dd MMM yyyy', 'id_ID').format(d);

String dbDateTime(DateTime d) => DateFormat('yyyy-MM-dd HH:mm:ss').format(d);
String dbDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

int parseNum(String s) {
  final t = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (t.isEmpty) return 0;
  return int.tryParse(t) ?? 0;
}

double parseDouble(String s) => double.tryParse(s.replaceAll(',', '.').trim()) ?? 0;

/// Input angka otomatis jadi format ribuan (15.000)
class RupiahFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue(text: '');
    if (digits.length > 13) digits = digits.substring(0, 13);
    final n = int.parse(digits);
    final t = _nf.format(n);
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

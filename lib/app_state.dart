import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'db/database.dart';
import 'models.dart';

class ThemeSeed {
  final String name;
  final Color color;
  const ThemeSeed(this.name, this.color);
}

class AppState extends ChangeNotifier {
  static const List<ThemeSeed> seeds = [
    ThemeSeed('Hijau Toska', Color(0xFF00897B)),
    ThemeSeed('Oranye', Color(0xFFEF6C00)),
    ThemeSeed('Merah', Color(0xFFC62828)),
    ThemeSeed('Biru', Color(0xFF1565C0)),
    ThemeSeed('Indigo', Color(0xFF3949AB)),
    ThemeSeed('Hijau', Color(0xFF2E7D32)),
    ThemeSeed('Ungu', Color(0xFF6A1B9A)),
    ThemeSeed('Coklat', Color(0xFF6D4C41)),
  ];

  static const Map<String, String> defaults = {
    // toko
    'store_name': 'Rumah Makan Saya',
    'store_address': 'Jl. Contoh No. 1',
    'store_phone': '',
    'logo_b64': '',
    'qris_b64': '',
    // struk
    'receipt_header': '',
    'receipt_footer': 'Terima kasih atas kunjungan Anda',
    'rc_show_logo': '1',
    'rc_show_name': '1',
    'rc_show_address': '1',
    'rc_show_phone': '1',
    'rc_show_cashier': '1',
    'rc_show_customer': '1',
    'rc_show_note': '1',
    'rc_title_big': '1',
    'rc_title_wide': '0',
    // transaksi
    'tax_percent': '0',
    'service_percent': '0',
    'invoice_prefix': 'RM',
    'order_types': '', // rumah makan tanpa meja (bawa pulang)
    // printer
    'pr_address': '',
    'pr_name': '',
    'pr_chars': '32',
    'pr_dots': '384',
    'pr_font_b': '0',
    'pr_logo_mode': 'raster', // raster | escstar | off
    'pr_logo_percent': '60',
    'pr_dither': '0',
    'pr_margin_zero': '1',
    'pr_line_spacing': '0',
    'pr_feed': '3',
    'pr_cut': '0',
    'pr_copies': '1',
    'pr_chunk': '256',
    'pr_delay': '20',
    'pr_init': '1',
    'pr_drawer': '0',
    'pr_auto': '0',
    'pr_bold_total': '1',
    // tampilan
    'ui_mode': 'auto', // auto | phone | tablet
    'ui_orientation': 'auto', // auto | portrait | landscape
    'ui_color': '0',
    'ui_dark': '0', // 0 terang | 1 gelap | 2 sistem
    'ui_text_scale': '1.0',
    'ui_card': 'm', // s | m | l
    'ui_show_images': '1',
    'ui_haptic': '1',
    // hak akses kasir
    'perm_kasir_menu': '0',
    'perm_kasir_expense': '1',
    'perm_kasir_report': '0',
    'perm_kasir_discount': '1',
    // lain
    'expense_categories': 'Bahan Baku,Gas & Air,Listrik,Gaji,Sewa,Operasional,Lain-lain',
    'backup_last_slot': '0',
    'backup_last_time': '',
    'backup_last_file': '',
    'first_run_shown': '0',
  };

  Map<String, String> _s = {};
  AppUser? user;

  String? _logoKey;
  Uint8List? _logo;
  String? _qrisKey;
  Uint8List? _qris;

  Future<void> load() async {
    _s = await Repo.settings();
    applyOrientation();
    notifyListeners();
  }

  String get(String k) => _s[k] ?? defaults[k] ?? '';
  bool b(String k) => get(k) == '1';
  int i(String k, [int def = 0]) => int.tryParse(get(k).trim()) ?? def;
  double d(String k, [double def = 0]) => double.tryParse(get(k).trim().replaceAll(',', '.')) ?? def;

  Future<void> set(String k, String v) => setMany({k: v});

  Future<void> setMany(Map<String, String> values) async {
    _s.addAll(values);
    await Repo.setSettings(values);
    if (values.containsKey('ui_orientation')) applyOrientation();
    notifyListeners();
  }

  void setUser(AppUser? u) {
    user = u;
    Activity.user = u?.name ?? '';
    notifyListeners();
  }

  bool get isOwner => user?.isOwner ?? false;

  /// perm: menu | expense | report | discount (hapus transaksi khusus owner)
  bool can(String perm) => isOwner || b('perm_kasir_$perm');

  Uint8List? get logo {
    final k = get('logo_b64');
    if (k != _logoKey) {
      _logoKey = k;
      _logo = _decode(k);
    }
    return _logo;
  }

  Uint8List? get qris {
    final k = get('qris_b64');
    if (k != _qrisKey) {
      _qrisKey = k;
      _qris = _decode(k);
    }
    return _qris;
  }

  static Uint8List? _decode(String s) {
    if (s.isEmpty) return null;
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  Color get seedColor {
    var idx = i('ui_color');
    if (idx < 0 || idx >= seeds.length) idx = 0;
    return seeds[idx].color;
  }

  ThemeMode get themeMode {
    switch (get('ui_dark')) {
      case '1':
        return ThemeMode.dark;
      case '2':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  double get textScale {
    final v = d('ui_text_scale', 1.0);
    if (v < 0.8 || v > 1.5) return 1.0;
    return v;
  }

  bool isTablet(BuildContext context) {
    switch (get('ui_mode')) {
      case 'tablet':
        return true;
      case 'phone':
        return false;
      default:
        return MediaQuery.sizeOf(context).shortestSide >= 600;
    }
  }

  double get menuCardExtent {
    switch (get('ui_card')) {
      case 's':
        return 120;
      case 'l':
        return 200;
      default:
        return 155;
    }
  }

  List<String> get orderTypes =>
      get('order_types').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  List<String> get expenseCategories =>
      get('expense_categories').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  void applyOrientation() {
    List<DeviceOrientation> o;
    switch (get('ui_orientation')) {
      case 'portrait':
        o = [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown];
        break;
      case 'landscape':
        o = [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight];
        break;
      default:
        o = [];
    }
    SystemChrome.setPreferredOrientations(o);
  }
}

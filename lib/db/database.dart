import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models.dart';
import '../utils/format.dart';

String hashPw(String pw) => sha256.convert(utf8.encode('kasirRM::$pw')).toString();

const String kDefaultPassword = 'Sandi123';
const String kDefaultUsername = 'owner';

/// Log aktivitas pengguna (siapa melakukan apa & kapan)
class Activity {
  static String user = '';
  static String _lastKey = '';
  static DateTime _lastTime = DateTime(2000);

  static Future<void> log(String category, String action, [String detail = '']) async {
    try {
      final now = DateTime.now();
      final key = '$user|$category|$action|$detail';
      // cegah log ganda berturut-turut (mis. geser slider)
      if (key == _lastKey && now.difference(_lastTime).inSeconds < 60) return;
      _lastKey = key;
      _lastTime = now;
      final db = await Db.instance;
      await db.insert('activity_logs', {
        'created_at': dbDateTime(now),
        'user_name': user,
        'category': category,
        'action': action,
        'detail': detail,
      });
    } catch (_) {}
  }
}

String? _settingGroup(String k) {
  if (k.startsWith('backup_') || k.startsWith('activated') || k == 'first_run_shown' || k == 'seeded' || k.startsWith('ui_')) return null;
  if (k.startsWith('pr_')) return 'Printer';
  if (k.startsWith('rc_') || k.startsWith('receipt_')) return 'Struk';
  if (k.startsWith('perm_')) return 'Hak akses kasir';
  if (k.startsWith('store_') || k == 'logo_b64') return 'Profil toko & logo';
  if (k == 'qris_b64') return 'Gambar QRIS';
  return 'Transaksi & pajak';
}

const Map<String, String> _settingLabels = {
  'perm_kasir_menu': 'Kelola menu',
  'perm_kasir_expense': 'Catat pengeluaran',
  'perm_kasir_report': 'Lihat laporan',
  'perm_kasir_discount': 'Memberi diskon',
  'tax_percent': 'Pajak %',
  'service_percent': 'Service %',
  'invoice_prefix': 'Awalan nota',
  'expense_categories': 'Kategori pengeluaran',
  'hpp_categories': 'Kategori HPP',
};

class Db {
  static Database? _db;
  static Future<Database>? _opening;
  static const String fileName = 'kasir_rumah_makan.db';

  static Future<String> path() async => p.join(await getDatabasesPath(), fileName);

  static Future<Database> get instance {
    final d = _db;
    if (d != null && d.isOpen) return Future.value(d);
    return _opening ??= _open();
  }

  static Future<Database> _open() async {
    try {
      final db = await openDatabase(
        await path(),
        onOpen: (db) async {
          await _schema(db);
          await _seed(db);
        },
      );
      _db = db;
      return db;
    } finally {
      _opening = null;
    }
  }

  static Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null && d.isOpen) await d.close();
  }

  static Future<void> _schema(Database db) async {
    const stmts = [
      'CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT)',
      "CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL, name TEXT NOT NULL, password TEXT NOT NULL, role TEXT NOT NULL DEFAULT 'kasir', active INTEGER NOT NULL DEFAULT 1, created_at TEXT)",
      'CREATE TABLE IF NOT EXISTS categories(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, sort INTEGER NOT NULL DEFAULT 0)',
      'CREATE TABLE IF NOT EXISTS menu_items(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, category_id INTEGER, price INTEGER NOT NULL DEFAULT 0, image BLOB, available INTEGER NOT NULL DEFAULT 1, sort INTEGER NOT NULL DEFAULT 0, created_at TEXT)',
      'CREATE TABLE IF NOT EXISTS payment_methods(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, is_cash INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1, sort INTEGER NOT NULL DEFAULT 0)',
      "CREATE TABLE IF NOT EXISTS sales(id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL, created_at TEXT NOT NULL, user_id INTEGER, user_name TEXT, customer TEXT, order_type TEXT, subtotal INTEGER NOT NULL DEFAULT 0, discount INTEGER NOT NULL DEFAULT 0, service INTEGER NOT NULL DEFAULT 0, tax INTEGER NOT NULL DEFAULT 0, total INTEGER NOT NULL DEFAULT 0, payment_method TEXT, is_cash INTEGER NOT NULL DEFAULT 1, paid INTEGER NOT NULL DEFAULT 0, change_amount INTEGER NOT NULL DEFAULT 0, reference TEXT, status TEXT NOT NULL DEFAULT 'paid', void_reason TEXT, void_by TEXT, void_at TEXT)",
      'CREATE INDEX IF NOT EXISTS idx_sales_date ON sales(created_at)',
      'CREATE TABLE IF NOT EXISTS sale_items(id INTEGER PRIMARY KEY AUTOINCREMENT, sale_id INTEGER NOT NULL, menu_id INTEGER, name TEXT NOT NULL, price INTEGER NOT NULL DEFAULT 0, qty INTEGER NOT NULL DEFAULT 1, note TEXT, subtotal INTEGER NOT NULL DEFAULT 0)',
      'CREATE INDEX IF NOT EXISTS idx_items_sale ON sale_items(sale_id)',
      'CREATE TABLE IF NOT EXISTS held_orders(id INTEGER PRIMARY KEY AUTOINCREMENT, label TEXT, created_at TEXT, data TEXT NOT NULL)',
      'CREATE TABLE IF NOT EXISTS expenses(id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, category TEXT, description TEXT, amount INTEGER NOT NULL DEFAULT 0, method TEXT, user_name TEXT, created_at TEXT)',
      'CREATE INDEX IF NOT EXISTS idx_exp_date ON expenses(date)',
      'CREATE TABLE IF NOT EXISTS activity_logs(id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, user_name TEXT, category TEXT, action TEXT, detail TEXT)',
      'CREATE INDEX IF NOT EXISTS idx_log_date ON activity_logs(created_at)',
    ];
    for (final s in stmts) {
      await db.execute(s);
    }
  }

  static Future<int> _count(Database db, String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  static Future<void> _seed(Database db) async {
    final now = dbDateTime(DateTime.now());
    if (await _count(db, 'users') == 0) {
      await db.insert('users', {
        'username': kDefaultUsername,
        'name': 'Owner',
        'password': hashPw(kDefaultPassword),
        'role': 'owner',
        'active': 1,
        'created_at': now,
      });
    }
    if (await _count(db, 'payment_methods') == 0) {
      final pm = [
        ['Tunai', 1],
        ['QRIS', 0],
        ['Transfer Bank', 0],
        ['Debit/Kartu', 0],
        ['E-Wallet', 0],
      ];
      for (var i = 0; i < pm.length; i++) {
        await db.insert('payment_methods', {'name': pm[i][0], 'is_cash': pm[i][1], 'active': 1, 'sort': i});
      }
    }
    final seeded = await db.query('settings', where: 'key=?', whereArgs: ['seeded']);
    if (seeded.isEmpty) {
      if (await _count(db, 'categories') == 0 && await _count(db, 'menu_items') == 0) {
        final makanan = await db.insert('categories', {'name': 'Makanan', 'sort': 0});
        final minuman = await db.insert('categories', {'name': 'Minuman', 'sort': 1});
        await db.insert('categories', {'name': 'Snack', 'sort': 2});
        final samples = [
          ['Nasi Goreng Spesial', makanan, 18000],
          ['Mie Goreng', makanan, 15000],
          ['Ayam Bakar', makanan, 22000],
          ['Soto Ayam', makanan, 15000],
          ['Es Teh Manis', minuman, 4000],
          ['Es Jeruk', minuman, 6000],
          ['Kopi Hitam', minuman, 5000],
        ];
        for (var i = 0; i < samples.length; i++) {
          await db.insert('menu_items', {
            'name': samples[i][0],
            'category_id': samples[i][1],
            'price': samples[i][2],
            'available': 1,
            'sort': i,
            'created_at': now,
          });
        }
      }
      await db.insert('settings', {'key': 'seeded', 'value': '1'}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Cek apakah file adalah database aplikasi ini yang valid
  static Future<bool> isValidAppDb(String filePath) async {
    Database? d;
    try {
      d = await openDatabase(filePath, readOnly: true, singleInstance: false);
      final t = await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name IN ('users','sales','menu_items')");
      return t.length == 3;
    } catch (_) {
      return false;
    } finally {
      try {
        await d?.close();
      } catch (_) {}
    }
  }
}

class Repo {
  // ---------------- SETTINGS ----------------
  static Future<Map<String, String>> settings() async {
    final db = await Db.instance;
    final r = await db.query('settings');
    return {for (final m in r) toStr(m['key']): toStr(m['value'])};
  }

  static Future<void> setSettings(Map<String, String> values) async {
    final db = await Db.instance;
    final b = db.batch();
    values.forEach((k, v) {
      b.insert('settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await b.commit(noResult: true);
    final groups = <String, List<String>>{};
    values.forEach((k, v) {
      final g = _settingGroup(k);
      if (g == null) return;
      final label = _settingLabels[k];
      final list = groups.putIfAbsent(g, () => []);
      if (label != null) {
        final val = k.startsWith('perm_') ? (v == '1' ? 'aktif' : 'nonaktif') : v;
        list.add('$label: $val');
      }
    });
    for (final e in groups.entries) {
      await Activity.log('pengaturan', 'Ubah pengaturan ${e.key}', e.value.join(', '));
    }
  }

  // ---------------- USERS ----------------
  static Future<List<AppUser>> users({bool onlyActive = false}) async {
    final db = await Db.instance;
    final r = await db.query('users',
        where: onlyActive ? 'active=1' : null, orderBy: "CASE role WHEN 'owner' THEN 0 ELSE 1 END, name");
    return r.map(AppUser.fromMap).toList();
  }

  static Future<AppUser?> login(String username, String password) async {
    final db = await Db.instance;
    final r = await db.query('users',
        where: 'LOWER(username)=? AND active=1', whereArgs: [username.trim().toLowerCase()], limit: 1);
    if (r.isEmpty) return null;
    if (toStr(r.first['password']) != hashPw(password)) return null;
    return AppUser.fromMap(r.first);
  }

  static Future<bool> checkPassword(int userId, String password) async {
    final db = await Db.instance;
    final r = await db.query('users', where: 'id=?', whereArgs: [userId], limit: 1);
    return r.isNotEmpty && toStr(r.first['password']) == hashPw(password);
  }

  static Future<void> setPassword(int userId, String password) async {
    final db = await Db.instance;
    await db.update('users', {'password': hashPw(password)}, where: 'id=?', whereArgs: [userId]);
    await Activity.log('pengguna', 'Ganti password');
  }

  static Future<int> _activeOwnersExcept(Database db, int? exceptId) async {
    return Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM users WHERE role='owner' AND active=1 AND id<>?", [exceptId ?? -1])) ??
        0;
  }

  /// return null = sukses, selain itu pesan error
  static Future<String?> saveUser({
    int? id,
    required String username,
    required String name,
    required String role,
    required bool active,
    String? password,
  }) async {
    final db = await Db.instance;
    final u = username.trim().toLowerCase();
    if (u.isEmpty || name.trim().isEmpty) return 'Username dan nama wajib diisi';
    if (u.contains(' ')) return 'Username tidak boleh mengandung spasi';
    final dup = await db.query('users', where: 'LOWER(username)=? AND id<>?', whereArgs: [u, id ?? -1]);
    if (dup.isNotEmpty) return 'Username sudah dipakai';
    if (id != null && (role != 'owner' || !active)) {
      if (await _activeOwnersExcept(db, id) == 0) return 'Minimal harus ada 1 owner aktif';
    }
    final data = <String, Object?>{'username': u, 'name': name.trim(), 'role': role, 'active': active ? 1 : 0};
    if (id == null) {
      if (password == null || password.length < 4) return 'Password minimal 4 karakter';
      data['password'] = hashPw(password);
      data['created_at'] = dbDateTime(DateTime.now());
      await db.insert('users', data);
      await Activity.log('pengguna', 'Tambah pengguna', '$u ($role)');
    } else {
      final pw = password ?? '';
      final pwChanged = pw.isNotEmpty;
      if (pwChanged) {
        if (pw.length < 4) return 'Password minimal 4 karakter';
        data['password'] = hashPw(pw);
      }
      await db.update('users', data, where: 'id=?', whereArgs: [id]);
      await Activity.log('pengguna', 'Ubah pengguna',
          '$u ($role${active ? '' : ', nonaktif'})${pwChanged ? ', password direset' : ''}');
    }
    return null;
  }

  static Future<String?> deleteUser(int id) async {
    final db = await Db.instance;
    if (await _activeOwnersExcept(db, id) == 0) {
      final r = await db.query('users', where: 'id=?', whereArgs: [id]);
      if (r.isNotEmpty && toStr(r.first['role']) == 'owner') return 'Owner terakhir tidak boleh dihapus';
    }
    final r = await db.query('users', where: 'id=?', whereArgs: [id]);
    await db.delete('users', where: 'id=?', whereArgs: [id]);
    await Activity.log('pengguna', 'Hapus pengguna', r.isEmpty ? '#$id' : toStr(r.first['username']));
    return null;
  }

  // ---------------- CATEGORIES ----------------
  static Future<List<Category>> categories() async {
    final db = await Db.instance;
    final r = await db.query('categories', orderBy: 'sort, name');
    return r.map(Category.fromMap).toList();
  }

  static Future<void> saveCategory({int? id, required String name, int sort = 0}) async {
    final db = await Db.instance;
    if (id == null) {
      await db.insert('categories', {'name': name.trim(), 'sort': sort});
      await Activity.log('menu', 'Tambah kategori', name.trim());
    } else {
      final old = await db.query('categories', where: 'id=?', whereArgs: [id]);
      await db.update('categories', {'name': name.trim(), 'sort': sort}, where: 'id=?', whereArgs: [id]);
      final oldName = old.isEmpty ? '' : toStr(old.first['name']);
      if (oldName != name.trim()) await Activity.log('menu', 'Ubah kategori', '$oldName -> ${name.trim()}');
    }
  }

  static Future<void> deleteCategory(int id) async {
    final db = await Db.instance;
    final old = await db.query('categories', where: 'id=?', whereArgs: [id]);
    await Activity.log('menu', 'Hapus kategori', old.isEmpty ? '#$id' : toStr(old.first['name']));
    await db.transaction((t) async {
      await t.update('menu_items', {'category_id': null}, where: 'category_id=?', whereArgs: [id]);
      await t.delete('categories', where: 'id=?', whereArgs: [id]);
    });
  }

  // ---------------- MENU ----------------
  static Future<List<MenuItem>> menus() async {
    final db = await Db.instance;
    final r = await db.rawQuery(
        'SELECT m.*, c.name AS category_name FROM menu_items m LEFT JOIN categories c ON c.id=m.category_id ORDER BY COALESCE(c.sort,9999), m.sort, m.name');
    return r.map(MenuItem.fromMap).toList();
  }

  static Future<int> saveMenu(MenuItem m) async {
    final db = await Db.instance;
    if (m.id == null) {
      final data = m.toMap()..['created_at'] = dbDateTime(DateTime.now());
      final id = await db.insert('menu_items', data);
      await Activity.log('menu', 'Tambah menu', '${m.name} ${rp(m.price)}');
      return id;
    }
    final old = await db.query('menu_items', columns: ['name', 'price'], where: 'id=?', whereArgs: [m.id]);
    await db.update('menu_items', m.toMap(), where: 'id=?', whereArgs: [m.id]);
    final changes = <String>[];
    if (old.isNotEmpty) {
      final oldName = toStr(old.first['name']);
      final oldPrice = toInt(old.first['price']);
      if (oldName != m.name) changes.add('nama $oldName -> ${m.name}');
      if (oldPrice != m.price) changes.add('harga ${rp(oldPrice)} -> ${rp(m.price)}');
    }
    await Activity.log('menu', 'Ubah menu', '${m.name}${changes.isEmpty ? '' : ' (${changes.join(', ')})'}');
    return m.id!;
  }

  static Future<void> setMenuAvailable(int id, bool available) async {
    final db = await Db.instance;
    await db.update('menu_items', {'available': available ? 1 : 0}, where: 'id=?', whereArgs: [id]);
    final r = await db.query('menu_items', columns: ['name'], where: 'id=?', whereArgs: [id]);
    await Activity.log('menu', available ? 'Menu tersedia' : 'Menu ditandai habis', r.isEmpty ? '' : toStr(r.first['name']));
  }

  static Future<void> deleteMenu(int id) async {
    final db = await Db.instance;
    final r = await db.query('menu_items', columns: ['name'], where: 'id=?', whereArgs: [id]);
    await db.delete('menu_items', where: 'id=?', whereArgs: [id]);
    await Activity.log('menu', 'Hapus menu', r.isEmpty ? '#$id' : toStr(r.first['name']));
  }

  // ---------------- PAYMENT METHODS ----------------
  static Future<List<PayMethod>> payMethods({bool onlyActive = false}) async {
    final db = await Db.instance;
    final r = await db.query('payment_methods', where: onlyActive ? 'active=1' : null, orderBy: 'sort, id');
    return r.map(PayMethod.fromMap).toList();
  }

  static Future<void> savePayMethod(PayMethod m) async {
    final db = await Db.instance;
    final data = {'name': m.name.trim(), 'is_cash': m.isCash ? 1 : 0, 'active': m.active ? 1 : 0, 'sort': m.sort};
    if (m.id == null) {
      await db.insert('payment_methods', data);
      await Activity.log('pengaturan', 'Tambah metode bayar', m.name.trim());
    } else {
      await db.update('payment_methods', data, where: 'id=?', whereArgs: [m.id]);
      await Activity.log('pengaturan', 'Ubah metode bayar', '${m.name.trim()}${m.active ? '' : ' (nonaktif)'}');
    }
  }

  static Future<String?> deletePayMethod(int id) async {
    final db = await Db.instance;
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM payment_methods WHERE id<>? AND active=1', [id])) ?? 0;
    if (n == 0) return 'Minimal harus ada 1 metode pembayaran aktif';
    final r = await db.query('payment_methods', where: 'id=?', whereArgs: [id]);
    await db.delete('payment_methods', where: 'id=?', whereArgs: [id]);
    await Activity.log('pengaturan', 'Hapus metode bayar', r.isEmpty ? '' : toStr(r.first['name']));
    return null;
  }

  // ---------------- SALES ----------------
  static Future<int> saveSale(Sale s, List<CartItem> items, {required String prefix, int? userId}) async {
    final db = await Db.instance;
    final id = await db.transaction((txn) async {
      final now = DateTime.now();
      final day = dbDay(now);
      final cnt = Sqflite.firstIntValue(
              await txn.rawQuery('SELECT COUNT(*) FROM sales WHERE created_at >= ? AND created_at < ?',
                  ['$day 00:00:00', '$day 99'])) ??
          0;
      final inv = '$prefix${DateFormat('yyMMdd').format(now)}-${(cnt + 1).toString().padLeft(4, '0')}';
      final saleId = await txn.insert('sales', {
        'invoice_no': inv,
        'created_at': dbDateTime(now),
        'user_id': userId,
        'user_name': s.userName,
        'customer': s.customer,
        'order_type': s.orderType,
        'subtotal': s.subtotal,
        'discount': s.discount,
        'service': s.service,
        'tax': s.tax,
        'total': s.total,
        'payment_method': s.paymentMethod,
        'is_cash': s.isCash ? 1 : 0,
        'paid': s.paid,
        'change_amount': s.change,
        'reference': s.reference,
        'status': 'paid',
      });
      for (final it in items) {
        await txn.insert('sale_items', {
          'sale_id': saleId,
          'menu_id': it.menuId,
          'name': it.name,
          'price': it.price,
          'qty': it.qty,
          'note': it.note,
          'subtotal': it.subtotal,
        });
      }
      return saleId;
    });
    final inv = await db.query('sales', columns: ['invoice_no'], where: 'id=?', whereArgs: [id]);
    await Activity.log(
      'penjualan',
      'Transaksi baru',
      '${inv.isEmpty ? '' : toStr(inv.first['invoice_no'])} ${rp(s.total)} ${s.paymentMethod}'
          '${s.discount > 0 ? ' (diskon ${rp(s.discount)})' : ''}',
    );
    return id;
  }

  static Future<Sale?> sale(int id) async {
    final db = await Db.instance;
    final r = await db.query('sales', where: 'id=?', whereArgs: [id], limit: 1);
    if (r.isEmpty) return null;
    final s = Sale.fromMap(r.first);
    final it = await db.query('sale_items', where: 'sale_id=?', whereArgs: [id], orderBy: 'id');
    s.items = it.map(SaleItem.fromMap).toList();
    return s;
  }

  static List<String> _range(DateTime from, DateTime to) =>
      [dbDateTime(dayStart(from)), dbDateTime(dayStart(to).add(const Duration(days: 1)))];

  static Future<List<Sale>> sales(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final r = await db.query('sales',
        where: 'created_at >= ? AND created_at < ?', whereArgs: _range(from, to), orderBy: 'created_at DESC, id DESC');
    return r.map(Sale.fromMap).toList();
  }

  static Future<List<Sale>> salesWithItems(DateTime from, DateTime to) async {
    final list = await sales(from, to);
    if (list.isEmpty) return list;
    final db = await Db.instance;
    final rows = await db.rawQuery(
        'SELECT si.* FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.created_at >= ? AND s.created_at < ? ORDER BY si.id',
        _range(from, to));
    final map = <int, List<SaleItem>>{};
    for (final r in rows) {
      map.putIfAbsent(toInt(r['sale_id']), () => []).add(SaleItem.fromMap(r));
    }
    for (final s in list) {
      s.items = map[s.id] ?? [];
    }
    return list;
  }

  /// Hapus transaksi permanen (khusus owner). Tercatat di log aktivitas.
  static Future<void> deleteSale(int id, String reason) async {
    final db = await Db.instance;
    final s = await sale(id);
    await db.transaction((t) async {
      await t.delete('sale_items', where: 'sale_id=?', whereArgs: [id]);
      await t.delete('sales', where: 'id=?', whereArgs: [id]);
    });
    if (s != null) {
      final items = s.items.map((e) => '${e.qty}x ${e.name}').join(', ');
      await Activity.log('penjualan', 'Hapus transaksi',
          '${s.invoiceNo} ${rp(s.total)} ${s.paymentMethod} (kasir ${s.userName}, ${dbDateTime(s.createdAt)}) [$items]'
              '${reason.trim().isEmpty ? '' : ' Alasan: ${reason.trim()}'}');
    }
  }

  // ---------------- HELD ORDERS ----------------
  static Future<List<HeldOrder>> heldOrders() async {
    final db = await Db.instance;
    final r = await db.query('held_orders', orderBy: 'id DESC');
    return r.map(HeldOrder.fromMap).toList();
  }

  static Future<int> saveHeld({int? id, required String label, required String data}) async {
    final db = await Db.instance;
    if (id != null) {
      final n = await db.update('held_orders', {'label': label, 'data': data}, where: 'id=?', whereArgs: [id]);
      if (n > 0) return id;
    }
    return db.insert('held_orders', {'label': label, 'data': data, 'created_at': dbDateTime(DateTime.now())});
  }

  static Future<void> deleteHeld(int id) async {
    final db = await Db.instance;
    await db.delete('held_orders', where: 'id=?', whereArgs: [id]);
  }

  static Future<int> heldCount() async {
    final db = await Db.instance;
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM held_orders')) ?? 0;
  }

  // ---------------- EXPENSES ----------------
  static Future<List<Expense>> expenses(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final r = await db.query('expenses',
        where: 'date >= ? AND date <= ?', whereArgs: [dbDay(from), dbDay(to)], orderBy: 'date DESC, id DESC');
    return r.map(Expense.fromMap).toList();
  }

  static Future<void> saveExpense(Expense e) async {
    final db = await Db.instance;
    final data = {
      'date': dbDay(e.date),
      'category': e.category,
      'description': e.description,
      'amount': e.amount,
      'method': e.method,
      'user_name': e.userName,
    };
    final desc = '${e.category}${e.description.isEmpty ? '' : ' - ${e.description}'} ${rp(e.amount)}';
    if (e.id == null) {
      data['created_at'] = dbDateTime(DateTime.now());
      await db.insert('expenses', data);
      await Activity.log('pengeluaran', 'Tambah pengeluaran', desc);
    } else {
      final old = await db.query('expenses', columns: ['amount'], where: 'id=?', whereArgs: [e.id]);
      await db.update('expenses', data, where: 'id=?', whereArgs: [e.id]);
      final oldAmt = old.isEmpty ? e.amount : toInt(old.first['amount']);
      await Activity.log('pengeluaran', 'Ubah pengeluaran', '$desc${oldAmt != e.amount ? ' (sebelumnya ${rp(oldAmt)})' : ''}');
    }
  }

  static Future<void> deleteExpense(int id) async {
    final db = await Db.instance;
    final r = await db.query('expenses', where: 'id=?', whereArgs: [id]);
    await db.delete('expenses', where: 'id=?', whereArgs: [id]);
    if (r.isNotEmpty) {
      final e = Expense.fromMap(r.first);
      await Activity.log('pengeluaran', 'Hapus pengeluaran',
          '${dbDay(e.date)} ${e.category}${e.description.isEmpty ? '' : ' - ${e.description}'} ${rp(e.amount)}');
    }
  }

  // ---------------- REPORT ----------------
  static Future<ReportData> report(DateTime from, DateTime to) async {
    final db = await Db.instance;
    final rg = _range(from, to);
    final d = ReportData(from, to);
    final s = await db.rawQuery(
        "SELECT COUNT(*) c, COALESCE(SUM(subtotal),0) g, COALESCE(SUM(discount),0) d, COALESCE(SUM(tax),0) t, COALESCE(SUM(service),0) sv, COALESCE(SUM(total),0) tot FROM sales WHERE status='paid' AND created_at >= ? AND created_at < ?",
        rg);
    final m = s.first;
    d.trxCount = toInt(m['c']);
    d.gross = toInt(m['g']);
    d.discount = toInt(m['d']);
    d.tax = toInt(m['t']);
    d.service = toInt(m['sv']);
    d.total = toInt(m['tot']);
    d.voidCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM sales WHERE status='void' AND created_at >= ? AND created_at < ?", rg)) ??
        0;
    final bm = await db.rawQuery(
        "SELECT COALESCE(payment_method,'-') n, COUNT(*) c, COALESCE(SUM(total),0) t FROM sales WHERE status='paid' AND created_at >= ? AND created_at < ? GROUP BY payment_method ORDER BY t DESC",
        rg);
    d.byMethod = bm.map((r) => NameValue(toStr(r['n']), count: toInt(r['c']), total: toInt(r['t']))).toList();
    final bc = await db.rawQuery(
        "SELECT COALESCE(NULLIF(user_name,''),'-') n, COUNT(*) c, COALESCE(SUM(total),0) t FROM sales WHERE status='paid' AND created_at >= ? AND created_at < ? GROUP BY n ORDER BY t DESC",
        rg);
    d.byCashier = bc.map((r) => NameValue(toStr(r['n']), count: toInt(r['c']), total: toInt(r['t']))).toList();
    final top = await db.rawQuery(
        "SELECT si.name n, COALESCE(SUM(si.qty),0) q, COALESCE(SUM(si.subtotal),0) t FROM sale_items si JOIN sales s ON s.id=si.sale_id WHERE s.status='paid' AND s.created_at >= ? AND s.created_at < ? GROUP BY si.name ORDER BY q DESC, t DESC LIMIT 100",
        rg);
    d.topItems = top.map((r) => NameValue(toStr(r['n']), qty: toInt(r['q']), total: toInt(r['t']))).toList();
    final daily = await db.rawQuery(
        "SELECT substr(created_at,1,10) n, COUNT(*) c, COALESCE(SUM(total),0) t FROM sales WHERE status='paid' AND created_at >= ? AND created_at < ? GROUP BY n ORDER BY n",
        rg);
    d.daily = daily.map((r) => NameValue(toStr(r['n']), count: toInt(r['c']), total: toInt(r['t']))).toList();
    final ex = await db.rawQuery(
        "SELECT COALESCE(NULLIF(category,''),'Lain-lain') n, COUNT(*) c, COALESCE(SUM(amount),0) t FROM expenses WHERE date >= ? AND date <= ? GROUP BY n ORDER BY t DESC",
        [dbDay(from), dbDay(to)]);
    d.expenseByCat = ex.map((r) => NameValue(toStr(r['n']), count: toInt(r['c']), total: toInt(r['t']))).toList();
    d.expense = d.expenseByCat.fold(0, (a, b) => a + b.total);
    return d;
  }

  // ---------------- LOG AKTIVITAS ----------------
  static Future<List<ActivityLog>> logs(DateTime from, DateTime to, {String? category, String query = ''}) async {
    final db = await Db.instance;
    final where = <String>['created_at >= ?', 'created_at < ?'];
    final args = <Object?>[..._range(from, to)];
    if (category != null && category.isNotEmpty) {
      where.add('category = ?');
      args.add(category);
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      where.add("(LOWER(action) LIKE ? OR LOWER(COALESCE(detail,'')) LIKE ? OR LOWER(COALESCE(user_name,'')) LIKE ?)");
      args.addAll(['%$q%', '%$q%', '%$q%']);
    }
    final r = await db.query('activity_logs', where: where.join(' AND '), whereArgs: args, orderBy: 'id DESC', limit: 2000);
    return r.map(ActivityLog.fromMap).toList();
  }
}

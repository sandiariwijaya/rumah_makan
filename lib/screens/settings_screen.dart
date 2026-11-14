import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../cart_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/backup.dart';
import '../services/native.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import 'activity_log_screen.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'menu_screen.dart' show pickImageBytes;
import 'payment_sheet.dart' show payIcon;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  void _go(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final owner = app.isOwner;
    final user = app.user;

    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: onTap,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: (color ?? cs.primary).withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color ?? cs.primary),
              ),
              title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Pengaturan', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: cs.onPrimary.withOpacity(0.2),
                      child: Icon(owner ? Icons.workspace_premium_rounded : Icons.person_rounded, color: cs.onPrimary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? '', style: TextStyle(color: cs.onPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                          Text('${owner ? 'Owner' : 'Kasir'} • @${user?.username ?? ''}', style: TextStyle(color: cs.onPrimary.withOpacity(0.85))),
                          Text(app.get('store_name'), style: TextStyle(color: cs.onPrimary.withOpacity(0.85), fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Keluar',
                      onPressed: () => doLogout(context),
                      icon: Icon(Icons.logout_rounded, color: cs.onPrimary),
                    ),
                  ],
                ),
              ),
              if (owner) ...[
                const SectionTitle('TOKO'),
                tile(Icons.storefront_rounded, 'Profil Toko & Logo', 'Nama, alamat, telepon, logo', () => _go(context, const StoreSettingsPage())),
                tile(Icons.receipt_rounded, 'Struk / Resi', 'Header, footer, isi struk & pratinjau', () => _go(context, const ReceiptSettingsPage())),
                tile(Icons.percent_rounded, 'Transaksi & Pajak', 'Pajak, service, nomor nota, kategori pengeluaran',
                    () => _go(context, const TransactionSettingsPage())),
                tile(Icons.qr_code_2_rounded, 'Pembayaran & QRIS', 'Tunai, QRIS, transfer, e-wallet, gambar QRIS',
                    () => _go(context, const PaymentSettingsPage())),
              ],
              const SectionTitle('PERANGKAT'),
              tile(Icons.print_rounded, 'Printer Bluetooth',
                  app.get('pr_address').isEmpty ? 'Belum dipilih' : '${app.get('pr_name')} • ${app.i('pr_chars', 32)} karakter',
                  () => _go(context, const PrinterSettingsPage())),
              tile(Icons.devices_rounded, 'Tampilan (HP / Tablet)', 'Mode layar, warna tema, ukuran teks & kartu menu',
                  () => _go(context, const DisplaySettingsPage())),
              const SectionTitle('PENGGUNA'),
              if (owner)
                tile(Icons.people_alt_rounded, 'Pengguna & Hak Akses', 'Tambah kasir/owner, atur akses kasir', () => _go(context, const UsersPage())),
              tile(Icons.password_rounded, 'Ganti Password', 'Ubah password akun Anda', () => changePasswordDialog(context)),
              if (owner) ...[
                const SectionTitle('DATA'),
                tile(Icons.history_rounded, 'Log Aktivitas', 'Riwayat siapa melakukan apa: login, transaksi, hapus, ubah menu, dll.',
                    () => _go(context, const ActivityLogScreen()),
                    color: Colors.deepPurple),
                tile(Icons.backup_rounded, 'Backup & Restore',
                    app.get('backup_last_time').isEmpty ? 'Belum ada backup' : 'Terakhir: ${fmtDateTime(DateTime.tryParse(app.get('backup_last_time')) ?? DateTime.now())}',
                    () => _go(context, const BackupPage()),
                    color: Colors.teal),
              ],
              const SectionTitle('LAINNYA'),
              tile(Icons.info_outline_rounded, 'Tentang Aplikasi', 'Kasir Rumah Makan v1.0.0', () {
                showAboutDialog(
                  context: context,
                  applicationName: 'Kasir Rumah Makan',
                  applicationVersion: '1.0.0',
                  applicationIcon: Icon(Icons.restaurant_menu_rounded, color: cs.primary, size: 40),
                  children: const [
                    Text('Aplikasi kasir offline untuk rumah makan. Data tersimpan di HP dan dibackup otomatis setiap login (3 file berputar).'),
                  ],
                );
              }),
              tile(Icons.logout_rounded, 'Keluar', 'Keluar dari akun', () => doLogout(context), color: cs.error),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================= GANTI PASSWORD =======================
Future<void> changePasswordDialog(BuildContext context) async {
  final app = context.read<AppState>();
  final user = app.user;
  if (user == null) return;
  final oldC = TextEditingController();
  final newC = TextEditingController();
  final confC = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Ganti Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: oldC, obscureText: true, decoration: inputDeco('Password lama', icon: Icons.lock_outline)),
            const SizedBox(height: 10),
            TextField(controller: newC, obscureText: true, decoration: inputDeco('Password baru (min. 4)', icon: Icons.lock_reset)),
            const SizedBox(height: 10),
            TextField(controller: confC, obscureText: true, decoration: inputDeco('Ulangi password baru', icon: Icons.lock_reset)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
      ],
    ),
  );
  final o = oldC.text, n = newC.text, c = confC.text;
  disposeLater(oldC);
  disposeLater(newC);
  disposeLater(confC);
  if (ok != true) return;
  if (!await Repo.checkPassword(user.id, o)) {
    Notify.error('Password lama salah');
    return;
  }
  if (n.length < 4) {
    Notify.error('Password baru minimal 4 karakter');
    return;
  }
  if (n != c) {
    Notify.error('Konfirmasi password tidak sama');
    return;
  }
  await Repo.setPassword(user.id, n);
  Notify.success('Password berhasil diganti');
}

// ======================= HELPER FORM =======================
class _SettingsScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  const _SettingsScaffold({required this.title, required this.children, this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: children),
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: bottom),
            ),
    );
  }
}

Widget _switch(AppState app, String key, String title, {String? sub, ValueChanged<bool>? after}) => SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: app.b(key),
      title: Text(title),
      subtitle: sub == null ? null : Text(sub),
      onChanged: (v) async {
        await app.set(key, v ? '1' : '0');
        after?.call(v);
      },
    );

Widget _saveButton(VoidCallback onPressed, {String label = 'SIMPAN'}) => SizedBox(
      height: 52,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.save_rounded),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );

// ======================= PROFIL TOKO =======================
class StoreSettingsPage extends StatefulWidget {
  const StoreSettingsPage({super.key});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  late final AppState app = context.read<AppState>();
  late final _name = TextEditingController(text: app.get('store_name'));
  late final _addr = TextEditingController(text: app.get('store_address'));
  late final _phone = TextEditingController(text: app.get('store_phone'));

  @override
  void dispose() {
    _name.dispose();
    _addr.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final b = await pickImageBytes(context, maxWidth: 512, quality: 90);
    if (b == null) return;
    await app.set('logo_b64', base64Encode(b));
    Notify.success('Logo diperbarui');
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      Notify.warning('Nama toko wajib diisi');
      return;
    }
    await app.setMany({
      'store_name': _name.text.trim(),
      'store_address': _addr.text.trim(),
      'store_phone': _phone.text.trim(),
    });
    Notify.success('Profil toko disimpan');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final logo = app.logo;
    return _SettingsScaffold(
      title: 'Profil Toko & Logo',
      bottom: _saveButton(_save),
      children: [
        Center(
          child: GestureDetector(
            onTap: _pickLogo,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: logo != null
                  ? Image.memory(logo, fit: BoxFit.contain)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, size: 44, color: cs.primary),
                        const SizedBox(height: 6),
                        const Text('Pilih Logo', style: TextStyle(color: Colors.black87)),
                      ],
                    ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(onPressed: _pickLogo, icon: const Icon(Icons.image_rounded), label: const Text('Ganti Logo')),
            if (logo != null)
              TextButton.icon(
                onPressed: () async {
                  await app.set('logo_b64', '');
                  Notify.info('Logo dihapus');
                },
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                label: Text('Hapus', style: TextStyle(color: cs.error)),
              ),
          ],
        ),
        Text('Tips: logo hitam-putih dengan latar putih hasil cetaknya paling bagus di printer thermal.',
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 16),
        TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: inputDeco('Nama Rumah Makan', icon: Icons.storefront_rounded)),
        const SizedBox(height: 12),
        TextField(controller: _addr, maxLines: 2, decoration: inputDeco('Alamat', icon: Icons.place_rounded)),
        const SizedBox(height: 12),
        TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: inputDeco('Telepon / WA', icon: Icons.phone_rounded)),
      ],
    );
  }
}

// ======================= STRUK =======================
Sale sampleSale() => Sale(
      invoiceNo: 'RM261113-0001',
      createdAt: DateTime.now(),
      userName: 'Kasir',
      customer: 'Budi',
      subtotal: 52000,
      discount: 2000,
      total: 50000,
      paymentMethod: 'Tunai',
      isCash: true,
      paid: 100000,
      change: 50000,
      items: [
        SaleItem(name: 'Nasi Goreng Spesial', price: 18000, qty: 2, note: 'tidak pedas', subtotal: 36000),
        SaleItem(name: 'Es Teh Manis', price: 4000, qty: 4, subtotal: 16000),
      ],
    );

class ReceiptPreview extends StatelessWidget {
  final List<PItem> items;
  final int chars;
  const ReceiptPreview({super.key, required this.items, required this.chars});

  @override
  Widget build(BuildContext context) {
    final logo = items.whereType<PLogo>().isNotEmpty ? items.whereType<PLogo>().first.bytes : null;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final it in items)
                if (it is PLogo && logo != null)
                  SizedBox(
                    width: chars * 7.8,
                    child: Center(
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.33, 0.33, 0.33, 0, 0, //
                          0.33, 0.33, 0.33, 0, 0,
                          0.33, 0.33, 0.33, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                        child: Image.memory(logo, height: 60),
                      ),
                    ),
                  )
                else if (it is PText)
                  Text(
                    TextFmt.ascii(it.text).padRight(it.wide ? chars ~/ 2 : chars),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: it.big ? 20 : 13,
                      height: 1.25,
                      letterSpacing: it.wide ? 7.8 : 0,
                      fontWeight: it.bold ? FontWeight.w900 : FontWeight.w500,
                      color: Colors.black,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReceiptSettingsPage extends StatefulWidget {
  const ReceiptSettingsPage({super.key});

  @override
  State<ReceiptSettingsPage> createState() => _ReceiptSettingsPageState();
}

class _ReceiptSettingsPageState extends State<ReceiptSettingsPage> {
  late final AppState app = context.read<AppState>();
  late final _header = TextEditingController(text: app.get('receipt_header'));
  late final _footer = TextEditingController(text: app.get('receipt_footer'));

  @override
  void dispose() {
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _saveTexts() async {
    await app.setMany({'receipt_header': _header.text.trim(), 'receipt_footer': _footer.text.trim()});
    Notify.success('Teks struk disimpan');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return _SettingsScaffold(
      title: 'Struk / Resi',
      children: [
        TextField(controller: _header, maxLines: 2, decoration: inputDeco('Teks tambahan di atas (opsional)', icon: Icons.vertical_align_top_rounded)),
        const SizedBox(height: 12),
        TextField(controller: _footer, maxLines: 3, decoration: inputDeco('Teks bawah / footer', icon: Icons.vertical_align_bottom_rounded)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(onPressed: _saveTexts, icon: const Icon(Icons.save_rounded), label: const Text('Simpan Teks')),
        ),
        const SectionTitle('ISI STRUK'),
        _switch(app, 'rc_show_logo', 'Tampilkan logo'),
        _switch(app, 'rc_show_name', 'Tampilkan nama toko'),
        _switch(app, 'rc_title_big', 'Nama toko huruf tinggi'),
        _switch(app, 'rc_title_wide', 'Nama toko huruf lebar', sub: 'Huruf 2x lebar (untuk nama pendek)'),
        _switch(app, 'rc_show_address', 'Tampilkan alamat'),
        _switch(app, 'rc_show_phone', 'Tampilkan telepon'),
        _switch(app, 'rc_show_cashier', 'Tampilkan nama kasir'),
        _switch(app, 'rc_show_customer', 'Tampilkan nama pelanggan'),
        _switch(app, 'rc_show_note', 'Tampilkan catatan item'),
        _switch(app, 'pr_bold_total', 'TOTAL huruf besar'),
        const SectionTitle('PRATINJAU'),
        ReceiptPreview(items: Receipts.sale(app, sampleSale()), chars: Receipts.chars(app)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => PrinterService.printSale(app, sampleSale()),
          icon: const Icon(Icons.print_rounded),
          label: const Text('Cetak Contoh Struk'),
        ),
      ],
    );
  }
}

// ======================= TRANSAKSI & PAJAK =======================
class TransactionSettingsPage extends StatefulWidget {
  const TransactionSettingsPage({super.key});

  @override
  State<TransactionSettingsPage> createState() => _TransactionSettingsPageState();
}

class _TransactionSettingsPageState extends State<TransactionSettingsPage> {
  late final AppState app = context.read<AppState>();
  late final _tax = TextEditingController(text: app.get('tax_percent'));
  late final _svc = TextEditingController(text: app.get('service_percent'));
  late final _prefix = TextEditingController(text: app.get('invoice_prefix'));
  late final _expCats = TextEditingController(text: app.get('expense_categories'));

  @override
  void dispose() {
    for (final c in [_tax, _svc, _prefix, _expCats]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final tax = parseDouble(_tax.text);
    final svc = parseDouble(_svc.text);
    if (tax < 0 || tax > 100 || svc < 0 || svc > 100) {
      Notify.warning('Persentase harus 0 - 100');
      return;
    }
    String clean(String s) => s.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
    final prefix = _prefix.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9\-]'), '');
    await app.setMany({
      'tax_percent': tax.toString(),
      'service_percent': svc.toString(),
      'invoice_prefix': prefix,
      'expense_categories': clean(_expCats.text),
    });
    Notify.success('Pengaturan transaksi disimpan');
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final dec = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return _SettingsScaffold(
      title: 'Transaksi & Pajak',
      bottom: _saveButton(_save),
      children: [
        const SectionTitle('PAJAK & SERVICE'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tax,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: dec,
                decoration: inputDeco('Pajak (PB1)', suffix: '%', icon: Icons.account_balance_rounded),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _svc,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: dec,
                decoration: inputDeco('Service', suffix: '%', icon: Icons.room_service_rounded),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Isi 0 jika tidak dipakai. Pajak dihitung dari (subtotal - diskon + service).', style: TextStyle(fontSize: 12)),
        const SectionTitle('NOMOR NOTA'),
        TextField(
          controller: _prefix,
          decoration: inputDeco('Awalan nomor nota', icon: Icons.tag_rounded, hint: 'contoh: RM'),
        ),
        const SizedBox(height: 4),
        const Text('Format: AWALAN + yyMMdd - urutan. Contoh: RM261113-0001', style: TextStyle(fontSize: 12)),
        const SectionTitle('KATEGORI PENGELUARAN'),
        TextField(
          controller: _expCats,
          maxLines: 2,
          decoration: inputDeco('Pisahkan dengan koma', icon: Icons.category_outlined),
        ),
      ],
    );
  }
}

// ======================= PEMBAYARAN & QRIS =======================
class PaymentSettingsPage extends StatefulWidget {
  const PaymentSettingsPage({super.key});

  @override
  State<PaymentSettingsPage> createState() => _PaymentSettingsPageState();
}

class _PaymentSettingsPageState extends State<PaymentSettingsPage> {
  List<PayMethod> _list = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.payMethods();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _edit([PayMethod? m]) async {
    final name = TextEditingController(text: m?.name ?? '');
    var isCash = m?.isCash ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(m == null ? 'Tambah Metode' : 'Ubah Metode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, autofocus: true, decoration: inputDeco('Nama metode', hint: 'contoh: GoPay, OVO, Dana')),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isCash,
                onChanged: (v) => setD(() => isCash = v),
                title: const Text('Pembayaran tunai'),
                subtitle: const Text('Aktifkan untuk input uang diterima & kembalian'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = name.text.trim();
    disposeLater(name);
    if (ok != true || n.isEmpty) return;
    await Repo.savePayMethod(PayMethod(id: m?.id, name: n, isCash: isCash, active: m?.active ?? true, sort: m?.sort ?? _list.length));
    Notify.success('Metode pembayaran disimpan');
    _load();
  }

  Future<void> _pickQris() async {
    final app = context.read<AppState>();
    final b = await pickImageBytes(context, maxWidth: 900, quality: 92);
    if (b == null) return;
    await app.set('qris_b64', base64Encode(b));
    Notify.success('Gambar QRIS disimpan');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final qris = app.qris;
    return _SettingsScaffold(
      title: 'Pembayaran & QRIS',
      children: [
        SectionTitle('METODE PEMBAYARAN',
            trailing: TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add_rounded), label: const Text('Tambah'))),
        for (final m in _list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(payIcon(m), color: cs.primary),
                title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(m.isCash ? 'Tunai (ada kembalian)' : 'Non tunai'),
                onTap: () => _edit(m),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: m.active,
                      onChanged: (v) async {
                        if (!v && _list.where((e) => e.active).length <= 1) {
                          Notify.warning('Minimal 1 metode harus aktif');
                          return;
                        }
                        m.active = v;
                        await Repo.savePayMethod(m);
                        _load();
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'Hapus metode?', message: 'Hapus "${m.name}"?', okText: 'Hapus', danger: true);
                        if (!ok) return;
                        final err = await Repo.deletePayMethod(m.id!);
                        if (err != null) {
                          Notify.error(err);
                        } else {
                          Notify.success('Metode dihapus');
                        }
                        _load();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SectionTitle('GAMBAR QRIS'),
        Text('Upload foto/screenshot QRIS toko. Akan ditampilkan ke pelanggan saat memilih metode yang namanya mengandung "QRIS".',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 12),
        if (qris != null)
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              child: Image.memory(qris, height: 220),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FilledButton.tonalIcon(onPressed: _pickQris, icon: const Icon(Icons.qr_code_scanner_rounded), label: Text(qris == null ? 'Upload QRIS' : 'Ganti QRIS')),
            if (qris != null) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => app.set('qris_b64', ''),
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                label: Text('Hapus', style: TextStyle(color: cs.error)),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ======================= PRINTER =======================
class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  late final AppState app = context.read<AppState>();
  late final _chars = TextEditingController(text: app.get('pr_chars'));
  late final _dots = TextEditingController(text: app.get('pr_dots'));
  late final _chunk = TextEditingController(text: app.get('pr_chunk'));
  late final _delay = TextEditingController(text: app.get('pr_delay'));
  bool _scanning = false;

  @override
  void dispose() {
    for (final c in [_chars, _dots, _chunk, _delay]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choose() async {
    setState(() => _scanning = true);
    final list = await PrinterService.pairedDevices();
    if (!mounted) return;
    setState(() => _scanning = false);
    if (list.isEmpty) {
      Notify.info('Tidak ada perangkat ter-pair. Pair printer dulu di Pengaturan Bluetooth HP (PIN biasanya 0000 / 1234).');
      return;
    }
    final picked = await showModalBottomSheet<BtDevice>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Pilih Printer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            for (final d in list)
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text(d.name),
                subtitle: Text(d.address),
                trailing: d.address == app.get('pr_address') ? const Icon(Icons.check_circle_rounded, color: Colors.green) : null,
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await Native.btDisconnect();
    await app.setMany({'pr_address': picked.address, 'pr_name': picked.name});
    Notify.info('Menghubungkan ke ${picked.name}...');
    final ok = await Native.btConnect(picked.address);
    if (ok) {
      Notify.success('Terhubung ke ${picked.name}');
    } else {
      Notify.warning('Printer disimpan, tapi belum bisa terhubung. Pastikan printer menyala.');
    }
  }

  Future<void> _preset(int chars, int dots) async {
    _chars.text = '$chars';
    _dots.text = '$dots';
    await app.setMany({'pr_chars': '$chars', 'pr_dots': '$dots'});
    Notify.info('Preset diterapkan: $chars karakter, $dots dot');
  }

  Future<void> _saveNumbers() async {
    int clampI(String s, int min, int max, int def) {
      final v = int.tryParse(s.trim()) ?? def;
      return v < min ? min : (v > max ? max : v);
    }

    final chars = clampI(_chars.text, 16, 80, 32);
    final dots = clampI(_dots.text, 96, 832, 384);
    final chunk = clampI(_chunk.text, 16, 8192, 256);
    final delay = clampI(_delay.text, 0, 500, 20);
    _chars.text = '$chars';
    _dots.text = '$dots';
    _chunk.text = '$chunk';
    _delay.text = '$delay';
    await app.setMany({'pr_chars': '$chars', 'pr_dots': '$dots', 'pr_chunk': '$chunk', 'pr_delay': '$delay'});
    Notify.success('Pengaturan printer disimpan');
  }

  Widget _stepper(String label, String key, int min, int max, {String? sub}) {
    final v = app.i(key, min);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: sub == null ? null : Text(sub),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(onPressed: v > min ? () => app.set(key, '${v - 1}') : null, icon: const Icon(Icons.remove_rounded)),
          SizedBox(width: 36, child: Text('$v', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          IconButton.filledTonal(onPressed: v < max ? () => app.set(key, '${v + 1}') : null, icon: const Icon(Icons.add_rounded)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final addr = app.get('pr_address');
    final chars = app.i('pr_chars', 32);
    final dots = app.i('pr_dots', 384);
    String preset = 'custom';
    if (chars == 32 && dots == 384) preset = '58';
    if (chars == 48 && dots == 576) preset = '80';
    if (chars == 42 && dots == 384) preset = '58b';

    return _SettingsScaffold(
      title: 'Printer Bluetooth',
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.print_rounded, color: cs.onPrimaryContainer, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(addr.isEmpty ? 'Belum ada printer' : app.get('pr_name'),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                        Text(addr.isEmpty ? 'Pilih printer yang sudah di-pair' : addr, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _scanning ? null : _choose,
                    icon: _scanning
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.bluetooth_searching_rounded),
                    label: const Text('Pilih Printer'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: addr.isEmpty ? null : () => PrinterService.testPrint(app),
                    icon: const Icon(Icons.receipt_long_rounded),
                    label: const Text('Tes Cetak'),
                  ),
                  OutlinedButton.icon(
                    onPressed: addr.isEmpty
                        ? null
                        : () async {
                            await Native.btDisconnect();
                            Notify.info('Koneksi printer diputus');
                          },
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Putuskan'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SectionTitle('UKURAN KERTAS'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(label: const Text('58mm (32 huruf)'), selected: preset == '58', onSelected: (_) => _preset(32, 384)),
            ChoiceChip(label: const Text('58mm Font kecil (42)'), selected: preset == '58b', onSelected: (_) => _preset(42, 384)),
            ChoiceChip(label: const Text('80mm (48 huruf)'), selected: preset == '80', onSelected: (_) => _preset(48, 576)),
            ChoiceChip(label: const Text('Custom'), selected: preset == 'custom', onSelected: (_) {}),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chars,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDeco('Karakter per baris'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _dots,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDeco('Lebar cetak (dot)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Jika teks turun baris/terpotong, kecilkan "Karakter per baris". Gunakan Tes Cetak untuk mengecek.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(onPressed: _saveNumbers, icon: const Icon(Icons.save_rounded), label: const Text('Simpan Ukuran')),
        ),
        const SectionTitle('HASIL CETAK'),
        _switch(app, 'pr_auto', 'Cetak otomatis setelah bayar'),
        _stepper('Jumlah rangkap', 'pr_copies', 1, 3),
        _switch(app, 'pr_font_b', 'Gunakan font kecil (Font B)', sub: 'Atur karakter per baris ke 42 (58mm) / 64 (80mm)'),
        _switch(app, 'pr_margin_zero', 'Margin kiri 0 (mepet)', sub: 'Kirim perintah GS L 0'),
        _stepper('Baris kosong setelah cetak', 'pr_feed', 0, 8, sub: 'Kecil = struk lebih pendek/mepet'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Jarak antar baris'),
          subtitle: Text(app.i('pr_line_spacing') == 0 ? 'Bawaan printer' : '${app.i('pr_line_spacing')} dot (kecil = lebih rapat)'),
        ),
        Slider(
          value: app.i('pr_line_spacing').clamp(0, 60).toDouble(),
          min: 0,
          max: 60,
          divisions: 60,
          label: app.i('pr_line_spacing') == 0 ? 'Bawaan' : '${app.i('pr_line_spacing')}',
          onChanged: (v) => app.set('pr_line_spacing', '${v.round()}'),
        ),
        _switch(app, 'pr_cut', 'Potong kertas otomatis', sub: 'Hanya untuk printer dengan auto cutter'),
        _switch(app, 'pr_drawer', 'Buka laci uang (tunai)', sub: 'Jika laci kas tersambung ke printer'),
        const SectionTitle('LOGO'),
        DropdownButtonFormField<String>(
          value: ['raster', 'escstar', 'off'].contains(app.get('pr_logo_mode')) ? app.get('pr_logo_mode') : 'raster',
          decoration: inputDeco('Mode cetak logo', icon: Icons.image_rounded),
          items: const [
            DropdownMenuItem(value: 'raster', child: Text('Raster GS v 0 (umum)')),
            DropdownMenuItem(value: 'escstar', child: Text('Bit image ESC * (printer lama)')),
            DropdownMenuItem(value: 'off', child: Text('Tidak cetak logo')),
          ],
          onChanged: (v) => app.set('pr_logo_mode', v ?? 'raster'),
        ),
        const SizedBox(height: 8),
        ListTile(contentPadding: EdgeInsets.zero, title: const Text('Lebar logo'), trailing: Text('${app.i('pr_logo_percent', 60)}%')),
        Slider(
          value: app.i('pr_logo_percent', 60).clamp(20, 100).toDouble(),
          min: 20,
          max: 100,
          divisions: 16,
          label: '${app.i('pr_logo_percent', 60)}%',
          onChanged: (v) => app.set('pr_logo_percent', '${v.round()}'),
        ),
        _switch(app, 'pr_dither', 'Dithering (untuk logo foto/berwarna)'),
        Text('Jika logo tercetak berantakan/karakter aneh, ganti mode ke "Bit image ESC *" atau matikan logo.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SectionTitle('KOMPATIBILITAS (LANJUTAN)'),
        _switch(app, 'pr_init', 'Kirim reset printer (ESC @) di awal'),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chunk,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDeco('Ukuran paket (byte)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _delay,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: inputDeco('Jeda antar paket (ms)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Printer murah yang hasilnya terpotong/hilang di tengah: kecilkan ukuran paket (mis. 128) dan naikkan jeda (mis. 40-60 ms).',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.tonalIcon(onPressed: _saveNumbers, icon: const Icon(Icons.save_rounded), label: const Text('Simpan')),
        ),
        const SectionTitle('PRATINJAU STRUK'),
        ReceiptPreview(items: Receipts.sale(app, sampleSale()), chars: Receipts.chars(app)),
      ],
    );
  }
}

// ======================= TAMPILAN =======================
class DisplaySettingsPage extends StatelessWidget {
  const DisplaySettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    Widget seg<T>(String title, T value, List<(T, String, IconData)> opts, ValueChanged<T> onChanged) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<T>(
              segments: [for (final o in opts) ButtonSegment<T>(value: o.$1, label: Text(o.$2), icon: Icon(o.$3))],
              selected: {value},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(s.first),
            ),
            const SizedBox(height: 16),
          ],
        );
    final scales = [0.9, 1.0, 1.1, 1.2, 1.3];
    var scale = app.textScale;
    if (!scales.contains(scale)) scale = 1.0;

    return _SettingsScaffold(
      title: 'Tampilan',
      children: [
        const SectionTitle('MODE LAYAR'),
        seg<String>('Tata letak', app.get('ui_mode'), [
          ('auto', 'Otomatis', Icons.auto_awesome_rounded),
          ('phone', 'HP', Icons.smartphone_rounded),
          ('tablet', 'Tablet', Icons.tablet_android_rounded),
        ], (v) => app.set('ui_mode', v)),
        seg<String>('Orientasi', app.get('ui_orientation'), [
          ('auto', 'Bebas', Icons.screen_rotation_rounded),
          ('portrait', 'Tegak', Icons.stay_current_portrait_rounded),
          ('landscape', 'Mendatar', Icons.stay_current_landscape_rounded),
        ], (v) => app.set('ui_orientation', v)),
        seg<String>('Ukuran kartu menu', app.get('ui_card'), [
          ('s', 'Kecil', Icons.grid_on_rounded),
          ('m', 'Sedang', Icons.grid_view_rounded),
          ('l', 'Besar', Icons.view_module_rounded),
        ], (v) => app.set('ui_card', v)),
        _switch(app, 'ui_show_images', 'Tampilkan gambar menu di penjualan'),
        _switch(app, 'ui_haptic', 'Getar halus saat menekan menu'),
        const SectionTitle('UKURAN TEKS'),
        Wrap(
          spacing: 8,
          children: [
            for (final s in scales)
              ChoiceChip(
                label: Text('${(s * 100).round()}%'),
                selected: scale == s,
                onSelected: (_) => app.set('ui_text_scale', s.toString()),
              ),
          ],
        ),
        const SectionTitle('TEMA'),
        seg<String>('Mode warna', app.get('ui_dark'), [
          ('0', 'Terang', Icons.light_mode_rounded),
          ('1', 'Gelap', Icons.dark_mode_rounded),
          ('2', 'Sistem', Icons.brightness_auto_rounded),
        ], (v) => app.set('ui_dark', v)),
        const Text('Warna utama', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < AppState.seeds.length; i++)
              Tooltip(
                message: AppState.seeds[i].name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => app.set('ui_color', '$i'),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppState.seeds[i].color,
                      shape: BoxShape.circle,
                      border: Border.all(color: app.i('ui_color') == i ? cs.onSurface : Colors.transparent, width: 3),
                    ),
                    child: app.i('ui_color') == i ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ======================= PENGGUNA =======================
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  List<AppUser> _users = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await Repo.users();
    if (mounted) setState(() => _users = u);
  }

  Future<void> _edit([AppUser? u]) async {
    final name = TextEditingController(text: u?.name ?? '');
    final username = TextEditingController(text: u?.username ?? '');
    final pass = TextEditingController();
    var role = u?.role ?? 'kasir';
    var active = u?.active ?? true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(u == null ? 'Tambah Pengguna' : 'Ubah Pengguna'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, textCapitalization: TextCapitalization.words, decoration: inputDeco('Nama', icon: Icons.badge_outlined)),
                const SizedBox(height: 10),
                TextField(controller: username, decoration: inputDeco('Username (tanpa spasi)', icon: Icons.alternate_email_rounded)),
                const SizedBox(height: 10),
                TextField(
                  controller: pass,
                  obscureText: true,
                  decoration: inputDeco(u == null ? 'Password (min. 4)' : 'Password baru (kosongkan jika tetap)', icon: Icons.lock_outline_rounded),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'kasir', label: Text('Kasir'), icon: Icon(Icons.person_rounded)),
                    ButtonSegment(value: 'owner', label: Text('Owner'), icon: Icon(Icons.workspace_premium_rounded)),
                  ],
                  selected: {role},
                  onSelectionChanged: (s) => setD(() => role = s.first),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Aktif'),
                  value: active,
                  onChanged: (v) => setD(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final n = name.text, un = username.text, pw = pass.text;
    disposeLater(name);
    disposeLater(username);
    disposeLater(pass);
    if (ok != true) return;
    final err = await Repo.saveUser(id: u?.id, username: un, name: n, role: role, active: active, password: pw.isEmpty ? null : pw);
    if (err != null) {
      Notify.error(err);
      return;
    }
    Notify.success('Pengguna disimpan');
    if (!mounted) return;
    // perbarui sesi bila mengubah akun sendiri
    final app = context.read<AppState>();
    if (u != null && app.user?.id == u.id) {
      final list = await Repo.users();
      final me = list.where((e) => e.id == u.id);
      if (me.isNotEmpty) app.setUser(me.first);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return _SettingsScaffold(
      title: 'Pengguna & Hak Akses',
      children: [
        SectionTitle('DAFTAR PENGGUNA',
            trailing: TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Tambah'))),
        for (final u in _users)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onTap: () => _edit(u),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: u.isOwner ? Colors.amber.withOpacity(0.25) : cs.primaryContainer,
                  child: Icon(u.isOwner ? Icons.workspace_premium_rounded : Icons.person_rounded,
                      color: u.isOwner ? Colors.amber.shade800 : cs.onPrimaryContainer),
                ),
                title: Text(u.name, style: TextStyle(fontWeight: FontWeight.w700, decoration: u.active ? null : TextDecoration.lineThrough)),
                subtitle: Text('@${u.username} • ${u.isOwner ? 'Owner' : 'Kasir'}${u.active ? '' : ' • nonaktif'}'),
                trailing: u.id == app.user?.id
                    ? const Chip(label: Text('Anda'))
                    : IconButton(
                        icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                        onPressed: () async {
                          final ok = await confirmDialog(context, title: 'Hapus pengguna?', message: 'Hapus "${u.name}"?', okText: 'Hapus', danger: true);
                          if (!ok) return;
                          final err = await Repo.deleteUser(u.id);
                          if (err != null) {
                            Notify.error(err);
                          } else {
                            Notify.success('Pengguna dihapus');
                          }
                          _load();
                        },
                      ),
              ),
            ),
          ),
        const SectionTitle('HAK AKSES KASIR'),
        Text('Owner selalu bisa mengakses semua menu. Atur apa saja yang boleh diakses kasir:',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        _switch(app, 'perm_kasir_menu', 'Kelola menu & kategori'),
        _switch(app, 'perm_kasir_expense', 'Catat pengeluaran'),
        _switch(app, 'perm_kasir_report', 'Lihat laporan'),
        _switch(app, 'perm_kasir_discount', 'Memberi diskon'),
        const SizedBox(height: 6),
        Text('Hapus transaksi hanya bisa dilakukan oleh owner.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

// ======================= BACKUP & RESTORE =======================
class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  List<File> _files = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await BackupService.localBackups();
      if (mounted) setState(() => _files = f);
    } catch (_) {}
  }

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    final r = await BackupService.run(context.read<AppState>());
    await Activity.log('data', r.ok ? 'Backup manual' : 'Backup manual gagal', r.ok ? 'Slot ${r.slot}/3' : (r.error ?? ''));
    if (mounted) setState(() => _busy = false);
    if (r.ok) {
      Notify.success('Backup tersimpan ke slot ${r.slot}/3');
    } else {
      Notify.error('Backup gagal: ${r.error}');
    }
    _load();
  }

  Future<void> _share(File f) async {
    try {
      await Share.shareXFiles([XFile(f.path)], subject: 'Backup Kasir Rumah Makan');
    } catch (e) {
      Notify.error('Gagal membagikan: $e');
    }
  }

  Future<void> _restore(String path) async {
    final ok = await confirmDialog(
      context,
      title: 'Restore Data?',
      message: 'SEMUA data saat ini akan diganti dengan data dari file backup. Lanjutkan?',
      okText: 'Restore',
      danger: true,
      icon: Icons.restore_rounded,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final cart = context.read<CartState>();
    final who = app.user?.name ?? '';
    final err = await BackupService.restore(path);
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) {
      Notify.error(err);
      return;
    }
    Activity.user = who;
    await Activity.log('data', 'Restore data', path.split('/').last);
    await app.load();
    app.setUser(null);
    cart.clear();
    Notify.success('Restore berhasil. Silakan login kembali.');
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  Future<void> _restoreFromFile() async {
    try {
      final path = await Native.pickFile();
      if (path == null) return;
      await _restore(path);
    } catch (e) {
      Notify.error('Gagal membuka file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final last = DateTime.tryParse(app.get('backup_last_time'));
    return _SettingsScaffold(
      title: 'Backup & Restore',
      children: [
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.verified_user_rounded, color: cs.primary),
                const SizedBox(width: 8),
                const Text('Backup Otomatis', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
              const SizedBox(height: 8),
              const Text('Setiap login, data dibackup otomatis ke 3 file yang dipakai bergantian:\n'
                  'backup_kasir_rm_1.db → _2.db → _3.db → kembali ke _1.db (ditimpa).'),
              const SizedBox(height: 8),
              Text('Lokasi: folder Download/${BackupService.folderName}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              const SizedBox(height: 8),
              Text(last == null ? 'Belum pernah backup' : 'Terakhir: ${fmtDateTime(last)} (slot ${app.get('backup_last_slot')})',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (app.get('backup_last_file').isNotEmpty)
                Text(app.get('backup_last_file'), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _backupNow,
          icon: const Icon(Icons.backup_rounded),
          label: const Text('Backup Sekarang'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restoreFromFile,
          icon: const Icon(Icons.file_open_rounded),
          label: const Text('Restore dari File (.db)'),
        ),
        const SizedBox(height: 4),
        Text('Untuk pindah HP: bagikan file backup ke HP baru (WA/Drive), lalu pilih "Restore dari File".',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SectionTitle('FILE BACKUP DI HP INI'),
        if (_files.isEmpty) const Text('Belum ada file backup'),
        for (final f in _files)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SoftCard(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storage_rounded),
                title: Text(f.uri.pathSegments.isNotEmpty ? f.uri.pathSegments.last : f.path),
                subtitle: Text('${fmtDateTime(f.lastModifiedSync())} • ${(f.lengthSync() / 1024).toStringAsFixed(0)} KB'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'Bagikan', onPressed: () => _share(f), icon: const Icon(Icons.share_rounded)),
                    IconButton(tooltip: 'Restore', onPressed: _busy ? null : () => _restore(f.path), icon: const Icon(Icons.restore_rounded)),
                  ],
                ),
              ),
            ),
          ),
        if (_busy) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}

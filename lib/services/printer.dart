import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:permission_handler/permission_handler.dart';

import '../app_state.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import 'native.dart';

// ======================= ITEM CETAK =======================
abstract class PItem {}

class PText extends PItem {
  final String text;
  final bool bold;
  final bool big; // tinggi ganda
  final bool wide; // lebar ganda
  PText(this.text, {this.bold = false, this.big = false, this.wide = false});
}

class PLogo extends PItem {
  final Uint8List bytes;
  PLogo(this.bytes);
}

// ======================= FORMAT TEKS =======================
class TextFmt {
  final int w;
  TextFmt(this.w);

  static const Map<String, String> _map = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c', 'Á': 'A', 'É': 'E', 'Í': 'I',
    'Ó': 'O', 'Ú': 'U', 'Ñ': 'N', '‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-',
    '…': '...', '•': '*', '×': 'x', '·': '.', '\t': ' ',
  };

  /// Ubah ke ASCII aman (semua printer thermal mendukung ASCII)
  static String ascii(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (r >= 32 && r < 127) {
        b.write(ch);
      } else if (_map.containsKey(ch)) {
        b.write(_map[ch]);
      } else if (r == 10 || r == 13) {
        b.write(' ');
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  String sep([String c = '-']) => c * w;

  String center(String t, [int? width]) {
    final ww = width ?? w;
    t = t.trim();
    if (t.length >= ww) return t.substring(0, ww);
    final pad = (ww - t.length) ~/ 2;
    return ' ' * pad + t;
  }

  String lr(String l, String r, [int? width]) {
    final ww = width ?? w;
    if (r.length >= ww) return r.substring(0, ww);
    final maxL = ww - r.length - 1;
    if (l.length > maxL) l = l.substring(0, maxL < 0 ? 0 : maxL);
    return l + ' ' * (ww - l.length - r.length) + r;
  }

  String kv(String k, String v, [int keyWidth = 6]) => '${k.padRight(keyWidth)}: $v';

  List<String> wrap(String text, [int? width]) {
    final ww = width ?? w;
    final res = <String>[];
    for (final para in text.split('\n')) {
      var line = '';
      for (var word in para.split(' ')) {
        if (word.isEmpty) continue;
        while (word.length > ww) {
          if (line.isNotEmpty) {
            res.add(line);
            line = '';
          }
          res.add(word.substring(0, ww));
          word = word.substring(ww);
        }
        if (line.isEmpty) {
          line = word;
        } else if (line.length + 1 + word.length <= ww) {
          line = '$line $word';
        } else {
          res.add(line);
          line = word;
        }
      }
      if (line.isNotEmpty) res.add(line);
    }
    return res;
  }
}

// ======================= KOMPOSISI STRUK =======================
class Receipts {
  /// Printer thermal 58mm: 32 karakter per baris (Font A standar)
  static const int kChars58 = 32;

  static int chars(AppState app) => kChars58;

  static List<PItem> header(AppState app) {
    final w = chars(app);
    final f = TextFmt(w);
    final out = <PItem>[];
    final logo = app.logo;
    if (app.b('rc_show_logo') && logo != null) out.add(PLogo(logo));
    final name = TextFmt.ascii(app.get('store_name')).trim();
    if (app.b('rc_show_name') && name.isNotEmpty) {
      final big = app.b('rc_title_big');
      final wide = app.b('rc_title_wide');
      final tw = wide ? w ~/ 2 : w;
      for (final l in f.wrap(name, tw)) {
        out.add(PText(f.center(l, tw), bold: true, big: big, wide: wide));
      }
    }
    final addr = TextFmt.ascii(app.get('store_address')).trim();
    if (app.b('rc_show_address') && addr.isNotEmpty) {
      for (final l in f.wrap(addr)) {
        out.add(PText(f.center(l)));
      }
    }
    final phone = TextFmt.ascii(app.get('store_phone')).trim();
    if (app.b('rc_show_phone') && phone.isNotEmpty) out.add(PText(f.center('Telp: $phone')));
    final hdr = TextFmt.ascii(app.get('receipt_header')).trim();
    if (hdr.isNotEmpty) {
      for (final l in f.wrap(hdr)) {
        out.add(PText(f.center(l)));
      }
    }
    return out;
  }

  static List<PItem> sale(AppState app, Sale s, {bool reprint = false}) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = header(app);
    out.add(PText(f.sep()));
    out.add(PText(f.kv('No', s.invoiceNo)));
    out.add(PText(f.kv('Tgl', '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)}')));
    if (app.b('rc_show_cashier') && s.userName.isNotEmpty) out.add(PText(f.kv('Kasir', a(s.userName))));
    if (app.b('rc_show_customer')) {
      if (s.customer.trim().isNotEmpty) {
        for (final l in f.wrap(f.kv('Nama', a(s.customer.trim())))) {
          out.add(PText(l));
        }
      }
      if (s.orderType.isNotEmpty) out.add(PText(f.kv('Tipe', a(s.orderType))));
    }
    if (reprint) out.add(PText(f.center('** CETAK ULANG **')));
    if (s.isVoid) out.add(PText(f.center('*** DIBATALKAN ***'), bold: true));
    out.add(PText(f.sep()));
    for (final it in s.items) {
      for (final l in f.wrap(a(it.name))) {
        out.add(PText(l));
      }
      out.add(PText(f.lr('  ${it.qty} x ${nf(it.price)}', nf(it.subtotal))));
      if (app.b('rc_show_note') && it.note.trim().isNotEmpty) {
        for (final l in f.wrap('  * ${a(it.note.trim())}')) {
          out.add(PText(l));
        }
      }
    }
    out.add(PText(f.sep()));
    out.add(PText(f.lr('Subtotal', nf(s.subtotal))));
    if (s.discount > 0) out.add(PText(f.lr('Diskon', '-${nf(s.discount)}')));
    if (s.service > 0) out.add(PText(f.lr('Service', nf(s.service))));
    if (s.tax > 0) out.add(PText(f.lr('Pajak', nf(s.tax))));
    final boldTotal = app.b('pr_bold_total');
    out.add(PText(f.lr('TOTAL', nf(s.total)), bold: true, big: boldTotal));
    out.add(PText(f.lr(a(s.paymentMethod.isEmpty ? 'Bayar' : s.paymentMethod), nf(s.paid))));
    if (s.isCash) out.add(PText(f.lr('Kembali', nf(s.change))));
    if (s.reference.trim().isNotEmpty) out.add(PText(f.lr('Ref', a(s.reference.trim()))));
    final footer = a(app.get('receipt_footer')).trim();
    if (footer.isNotEmpty) {
      out.add(PText(f.sep()));
      for (final line in footer.split('\n')) {
        for (final l in f.wrap(line)) {
          out.add(PText(f.center(l)));
        }
      }
    }
    return out;
  }

  static List<PItem> testPage(AppState app) {
    final w = chars(app);
    final f = TextFmt(w);
    final out = header(app);
    out.add(PText(f.sep()));
    out.add(PText(f.center('TES PRINTER', w), bold: true));
    final ruler = StringBuffer();
    for (var i = 1; i <= w; i++) {
      ruler.write(i % 10);
    }
    out.add(PText(ruler.toString()));
    out.add(PText(f.lr('Kiri', 'Kanan')));
    out.add(PText(f.lr('Nasi Goreng', nf(18000))));
    out.add(PText('Teks tebal', bold: true));
    out.add(PText('Teks tinggi', big: true));
    out.add(PText(f.sep()));
    out.add(PText('Lebar: $w karakter'));
    for (final l in f.wrap('Jika deretan angka di atas pas 1 baris (tidak turun), setelan lebar sudah benar.')) {
      out.add(PText(l));
    }
    out.add(PText(f.sep()));
    out.add(PText(f.center(fmtDateTime(DateTime.now()))));
    return out;
  }

  /// Laporan penjualan (harian / periode) untuk dicetak di printer thermal
  static List<PItem> recap(AppState app, ReportData d, String printedBy, {List<Sale>? sales}) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final out = <PItem>[];
    final name = a(app.get('store_name')).trim();
    if (name.isNotEmpty) {
      for (final l in f.wrap(name)) {
        out.add(PText(f.center(l), bold: true));
      }
    }
    final daily = dbDay(d.from) == dbDay(d.to);
    out.add(PText(f.center(daily ? 'LAPORAN PENJUALAN HARIAN' : 'LAPORAN PENJUALAN'), bold: true));
    out.add(PText(f.center(daily
        ? a(fmtDayName(d.from))
        : '${fmtDateShort(d.from)} - ${fmtDateShort(d.to)}')));
    out.add(PText(f.sep()));
    out.add(PText(f.lr('Jumlah transaksi', nf(d.trxCount))));
    out.add(PText(f.lr('Penjualan kotor', nf(d.gross))));
    if (d.discount > 0) out.add(PText(f.lr('Diskon', '-${nf(d.discount)}')));
    if (d.service > 0) out.add(PText(f.lr('Service', nf(d.service))));
    if (d.tax > 0) out.add(PText(f.lr('Pajak', nf(d.tax))));
    out.add(PText(f.lr('TOTAL PENJUALAN', nf(d.total)), bold: true));
    out.add(PText(f.lr('Rata-rata/transaksi', nf(d.average))));
    out.add(PText(f.sep()));
    out.add(PText('Per metode bayar:', bold: true));
    if (d.byMethod.isEmpty) out.add(PText('  -'));
    for (final m in d.byMethod) {
      out.add(PText(f.lr('${a(m.name)} (${m.count})', nf(m.total))));
    }
    if (d.byCashier.isNotEmpty) {
      out.add(PText(f.sep()));
      out.add(PText('Per kasir:', bold: true));
      for (final c in d.byCashier) {
        out.add(PText(f.lr('${a(c.name)} (${c.count})', nf(c.total))));
      }
    }
    out.add(PText(f.sep()));
    out.add(PText('Pengeluaran:', bold: true));
    if (d.expenseByCat.isEmpty) out.add(PText('  -'));
    for (final e in d.expenseByCat) {
      out.add(PText(f.lr('  ${a(e.name)}', nf(e.total))));
    }
    out.add(PText(f.lr('Total pengeluaran', nf(d.expense))));
    out.add(PText(f.sep()));
    final cashIn = d.byMethod
        .where((m) => m.name.toLowerCase().contains('tunai') || m.name.toLowerCase().contains('cash'))
        .fold<int>(0, (s, m) => s + m.total);
    out.add(PText(f.lr('Penjualan tunai', nf(cashIn))));
    out.add(PText(f.lr('Penjualan - Pengeluaran', nf(d.net)), bold: true));
    if (d.topItems.isNotEmpty) {
      out.add(PText(f.sep()));
      out.add(PText(f.lr('Menu terjual', 'Qty'), bold: true));
      for (final t in d.topItems) {
        final qty = '${t.qty}';
        final lines = f.wrap(a(t.name), w - qty.length - 1);
        for (var i = 0; i < lines.length; i++) {
          out.add(PText(i == lines.length - 1 ? f.lr(lines[i], qty) : lines[i]));
        }
      }
    }
    if (sales != null && sales.isNotEmpty) {
      out.add(PText(f.sep()));
      out.add(PText('Daftar transaksi:', bold: true));
      for (final s in sales.reversed) {
        final left = daily ? '${fmtTime(s.createdAt)} ${s.invoiceNo}' : '${fmtDateShort(s.createdAt)} ${s.invoiceNo}';
        out.add(PText(f.lr(left, nf(s.total))));
      }
    }
    out.add(PText(f.sep()));
    out.add(PText('Dicetak: ${fmtDateShort(DateTime.now())} ${fmtTime(DateTime.now())}'));
    out.add(PText('Oleh   : ${a(printedBy)}'));
    return out;
  }

  /// Laporan laba rugi untuk printer thermal 58mm
  static List<PItem> profitLoss(AppState app, ReportData d, String printedBy) {
    final w = chars(app);
    final f = TextFmt(w);
    const a = TextFmt.ascii;
    final pl = ProfitLoss.from(d, app.hppCategories);
    final out = <PItem>[];
    final name = a(app.get('store_name')).trim();
    if (name.isNotEmpty) {
      for (final l in f.wrap(name)) {
        out.add(PText(f.center(l), bold: true));
      }
    }
    out.add(PText(f.center('LAPORAN LABA RUGI'), bold: true));
    out.add(PText(f.center(dbDay(d.from) == dbDay(d.to)
        ? a(fmtDayName(d.from))
        : '${fmtDateShort(d.from)} - ${fmtDateShort(d.to)}')));
    out.add(PText(f.sep()));
    out.add(PText('PENDAPATAN', bold: true));
    out.add(PText(f.lr('Penjualan kotor', nf(pl.gross))));
    if (pl.discount > 0) out.add(PText(f.lr('Diskon', '-${nf(pl.discount)}')));
    if (pl.service > 0) out.add(PText(f.lr('Service', nf(pl.service))));
    out.add(PText(f.lr('Pendapatan bersih', nf(pl.revenue)), bold: true));
    out.add(PText(f.sep()));
    out.add(PText('HPP (bahan baku)', bold: true));
    if (pl.hppItems.isEmpty) out.add(PText('  -'));
    for (final e in pl.hppItems) {
      out.add(PText(f.lr('  ${a(e.name)}', nf(e.total))));
    }
    out.add(PText(f.lr('Total HPP', nf(pl.hpp))));
    out.add(PText(f.lr('LABA KOTOR', nf(pl.grossProfit)), bold: true));
    out.add(PText(f.sep()));
    out.add(PText('BEBAN OPERASIONAL', bold: true));
    if (pl.opexItems.isEmpty) out.add(PText('  -'));
    for (final e in pl.opexItems) {
      out.add(PText(f.lr('  ${a(e.name)}', nf(e.total))));
    }
    out.add(PText(f.lr('Total beban', nf(pl.opex))));
    out.add(PText(f.sep('=')));
    out.add(PText(f.lr(pl.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', nf(pl.net)), bold: true, big: true));
    out.add(PText(f.lr('Margin', '${pl.margin.toStringAsFixed(1)}%')));
    if (pl.tax > 0) {
      out.add(PText(f.sep()));
      out.add(PText(f.lr('Pajak dipungut*', nf(pl.tax))));
      for (final l in f.wrap('*Pajak titipan pelanggan, tidak dihitung sebagai pendapatan.')) {
        out.add(PText(l));
      }
    }
    out.add(PText(f.sep()));
    out.add(PText('Dicetak: ${fmtDateShort(DateTime.now())} ${fmtTime(DateTime.now())}'));
    out.add(PText('Oleh   : ${a(printedBy)}'));
    return out;
  }
}

// ======================= ENCODER ESC/POS =======================
class EscPos {
  static Future<Uint8List> encode(AppState app, List<PItem> items, {bool drawer = false}) async {
    // Khusus printer thermal 58mm (384 dot, 32 karakter, Font A)
    final bytes = <int>[];
    bytes.addAll([0x1B, 0x40]); // ESC @ reset
    bytes.addAll([0x1D, 0x4C, 0x00, 0x00]); // GS L 0 -> margin kiri 0 (mepet)
    const baseMode = 0x00;
    for (final it in items) {
      if (it is PText) {
        var mode = baseMode;
        if (it.bold) mode |= 0x08;
        if (it.big) mode |= 0x10;
        if (it.wide) mode |= 0x20;
        bytes.addAll([0x1B, 0x21, mode]);
        if (it.bold) bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(TextFmt.ascii(it.text).codeUnits);
        bytes.add(0x0A);
        if (it.bold) bytes.addAll([0x1B, 0x45, 0x00]);
        if (mode != baseMode) bytes.addAll([0x1B, 0x21, baseMode]);
      } else if (it is PLogo) {
        try {
          bytes.addAll(await _logo(app, it.bytes));
        } catch (_) {
          // logo gagal diproses -> lewati
        }
      }
    }
    bytes.addAll([0x1B, 0x21, 0x00]);
    final feed = app.i('pr_feed', 3);
    for (var i = 0; i < feed && i < 8; i++) {
      bytes.add(0x0A);
    }
    return Uint8List.fromList(bytes);
  }

  /// Lebar cetak printer 58mm = 384 dot
  static int paperDots(AppState app) => 384;

  static Future<List<int>> _logo(AppState app, Uint8List src) async {
    final paper = paperDots(app);
    var pct = app.i('pr_logo_percent', 60);
    if (pct < 10) pct = 10;
    if (pct > 100) pct = 100;
    final targetW = (paper * pct / 100).round();
    const maxH = 260;

    ui.Codec codec = await ui.instantiateImageCodec(src, targetWidth: targetW);
    ui.Image img = (await codec.getNextFrame()).image;
    if (img.height > maxH) {
      img.dispose();
      codec = await ui.instantiateImageCodec(src, targetHeight: maxH);
      img = (await codec.getNextFrame()).image;
    }
    final w = img.width > paper ? paper : img.width;
    final h = img.height;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final imgW = img.width;
    img.dispose();
    if (bd == null || w <= 0 || h <= 0) return const [];

    // luminance dengan latar putih untuk transparansi
    final lum = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * imgW + x) * 4;
        final r = bd.getUint8(o), g = bd.getUint8(o + 1), b = bd.getUint8(o + 2), a = bd.getUint8(o + 3);
        final l = 0.299 * r + 0.587 * g + 0.114 * b;
        final alpha = a / 255.0;
        lum[y * w + x] = l * alpha + 255 * (1 - alpha);
      }
    }
    final black = Uint8List(paper * h);
    final offset = (paper - w) ~/ 2;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (lum[i] < 128) black[y * paper + x + offset] = 1;
      }
    }

    final out = <int>[];
    // GS v 0 raster, dikirim per 24 baris agar aman untuk buffer kecil
    final wb = (paper + 7) ~/ 8;
    for (var y0 = 0; y0 < h; y0 += 24) {
      final bandH = (h - y0) < 24 ? (h - y0) : 24;
      out.addAll([0x1D, 0x76, 0x30, 0x00, wb & 0xFF, (wb >> 8) & 0xFF, bandH & 0xFF, (bandH >> 8) & 0xFF]);
      for (var y = y0; y < y0 + bandH; y++) {
        for (var xb = 0; xb < wb; xb++) {
          var byte = 0;
          for (var bit = 0; bit < 8; bit++) {
            final x = xb * 8 + bit;
            if (x < paper && black[y * paper + x] == 1) byte |= (0x80 >> bit);
          }
          out.add(byte);
        }
      }
    }
    return out;
  }
}

// ======================= LAYANAN PRINTER =======================
class PrinterService {
  static bool _busy = false;

  static Future<bool> ensurePermission() async {
    final sdk = await Native.sdkInt();
    if (sdk >= 31) {
      final st = await Permission.bluetoothConnect.request();
      if (!st.isGranted) {
        Notify.error('Izin Bluetooth ditolak. Aktifkan di Pengaturan HP > Aplikasi > Izin.');
        if (st.isPermanentlyDenied) await openAppSettings();
        return false;
      }
    }
    return true;
  }

  static Future<List<BtDevice>> pairedDevices() async {
    if (!await ensurePermission()) return [];
    if (!await Native.btEnabled()) {
      Notify.warning('Bluetooth belum aktif. Nyalakan Bluetooth terlebih dahulu.');
      return [];
    }
    try {
      return await Native.btPaired();
    } catch (e) {
      Notify.error('Gagal membaca perangkat: $e');
      return [];
    }
  }

  static Future<bool> printItems(AppState app, List<PItem> items, {int? copies, bool drawer = false, bool silent = false}) async {
    if (_busy) {
      Notify.info('Printer sedang mencetak...');
      return false;
    }
    final addr = app.get('pr_address');
    if (addr.isEmpty) {
      Notify.warning('Printer belum dipilih. Atur di Pengaturan > Printer.');
      return false;
    }
    _busy = true;
    try {
      if (!await ensurePermission()) return false;
      if (!await Native.btEnabled()) {
        Notify.warning('Bluetooth belum aktif.');
        return false;
      }
      final data = await EscPos.encode(app, items);
      const chunk = 256;
      const delay = 20;
      var connected = await Native.btIsConnected(addr);
      if (!connected) connected = await Native.btConnect(addr);
      if (!connected) {
        Notify.error('Tidak bisa terhubung ke printer. Pastikan printer menyala & sudah di-pair.');
        return false;
      }
      var n = copies ?? app.i('pr_copies', 1);
      if (n < 1) n = 1;
      if (n > 3) n = 3;
      for (var c = 0; c < n; c++) {
        var ok = await Native.btWrite(data, chunk: chunk, delay: delay);
        if (!ok) {
          // coba sambung ulang sekali
          if (await Native.btConnect(addr)) ok = await Native.btWrite(data, chunk: chunk, delay: delay);
        }
        if (!ok) {
          Notify.error('Gagal mengirim data ke printer.');
          return false;
        }
        if (c < n - 1) await Future.delayed(const Duration(milliseconds: 1200));
      }
      if (!silent) Notify.success('Struk berhasil dicetak');
      return true;
    } catch (e) {
      Notify.error('Error printer: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  static Future<bool> printSale(AppState app, Sale s, {bool reprint = false}) {
    return printItems(app, Receipts.sale(app, s, reprint: reprint));
  }

  static Future<bool> testPrint(AppState app) => printItems(app, Receipts.testPage(app), copies: 1);

  /// Teks pratinjau struk (untuk layar)
  static String preview(List<PItem> items) {
    final b = StringBuffer();
    for (final it in items) {
      if (it is PText) {
        b.writeln(TextFmt.ascii(it.text));
      } else if (it is PLogo) {
        b.writeln('[LOGO]');
      }
    }
    return b.toString();
  }
}

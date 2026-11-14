import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import 'native.dart';
import 'printer.dart' show TextFmt;

class _ReportBundle {
  final ReportData d;
  final List<Sale> sales;
  final List<Expense> expenses;
  _ReportBundle(this.d, this.sales, this.expenses);
}

/// Export laporan ke PDF & Excel (XLSX)
class ReportExport {
  static const String pdfMime = 'application/pdf';
  static const String xlsxMime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  static Future<_ReportBundle> _load(DateTime from, DateTime to) async {
    final d = await Repo.report(from, to);
    final s = (await Repo.salesWithItems(from, to)).where((e) => !e.isVoid).toList();
    final e = await Repo.expenses(from, to);
    return _ReportBundle(d, s, e);
  }

  static String _period(DateTime from, DateTime to) =>
      dbDay(from) == dbDay(to) ? fmtDayName(from) : '${fmtDate(from)} s/d ${fmtDate(to)}';

  static String _items(Sale s) => s.items.map((e) => '${e.qty}x ${e.name}').join(', ');

  static Future<void> export(AppState app, DateTime from, DateTime to, {required bool pdf}) async {
    try {
      Notify.info('Menyiapkan file ${pdf ? 'PDF' : 'Excel'}...');
      final data = await _load(from, to);
      Uint8List bytes;
      if (pdf) {
        try {
          bytes = await _buildPdf(app, data);
        } catch (_) {
          // logo tidak bisa dibaca -> buat ulang tanpa logo
          bytes = await _buildPdf(app, data, withLogo: false);
        }
      } else {
        bytes = _buildXlsx(app, data);
      }
      final store = app.get('store_name').replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
      final period = dbDay(from) == dbDay(to) ? dbDay(from) : '${dbDay(from)}_sd_${dbDay(to)}';
      final name = 'Laporan_${store.isEmpty ? 'Penjualan' : store}_$period.${pdf ? 'pdf' : 'xlsx'}';
      final mime = pdf ? pdfMime : xlsxMime;
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, name));
      await f.writeAsBytes(bytes, flush: true);

      String? saved;
      try {
        final sdk = await Native.sdkInt();
        var allowed = true;
        if (sdk > 0 && sdk < 29) allowed = (await Permission.storage.request()).isGranted;
        if (allowed) saved = await Native.saveToDownloads(f.path, name, folder: 'KasirRumahMakan/Laporan', mime: mime);
      } catch (_) {
        saved = null;
      }
      await Activity.log('data', 'Export laporan ${pdf ? 'PDF' : 'Excel'}', '${dbDay(from)} s/d ${dbDay(to)}');
      if (saved != null) Notify.success('Tersimpan di Download/KasirRumahMakan/Laporan');
      await Share.shareXFiles([XFile(f.path, mimeType: mime, name: name)], subject: 'Laporan ${_period(from, to)}');
    } catch (e) {
      Notify.error('Gagal export: $e');
    }
  }

  // ======================= PDF =======================
  static Future<Uint8List> _buildPdf(AppState app, _ReportBundle x, {bool withLogo = true}) async {
    final a = TextFmt.ascii;
    final d = x.d;
    final storeName = a(app.get('store_name'));
    final doc = pw.Document(title: 'Laporan Penjualan', author: storeName);
    pw.MemoryImage? logo;
    final lb = withLogo ? app.logo : null;
    if (lb != null) {
      try {
        logo = pw.MemoryImage(lb);
      } catch (_) {
        logo = null;
      }
    }
    final logoImg = logo;
    final primary = PdfColor.fromInt(app.seedColor.value);
    final now = DateTime.now();

    pw.Widget table(List<String> headers, List<List<String>> rows, {Set<int> right = const {}, List<double>? flex}) {
      final align = <int, pw.Alignment>{
        for (var i = 0; i < headers.length; i++) i: right.contains(i) ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
      };
      return pw.TableHelper.fromTextArray(
        headers: headers.map(a).toList(),
        data: rows.map((r) => r.map(a).toList()).toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
        headerDecoration: pw.BoxDecoration(color: primary),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        cellHeight: 16,
        cellAlignments: align,
        headerAlignments: align,
        oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
        columnWidths: flex == null ? null : {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
      );
    }

    pw.Widget title(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(a(t), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: primary)),
        );

    pw.Widget box(String label, String value, PdfColor color) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(a(label), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                pw.SizedBox(height: 3),
                pw.Text(a(value), style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color)),
              ],
            ),
          ),
        );

    final totalExpense = x.expenses.fold<int>(0, (s, e) => s + e.amount);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 32),
        footer: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(a('Dicetak ${fmtDateTime(now)} oleh ${app.user?.name ?? '-'}'),
                style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
            pw.Text('Hal ${ctx.pageNumber}/${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
          ],
        ),
        build: (ctx) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logoImg != null)
                pw.Container(width: 48, height: 48, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(logoImg, fit: pw.BoxFit.contain)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(storeName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    if (app.get('store_address').isNotEmpty)
                      pw.Text(a(app.get('store_address')), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                    if (app.get('store_phone').isNotEmpty)
                      pw.Text(a('Telp: ${app.get('store_phone')}'), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('LAPORAN PENJUALAN', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary)),
                  pw.Text(a(_period(d.from, d.to)), style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey400),
          pw.Row(children: [
            box('Total Penjualan', rp(d.total), primary),
            box('Jumlah Transaksi', nf(d.trxCount), PdfColors.indigo),
            box('Pengeluaran', rp(d.expense), PdfColors.red700),
            box('Penjualan - Pengeluaran', rp(d.net), d.net >= 0 ? PdfColors.green700 : PdfColors.red700),
          ]),
          title('Ringkasan'),
          table(
            ['Keterangan', 'Nilai'],
            [
              ['Penjualan kotor (subtotal)', rp(d.gross)],
              ['Diskon', rp(d.discount)],
              ['Service', rp(d.service)],
              ['Pajak', rp(d.tax)],
              ['Total penjualan', rp(d.total)],
              ['Rata-rata per transaksi', rp(d.average)],
              ['Total pengeluaran', rp(d.expense)],
            ],
            right: {1},
            flex: [3, 2],
          ),
          title('Per Metode Pembayaran'),
          table(['Metode', 'Transaksi', 'Total'], [for (final m in d.byMethod) [m.name, nf(m.count), rp(m.total)]],
              right: {1, 2}, flex: [3, 1, 2]),
          title('Per Kasir'),
          table(['Kasir', 'Transaksi', 'Total'], [for (final c in d.byCashier) [c.name, nf(c.count), rp(c.total)]],
              right: {1, 2}, flex: [3, 1, 2]),
          title('Menu Terjual'),
          table(['No', 'Menu', 'Qty', 'Total'],
              [for (var i = 0; i < d.topItems.length; i++) ['${i + 1}', d.topItems[i].name, nf(d.topItems[i].qty), rp(d.topItems[i].total)]],
              right: {0, 2, 3}, flex: [0.5, 4, 1, 2]),
          title('Daftar Transaksi'),
          table(
            ['No Nota', 'Waktu', 'Kasir', 'Pelanggan', 'Metode', 'Item', 'Total'],
            [
              for (final s in x.sales)
                [s.invoiceNo, '${fmtDateShort(s.createdAt)} ${fmtTime(s.createdAt)}', s.userName, s.customer, s.paymentMethod, _items(s), rp(s.total)],
            ],
            right: {6},
            flex: [2.2, 1.7, 1.3, 1.4, 1.3, 4, 1.6],
          ),
          title('Pengeluaran'),
          table(
            ['Tanggal', 'Kategori', 'Keterangan', 'Metode', 'Oleh', 'Nominal'],
            [
              for (final e in x.expenses) [fmtDateShort(e.date), e.category, e.description, e.method, e.userName, rp(e.amount)],
              if (x.expenses.isNotEmpty) ['', '', 'TOTAL', '', '', rp(totalExpense)],
            ],
            right: {5},
            flex: [1.2, 1.6, 3, 1.2, 1.2, 1.6],
          ),
        ],
      ),
    );
    return doc.save();
  }

  // ======================= XLSX =======================
  static Uint8List _buildXlsx(AppState app, _ReportBundle x) {
    final d = x.d;
    final wb = XlsxBuilder();

    final s1 = wb.sheet('Ringkasan', [32, 16, 18]);
    s1.row([XC.title('LAPORAN PENJUALAN')]);
    s1.row([XC.bold(app.get('store_name'))]);
    s1.row([XC.text('Periode: ${_period(d.from, d.to)}')]);
    s1.row([XC.text('Dicetak: ${fmtDateTime(DateTime.now())} oleh ${app.user?.name ?? '-'}')]);
    s1.row([]);
    s1.row([XC.header('Keterangan'), XC.header(''), XC.header('Nilai')]);
    void kv(String k, int v, {bool bold = false}) =>
        s1.row([bold ? XC.bold(k) : XC.text(k), XC.empty, bold ? XC.numberBold(v) : XC.number(v)]);
    kv('Jumlah transaksi', d.trxCount);
    kv('Penjualan kotor (subtotal)', d.gross);
    kv('Diskon', d.discount);
    kv('Service', d.service);
    kv('Pajak', d.tax);
    kv('Total penjualan', d.total, bold: true);
    kv('Rata-rata per transaksi', d.average);
    kv('Total pengeluaran', d.expense);
    kv('Penjualan - Pengeluaran', d.net, bold: true);
    s1.row([]);
    s1.row([XC.header('Metode Pembayaran'), XC.header('Transaksi'), XC.header('Total')]);
    for (final m in d.byMethod) {
      s1.row([XC.text(m.name), XC.number(m.count), XC.number(m.total)]);
    }
    s1.row([]);
    s1.row([XC.header('Kasir'), XC.header('Transaksi'), XC.header('Total')]);
    for (final c in d.byCashier) {
      s1.row([XC.text(c.name), XC.number(c.count), XC.number(c.total)]);
    }
    s1.row([]);
    s1.row([XC.header('Kategori Pengeluaran'), XC.header('Jumlah'), XC.header('Total')]);
    for (final e in d.expenseByCat) {
      s1.row([XC.text(e.name), XC.number(e.count), XC.number(e.total)]);
    }

    final s2 = wb.sheet('Transaksi', [18, 12, 8, 14, 18, 14, 12, 10, 10, 10, 13, 13, 12, 50]);
    s2.row([
      for (final h in ['No Nota', 'Tanggal', 'Jam', 'Kasir', 'Pelanggan', 'Metode', 'Subtotal', 'Diskon', 'Service', 'Pajak', 'Total', 'Dibayar', 'Kembali', 'Item'])
        XC.header(h),
    ]);
    for (final s in x.sales) {
      s2.row([
        XC.text(s.invoiceNo),
        XC.text(dbDay(s.createdAt)),
        XC.text(fmtTime(s.createdAt)),
        XC.text(s.userName),
        XC.text(s.customer),
        XC.text(s.paymentMethod),
        XC.number(s.subtotal),
        XC.number(s.discount),
        XC.number(s.service),
        XC.number(s.tax),
        XC.number(s.total),
        XC.number(s.paid),
        XC.number(s.change),
        XC.text(_items(s)),
      ]);
    }
    if (x.sales.isNotEmpty) {
      int sum(int Function(Sale) f) => x.sales.fold(0, (a, s) => a + f(s));
      s2.row([
        XC.bold('TOTAL'), XC.empty, XC.empty, XC.empty, XC.empty, XC.empty,
        XC.numberBold(sum((s) => s.subtotal)),
        XC.numberBold(sum((s) => s.discount)),
        XC.numberBold(sum((s) => s.service)),
        XC.numberBold(sum((s) => s.tax)),
        XC.numberBold(sum((s) => s.total)),
      ]);
    }

    final s3 = wb.sheet('Detail Item', [18, 12, 8, 30, 8, 12, 13, 24]);
    s3.row([for (final h in ['No Nota', 'Tanggal', 'Jam', 'Menu', 'Qty', 'Harga', 'Subtotal', 'Catatan']) XC.header(h)]);
    for (final s in x.sales) {
      for (final it in s.items) {
        s3.row([
          XC.text(s.invoiceNo),
          XC.text(dbDay(s.createdAt)),
          XC.text(fmtTime(s.createdAt)),
          XC.text(it.name),
          XC.number(it.qty),
          XC.number(it.price),
          XC.number(it.subtotal),
          XC.text(it.note),
        ]);
      }
    }

    final s4 = wb.sheet('Menu Terlaris', [6, 32, 10, 15]);
    s4.row([for (final h in ['No', 'Menu', 'Qty', 'Total']) XC.header(h)]);
    for (var i = 0; i < d.topItems.length; i++) {
      final t = d.topItems[i];
      s4.row([XC.number(i + 1), XC.text(t.name), XC.number(t.qty), XC.number(t.total)]);
    }

    final s5 = wb.sheet('Pengeluaran', [12, 18, 36, 12, 15, 16]);
    s5.row([for (final h in ['Tanggal', 'Kategori', 'Keterangan', 'Metode', 'Nominal', 'Dicatat oleh']) XC.header(h)]);
    for (final e in x.expenses) {
      s5.row([XC.text(dbDay(e.date)), XC.text(e.category), XC.text(e.description), XC.text(e.method), XC.number(e.amount), XC.text(e.userName)]);
    }
    if (x.expenses.isNotEmpty) {
      s5.row([XC.bold('TOTAL'), XC.empty, XC.empty, XC.empty, XC.numberBold(x.expenses.fold<int>(0, (a, e) => a + e.amount))]);
    }
    return wb.build();
  }
}

// ======================= PENULIS XLSX SEDERHANA =======================
/// Sel Excel. style: 0 normal, 1 header, 2 angka, 3 angka tebal, 4 judul, 5 teks tebal
class XC {
  final Object? value;
  final int style;
  const XC(this.value, this.style);

  static const XC empty = XC(null, 0);
  static XC text(String v) => XC(v, 0);
  static XC header(String v) => XC(v, 1);
  static XC number(num v) => XC(v, 2);
  static XC numberBold(num v) => XC(v, 3);
  static XC title(String v) => XC(v, 4);
  static XC bold(String v) => XC(v, 5);
}

class XlsxSheet {
  final String name;
  final List<double> widths;
  final List<List<XC>> rows = [];
  XlsxSheet(this.name, this.widths);

  void row(List<XC> cells) => rows.add(cells);
}

class XlsxBuilder {
  static const String _head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
  static const String _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  static const String _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  static const String _pkgRel = 'http://schemas.openxmlformats.org/package/2006/relationships';
  static const String _styles = '$_head<styleSheet xmlns="$_ns">'
      '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font>'
      '<font><b/><sz val="14"/><name val="Calibri"/></font></fonts>'
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFD9EAD3"/><bgColor indexed="64"/></patternFill></fill></fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="6">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>'
      '<xf numFmtId="3" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
      '<xf numFmtId="3" fontId="1" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
      '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  final List<XlsxSheet> _sheets = [];

  XlsxSheet sheet(String name, List<double> widths) {
    var n = name.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ');
    if (n.length > 31) n = n.substring(0, 31);
    final s = XlsxSheet(n, widths);
    _sheets.add(s);
    return s;
  }

  static String _esc(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r < 0x20 && r != 9 && r != 10 && r != 13) continue;
      switch (r) {
        case 38:
          b.write('&amp;');
          break;
        case 60:
          b.write('&lt;');
          break;
        case 62:
          b.write('&gt;');
          break;
        case 34:
          b.write('&quot;');
          break;
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static String _col(int i) {
    var n = i + 1;
    var s = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      s = String.fromCharCode(65 + r) + s;
      n = (n - 1) ~/ 26;
    }
    return s;
  }

  String _sheetXml(XlsxSheet sh) {
    final b = StringBuffer('$_head<worksheet xmlns="$_ns">');
    if (sh.widths.isNotEmpty) {
      b.write('<cols>');
      for (var i = 0; i < sh.widths.length; i++) {
        b.write('<col min="${i + 1}" max="${i + 1}" width="${sh.widths[i]}" customWidth="1"/>');
      }
      b.write('</cols>');
    }
    b.write('<sheetData>');
    for (var r = 0; r < sh.rows.length; r++) {
      b.write('<row r="${r + 1}">');
      final row = sh.rows[r];
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        final v = cell.value;
        if (v == null) continue;
        final ref = '${_col(c)}${r + 1}';
        if (v is num) {
          b.write('<c r="$ref" s="${cell.style}"><v>$v</v></c>');
        } else {
          b.write('<c r="$ref" s="${cell.style}" t="inlineStr"><is><t xml:space="preserve">${_esc(v.toString())}</t></is></c>');
        }
      }
      b.write('</row>');
    }
    b.write('</sheetData></worksheet>');
    return b.toString();
  }

  Uint8List build() {
    final n = _sheets.length;
    final ct = StringBuffer('$_head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 0; i < n; i++) {
      ct.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
    }
    ct.write('</Types>');

    final wbx = StringBuffer('$_head<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>');
    for (var i = 0; i < n; i++) {
      wbx.write('<sheet name="${_esc(_sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>');
    }
    wbx.write('</sheets></workbook>');

    final rels = StringBuffer('$_head<Relationships xmlns="$_pkgRel">');
    for (var i = 0; i < n; i++) {
      rels.write('<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" Target="worksheets/sheet${i + 1}.xml"/>');
    }
    rels.write('<Relationship Id="rId${n + 1}" Type="$_rel/styles" Target="styles.xml"/></Relationships>');

    final zip = _StoredZip();
    zip.add('[Content_Types].xml', ct.toString());
    zip.add('_rels/.rels',
        '$_head<Relationships xmlns="$_pkgRel"><Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    zip.add('xl/workbook.xml', wbx.toString());
    zip.add('xl/_rels/workbook.xml.rels', rels.toString());
    zip.add('xl/styles.xml', _styles);
    for (var i = 0; i < n; i++) {
      zip.add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(_sheets[i]));
    }
    return zip.build();
  }
}

/// Zip tanpa kompresi (stored) - cukup untuk file XLSX
class _StoredZip {
  final List<MapEntry<String, Uint8List>> _files = [];

  void add(String name, String content) => _files.add(MapEntry(name, Uint8List.fromList(utf8.encode(content))));

  static final List<int> _table = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
    }
    return c;
  });

  static int _crc32(Uint8List data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  Uint8List build() {
    final out = BytesBuilder();
    final central = BytesBuilder();
    var offset = 0;
    for (final f in _files) {
      final name = utf8.encode(f.key);
      final data = f.value;
      final crc = _crc32(data);

      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 0x0800, Endian.little)
        ..setUint16(8, 0, Endian.little)
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, 33, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, data.length, Endian.little)
        ..setUint32(22, data.length, Endian.little)
        ..setUint16(26, name.length, Endian.little)
        ..setUint16(28, 0, Endian.little);
      out.add(local.buffer.asUint8List());
      out.add(name);
      out.add(data);

      final cd = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(4, 20, Endian.little)
        ..setUint16(6, 20, Endian.little)
        ..setUint16(8, 0x0800, Endian.little)
        ..setUint16(10, 0, Endian.little)
        ..setUint16(12, 0, Endian.little)
        ..setUint16(14, 33, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, data.length, Endian.little)
        ..setUint32(24, data.length, Endian.little)
        ..setUint16(28, name.length, Endian.little)
        ..setUint16(30, 0, Endian.little)
        ..setUint16(32, 0, Endian.little)
        ..setUint16(34, 0, Endian.little)
        ..setUint16(36, 0, Endian.little)
        ..setUint32(38, 0, Endian.little)
        ..setUint32(42, offset, Endian.little);
      central.add(cd.buffer.asUint8List());
      central.add(name);
      offset += 30 + name.length + data.length;
    }
    final cdBytes = central.toBytes();
    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, Endian.little)
      ..setUint16(4, 0, Endian.little)
      ..setUint16(6, 0, Endian.little)
      ..setUint16(8, _files.length, Endian.little)
      ..setUint16(10, _files.length, Endian.little)
      ..setUint32(12, cdBytes.length, Endian.little)
      ..setUint32(16, offset, Endian.little)
      ..setUint16(20, 0, Endian.little);
    out.add(cdBytes);
    out.add(end.buffer.asUint8List());
    return out.toBytes();
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/export.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTime _from = dayStart(DateTime.now());
  late DateTime _to = dayStart(DateTime.now());
  ReportData? _data;
  List<Sale> _sales = [];
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await Repo.report(_from, _to);
      final s = await Repo.sales(_from, _to);
      final e = await Repo.expenses(_from, _to);
      if (!mounted) return;
      setState(() {
        _data = d;
        _sales = s;
        _expenses = e;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Notify.error('Gagal memuat laporan: $e');
    }
  }

  /// Cetak laporan penjualan (harian / periode) ke printer thermal
  Future<void> _printRecap() async {
    final d = _data;
    if (d == null) return;
    final app = context.read<AppState>();
    final withList = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                dbDay(_from) == dbDay(_to) ? 'Cetak Laporan Harian ${fmtDate(_from)}' : 'Cetak Laporan ${fmtDateShort(_from)} - ${fmtDateShort(_to)}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.summarize_rounded),
              title: const Text('Ringkasan'),
              subtitle: const Text('Total, metode bayar, kasir, pengeluaran, menu terjual'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt_rounded),
              title: const Text('Ringkasan + daftar transaksi'),
              subtitle: Text('${_sales.where((e) => !e.isVoid).length} transaksi ikut dicetak'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (withList == null) return;
    final ok = await PrinterService.printItems(
      app,
      Receipts.recap(app, d, app.user?.name ?? '', sales: withList ? _sales.where((e) => !e.isVoid).toList() : null),
      copies: 1,
      silent: true,
    );
    if (ok) {
      Notify.success('Laporan dicetak');
      Activity.log('data', 'Cetak laporan ke printer', '${dbDay(_from)} s/d ${dbDay(_to)}');
    }
  }

  Future<void> _printProfitLoss() async {
    final d = _data;
    if (d == null) return;
    final app = context.read<AppState>();
    final ok = await PrinterService.printItems(app, Receipts.profitLoss(app, d, app.user?.name ?? ''), copies: 1, silent: true);
    if (ok) {
      Notify.success('Laporan laba rugi dicetak');
      Activity.log('data', 'Cetak laba rugi ke printer', '${dbDay(_from)} s/d ${dbDay(_to)}');
    }
  }

  Future<void> _export(bool pdf) async {
    await ReportExport.export(context.read<AppState>(), _from, _to, pdf: pdf);
  }

  Future<void> _openSale(Sale s) async {
    final full = await Repo.sale(s.id);
    if (full == null || !mounted) return;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => SaleDetailSheet(sale: full),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Laporan', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'Cetak laporan ke printer', onPressed: _printRecap, icon: const Icon(Icons.print_rounded)),
            PopupMenuButton<String>(
              tooltip: 'Export laporan',
              icon: const Icon(Icons.download_rounded),
              onSelected: (v) => _export(v == 'pdf'),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(leading: Icon(Icons.picture_as_pdf_rounded, color: Colors.red), title: Text('Export PDF')),
                ),
                PopupMenuItem(
                  value: 'xlsx',
                  child: ListTile(leading: Icon(Icons.grid_on_rounded, color: Colors.green), title: Text('Export Excel (.xlsx)')),
                ),
              ],
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'Ringkasan'),
              Tab(text: 'Laba Rugi'),
              Tab(text: 'Transaksi'),
              Tab(text: 'Menu Terlaris'),
              Tab(text: 'Pengeluaran'),
            ],
          ),
        ),
        body: Column(
          children: [
            const SizedBox(height: 6),
            PeriodPicker(
              from: _from,
              to: _to,
              onChanged: (f, t) {
                setState(() {
                  _from = f;
                  _to = t;
                });
                _load();
              },
            ),
            Expanded(
              child: _loading || _data == null
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      children: [
                        _Summary(data: _data!, onRefresh: _load, onPrint: _printRecap, onExport: _export),
                        _ProfitLossView(data: _data!, onPrint: _printProfitLoss, onExport: _export),
                        _SalesList(sales: _sales, onTap: _openSale, onRefresh: _load),
                        _TopItems(data: _data!),
                        _ExpenseList(list: _expenses, data: _data!),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final ReportData data;
  final Future<void> Function() onRefresh;
  final VoidCallback onPrint;
  final ValueChanged<bool> onExport;
  const _Summary({required this.data, required this.onRefresh, required this.onPrint, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width > 700;
    final cards = [
      StatCard(title: 'Total Penjualan', value: rp(data.total), icon: Icons.trending_up_rounded, color: cs.primary),
      StatCard(title: 'Jumlah Transaksi', value: nf(data.trxCount), icon: Icons.receipt_long_rounded, color: Colors.indigo,
          sub: data.voidCount > 0 ? '${data.voidCount} dibatalkan' : null),
      StatCard(title: 'Rata-rata / Transaksi', value: rp(data.average), icon: Icons.analytics_rounded, color: Colors.teal),
      StatCard(title: 'Pengeluaran', value: rp(data.expense), icon: Icons.account_balance_wallet_rounded, color: cs.error),
      StatCard(
          title: 'Selisih (Penjualan - Pengeluaran)',
          value: rp(data.net),
          icon: Icons.savings_rounded,
          color: data.net >= 0 ? const Color(0xFF16A34A) : cs.error),
      StatCard(title: 'Diskon Diberikan', value: rp(data.discount), icon: Icons.local_offer_rounded, color: Colors.orange,
          sub: 'Pajak ${rp(data.tax)} • Service ${rp(data.service)}'),
    ];
    Widget nvList(List<NameValue> list, String empty) => SoftCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: list.isEmpty
              ? Padding(padding: const EdgeInsets.all(12), child: Text(empty))
              : Column(
                  children: [
                    for (final m in list)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${m.count} transaksi'),
                        trailing: Text(rp(m.total), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
        );
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onPrint,
                  icon: const Icon(Icons.print_rounded),
                  label: Text(dbDay(data.from) == dbDay(data.to) ? 'Cetak Laporan Harian' : 'Cetak Laporan'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Export PDF',
                onPressed: () => onExport(true),
                icon: const Icon(Icons.picture_as_pdf_rounded),
              ),
              IconButton.filledTonal(
                tooltip: 'Export Excel',
                onPressed: () => onExport(false),
                icon: const Icon(Icons.grid_on_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: wide ? 3 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: wide ? 2.6 : 1.4,
            children: cards,
          ),
          if (data.daily.length > 1) ...[
            const SectionTitle('GRAFIK PENJUALAN HARIAN'),
            SoftCard(child: SizedBox(height: 180, child: _BarChart(items: data.daily))),
          ],
          const SectionTitle('PER METODE PEMBAYARAN'),
          nvList(data.byMethod, 'Belum ada transaksi'),
          const SectionTitle('PER KASIR'),
          nvList(data.byCashier, 'Belum ada transaksi'),
        ],
      ),
    );
  }
}

class _ProfitLossView extends StatelessWidget {
  final ReportData data;
  final VoidCallback onPrint;
  final ValueChanged<bool> onExport;
  const _ProfitLossView({required this.data, required this.onPrint, required this.onExport});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final pl = ProfitLoss.from(data, app.hppCategories);
    const green = Color(0xFF16A34A);

    Widget line(String l, int v, {bool bold = false, bool minus = false, Color? color, double indent = 0}) => Padding(
          padding: EdgeInsets.fromLTRB(indent, 4, 0, 4),
          child: Row(
            children: [
              Expanded(child: Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400))),
              Text(minus && v != 0 ? '(${rp(v)})' : rp(v),
                  style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, color: color)),
            ],
          ),
        );

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: cs.primary, letterSpacing: 0.4)),
                const SizedBox(height: 4),
                ...children,
              ],
            ),
          ),
        );

    final netColor = pl.net >= 0 ? green : cs.error;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: onPrint,
                icon: const Icon(Icons.print_rounded),
                label: const Text('Cetak Laba Rugi'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(tooltip: 'Export PDF', onPressed: () => onExport(true), icon: const Icon(Icons.picture_as_pdf_rounded)),
            IconButton.filledTonal(tooltip: 'Export Excel', onPressed: () => onExport(false), icon: const Icon(Icons.grid_on_rounded)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [netColor, Color.lerp(netColor, Colors.black, 0.25)!]),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Text(pl.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH',
                  style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, letterSpacing: 1)),
              FittedBox(
                child: Text(rp(pl.net), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              ),
              Text('Margin ${pl.margin.toStringAsFixed(1)}% dari pendapatan bersih', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        section('PENDAPATAN', [
          line('Penjualan kotor', pl.gross, indent: 8),
          if (pl.discount > 0) line('Diskon', pl.discount, minus: true, color: cs.error, indent: 8),
          if (pl.service > 0) line('Service', pl.service, indent: 8),
          const Divider(),
          line('Pendapatan bersih', pl.revenue, bold: true),
        ]),
        section('HARGA POKOK PENJUALAN (HPP)', [
          if (pl.hppItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Belum ada pengeluaran kategori: ${app.hppCategories.join(', ')}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
          for (final e in pl.hppItems) line(e.name, e.total, minus: true, indent: 8),
          const Divider(),
          line('Total HPP', pl.hpp, minus: true, bold: true),
          line('LABA KOTOR', pl.grossProfit, bold: true, color: pl.grossProfit >= 0 ? green : cs.error),
        ]),
        section('BEBAN OPERASIONAL', [
          if (pl.opexItems.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('Tidak ada beban operasional', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ),
          for (final e in pl.opexItems) line(e.name, e.total, minus: true, indent: 8),
          const Divider(),
          line('Total beban operasional', pl.opex, minus: true, bold: true),
        ]),
        section('HASIL', [
          line('Laba kotor', pl.grossProfit),
          line('Beban operasional', pl.opex, minus: true),
          const Divider(),
          line(pl.net >= 0 ? 'LABA BERSIH' : 'RUGI BERSIH', pl.net, bold: true, color: netColor),
        ]),
        if (pl.tax > 0)
          Text('Pajak dipungut dari pelanggan ${rp(pl.tax)} tidak dihitung sebagai pendapatan (titipan untuk disetor).',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 6),
        Text('Kategori HPP diatur di Pengaturan > Transaksi & Pajak.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<NameValue> items;
  const _BarChart({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxV = items.fold<int>(0, (a, b) => b.total > a ? b.total : a);
    return LayoutBuilder(builder: (context, c) {
      final barW = ((c.maxWidth - 8) / items.length).clamp(4.0, 40.0).toDouble();
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final it in items)
              Tooltip(
                message: '${it.name}\n${rp(it.total)}',
                child: SizedBox(
                  width: barW,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        margin: EdgeInsets.symmetric(horizontal: barW * 0.15),
                        height: maxV == 0 ? 2.0 : (it.total / maxV * 140).clamp(2.0, 140.0).toDouble(),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(it.name.length >= 10 ? it.name.substring(8, 10) : it.name,
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _SalesList extends StatelessWidget {
  final List<Sale> sales;
  final ValueChanged<Sale> onTap;
  final Future<void> Function() onRefresh;
  const _SalesList({required this.sales, required this.onTap, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (sales.isEmpty) return const EmptyState(icon: Icons.receipt_long_rounded, title: 'Belum ada transaksi');
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: sales.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = sales[i];
          return SoftCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            onTap: () => onTap(s),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: s.isVoid ? cs.errorContainer : cs.primaryContainer,
                  child: Icon(s.isVoid ? Icons.block_rounded : Icons.receipt_rounded,
                      color: s.isVoid ? cs.onErrorContainer : cs.onPrimaryContainer, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                        '${fmtDateTime(s.createdAt)} • ${s.paymentMethod}${s.customer.isNotEmpty ? ' • ${s.customer}' : ''}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(rp(s.total),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            decoration: s.isVoid ? TextDecoration.lineThrough : null,
                            color: s.isVoid ? cs.error : null)),
                    if (s.isVoid) Text('BATAL', style: TextStyle(color: cs.error, fontSize: 11, fontWeight: FontWeight.w700)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TopItems extends StatelessWidget {
  final ReportData data;
  const _TopItems({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (data.topItems.isEmpty) return const EmptyState(icon: Icons.emoji_events_rounded, title: 'Belum ada menu terjual');
    final maxQ = data.topItems.first.qty == 0 ? 1 : data.topItems.first.qty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: data.topItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final t = data.topItems[i];
        final medal = i == 0 ? const Color(0xFFF5B301) : (i == 1 ? const Color(0xFF9E9E9E) : (i == 2 ? const Color(0xFFB87333) : cs.primary));
        return SoftCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: medal.withOpacity(0.18),
                child: Text('${i + 1}', style: TextStyle(color: medal, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: t.qty / maxQ, minHeight: 6),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${t.qty} porsi', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(rp(t.total), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseList extends StatelessWidget {
  final List<Expense> list;
  final ReportData data;
  const _ExpenseList({required this.list, required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (list.isEmpty) return const EmptyState(icon: Icons.savings_rounded, title: 'Tidak ada pengeluaran');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        SoftCard(
          child: Column(
            children: [
              for (final c in data.expenseByCat)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text('${c.name} (${c.count})')),
                    Text(rp(c.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                ),
              const Divider(),
              Row(children: [
                const Expanded(child: Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900))),
                Text(rp(data.expense), style: TextStyle(fontWeight: FontWeight.w900, color: cs.error)),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final e in list)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text(e.description.isEmpty ? e.category : e.description),
            subtitle: Text('${e.category} • ${fmtDate(e.date)} • ${e.method}'),
            trailing: Text(rp(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
      ],
    );
  }
}

// ======================= DETAIL TRANSAKSI =======================
class SaleDetailSheet extends StatelessWidget {
  final Sale sale;
  const SaleDetailSheet({super.key, required this.sale});

  Future<void> _delete(BuildContext context) async {
    final app = context.read<AppState>();
    if (!app.isOwner) {
      Notify.warning('Hanya owner yang dapat menghapus transaksi');
      return;
    }
    final reason = await inputDialog(context, title: 'Hapus Transaksi', label: 'Alasan penghapusan', hint: 'contoh: salah input');
    if (reason == null || !context.mounted) return;
    final ok = await confirmDialog(context,
        title: 'Hapus permanen?',
        message: 'Transaksi ${sale.invoiceNo} (${rp(sale.total)}) akan dihapus dan tidak dihitung di laporan. Tindakan ini tercatat di log aktivitas.',
        okText: 'Hapus',
        danger: true);
    if (!ok || !context.mounted) return;
    await Repo.deleteSale(sale.id, reason);
    Notify.success('Transaksi dihapus');
    if (context.mounted) Navigator.pop(context, true);
  }

  Future<void> _reprint(AppState app) async {
    final ok = await PrinterService.printSale(app, sale, reprint: true);
    if (ok) Activity.log('penjualan', 'Cetak ulang struk', '${sale.invoiceNo} ${rp(sale.total)}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    Widget row(String l, String r, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Text(l, style: TextStyle(fontWeight: bold ? FontWeight.w900 : null)),
            const Spacer(),
            Text(r, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, color: color)),
          ]),
        );
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(sale.invoiceNo, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                if (sale.isVoid)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(20)),
                    child: Text('DIBATALKAN', style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
              ],
            ),
            Text('${fmtDayName(sale.createdAt)} ${fmtTime(sale.createdAt)}', style: TextStyle(color: cs.onSurfaceVariant)),
            Text('Kasir: ${sale.userName}${sale.customer.isNotEmpty ? ' • ${sale.customer}' : ''}${sale.orderType.isNotEmpty ? ' • ${sale.orderType}' : ''}',
                style: TextStyle(color: cs.onSurfaceVariant)),
            if (sale.isVoid && sale.voidReason.isNotEmpty) Text('Alasan batal: ${sale.voidReason}', style: TextStyle(color: cs.error)),
            const Divider(height: 24),
            for (final it in sale.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${it.qty} x ${rp(it.price)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                          if (it.note.isNotEmpty) Text('Catatan: ${it.note}', style: TextStyle(color: cs.tertiary, fontSize: 12)),
                        ],
                      ),
                    ),
                    Text(rp(it.subtotal), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const Divider(height: 24),
            row('Subtotal', rp(sale.subtotal)),
            if (sale.discount > 0) row('Diskon', '-${rp(sale.discount)}', color: cs.error),
            if (sale.service > 0) row('Service', rp(sale.service)),
            if (sale.tax > 0) row('Pajak', rp(sale.tax)),
            row('TOTAL', rp(sale.total), bold: true, color: cs.primary),
            row(sale.paymentMethod, rp(sale.paid)),
            if (sale.isCash) row('Kembali', rp(sale.change)),
            if (sale.reference.isNotEmpty) row('Ref', sale.reference),
            const SizedBox(height: 18),
            Row(
              children: [
                if (app.isOwner)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _delete(context),
                      style: OutlinedButton.styleFrom(foregroundColor: cs.error),
                      icon: const Icon(Icons.delete_forever_rounded),
                      label: const Text('Hapus'),
                    ),
                  ),
                if (app.isOwner) const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _reprint(app),
                    icon: const Icon(Icons.print_rounded),
                    label: const Text('Cetak Ulang'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

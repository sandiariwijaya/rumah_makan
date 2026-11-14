import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cart_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/printer.dart';
import '../utils/format.dart';
import '../utils/notify.dart';

IconData payIcon(PayMethod m) {
  final n = m.name.toUpperCase();
  if (m.isCash) return Icons.payments_rounded;
  if (n.contains('QRIS')) return Icons.qr_code_2_rounded;
  if (n.contains('TRANSFER') || n.contains('BANK')) return Icons.account_balance_rounded;
  if (n.contains('DEBIT') || n.contains('KARTU') || n.contains('CARD')) return Icons.credit_card_rounded;
  return Icons.account_balance_wallet_rounded;
}

/// Mulai proses pembayaran untuk isi keranjang
Future<void> startPayment(BuildContext context) async {
  final cart = context.read<CartState>();
  final app = context.read<AppState>();
  if (cart.isEmpty) {
    Notify.warning('Keranjang masih kosong');
    return;
  }
  final methods = await Repo.payMethods(onlyActive: true);
  if (!context.mounted) return;
  if (methods.isEmpty) {
    Notify.error('Belum ada metode pembayaran aktif. Atur di Pengaturan.');
    return;
  }
  final sale = await showModalBottomSheet<Sale>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (_) => PaymentSheet(methods: methods),
  );
  if (sale == null || !context.mounted) return;
  if (app.b('pr_auto')) {
    PrinterService.printSale(app, sale);
  }
  await showSuccessDialog(context, sale);
}

Future<void> showSuccessDialog(BuildContext context, Sale s) async {
  final app = context.read<AppState>();
  final autoPrinted = app.b('pr_auto');
  await showDialog(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(color: Color(0x2216A34A), shape: BoxShape.circle),
          child: const Icon(Icons.check_rounded, color: Color(0xFF16A34A), size: 44),
        ),
        title: const Text('Pembayaran Berhasil', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.invoiceNo, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Text('Total ${rp(s.total)} • ${s.paymentMethod}', textAlign: TextAlign.center),
            if (s.isCash) ...[
              const SizedBox(height: 14),
              Text('Kembalian', style: TextStyle(color: cs.onSurfaceVariant)),
              FittedBox(
                child: Text(rp(s.change),
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: cs.primary)),
              ),
            ],
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => PrinterService.printSale(app, s),
            icon: const Icon(Icons.print_rounded),
            label: Text(autoPrinted ? 'Cetak Lagi' : 'Cetak Struk'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Transaksi Baru'),
          ),
        ],
      );
    },
  );
}

class PaymentSheet extends StatefulWidget {
  final List<PayMethod> methods;
  const PaymentSheet({super.key, required this.methods});

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late PayMethod _method;
  final _amount = TextEditingController();
  final _ref = TextEditingController();
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _method = widget.methods.firstWhere((m) => m.isCash, orElse: () => widget.methods.first);
  }

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  List<int> _suggestions(int total) {
    final set = <int>{};
    for (final step in [1000, 5000, 10000, 20000, 50000, 100000]) {
      final v = ((total + step - 1) ~/ step) * step;
      if (v > total) set.add(v);
    }
    for (final note in [50000, 100000, 200000]) {
      if (note > total) set.add(note);
    }
    final l = set.toList()..sort();
    return l.take(6).toList();
  }

  void _setAmount(int v) {
    _amount.text = nf(v);
    setState(() {});
  }

  Future<void> _process(Totals t) async {
    if (_processing) return;
    final app = context.read<AppState>();
    final cart = context.read<CartState>();
    if (cart.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final paid = _method.isCash ? parseNum(_amount.text) : t.total;
    if (_method.isCash && paid < t.total) {
      Notify.error('Uang yang dibayar kurang ${rp(t.total - paid)}');
      return;
    }
    setState(() => _processing = true);
    try {
      final sale = Sale(
        createdAt: DateTime.now(),
        userName: app.user?.name ?? '',
        customer: cart.customer.trim(),
        orderType: cart.orderType,
        subtotal: t.subtotal,
        discount: t.discount,
        service: t.service,
        tax: t.tax,
        total: t.total,
        paymentMethod: _method.name,
        isCash: _method.isCash,
        paid: paid,
        change: _method.isCash ? paid - t.total : 0,
        reference: _ref.text.trim(),
      );
      final id = await Repo.saveSale(sale, List.of(cart.items), prefix: app.get('invoice_prefix'), userId: app.user?.id);
      final held = cart.heldId;
      if (held != null) await Repo.deleteHeld(held);
      final saved = await Repo.sale(id);
      cart.clear();
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      Notify.error('Gagal menyimpan transaksi: $e');
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cart = context.watch<CartState>();
    final cs = Theme.of(context).colorScheme;
    final t = cart.totals(app.d('tax_percent'), app.d('service_percent'));
    final paid = parseNum(_amount.text);
    final change = paid - t.total;
    final qris = app.qris;
    final canPay = !_processing && (!_method.isCash || paid >= t.total);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.5)!]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  Text('Total Bayar', style: TextStyle(color: cs.onPrimary.withOpacity(0.85))),
                  FittedBox(
                    child: Text(rp(t.total),
                        style: TextStyle(color: cs.onPrimary, fontSize: 36, fontWeight: FontWeight.w900)),
                  ),
                  Text('${cart.count} item${cart.customer.trim().isNotEmpty ? ' • ${cart.customer.trim()}' : ''}',
                      style: TextStyle(color: cs.onPrimary.withOpacity(0.85))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Metode Pembayaran', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in widget.methods)
                  ChoiceChip(
                    avatar: Icon(payIcon(m), size: 18),
                    label: Text(m.name),
                    selected: identical(m, _method),
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_method.isCash) ...[
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahFormatter()],
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Uang Diterima',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  suffixIcon: _amount.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() => _amount.clear()),
                        ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(onPressed: () => _setAmount(t.total), child: const Text('Uang Pas')),
                  for (final s in _suggestions(t.total))
                    OutlinedButton(onPressed: () => _setAmount(s), child: Text(nf(s))),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (paid >= t.total ? const Color(0xFF16A34A) : cs.error).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Text(paid >= t.total ? 'Kembalian' : 'Kurang', style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text(rp(change.abs()),
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: paid >= t.total ? const Color(0xFF16A34A) : cs.error)),
                  ],
                ),
              ),
            ] else ...[
              if (_method.isQris && qris != null)
                Center(
                  child: GestureDetector(
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => Dialog(
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx),
                          child: Padding(padding: const EdgeInsets.all(12), child: Image.memory(qris)),
                        ),
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                      child: Image.memory(qris, height: 240, fit: BoxFit.contain),
                    ),
                  ),
                )
              else if (_method.isQris)
                Text('Gambar QRIS belum diatur (Pengaturan > Pembayaran & QRIS).',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              TextField(
                controller: _ref,
                decoration: InputDecoration(
                  labelText: 'No. Referensi (opsional)',
                  prefixIcon: const Icon(Icons.tag_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: canPay
                    ? () {
                        HapticFeedback.mediumImpact();
                        _process(t);
                      }
                    : null,
                icon: _processing
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.check_circle_rounded),
                label: Text(_processing ? 'Menyimpan...' : 'PROSES PEMBAYARAN',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

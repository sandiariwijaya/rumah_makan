import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cart_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';
import 'payment_sheet.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  List<MenuItem> _menus = [];
  List<Category> _cats = [];
  int? _cat; // null = semua
  String _q = '';
  bool _loading = true;
  int _heldCount = 0;
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final m = await Repo.menus();
      final c = await Repo.categories();
      final h = await Repo.heldCount();
      if (!mounted) return;
      setState(() {
        _menus = m;
        _cats = c;
        _heldCount = h;
        _loading = false;
        if (_cat != null && !c.any((e) => e.id == _cat)) _cat = null;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      Notify.error('Gagal memuat menu: $e');
    }
  }

  Future<void> _refreshHeld() async {
    final h = await Repo.heldCount();
    if (mounted) setState(() => _heldCount = h);
  }

  List<MenuItem> get _filtered {
    final q = _q.trim().toLowerCase();
    return _menus.where((m) {
      if (_cat != null && m.categoryId != _cat) return false;
      if (q.isNotEmpty && !m.name.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _tapMenu(MenuItem m) {
    if (!m.available) {
      Notify.warning('${m.name} sedang habis');
      return;
    }
    final app = context.read<AppState>();
    if (app.b('ui_haptic')) HapticFeedback.selectionClick();
    context.read<CartState>().add(m);
  }

  Future<void> _holdOrder() async {
    final cart = context.read<CartState>();
    if (cart.isEmpty) return;
    final label = await inputDialog(
      context,
      title: 'Simpan Pesanan',
      label: 'Nama pelanggan',
      initial: cart.heldLabel.isNotEmpty ? cart.heldLabel : cart.customer,
      hint: 'contoh: Pak Budi',
    );
    if (label == null) return;
    final l = label.trim().isEmpty ? 'Pesanan ${fmtTime(DateTime.now())}' : label.trim();
    if (cart.customer.trim().isEmpty) cart.setCustomer(l);
    await Repo.saveHeld(id: cart.heldId, label: l, data: cart.toJsonString());
    cart.clear();
    Notify.success('Pesanan "$l" disimpan');
    _refreshHeld();
  }

  Future<void> _openHeld() async {
    final list = await Repo.heldOrders();
    if (!mounted) return;
    if (list.isEmpty) {
      Notify.info('Tidak ada pesanan tersimpan');
      return;
    }
    final picked = await showModalBottomSheet<HeldOrder>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (ctx) => _HeldList(list: list, onChanged: _refreshHeld),
    );
    if (picked == null || !mounted) return;
    final cart = context.read<CartState>();
    if (!cart.isEmpty && cart.heldId != picked.id) {
      final ok = await confirmDialog(context,
          title: 'Ganti Keranjang?', message: 'Keranjang saat ini belum dibayar. Simpan dulu atau ganti dengan pesanan tersimpan?', okText: 'Ganti');
      if (!ok || !mounted) return;
    }
    cart.loadHeld(picked);
    Notify.info('Pesanan "${picked.label}" dibuka');
  }

  Future<void> _openCartSheet() async {
    final goPay = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: CartPanel(
          onPay: () => Navigator.pop(ctx, true),
          onHold: () => Navigator.pop(ctx, false),
        ),
      ),
    );
    if (!mounted) return;
    if (goPay == true) {
      await startPayment(context);
    } else if (goPay == false) {
      await _holdOrder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final tablet = app.isTablet(context);
    final width = MediaQuery.sizeOf(context).width;
    double cartW = width * 0.36;
    if (cartW < 320) cartW = 320;
    if (cartW > 430) cartW = 430;

    final menuPanel = _MenuPanel(
      loading: _loading,
      menus: _filtered,
      cats: _cats,
      selectedCat: _cat,
      search: _search,
      heldCount: _heldCount,
      onCat: (c) => setState(() => _cat = c),
      onSearch: (v) => setState(() => _q = v),
      onTap: _tapMenu,
      onHeld: _openHeld,
      onRefresh: _load,
    );

    if (tablet) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              Expanded(child: menuPanel),
              SizedBox(
                width: cartW,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 2,
                  child: CartPanel(onPay: () => startPayment(context), onHold: _holdOrder),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(bottom: false, child: menuPanel),
      bottomNavigationBar: _CartBar(onOpen: _openCartSheet, onPay: () => startPayment(context)),
    );
  }
}

// ======================= PANEL MENU =======================
class _MenuPanel extends StatelessWidget {
  final bool loading;
  final List<MenuItem> menus;
  final List<Category> cats;
  final int? selectedCat;
  final TextEditingController search;
  final int heldCount;
  final ValueChanged<int?> onCat;
  final ValueChanged<String> onSearch;
  final ValueChanged<MenuItem> onTap;
  final VoidCallback onHeld;
  final Future<void> Function() onRefresh;

  const _MenuPanel({
    required this.loading,
    required this.menus,
    required this.cats,
    required this.selectedCat,
    required this.search,
    required this.heldCount,
    required this.onCat,
    required this.onSearch,
    required this.onTap,
    required this.onHeld,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final showImg = app.b('ui_show_images');
    final extent = app.menuCardExtent;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: TextField(
                    controller: search,
                    onChanged: onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari menu...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                search.clear();
                                onSearch('');
                              },
                            ),
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: heldCount > 0,
                label: Text('$heldCount'),
                child: IconButton.filledTonal(
                  tooltip: 'Pesanan tersimpan',
                  onPressed: onHeld,
                  icon: const Icon(Icons.receipt_long_rounded),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Semua'),
                  selected: selectedCat == null,
                  onSelected: (_) => onCat(null),
                ),
              ),
              for (final c in cats)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c.name),
                    selected: selectedCat == c.id,
                    onSelected: (_) => onCat(c.id),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: menus.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 80),
                          EmptyState(
                              icon: Icons.restaurant_menu_rounded,
                              title: 'Menu tidak ditemukan',
                              subtitle: 'Tambahkan menu di halaman Menu'),
                        ])
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: extent,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: showImg ? 0.78 : 1.45,
                          ),
                          itemCount: menus.length,
                          itemBuilder: (_, i) => _MenuCard(item: menus[i], showImage: showImg, onTap: () => onTap(menus[i])),
                        ),
                ),
        ),
      ],
    );
  }
}

class _MenuCard extends StatelessWidget {
  final MenuItem item;
  final bool showImage;
  final VoidCallback onTap;
  const _MenuCard({required this.item, required this.showImage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qty = context.select<CartState, int>((c) => c.qtyOf(item.id ?? -1));
    final selected = qty > 0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: selected ? cs.primary : cs.outlineVariant.withOpacity(0.5), width: selected ? 2 : 1),
        boxShadow: selected
            ? [BoxShadow(color: cs.primary.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 4))]
            : const [],
      ),
      child: Material(
        color: cs.surface,
        borderRadius: BorderRadius.circular(17),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Opacity(
            opacity: item.available ? 1 : 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showImage)
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: MenuThumb(image: item.image, name: item.name, radius: 0)),
                        if (!item.available)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black45,
                              alignment: Alignment.center,
                              child: const Text('HABIS',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            ),
                          ),
                        if (selected) Positioned(top: 6, right: 6, child: _QtyBadge(qty: qty)),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(item.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, height: 1.2)),
                          ),
                          if (!showImage && selected) ...[const SizedBox(width: 4), _QtyBadge(qty: qty)],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(item.available ? rp(item.price) : 'Habis',
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyBadge extends StatelessWidget {
  final int qty;
  const _QtyBadge({required this.qty});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 26),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6)],
      ),
      child: Text('$qty',
          textAlign: TextAlign.center, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

// ======================= BAR KERANJANG (HP) =======================
class _CartBar extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onPay;
  const _CartBar({required this.onOpen, required this.onPay});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cart = context.watch<CartState>();
    final cs = Theme.of(context).colorScheme;
    if (cart.isEmpty) return const SizedBox.shrink();
    final t = cart.totals(app.d('tax_percent'), app.d('service_percent'));
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Material(
          color: cs.primary,
          borderRadius: BorderRadius.circular(18),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
              child: Row(
                children: [
                  Badge(
                    label: Text('${cart.count}'),
                    backgroundColor: cs.tertiaryContainer,
                    textColor: cs.onTertiaryContainer,
                    child: Icon(Icons.shopping_bag_rounded, color: cs.onPrimary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Lihat pesanan', style: TextStyle(color: cs.onPrimary.withOpacity(0.85), fontSize: 12)),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(rp(t.total),
                              style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w900, fontSize: 18)),
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: onPay,
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.onPrimary,
                      foregroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('BAYAR', style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ======================= PANEL KERANJANG =======================
class CartPanel extends StatefulWidget {
  final VoidCallback onPay;
  final VoidCallback onHold;
  const CartPanel({super.key, required this.onPay, required this.onHold});

  @override
  State<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<CartPanel> {
  final _customer = TextEditingController();
  CartState? _cart;

  @override
  void initState() {
    super.initState();
    _cart = context.read<CartState>();
    _customer.text = _cart!.customer;
    _cart!.addListener(_syncCustomer);
  }

  void _syncCustomer() {
    final c = _cart;
    if (c == null || !mounted) return;
    if (_customer.text != c.customer) {
      _customer.value = TextEditingValue(text: c.customer, selection: TextSelection.collapsed(offset: c.customer.length));
    }
  }

  @override
  void dispose() {
    _cart?.removeListener(_syncCustomer);
    _customer.dispose();
    super.dispose();
  }

  Future<void> _editItem(CartItem it) async {
    final cart = context.read<CartState>();
    var qty = it.qty;
    final note = TextEditingController(text: it.note);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(it.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                      onPressed: qty > 1 ? () => setD(() => qty--) : null, icon: const Icon(Icons.remove_rounded)),
                  SizedBox(
                    width: 70,
                    child: Text('$qty',
                        textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
                  ),
                  IconButton.filledTonal(onPressed: () => setD(() => qty++), icon: const Icon(Icons.add_rounded)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final n in [5, 10, 20])
                    ActionChip(label: Text('$n'), onPressed: () => setD(() => qty = n)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: inputDeco('Catatan', icon: Icons.edit_note_rounded, hint: 'contoh: tidak pedas'),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              icon: Icon(Icons.delete_outline_rounded, color: Theme.of(ctx).colorScheme.error),
              label: Text('Hapus', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('Simpan')),
          ],
        ),
      ),
    );
    final noteText = note.text;
    disposeLater(note);
    if (res == 'delete') {
      cart.remove(it);
    } else if (res == 'ok') {
      cart.update(it, qty: qty, note: noteText);
    }
  }

  Future<void> _editDiscount() async {
    final app = context.read<AppState>();
    if (!app.can('discount')) {
      Notify.warning('Anda tidak punya akses memberi diskon');
      return;
    }
    final cart = context.read<CartState>();
    var percent = cart.discountPercent;
    final c = TextEditingController(text: cart.discountValue == 0 ? '' : (percent ? '${cart.discountValue}' : nf(cart.discountValue)));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Diskon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Rupiah')),
                  ButtonSegment(value: true, label: Text('Persen')),
                ],
                selected: {percent},
                onSelectionChanged: (s) => setD(() {
                  percent = s.first;
                  c.clear();
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: percent
                    ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]
                    : [RupiahFormatter()],
                decoration: inputDeco(percent ? 'Diskon (%)' : 'Diskon (Rp)', suffix: percent ? '%' : null, prefix: percent ? null : 'Rp '),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Terapkan')),
          ],
        ),
      ),
    );
    final v = parseNum(c.text);
    disposeLater(c);
    if (ok == true) cart.setDiscount(v, percent);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cart = context.watch<CartState>();
    final cs = Theme.of(context).colorScheme;
    final taxPct = app.d('tax_percent');
    final svcPct = app.d('service_percent');
    final t = cart.totals(taxPct, svcPct);
    final types = app.orderTypes;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.shopping_bag_rounded),
              const SizedBox(width: 8),
              Expanded(
                child: Text(cart.heldLabel.isNotEmpty ? 'Pesanan: ${cart.heldLabel}' : 'Pesanan',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (!cart.isEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final ok = await confirmDialog(context,
                        title: 'Kosongkan keranjang?', message: 'Semua item di keranjang akan dihapus.', okText: 'Kosongkan', danger: true);
                    if (ok) cart.clear();
                  },
                  icon: Icon(Icons.delete_sweep_rounded, color: cs.error),
                  label: Text('Hapus', style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
        if (types.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final ty in types)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(ty),
                      selected: cart.orderType == ty,
                      onSelected: (_) => cart.setOrderType(cart.orderType == ty ? '' : ty),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: TextField(
            controller: _customer,
            onChanged: cart.setCustomer,
            textCapitalization: TextCapitalization.words,
            decoration: inputDeco('Nama pelanggan (opsional)', icon: Icons.person_outline_rounded),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: cart.isEmpty
              ? const EmptyState(
                  icon: Icons.touch_app_rounded, title: 'Keranjang kosong', subtitle: 'Ketuk gambar menu untuk menambahkan')
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: cart.items.length,
                  separatorBuilder: (_, __) => Divider(height: 1, indent: 16, endIndent: 16, color: cs.outlineVariant.withOpacity(0.4)),
                  itemBuilder: (_, i) {
                    final it = cart.items[i];
                    return Dismissible(
                      key: ObjectKey(it),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: cs.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(Icons.delete_rounded, color: cs.onErrorContainer),
                      ),
                      onDismissed: (_) => cart.remove(it),
                      child: InkWell(
                        onTap: () => _editItem(it),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(it.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${rp(it.price)} • ${rp(it.subtotal)}',
                                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                    if (it.note.isNotEmpty)
                                      Text('📝 ${it.note}',
                                          style: TextStyle(color: cs.tertiary, fontSize: 12, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                              _Stepper(qty: it.qty, onMinus: () => cart.dec(it), onPlus: () => cart.inc(it)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.5))),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                _row('Subtotal', rp(t.subtotal)),
                InkWell(
                  onTap: cart.isEmpty ? null : _editDiscount,
                  child: _row(
                    'Diskon${cart.discountPercent && cart.discountValue > 0 ? ' (${cart.discountValue}%)' : ''}',
                    t.discount > 0 ? '-${rp(t.discount)}' : 'Tambah',
                    valueColor: t.discount > 0 ? cs.error : cs.primary,
                    icon: Icons.local_offer_outlined,
                  ),
                ),
                if (t.service > 0) _row('Service (${_pct(svcPct)}%)', rp(t.service)),
                if (t.tax > 0) _row('Pajak (${_pct(taxPct)}%)', rp(t.tax)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                    const Spacer(),
                    Text(rp(t.total), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: cs.primary)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: cart.isEmpty ? null : widget.onHold,
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Simpan'),
                        style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: cart.isEmpty ? null : widget.onPay,
                          icon: const Icon(Icons.payments_rounded),
                          label: const Text('BAYAR', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                          style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _pct(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Widget _row(String l, String r, {Color? valueColor, IconData? icon}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Text(l),
            if (icon != null) ...[const SizedBox(width: 4), Icon(icon, size: 14)],
            const Spacer(),
            Text(r, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
          ],
        ),
      );
}

class _Stepper extends StatelessWidget {
  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _Stepper({required this.qty, required this.onMinus, required this.onPlus});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withOpacity(0.6), borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onMinus,
            icon: Icon(qty <= 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, size: 20),
          ),
          SizedBox(
            width: 28,
            child: Text('$qty', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onPlus,
            icon: Icon(Icons.add_rounded, size: 20, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

// ======================= DAFTAR PESANAN TERSIMPAN =======================
class _HeldList extends StatefulWidget {
  final List<HeldOrder> list;
  final VoidCallback onChanged;
  const _HeldList({required this.list, required this.onChanged});

  @override
  State<_HeldList> createState() => _HeldListState();
}

class _HeldListState extends State<_HeldList> {
  late List<HeldOrder> _list = List.of(widget.list);

  int _total(HeldOrder h) {
    try {
      final c = CartState()..loadHeld(h);
      final v = c.subtotal;
      c.dispose();
      return v;
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Row(children: [
              Icon(Icons.receipt_long_rounded),
              SizedBox(width: 8),
              Text('Pesanan Tersimpan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ]),
          ),
          Flexible(
            child: _list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: EmptyState(icon: Icons.inbox_rounded, title: 'Tidak ada pesanan tersimpan'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final h = _list[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SoftCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          onTap: () => Navigator.pop(context, h),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: cs.primaryContainer,
                                child: Icon(Icons.shopping_bag_outlined, color: cs.onPrimaryContainer),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(h.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text('${fmtTime(h.createdAt)} • ${rp(_total(h))}',
                                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                                onPressed: () async {
                                  final ok = await confirmDialog(context,
                                      title: 'Hapus pesanan?', message: 'Pesanan "${h.label}" akan dihapus.', okText: 'Hapus', danger: true);
                                  if (!ok) return;
                                  await Repo.deleteHeld(h.id);
                                  widget.onChanged();
                                  if (mounted) setState(() => _list.remove(h));
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

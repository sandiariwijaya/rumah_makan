import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../utils/notify.dart';
import '../widgets/common.dart';

class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  late DateTime _from = dayStart(DateTime.now());
  late DateTime _to = dayStart(DateTime.now());
  List<Expense> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final l = await Repo.expenses(_from, _to);
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  bool _canModify(Expense e) {
    final app = context.read<AppState>();
    if (app.isOwner) return true;
    return e.userName == app.user?.name && dbDay(e.date) == dbDay(DateTime.now());
  }

  Future<void> _openForm([Expense? e]) async {
    if (e != null && !_canModify(e)) {
      Notify.warning('Hanya owner yang dapat mengubah data ini');
      return;
    }
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (_) => ExpenseForm(expense: e),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _list.fold<int>(0, (a, b) => a + b.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Pengeluaran', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat Pengeluaran'),
      ),
      body: Column(
        children: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: StatCard(
              title: 'Total Pengeluaran',
              value: rp(total),
              icon: Icons.account_balance_wallet_rounded,
              color: cs.error,
              sub: '${_list.length} catatan',
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? const EmptyState(icon: Icons.savings_rounded, title: 'Belum ada pengeluaran', subtitle: 'Catat belanja bahan, gas, listrik, dll.')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          itemCount: _list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final e = _list[i];
                            return SoftCard(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              onTap: () => _openForm(e),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: cs.errorContainer,
                                    child: Icon(Icons.shopping_basket_rounded, color: cs.onErrorContainer, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.description.isEmpty ? e.category : e.description,
                                            style: const TextStyle(fontWeight: FontWeight.w700)),
                                        Text('${e.category} • ${fmtDate(e.date)} • ${e.method}${e.userName.isNotEmpty ? ' • ${e.userName}' : ''}',
                                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Text(rp(e.amount), style: TextStyle(fontWeight: FontWeight.w800, color: cs.error)),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class ExpenseForm extends StatefulWidget {
  final Expense? expense;
  const ExpenseForm({super.key, this.expense});

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _desc = TextEditingController();
  final _amount = TextEditingController();
  late DateTime _date;
  String _cat = '';
  String _method = 'Tunai';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    final cats = context.read<AppState>().expenseCategories;
    if (e != null) {
      _desc.text = e.description;
      _amount.text = nf(e.amount);
      _date = e.date;
      _cat = e.category;
      _method = e.method.isEmpty ? 'Tunai' : e.method;
    } else {
      _date = dayStart(DateTime.now());
      _cat = cats.isNotEmpty ? cats.first : 'Lain-lain';
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = parseNum(_amount.text);
    if (amount <= 0) {
      Notify.warning('Nominal wajib diisi');
      return;
    }
    final app = context.read<AppState>();
    setState(() => _saving = true);
    try {
      await Repo.saveExpense(Expense(
        id: widget.expense?.id,
        date: _date,
        category: _cat,
        description: _desc.text.trim(),
        amount: amount,
        method: _method,
        userName: widget.expense?.userName.isNotEmpty == true ? widget.expense!.userName : (app.user?.name ?? ''),
      ));
      Notify.success('Pengeluaran disimpan');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      Notify.error('Gagal menyimpan: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Hapus pengeluaran?', message: 'Data ini akan dihapus permanen.', okText: 'Hapus', danger: true);
    if (!ok) return;
    await Repo.deleteExpense(widget.expense!.id!);
    Notify.success('Pengeluaran dihapus');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final cats = app.expenseCategories;
    final catItems = {...cats, if (_cat.isNotEmpty) _cat}.toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(widget.expense == null ? 'Catat Pengeluaran' : 'Ubah Pengeluaran',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                if (widget.expense != null)
                  IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline_rounded, color: cs.error)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: widget.expense == null,
              keyboardType: TextInputType.number,
              inputFormatters: [RupiahFormatter()],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              decoration: inputDeco('Nominal', prefix: 'Rp ', icon: Icons.payments_rounded),
            ),
            const SizedBox(height: 12),
            const Text('Kategori', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in catItems)
                  ChoiceChip(label: Text(c), selected: _cat == c, onSelected: (_) => setState(() => _cat = c)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              textCapitalization: TextCapitalization.sentences,
              decoration: inputDeco('Keterangan', icon: Icons.notes_rounded, hint: 'contoh: beli beras 25kg'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null) setState(() => _date = dayStart(d));
                    },
                    icon: const Icon(Icons.event_rounded),
                    label: Text(fmtDate(_date)),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'Tunai', label: Text('Tunai')),
                    ButtonSegment(value: 'Non Tunai', label: Text('Non Tunai')),
                  ],
                  selected: {_method == 'Tunai' ? 'Tunai' : 'Non Tunai'},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _method = s.first),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('SIMPAN', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

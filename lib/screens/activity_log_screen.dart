import 'package:flutter/material.dart';

import '../db/database.dart';
import '../models.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

/// Log aktivitas (khusus owner)
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  static const Map<String, String> _cats = {
    '': 'Semua',
    'akses': 'Login',
    'penjualan': 'Penjualan',
    'menu': 'Menu',
    'pengeluaran': 'Pengeluaran',
    'pengguna': 'Pengguna',
    'pengaturan': 'Pengaturan',
    'data': 'Data & Laporan',
  };

  late DateTime _from = dayStart(DateTime.now()).subtract(const Duration(days: 6));
  late DateTime _to = dayStart(DateTime.now());
  String _cat = '';
  String _q = '';
  List<ActivityLog> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final l = await Repo.logs(_from, _to, category: _cat, query: _q);
    if (!mounted) return;
    setState(() {
      _list = l;
      _loading = false;
    });
  }

  (IconData, Color) _style(ActivityLog l) {
    final a = l.action.toLowerCase();
    if (a.contains('hapus')) return (Icons.delete_forever_rounded, Colors.red);
    switch (l.category) {
      case 'akses':
        return (a.contains('logout') ? Icons.logout_rounded : Icons.login_rounded, Colors.blueGrey);
      case 'penjualan':
        return (Icons.point_of_sale_rounded, Colors.green);
      case 'menu':
        return (Icons.restaurant_menu_rounded, Colors.orange);
      case 'pengeluaran':
        return (Icons.account_balance_wallet_rounded, Colors.pink);
      case 'pengguna':
        return (Icons.manage_accounts_rounded, Colors.indigo);
      case 'pengaturan':
        return (Icons.settings_rounded, Colors.teal);
      case 'data':
        return (Icons.storage_rounded, Colors.deepPurple);
      default:
        return (Icons.history_rounded, Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String? lastDay;
    final children = <Widget>[];
    for (final l in _list) {
      final day = dbDay(l.createdAt);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(fmtDayName(l.createdAt),
              style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary, fontSize: 13)),
        ));
      }
      final st = _style(l);
      children.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SoftCard(
          padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 18, backgroundColor: st.$2.withOpacity(0.15), child: Icon(st.$1, color: st.$2, size: 18)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(l.action, style: const TextStyle(fontWeight: FontWeight.w700))),
                        Text(fmtTime(l.createdAt), style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                    if (l.detail.isNotEmpty) Text(l.detail, style: TextStyle(fontSize: 12.5, color: cs.onSurface.withOpacity(0.85))),
                    Text(l.userName.isEmpty ? '-' : l.userName, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Log Aktivitas')),
      body: Column(
        children: [
          PeriodPicker(
            from: _from,
            to: _to,
            onChanged: (f, t) {
              _from = f;
              _to = t;
              _load();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                _q = v;
                _load();
              },
              onChanged: (v) {
                if (v.isEmpty && _q.isNotEmpty) {
                  _q = '';
                  _load();
                }
              },
              decoration: InputDecoration(
                hintText: 'Cari (nama, no nota, menu...) lalu tekan enter',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: cs.surfaceContainerHighest.withOpacity(0.5),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                for (final e in _cats.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: _cat == e.key,
                      onSelected: (_) {
                        _cat = e.key;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _list.isEmpty
                    ? const EmptyState(icon: Icons.history_rounded, title: 'Tidak ada aktivitas', subtitle: 'Coba ubah periode atau filter')
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: children),
                      ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cart_state.dart';
import '../db/database.dart';
import '../widgets/common.dart';
import 'expense_screen.dart';
import 'login_screen.dart';
import 'menu_screen.dart';
import 'pos_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';

class _Tab {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final Widget Function() build;
  _Tab(this.label, this.icon, this.activeIcon, this.build);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

Future<void> doLogout(BuildContext context) async {
  final cart = context.read<CartState>();
  final ok = await confirmDialog(
    context,
    title: 'Keluar?',
    message: cart.isEmpty
        ? 'Anda akan keluar dari akun ini.'
        : 'Masih ada pesanan di keranjang yang belum dibayar dan akan dihapus. Simpan pesanan dulu bila perlu.',
    okText: 'Keluar',
    danger: !cart.isEmpty,
    icon: Icons.logout_rounded,
  );
  if (!ok || !context.mounted) return;
  await Activity.log('akses', 'Logout');
  if (!context.mounted) return;
  context.read<AppState>().setUser(null);
  cart.clear();
  Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  List<_Tab> _tabs(AppState app) => [
        _Tab('Penjualan', Icons.point_of_sale_outlined, Icons.point_of_sale_rounded, () => const PosScreen()),
        if (app.can('menu')) _Tab('Menu', Icons.restaurant_menu_outlined, Icons.restaurant_menu_rounded, () => const MenuScreen()),
        if (app.can('expense'))
          _Tab('Pengeluaran', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, () => const ExpenseScreen()),
        if (app.can('report')) _Tab('Laporan', Icons.insert_chart_outlined_rounded, Icons.insert_chart_rounded, () => const ReportScreen()),
        _Tab('Pengaturan', Icons.settings_outlined, Icons.settings_rounded, () => const SettingsScreen()),
      ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tabs = _tabs(app);
    if (_index >= tabs.length) _index = 0;
    final tablet = app.isTablet(context);
    final page = KeyedSubtree(key: ValueKey(tabs[_index].label), child: tabs[_index].build());
    final cs = Theme.of(context).colorScheme;

    if (tablet) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideNav(
                tabs: tabs,
                index: _index,
                onTap: (i) => setState(() => _index = i),
                header: _Avatar(app: app),
                onLogout: () => doLogout(context),
              ),
              VerticalDivider(width: 1, color: cs.outlineVariant.withOpacity(0.5)),
              Expanded(child: page),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: page,
      bottomNavigationBar: _BottomNav(tabs: tabs, index: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}

/// Item navigasi: ikon dalam "pil" + label yang mengecil otomatis (tidak terpotong)
class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;
  final double labelSize;
  const _NavItem({required this.tab, required this.selected, required this.onTap, this.labelSize = 12});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(selected ? tab.activeIcon : tab.icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                tab.label,
                maxLines: 1,
                softWrap: false,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontSize: labelSize,
                  color: color,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.tabs, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainer,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(child: _NavItem(tab: tabs[i], selected: i == index, onTap: () => onTap(i))),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final List<_Tab> tabs;
  final int index;
  final ValueChanged<int> onTap;
  final Widget header;
  final VoidCallback onLogout;
  const _SideNav({required this.tabs, required this.index, required this.onTap, required this.header, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 100,
      color: cs.surfaceContainerLow,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          children: [
            header,
            const SizedBox(height: 16),
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _NavItem(tab: tabs[i], selected: i == index, onTap: () => onTap(i), labelSize: 12.5),
              ),
            const SizedBox(height: 10),
            IconButton.filledTonal(tooltip: 'Keluar', onPressed: onLogout, icon: const Icon(Icons.logout_rounded)),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final AppState app;
  const _Avatar({required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final logo = app.logo;
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: logo != null
              ? Image.memory(logo, fit: BoxFit.cover, gaplessPlayback: true)
              : Icon(Icons.restaurant_rounded, color: cs.onPrimaryContainer),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 72,
          child: Text(app.user?.name ?? '',
              textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
        ),
      ],
    );
  }
}

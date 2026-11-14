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
              LayoutBuilder(
                builder: (context, cons) => SingleChildScrollView(
                  child: SizedBox(
                    height: cons.maxHeight < 600 ? 600 : cons.maxHeight,
                    child: Material(
                      color: Colors.transparent,
                      child: NavigationRail(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                labelType: NavigationRailLabelType.all,
                backgroundColor: cs.surfaceContainerLow,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _Avatar(app: app),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: IconButton.filledTonal(
                    tooltip: 'Keluar',
                    onPressed: () => doLogout(context),
                    icon: const Icon(Icons.logout_rounded),
                  ),
                ),
                destinations: [
                  for (final t in tabs)
                    NavigationRailDestination(icon: Icon(t.icon), selectedIcon: Icon(t.activeIcon), label: Text(t.label)),
                ],
                      ),
                    ),
                  ),
                ),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        height: 66,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.activeIcon), label: t.label),
        ],
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

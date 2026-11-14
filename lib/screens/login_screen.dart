import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../cart_state.dart';
import '../db/database.dart';
import '../models.dart';
import '../services/backup.dart';
import '../utils/notify.dart';
import 'home_shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _loading = false;
  String _status = '';
  List<AppUser> _users = [];

  @override
  void initState() {
    super.initState();
    _loadUsers();
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstRunInfo());
  }

  Future<void> _loadUsers() async {
    final u = await Repo.users(onlyActive: true);
    if (!mounted) return;
    setState(() {
      _users = u;
      if (_user.text.isEmpty && u.length == 1) _user.text = u.first.username;
    });
  }

  Future<void> _firstRunInfo() async {
    final app = context.read<AppState>();
    if (app.get('first_run_shown') == '1') return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.key_rounded, size: 40, color: cs.primary),
          title: const Text('Akun Awal', textAlign: TextAlign.center),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Gunakan akun berikut untuk login pertama kali:', textAlign: TextAlign.center),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    Text('Username', style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12)),
                    Text(kDefaultUsername,
                        style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 20)),
                    const SizedBox(height: 8),
                    Text('Password', style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12)),
                    SelectableText(kDefaultPassword,
                        style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: 20)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text('Pesan ini hanya muncul 1 kali. Segera ganti password di menu Pengaturan.',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.error, fontSize: 12)),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Saya Mengerti'),
            ),
          ],
        );
      },
    );
    await app.set('first_run_shown', '1');
    if (!mounted) return;
    if (_user.text.isEmpty) _user.text = kDefaultUsername;
    _passFocus.requestFocus();
  }

  Future<void> _login() async {
    if (_loading) return;
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      Notify.warning('Username dan password wajib diisi');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Memeriksa akun...';
    });
    final app = context.read<AppState>();
    final cart = context.read<CartState>();
    try {
      final user = await Repo.login(u, p);
      if (user == null) {
        Notify.error('Username atau password salah');
        return;
      }
      app.setUser(user);
      cart.clear();
      if (mounted) setState(() => _status = 'Membuat backup otomatis...');
      await Activity.log('akses', 'Login', user.isOwner ? 'Owner' : 'Kasir');
      final r = await BackupService.run(app);
      await Activity.log('data', r.ok ? 'Backup otomatis' : 'Backup otomatis gagal', r.ok ? 'Slot ${r.slot}/3' : (r.error ?? ''));
      if (r.ok) {
        Notify.success('Selamat datang, ${user.name}! Backup otomatis tersimpan (${r.slot}/3)');
      } else {
        Notify.warning('Login berhasil, tetapi backup gagal: ${r.error}');
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    } catch (e) {
      Notify.error('Gagal login: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = '';
        });
      }
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final logo = app.logo;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primary, Color.lerp(cs.primary, cs.tertiary, 0.6)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logo != null
                          ? Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true)
                          : Icon(Icons.restaurant_menu_rounded, size: 52, color: cs.primary),
                    ),
                    const SizedBox(height: 16),
                    Text(app.get('store_name'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Aplikasi Kasir', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 24, offset: Offset(0, 10))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text('Masuk', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 16),
                          if (_users.length > 1) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final u in _users)
                                  ChoiceChip(
                                    avatar: Icon(u.isOwner ? Icons.workspace_premium_rounded : Icons.person_rounded, size: 18),
                                    label: Text(u.name),
                                    selected: _user.text.trim().toLowerCase() == u.username,
                                    onSelected: (_) {
                                      setState(() => _user.text = u.username);
                                      _passFocus.requestFocus();
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextField(
                            controller: _user,
                            textInputAction: TextInputAction.next,
                            onSubmitted: (_) => _passFocus.requestFocus(),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: 'Username',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass,
                            focusNode: _passFocus,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _loading ? null : _login,
                              icon: _loading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                                  : const Icon(Icons.login_rounded),
                              label: Text(_loading ? _status : 'MASUK', style: const TextStyle(fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Backup otomatis berjalan setiap login', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

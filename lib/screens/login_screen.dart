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
  }

  Future<void> _loadUsers() async {
    final u = await Repo.users(onlyActive: true);
    if (!mounted) return;
    setState(() => _users = u);
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
                    // Logo persegi panjang besar
                    Container(
                      width: double.infinity,
                      height: logo != null ? 150 : 120,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 8))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: logo != null
                          ? Image.memory(logo, fit: BoxFit.contain, gaplessPlayback: true)
                          : Icon(Icons.restaurant_menu_rounded, size: 64, color: cs.primary),
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

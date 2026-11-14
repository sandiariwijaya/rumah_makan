import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../db/database.dart';
import '../utils/notify.dart';
import 'login_screen.dart';

/// Hash kode aktivasi (user + password) — nilai asli tidak disimpan di aplikasi.
const String _kActivationHash = 'de8910433d7d29231a3e001a86d501a9c2be322376e6c6192b62ca3e553aa44a';

bool checkActivation(String user, String password) {
  final h = sha256.convert(utf8.encode('aktivasiRM::${user.trim().toLowerCase()}::$password')).toString();
  return h == _kActivationHash;
}

/// Layar aktivasi — muncul sekali setelah aplikasi pertama kali diinstal.
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _obscure = true;
  bool _busy = false;
  int _fails = 0;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    if (_busy) return;
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      Notify.warning('Isi user dan password aktivasi');
      return;
    }
    if (_fails >= 5) {
      Notify.error('Terlalu banyak percobaan. Tutup lalu buka kembali aplikasi.');
      return;
    }
    setState(() => _busy = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!checkActivation(_user.text, _pass.text)) {
      _fails++;
      if (mounted) setState(() => _busy = false);
      Notify.error('Kode aktivasi salah');
      return;
    }
    final app = context.read<AppState>();
    await app.setMany({'activated': '1', 'activated_at': DateTime.now().toIso8601String()});
    Activity.user = 'Sistem';
    await Activity.log('akses', 'Aktivasi aplikasi');
    Activity.user = '';
    Notify.success('Aplikasi berhasil diaktifkan');
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                      padding: const EdgeInsets.all(18),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(Icons.verified_user_rounded, size: 54, color: cs.primary),
                    ),
                    const SizedBox(height: 16),
                    const Text('Aktivasi Aplikasi',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    const Text('Masukkan kode aktivasi dari pembuat aplikasi',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: cs.surface, borderRadius: BorderRadius.circular(24)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _user,
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            onSubmitted: (_) => _passFocus.requestFocus(),
                            decoration: InputDecoration(
                              labelText: 'User aktivasi',
                              prefixIcon: const Icon(Icons.person_outline_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _pass,
                            focusNode: _passFocus,
                            obscureText: _obscure,
                            onSubmitted: (_) => _activate(),
                            decoration: InputDecoration(
                              labelText: 'Password aktivasi',
                              prefixIcon: const Icon(Icons.key_rounded),
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
                              onPressed: _busy ? null : _activate,
                              icon: _busy
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4))
                                  : const Icon(Icons.lock_open_rounded),
                              label: const Text('AKTIFKAN', style: TextStyle(fontWeight: FontWeight.w800)),
                              style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                            ),
                          ),
                        ],
                      ),
                    ),
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

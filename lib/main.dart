import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'cart_state.dart';
import 'screens/activation_screen.dart';
import 'screens/login_screen.dart';
import 'utils/notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  final app = AppState();
  await app.load();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<CartState>(create: (_) => CartState()),
      ],
      child: const KasirApp(),
    ),
  );
}

ThemeData buildTheme(Color seed, Brightness brightness) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    brightness: brightness,
    visualDensity: VisualDensity.standard,
    scaffoldBackgroundColor: brightness == Brightness.light ? const Color(0xFFF6F7FB) : cs.surface,
  );
}

class KasirApp extends StatelessWidget {
  const KasirApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: 'Kasir Rumah Makan',
      debugShowCheckedModeBanner: false,
      navigatorKey: Notify.navKey,
      theme: buildTheme(app.seedColor, Brightness.light),
      darkTheme: buildTheme(app.seedColor, Brightness.dark),
      themeMode: app.themeMode,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(app.textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: app.get('activated') == '1' ? const LoginScreen() : const ActivationScreen(),
    );
  }
}

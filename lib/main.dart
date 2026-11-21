import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'config.dart';
import 'db/database.dart';
import 'screens/activation_screen.dart';
import 'screens/login_screen.dart';
import 'services/activation.dart';
import 'utils/notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  Intl.defaultLocale = 'id_ID';
  final app = AppState();
  await app.load();
  final active = await Activation.isActive();
  final hasUser = await Repo.userCount() > 0;
  runApp(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: TokoApp(start: !active ? const ActivationScreen() : (hasUser ? const LoginScreen() : const SetupOwnerScreen())),
    ),
  );
}

ThemeData buildTheme(Color seed, Brightness brightness) {
  final cs = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  final light = brightness == Brightness.light;
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    brightness: brightness,
    scaffoldBackgroundColor: light ? const Color(0xFFF5F7FB) : cs.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: light ? const Color(0xFFF5F7FB) : cs.surface,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: cs.outlineVariant.withOpacity(0.4))),
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : cs.surfaceContainerHighest.withOpacity(0.3),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 66,
      backgroundColor: light ? Colors.white : cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
    ),
  );
}

class TokoApp extends StatelessWidget {
  final Widget start;
  const TokoApp({super.key, required this.start});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return MaterialApp(
      title: AppConfig.appName,
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
      home: start,
    );
  }
}

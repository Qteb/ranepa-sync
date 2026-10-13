import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/background.dart';
import 'services/home_widget_bridge.dart';
import 'services/lesson_links.dart';
import 'services/notifications.dart';
import 'services/tips.dart';

// Бордовый в цвет фирменного стиля академии.
const _seed = Color(0xFF8E1B2E);

/// Акцент для Cupertino-виджетов: в тёмной теме светлее, иначе тонет в фоне.
const accent = CupertinoDynamicColor.withBrightness(
  color: _seed,
  darkColor: Color(0xFFE5737F),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  await HomeWidget.setAppGroupId(appGroupId);
  await initNotifications();
  await initBackground();
  final prefs = await SharedPreferences.getInstance();
  Tips.instance.init(prefs);
  await initLessonLinks();
  await openLaunchNotification();
  final state = AppState(prefs);
  // Задача могла не зарегистрироваться (обновление со старой версии).
  if (state.loggedIn && !state.demo) unawaited(scheduleBackgroundRefresh());
  runApp(RanepaApp(state: state));
}

class RanepaApp extends StatelessWidget {
  const RanepaApp({super.key, required this.state});

  final AppState state;

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
    useMaterial3: true,
    cupertinoOverrideTheme: const CupertinoThemeData(
      primaryColor: accent,
      scaffoldBackgroundColor: CupertinoColors.systemBackground,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'Расписание студента',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: state.themeMode,
        locale: const Locale('ru'),
        supportedLocales: const [Locale('ru')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        // Экраны свёрстаны на Cupertino-виджетах внутри MaterialApp: задаём
        // им стиль текста iOS (иначе Flutter подчёркивает текст жёлтым) и
        // цвет строки состояния по теме приложения, а не системы.
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark,
            child: DefaultTextStyle(
              style: CupertinoTheme.of(context).textTheme.textStyle,
              // Крупный шрифт из настроек iOS, но не больше ×2: дальше
              // названия пар рвутся по слогам на каждой строке.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 2,
                child: child!,
              ),
            ),
          );
        },
        home: state.loggedIn
            ? HomeScreen(key: const ValueKey('home'), state: state)
            : AuthFlow(key: const ValueKey('auth'), state: state),
      ),
    );
  }
}

/// Стартовый экран → вход в ЛК. Без Navigator.push: после входа MaterialApp
/// сам заменит этот виджет на расписание, и ничего не останется в стеке.
class AuthFlow extends StatefulWidget {
  const AuthFlow({super.key, required this.state});

  final AppState state;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  bool _login = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_login,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _login = false);
      },
      child: _login
          ? LoginScreen(
              state: widget.state,
              onBack: () => setState(() => _login = false),
            )
          : OnboardingScreen(
              error: widget.state.error,
              onLogin: () => setState(() => _login = true),
              onDemo: widget.state.startDemo,
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/storage/storage_service.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/domain/providers.dart';
import 'features/home/presentation/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // System UI
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0A0A0A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Init preferences
  await PreferencesService().init();

  runApp(const ProviderScope(child: SlixTvApp()));
}

class SlixTvApp extends StatelessWidget {
  const SlixTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const _AppNavigator(),
    );
  }
}

/// Top-level navigator that handles auth state transitions.
class _AppNavigator extends ConsumerStatefulWidget {
  const _AppNavigator();

  @override
  ConsumerState<_AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends ConsumerState<_AppNavigator> {
  _Screen _currentScreen = _Screen.splash;

  @override
  Widget build(BuildContext context) {
    // Listen to auth state changes
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated && _currentScreen != _Screen.main) {
        setState(() => _currentScreen = _Screen.main);
      }
    });

    switch (_currentScreen) {
      case _Screen.splash:
        return SplashScreen(
          onAuthenticated: () => setState(() => _currentScreen = _Screen.main),
          onUnauthenticated: () => setState(() => _currentScreen = _Screen.login),
        );
      case _Screen.login:
        return const LoginScreen();
      case _Screen.main:
        return AppShell(
          onLogout: () => setState(() => _currentScreen = _Screen.login),
        );
    }
  }
}

enum _Screen { splash, login, main }

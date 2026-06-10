import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'core/storage/storage_service.dart';
import 'features/auth/presentation/splash_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/auth/domain/providers.dart';
import 'features/home/presentation/app_shell.dart';
import 'core/widgets/remote_config_wrapper.dart';

import 'core/constants/app_colors.dart';
import 'features/auth/data/models.dart' show Channel, Category;
import 'features/movies/domain/models.dart' show VodItem;
import 'features/series/domain/models.dart' show SeriesItem;
import 'features/movies/presentation/movie_detail_screen.dart';
import 'features/series/presentation/series_screen.dart';
import 'features/player/presentation/player_screen.dart';
import 'core/widgets/parental_pin_dialog.dart';
import 'features/home/presentation/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // Force Landscape Orientation (Horizontal Layout)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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
      builder: (context, child) => RemoteConfigWrapper(child: child!),
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

  void _onChannelTap(Channel channel) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(tvCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == channel.categoryId,
        orElse: () => Category(id: channel.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: channel.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
    _navigateToLivePlayer(channel);
  }

  Future<void> _navigateToLivePlayer(Channel channel) async {
    _showLoadingDialog();
    try {
      final api = ref.read(stalkerApiProvider);
      final streamUrl = await api.createLink(channel.cmd, 'itv');
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading
      _openPlayer(streamUrl, channel.name, contentId: 'ch_${channel.id}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      _showError('Failed to load channel: ${_cleanError(e)}');
    }
  }

  void _onMovieTap(VodItem movie) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(vodCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == movie.categoryId,
        orElse: () => Category(id: movie.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: movie.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MovieDetailScreen(movie: movie),
    ));
  }

  void _onSeriesTap(SeriesItem series) async {
    final lockState = ref.read(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      final categories = ref.read(seriesCategoriesProvider).value ?? [];
      final category = categories.firstWhere(
        (c) => c.id == series.categoryId,
        orElse: () => Category(id: series.categoryId, title: ''),
      );
      if (isAdultContent(categoryName: category.title, itemName: series.name)) {
        final authenticated = await ParentalPinDialog.show(context);
        if (!authenticated) return;
      }
    }
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(series: series),
    ));
  }

  void _openPlayer(String streamUrl, String title, {String? subtitle, String? contentId}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PlayerScreen(
        streamUrl: streamUrl,
        title: title,
        subtitle: subtitle,
        contentId: contentId,
      ),
    ));
  }

  void _showLoadingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanError(dynamic e) =>
      e.toString().replaceAll('Exception: ', '').replaceAll('Exception:', '');

  @override
  Widget build(BuildContext context) {
    // Listen to auth state changes
    ref.listen<AuthState>(authProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated && _currentScreen != _Screen.main) {
        setState(() => _currentScreen = _Screen.main);
      }
    });

    final Widget activeScreen;
    switch (_currentScreen) {
      case _Screen.splash:
        activeScreen = SplashScreen(
          onAuthenticated: () => setState(() => _currentScreen = _Screen.main),
          onUnauthenticated: () => setState(() => _currentScreen = _Screen.login),
        );
        break;
      case _Screen.login:
        activeScreen = const LoginScreen();
        break;
      case _Screen.main:
        activeScreen = HomeScreen(
          onLogout: () => setState(() => _currentScreen = _Screen.login),
          onChannelTap: _onChannelTap,
          onMovieTap: _onMovieTap,
          onSeriesTap: _onSeriesTap,
        );
        break;
    }

    return activeScreen;
  }
}

enum _Screen { splash, login, main }


import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/stalker_api_service.dart';
import '../data/models.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../movies/data/movies_service.dart';
import '../../series/data/series_service.dart';
import '../../movies/domain/models.dart' as vod_models;
import '../../series/domain/models.dart' as series_models;

import '../../../core/errors/exceptions.dart';

// ─── Services ──────────────────────────────────────────────

// Single shared singleton so login session is visible to content providers
final _sharedApiService = StalkerApiService();

final stalkerApiProvider = Provider<StalkerApiService>((ref) {
  return _sharedApiService;
});

final apiClientProvider = Provider<ApiClient>((ref) => _sharedApiService.client);

final moviesServiceProvider = Provider<MoviesService>((ref) {
  return MoviesService(
    ref.watch(apiClientProvider),
  );
});

final seriesServiceProvider = Provider<SeriesService>((ref) {
  return SeriesService(
    ref.watch(apiClientProvider),
  );
});

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final preferencesProvider = Provider<PreferencesService>((ref) {
  return PreferencesService();
});

final loggerProvider = Provider<AppLogger>((ref) {
  return AppLogger();
});

// ─── Auth State ────────────────────────────────────────────

enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final String? portalUrl;
  final String? macAddress;
  final String? token;
  final StalkerProfile? profile;
  final StalkerMainInfo? mainInfo;
  final String? errorMessage;
  final bool rememberMe;
  final bool sessionReady;

  const AuthState({
    this.status = AuthStatus.initial,
    this.portalUrl,
    this.macAddress,
    this.token,
    this.profile,
    this.mainInfo,
    this.errorMessage,
    this.rememberMe = false,
    this.sessionReady = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? portalUrl,
    String? macAddress,
    String? token,
    StalkerProfile? profile,
    StalkerMainInfo? mainInfo,
    String? errorMessage,
    bool? rememberMe,
    bool? sessionReady,
  }) {
    return AuthState(
      status: status ?? this.status,
      portalUrl: portalUrl ?? this.portalUrl,
      macAddress: macAddress ?? this.macAddress,
      token: token ?? this.token,
      profile: profile ?? this.profile,
      mainInfo: mainInfo ?? this.mainInfo,
      errorMessage: errorMessage,
      rememberMe: rememberMe ?? this.rememberMe,
      sessionReady: sessionReady ?? this.sessionReady,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StalkerApiService _api;
  final SecureStorageService _storage;
  final AppLogger _logger;

  AuthNotifier(this._api, this._storage, this._logger)
      : super(const AuthState());

  /// Try restoring a saved session.
  Future<bool> tryRestoreSession() async {
    _logger.i('AUTH', 'Attempting native session restore');
    state = state.copyWith(status: AuthStatus.loading, sessionReady: false);

    try {
      final creds = await _storage.getPortalCredentials();
      final portalUrl = creds['portalUrl'];
      final macAddress = creds['macAddress'];

      if (portalUrl == null || macAddress == null) {
        _logger.i('AUTH', 'No saved credentials found');
        state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
        return false;
      }

      state = state.copyWith(
        portalUrl: portalUrl,
        macAddress: macAddress,
      );

      _logger.i('AUTH', 'Starting native handshake for session restore...');
      final token = await _api.handshake(portalUrl, macAddress);
      final profile = await _api.getProfile();

      StalkerMainInfo? mainInfo;
      try {
        mainInfo = await _api.getMainInfo();
      } catch (_) {
        _logger.w('AUTH', 'getMainInfo failed during session restore (ignored)');
      }

      state = state.copyWith(
        status: AuthStatus.authenticated,
        portalUrl: portalUrl,
        macAddress: macAddress,
        token: token,
        profile: profile,
        mainInfo: mainInfo,
        rememberMe: true,
        sessionReady: true,
      );
      _logger.i('AUTH', 'Session restored successfully natively');
      return true;
    } catch (e) {
      _logger.e('AUTH', 'Session restore failed', error: e);
      state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
      return false;
    }
  }

  /// Login with portal URL and MAC address.
  Future<void> login(String portalUrl, String macAddress, {bool rememberMe = false}) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
      portalUrl: portalUrl,
      macAddress: macAddress,
      sessionReady: false,
    );

    try {
      _logger.i('AUTH', 'Starting native login flow');
      
      final token = await _api.handshake(portalUrl, macAddress);
      final profile = await _api.getProfile();
      
      // profile.status == false means the server returned blocked=1 or status=1
      if (!profile.status) {
        throw const AuthException(
          message: 'MAC address not registered or subscription is blocked.\n'
              'Please check your MAC address or contact your IPTV provider.',
        );
      }
      
      StalkerMainInfo? mainInfo;
      try {
        mainInfo = await _api.getMainInfo();
      } catch (_) {
        _logger.w('AUTH', 'getMainInfo failed during login (ignored)');
      }

      await _storage.savePortalCredentials(
        portalUrl: portalUrl,
        macAddress: macAddress,
      );
      await _storage.saveToken(token);
      await _storage.setRememberMe(rememberMe);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        token: token,
        profile: profile,
        mainInfo: mainInfo,
        rememberMe: rememberMe,
        sessionReady: true,
      );
      _logger.i('AUTH', 'Login successful & session ready (native)');
    } catch (e) {
      _logger.e('AUTH', 'Login failed', error: e);
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _getErrorMessage(e),
        sessionReady: false,
      );
    }
  }

  Future<void> logout() async {
    _api.logout();
    await _storage.clearSession();
    await _storage.setRememberMe(false);
    state = const AuthState(status: AuthStatus.unauthenticated, sessionReady: false);
    _logger.i('AUTH', 'Logged out');
  }

  String _getErrorMessage(dynamic error) {
    final msg = error.toString();
    if (msg.contains('not registered on this portal') || msg.contains('Authentication request')) {
      return 'MAC address not registered.\nCheck your MAC or contact your IPTV provider.';
    }
    if (msg.contains('blocked or expired') || msg.contains('Subscription')) {
      return 'Subscription blocked or expired.\nContact your IPTV provider.';
    }
    if (msg.contains('timeout')) return 'Connection timed out. Check portal URL.';
    if (msg.contains('Cannot reach')) return 'Server unreachable. Check your connection.';
    if (msg.contains('Handshake failed')) return 'Portal handshake failed. Verify URL and MAC.';
    if (msg.contains('Empty token')) return 'Invalid response from portal.';
    if (msg.contains('Rate limited')) return 'Too many requests. Wait a moment and try again.';
    return 'Authentication failed: ${error.toString().replaceAll('Exception: ', '')}';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(stalkerApiProvider),
    ref.watch(secureStorageProvider),
    ref.watch(loggerProvider),
  );
});

// ─── Content Providers ─────────────────────────────────────
// All content providers watch auth state's sessionReady flag to ensure
// they don't start requesting content prematurely.

// Live TV categories
final tvCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  final api = ref.watch(stalkerApiProvider);
  return api.getCategories('itv');
});

// All channels
final allChannelsProvider = FutureProvider<List<Channel>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  final api = ref.watch(stalkerApiProvider);
  return api.getAllChannels();
});

// Channels by category
final channelsByCategoryProvider = FutureProvider.family<List<Channel>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  final api = ref.watch(stalkerApiProvider);
  return api.getChannels(categoryId: categoryId);
});

// VOD categories
final vodCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  return ref.watch(moviesServiceProvider).getCategories();
});

// Movies
final moviesProvider = FutureProvider.family<List<vod_models.VodItem>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  return ref.watch(moviesServiceProvider).getOrderedList(categoryId: categoryId);
});

// Series categories
final seriesCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  return ref.watch(seriesServiceProvider).getCategories();
});

// Series
final seriesProvider = FutureProvider.family<List<series_models.SeriesItem>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  return ref.watch(seriesServiceProvider).getOrderedList(categoryId: categoryId);
});

// Series Info (seasons/episodes)
final seriesInfoProvider = FutureProvider.family<List<series_models.Season>, String>((ref, seriesId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  return ref.watch(seriesServiceProvider).getSeriesInfo(seriesId);
});

// EPG for a channel
final epgProvider = FutureProvider.family<List<EpgProgram>, String>((ref, channelId) async {
  final authState = ref.watch(authProvider);
  if (authState.status != AuthStatus.authenticated) return [];
  final api = ref.watch(stalkerApiProvider);
  return api.getEpg(channelId);
});

// Stream URL resolver
final streamUrlProvider = FutureProvider.family<String, ({String cmd, String type})>((ref, params) async {
  final api = ref.watch(stalkerApiProvider);
  return api.createLink(params.cmd, params.type);
});

// VOD item detailed info (synopsis, cast, etc.)
final vodInfoProvider = FutureProvider.family<vod_models.VodItem?, vod_models.VodItem>((ref, item) async {
  final authState = ref.watch(authProvider);
  if (authState.status != AuthStatus.authenticated) return null;
  return ref.watch(moviesServiceProvider).getVodInfo(item);
});

// ─── Favorites ─────────────────────────────────────────────

class FavoritesNotifier extends StateNotifier<Map<String, Set<String>>> {
  final PreferencesService _prefs;

  FavoritesNotifier(this._prefs) : super({
    'channels': {},
    'movies': {},
    'series': {},
  }) {
    _loadFavorites();
  }

  void _loadFavorites() {
    state = {
      'channels': _prefs.getFavorites('channels').toSet(),
      'movies': _prefs.getFavorites('movies').toSet(),
      'series': _prefs.getFavorites('series').toSet(),
    };
  }

  bool isFavorite(String type, String id) {
    return state[type]?.contains(id) ?? false;
  }

  Future<void> toggleFavorite(String type, String id) async {
    final current = Map<String, Set<String>>.from(state);
    final set = Set<String>.from(current[type] ?? {});

    if (set.contains(id)) {
      set.remove(id);
    } else {
      set.add(id);
    }

    current[type] = set;
    state = current;
    await _prefs.saveFavorites(type, set.toList());
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Map<String, Set<String>>>((ref) {
  return FavoritesNotifier(ref.watch(preferencesProvider));
});

// ─── Search ────────────────────────────────────────────────

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider<Map<String, List<dynamic>>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().length < 2) return {'channels': [], 'movies': [], 'series': []};

  final api = ref.watch(stalkerApiProvider);
  final lowerQuery = query.toLowerCase();

  // Search across all content types
  final results = <String, List<dynamic>>{};

  try {
    final channels = await api.getAllChannels();
    results['channels'] = channels
        .where((c) => c.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();
  } catch (_) {
    results['channels'] = [];
  }

  try {
    final moviesService = ref.read(moviesServiceProvider);
    final movies = await moviesService.getOrderedList();
    results['movies'] = movies
        .where((m) => m.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();
  } catch (_) {
    results['movies'] = [];
  }

  try {
    final seriesService = ref.read(seriesServiceProvider);
    final series = await seriesService.getOrderedList();
    results['series'] = series
        .where((s) => s.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();
  } catch (_) {
    results['series'] = [];
  }

  return results;
});

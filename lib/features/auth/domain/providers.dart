
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../data/stalker_api_service.dart';
import '../data/xtream_api_service.dart';
import '../data/models.dart';
import '../../../core/storage/storage_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../movies/data/movies_service.dart';
import '../../series/data/series_service.dart';
import '../../../core/network/opensubtitles_service.dart';
import '../../movies/domain/models.dart' as vod_models;
import '../../series/domain/models.dart' as series_models;

import '../../../core/errors/exceptions.dart';

// ─── Services ──────────────────────────────────────────────

// Single shared singleton so login session is visible to content providers
final _sharedApiService = StalkerApiService();
final _sharedXtreamApiService = XtreamApiService();

final stalkerApiProvider = Provider<StalkerApiService>((ref) {
  return _sharedApiService;
});

final xtreamApiProvider = Provider<XtreamApiService>((ref) {
  return _sharedXtreamApiService;
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

final opensubtitlesServiceProvider = Provider<OpenSubtitlesService>((ref) {
  return OpenSubtitlesService();
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
  final String authType; // 'stalker' or 'xtream'
  final String? portalUrl;
  final String? macAddress;
  final String? token;
  final StalkerProfile? profile;
  final StalkerMainInfo? mainInfo;
  final String? errorMessage;
  final bool rememberMe;
  final bool sessionReady;
  final Map<String, dynamic>? xtreamUserInfo;

  const AuthState({
    this.status = AuthStatus.initial,
    this.authType = 'stalker',
    this.portalUrl,
    this.macAddress,
    this.token,
    this.profile,
    this.mainInfo,
    this.errorMessage,
    this.rememberMe = false,
    this.sessionReady = false,
    this.xtreamUserInfo,
  });

  AuthState copyWith({
    AuthStatus? status,
    String? authType,
    String? portalUrl,
    String? macAddress,
    String? token,
    StalkerProfile? profile,
    StalkerMainInfo? mainInfo,
    String? errorMessage,
    bool? rememberMe,
    bool? sessionReady,
    Map<String, dynamic>? xtreamUserInfo,
  }) {
    return AuthState(
      status: status ?? this.status,
      authType: authType ?? this.authType,
      portalUrl: portalUrl ?? this.portalUrl,
      macAddress: macAddress ?? this.macAddress,
      token: token ?? this.token,
      profile: profile ?? this.profile,
      mainInfo: mainInfo ?? this.mainInfo,
      errorMessage: errorMessage,
      rememberMe: rememberMe ?? this.rememberMe,
      sessionReady: sessionReady ?? this.sessionReady,
      xtreamUserInfo: xtreamUserInfo ?? this.xtreamUserInfo,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final StalkerApiService _api;
  final XtreamApiService _xtreamApi;
  final SecureStorageService _storage;
  final AppLogger _logger;

  AuthNotifier(this._api, this._xtreamApi, this._storage, this._logger)
      : super(const AuthState()) {
    // Proactively restore session
    tryRestoreSession();
  }

  /// Try restoring a saved session.
  Future<bool> tryRestoreSession() async {
    _logger.i('AUTH', 'Attempting native session restore');
    state = state.copyWith(status: AuthStatus.loading, sessionReady: false);

    try {
      final authType = await _storage.getAuthType();
      final rememberMe = await _storage.getRememberMe();
      if (!rememberMe) {
        _logger.i('AUTH', 'Remember me not checked, skipping auto-login');
        state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
        return false;
      }

      if (authType == 'xtream') {
        final creds = await _storage.getXtreamCredentials();
        final portalUrl = creds['portalUrl'];
        final username = creds['username'];
        final password = creds['password'];

        if (portalUrl == null || username == null || password == null) {
          _logger.i('AUTH', 'No saved Xtream credentials found');
          state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
          return false;
        }

        _logger.i('AUTH', 'Restoring Xtream session...');
        final loginRes = await _xtreamApi.login(portalUrl, username, password);
        _xtreamApi.configure(portalUrl: portalUrl, username: username, password: password);

        state = state.copyWith(
          status: AuthStatus.authenticated,
          authType: 'xtream',
          portalUrl: portalUrl,
          rememberMe: true,
          sessionReady: true,
          xtreamUserInfo: loginRes['user_info'],
        );
        _logger.i('AUTH', 'Xtream Session restored successfully');
        return true;
      } else {
        final creds = await _storage.getPortalCredentials();
        final portalUrl = creds['portalUrl'];
        final activePortalUrl = creds['activePortalUrl'] ?? portalUrl;
        final macAddress = creds['macAddress'];
        final stbModel = creds['stbModel'];
        final serialNumber = creds['serialNumber'];
        final timezone = creds['timezone'];
        final urlEncodeMacStr = creds['urlEncodeMac'];
        final urlEncodeMac = urlEncodeMacStr != null ? urlEncodeMacStr == 'true' : null;

        if (portalUrl == null || macAddress == null) {
          _logger.i('AUTH', 'No saved credentials found');
          state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
          return false;
        }

        state = state.copyWith(
          portalUrl: portalUrl,
          macAddress: macAddress,
          authType: 'stalker',
        );

        _logger.i('AUTH', 'Starting native handshake for session restore...');
        final token = await _api.handshake(
          activePortalUrl!,
          macAddress,
          stbModel: stbModel,
          serialNumber: serialNumber,
          timezone: timezone,
          urlEncodeMac: urlEncodeMac,
        );
        final profile = await _api.getProfile();

        StalkerMainInfo? mainInfo;
        try {
          mainInfo = await _api.getMainInfo();
        } catch (_) {
          _logger.w('AUTH', 'getMainInfo failed during session restore (ignored)');
        }

        state = state.copyWith(
          status: AuthStatus.authenticated,
          authType: 'stalker',
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
      }
    } catch (e) {
      if (e is StalkerRedirectException) {
        _logger.i('AUTH', 'Redirecting Stalker session restore to: ${e.redirectUrl}');
        final creds = await _storage.getPortalCredentials();
        final macAddress = creds['macAddress'] ?? '';
        final stbModel = creds['stbModel'];
        final serialNumber = creds['serialNumber'];
        final timezone = creds['timezone'];
        final urlEncodeMacStr = creds['urlEncodeMac'];
        final urlEncodeMac = urlEncodeMacStr != null ? urlEncodeMacStr == 'true' : null;

        await _storage.savePortalCredentials(
          portalUrl: creds['portalUrl'] ?? '',
          activePortalUrl: e.redirectUrl,
          macAddress: macAddress,
          stbModel: stbModel,
          serialNumber: serialNumber,
          timezone: timezone,
          urlEncodeMac: urlEncodeMac,
        );
        return tryRestoreSession();
      }
      _logger.e('AUTH', 'Session restore failed', error: e);
      state = state.copyWith(status: AuthStatus.unauthenticated, sessionReady: false);
      return false;
    }
  }

  /// Login with portal URL and MAC address.
  Future<void> login(
    String portalUrl,
    String macAddress, {
    bool rememberMe = false,
    String? stbModel,
    String? serialNumber,
    String? timezone,
    bool? urlEncodeMac,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
      portalUrl: portalUrl,
      macAddress: macAddress,
      sessionReady: false,
    );

    await _loginHelper(
      activeUrl: portalUrl,
      originalUrl: portalUrl,
      macAddress: macAddress,
      rememberMe: rememberMe,
      stbModel: stbModel,
      serialNumber: serialNumber,
      timezone: timezone,
      urlEncodeMac: urlEncodeMac,
    );
  }

  Future<void> _loginHelper({
    required String activeUrl,
    required String originalUrl,
    required String macAddress,
    required bool rememberMe,
    String? stbModel,
    String? serialNumber,
    String? timezone,
    bool? urlEncodeMac,
  }) async {
    try {
      _logger.i('AUTH', 'Starting Stalker login helper: active=$activeUrl, original=$originalUrl');
      
      final token = await _api.handshake(
        activeUrl,
        macAddress,
        stbModel: stbModel,
        serialNumber: serialNumber,
        timezone: timezone,
        urlEncodeMac: urlEncodeMac,
      );
      final profile = await _api.getProfile();
      
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
        portalUrl: originalUrl,
        activePortalUrl: activeUrl,
        macAddress: macAddress,
        stbModel: stbModel,
        serialNumber: serialNumber,
        timezone: timezone,
        urlEncodeMac: urlEncodeMac,
      );
      await _storage.saveAuthType('stalker');
      await _storage.saveToken(token);
      await _storage.setRememberMe(rememberMe);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        authType: 'stalker',
        portalUrl: originalUrl,
        token: token,
        profile: profile,
        mainInfo: mainInfo,
        rememberMe: rememberMe,
        sessionReady: true,
      );
      _logger.i('AUTH', 'Login successful & session ready (native)');
    } catch (e) {
      if (e is StalkerRedirectException) {
        // Detect redirect loops — compare by host to catch scheme/path variations
        final redirectUri = Uri.tryParse(e.redirectUrl);
        final activeUri = Uri.tryParse(activeUrl);
        final isSameHost = redirectUri != null && activeUri != null && 
            redirectUri.host.toLowerCase() == activeUri.host.toLowerCase();
        
        if (isSameHost || e.redirectUrl == activeUrl) {
          _logger.w('AUTH', 'Redirect loop detected: ${e.redirectUrl} ↔ $activeUrl');
          // Instead of showing error, try the redirect URL directly (once)
          // since it might have a different path that works
          if (e.redirectUrl != activeUrl) {
            _logger.i('AUTH', 'Same host redirect, trying with new path: ${e.redirectUrl}');
            try {
              // Clear the cached endpoint for this portal to force re-discovery
              await PreferencesService().clearEndpointCache(activeUrl);
              await PreferencesService().clearEndpointCache(e.redirectUrl);
            } catch (_) {}
            // Don't recurse — do a direct handshake attempt with the redirect URL
            try {
              final token = await _api.handshake(
                e.redirectUrl,
                macAddress,
                stbModel: stbModel,
                serialNumber: serialNumber,
                timezone: timezone,
                urlEncodeMac: urlEncodeMac,
              );
              final profile = await _api.getProfile();
              StalkerMainInfo? mainInfo;
              try { mainInfo = await _api.getMainInfo(); } catch (_) {}
              
              await _storage.savePortalCredentials(
                portalUrl: originalUrl,
                activePortalUrl: e.redirectUrl,
                macAddress: macAddress,
                stbModel: stbModel,
                serialNumber: serialNumber,
                timezone: timezone,
                urlEncodeMac: urlEncodeMac,
              );
              await _storage.saveAuthType('stalker');
              await _storage.saveToken(token);
              await _storage.setRememberMe(rememberMe);
              
              state = state.copyWith(
                status: AuthStatus.authenticated,
                authType: 'stalker',
                portalUrl: originalUrl,
                token: token,
                profile: profile,
                mainInfo: mainInfo,
                rememberMe: rememberMe,
                sessionReady: true,
              );
              _logger.i('AUTH', 'Login via redirect path successful');
              return;
            } catch (retryError) {
              _logger.e('AUTH', 'Redirect path also failed', error: retryError);
            }
          }
          state = state.copyWith(
            status: AuthStatus.error,
            errorMessage: 'MAC address not registered on this portal.\nCheck your MAC or contact your IPTV provider.',
            sessionReady: false,
          );
          return;
        }
        _logger.i('AUTH', 'Redirecting Stalker login to: ${e.redirectUrl}');
        return _loginHelper(
          activeUrl: e.redirectUrl,
          originalUrl: originalUrl,
          macAddress: macAddress,
          rememberMe: rememberMe,
          stbModel: stbModel,
          serialNumber: serialNumber,
          timezone: timezone,
          urlEncodeMac: urlEncodeMac,
        );
      }
      _logger.e('AUTH', 'Login failed', error: e);
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _getErrorMessage(e),
        sessionReady: false,
      );
    }
  }

  /// Login with Xtream Codes URL, username and password.
  Future<void> loginXtream(
    String portalUrl,
    String username,
    String password, {
    bool rememberMe = false,
  }) async {
    state = state.copyWith(
      status: AuthStatus.loading,
      errorMessage: null,
      portalUrl: portalUrl,
      sessionReady: false,
    );

    try {
      _logger.i('AUTH', 'Starting Xtream login flow');
      final loginRes = await _xtreamApi.login(portalUrl, username, password);
      _xtreamApi.configure(portalUrl: portalUrl, username: username, password: password);

      await _storage.saveXtreamCredentials(
        portalUrl: portalUrl,
        username: username,
        password: password,
      );
      await _storage.saveAuthType('xtream');
      await _storage.setRememberMe(rememberMe);

      state = state.copyWith(
        status: AuthStatus.authenticated,
        authType: 'xtream',
        portalUrl: portalUrl,
        rememberMe: rememberMe,
        sessionReady: true,
        xtreamUserInfo: loginRes['user_info'],
      );
      _logger.i('AUTH', 'Xtream login successful & session ready');
    } catch (e) {
      _logger.e('AUTH', 'Xtream login failed', error: e);
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: _getErrorMessage(e),
        sessionReady: false,
      );
    }
  }

  Future<void> logout() async {
    _api.logout();
    _xtreamApi.logout();
    await _storage.clearSession();
    await _storage.setRememberMe(false);
    state = const AuthState(status: AuthStatus.unauthenticated, sessionReady: false);
    _logger.i('AUTH', 'Logged out');
  }

  String _getErrorMessage(dynamic error) {
    if (error is DioException) {
      final dioError = error;
      if (dioError.type == DioExceptionType.connectionTimeout ||
          dioError.type == DioExceptionType.receiveTimeout ||
          dioError.type == DioExceptionType.sendTimeout) {
        return 'Connection timed out. Check your server URL and internet connection.';
      }
      if (dioError.type == DioExceptionType.badResponse) {
        final statusCode = dioError.response?.statusCode;
        if (statusCode == 404) {
          return 'Server returned a 404 error. Please check your Server URL or ensure your provider supports Xtream Codes.';
        }
        if (statusCode == 401 || statusCode == 403) {
          return 'Invalid username or password.';
        }
        return 'Server returned error status code: $statusCode.';
      }
      if (dioError.type == DioExceptionType.connectionError) {
        final errMsg = dioError.message?.toLowerCase() ?? '';
        if (errMsg.contains('getaddrinfo') || errMsg.contains('no address') || errMsg.contains('name or service not known') || errMsg.contains('no such host')) {
          return 'Cannot resolve server address. Check the portal URL — the domain may be incorrect or temporarily unavailable.';
        }
        if (errMsg.contains('connection refused')) {
          return 'Connection refused by the server. The portal may be offline or the URL incorrect.';
        }
        if (errMsg.contains('ssl') || errMsg.contains('certificate') || errMsg.contains('handshake')) {
          return 'SSL/TLS error. Try using http:// instead of https:// (or vice versa).';
        }
        return 'Cannot connect to the server. Check your server URL and network.';
      }
      return 'Network error: ${dioError.message}';
    }

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
    if (msg.contains('Empty token')) return 'Invalid response from portal. The server may not support Stalker protocol at this URL.';
    if (msg.contains('Rate limited')) return 'Too many requests. Wait a moment and try again.';
    if (msg.contains('Invalid username or password')) return 'Invalid username or password.';
    if (msg.contains('Invalid response format')) return 'Portal returned an unexpected response. The URL may not be a Stalker/Ministra portal.';
    return 'Authentication failed: ${msg.replaceAll('Exception: ', '')}';
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier(
    ref.watch(stalkerApiProvider),
    ref.watch(xtreamApiProvider),
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
  if (authState.authType == 'xtream') {
    final list = await ref.watch(xtreamApiProvider).getCategories('get_live_categories');
    return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
  }
  final api = ref.watch(stalkerApiProvider);
  final list = await api.getCategories('itv');
  return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
});

// All channels
final allChannelsProvider = FutureProvider<List<Channel>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  
  List<Channel> channels;
  if (authState.authType == 'xtream') {
    channels = await ref.watch(xtreamApiProvider).getLiveStreams();
  } else {
    channels = await ref.watch(stalkerApiProvider).getAllChannels();
  }

  final lockState = ref.watch(parentalLockProvider);
  if (lockState.isLocked && !lockState.isSessionUnlocked) {
    try {
      final categories = await ref.read(tvCategoriesProvider.future);
      final adultCatIds = categories
          .where((c) => isAdultContent(categoryName: c.title))
          .map((c) => c.id)
          .toSet();
      channels = channels.where((c) {
        if (adultCatIds.contains(c.categoryId)) return false;
        if (isAdultContent(itemName: c.name)) return false;
        return true;
      }).toList();
    } catch (_) {}
  }
  return channels;
});

// Channels by category
final channelsByCategoryProvider = FutureProvider.family<List<Channel>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  
  if (categoryId != null) {
    final lockState = ref.watch(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      try {
        final categories = await ref.read(tvCategoriesProvider.future);
        final selectedCat = categories.firstWhere((c) => c.id == categoryId);
        if (isAdultContent(categoryName: selectedCat.title)) {
          return []; // locked!
        }
      } catch (_) {}
    }
  }

  if (authState.authType == 'xtream') {
    return ref.watch(xtreamApiProvider).getLiveStreams(categoryId: categoryId);
  }
  final api = ref.watch(stalkerApiProvider);
  return api.getChannels(categoryId: categoryId);
});

// VOD categories
final vodCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  if (authState.authType == 'xtream') {
    final list = await ref.watch(xtreamApiProvider).getCategories('get_vod_categories');
    return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
  }
  final list = await ref.watch(moviesServiceProvider).getCategories();
  return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
});

// Movies
final moviesProvider = FutureProvider.family<List<vod_models.VodItem>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  
  if (categoryId != null) {
    final lockState = ref.watch(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      try {
        final categories = await ref.read(vodCategoriesProvider.future);
        final selectedCat = categories.firstWhere((c) => c.id == categoryId);
        if (isAdultContent(categoryName: selectedCat.title)) {
          return []; // locked!
        }
      } catch (_) {}
    }
  }

  List<vod_models.VodItem> movies;
  String? targetCategoryId = categoryId;
  
  if (authState.authType == 'xtream') {
    movies = await ref.watch(xtreamApiProvider).getVodStreams(categoryId: categoryId, page: 1);
  } else {
    if (targetCategoryId == null) {
      try {
        final categories = await ref.read(vodCategoriesProvider.future);
        if (categories.isNotEmpty) {
          targetCategoryId = categories.first.id;
        }
      } catch (_) {}
    }
    movies = await ref.watch(moviesServiceProvider).getOrderedList(categoryId: targetCategoryId, page: 1);
  }

  // If fetched global (categoryId == null), filter adult content
  if (categoryId == null) {
    final lockState = ref.watch(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      try {
        final categories = await ref.read(vodCategoriesProvider.future);
        final adultCatIds = categories
            .where((c) => isAdultContent(categoryName: c.title))
            .map((c) => c.id)
            .toSet();
        movies = movies.where((m) {
          if (adultCatIds.contains(m.categoryId.toString())) return false;
          if (isAdultContent(itemName: m.name)) return false;
          return true;
        }).toList();
      } catch (_) {}
    }
  }
  return movies;
});

// Series categories
final seriesCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  if (authState.authType == 'xtream') {
    final list = await ref.watch(xtreamApiProvider).getCategories('get_series_categories');
    return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
  }
  final list = await ref.watch(seriesServiceProvider).getCategories();
  return list.where((cat) => cat.title.toLowerCase() != 'all').toList();
});

// Series
final seriesProvider = FutureProvider.family<List<series_models.SeriesItem>, String?>((ref, categoryId) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  
  if (categoryId != null) {
    final lockState = ref.watch(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      try {
        final categories = await ref.read(seriesCategoriesProvider.future);
        final selectedCat = categories.firstWhere((c) => c.id == categoryId);
        if (isAdultContent(categoryName: selectedCat.title)) {
          return []; // locked!
        }
      } catch (_) {}
    }
  }

  List<series_models.SeriesItem> series;
  String? targetCategoryId = categoryId;
  
  if (authState.authType == 'xtream') {
    series = await ref.watch(xtreamApiProvider).getSeries(categoryId: categoryId, page: 1);
  } else {
    if (targetCategoryId == null) {
      try {
        final categories = await ref.read(seriesCategoriesProvider.future);
        if (categories.isNotEmpty) {
          targetCategoryId = categories.first.id;
        }
      } catch (_) {}
    }
    series = await ref.watch(seriesServiceProvider).getOrderedList(categoryId: targetCategoryId, page: 1);
  }

  // If fetched global (categoryId == null), filter adult content
  if (categoryId == null) {
    final lockState = ref.watch(parentalLockProvider);
    if (lockState.isLocked && !lockState.isSessionUnlocked) {
      try {
        final categories = await ref.read(seriesCategoriesProvider.future);
        final adultCatIds = categories
            .where((c) => isAdultContent(categoryName: c.title))
            .map((c) => c.id)
            .toSet();
        series = series.where((s) {
          if (adultCatIds.contains(s.categoryId.toString())) return false;
          if (isAdultContent(itemName: s.name)) return false;
          return true;
        }).toList();
      } catch (_) {}
    }
  }
  return series;
});

// Series Info (seasons/episodes) — accepts both seriesId and parent cmd
final seriesInfoProvider = FutureProvider.family<List<series_models.Season>, ({String seriesId, String seriesCmd})>((ref, params) async {
  final authState = ref.watch(authProvider);
  if (!authState.sessionReady) return [];
  if (authState.authType == 'xtream') {
    return ref.watch(xtreamApiProvider).getSeriesInfo(params.seriesId);
  }
  return ref.watch(seriesServiceProvider).getSeriesInfo(params.seriesId, seriesCmd: params.seriesCmd);
});

// EPG for a channel
final epgProvider = FutureProvider.family<List<EpgProgram>, String>((ref, channelId) async {
  final authState = ref.watch(authProvider);
  if (authState.status != AuthStatus.authenticated) return [];
  if (authState.authType == 'xtream') {
    final xcEpg = await ref.watch(xtreamApiProvider).getEPG(channelId);
    return xcEpg.map((e) => EpgProgram(
      id: '',
      name: e.title,
      description: e.description,
      startTime: e.startTime,
      endTime: e.endTime,
      channelId: channelId,
    )).toList();
  }
  final api = ref.watch(stalkerApiProvider);
  return api.getEpg(channelId);
});

// Full Simple EPG (Catch-up / Archive support) for a channel
final simpleEpgProvider = FutureProvider.family<List<EpgProgram>, String>((ref, channelId) async {
  final authState = ref.watch(authProvider);
  if (authState.status != AuthStatus.authenticated) return [];
  if (authState.authType == 'xtream') {
    // Use getFullEPG which fetches past + current + future programs for catch-up
    final xcEpg = await ref.watch(xtreamApiProvider).getFullEPG(channelId);
    return xcEpg.map((e) => EpgProgram(
      id: '',
      name: e.title,
      description: e.description,
      startTime: e.startTime,
      endTime: e.endTime,
      channelId: channelId,
    )).toList();
  }
  final api = ref.watch(stalkerApiProvider);
  return api.getSimpleEpg(channelId);
});


// Stream URL resolver
final streamUrlProvider = FutureProvider.family<String, ({String cmd, String type})>((ref, params) async {
  if (params.cmd.startsWith('http://') || params.cmd.startsWith('https://')) {
    return params.cmd;
  }
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

  final lowerQuery = query.toLowerCase();

  // Search across all content types
  final results = <String, List<dynamic>>{};

  try {
    final channels = ref.watch(allChannelsProvider).value ?? [];
    results['channels'] = channels
        .where((c) => c.name.toLowerCase().contains(lowerQuery))
        .take(20)
        .toList();
  } catch (_) {
    results['channels'] = [];
  }

  final lockState = ref.watch(parentalLockProvider);
  final isLocked = lockState.isLocked && !lockState.isSessionUnlocked;

  try {
    final moviesService = ref.read(moviesServiceProvider);
    final movies = await moviesService.getOrderedList(search: query);
    if (isLocked) {
      Set<String> adultCatIds = {};
      try {
        final categories = await ref.read(vodCategoriesProvider.future);
        adultCatIds = categories
            .where((c) => isAdultContent(categoryName: c.title))
            .map((c) => c.id)
            .toSet();
      } catch (_) {}
      
      results['movies'] = movies
          .where((m) => !adultCatIds.contains(m.categoryId.toString()) && !isAdultContent(itemName: m.name))
          .take(20)
          .toList();
    } else {
      results['movies'] = movies.take(20).toList();
    }
  } catch (_) {
    results['movies'] = [];
  }

  try {
    final seriesService = ref.read(seriesServiceProvider);
    final series = await seriesService.getOrderedList(search: query);
    if (isLocked) {
      Set<String> adultCatIds = {};
      try {
        final categories = await ref.read(seriesCategoriesProvider.future);
        adultCatIds = categories
            .where((c) => isAdultContent(categoryName: c.title))
            .map((c) => c.id)
            .toSet();
      } catch (_) {}
      
      results['series'] = series
          .where((s) => !adultCatIds.contains(s.categoryId.toString()) && !isAdultContent(itemName: s.name))
          .take(20)
          .toList();
    } else {
      results['series'] = series.take(20).toList();
    }
  } catch (_) {
    results['series'] = [];
  }

  return results;
});

// ─── Parental Control State ────────────────────────────────
class ParentalLockState {
  final bool isLocked;
  final String pin;
  final bool isSessionUnlocked;

  const ParentalLockState({
    this.isLocked = true, // Always locked for adult content
    this.pin = '0000',
    this.isSessionUnlocked = false,
  });

  ParentalLockState copyWith({
    bool? isLocked,
    String? pin,
    bool? isSessionUnlocked,
  }) {
    return ParentalLockState(
      isLocked: isLocked ?? this.isLocked,
      pin: pin ?? this.pin,
      isSessionUnlocked: isSessionUnlocked ?? this.isSessionUnlocked,
    );
  }
}

class ParentalLockNotifier extends StateNotifier<ParentalLockState> {
  final SecureStorageService _storage;

  ParentalLockNotifier(this._storage) : super(const ParentalLockState()) {
    _loadState();
  }

  Future<void> _loadState() async {
    final pin = await _storage.getParentalPin();
    state = ParentalLockState(
      isLocked: true, // Enforce lock
      pin: pin,
      isSessionUnlocked: false,
    );
  }

  void initFromServer(String serverPin) {
    // If the server provides a pin and it differs from local, sync it.
    if (serverPin.isNotEmpty && serverPin != state.pin) {
      _storage.saveParentalPin(serverPin);
      state = state.copyWith(pin: serverPin);
    }
  }

  Future<void> updatePin(String newPin) async {
    await _storage.saveParentalPin(newPin);
    state = state.copyWith(pin: newPin);
  }

  void unlockSession() {
    state = state.copyWith(isSessionUnlocked: true);
  }

  void lockSession() {
    state = state.copyWith(isSessionUnlocked: false);
  }
}

final parentalLockProvider = StateNotifierProvider<ParentalLockNotifier, ParentalLockState>((ref) {
  final notifier = ParentalLockNotifier(ref.watch(secureStorageProvider));
  
  // Proactively check current state in case session is already restored/authenticated
  final currentAuth = ref.read(authProvider);
  if (currentAuth.status == AuthStatus.authenticated) {
    if (currentAuth.authType == 'stalker' && currentAuth.profile != null) {
      notifier.initFromServer(currentAuth.profile!.parentPassword);
    } else if (currentAuth.authType == 'xtream' && currentAuth.xtreamUserInfo != null) {
      final userInfo = currentAuth.xtreamUserInfo!;
      if (userInfo.containsKey('parent_password')) {
        notifier.initFromServer(userInfo['parent_password'].toString());
      }
    }
  }
  
  // Sync server PIN when user authenticates dynamically
  ref.listen<AuthState>(authProvider, (previous, next) {
    if (next.status == AuthStatus.authenticated && previous?.status != AuthStatus.authenticated) {
      if (next.authType == 'stalker' && next.profile != null) {
        notifier.initFromServer(next.profile!.parentPassword);
      } else if (next.authType == 'xtream' && next.xtreamUserInfo != null) {
        final userInfo = next.xtreamUserInfo!;
        if (userInfo.containsKey('parent_password')) {
          notifier.initFromServer(userInfo['parent_password'].toString());
        }
      }
    }
  });

  return notifier;
});

bool isAdultContent({String? categoryName, String? itemName}) {
  final adultKeywords = [
    '18+', '18 +', '(18+)', '[18+]', '18 plus',
    'xxx', 'adult', 'for adults', 'erotic', 'porn', 'mature', 'uncensored'
  ];
  
  if (categoryName != null) {
    final lowerCat = categoryName.toLowerCase();
    for (final keyword in adultKeywords) {
      if (lowerCat.contains(keyword.toLowerCase())) {
        return true;
      }
    }
  }
  
  if (itemName != null) {
    final lowerItem = itemName.toLowerCase();
    for (final keyword in adultKeywords) {
      if (lowerItem.contains(keyword.toLowerCase())) {
        return true;
      }
    }
  }
  
  return false;
}

class ContinueWatchingNotifier extends StateNotifier<List<Map<String, dynamic>>> {
  final PreferencesService _prefs;

  ContinueWatchingNotifier(this._prefs) : super([]) {
    refresh();
  }

  void refresh() {
    state = _prefs.getAllContinueWatching();
  }

  Future<void> remove(String contentId) async {
    await _prefs.clearWatchProgress(contentId);
    refresh();
  }
}

final continueWatchingProvider = StateNotifierProvider<ContinueWatchingNotifier, List<Map<String, dynamic>>>((ref) {
  final prefs = ref.watch(preferencesProvider);
  return ContinueWatchingNotifier(prefs);
});


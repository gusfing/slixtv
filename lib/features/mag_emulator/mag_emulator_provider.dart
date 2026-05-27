import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_logger.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/error_handler.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/portal_discovery.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_auth_service.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/live_tv_service.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/movies_service.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/series_service.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/player_headers_service.dart';

// ─── Core Singletons ──────────────────────────────────────────────────────────

final magLoggerProvider = Provider<MagLogger>((ref) {
  return MagLogger();
});

final sessionManagerProvider = Provider<SessionManager>((ref) {
  return SessionManager();
});

final magSecureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

final deviceIdentityProvider = FutureProvider<DeviceIdentity>((ref) async {
  final storage = ref.read(magSecureStorageProvider);
  final session = ref.read(sessionManagerProvider);
  final identity = await DeviceIdentity.loadOrCreate(storage);
  session.setMacAddress(identity.mac);
  return identity;
});

final magDioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  final sessionManager = ref.watch(sessionManagerProvider);
  // Base options — interceptors are added later by magErrorHandlerProvider
  dio.options = BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    followRedirects: true,
    maxRedirects: 5,
  );
  // Attach CookieManager so session cookies (PHPSESSID etc.) persist
  dio.interceptors.add(CookieManager(sessionManager.cookieJar));
  return dio;
});

// ─── Auth & Protocol ──────────────────────────────────────────────────────────

final magAuthServiceProvider = Provider<MagAuthService>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value;

  if (deviceIdentity == null) {
    throw StateError('DeviceIdentity not yet loaded');
  }

  return MagAuthService(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
  );
});

/// Attaches the interceptor to the shared Dio instance. Must be watched early.
final magErrorHandlerProvider = Provider<MagErrorHandler>((ref) {
  final logger = ref.watch(magLoggerProvider);
  final authService = ref.watch(magAuthServiceProvider);
  final dio = ref.read(magDioProvider);

  final handler = MagErrorHandler(logger: logger, authService: authService);

  // Only attach once
  final alreadyAttached = dio.interceptors.any((i) => i is MagErrorHandler);
  if (!alreadyAttached) {
    dio.interceptors.add(handler);
  }

  return handler;
});

final portalDiscoveryProvider = Provider<PortalDiscoveryService>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;

  return PortalDiscoveryService(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
  );
});

final streamResolverProvider = Provider<StreamResolver>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;

  return StreamResolver(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
  );
});

// ─── Content Services ─────────────────────────────────────────────────────────

final magLiveTvServiceProvider = Provider<LiveTvService>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;
  final streamResolver = ref.watch(streamResolverProvider);
  ref.watch(magErrorHandlerProvider); // Ensure interceptor is attached

  return LiveTvService(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
    streamResolver: streamResolver,
  );
});

final magMoviesServiceProvider = Provider<MoviesService>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;
  final streamResolver = ref.watch(streamResolverProvider);
  ref.watch(magErrorHandlerProvider);

  return MoviesService(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
    streamResolver: streamResolver,
  );
});

final magSeriesServiceProvider = Provider<SeriesService>((ref) {
  final dio = ref.watch(magDioProvider);
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;
  final streamResolver = ref.watch(streamResolverProvider);
  ref.watch(magErrorHandlerProvider);

  return SeriesService(
    dio: dio,
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
    streamResolver: streamResolver,
  );
});

final playerHeadersServiceProvider = Provider<PlayerHeadersService>((ref) {
  final sessionManager = ref.watch(sessionManagerProvider);
  final deviceIdentity = ref.watch(deviceIdentityProvider).value!;

  return PlayerHeadersService(
    sessionManager: sessionManager,
    deviceIdentity: deviceIdentity,
  );
});

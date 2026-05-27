import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';

/// Secure storage for tokens, credentials, and sensitive data.
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  final AppLogger _logger = AppLogger();

  SecureStorageService._internal();

  // ─── Keys ────────────────────────────────────────────────
  static const String _portalUrlKey = 'portal_url';
  static const String _macAddressKey = 'mac_address';
  static const String _tokenKey = 'auth_token';
  static const String _cookiesKey = 'auth_cookies';
  static const String _rememberMeKey = 'remember_me';

  // ─── Portal Credentials ──────────────────────────────────
  Future<void> savePortalCredentials({
    required String portalUrl,
    required String macAddress,
  }) async {
    await _storage.write(key: _portalUrlKey, value: portalUrl);
    await _storage.write(key: _macAddressKey, value: macAddress);
    _logger.i('SecureStorage', 'Portal credentials saved');
  }

  Future<Map<String, String?>> getPortalCredentials() async {
    return {
      'portalUrl': await _storage.read(key: _portalUrlKey),
      'macAddress': await _storage.read(key: _macAddressKey),
    };
  }

  // ─── Token ───────────────────────────────────────────────
  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
    _logger.i('SecureStorage', 'Token saved');
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  // ─── Cookies ─────────────────────────────────────────────
  Future<void> saveCookies(String cookies) async {
    await _storage.write(key: _cookiesKey, value: cookies);
  }

  Future<String?> getCookies() async {
    return await _storage.read(key: _cookiesKey);
  }

  // ─── Remember Me ─────────────────────────────────────────
  Future<void> setRememberMe(bool value) async {
    await _storage.write(key: _rememberMeKey, value: value.toString());
  }

  Future<bool> getRememberMe() async {
    final val = await _storage.read(key: _rememberMeKey);
    return val == 'true';
  }

  // ─── Clear ───────────────────────────────────────────────
  Future<void> clearAll() async {
    await _storage.deleteAll();
    _logger.i('SecureStorage', 'All secure data cleared');
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _cookiesKey);
    _logger.i('SecureStorage', 'Session data cleared');
  }
}

/// Non-sensitive local preferences storage.
class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService() => _instance;

  SharedPreferences? _prefs;
  final AppLogger _logger = AppLogger();

  PreferencesService._internal();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _logger.i('Preferences', 'SharedPreferences initialized');
  }

  SharedPreferences get prefs {
    if (_prefs == null) throw Exception('PreferencesService not initialized');
    return _prefs!;
  }

  // ─── Continue Watching ───────────────────────────────────
  Future<void> saveWatchProgress(String contentId, int positionMs) async {
    await prefs.setInt('watch_progress_$contentId', positionMs);
    await prefs.setString('watch_timestamp_$contentId', DateTime.now().toIso8601String());
  }

  int getWatchProgress(String contentId) {
    return prefs.getInt('watch_progress_$contentId') ?? 0;
  }

  String? getWatchTimestamp(String contentId) {
    return prefs.getString('watch_timestamp_$contentId');
  }

  Future<void> clearWatchProgress(String contentId) async {
    await prefs.remove('watch_progress_$contentId');
    await prefs.remove('watch_timestamp_$contentId');
  }

  // ─── Favorites ───────────────────────────────────────────
  Future<void> saveFavorites(String type, List<String> ids) async {
    await prefs.setStringList('favorites_$type', ids);
  }

  List<String> getFavorites(String type) {
    return prefs.getStringList('favorites_$type') ?? [];
  }

  // ─── Last Channel ───────────────────────────────────────
  Future<void> saveLastChannel(String channelId) async {
    await prefs.setString('last_channel', channelId);
  }

  String? getLastChannel() {
    return prefs.getString('last_channel');
  }

  // ─── Recent Channels ────────────────────────────────────
  Future<void> addRecentChannel(String channelId) async {
    final recent = prefs.getStringList('recent_channels') ?? [];
    recent.remove(channelId);
    recent.insert(0, channelId);
    if (recent.length > 20) recent.removeLast();
    await prefs.setStringList('recent_channels', recent);
  }

  List<String> getRecentChannels() {
    return prefs.getStringList('recent_channels') ?? [];
  }

  // ─── Clear ───────────────────────────────────────────────

  /// Clears only cached/transient data (watch progress, recent channels).
  /// Preserves favorites and auth-related data.
  Future<void> clearCacheOnly() async {
    final keys = prefs.getKeys().toList();
    for (final key in keys) {
      if (key.startsWith('watch_progress_') ||
          key.startsWith('watch_timestamp_') ||
          key == 'recent_channels' ||
          key == 'last_channel') {
        await prefs.remove(key);
      }
    }
    _logger.i('Preferences', 'Cache cleared (favorites preserved)');
  }

  Future<void> clearAll() async {
    await prefs.clear();
    _logger.i('Preferences', 'All preferences cleared');
  }
}

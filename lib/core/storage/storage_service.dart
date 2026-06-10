import 'dart:convert';
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
  static const String _activePortalUrlKey = 'active_portal_url';
  static const String _macAddressKey = 'mac_address';
  static const String _tokenKey = 'auth_token';
  static const String _cookiesKey = 'auth_cookies';
  static const String _rememberMeKey = 'remember_me';
  static const String _stbModelKey = 'stb_model';
  static const String _serialNumberKey = 'serial_number';
  static const String _timezoneKey = 'timezone';
  static const String _urlEncodeMacKey = 'url_encode_mac';
  static const String _parentalPinKey = 'parental_pin';
  static const String _parentalLockKey = 'parental_lock_enabled';
  static const String _authTypeKey = 'auth_type';
  static const String _xtreamUsernameKey = 'xtream_username';
  static const String _xtreamPasswordKey = 'xtream_password';

  // ─── Portal Credentials ──────────────────────────────────
  Future<void> savePortalCredentials({
    required String portalUrl,
    String? activePortalUrl,
    required String macAddress,
    String? stbModel,
    String? serialNumber,
    String? timezone,
    bool? urlEncodeMac,
  }) async {
    await _storage.write(key: _portalUrlKey, value: portalUrl);
    await _storage.write(key: _activePortalUrlKey, value: activePortalUrl ?? portalUrl);
    await _storage.write(key: _macAddressKey, value: macAddress);
    if (stbModel != null) {
      await _storage.write(key: _stbModelKey, value: stbModel);
    } else {
      await _storage.delete(key: _stbModelKey);
    }
    if (serialNumber != null) {
      await _storage.write(key: _serialNumberKey, value: serialNumber);
    } else {
      await _storage.delete(key: _serialNumberKey);
    }
    if (timezone != null) {
      await _storage.write(key: _timezoneKey, value: timezone);
    } else {
      await _storage.delete(key: _timezoneKey);
    }
    if (urlEncodeMac != null) {
      await _storage.write(key: _urlEncodeMacKey, value: urlEncodeMac.toString());
    } else {
      await _storage.delete(key: _urlEncodeMacKey);
    }
    _logger.i('SecureStorage', 'Portal credentials and custom device params saved');
  }

  Future<Map<String, String?>> getPortalCredentials() async {
    return {
      'portalUrl': await _storage.read(key: _portalUrlKey),
      'activePortalUrl': await _storage.read(key: _activePortalUrlKey),
      'macAddress': await _storage.read(key: _macAddressKey),
      'stbModel': await _storage.read(key: _stbModelKey),
      'serialNumber': await _storage.read(key: _serialNumberKey),
      'timezone': await _storage.read(key: _timezoneKey),
      'urlEncodeMac': await _storage.read(key: _urlEncodeMacKey),
    };
  }

  // ─── Xtream Credentials ──────────────────────────────────
  Future<void> saveXtreamCredentials({
    required String portalUrl,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _portalUrlKey, value: portalUrl);
    await _storage.write(key: _xtreamUsernameKey, value: username);
    await _storage.write(key: _xtreamPasswordKey, value: password);
    await _storage.write(key: _authTypeKey, value: 'xtream');
    _logger.i('SecureStorage', 'Xtream credentials saved');
  }

  Future<Map<String, String?>> getXtreamCredentials() async {
    return {
      'portalUrl': await _storage.read(key: _portalUrlKey),
      'username': await _storage.read(key: _xtreamUsernameKey),
      'password': await _storage.read(key: _xtreamPasswordKey),
    };
  }

  Future<void> saveAuthType(String type) async {
    await _storage.write(key: _authTypeKey, value: type);
  }

  Future<String> getAuthType() async {
    return await _storage.read(key: _authTypeKey) ?? 'stalker';
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

  // ─── Parental Control PIN ───────────────────────────────
  Future<void> saveParentalPin(String pin) async {
    await _storage.write(key: _parentalPinKey, value: pin);
  }

  Future<String> getParentalPin() async {
    return await _storage.read(key: _parentalPinKey) ?? '0000';
  }

  // ─── Parental Lock Enabled ───────────────────────────────
  Future<void> setParentalLockEnabled(bool enabled) async {
    await _storage.write(key: _parentalLockKey, value: enabled.toString());
  }

  Future<bool> getParentalLockEnabled() async {
    final val = await _storage.read(key: _parentalLockKey);
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
    await _storage.delete(key: _xtreamUsernameKey);
    await _storage.delete(key: _xtreamPasswordKey);
    await _storage.delete(key: _authTypeKey);
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

  Future<void> saveWatchMetadata(String contentId, String metadataJson) async {
    await prefs.setString('watch_metadata_$contentId', metadataJson);
  }

  String? getWatchMetadata(String contentId) {
    return prefs.getString('watch_metadata_$contentId');
  }

  Future<void> saveWatchDuration(String contentId, int durationMs) async {
    await prefs.setInt('watch_duration_$contentId', durationMs);
  }

  int getWatchDuration(String contentId) {
    return prefs.getInt('watch_duration_$contentId') ?? 0;
  }

  Future<void> clearWatchProgress(String contentId) async {
    await prefs.remove('watch_progress_$contentId');
    await prefs.remove('watch_timestamp_$contentId');
    await prefs.remove('watch_metadata_$contentId');
    await prefs.remove('watch_duration_$contentId');
  }

  List<Map<String, dynamic>> getAllContinueWatching() {
    final list = <Map<String, dynamic>>[];
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('watch_progress_')) {
        final contentId = key.replaceFirst('watch_progress_', '');
        final progress = prefs.getInt(key) ?? 0;
        final duration = prefs.getInt('watch_duration_$contentId') ?? 0;
        
        // Mark as watched to end if > 95% progress
        bool isWatchedToEnd = false;
        if (duration > 0 && progress > 0) {
          isWatchedToEnd = progress > (duration * 0.95);
        }

        // Only keep if progress > 10s and not completed
        if (progress > 10000 && !isWatchedToEnd) {
          final timestamp = prefs.getString('watch_timestamp_$contentId');
          final metadataJson = prefs.getString('watch_metadata_$contentId');
          if (metadataJson != null) {
            try {
              final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
              list.add({
                'contentId': contentId,
                'progress': progress,
                'duration': duration,
                'timestamp': timestamp ?? '',
                'metadata': metadata,
              });
            } catch (_) {}
          }
        }
      }
    }
    // Sort by timestamp descending
    list.sort((a, b) {
      final tA = a['timestamp'] as String;
      final tB = b['timestamp'] as String;
      return tB.compareTo(tA);
    });
    return list;
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

  // ─── Discovered Stalker Endpoints ───────────────────────
  Future<void> saveDiscoveredEndpoint(String portalUrl, String loadPath) async {
    await prefs.setString('stalker_endpoint_${portalUrl.trim().toLowerCase()}', loadPath);
  }

  String? getDiscoveredEndpoint(String portalUrl) {
    try {
      return prefs.getString('stalker_endpoint_${portalUrl.trim().toLowerCase()}');
    } catch (_) {
      return null;
    }
  }

  Future<void> clearEndpointCache(String portalUrl) async {
    try {
      await prefs.remove('stalker_endpoint_${portalUrl.trim().toLowerCase()}');
    } catch (_) {}
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

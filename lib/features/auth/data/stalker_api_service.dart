import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import 'models.dart';

/// Complete MAG/Stalker middleware API implementation.
///
/// Protocol flow: handshake → profile → content → create_link → player
/// All requests share the same singleton ApiClient (token + session state).
class StalkerApiService {
  final ApiClient _client = ApiClient();
  final AppLogger _logger = AppLogger();

  String? _portalBase;
  String? _serverLoadPath;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;
  String? get serverLoadPath => _serverLoadPath;
  ApiClient get client => _client;

  // ─── Step 1: Handshake ──────────────────────────────────

  Future<String> handshake(String portalUrl, String macAddress) async {
    _logger.mag('HANDSHAKE', 'Starting with $portalUrl / $macAddress');
    _client.configure(portalUrl: portalUrl, macAddress: macAddress);
    _portalBase = _client.portalUrl;

    _serverLoadPath = await _discoverEndpoint();
    _client.serverLoadPath = _serverLoadPath;
    _logger.mag('HANDSHAKE', 'Endpoint: $_serverLoadPath');

    try {
      final response = await _stalkerRequest(
        type: AppConfig.typeStb,
        action: AppConfig.stalkerHandshakeAction,
        extraParams: {'prehash': '0'},
      );

      final js = response['js'];
      if (js == null || js == false) {
        throw const AuthException(message: 'Handshake response missing token');
      }

      final token = js['token']?.toString() ?? '';
      if (token.isEmpty) {
        throw const AuthException(message: 'Empty token from handshake');
      }

      _client.setToken(token);
      _isAuthenticated = true;
      _logger.mag('HANDSHAKE', 'SUCCESS token=${token.substring(0, 8)}...');
      return token;
    } catch (e) {
      _logger.e('MAG', 'Handshake failed', error: e);
      if (e is AuthException) rethrow;
      throw AuthException(message: 'Handshake failed: $e');
    }
  }

  Future<String> _discoverEndpoint() async {
    final base = _portalBase!;
    
    // Normalize base — remove trailing slashes and known load.php suffixes
    String cleanBase = base;
    if (cleanBase.endsWith('/server/load.php')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - '/server/load.php'.length);
    } else if (cleanBase.endsWith('/load.php')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - '/load.php'.length);
    }
    if (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }

    // Common stalker portal endpoint paths (in priority order)
    final paths = [
      '$cleanBase/stalker_portal/server/load.php',
      '$cleanBase/server/load.php',
      '$cleanBase/load.php',
      '$cleanBase/stalker_portal/c/fake_auth.js',      // some portals
      '$cleanBase/portal.php',                           // some custom portals
    ];

    for (final path in paths) {
      try {
        _logger.mag('DISCOVER', 'Trying: $path');
        final response = await _client.dio.get(
          path,
          queryParameters: {
            'type': AppConfig.typeStb,
            'action': AppConfig.stalkerHandshakeAction,
            'prehash': '0',
            'JsHttpRequest': '1-xml',
          },
          options: Options(
            validateStatus: (s) => s != null && s < 500,
            receiveTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 8),
          ),
        );

        if (response.statusCode == 429) {
          throw const AuthException(
              message: 'Rate limited. Please wait a moment and try again.');
        }
        if (response.statusCode == 200) {
          dynamic data = response.data;
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (_) {}
          }
          if (data is Map && data.containsKey('js')) {
            _logger.mag('DISCOVER', 'Found: $path');
            return path;
          }
        }
      } on AuthException {
        rethrow;
      } catch (_) {
        continue;
      }
    }

    // Fallback: use the cleaned base + standard path
    final fallback = '$cleanBase/stalker_portal/server/load.php';
    _logger.mag('DISCOVER', 'No endpoint found, using fallback: $fallback');
    return fallback;
  }

  // ─── Step 2: Profile ────────────────────────────────────

  Future<StalkerProfile> getProfile() async {
    final response = await _stalkerRequest(
      type: AppConfig.typeStb,
      action: AppConfig.stalkerGetProfileAction,
    );
    final js = response['js'];
    if (js == null || js == false || js is! Map<String, dynamic>) {
      return const StalkerProfile(id: '', name: 'User', mac: '', ip: '');
    }

    // status:2 = "Authentication request" — MAC is not registered on this portal.
    // blocked:1 = Account explicitly blocked by provider.
    final status = js['status'];
    final blocked = js['blocked'];

    if (status == 2 || status == '2') {
      throw const AuthException(
        message: 'MAC address not registered on this portal.\n'
            'Please check your MAC address or contact your IPTV provider.',
      );
    }
    
    if (blocked == 1 || blocked == '1') {
      throw const AuthException(
        message: 'Subscription blocked by your IPTV provider.',
      );
    }

    return StalkerProfile.fromJson(js);
  }

  Future<StalkerMainInfo> getMainInfo() async {
    final response = await _stalkerRequest(
      type: AppConfig.typeStb,
      action: AppConfig.stalkerGetMainInfoAction,
    );
    final js = response['js'];
    if (js == null || js == false || js is! Map<String, dynamic>) {
      return const StalkerMainInfo(serverName: '');
    }
    return StalkerMainInfo.fromJson(js);
  }

  // ─── Step 3: Categories ─────────────────────────────────

  /// Get categories for a content type.
  /// Handles: js=[...], js={data:[...]}, js=false, js=null
  Future<List<Category>> getCategories(String type) async {
    _logger.mag('CATEGORIES', 'type=$type');
    final action = type == AppConfig.typeItv
        ? AppConfig.stalkerGetGenresAction
        : 'get_categories';

    try {
      final response = await _stalkerRequest(type: type, action: action);
      return _extractCategories(response['js'], type);
    } catch (e) {
      _logger.e('CATEGORIES', 'Failed for type=$type', error: e);
      return [];
    }
  }

  List<Category> _extractCategories(dynamic js, String type) {
    if (js == null || js == false) return [];
    if (js is List) return _parseCatList(js);
    if (js is Map) {
      for (final key in ['data', 'genres', 'categories', 'items']) {
        final v = js[key];
        if (v is List) return _parseCatList(v);
        if (v is Map) return _parseCatList(v.values.toList());
      }
    }
    return [];
  }

  List<Category> _parseCatList(List raw) {
    final out = <Category>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        try { out.add(Category.fromJson(item)); } catch (_) {}
      }
    }
    return out;
  }

  // ─── Step 4: Ordered List ───────────────────────────────

  Future<Map<String, dynamic>> getOrderedList({
    required String type,
    String? categoryId,
    int page = 1,
    String sortBy = 'added',
  }) async {
    _logger.mag('CONTENT', 'type=$type cat=$categoryId p=$page');

    final params = <String, String>{
      'p': page.toString(),
      'sortby': sortBy,
      'hd': '0',
    };

    if (categoryId != null && categoryId.isNotEmpty && categoryId != '*') {
      params[type == AppConfig.typeItv ? 'genre' : 'category'] = categoryId;
    }

    try {
      final response = await _stalkerRequest(
        type: type,
        action: AppConfig.stalkerGetOrderedListAction,
        extraParams: params,
      );

      final js = response['js'];
      _logger.mag('CONTENT', 'js type: ${js?.runtimeType}');

      if (js == null || js == false) {
        return {'items': [], 'total': 0, 'pages': 0};
      }

      if (js is Map<String, dynamic>) {
        final rawData = js['data'];
        List items = [];
        
        if (rawData is List) {
          items = rawData;
        } else if (rawData is Map) {
          // Handle notorious PHP associative array bug in some Stalker portals
          items = rawData.values.toList();
        }

        final total = int.tryParse(js['total_items']?.toString() ?? '0') ?? 0;
        final pageSize = int.tryParse(js['max_page_items']?.toString() ?? '14') ?? 14;
        return {
          'items': items,
          'total': total,
          'pages': pageSize > 0 ? (total / pageSize).ceil() : 1,
        };
      }

      if (js is List) {
        return {'items': js, 'total': js.length, 'pages': 1};
      }
    } catch (e) {
      _logger.e('CONTENT', 'getOrderedList failed type=$type', error: e);
    }

    return {'items': [], 'total': 0, 'pages': 0};
  }

  // ─── Step 5: Specific Content Fetchers ──────────────────

  Future<List<Channel>> getAllChannels() async {
    final response = await _stalkerRequest(
      type: AppConfig.typeItv,
      action: AppConfig.stalkerGetAllChannelsAction,
    );
    final js = response['js'];
    if (js == null || js == false) return [];

    List? raw;
    if (js is Map<String, dynamic>) {
      final rawData = js['data'];
      if (rawData is List) raw = rawData;
      else if (rawData is Map) raw = rawData.values.toList();
    } else if (js is List) {
      raw = js;
    }
    if (raw == null || raw.isEmpty) return [];

    return raw.whereType<Map<String, dynamic>>()
        .map((e) => Channel.fromJson(e, client: _client))
        .toList();
  }

  Future<List<Channel>> getChannels({String? categoryId, int page = 1}) async {
    final result = await getOrderedList(
        type: AppConfig.typeItv, categoryId: categoryId,
        page: page, sortBy: 'number');
    return (result['items'] as List)
        .whereType<Map<String, dynamic>>()
        .map((e) => Channel.fromJson(e, client: _client))
        .toList();
  }

  Future<List<EpgProgram>> getEpg(String channelId) async {
    try {
      final response = await _stalkerRequest(
        type: AppConfig.typeItv,
        action: AppConfig.stalkerGetEpgAction,
        extraParams: {'ch_id': channelId, 'size': '10'},
      );
      final js = response['js'];
      if (js == null || js == false) return [];
      List? data;
      if (js is Map<String, dynamic>) {
        final rawData = js['data'];
        if (rawData is List) data = rawData;
        else if (rawData is Map) data = rawData.values.toList();
      } else if (js is List) {
        data = js;
      }
      if (data == null) return [];
      return data.whereType<Map<String, dynamic>>()
          .map((e) => EpgProgram.fromJson(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Step 6: Stream Resolution ──────────────────────────

  /// Resolves a MAG cmd string to a playable stream URL via create_link.
  ///
  /// The cmd from get_ordered_list (e.g. /media/464066.mpg or ffmpeg http://...)
  /// must be sent to create_link which returns the actual resolved stream URL.
  Future<String> createLink(String cmd, String type, {String? seriesId}) async {
    _logger.mag('CREATE_LINK', 'type=$type cmd=$cmd');
    
    // Diagnostic: Capture starting state
    _logger.debugState.selectedContent = 'Type: $type | Cmd: $cmd';
    _logger.debugState.cmd = cmd;
    _logger.debugState.cleanedCmd = UrlNormalizer.stripPlayerDirectives(cmd);

    final params = {
      'cmd': cmd,
      'series': seriesId ?? '',
      'forced_storage': '0',
      'disable_ad': '0',
      'volume': '100',
      'play_mode': '0',
    };
    _logger.debugState.requestPayload = params.toString();

    Map<String, dynamic> response;
    try {
      response = await _stalkerRequest(
        type: type,
        action: AppConfig.stalkerCreateLinkAction,
        extraParams: params,
      );
    } catch (e) {
      _logger.debugState.lastError = e.toString();
      throw PortalException(message: 'Stream request failed: $e');
    }

    final js = response['js'];
    _logger.debugState.rawResponse = js?.toString() ?? 'null';

    if (js == null || js == false) {
      throw const PortalException(message: 'No stream data received from portal');
    }

    String streamUrl = '';
    String errorCode = '';

    if (js is Map<String, dynamic>) {
      streamUrl = js['cmd']?.toString() ?? js['url']?.toString() ?? '';
      errorCode = js['error']?.toString() ?? '';
    } else if (js is String) {
      streamUrl = js;
    }

    if (errorCode == 'nothing_to_play') {
      throw const PortalException(
          message: 'This content is currently unavailable on the server.\nPlease try another title.');
    }
    if (errorCode.isNotEmpty && streamUrl.isEmpty) {
      throw PortalException(message: 'Server error: $errorCode');
    }

    streamUrl = UrlNormalizer.stripPlayerDirectives(streamUrl);

    // If it's an internal portal URL (e.g. localhost proxy), we MUST resolve it through our authenticated session.
    if (streamUrl.contains('localhost') || streamUrl.contains('127.0.0.1')) {
      final portalUri = Uri.tryParse(_client.portalUrl ?? '');
      if (portalUri != null) {
        streamUrl = streamUrl.replaceAll('localhost', portalUri.host).replaceAll('127.0.0.1', portalUri.host);
      }
      
      _logger.mag('RESOLVE_STREAM', 'Resolving internal stream via authenticated session: $streamUrl');
      _logger.debugState.redirects = 'Starting manual resolution for: $streamUrl\n';
      
      int redirectCount = 0;
      while (redirectCount < 5) {
        try {
          final response = await _client.dio.get(
            streamUrl,
            options: Options(
              followRedirects: false, // We must trace redirects manually
              validateStatus: (status) => status != null && status < 500,
              responseType: ResponseType.stream,
            ),
          );

          _logger.debugState.redirects += '[$redirectCount] HTTP ${response.statusCode} - $streamUrl\n';

          if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303 || response.statusCode == 307 || response.statusCode == 308) {
            final location = response.headers.value('location');
            response.data?.close(); // Release connection
            if (location != null && location.isNotEmpty) {
              _logger.mag('RESOLVE_STREAM', 'Got redirect -> $location');
              streamUrl = location;
              redirectCount++;
              continue;
            }
          }

          // Not a redirect, so this is the final URL
          response.data?.close();
          break;
        } catch (e) {
          _logger.e('RESOLVE_STREAM', 'Resolution failed', error: e);
          _logger.debugState.redirects += 'Resolution failed: $e\n';
          break; // Fallback to whatever URL we got so far
        }
      }
    }

    if (streamUrl.isEmpty) {
      throw const PortalException(
          message: 'Could not resolve stream URL.\nThis content may not be available.');
    }

    _logger.debugState.resolvedUrl = streamUrl;
    _logger.mag('CREATE_LINK_FINAL', 'Resolved: $streamUrl');
    return streamUrl;
  }

  // ─── Session Management ─────────────────────────────────

  Future<bool> reAuthenticate(String portalUrl, String macAddress) async {
    try {
      _client.clearSession();
      await handshake(portalUrl, macAddress);
      await getProfile();
      return true;
    } catch (e) {
      _logger.e('MAG', 'Re-auth failed', error: e);
      return false;
    }
  }

  void logout() {
    _isAuthenticated = false;
    _serverLoadPath = null;
    _client.clearSession();
    _logger.mag('SESSION', 'Logged out');
  }

  // ─── Internal Request ───────────────────────────────────

  Future<Map<String, dynamic>> _stalkerRequest({
    required String type,
    required String action,
    Map<String, String>? extraParams,
  }) async {
    if (_serverLoadPath == null) {
      throw const AuthException(
          message: 'Not connected to portal. Please login first.');
    }

    final params = <String, String>{
      'type': type,
      'action': action,
      'JsHttpRequest': '1-xml',
      if (_client.token != null) 'token': _client.token!,
      ...?extraParams,
    };

    _logger.mag('REQUEST', '→ $action [$type]');

    try {
      final response = await _client.dio.get(
        _serverLoadPath!,
        queryParameters: params,
        options: Options(
          validateStatus: (s) => s != null && s < 600,
          receiveTimeout: const Duration(seconds: 40),
        ),
      );

      if (response.statusCode == 429) {
        throw const ServerException(
            message: 'Rate limited. Please wait and try again.',
            statusCode: 429);
      }

      if (response.statusCode != null && response.statusCode! >= 400) {
        throw ServerException(
            message: 'Server ${response.statusCode} for $action',
            statusCode: response.statusCode);
      }

      Map<String, dynamic> data;
      if (response.data is Map<String, dynamic>) {
        data = response.data;
      } else if (response.data is String) {
        try {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        } catch (_) {
          data = {'js': response.data};
        }
      } else {
        data = {};
      }

      _logger.mag('RESPONSE', '← $action js=${data['js']?.runtimeType}');
      return data;
    } on DioException catch (e) {
      final errMessage = e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.receiveTimeout
          ? 'Connection timeout — check your network'
          : e.type == DioExceptionType.connectionError
              ? 'Cannot reach portal server'
              : 'Network error: ${e.message}';
      
      final err = ServerException(message: errMessage);
      _logger.e('NETWORK', err.message, error: e);
      throw err;
    } catch (e) {
      _logger.e('API', 'Unexpected error', error: e);
      rethrow;
    }
  }
}

import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/storage_service.dart';
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
  List<SubtitleInfo> lastResolvedSubtitles = [];

  bool get isAuthenticated => _isAuthenticated;
  String? get serverLoadPath => _serverLoadPath;
  ApiClient get client => _client;

  void setServerLoadPath(String path) {
    _serverLoadPath = path;
    _client.serverLoadPath = path;
  }

  void setAuthenticated(bool val) {
    _isAuthenticated = val;
  }

  // ─── Step 1: Handshake ──────────────────────────────────

  Future<String> handshake(
    String portalUrl,
    String macAddress, {
    String? stbModel,
    String? serialNumber,
    String? timezone,
    bool? urlEncodeMac,
  }) async {
    _logger.mag('HANDSHAKE', 'Starting with $portalUrl / $macAddress');
    _client.clearSession();
    _client.configure(
      portalUrl: portalUrl,
      macAddress: macAddress,
      serialNumber: serialNumber,
    );
    await _client.loadDeviceIdentity();
    
    _client.updateConfig(
      stbModel: stbModel,
      serialNumber: serialNumber,
      timezone: timezone,
      urlEncodeMac: urlEncodeMac,
    );

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

      if (js is Map<String, dynamic>) {
        if (js.containsKey('error') && js['error'] != null) {
          throw AuthException(message: js['error'].toString());
        }
        if (js.containsKey('msg') && js['msg'] != null) {
          final msg = js['msg'].toString();
          final blockMsg = js['block_msg']?.toString() ?? '';
          final cleanBlockMsg = blockMsg.replaceAll(RegExp(r'<[^>]*>'), '\n');
          throw AuthException(
            message: cleanBlockMsg.isNotEmpty 
              ? '$msg\n$cleanBlockMsg' 
              : msg
          );
        }
      }

      if (js is List && js.isEmpty) {
        throw const AuthException(
          message: 'The portal returned an empty handshake response.\n'
              'Please verify that your MAC address is active and registered on this portal.'
        );
      }

      String token = '';
      if (js is Map<String, dynamic>) {
        token = js['token']?.toString() ?? '';
      } else if (js is List && js.isNotEmpty) {
        try {
          token = js[0]['token']?.toString() ?? '';
        } catch (_) {}
      }

      if (token.isEmpty) {
        throw const AuthException(message: 'Empty token from handshake');
      }

      _client.setToken(token);
      _isAuthenticated = true;
      _logger.mag('HANDSHAKE', 'SUCCESS token=${token.substring(0, 8)}...');
      return token;
    } catch (e) {
      _logger.e('MAG', 'Handshake failed', error: e);
      // Clear endpoint cache on failure so we rediscover next time
      try {
        PreferencesService().saveDiscoveredEndpoint(portalUrl, '');
      } catch (_) {}
      if (e is AuthException) rethrow;
      throw AuthException(message: 'Handshake failed: $e');
    }
  }

  Future<String> _discoverEndpoint() async {
    final base = _portalBase!;
    
    // Check cache first to avoid rate limits (429)
    try {
      final cached = PreferencesService().getDiscoveredEndpoint(base);
      if (cached != null && cached.isNotEmpty) {
        _logger.mag('DISCOVER', 'Using cached endpoint: $cached');
        return cached;
      }
    } catch (e) {
      _logger.w('DISCOVER', 'Failed to read endpoint cache: $e');
    }

    // Resolve redirects of the base URL first
    String resolvedBase = base;
    try {
      _logger.mag('DISCOVER', 'Checking redirects for base: $base');
      final probeResponse = await _client.dio.get(
        base,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => true,
        ),
      );
      if (probeResponse.realUri.toString().isNotEmpty) {
        final finalUri = probeResponse.realUri;
        final resolvedUrl = '${finalUri.scheme}://${finalUri.host}${finalUri.hasPort && finalUri.port != 80 && finalUri.port != 443 ? ':${finalUri.port}' : ''}';
        if (resolvedUrl != base) {
          _logger.mag('DISCOVER', 'Portal URL redirects from $base to $resolvedUrl');
          resolvedBase = resolvedUrl;
          _client.updateConfig(portalUrl: resolvedBase);
          _portalBase = _client.portalUrl;
        }
      }
    } catch (e) {
      _logger.w('DISCOVER', 'Failed to resolve base URL redirects: $e');
    }

    // Normalize base — remove trailing slashes and known suffixes
    String cleanBase = resolvedBase;
    // Strip known path suffixes to get the bare domain
    for (final suffix in [
      '/stalker_portal/server/load.php',
      '/server/load.php',
      '/load.php',
      '/portal.php',
      '/stalker_portal/c/',
      '/stalker_portal/c',
      '/stalker_portal/',
      '/stalker_portal',
      '/c/',
      '/c',
    ]) {
      if (cleanBase.toLowerCase().endsWith(suffix)) {
        cleanBase = cleanBase.substring(0, cleanBase.length - suffix.length);
        break;
      }
    }
    while (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }

    // Common stalker portal endpoint paths (in priority order)
    // Covers: Ministra, Stalker Middleware, MAG portals, custom setups
    final pathSuffixes = [
      '/stalker_portal/server/load.php',
      '/server/load.php',
      '/portal.php',
      '/load.php',
      '/c/server/load.php',
    ];

    // Try each path with the original scheme first
    for (final suffix in pathSuffixes) {
      final path = '$cleanBase$suffix';
      final result = await _probeEndpoint(path);
      if (result != null) {
        _saveEndpointCache(base, result);
        return result;
      }
    }

    // If HTTP failed, try HTTPS as fallback (only if user entered HTTP)
    final uri = Uri.tryParse(cleanBase);
    if (uri != null && uri.scheme == 'http') {
      final httpsBase = cleanBase.replaceFirst('http://', 'https://');
      _logger.mag('DISCOVER', 'HTTP paths failed, trying HTTPS fallback...');
      for (final suffix in pathSuffixes) {
        final path = '$httpsBase$suffix';
        final result = await _probeEndpoint(path);
        if (result != null) {
          _saveEndpointCache(base, result);
          return result;
        }
      }
    }

    // Fallback: use the cleaned base + standard path
    final fallback = '$cleanBase/stalker_portal/server/load.php';
    _logger.mag('DISCOVER', 'No endpoint found, using fallback: $fallback');
    return fallback;
  }

  Future<void> _saveEndpointCache(String base, String path) async {
    try {
      await PreferencesService().saveDiscoveredEndpoint(base, path);
    } catch (e) {
      _logger.w('DISCOVER', 'Failed to cache endpoint: $e');
    }
  }

  /// Probes a single endpoint URL using a lightweight GET request.
  /// Sends a minimal request (no handshake) to check if the endpoint exists.
  /// Returns the working URL or null if this endpoint is not valid.
  Future<String?> _probeEndpoint(String path) async {
    try {
      _logger.mag('DISCOVER', 'Probing: $path');
      final response = await _client.dio.get(
        path,
        queryParameters: {
          'type': AppConfig.typeStb,
          'action': 'get_main_info',
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
    } catch (e) {
      _logger.mag('DISCOVER', 'Probe failed for $path: $e');
    }
    return null;
  }

  // ─── Step 2: Profile ────────────────────────────────────

  String? _parseRedirectBase(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    
    String path = uri.path;
    final serverIndex = path.indexOf('/server/');
    if (serverIndex != -1) {
      path = path.substring(0, serverIndex);
    } else {
      final loadIndex = path.indexOf('/load.php');
      if (loadIndex != -1) {
        path = path.substring(0, loadIndex);
      }
    }
    
    final authority = uri.hasPort && uri.port != 80 && uri.port != 443 
        ? '${uri.host}:${uri.port}' 
        : uri.host;
    
    return '${uri.scheme}://$authority$path';
  }

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
      final launcherProfileUrl = js['launcher_profile_url']?.toString() ?? '';
      if (launcherProfileUrl.isNotEmpty) {
        final redirectUrl = _parseRedirectBase(launcherProfileUrl);
        if (redirectUrl != null) {
          throw StalkerRedirectException(redirectUrl: redirectUrl);
        }
      }

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
    try {
      final response = await _stalkerRequest(
        type: AppConfig.typeStb,
        action: AppConfig.stalkerGetMainInfoAction,
      );
      final js = response['js'];
      if (js == null || js == false || js is! Map<String, dynamic>) {
        return const StalkerMainInfo(serverName: 'Stalker Portal');
      }
      return StalkerMainInfo.fromJson(js);
    } catch (e) {
      _logger.w('API', 'get_main_info not fully supported by this portal: $e');
      return const StalkerMainInfo(serverName: 'Stalker Portal');
    }
  }

  Future<void> setParentPassword(String newPassword) async {
    try {
      final res = await _stalkerRequest(
        type: AppConfig.typeStb,
        action: 'settings_set',
        extraParams: {
          'parent_password': newPassword,
          'parent_pass': newPassword,
        },
      );
      final js = res['js'];
      if (js == null || js == false) {
        throw Exception('Server rejected settings_set');
      }
    } catch (e) {
      _logger.w('API', 'settings_set failed, trying account/set_parent_password: $e');
      try {
        final res2 = await _stalkerRequest(
          type: 'account',
          action: 'set_parent_password',
          extraParams: {
            'password': newPassword,
            'parent_password': newPassword,
            'pass': newPassword,
            'repeat_pass': newPassword,
          },
        );
        final js2 = res2['js'];
        if (js2 == null || js2 == false) {
          throw Exception('Server rejected set_parent_password');
        }
      } catch (e2) {
        _logger.e('API', 'Failed to update parent password on server', error: e2);
        throw Exception('Stalker server rejected the password change request.');
      }
    }
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

  Future<Map<String, dynamic>> resolveEpisodeFileResponse({
    required String seriesId,
    required String episodeId,
    String? seasonId,
  }) async {
    _logger.mag('API', 'Resolving episode file response for seriesId=$seriesId, episodeId=$episodeId, seasonId=$seasonId');
    try {
      return await _stalkerRequest(
        type: AppConfig.typeVod,
        action: 'get_ordered_list',
        extraParams: {
          'movie_id': seriesId,
          if (seasonId != null && seasonId.isNotEmpty) 'season_id': seasonId,
          'episode_id': episodeId,
        },
      );
    } catch (e) {
      _logger.e('API', 'Failed to resolve episode file response', error: e);
      return {};
    }
  }

  // ─── Step 5: Specific Content Fetchers ──────────────────

  Future<List<Channel>> getAllChannels() async {
    // Try get_all_channels first (works on many portals)
    try {
      final response = await _stalkerRequest(
        type: AppConfig.typeItv,
        action: AppConfig.stalkerGetAllChannelsAction,
      );
      final js = response['js'];
      if (js != null && js != false) {
        List? raw;
        if (js is Map<String, dynamic>) {
          final rawData = js['data'];
          if (rawData is List) { raw = rawData; }
          else if (rawData is Map) { raw = rawData.values.toList(); }
        } else if (js is List) {
          raw = js;
        }
        if (raw != null && raw.isNotEmpty) {
          final channels = raw.whereType<Map<String, dynamic>>()
              .map((e) => Channel.fromJson(e, client: _client))
              .toList();
          if (channels.isNotEmpty) {
            _logger.mag('CHANNELS', 'get_all_channels returned ${channels.length} channels');
            return channels;
          }
        }
      }
    } catch (e) {
      _logger.w('CHANNELS', 'get_all_channels not supported, falling back to paginated fetch: $e');
    }

    // Fallback: paginate through get_ordered_list to collect ALL channels
    _logger.mag('CHANNELS', 'Falling back to paginated get_ordered_list for all channels');
    return _fetchAllChannelsPaginated(categoryId: null);
  }

  /// Fetches ALL channels for a category by paginating through get_ordered_list.
  Future<List<Channel>> getChannels({String? categoryId}) async {
    return _fetchAllChannelsPaginated(categoryId: categoryId);
  }

  /// Internal helper: fetches all pages of channels via get_ordered_list.
  Future<List<Channel>> _fetchAllChannelsPaginated({String? categoryId}) async {
    final allChannels = <Channel>[];
    int page = 1;
    const maxPages = 50; // Safety limit

    while (page <= maxPages) {
      final result = await getOrderedList(
        type: AppConfig.typeItv,
        categoryId: categoryId,
        page: page,
        sortBy: 'number',
      );

      final items = (result['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => Channel.fromJson(e, client: _client))
          .toList();

      allChannels.addAll(items);

      final totalPages = result['pages'] as int? ?? 1;
      _logger.mag('CHANNELS', 'Page $page/$totalPages: got ${items.length} channels (total so far: ${allChannels.length})');

      if (page >= totalPages || items.isEmpty) break;
      page++;
    }

    _logger.mag('CHANNELS', 'Paginated fetch complete: ${allChannels.length} total channels');
    return allChannels;
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
        if (rawData is List) { data = rawData; }
        else if (rawData is Map) { data = rawData.values.toList(); }
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

  Future<List<EpgProgram>> getSimpleEpg(String channelId) async {
    try {
      final response = await _stalkerRequest(
        type: AppConfig.typeItv,
        action: 'get_simple_epg',
        extraParams: {'ch_id': channelId},
      );
      final js = response['js'];
      if (js == null || js == false || (js is List && js.isEmpty) || (js is Map && (js['data'] == null || js['data'].isEmpty))) {
        throw Exception('get_simple_epg not supported or returned empty');
      }
      List? data;
      if (js is Map<String, dynamic>) {
        final rawData = js['data'];
        if (rawData is List) { data = rawData; }
        else if (rawData is Map) { data = rawData.values.toList(); }
      } else if (js is List) {
        data = js;
      }
      if (data == null || data.isEmpty) throw Exception('No EPG data');
      return data.whereType<Map<String, dynamic>>()
          .map((e) => EpgProgram.fromJson(e))
          .toList();
    } catch (_) {
      // Fallback: call get_short_epg with size=120 to get a large history/future list for Catch-Up!
      try {
        final response = await _stalkerRequest(
          type: AppConfig.typeItv,
          action: 'get_short_epg',
          extraParams: {'ch_id': channelId, 'size': '120'},
        );
        final js = response['js'];
        if (js == null || js == false) return [];
        List? data;
        if (js is Map<String, dynamic>) {
          final rawData = js['data'];
          if (rawData is List) { data = rawData; }
          else if (rawData is Map) { data = rawData.values.toList(); }
        } else if (js is List) {
          data = js;
        }
        if (data == null) return [];
        return data.whereType<Map<String, dynamic>>()
            .map((e) => EpgProgram.fromJson(e))
            .toList();
      } catch (e) {
        _logger.e('API', 'Failed to fetch short EPG fallback for channel $channelId', error: e);
        return [];
      }
    }
  }


  // ─── Step 6: Stream Resolution ──────────────────────────

  CreateLinkException _buildCreateLinkException(String message, String? portalError) {
    final netLogs = _logger.networkRequests;
    if (netLogs.isNotEmpty) {
      final lastLog = netLogs.last; // The create_link request log captured by interceptor
      return CreateLinkException(
        message: message,
        url: lastLog.url,
        method: lastLog.method,
        queryParams: lastLog.queryParams,
        requestBody: lastLog.requestBody,
        requestHeaders: lastLog.requestHeaders,
        cookiesSent: lastLog.requestCookies,
        responseStatusCode: lastLog.responseStatus,
        responseHeaders: lastLog.responseHeaders,
        rawResponseBody: lastLog.rawResponseBody,
        portalError: portalError,
      );
    }
    return CreateLinkException(
      message: message,
      url: _serverLoadPath ?? '',
      method: 'GET',
      queryParams: {},
      requestBody: null,
      requestHeaders: {},
      cookiesSent: '',
      responseHeaders: {},
      rawResponseBody: '',
      portalError: portalError,
    );
  }

  /// Resolves a MAG cmd string to a playable stream URL via create_link.
  ///
  /// The cmd from get_ordered_list (e.g. /media/464066.mpg or ffmpeg http://...)
  /// must be sent to create_link which returns the actual resolved stream URL.
  String _extractNumericId(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match != null ? match.group(0)! : '';
  }

  /// Resolves a MAG cmd string to a playable stream URL via create_link.
  ///
  /// The cmd from get_ordered_list (e.g. /media/464066.mpg or ffmpeg http://...)
  /// must be sent to create_link which returns the actual resolved stream URL.
  Future<String> createLink(
    String cmd,
    String type, {
    String? seriesId,
    Map<String, dynamic>? itemObject,
    String? parentSeriesId,
    String? archiveStart,
    String? archiveDuration,
  }) async {
    lastResolvedSubtitles = [];
    if (cmd.isEmpty) {
      throw Exception("Episode cmd missing");
    }
    final reqType = (type == AppConfig.typeSeries) ? AppConfig.typeVod : type;
    _logger.mag('CREATE_LINK', 'type=$type (reqType=$reqType) cmd=$cmd seriesId=$seriesId parentSeriesId=$parentSeriesId archiveStart=$archiveStart archiveDuration=$archiveDuration');
    
    // Diagnostic: Capture starting state
    _logger.debugState.selectedContent = 'Type: $type | Cmd: $cmd';
    _logger.debugState.cmd = cmd;
    _logger.debugState.cleanedCmd = UrlNormalizer.stripPlayerDirectives(cmd);

    String resolvedCmd = cmd;
    if ((type == AppConfig.typeSeries || reqType == AppConfig.typeVod) &&
        !resolvedCmd.startsWith('http') &&
        !resolvedCmd.startsWith('rtsp') &&
        !resolvedCmd.startsWith('/media/file_')) {
      _logger.mag('CREATE_LINK', 'Intercepted catalog cmd: $resolvedCmd. Resolving file ID...');
      try {
        final parentId = parentSeriesId ?? _extractNumericId(resolvedCmd);
        if (parentId.isNotEmpty) {
          if (type == AppConfig.typeSeries && itemObject != null) {
            // It's a Series Episode
            final episodeId = itemObject['id']?.toString() ?? '';
            final seasonId = itemObject['season_id']?.toString() ?? '';
            if (episodeId.isNotEmpty) {
              _logger.mag('CREATE_LINK', 'Querying get_ordered_list for series episode file: parent=$parentId, season=$seasonId, episode=$episodeId');
              final listRes = await _stalkerRequest(
                type: reqType,
                action: 'get_ordered_list',
                extraParams: {
                  'movie_id': parentId,
                  if (seasonId.isNotEmpty) 'season_id': seasonId,
                  'episode_id': episodeId,
                },
              );
              final listJs = listRes['js'];
              if (listJs != null && listJs != false) {
                final rawList = StalkerParser.extractList(listJs is Map ? listJs['data'] ?? listJs : listJs);
                if (rawList.isNotEmpty) {
                  final firstItem = rawList.first;
                  if (firstItem is Map<String, dynamic>) {
                    final fileId = firstItem['id']?.toString();
                    if (fileId != null && fileId.isNotEmpty) {
                      resolvedCmd = '/media/file_$fileId.mpg';
                      _logger.mag('CREATE_LINK', 'Resolved series episode to: $resolvedCmd');
                    }
                  }
                }
              }
            } else {
              _logger.w('CREATE_LINK', 'Cannot resolve series episode: episodeId is missing in itemObject: $itemObject');
            }
          } else {
            // It's a Movie
            _logger.mag('CREATE_LINK', 'Querying get_ordered_list for movie file: movie_id=$parentId');
            final listRes = await _stalkerRequest(
              type: reqType,
              action: 'get_ordered_list',
              extraParams: {
                'movie_id': parentId,
              },
            );
            final listJs = listRes['js'];
            if (listJs != null && listJs != false) {
              final rawList = StalkerParser.extractList(listJs is Map ? listJs['data'] ?? listJs : listJs);
              if (rawList.isNotEmpty) {
                final firstItem = rawList.first;
                if (firstItem is Map<String, dynamic>) {
                  final fileId = firstItem['id']?.toString();
                  if (fileId != null && fileId.isNotEmpty) {
                    resolvedCmd = '/media/file_$fileId.mpg';
                    _logger.mag('CREATE_LINK', 'Resolved movie to: $resolvedCmd');
                  }
                }
              }
            }
          }
        }
      } catch (e) {
        _logger.e('CREATE_LINK', 'Failed to resolve file command in createLink', error: e);
      }
    }

    String streamUrl = '';

    final params = {
      'cmd': resolvedCmd,
      if (reqType == AppConfig.typeVod) ...{
        'series': resolvedCmd.startsWith('/media/file_') ? '' : (seriesId ?? ''),
        'forced_storage': '',
        'disable_ad': '0',
        'download': '0',
        'force_ch_link_check': '0',
      } else ...{
        'forced_storage': '0',
        'disable_ad': '0',
        'volume': '100',
        'play_mode': '0',
        if (archiveStart != null) 'series': archiveStart,
        if (archiveDuration != null) 'duration': archiveDuration,
      }
    };
    _logger.debugState.requestPayload = params.toString();

    final actualReqType = (archiveStart != null) ? 'tv_archive' : reqType;

    Map<String, dynamic> response;
    try {
      response = await _stalkerRequest(
        type: actualReqType,
        action: AppConfig.stalkerCreateLinkAction,
        extraParams: params,
      );
    } catch (e) {
      _logger.debugState.lastError = e.toString();
      throw _buildCreateLinkException('Stream request failed: $e', 'network_error');
    }

    final js = response['js'];
    final rawText = response['text']?.toString() ?? '';
    final isTimeout = rawText.contains('Connection timeout') || rawText.contains('Failed to connect');

    _logger.debugState.rawResponse = js?.toString() ?? 'null';

    if (isTimeout) {
      throw _buildCreateLinkException(
        'The portal storage server is temporarily offline (Connection Timeout). Please try again later.',
        'connection_timeout'
      );
    }

    if (js == null || js == false) {
      throw _buildCreateLinkException('No stream data received from portal', 'empty_response');
    }

    String errorCode = '';

    if (js is Map<String, dynamic>) {
      streamUrl = js['cmd']?.toString() ?? js['url']?.toString() ?? '';
      errorCode = js['error']?.toString() ?? '';
      final rawSubs = js['subtitles'];
      if (rawSubs is List) {
        for (final sub in rawSubs) {
          if (sub is Map<String, dynamic>) {
            try {
              lastResolvedSubtitles.add(SubtitleInfo.fromJson(sub, baseUrl: _portalBase ?? _client.portalBase));
            } catch (_) {}
          }
        }
      }
    } else if (js is String) {
      streamUrl = js;
    }

    if (errorCode == 'nothing_to_play') {
      throw _buildCreateLinkException(
          'This content is currently unavailable on the server.\nPlease try another title.',
          'nothing_to_play'
      );
    }
    if (errorCode.isNotEmpty && streamUrl.isEmpty) {
      throw _buildCreateLinkException('Server error: $errorCode', errorCode);
    }

    streamUrl = UrlNormalizer.stripPlayerDirectives(streamUrl);

    // If it's an internal portal URL (e.g. localhost proxy), we MUST resolve it through our authenticated session.
    if (streamUrl.contains('localhost') || streamUrl.contains('127.0.0.1')) {
      final portalUri = Uri.tryParse(_client.portalUrl ?? '');
      final streamUri = Uri.tryParse(streamUrl);
      if (portalUri != null && streamUri != null) {
        streamUrl = streamUri.replace(
          scheme: portalUri.scheme,
          host: portalUri.host,
          port: portalUri.hasPort ? portalUri.port : null,
        ).toString();
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

  // ─── Telemetry & Synchronization ────────────────────────

  /// Extracts the file ID from a media command string.
  String _extractFileId(String cmd, String fallback) {
    final fileMatch = RegExp(r'file_(\d+)').firstMatch(cmd);
    if (fileMatch != null) return fileMatch.group(1)!;
    final mediaMatch = RegExp(r'/media/(\d+)').firstMatch(cmd);
    if (mediaMatch != null) return mediaMatch.group(1)!;
    return fallback;
  }

  /// Sends play-start events to the portal, matching STBEmu.
  Future<void> logStartPlay({
    required String videoId,
    required String cmd,
    required String resolvedUrl,
  }) async {
    _logger.mag('TELEMETRY_PLAY', 'Start videoId=$videoId cmd=$cmd');
    final fileId = _extractFileId(cmd, videoId);

    try {
      // 1. Send stb log with real_action=play
      final logParams = {
        'real_action': 'play',
        'param': '[object Object]',
        'content_id': fileId,
        'tmp_type': '2', // VOD
        'id': videoId,
        'cmd': resolvedUrl,
        'storage_id': '',
        'load': '',
        'error': '',
        'subtitles': '',
      };

      _stalkerRequest(
        type: AppConfig.typeStb,
        action: 'log',
        extraParams: logParams,
      ).then((_) {
        _logger.mag('TELEMETRY_PLAY', 'stb/log success');
      }).catchError((e) {
        _logger.e('TELEMETRY_PLAY', 'stb/log failed', error: e);
      });

      // 2. Set as played
      _stalkerRequest(
        type: AppConfig.typeVod,
        action: 'set_played',
        extraParams: {
          'video_id': videoId,
          'storage_id': '',
        },
      ).then((_) {
        _logger.mag('TELEMETRY_PLAY', 'vod/set_played success');
      }).catchError((e) {
        _logger.e('TELEMETRY_PLAY', 'vod/set_played failed', error: e);
      });

    } catch (e) {
      _logger.e('TELEMETRY_PLAY', 'Failed to dispatch start play logs', error: e);
    }
  }

  /// Sends play-stop events and syncs bookmarks with the portal.
  Future<void> logStopPlay({
    required String videoId,
    required String cmd,
    required String resolvedUrl,
    required int positionSeconds,
    String? seriesId,
  }) async {
    _logger.mag('TELEMETRY_STOP', 'Stop videoId=$videoId pos=$positionSeconds');
    final fileId = _extractFileId(cmd, videoId);

    try {
      // 1. Send stb log with real_action=stop
      final logParams = {
        'real_action': 'stop',
        'param': '',
        'content_id': '0',
        'tmp_type': '2',
        'storage_id': '',
      };

      _stalkerRequest(
        type: AppConfig.typeStb,
        action: 'log',
        extraParams: logParams,
      ).then((_) {
        _logger.mag('TELEMETRY_STOP', 'stb/log success');
      }).catchError((e) {
        _logger.e('TELEMETRY_STOP', 'stb/log failed', error: e);
      });

      // 2. Delete resolved stream link from portal session
      _stalkerRequest(
        type: AppConfig.typeVod,
        action: 'del_link',
        extraParams: {
          'item': resolvedUrl,
        },
      ).then((_) {
        _logger.mag('TELEMETRY_STOP', 'vod/del_link success');
      }).catchError((e) {
        _logger.e('TELEMETRY_STOP', 'vod/del_link failed', error: e);
      });

      // 3. Sync watch progress (set_not_ended)
      _stalkerRequest(
        type: AppConfig.typeVod,
        action: 'set_not_ended',
        extraParams: {
          'video_id': videoId,
          'series': seriesId ?? '0',
          'end_time': positionSeconds.toString(),
          'file_id': fileId,
        },
      ).then((_) {
        _logger.mag('TELEMETRY_STOP', 'vod/set_not_ended success');
      }).catchError((e) {
        _logger.e('TELEMETRY_STOP', 'vod/set_not_ended failed', error: e);
      });

    } catch (e) {
      _logger.e('TELEMETRY_STOP', 'Failed to dispatch stop play logs', error: e);
    }
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
          message: 'Server load path is not configured.');
    }

    final params = <String, String>{
      'type': type,
      'action': action,
      'JsHttpRequest': '1-xml',
      if (_client.token != null) 'token': _client.token!,
      ...?extraParams,
    };

    _logger.mag('REQUEST', '→ $action [$type] via Native Dio');

    try {
      final response = await _client.dio.get(
        _serverLoadPath!,
        queryParameters: params,
        options: Options(
          validateStatus: (s) => s != null && s < 600,
        ),
      );

      dynamic data = response.data;
      final rawBody = data?.toString() ?? '';
      final bodyPreview = rawBody.length > 300 ? rawBody.substring(0, 300) : rawBody;

      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }

      if (data is Map<String, dynamic>) {
        _logger.mag('RESPONSE', '← $action js=${data['js']?.runtimeType} data=$data');
        return data;
      }

      final ctype = response.headers.value('content-type') ?? 'unknown';
      final errorMsg = 'Invalid response format (status: ${response.statusCode}, type: $ctype). Preview: $bodyPreview';
      _logger.e('API', 'Request failed: $action - $errorMsg');
      throw PortalException(message: errorMsg);
    } on DioException catch (e) {
      _logger.e('API', 'Request failed: $action', error: e.message);
      throw PortalException(message: 'Request failed: ${e.message}');
    } catch (e) {
      if (e is PortalException) rethrow;
      _logger.e('API', 'Request failed: $action', error: e);
      throw PortalException(message: 'Request failed: $e');
    }
  }
}

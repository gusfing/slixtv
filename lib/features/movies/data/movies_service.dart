import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../auth/data/models.dart' show Category;
import '../domain/models.dart';

class MoviesService {
  final ApiClient _client;
  final AppLogger _logger = AppLogger();

  MoviesService(this._client);

  Future<Map<String, dynamic>> _stalkerRequest({
    required String action,
    Map<String, String>? extraParams,
  }) async {
    if (_client.portalUrl == null || _client.token == null) {
      throw const AuthException(message: 'Not authenticated.');
    }

    // Use the discovered server load path from handshake, NOT raw portal URL
    final loadPath = _client.serverLoadPath ??
        (_client.portalUrl!.endsWith('load.php')
            ? _client.portalUrl!
            : '${_client.portalUrl}/server/load.php');

    final params = <String, String>{
      'type': AppConfig.typeVod,
      'action': action,
      'JsHttpRequest': '1-xml',
      'token': _client.token!,
      ...?extraParams,
    };

    _logger.mag('MOVIES_REQ', '→ $action loadPath=$loadPath');

    try {
      final response = await _client.dio.get(
        loadPath,
        queryParameters: params,
        options: Options(
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      dynamic data = response.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {
          _logger.e('MOVIES_SERVICE', 'Failed to parse string response for $action');
        }
      }
      if (data is Map && data.containsKey('js')) {
        return data as Map<String, dynamic>;
      }
      return {'js': null};
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'Request failed: $action', error: e);
      throw PortalException(message: 'Network error: $e');
    }
  }

  Future<List<Category>> getCategories() async {
    try {
      final response = await _stalkerRequest(action: 'get_categories');
      final js = response['js'];
      
      final rawList = StalkerParser.extractList(js);
      return rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => Category.fromJson(e))
          .toList();
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'Categories failed', error: e);
      return [];
    }
  }

  Future<List<VodItem>> getOrderedList({String? categoryId, int page = 1}) async {
    final params = <String, String>{
      'p': page.toString(),
      'sortby': 'added',
      'hd': '0',
    };

    if (categoryId != null && categoryId.isNotEmpty && categoryId != '*') {
      params['category'] = categoryId;
    }

    try {
      final response = await _stalkerRequest(
        action: AppConfig.stalkerGetOrderedListAction,
        extraParams: params,
      );

      final js = response['js'];
      
      List items = [];
      if (js is Map<String, dynamic> && js.containsKey('data')) {
        items = StalkerParser.extractList(js['data']);
      } else {
        items = StalkerParser.extractList(js);
      }

      return items
          .whereType<Map<String, dynamic>>()
          .map((e) => VodItem.fromJson(e, _client))
          .toList();
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'getOrderedList failed', error: e);
      return [];
    }
  }

  Future<VodItem?> getVodInfo(VodItem item) async {
    try {
      final response = await _stalkerRequest(
        action: 'get_info',
        extraParams: {'movie_id': item.id},
      );
      
      final js = response['js'];
      if (js == null || js == false) return null;

      final bestCmd = StalkerParser.extractBestPlaybackCmd(
        {'cmd': item.cmd}, 
        response
      );

      if (js is Map<String, dynamic>) {
        final info = js['info'];
        if (info is Map<String, dynamic>) {
          final combined = {
            ...info, 
            'id': item.id,
            if (bestCmd != null && bestCmd.isNotEmpty) 'cmd': bestCmd,
          };
          return VodItem.fromJson(combined, _client);
        }
        return VodItem.fromJson({
          ...js, 
          'id': item.id,
          if (bestCmd != null && bestCmd.isNotEmpty) 'cmd': bestCmd,
        }, _client);
      }
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'get_info failed for ${item.id}', error: e);
    }
    return null;
  }

  Future<String> createVodLink(String extractedCmd, String movieId) async {
    _logger.mag('CREATE_VOD_LINK_REQ', 'initial cmd: $extractedCmd | movie_id: $movieId');
    
    // Fallback engine: Try multiple variations of the payload until the portal returns a valid stream.
    final fallbacks = [
      {'cmd': extractedCmd, 'movie_id': movieId, 'forced_storage': '0', 'disable_ad': '1'},
      {'cmd': 'ffmpeg $extractedCmd', 'movie_id': movieId, 'forced_storage': '0', 'disable_ad': '1'},
      {'cmd': extractedCmd.startsWith('/media/') ? '${_client.portalUrl}$extractedCmd' : extractedCmd, 'movie_id': movieId},
      {'cmd': extractedCmd}, // Strict fallback without movie_id
    ];

    String? lastErrorMsg;

    for (int i = 0; i < fallbacks.length; i++) {
      final payload = fallbacks[i];
      _logger.debugState.selectedContent = 'VOD: $movieId | Attempt: ${i + 1}';
      _logger.debugState.cmd = payload['cmd'] ?? '';
      _logger.debugState.cleanedCmd = UrlNormalizer.stripPlayerDirectives(payload['cmd'] ?? '');
      _logger.debugState.requestPayload = payload.toString();

      _logger.mag('CREATE_VOD_ATTEMPT', 'Attempt ${i + 1}: $payload');

      try {
        final response = await _stalkerRequest(
          action: AppConfig.stalkerCreateLinkAction,
          extraParams: payload,
        );

        final js = response['js'];
        _logger.debugState.rawResponse = js?.toString() ?? 'null';

        if (js == null || js == false) continue;

        String streamUrl = '';
        String errorCode = '';

        if (js is Map<String, dynamic>) {
          streamUrl = js['cmd']?.toString() ?? js['url']?.toString() ?? '';
          errorCode = js['error']?.toString() ?? '';
        } else if (js is String) {
          streamUrl = js;
        }

        if (errorCode == 'nothing_to_play' || streamUrl.isEmpty) {
          lastErrorMsg = errorCode;
          continue; // Try next fallback
        }

        // We got a stream! Resolve it if it's an internal proxy.
        return await _resolveStream(streamUrl);
      } catch (e) {
        lastErrorMsg = e.toString();
        _logger.debugState.lastError = lastErrorMsg;
        continue;
      }
    }

    throw PortalException(message: 'Could not resolve a valid stream URL after all fallbacks. Last error: $lastErrorMsg');
  }

  Future<String> _resolveStream(String streamUrl) async {
    String finalStreamUrl = UrlNormalizer.stripPlayerDirectives(streamUrl);

    if (finalStreamUrl.contains('localhost') || finalStreamUrl.contains('127.0.0.1')) {
      final portalUri = Uri.tryParse(_client.portalUrl ?? '');
      if (portalUri != null) {
        finalStreamUrl = finalStreamUrl.replaceAll('localhost', portalUri.host).replaceAll('127.0.0.1', portalUri.host);
      }
      
      _logger.mag('RESOLVE_VOD_STREAM', 'Resolving internal stream: $finalStreamUrl');
      _logger.debugState.redirects = 'Starting manual VOD resolution for: $finalStreamUrl\n';
      
      int redirectCount = 0;
      while (redirectCount < 5) {
        try {
          final response = await _client.dio.get(
            finalStreamUrl,
            options: Options(
              followRedirects: false,
              validateStatus: (status) => status != null && status < 500,
              responseType: ResponseType.stream,
            ),
          );

          _logger.debugState.redirects += '[$redirectCount] HTTP ${response.statusCode} - $finalStreamUrl\n';

          if (response.statusCode == 301 || response.statusCode == 302 || response.statusCode == 303 || response.statusCode == 307 || response.statusCode == 308) {
            final location = response.headers.value('location');
            response.data?.close();
            if (location != null && location.isNotEmpty) {
              finalStreamUrl = location;
              redirectCount++;
              continue;
            }
          }

          response.data?.close();
          break;
        } catch (e) {
          _logger.e('RESOLVE_VOD_STREAM', 'Resolution failed', error: e);
          _logger.debugState.redirects += 'Resolution failed: $e\n';
          break;
        }
      }
    }

    if (finalStreamUrl.isEmpty || finalStreamUrl == 'null') {
      throw const PortalException(message: 'Stream URL is invalid or empty.');
    }

    _logger.debugState.resolvedUrl = finalStreamUrl;
    _logger.mag('CREATE_VOD_LINK_FINAL', 'Resolved: $finalStreamUrl');
    return finalStreamUrl;
  }
}

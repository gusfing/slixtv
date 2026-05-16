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

  Future<VodItem?> getVodInfo(String movieId) async {
    try {
      final response = await _stalkerRequest(
        action: 'get_info',
        extraParams: {'movie_id': movieId},
      );
      
      final js = response['js'];
      if (js == null || js == false) return null;

      if (js is Map<String, dynamic>) {
        final info = js['info'];
        if (info is Map<String, dynamic>) {
          String? fileCmd;
          if (js['files'] is List && (js['files'] as List).isNotEmpty) {
            final firstFile = (js['files'] as List).first;
            if (firstFile is Map) {
              fileCmd = firstFile['cmd']?.toString() ?? firstFile['url']?.toString();
            }
          }
          final combined = {
            ...info, 
            'id': movieId,
            if (fileCmd != null && fileCmd.isNotEmpty) 'cmd': fileCmd,
          };
          return VodItem.fromJson(combined, _client);
        }
        return VodItem.fromJson({...js, 'id': movieId}, _client);
      }
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'get_info failed for $movieId', error: e);
    }
    return null;
  }

  Future<String> createVodLink(String cmd, String movieId) async {
    _logger.mag('CREATE_VOD_LINK_REQ', 'cmd: $cmd | movie_id: $movieId');
    
    // Diagnostic: Capture starting state
    _logger.debugState.selectedContent = 'VOD: $movieId | Cmd: $cmd';
    _logger.debugState.cmd = cmd;

    final cleanedDirectUrl = UrlNormalizer.normalize(cmd, _client.portalUrl);
    _logger.debugState.cleanedCmd = cleanedDirectUrl;

    if (cleanedDirectUrl.startsWith('http://') || cleanedDirectUrl.startsWith('https://')) {
      _logger.mag('CREATE_VOD_LINK_BYPASS', 'Using direct URL: $cleanedDirectUrl');
      _logger.debugState.resolvedUrl = cleanedDirectUrl;
      return cleanedDirectUrl;
    }

    final params = {
      'cmd': cmd,
      'movie_id': movieId,
      'forced_storage': '0',
      'disable_ad': '1',
      'volume': '100',
    };
    _logger.debugState.requestPayload = params.toString();

    Map<String, dynamic> response;
    try {
      response = await _stalkerRequest(
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
      throw const PortalException(message: 'Portal returned no stream data.');
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
          message: 'This content is currently unavailable on the server. Try another title.');
    }
    
    if (errorCode.isNotEmpty && streamUrl.isEmpty) {
      throw PortalException(message: 'Server error: $errorCode');
    }

    final finalUrl = UrlNormalizer.normalize(streamUrl, _client.portalUrl);

    if (finalUrl.isEmpty) {
      throw const PortalException(message: 'Could not resolve a valid stream URL.');
    }

    _logger.debugState.resolvedUrl = finalUrl;
    _logger.mag('CREATE_VOD_LINK_FINAL', 'Resolved: $finalUrl');
    return finalUrl;
  }
}

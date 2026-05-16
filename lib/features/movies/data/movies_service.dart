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

      String? bestCmd;
      final orderedItemCmd = item.cmd;
      String parserCmd = '';

      if (orderedItemCmd.isNotEmpty) {
        bestCmd = orderedItemCmd;
      }

      if (bestCmd == null || bestCmd.isEmpty) {
        final extracted = StalkerParser.extractBestPlaybackCmd(
          item.toJson(),
          response,
        );

        if (extracted != null && extracted.isNotEmpty) {
          parserCmd = extracted;
          bestCmd = extracted;
        }
      }

      // Reject generic /media/ URLs as they are unplayable
      if (bestCmd != null && bestCmd.startsWith('/media/')) {
        bestCmd = null;
      }

      _logger.mag('MOVIE_CMD_SELECTED', 
        'orderedItemCmd: $orderedItemCmd | parserCmd: $parserCmd | finalCmd: $bestCmd'
      );

      if (js is Map<String, dynamic>) {
        final info = js['info'];
        if (info is Map<String, dynamic>) {
          final combined = {
            ...info, 
            'id': item.id,
          };
          if (bestCmd != null && bestCmd.isNotEmpty) {
            combined['cmd'] = bestCmd;
          }
          return VodItem.fromJson(combined, _client);
        }
        
        final combinedJs = {
          ...js, 
          'id': item.id,
        };
        if (bestCmd != null && bestCmd.isNotEmpty) {
          combinedJs['cmd'] = bestCmd;
        }
        return VodItem.fromJson(combinedJs, _client);
      }
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'get_info failed for ${item.id}', error: e);
    }
    return null;
  }
}

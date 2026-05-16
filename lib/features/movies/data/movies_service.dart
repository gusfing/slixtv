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
          .map((e) {
            final item = VodItem.fromJson(e, _client);
            _logger.mag('MOVIE_LIST_ITEM', 'movieId=${item.id} title=${item.name} cmd=${item.cmd}');
            return item;
          })
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

      // The cmd from ordered_list (item.cmd) is the source of truth.
      // We ONLY override it if item.cmd is empty or /media/ AND get_info provides something better.
      String chosenCmd = item.cmd;

      if (chosenCmd.isEmpty || chosenCmd.startsWith('/media/')) {
        // item.cmd is bad — try to find something better in get_info
        final infoCmd = _extractCmdFromInfoResponse(js);
        if (infoCmd != null && infoCmd.isNotEmpty && !infoCmd.startsWith('/media/')) {
          chosenCmd = infoCmd;
        }
        // If still bad, keep whatever we had (even /media/) so the field isn't null
      }

      // Hard failure log — so we can see exactly what happened
      if (chosenCmd.isEmpty || chosenCmd.startsWith('/media/')) {
        _logger.mag('INVALID_MOVIE_CMD', 
          'itemCmd=${item.cmd} | infoJsCmd=${_extractCmdFromInfoResponse(js)} | chosenCmd=$chosenCmd'
        );
      }

      _logger.mag('MOVIE_CMD_SELECTED',
        'orderedItemCmd=${item.cmd} | chosenCmd=$chosenCmd'
      );

      // Use copyWith to enrich metadata from get_info WITHOUT touching cmd
      if (js is Map<String, dynamic>) {
        final info = (js['info'] is Map<String, dynamic>) 
            ? js['info'] as Map<String, dynamic> 
            : js;

        return item.copyWith(
          cmd: chosenCmd,
          description: _nonNull(info['description']) ?? _nonNull(info['descr']) ?? item.description,
          year: _nonNull(info['year']) ?? item.year,
          rating: _nonNull(info['rating_imdb'])?.toString() ??
              _nonNull(info['rating_kinopoisk'])?.toString() ??
              _nonNull(info['rate'])?.toString() ??
              item.rating,
          director: _nonNull(info['director']) ?? item.director,
          actors: _nonNull(info['actors']) ?? _nonNull(info['cast']) ?? item.actors,
          genre: _nonNull(info['genres_str']) ??
              _nonNull(info['genre_str']) ??
              _nonNull(info['genre']) ??
              item.genre,
          duration: _nonNull(info['time']) ??
              _nonNull(info['length']) ??
              _nonNull(info['duration']) ??
              item.duration,
        );
      }
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'get_info failed for ${item.id}', error: e);
    }
    return null;
  }

  /// Extracts a cmd string from a get_info response 'js' object.
  /// Tries js.cmd, js.info.cmd, js.files[0].cmd in order.
  String? _extractCmdFromInfoResponse(dynamic js) {
    if (js is! Map<String, dynamic>) return null;
    
    final directCmd = js['cmd']?.toString();
    if (directCmd != null && directCmd.isNotEmpty) return directCmd;

    final info = js['info'];
    if (info is Map<String, dynamic>) {
      final infoCmd = info['cmd']?.toString();
      if (infoCmd != null && infoCmd.isNotEmpty) return infoCmd;
    }

    final files = js['files'];
    if (files != null) {
      final filesList = StalkerParser.extractList(files);
      if (filesList.isNotEmpty && filesList.first is Map) {
        final fileCmd = (filesList.first as Map)['cmd']?.toString();
        if (fileCmd != null && fileCmd.isNotEmpty) return fileCmd;
      }
    }
    return null;
  }

  static String? _nonNull(dynamic v) {
    if (v == null || v == 'null' || v == '' || v == 0 || v == '0.0') return null;
    final s = v.toString();
    return s.isEmpty || s == 'null' ? null : s;
  }
}

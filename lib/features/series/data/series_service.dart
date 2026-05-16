import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../auth/data/models.dart' show Category;
import '../domain/models.dart';

class SeriesService {
  final ApiClient _client;
  final AppLogger _logger = AppLogger();

  SeriesService(this._client);

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
      'type': AppConfig.typeSeries,
      'action': action,
      'JsHttpRequest': '1-xml',
      'token': _client.token!,
      ...?extraParams,
    };

    _logger.mag('SERIES_REQ', '→ $action loadPath=$loadPath');

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
          _logger.e('SERIES_SERVICE', 'Failed to parse string response for $action');
        }
      }
      if (data is Map && data.containsKey('js')) {
        return data as Map<String, dynamic>;
      }
      return {'js': null};
    } catch (e) {
      _logger.e('SERIES_SERVICE', 'Request failed: $action', error: e);
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
      _logger.e('SERIES_SERVICE', 'Categories failed', error: e);
      return [];
    }
  }

  Future<List<SeriesItem>> getOrderedList({String? categoryId, int page = 1}) async {
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
          .map((e) => SeriesItem.fromJson(e, _client))
          .toList();
    } catch (e) {
      _logger.e('SERIES_SERVICE', 'getOrderedList failed', error: e);
      return [];
    }
  }

  Future<List<Season>> getSeriesInfo(String seriesId) async {
    _logger.mag('SERIES_INFO', 'id=$seriesId');
    try {
      final response = await _stalkerRequest(
        action: AppConfig.stalkerGetOrderedListAction,
        extraParams: {
          'movie_id': seriesId,
        },
      );

      final js = response['js'];
      if (js == null || js == false) return [];

      String? seriesCmd;
      if (js is Map<String, dynamic>) {
        seriesCmd = js['cmd']?.toString();
      }

      final seasons = <Season>[];
      final flatEpisodes = <Episode>[];

      void processEpisodeList(List eps, String seasonName, int seasonNum) {
        final parsedEps = <Episode>[];
        for (int i = 0; i < eps.length; i++) {
          final ep = eps[i];
          if (ep is Map<String, dynamic>) {
            parsedEps.add(Episode.fromJson(ep, i, _client, seriesCmd: seriesCmd));
          }
        }
        if (parsedEps.isNotEmpty) {
          seasons.add(Season(
            id: seasonNum.toString(),
            name: seasonName,
            seasonNumber: seasonNum,
            episodes: parsedEps,
          ));
        }
      }

      // Scenario 1: Flat Array Directly
      if (js is List) {
        for (int i = 0; i < js.length; i++) {
          if (js[i] is Map<String, dynamic>) {
            flatEpisodes.add(Episode.fromJson(js[i], flatEpisodes.length, _client, seriesCmd: seriesCmd));
          }
        }
      }
      
      // Scenario 2: Nested Data Array or Dictionary Mapping
      if (js is Map<String, dynamic>) {
        final data = js['data'];
        
        if (data is List) {
          for (int i = 0; i < data.length; i++) {
            final item = data[i];
            if (item is Map<String, dynamic>) {
              // Some portals nest episodes in a 'series' array inside the season object
              final seriesSub = item['series'];
              if (seriesSub is List) {
                processEpisodeList(seriesSub, item['name']?.toString() ?? 'Season ${i + 1}', i + 1);
              } else {
                flatEpisodes.add(Episode.fromJson(item, flatEpisodes.length, _client, seriesCmd: seriesCmd));
              }
            }
          }
        } else if (data is Map) {
          // Dictionary-mapped seasons (e.g., {"1": [...], "2": [...]})
          data.forEach((key, value) {
            if (value is List) {
              final seasonNum = int.tryParse(key.toString()) ?? seasons.length + 1;
              processEpisodeList(value, 'Season $key', seasonNum);
            }
          });
        }
      }

      if (seasons.isNotEmpty) return seasons;
      if (flatEpisodes.isNotEmpty) {
        return [Season(id: '1', name: 'Season 1', seasonNumber: 1, episodes: flatEpisodes)];
      }
    } catch (e) {
      _logger.e('SERIES_INFO', 'Failed for id=$seriesId', error: e);
    }
    return [];
  }
}

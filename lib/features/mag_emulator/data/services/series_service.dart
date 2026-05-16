import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/content_models.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';

class SeriesService {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;
  final StreamResolver streamResolver;

  SeriesService({
    required this.dio,
    required this.sessionManager,
    required this.deviceIdentity,
    required this.streamResolver,
  });

  String get _url {
    if (sessionManager.portalBaseUrl == null || sessionManager.portalEndpoint == null) {
      throw Exception('Portal endpoint not discovered');
    }
    return '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
  }

  Map<String, String> get _headers {
    return MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );
  }

  Future<dynamic> _makeRequest(Map<String, dynamic> queryParameters) async {
    final response = await dio.get(
      _url,
      queryParameters: queryParameters,
      options: Options(headers: _headers),
    );
    
    final parsed = ResponseParser.parseResponse(response);
    return parsed['js'];
  }

  List<dynamic> _normalizeDataList(dynamic jsData) {
    if (jsData == false || jsData == null) return [];
    if (jsData is List) return jsData;
    if (jsData is Map) {
      if (jsData.containsKey('data') && jsData['data'] is List) {
        return jsData['data'] as List;
      }
      return jsData.values.toList();
    }
    return [];
  }

  Future<List<MagCategory>> getCategories() async {
    final jsData = await _makeRequest({
      'type': 'series',
      'action': 'get_categories',
    });

    final list = _normalizeDataList(jsData);
    return list.map((e) => MagCategory.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<MagSeries>> getSeriesByCategory(String categoryId, {int page = 1}) async {
    final jsData = await _makeRequest({
      'type': 'series',
      'action': 'get_ordered_list',
      'category': categoryId,
      'p': page.toString(),
    });

    final list = _normalizeDataList(jsData);
    final baseUrl = sessionManager.portalBaseUrl ?? '';
    return list.map((e) => MagSeries.fromMap(e as Map<String, dynamic>, baseUrl)).toList();
  }

  Future<MagSeries?> getSeriesMetadata(String seriesId) async {
    final jsData = await _makeRequest({
      'type': 'series',
      'action': 'get_info',
      'series_id': seriesId,
    });

    if (jsData == false || jsData == null) return null;

    Map<String, dynamic>? dataMap;
    if (jsData is Map) {
      if (jsData.containsKey('series')) {
         dataMap = jsData['series'] as Map<String, dynamic>?;
      } else {
         dataMap = jsData as Map<String, dynamic>;
      }
    } else if (jsData is List && jsData.isNotEmpty) {
      dataMap = jsData.first as Map<String, dynamic>;
    }

    if (dataMap != null) {
      final baseUrl = sessionManager.portalBaseUrl ?? '';
      return MagSeries.fromMap(dataMap, baseUrl);
    }
    return null;
  }

  Future<List<MagSeason>> getSeasonData(String seriesId) async {
    // This is often a complex parsing logic since it can be different formats
    final jsData = await _makeRequest({
      'type': 'series',
      'action': 'get_ordered_list',
      'series_id': seriesId,
    });

    if (jsData == false || jsData == null) return [];

    final Map<String, List<MagEpisode>> seasonsMap = {};

    void processEpisodeList(List<dynamic> list) {
      for (var item in list) {
        if (item is Map<String, dynamic>) {
          // Format 1: Nested object with season_number and episodes array
          if (item.containsKey('series') && item['series'] is List) {
            final seasonNum = item['season_number']?.toString() ?? item['season']?.toString() ?? '1';
            if (!seasonsMap.containsKey(seasonNum)) seasonsMap[seasonNum] = [];
            for (var ep in item['series']) {
              if (ep is Map<String, dynamic>) {
                seasonsMap[seasonNum]!.add(MagEpisode.fromMap(ep, seasonNum));
              }
            }
          } 
          // Format 2: Flat episode list with season field
          else {
             final seasonNum = item['season']?.toString() ?? '1';
             if (!seasonsMap.containsKey(seasonNum)) seasonsMap[seasonNum] = [];
             seasonsMap[seasonNum]!.add(MagEpisode.fromMap(item, seasonNum));
          }
        }
      }
    }

    if (jsData is List) {
      processEpisodeList(jsData);
    } else if (jsData is Map) {
      // Format 3: Map-based structure with season IDs as keys
      if (jsData.containsKey('data') && jsData['data'] is List) {
         processEpisodeList(jsData['data']);
      } else {
        jsData.forEach((key, value) {
          final seasonNum = key.toString();
          if (!seasonsMap.containsKey(seasonNum)) seasonsMap[seasonNum] = [];
          if (value is List) {
            for (var ep in value) {
              if (ep is Map<String, dynamic>) {
                 seasonsMap[seasonNum]!.add(MagEpisode.fromMap(ep, seasonNum));
              }
            }
          }
        });
      }
    }

    final List<MagSeason> result = [];
    seasonsMap.forEach((seasonNumber, episodes) {
      result.add(MagSeason(seasonNumber: seasonNumber, episodes: episodes));
    });

    // Sort seasons
    result.sort((a, b) => (int.tryParse(a.seasonNumber) ?? 0).compareTo(int.tryParse(b.seasonNumber) ?? 0));
    
    return result;
  }

  Future<String> createPlaybackLink(String episodeCmd, String seriesId) async {
    return await streamResolver.resolveStreamUrl('series', episodeCmd, series: seriesId);
  }
}

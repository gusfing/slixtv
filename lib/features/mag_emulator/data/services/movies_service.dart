import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/content_models.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';

class MoviesService {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;
  final StreamResolver streamResolver;

  MoviesService({
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
    if (jsData == false || jsData == null) {
      return [];
    }
    if (jsData is List) {
      return jsData;
    }
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
      'type': 'vod',
      'action': 'get_categories',
    });

    final list = _normalizeDataList(jsData);
    return list.map((e) => MagCategory.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<MagMovie>> getMoviesByCategory(String categoryId, {int page = 1, String sort = 'added'}) async {
    final jsData = await _makeRequest({
      'type': 'vod',
      'action': 'get_ordered_list',
      'category': categoryId,
      'p': page.toString(),
      'sortby': sort,
    });

    final list = _normalizeDataList(jsData);
    final baseUrl = sessionManager.portalBaseUrl ?? '';
    return list.map((e) => MagMovie.fromMap(e as Map<String, dynamic>, baseUrl)).toList();
  }

  Future<MagMovie?> getMovieMetadata(String movieId) async {
    final jsData = await _makeRequest({
      'type': 'vod',
      'action': 'get_info',
      'movie_id': movieId,
    });

    if (jsData == false || jsData == null) return null;

    Map<String, dynamic>? dataMap;
    if (jsData is Map) {
      if (jsData.containsKey('movie')) {
         dataMap = jsData['movie'] as Map<String, dynamic>?;
      } else {
         dataMap = jsData as Map<String, dynamic>;
      }
    } else if (jsData is List && jsData.isNotEmpty) {
      dataMap = jsData.first as Map<String, dynamic>;
    }

    if (dataMap != null) {
      final baseUrl = sessionManager.portalBaseUrl ?? '';
      return MagMovie.fromMap(dataMap, baseUrl);
    }

    return null;
  }

  Future<String> createPlaybackLink(String movieCmd) async {
    return await streamResolver.resolveStreamUrl('vod', movieCmd);
  }
}

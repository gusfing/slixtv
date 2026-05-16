import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/content_models.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';

class LiveTvService {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;
  final StreamResolver streamResolver;

  LiveTvService({
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
      // Handle PHP associative array format
      return jsData.values.toList();
    }
    return [];
  }

  Future<List<MagCategory>> getCategories() async {
    final jsData = await _makeRequest({
      'type': 'itv',
      'action': 'get_genres',
    });

    final list = _normalizeDataList(jsData);
    return list.map((e) => MagCategory.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<List<MagChannel>> getAllChannels() async {
    final jsData = await _makeRequest({
      'type': 'itv',
      'action': 'get_all_channels',
    });

    final list = _normalizeDataList(jsData);
    final baseUrl = sessionManager.portalBaseUrl ?? '';
    return list.map((e) => MagChannel.fromMap(e as Map<String, dynamic>, baseUrl)).toList();
  }

  Future<List<MagChannel>> getChannelsByCategory(String categoryId) async {
    final jsData = await _makeRequest({
      'type': 'itv',
      'action': 'get_ordered_list',
      'genre': categoryId,
    });

    final list = _normalizeDataList(jsData);
    final baseUrl = sessionManager.portalBaseUrl ?? '';
    return list.map((e) => MagChannel.fromMap(e as Map<String, dynamic>, baseUrl)).toList();
  }

  Future<List<MagEpg>> getEPG(String channelId) async {
    final jsData = await _makeRequest({
      'type': 'itv',
      'action': 'get_short_epg',
      'ch_id': channelId,
    });

    final list = _normalizeDataList(jsData);
    return list.map((e) => MagEpg.fromMap(e as Map<String, dynamic>)).toList();
  }

  Future<String> createPlaybackLink(String channelCmd) async {
    return await streamResolver.resolveStreamUrl('itv', channelCmd);
  }
}

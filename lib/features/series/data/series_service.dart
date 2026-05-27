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

  // ─── Internal Request Helper ───────────────────────────────────────────────

  Future<Map<String, dynamic>> _stalkerRequest({
    required String action,
    Map<String, String>? extraParams,
  }) async {
    final params = <String, String>{
      'type': AppConfig.typeVod,
      'action': action,
      'JsHttpRequest': '1-xml',
      ...?extraParams,
    };

    _logger.mag('SERIES_REQ', '→ $action via Native Dio');

    try {
      final response = await _client.dio.get(
        _client.serverLoadPath!,
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
        return data;
      }

      final ctype = response.headers.value('content-type') ?? 'unknown';
      final errorMsg = 'Invalid response format (status: ${response.statusCode}, type: $ctype). Preview: $bodyPreview';
      _logger.e('SERIES_SERVICE', 'Request failed: $action - $errorMsg');
      throw PortalException(message: errorMsg);
    } catch (e) {
      if (e is PortalException) rethrow;
      _logger.e('SERIES_SERVICE', 'Request failed: $action', error: e);
      throw PortalException(message: 'Network error: $e');
    }
  }

  // ─── Category Helpers ──────────────────────────────────────────────────────

  bool _isSeriesCategory(Category cat) {
    final title = cat.title.toLowerCase();
    final alias = cat.alias.toLowerCase();
    return title.contains('series') ||
        title.contains('serial') ||
        title.contains('drama') ||
        title.contains('natok') ||
        title.contains('show') ||
        title.contains('rhyme') ||
        title.contains('kids collection') ||
        alias.contains('series') ||
        alias.contains('serial') ||
        alias.contains('drama') ||
        alias.contains('natok') ||
        alias.contains('show') ||
        alias.contains('rhyme') ||
        alias.contains('kids_collection');
  }

  // ─── Public API ────────────────────────────────────────────────────────────

  /// Returns VOD categories that look like series/show categories.
  Future<List<Category>> getCategories() async {
    try {
      final response = await _stalkerRequest(action: 'get_categories');
      final js = response['js'];
      if (js == null || js == false) return [];

      final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
      final allCats = rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => Category.fromJson(e))
          .toList();
      return allCats.where(_isSeriesCategory).toList();
    } catch (e) {
      _logger.e('SERIES_SERVICE', 'getCategories failed', error: e);
      return [];
    }
  }

  /// Returns series items (is_series=1) optionally filtered by category.
  Future<List<SeriesItem>> getOrderedList({String? categoryId, int page = 1}) async {
    try {
      final params = <String, String>{
        'p': page.toString(),
        'sortby': 'added',
        'hd': '0',
        'is_series': '1',
      };
      if (categoryId != null &&
          categoryId.isNotEmpty &&
          categoryId != '*' &&
          categoryId != 'all') {
        params['category'] = categoryId;
      }
      final response = await _stalkerRequest(
        action: 'get_ordered_list',
        extraParams: params,
      );
      final js = response['js'];
      if (js == null || js == false) return [];

      final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
      return rawList
          .whereType<Map<String, dynamic>>()
          .map((e) => SeriesItem.fromJson(e, _client))
          .toList();
    } catch (e) {
      _logger.e('SERIES_SERVICE', 'getOrderedList failed', error: e);
      return [];
    }
  }

  /// Fetches episode list for a series by its parent ID (movie_id).
  ///
  /// Stalker returns a flat episode list when you pass movie_id=<seriesId>.
  /// Each episode item carries a `series_num` (episode number within season)
  /// and optionally a `season_num` or category hint.  We group by
  /// season_num → Season → [Episode].
  Future<List<Season>> getSeriesInfo(String seriesId) async {
    _logger.mag('SERIES_INFO', 'id=$seriesId via Native Dio');
    try {
      // Fetch all episodes for this parent series
      final response = await _stalkerRequest(
        action: 'get_ordered_list',
        extraParams: {
          'movie_id': seriesId,
          'sortby': 'added',
        },
      );

      final js = response['js'];
      if (js == null || js == false) {
        _logger.w('SERIES_INFO', 'Empty js for series $seriesId');
        return [];
      }

      final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
      _logger.mag('SERIES_INFO', 'Got ${rawList.length} episode items for $seriesId');

      if (rawList.isEmpty) return [];

      // ── Group by season ────────────────────────────────────────────────────
      // Episodes may have `season_num`, `s_num`, `season`, or just a numeric
      // sequence.  Fall back to a single Season 1 if no season info exists.
      final Map<int, List<Map<String, dynamic>>> bySeasonNum = {};

      for (int i = 0; i < rawList.length; i++) {
        final ep = rawList[i];
        if (ep is! Map<String, dynamic>) continue;

        final seasonNum = _extractSeasonNum(ep, i);
        bySeasonNum.putIfAbsent(seasonNum, () => []).add(ep);
      }

      final seasons = <Season>[];
      int globalIndex = 0;

      for (final seasonNum in (bySeasonNum.keys.toList()..sort())) {
        final rawEps = bySeasonNum[seasonNum]!;
        final episodes = <Episode>[];

        for (int i = 0; i < rawEps.length; i++) {
          episodes.add(Episode.fromJson(rawEps[i], globalIndex++, _client));
        }

        seasons.add(Season(
          id: seasonNum.toString(),
          name: 'Season $seasonNum',
          seasonNumber: seasonNum,
          episodes: episodes,
        ));
      }

      seasons.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      _logger.mag('SERIES_INFO',
          'Built ${seasons.length} season(s) for series $seriesId');
      return seasons;
    } catch (e) {
      _logger.e('SERIES_INFO', 'Failed for series $seriesId', error: e);
      return [];
    }
  }

  /// Extracts the season number from an episode JSON map.
  /// Falls back to 1 if no season field is present.
  int _extractSeasonNum(Map<String, dynamic> ep, int fallbackIndex) {
    final candidates = [
      ep['season_num'],
      ep['s_num'],
      ep['season'],
      ep['series_season'],
    ];
    for (final c in candidates) {
      final n = int.tryParse(c?.toString() ?? '');
      if (n != null && n > 0) return n;
    }
    return 1; // default: all episodes in Season 1
  }
}

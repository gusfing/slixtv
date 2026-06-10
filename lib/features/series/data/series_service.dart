import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../auth/data/models.dart' show Category;
import '../domain/models.dart';

class StalkerPaginationState {
  int nextPortalPage = 1;
  bool portalHasMore = true;
}

class SeriesService {
  final ApiClient _client;
  final AppLogger _logger = AppLogger();

  final Map<String, StalkerPaginationState> _paginationStates = {};

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
    
    // 1. Explicitly exclude categories that contain movies on this portal
    if (title.contains('kids rhymes') ||
        title.contains('kids collection') ||
        title.contains('stage dramas') ||
        title.contains('stage drama') ||
        title.contains('natok') ||
        title.contains('kids movies') ||
        alias.contains('kids_rhymes') ||
        alias.contains('kids_collection') ||
        alias.contains('stage_drama') ||
        alias.contains('natok')) {
      return false;
    }
    
    // Special check for Punjabi kids series which contains movies
    if (title == 'punjabi | kids series') {
      return false;
    }

    // 2. Match the valid series categories
    return title.contains('series') ||
        title.contains('serial') ||
        title.contains('tv serial') ||
        title.contains('anime') ||
        title.contains('documentary') ||
        title.contains('arabic sub') ||
        title.contains('music albums') ||
        title.contains('korean drama') ||
        title.contains('political shows') ||
        title.contains('sports | events') ||
        title.contains('cricket events') ||
        (title.contains('adult') && title.contains('celebrity')) ||
        alias.contains('series') ||
        alias.contains('serial') ||
        alias.contains('anime') ||
        alias.contains('documentary') ||
        alias.contains('arabic_sub') ||
        alias.contains('music_albums') ||
        alias.contains('k-drama') ||
        alias.contains('political_shows') ||
        alias.contains('sporting_events') ||
        alias.contains('celebrity');
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
  Future<List<SeriesItem>> getOrderedList({String? categoryId, int page = 1, String? search}) async {
    try {
      final key = '${categoryId ?? ""}_${search ?? ""}';
      if (page == 1) {
        _paginationStates.remove(key);
        _logger.mag('SERIES_SERVICE', 'Resetting Stalker Series page tracking for key: $key');
      }
      final state = _paginationStates.putIfAbsent(key, () => StalkerPaginationState());

      final List<SeriesItem> accumulatedSeries = [];
      int pagesFetchedThisCall = 0;

      // Only apply is_series client-side filtering when browsing without a
      // specific category (e.g. dashboard count). When a category is selected,
      // trust the category assignment.
      final bool hasSpecificCategory = categoryId != null &&
          categoryId.isNotEmpty &&
          categoryId != '*' &&
          categoryId != 'all';

      while (state.portalHasMore && accumulatedSeries.length < 14 && pagesFetchedThisCall < 10) {
        final currentPortalPage = state.nextPortalPage;
        _logger.mag('SERIES_SERVICE', 'Fetching Stalker Series portal page $currentPortalPage (accumulated: ${accumulatedSeries.length})');

        final params = <String, String>{
          'p': currentPortalPage.toString(),
          'sortby': 'added',
          'hd': '0',
          if (search != null && search.isNotEmpty) 'search': search,
        };
        if (hasSpecificCategory) {
          params['category'] = categoryId!;
        }

        final response = await _stalkerRequest(
          action: 'get_ordered_list',
          extraParams: params,
        );
        final js = response['js'];
        if (js == null || js == false) {
          state.portalHasMore = false;
          break;
        }

        final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
        if (rawList.isEmpty) {
          state.portalHasMore = false;
          break;
        }

        final List<SeriesItem> pageSeries;
        if (hasSpecificCategory) {
          // Trust category — include all items
          pageSeries = rawList
              .whereType<Map<String, dynamic>>()
              .map((e) => SeriesItem.fromJson(e, _client))
              .toList();
        } else {
          // No category filter — only keep series items from the global list
          pageSeries = rawList
              .whereType<Map<String, dynamic>>()
              .where((json) {
                final isSeries = json['is_series'] == 1 ||
                                 json['is_series'] == '1' ||
                                 json['is_series'] == true ||
                                 json['is_series'] == 'true';
                return isSeries;
              })
              .map((e) => SeriesItem.fromJson(e, _client))
              .toList();
        }

        accumulatedSeries.addAll(pageSeries);

        if (rawList.length < 14) {
          state.portalHasMore = false;
        }

        state.nextPortalPage++;
        pagesFetchedThisCall++;
      }

      _logger.mag('SERIES_SERVICE', 'getOrderedList completed. Returned ${accumulatedSeries.length} series (portalHasMore=${state.portalHasMore}, nextPortalPage=${state.nextPortalPage})');
      return accumulatedSeries;
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
  Future<List<Season>> getSeriesInfo(String seriesId, {String? seriesCmd}) async {
    _logger.mag('SERIES_INFO', 'id=$seriesId via Native Dio');
    try {
      String effectiveSeriesCmd = seriesCmd ?? '';

      // Fetch the top-level list (seasons or flat episodes)
      final response = await _stalkerRequest(
        action: 'get_ordered_list',
        extraParams: {
          'movie_id': seriesId,
          'sortby': 'added',
        },
      );
      debugPrint('RAW_SERIES_EPISODE_RESPONSE: $response');

      final js = response['js'];
      if (js == null || js == false) {
        _logger.w('SERIES_INFO', 'Empty js for series $seriesId');
        return [];
      }

      final rawList = StalkerParser.extractList(js is Map ? js['data'] ?? js : js);
      _logger.mag('SERIES_INFO', 'Got ${rawList.length} top-level items for $seriesId');

      if (rawList.isEmpty) return [];

      final hasSeasons = rawList.any((e) =>
          e is Map<String, dynamic> &&
          (e['is_season'] == true ||
              e['is_season'] == 'true' ||
              e['is_season'] == 1 ||
              e['is_season'] == '1'));

      final List<Map<String, dynamic>> allEpisodesRaw = [];

      if (hasSeasons) {
        _logger.mag('SERIES_INFO', 'Detected season-based series. Fetching episodes for each season...');
        for (final item in rawList) {
          if (item is! Map<String, dynamic>) continue;
          final isSeason = item['is_season'] == true ||
              item['is_season'] == 'true' ||
              item['is_season'] == 1 ||
              item['is_season'] == '1';
          if (isSeason) {
            final seasonId = item['id']?.toString() ?? '';
            final seasonNumStr = item['season_number']?.toString() ?? '';
            if (seasonId.isNotEmpty) {
              _logger.mag('SERIES_INFO', 'Fetching episodes for season_id=$seasonId (Season $seasonNumStr)');
              try {
                final epResponse = await _stalkerRequest(
                  action: 'get_ordered_list',
                  extraParams: {
                    'movie_id': seriesId,
                    'season_id': seasonId,
                  },
                );
                debugPrint('RAW_SERIES_EPISODE_RESPONSE: $epResponse');
                final epJs = epResponse['js'];
                if (epJs != null && epJs != false) {
                  final epList = StalkerParser.extractList(epJs is Map ? epJs['data'] ?? epJs : epJs);
                  _logger.mag('SERIES_INFO', 'Season $seasonId returned ${epList.length} episodes');
                  for (final ep in epList) {
                    if (ep is Map<String, dynamic>) {
                      final mutableEp = Map<String, dynamic>.from(ep);
                      mutableEp['season_id'] = seasonId;
                      if (seasonNumStr.isNotEmpty && mutableEp['season_num'] == null) {
                        mutableEp['season_num'] = seasonNumStr;
                      }
                      allEpisodesRaw.add(mutableEp);
                    }
                  }
                }
              } catch (e) {
                _logger.e('SERIES_INFO', 'Failed to fetch episodes for season $seasonId', error: e);
              }
            }
          } else {
            allEpisodesRaw.add(item);
          }
        }
      } else {
        _logger.mag('SERIES_INFO', 'Detected flat series. Using original list of episodes.');
        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            allEpisodesRaw.add(item);
          }
        }
      }

      if (allEpisodesRaw.isEmpty) return [];

      // ── Group by season ────────────────────────────────────────────────────
      // Episodes may have `season_num`, `s_num`, `season`, or just a numeric
      // sequence.  Fall back to a single Season 1 if no season info exists.
      final Map<int, List<Map<String, dynamic>>> bySeasonNum = {};

      for (int i = 0; i < allEpisodesRaw.length; i++) {
        final ep = allEpisodesRaw[i];
        final seasonNum = _extractSeasonNum(ep, i);
        bySeasonNum.putIfAbsent(seasonNum, () => []).add(ep);
      }

      final seasons = <Season>[];
      int globalIndex = 0;

      for (final seasonNum in (bySeasonNum.keys.toList()..sort())) {
        final rawEps = List<Map<String, dynamic>>.from(bySeasonNum[seasonNum]!.reversed);
        rawEps.sort((a, b) {
          int? aNum;
          final aName = a['name']?.toString() ?? a['title']?.toString() ?? '';
          if (aName.isNotEmpty) {
            final match = RegExp(r'(?:episode|ep|ep\.|e)\s*(\d+)', caseSensitive: false).firstMatch(aName);
            if (match != null) aNum = int.tryParse(match.group(1) ?? '');
          }

          int? bNum;
          final bName = b['name']?.toString() ?? b['title']?.toString() ?? '';
          if (bName.isNotEmpty) {
            final match = RegExp(r'(?:episode|ep|ep\.|e)\s*(\d+)', caseSensitive: false).firstMatch(bName);
            if (match != null) bNum = int.tryParse(match.group(1) ?? '');
          }

          aNum ??= int.tryParse(a['series_number']?.toString() ?? '') ??
              int.tryParse(a['series_num']?.toString() ?? '') ??
              int.tryParse(a['episode_num']?.toString() ?? '');
          bNum ??= int.tryParse(b['series_number']?.toString() ?? '') ??
              int.tryParse(b['series_num']?.toString() ?? '') ??
              int.tryParse(b['episode_num']?.toString() ?? '');

          if (aNum != null && bNum != null) {
            return aNum.compareTo(bNum);
          }
          final aDate = a['date_add']?.toString() ?? a['added']?.toString() ?? '';
          final bDate = b['date_add']?.toString() ?? b['added']?.toString() ?? '';
          if (aDate.isNotEmpty && bDate.isNotEmpty) {
            return aDate.compareTo(bDate);
          }
          return 0;
        });
        final episodes = <Episode>[];

        for (int i = 0; i < rawEps.length; i++) {
          episodes.add(Episode.fromJson(rawEps[i], globalIndex++, _client, seriesCmd: effectiveSeriesCmd));
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

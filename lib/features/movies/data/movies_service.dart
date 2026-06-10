import 'dart:convert';
import 'package:dio/dio.dart';
import '../../../core/config/app_config.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/stalker_parser.dart';
import '../../auth/data/models.dart' show Category, SubtitleInfo;
import '../domain/models.dart';

class StalkerPaginationState {
  int nextPortalPage = 1;
  bool portalHasMore = true;
}

class MoviesService {
  final ApiClient _client;
  final AppLogger _logger = AppLogger();
  List<SubtitleInfo> lastResolvedSubtitles = [];

  final Map<String, StalkerPaginationState> _paginationStates = {};

  MoviesService(this._client);

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

    _logger.mag('MOVIES_REQ', '→ $action via Native Dio');

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
      final bodyPreview = rawBody.length > 500 ? rawBody.substring(0, 500) : rawBody;

      // Log raw portal response for key actions
      if (action == 'get_ordered_list' || action == 'get_description' || action == 'create_link') {
        _logger.mag('RAW_RESPONSE', '[$action] ${bodyPreview.length > 200 ? bodyPreview.substring(0, 200) : bodyPreview}');
      }

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
      _logger.e('MOVIES_SERVICE', 'Request failed: $action - $errorMsg');
      throw PortalException(message: errorMsg);
    } catch (e) {
      if (e is PortalException) rethrow;
      _logger.e('MOVIES_SERVICE', 'Request failed: $action', error: e);
      throw PortalException(message: 'Network error: $e');
    }
  }

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
      return allCats.where((cat) => !_isSeriesCategory(cat)).toList();
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'Categories failed', error: e);
      return [];
    }
  }

  Future<List<VodItem>> getOrderedList({String? categoryId, int page = 1, String? search}) async {
    try {
      final key = '${categoryId ?? ""}_${search ?? ""}';
      if (page == 1) {
        _paginationStates.remove(key);
        _logger.mag('MOVIES_SERVICE', 'Resetting Stalker VOD page tracking for key: $key');
      }
      final state = _paginationStates.putIfAbsent(key, () => StalkerPaginationState());

      final List<VodItem> accumulatedMovies = [];
      int pagesFetchedThisCall = 0;

      // Only apply is_series client-side filtering when browsing without a
      // specific category (e.g. dashboard "latest" count). When a category
      // is selected, trust the category assignment — the portal's is_series
      // field is unreliable and filtering causes empty results.
      final bool hasSpecificCategory = categoryId != null &&
          categoryId.isNotEmpty &&
          categoryId != '*' &&
          categoryId != 'all';

      while (state.portalHasMore && accumulatedMovies.length < 14 && pagesFetchedThisCall < 10) {
        final currentPortalPage = state.nextPortalPage;
        _logger.mag('MOVIES_SERVICE', 'Fetching Stalker VOD portal page $currentPortalPage (accumulated: ${accumulatedMovies.length})');

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

        final List<VodItem> pageMovies;
        if (hasSpecificCategory) {
          // Trust category — include all items
          pageMovies = rawList
              .whereType<Map<String, dynamic>>()
              .map((e) => VodItem.fromJson(e, _client))
              .toList();
        } else {
          // No category filter — exclude series items from the global list
          pageMovies = rawList
              .whereType<Map<String, dynamic>>()
              .where((json) {
                final isSeries = json['is_series'] == 1 ||
                                 json['is_series'] == '1' ||
                                 json['is_series'] == true ||
                                 json['is_series'] == 'true';
                return !isSeries;
              })
              .map((e) => VodItem.fromJson(e, _client))
              .toList();
        }

        accumulatedMovies.addAll(pageMovies);

        if (rawList.length < 14) {
          state.portalHasMore = false;
        }

        state.nextPortalPage++;
        pagesFetchedThisCall++;
      }

      _logger.mag('MOVIES_SERVICE', 'getOrderedList completed. Returned ${accumulatedMovies.length} movies (portalHasMore=${state.portalHasMore}, nextPortalPage=${state.nextPortalPage})');
      return accumulatedMovies;
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'getOrderedList failed', error: e);
      return [];
    }
  }

  Future<VodItem?> getVodInfo(VodItem item) async {
    try {
      _logger.mag('MOVIES_SERVICE', 'getVodInfo: Attempting get_description for movie ${item.id}');
      var response = await _stalkerRequest(
        action: 'get_description',
        extraParams: {'movie_id': item.id},
      );
      
      var js = response['js'];
      if (js == null || js == false) {
        _logger.mag('MOVIES_SERVICE', 'get_description returned js=false/null for movie ${item.id}. Trying compatibility fallback get_info...');
        response = await _stalkerRequest(
          action: 'get_info',
          extraParams: {'movie_id': item.id},
        );
        js = response['js'];
      }

      if (js != null && js != false) {
        final movieJson = js;
        _logger.mag('MOVIES_SERVICE', 'FULL_MOVIE_JSON: $movieJson');
      }

      if (js == null || js == false) {
        _logger.mag('MOVIES_SERVICE', 'Both get_description and get_info failed for movie ${item.id}. Fetching files from get_ordered_list...');
        try {
          final listRes = await _stalkerRequest(
            action: 'get_ordered_list',
            extraParams: {'movie_id': item.id},
          );
          final listJs = listRes['js'];
          if (listJs != null && listJs != false) {
            final rawList = StalkerParser.extractList(listJs is Map ? listJs['data'] ?? listJs : listJs);
            if (rawList.isNotEmpty) {
              final firstItem = rawList.first;
              if (firstItem is Map<String, dynamic>) {
                final fileId = firstItem['id']?.toString();
                if (fileId != null && fileId.isNotEmpty) {
                  final newCmd = '/media/file_$fileId.mpg';
                  _logger.mag('MOVIES_SERVICE', 'Resolved movie ${item.id} file ID $fileId -> command $newCmd');
                  js = {
                    'cmd': newCmd,
                    'movie': firstItem,
                    'info': firstItem,
                  };
                }
              }
            }
          }
        } catch (e) {
          _logger.e('MOVIES_SERVICE', 'Failed to retrieve movie files from get_ordered_list for movie ${item.id}', error: e);
        }
      }

      if (js == null || js == false) {
        _logger.e('MOVIES_SERVICE', 'Both get_description and get_info failed (returned false/null) for movie ${item.id}');
        return null;
      }

      // ALWAYS prefer cmd from get_description/get_info over get_ordered_list.
      // get_ordered_list returns simplified cmd like /media/452019.mpg
      // get_description/get_info returns the REAL cmd like /media/file_3285742.mpg
      final infoCmd = _extractCmdFromInfoResponse(js);
      String chosenCmd = item.cmd;

      _logger.mag('GETVOD_CMD_TRACE', 'movieId=${item.id} orderedListCmd=${item.cmd} descriptionCmd=$infoCmd');

      if (infoCmd != null && infoCmd.isNotEmpty) {
        // ALWAYS use description cmd — it's the real portal path
        chosenCmd = infoCmd;
        _logger.mag('GETVOD_CMD_OVERRIDE', 'Using description cmd: $chosenCmd (was: ${item.cmd})');
      }

      if (chosenCmd.isEmpty) {
        _logger.mag('INVALID_MOVIE_CMD', 
          'itemCmd=${item.cmd} | infoJsCmd=$infoCmd | chosenCmd=$chosenCmd'
        );
      }

      _logger.mag('MOVIE_CMD_SELECTED',
        'orderedItemCmd=${item.cmd} | descriptionCmd=$infoCmd | chosenCmd=$chosenCmd'
      );

      // Use copyWith to enrich metadata from get_info/get_description WITHOUT touching cmd
      if (js is Map<String, dynamic>) {
        final info = (js['info'] is Map<String, dynamic>) 
            ? js['info'] as Map<String, dynamic> 
            : ((js['movie'] is Map<String, dynamic>)
                ? js['movie'] as Map<String, dynamic>
                : js);

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
          rawJson: js,
        );
      }
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'getVodInfo failed for ${item.id}', error: e);
    }
    return null;
  }

  /// Extracts a cmd string from a get_info/get_description response 'js' object.
  /// Tries js.cmd, js.info.cmd, js.movie.cmd, js.files[0].cmd in order.
  String? _extractCmdFromInfoResponse(dynamic js) {
    if (js is! Map<String, dynamic>) return null;
    
    final directCmd = js['cmd']?.toString();
    if (directCmd != null && directCmd.isNotEmpty) return directCmd;

    final info = js['info'];
    if (info is Map<String, dynamic>) {
      final infoCmd = info['cmd']?.toString();
      if (infoCmd != null && infoCmd.isNotEmpty) return infoCmd;
    }

    final movie = js['movie'];
    if (movie is Map<String, dynamic>) {
      final movieCmd = movie['cmd']?.toString();
      if (movieCmd != null && movieCmd.isNotEmpty) return movieCmd;
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

  CreateLinkException _buildCreateLinkException(String message, String? portalError) {
    final netLogs = _logger.networkRequests;
    if (netLogs.isNotEmpty) {
      final lastLog = netLogs.last; // The create_link request log captured by interceptor
      return CreateLinkException(
        message: message,
        url: lastLog.url,
        method: lastLog.method,
        queryParams: lastLog.queryParams,
        requestBody: lastLog.requestBody,
        requestHeaders: lastLog.requestHeaders,
        cookiesSent: lastLog.requestCookies,
        responseStatusCode: lastLog.responseStatus,
        responseHeaders: lastLog.responseHeaders,
        rawResponseBody: lastLog.rawResponseBody,
        portalError: portalError,
      );
    }
    return CreateLinkException(
      message: message,
      url: _client.serverLoadPath ?? '',
      method: 'GET',
      queryParams: {},
      requestBody: null,
      requestHeaders: {},
      cookiesSent: '',
      responseHeaders: {},
      rawResponseBody: '',
      portalError: portalError,
    );
  }

  /// VOD-specific create_link engine.
  Future<String> createVodLink(VodItem movie) async {
    lastResolvedSubtitles = [];
    final cmd = movie.cmd;
    if (cmd.startsWith('http://') || cmd.startsWith('https://')) {
      return cmd;
    }
    final movieId = movie.id;
    _logger.mag('CREATE_VOD_LINK_START', 'movieId=$movieId cmd=$cmd');
    _logger.debugState.selectedContent = 'VOD: $movieId | cmd: $cmd';
    _logger.debugState.cmd = cmd;

    // Use movie.cmd (which should already be set by getVodInfo from get_description).
    // Fallback to rawJson['cmd'] only if movie.cmd is empty.
    final rawCmd = cmd.isNotEmpty ? cmd : (movie.rawJson?['cmd']?.toString() ?? '');

    _logger.mag('CREATE_VOD_LINK_TRACE', 'movieId=$movieId cmd=$cmd rawJson.cmd=${movie.rawJson?['cmd']} FINAL=$rawCmd');

    if (rawCmd.isEmpty) {
      throw _buildCreateLinkException('No cmd available for this movie. Portal did not provide a media path.', 'empty_cmd');
    }

    String resolvedCmd = rawCmd;
    String? directUrl;
    if (resolvedCmd.isNotEmpty && 
        !resolvedCmd.startsWith('http') && 
        !resolvedCmd.startsWith('rtsp') && 
        !resolvedCmd.startsWith('/media/file_')) {
      _logger.mag('MOVIES_SERVICE', 'createVodLink: cmd "$resolvedCmd" is not a file command. Attempting resolution via get_ordered_list...');
      try {
        final listRes = await _stalkerRequest(
          action: 'get_ordered_list',
          extraParams: {'movie_id': movieId},
        );
        final listJs = listRes['js'];
        if (listJs != null && listJs != false) {
          final rawList = StalkerParser.extractList(listJs is Map ? listJs['data'] ?? listJs : listJs);
          if (rawList.isNotEmpty) {
            final firstItem = rawList.first;
            if (firstItem is Map<String, dynamic>) {
              directUrl = firstItem['cmd']?.toString() ?? firstItem['url']?.toString();
              final fileId = firstItem['id']?.toString();
              if (fileId != null && fileId.isNotEmpty) {
                resolvedCmd = '/media/file_$fileId.mpg';
                _logger.mag('MOVIES_SERVICE', 'createVodLink: Resolved movie $movieId to file command "$resolvedCmd" (directUrl: $directUrl)');
              }
            }
          }
        }
      } catch (e) {
        _logger.e('MOVIES_SERVICE', 'createVodLink: Failed to resolve file command for movie $movieId', error: e);
      }
    }

    try {
      final params = {
        'cmd': resolvedCmd,
        'series': '',
        'forced_storage': '',
        'disable_ad': '0',
        'download': '0',
        'force_ch_link_check': '0',
      };
      
      _logger.mag('CREATE_VOD_LINK_PARAMS', params.toString());
      _logger.debugState.requestPayload = params.toString();

      final response = await _stalkerRequest(
        action: 'create_link',
        extraParams: params,
      );

      final js = response['js'];
      final rawText = response['text']?.toString() ?? '';
      final isTimeout = rawText.contains('Connection timeout') || rawText.contains('Failed to connect');

      if (isTimeout) {
        if (directUrl != null && directUrl.isNotEmpty) {
          _logger.mag('MOVIES_SERVICE', 'create_link timed out. Falling back to direct URL: $directUrl');
          return await _resolveStreamUrl(directUrl, movieId);
        }
        throw _buildCreateLinkException(
          'The portal storage server is temporarily offline (Connection Timeout). Please try again later.',
          'connection_timeout'
        );
      }

      if (js == null || js == false) {
        if (directUrl != null && directUrl.isNotEmpty) {
          _logger.mag('MOVIES_SERVICE', 'create_link returned empty response. Falling back to direct URL: $directUrl');
          return await _resolveStreamUrl(directUrl, movieId);
        }
        throw _buildCreateLinkException('No stream URL returned', 'empty_response');
      }

      String streamUrl = '';
      String errorCode = '';
      if (js is Map<String, dynamic>) {
        streamUrl = js['cmd']?.toString() ?? js['url']?.toString() ?? '';
        errorCode = js['error']?.toString() ?? '';
        final rawSubs = js['subtitles'];
        if (rawSubs is List) {
          for (final sub in rawSubs) {
            if (sub is Map<String, dynamic>) {
              try {
                lastResolvedSubtitles.add(SubtitleInfo.fromJson(sub, baseUrl: _client.portalBase));
              } catch (_) {}
            }
          }
        }
      } else if (js is String) {
        streamUrl = js;
      }

      if (errorCode == 'nothing_to_play') {
        if (directUrl != null && directUrl.isNotEmpty) {
          _logger.mag('MOVIES_SERVICE', 'create_link returned nothing_to_play. Falling back to direct URL: $directUrl');
          return await _resolveStreamUrl(directUrl, movieId);
        }
        throw _buildCreateLinkException(
          'The portal is currently unable to play this item (nothing_to_play).',
          'nothing_to_play'
        );
      } else if (errorCode.isNotEmpty && streamUrl.isEmpty) {
        if (directUrl != null && directUrl.isNotEmpty) {
          _logger.mag('MOVIES_SERVICE', 'create_link returned error $errorCode. Falling back to direct URL: $directUrl');
          return await _resolveStreamUrl(directUrl, movieId);
        }
        throw _buildCreateLinkException('Server error: $errorCode', errorCode);
      }

      if (streamUrl.isEmpty) {
        if (directUrl != null && directUrl.isNotEmpty) {
          _logger.mag('MOVIES_SERVICE', 'create_link resolved stream URL is empty. Falling back to direct URL: $directUrl');
          return await _resolveStreamUrl(directUrl, movieId);
        }
        throw _buildCreateLinkException('Resolved stream URL is empty', 'empty_stream_url');
      }

      _logger.mag('CREATE_VOD_RESOLVED', 'Resolved stream via Native API: $streamUrl');
      return await _resolveStreamUrl(streamUrl, movieId);
    } catch (e) {
      _logger.e('CREATE_VOD_FAILED', 'movieId=$movieId error=$e');
      if (directUrl != null && directUrl.isNotEmpty) {
        _logger.mag('MOVIES_SERVICE', 'createVodLink failed with exception. Falling back to direct URL: $directUrl');
        try {
          return await _resolveStreamUrl(directUrl, movieId);
        } catch (ex) {
          _logger.e('MOVIES_SERVICE', 'Fallback direct URL playback failed', error: ex);
        }
      }
      if (e is CreateLinkException) rethrow;
      throw _buildCreateLinkException(
        'Could not resolve stream. Last error: $e',
        'resolve_error'
      );
    }
  }

  /// Resolves internal/localhost stream URLs using the authenticated Dio session,
  /// tracing redirects manually — same as the Live TV engine.
  Future<String> _resolveStreamUrl(String streamUrl, String movieId) async {
    // Strip player directives (ffmpeg, ffrt, etc.)
    String url = streamUrl.trim();
    const prefixes = ['ffmpeg ', 'ffrt3 ', 'ffrt ', 'auto '];
    for (final p in prefixes) {
      if (url.toLowerCase().startsWith(p.toLowerCase())) {
        url = url.substring(p.length).trim();
        break;
      }
    }
    final httpIdx = url.indexOf('http');
    if (httpIdx > 0 && !url.substring(0, httpIdx).contains('://')) {
      url = url.substring(httpIdx);
    }

    _logger.debugState.cleanedCmd = url;

    // Resolve internal proxy (localhost → real portal host)
    if (url.contains('localhost') || url.contains('127.0.0.1')) {
      final portalUri = Uri.tryParse(_client.portalUrl ?? '');
      if (portalUri != null) {
        url = url
            .replaceAll('localhost', portalUri.host)
            .replaceAll('127.0.0.1', portalUri.host);
      }

      _logger.mag('RESOLVE_VOD_STREAM', 'movieId=$movieId resolving: $url');
      _logger.debugState.redirects = 'Resolving: $url\n';

      int redirects = 0;
      while (redirects < 5) {
        try {
          final resp = await _client.dio.get(
            url,
            options: Options(
              followRedirects: false,
              validateStatus: (s) => s != null && s < 500,
              responseType: ResponseType.stream,
            ),
          );

          _logger.debugState.redirects += '[$redirects] HTTP ${resp.statusCode} - $url\n';

          final status = resp.statusCode ?? 0;
          if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
            final location = resp.headers.value('location');
            resp.data?.close();
            if (location != null && location.isNotEmpty) {
              url = location;
              redirects++;
              continue;
            }
          }
          resp.data?.close();
          break;
        } catch (e) {
          _logger.e('RESOLVE_VOD_STREAM', 'redirect trace failed', error: e);
          _logger.debugState.redirects += 'Error: $e\n';
          break;
        }
      }
    }

    if (url.isEmpty) {
      throw const PortalException(message: 'Resolved stream URL is empty');
    }

    _logger.debugState.resolvedUrl = url;
    _logger.mag('CREATE_VOD_FINAL', 'movieId=$movieId finalUrl=$url');
    return url;
  }
}

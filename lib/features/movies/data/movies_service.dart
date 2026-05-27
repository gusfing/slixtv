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
      return allCats.where((c) => !_isSeriesCategory(c)).toList();
    } catch (e) {
      _logger.e('MOVIES_SERVICE', 'Categories failed', error: e);
      return [];
    }
  }

  Future<List<VodItem>> getOrderedList({String? categoryId, int page = 1}) async {
    try {
      final params = <String, String>{
        'p': page.toString(),
        'sortby': 'added',
        'hd': '0',
      };
      if (categoryId != null && categoryId.isNotEmpty && categoryId != '*' && categoryId != 'all') {
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
        action: 'get_description',
        extraParams: {'movie_id': item.id},
      );
      
      final js = response['js'];
      if (js == null || js == false) return null;

      // ALWAYS prefer cmd from get_description over get_ordered_list.
      // get_ordered_list returns simplified cmd like /media/452019.mpg
      // get_description returns the REAL cmd like /media/file_3285742.mpg
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
          rawJson: js,
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

  /// VOD-specific create_link engine.
  Future<String> createVodLink(VodItem movie) async {
    final cmd = movie.cmd;
    final movieId = movie.id;
    _logger.mag('CREATE_VOD_LINK_START', 'movieId=$movieId cmd=$cmd');
    _logger.debugState.selectedContent = 'VOD: $movieId | cmd: $cmd';
    _logger.debugState.cmd = cmd;

    // Use movie.cmd (which should already be set by getVodInfo from get_description).
    // Fallback to rawJson['cmd'] only if movie.cmd is empty.
    final rawCmd = cmd.isNotEmpty ? cmd : (movie.rawJson?['cmd']?.toString() ?? '');

    _logger.mag('CREATE_VOD_LINK_TRACE', 'movieId=$movieId cmd=$cmd rawJson.cmd=${movie.rawJson?['cmd']} FINAL=$rawCmd');

    if (rawCmd.isEmpty) {
      throw const PortalException(message: 'No cmd available for this movie. Portal did not provide a media path.');
    }

    try {
      final params = {
        'cmd': rawCmd,
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
        throw const PortalException(
          message: 'The portal storage server is temporarily offline (Connection Timeout). Please try again later.'
        );
      }

      if (js == null || js == false) {
        throw const PortalException(message: 'No stream URL returned');
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
          message: 'The portal is currently unable to play this item (nothing_to_play).'
        );
      } else if (errorCode.isNotEmpty && streamUrl.isEmpty) {
        throw PortalException(message: 'Server error: $errorCode');
      }

      if (streamUrl.isEmpty) {
        throw const PortalException(message: 'Resolved stream URL is empty');
      }

      _logger.mag('CREATE_VOD_RESOLVED', 'Resolved stream via Native API: $streamUrl');
      return await _resolveStreamUrl(streamUrl, movieId);
    } catch (e) {
      _logger.e('CREATE_VOD_FAILED', 'movieId=$movieId error=$e');
      if (e is PortalException) rethrow;
      throw PortalException(
        message: 'Could not resolve stream. Last error: $e'
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

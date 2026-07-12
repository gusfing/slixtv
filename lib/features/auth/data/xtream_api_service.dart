import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' hide Category;
import '../../../core/logging/app_logger.dart';
import 'models.dart' show Category, Channel;
import '../../movies/domain/models.dart' show VodItem;
import '../../series/domain/models.dart' show SeriesItem, Season, Episode;

class XtreamApiService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    sendTimeout: const Duration(seconds: 20),
  ));
  final AppLogger _logger = AppLogger();

  String? _portalUrl;
  String? _username;
  String? _password;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;
  String? get portalUrl => _portalUrl;
  String? get username => _username;
  String? get password => _password;

  void configure({
    required String portalUrl,
    required String username,
    required String password,
  }) {
    _portalUrl = _normalizeUrl(portalUrl);
    _username = username;
    _password = password;
  }

  void setAuthenticated(bool val) {
    _isAuthenticated = val;
  }

  void logout() {
    _isAuthenticated = false;
    _portalUrl = null;
    _username = null;
    _password = null;
  }

  String _normalizeUrl(String url) {
    url = url.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.toLowerCase().endsWith('/player_api.php')) {
      url = url.substring(0, url.length - '/player_api.php'.length);
    } else if (url.toLowerCase().endsWith('player_api.php')) {
      url = url.substring(0, url.length - 'player_api.php'.length);
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Future<Map<String, dynamic>> login(
    String portalUrl,
    String username,
    String password,
  ) async {
    final cleanUrl = _normalizeUrl(portalUrl);
    final requestUrl = '$cleanUrl/player_api.php';

    _logger.i('XTREAM', 'Attempting login to $requestUrl with user $username');

    try {
      final response = await _dio.get(
        requestUrl,
        queryParameters: {
          'username': username,
          'password': password,
        },
      );

      final data = response.data;
      Map<String, dynamic> parsedData;
      if (data is String) {
        parsedData = jsonDecode(data);
      } else if (data is Map<String, dynamic>) {
        parsedData = data;
      } else {
        throw Exception('Invalid response type: ${data.runtimeType}');
      }

      final userInfo = parsedData['user_info'];
      if (userInfo == null) {
        throw Exception('Invalid username or password');
      }

      final auth = userInfo['auth']?.toString() ?? '1';
      final status = userInfo['status']?.toString() ?? 'Active';

      if (auth == '0' || status.toLowerCase() == 'expired' || status.toLowerCase() == 'blocked') {
        throw Exception('Account is expired or blocked. Contact your provider.');
      }

      _portalUrl = cleanUrl;
      _username = username;
      _password = password;
      _isAuthenticated = true;

      return parsedData;
    } catch (e) {
      _logger.e('XTREAM', 'Login failed', error: e);
      rethrow;
    }
  }

  Future<void> setParentPassword(String newPassword) async {
    if (!_isAuthenticated) return;
    try {
      // Xtream API might not officially support this, but if a panel does, it's typically via this endpoint.
      await _dio.get(
        '$_portalUrl/player_api.php',
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'set_parent_password',
          'parent_password': newPassword,
        },
      );
    } catch (e) {
      _logger.e('XTREAM', 'Failed to update parent password on server', error: e);
    }
  }

  Future<List<Category>> getCategories(String action) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    try {
      final response = await _dio.get(
        requestUrl,
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': action,
        },
      );

      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;
      if (data is List) {
        return data.map((item) {
          final map = item as Map<String, dynamic>;
          return Category(
            id: map['category_id']?.toString() ?? '',
            title: map['category_name']?.toString() ?? '',
            alias: '',
          );
        }).toList();
      }
      return [];
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load categories: $action', error: e);
      return [];
    }
  }

  Future<List<Channel>> getLiveStreams({String? categoryId}) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    final params = {
      'username': _username,
      'password': _password,
      'action': 'get_live_streams',
      if (categoryId != null && categoryId.isNotEmpty && categoryId != '*' && categoryId != 'all')
        'category_id': categoryId,
    };

    try {
      final response = await _dio.get(requestUrl, queryParameters: params);
      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;

      if (data is List) {
        return data.map((item) {
          final map = item as Map<String, dynamic>;
          final streamId = map['stream_id']?.toString() ?? '';
          final streamIcon = map['stream_icon']?.toString() ?? '';
          return Channel(
            id: streamId,
            name: map['name']?.toString() ?? '',
            number: map['num']?.toString() ?? '',
            logo: streamIcon,
            cmd: '$_portalUrl/$_username/$_password/$streamId',
            categoryId: map['category_id']?.toString() ?? '',
            useHttpTmpLink: false,
            useLoadBalancing: false,
          );
        }).toList();
      }
      return [];
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load live streams', error: e);
      return [];
    }
  }

  Future<List<VodItem>> getVodStreams({String? categoryId, int page = 1, String? search}) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    final params = {
      'username': _username,
      'password': _password,
      'action': 'get_vod_streams',
      if (categoryId != null && categoryId.isNotEmpty && categoryId != '*' && categoryId != 'all')
        'category_id': categoryId,
    };

    try {
      final response = await _dio.get(requestUrl, queryParameters: params);
      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;

      if (data is List) {
        final List<VodItem> list = [];
        for (final item in data) {
          final map = item as Map<String, dynamic>;
          final streamId = map['stream_id']?.toString() ?? '';
          final streamIcon = map['stream_icon']?.toString() ?? '';
          final containerExt = map['container_extension']?.toString() ?? 'mp4';
          final name = map['name']?.toString() ?? '';

          if (search != null && search.isNotEmpty && !name.toLowerCase().contains(search.toLowerCase())) {
            continue;
          }

          list.add(VodItem(
            id: streamId,
            name: name,
            description: map['plot']?.toString() ?? '',
            poster: _processUrl(streamIcon),
            cmd: '$_portalUrl/movie/$_username/$_password/$streamId.$containerExt',
            categoryId: map['category_id']?.toString() ?? '',
            year: map['year']?.toString() ?? '',
            rating: map['rating']?.toString() ?? '',
            director: '',
            actors: '',
            genre: '',
            duration: '',
            hasFiles: true,
          ));
        }

        // Simulating pagination
        final int itemsPerPage = 15;
        final int startIndex = (page - 1) * itemsPerPage;
        if (startIndex >= list.length) return [];
        final int endIndex = (startIndex + itemsPerPage).clamp(0, list.length);
        return list.sublist(startIndex, endIndex);
      }
      return [];
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load VOD streams', error: e);
      return [];
    }
  }

  Future<List<SeriesItem>> getSeries({String? categoryId, int page = 1, String? search}) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    final params = {
      'username': _username,
      'password': _password,
      'action': 'get_series',
      if (categoryId != null && categoryId.isNotEmpty && categoryId != '*' && categoryId != 'all')
        'category_id': categoryId,
    };

    try {
      final response = await _dio.get(requestUrl, queryParameters: params);
      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;

      if (data is List) {
        final List<SeriesItem> list = [];
        for (final item in data) {
          final map = item as Map<String, dynamic>;
          final seriesId = map['series_id']?.toString() ?? '';
          final cover = map['cover']?.toString() ?? '';
          final name = map['name']?.toString() ?? '';

          if (search != null && search.isNotEmpty && !name.toLowerCase().contains(search.toLowerCase())) {
            continue;
          }

          list.add(SeriesItem(
            id: seriesId,
            name: name,
            description: map['plot']?.toString() ?? '',
            poster: _processUrl(cover),
            categoryId: map['category_id']?.toString() ?? '',
            year: map['releaseDate']?.toString() ?? '',
            rating: map['rating']?.toString() ?? '',
            genre: map['genre']?.toString() ?? '',
            director: map['director']?.toString() ?? '',
            actors: map['cast']?.toString() ?? '',
            seriesCount: '',
            cmd: '',
          ));
        }

        // Simulating pagination
        final int itemsPerPage = 15;
        final int startIndex = (page - 1) * itemsPerPage;
        if (startIndex >= list.length) return [];
        final int endIndex = (startIndex + itemsPerPage).clamp(0, list.length);
        return list.sublist(startIndex, endIndex);
      }
      return [];
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load series list', error: e);
      return [];
    }
  }

  Future<List<Season>> getSeriesInfo(String seriesId) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    try {
      final response = await _dio.get(
        requestUrl,
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_series_info',
          'series_id': seriesId,
        },
      );

      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;
      if (data is! Map<String, dynamic>) return [];

      final List<Season> seasonsList = [];
      final episodesMap = data['episodes'] as Map<String, dynamic>? ?? {};

      episodesMap.forEach((seasonKey, episodeList) {
        final seasonNum = int.tryParse(seasonKey) ?? 1;
        if (episodeList is List) {
          final List<Episode> mappedEpisodes = [];
          for (var i = 0; i < episodeList.length; i++) {
            final epJson = episodeList[i] as Map<String, dynamic>;
            final epId = epJson['id']?.toString() ?? '';
            final containerExt = epJson['container_extension']?.toString() ?? 'mp4';
            final infoJson = epJson['info'] as Map<String, dynamic>?;

            final epName = epJson['title']?.toString() ?? 'Episode ${i + 1}';
            final streamUrl = '$_portalUrl/series/$_username/$_password/$epId.$containerExt';

            mappedEpisodes.add(Episode(
              id: epId,
              name: epName,
              cmd: streamUrl,
              episodeNumber: int.tryParse(epJson['episode_num']?.toString() ?? '') ?? (i + 1),
              duration: infoJson?['duration']?.toString() ?? '',
              poster: _processUrl(infoJson?['movie_image']?.toString() ?? ''),
              description: infoJson?['plot']?.toString() ?? '',
            ));
          }
          seasonsList.add(Season(
            id: seasonKey,
            name: 'Season $seasonKey',
            seasonNumber: seasonNum,
            episodes: mappedEpisodes,
          ));
        }
      });

      seasonsList.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      return seasonsList;
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load series info for seriesId=$seriesId', error: e);
      return [];
    }
  }

  /// Fetches short EPG (current + upcoming) for a stream.
  Future<List<EpgModel>> getEPG(String streamId) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    try {
      final response = await _dio.get(
        requestUrl,
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_short_epg',
          'stream_id': streamId,
        },
      );

      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;
      if (data is Map<String, dynamic>) {
        final List<dynamic>? list = data['epg_listings'];
        if (list != null) {
          return list
              .map((item) => EpgModel.fromJson(item as Map<String, dynamic>))
              .where((e) => e.title.isNotEmpty)
              .toList();
        }
      }
      return [];
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load EPG for streamId=$streamId', error: e);
      return [];
    }
  }

  /// Fetches full EPG (past + current + future) for catch-up / archive playback.
  /// Uses get_simple_data_table which returns all programs for a given stream.
  Future<List<EpgModel>> getFullEPG(String streamId) async {
    if (!_isAuthenticated) return [];
    final requestUrl = '$_portalUrl/player_api.php';

    try {
      // Try get_simple_data_table first (returns full day EPG with past programs)
      final response = await _dio.get(
        requestUrl,
        queryParameters: {
          'username': _username,
          'password': _password,
          'action': 'get_simple_data_table',
          'stream_id': streamId,
        },
      );

      final dynamic data = response.data is String ? jsonDecode(response.data) : response.data;
      if (data is Map<String, dynamic>) {
        final List<dynamic>? list = data['epg_listings'];
        if (list != null && list.isNotEmpty) {
          return list
              .map((item) => EpgModel.fromJson(item as Map<String, dynamic>))
              .where((e) => e.title.isNotEmpty)
              .toList();
        }
      }

      // Fallback to get_short_epg if get_simple_data_table returns nothing
      _logger.i('XTREAM', 'get_simple_data_table returned empty, falling back to get_short_epg');
      return getEPG(streamId);
    } catch (e) {
      _logger.e('XTREAM', 'Failed to load full EPG for streamId=$streamId, falling back to short EPG', error: e);
      // Fallback to short EPG on error
      return getEPG(streamId);
    }
  }
  String _processUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    try {
      if (!url.startsWith('http')) return url;
      return Uri.encodeFull(url.replaceAll(r'\', '/'));
    } catch (_) {
      return url;
    }
  }
}

class EpgModel {
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;

  EpgModel({
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
  });

  static String _safeBase64Decode(String? encoded) {
    if (encoded == null || encoded.isEmpty) return '';
    try {
      // Add padding if needed
      String padded = encoded;
      final remainder = padded.length % 4;
      if (remainder > 0) {
        padded += '=' * (4 - remainder);
      }
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      // If base64 decode fails, return as-is (some servers send plain text)
      return encoded;
    }
  }

  factory EpgModel.fromJson(Map<String, dynamic> json) {
    DateTime parseTime(String? timeStr) {
      if (timeStr == null || timeStr.isEmpty) return DateTime.now();
      final ts = int.tryParse(timeStr);
      if (ts != null) return DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      return DateTime.tryParse(timeStr) ?? DateTime.now();
    }

    return EpgModel(
      title: _safeBase64Decode(json['title']?.toString()),
      description: _safeBase64Decode(json['description']?.toString()),
      startTime: parseTime(json['start']?.toString() ?? json['start_timestamp']?.toString()),
      endTime: parseTime(json['end']?.toString() ?? json['stop_timestamp']?.toString()),
    );
  }
}

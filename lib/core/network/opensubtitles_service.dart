import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../logging/app_logger.dart';

class OpenSubtitlesBlockedException implements Exception {
  final String message;
  OpenSubtitlesBlockedException(this.message);
  @override
  String toString() => message;
}

class OpenSubtitleFile {
  final int fileId;
  final String fileName;

  OpenSubtitleFile({required this.fileId, required this.fileName});

  factory OpenSubtitleFile.fromJson(Map<String, dynamic> json) {
    return OpenSubtitleFile(
      fileId: json['file_id'] as int,
      fileName: json['file_name']?.toString() ?? '',
    );
  }
}

class OpenSubtitleItem {
  final String id;
  final String language;
  final String release;
  final List<OpenSubtitleFile> files;

  OpenSubtitleItem({
    required this.id,
    required this.language,
    required this.release,
    required this.files,
  });

  factory OpenSubtitleItem.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString() ?? '';
    final attrs = json['attributes'] as Map<String, dynamic>? ?? {};
    final language = attrs['language']?.toString() ?? '';
    final release = attrs['release']?.toString() ?? '';
    final filesList = attrs['files'] as List? ?? [];
    final files = filesList
        .whereType<Map<String, dynamic>>()
        .map((f) => OpenSubtitleFile.fromJson(f))
        .toList();

    return OpenSubtitleItem(
      id: id,
      language: language,
      release: release,
      files: files,
    );
  }
}

class OpenSubtitlesService {
  final Dio _dio = Dio();
  final AppLogger _logger = AppLogger();
  String? _token;

  static const String baseUrl = 'https://api.opensubtitles.com/api/v1';
  static const String apiKey = 'CURSFvbU4GFEzpPPjq5ArxdRjALVxz66';
  static const String userAgent = 'iptv App v1.0';

  Map<String, String> get _baseHeaders => {
        'User-Agent': userAgent,
        'Api-Key': apiKey,
        'Accept': 'application/json',
      };

  Future<String?> login({String? username, String? password}) async {
    final user = username ?? 'sheriiptv';
    final pass = password ?? 'Abc@12345';
    
    _logger.mag('OPENSUB_AUTH', 'Logging in as $user');

    try {
      final response = await _dio.post(
        '$baseUrl/login',
        data: {
          'username': user,
          'password': pass,
        },
        options: Options(
          headers: {
            ..._baseHeaders,
            'Content-Type': 'application/json',
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      _logger.mag('OPENSUB_AUTH_RESP', 'Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          _token = data['token']?.toString();
          return _token;
        }
      } else {
        _logger.e('OPENSUB_AUTH', 'Login failed: ${response.data}');
      }
    } catch (e) {
      _logger.e('OPENSUB_AUTH', 'Connection error', error: e);
    }
    return null;
  }

  Future<List<OpenSubtitleItem>> search({
    required String query,
    String? languages,
    String? seasonNumber,
    String? episodeNumber,
    String? imdbId,
  }) async {
    _logger.mag('OPENSUB_SEARCH', 'Query: $query, Langs: $languages, Ep: $episodeNumber, IMDB: $imdbId');

    try {
      // OpenSubtitles expects integer numeric IMDB ID (e.g. 1375666 instead of tt1375666)
      String? cleanImdbId;
      if (imdbId != null && imdbId.isNotEmpty) {
        cleanImdbId = imdbId.replaceAll(RegExp(r'\D'), '');
      }

      final params = <String, dynamic>{
        'query': query,
        if (languages != null && languages.isNotEmpty) 'languages': languages,
        if (seasonNumber != null && seasonNumber.isNotEmpty) 'season_number': seasonNumber,
        if (episodeNumber != null && episodeNumber.isNotEmpty) 'episode_number': episodeNumber,
        if (cleanImdbId != null && cleanImdbId.isNotEmpty) 'imdb_id': cleanImdbId,
      };

      final response = await _dio.get(
        '$baseUrl/subtitles',
        queryParameters: params,
        options: Options(
          headers: _baseHeaders,
          responseType: ResponseType.plain, // Fetch plain first to inspect for ISP redirection block html
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      final String responseBody = response.data?.toString() ?? '';
      
      // Check for ISP blocks (Airtel redirects to court-orders page)
      if (responseBody.contains('airtel.in') || responseBody.contains('court-orders') || responseBody.contains('<iframe') || responseBody.contains('<html>')) {
        throw OpenSubtitlesBlockedException(
          'A connection block by your ISP was detected. Please change your DNS to 1.1.1.1 (Cloudflare) or 8.8.8.8 (Google), or use a VPN to search subtitles.'
        );
      }

      if (response.statusCode != 200) {
        throw Exception('OpenSubtitles returned server status code: ${response.statusCode}');
      }

      // Parse JSON from text
      var decodedData = response.data;
      if (decodedData is String) {
        try {
          decodedData = jsonDecode(decodedData);
        } catch (_) {}
      }

      if (decodedData is Map<String, dynamic>) {
        final list = decodedData['data'] as List? ?? [];
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => OpenSubtitleItem.fromJson(item))
            .toList();
      }
    } on OpenSubtitlesBlockedException {
      rethrow;
    } catch (e) {
      _logger.e('OPENSUB_SEARCH', 'Search failed', error: e);
      // Double check if error is likely an ISP block / dns failure
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('handshake_failure') || errStr.contains('sslexception') || errStr.contains('connection refused') || errStr.contains('connection closed')) {
        throw OpenSubtitlesBlockedException(
          'Could not establish secure connection to OpenSubtitles (ISP block suspected). Try changing your DNS to 1.1.1.1 or using a VPN.'
        );
      }
      throw Exception('Subtitles search failed. Please try again.');
    }
    return [];
  }

  Future<String> download(int fileId, {String? username, String? password}) async {
    _logger.mag('OPENSUB_DOWNLOAD', 'File ID: $fileId');

    // 1. Authenticate if no token cached
    if (_token == null) {
      await login(username: username, password: password);
    }
    
    if (_token == null) {
      throw Exception('Authentication failed. Please verify your OpenSubtitles username and password in settings.');
    }

    try {
      // 2. Request download link
      final response = await _dio.post(
        '$baseUrl/download',
        data: {
          'file_id': fileId,
        },
        options: Options(
          headers: {
            ..._baseHeaders,
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_token',
          },
          validateStatus: (status) => status != null && status < 600,
        ),
      );

      if (response.statusCode != 200) {
        _logger.e('OPENSUB_DOWNLOAD', 'Download request failed: ${response.data}');
        // If 401 unauthorized, retry once by clearing token
        if (response.statusCode == 401) {
          _token = null;
          return download(fileId, username: username, password: password);
        }
        throw Exception('Server error during subtitle download request: ${response.statusCode}');
      }

      final data = response.data;
      String? downloadLink;
      if (data is Map<String, dynamic>) {
        downloadLink = data['link']?.toString() ?? data['data']?['link']?.toString();
      }

      if (downloadLink == null || downloadLink.isEmpty) {
        throw Exception('Download link was not provided by server.');
      }

      _logger.mag('OPENSUB_DOWNLOAD_LINK', 'Link: $downloadLink');

      // 3. Download the actual file bytes
      final fileResponse = await _dio.get(
        downloadLink,
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );

      final bytes = fileResponse.data as List<int>;
      
      // 4. Save to temporary directory
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/opensub_$fileId.srt');
      await file.writeAsBytes(bytes);
      
      _logger.mag('OPENSUB_DOWNLOAD_SUCCESS', 'Saved: ${file.path}');
      return file.path;
    } catch (e) {
      _logger.e('OPENSUB_DOWNLOAD', 'Download failed', error: e);
      rethrow;
    }
  }
}

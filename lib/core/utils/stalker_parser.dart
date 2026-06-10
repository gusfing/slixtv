import '../network/api_client.dart';

/// Centralized utility for handling Stalker Middleware protocol anomalies and parsing edge cases.
class StalkerParser {
  /// Some Stalker portals serialize empty arrays as `[]` but populated lists as an
  /// associative map like `{"0": {...}, "1": {...}}` instead of standard JSON arrays `[...]`.
  /// This method safely normalizes those into a standard `List`.
  static List<dynamic> extractList(dynamic rawData) {
    if (rawData == null || rawData == false) return [];
    
    if (rawData is List) return rawData;
    
    if (rawData is Map) {
      // If it's a map wrapped inside `{"data": ... }`, unwrap it.
      if (rawData.containsKey('data')) {
        return extractList(rawData['data']);
      }
      
      // If it's an associative map (e.g. "0": {...}), extract the values.
      final values = rawData.values.toList();
      if (values.isNotEmpty && (values.first is Map || values.first is List)) {
        return values;
      }
    }
    
    return [];
  }

  /// Extracts the most STB-compatible playback command from a combination of the
  /// item's list data (ordered_list) and its detailed info response (get_info).
  /// Priorities:
  /// 1. orderedItem['cmd']
  /// 2. infoResponse['js']['cmd']
  /// 3. infoResponse['js']['files'][0]['cmd']
  /// 4. Alternate fields: ffmpeg_cmd, stream_url, play_url, file, url
  static String? extractBestPlaybackCmd(dynamic orderedItem, dynamic infoResponse) {
    String? bestCmd;
    String orderedListCmd = '';
    String infoCmd = '';
    String filesCmd = '';

    String? checkMap(Map map) {
      final fields = [
        'cmd', 'ffmpeg_cmd', 'stream_cmd', 'stream_url', 'play_url', 'url', 'file', 'video_url',
        'movie_link', 'movie_url', 'path', 'uri', 'link'
      ];
      for (final f in fields) {
        final val = map[f]?.toString();
        if (val != null && val.isNotEmpty) {
          return val;
        }
      }
      return null;
    }

    // 1. Check ordered list item
    if (orderedItem is Map) {
      orderedListCmd = checkMap(orderedItem) ?? '';
      if (orderedListCmd.isNotEmpty) bestCmd = orderedListCmd;
    }

    if (infoResponse != null && infoResponse is Map) {
      dynamic js = infoResponse['js'];
      if (js != null && js is Map) {
        // 2. Check root of get_info 'js'
        infoCmd = checkMap(js) ?? '';
        if (bestCmd == null && infoCmd.isNotEmpty) bestCmd = infoCmd;

        // 3. Check 'info' map inside 'js'
        if (infoCmd.isEmpty && js['info'] is Map) {
          infoCmd = checkMap(js['info']) ?? '';
          if (bestCmd == null && infoCmd.isNotEmpty) bestCmd = infoCmd;
        }

        // 4. Check 'files' array inside 'js'
        if (js['files'] != null) {
          final filesList = extractList(js['files']);
          if (filesList.isNotEmpty && filesList.first is Map) {
            filesCmd = checkMap(filesList.first) ?? '';
            if (bestCmd == null && filesCmd.isNotEmpty) bestCmd = filesCmd;
          }
        }
      }
    }

    // Capture extraction diagnostics
    final logMap = {
      'orderedListCmd': orderedListCmd,
      'infoCmd': infoCmd,
      'filesCmd': filesCmd,
      'chosenCmd': bestCmd ?? '',
    };
    
    // Using a simple print for console, but ideally this should be tied to AppLogger
    // if StalkerParser has access to it.
    print('CMD_EXTRACTION_DIAGNOSTICS: $logMap');

    return bestCmd;
  }
}

class PosterResolver {
  /// Examines a Stalker JSON object and rigorously extracts the highest quality poster URL.
  /// Checks: `cover_big` > `cover` > `poster` > `screenshot_uri` > `icon` > `logo` > `image`.
  /// Resolves any relative paths (e.g., `/misc/logo.jpg`) against the authenticated portal base URL.
  static String resolve(Map<String, dynamic> json, ApiClient client) {
    final fields = [
      'cover_big',
      'cover',
      'poster',
      'screenshot_uri',
      'icon',
      'logo',
      'image'
    ];

    String rawPoster = '';
    for (final field in fields) {
      final value = json[field]?.toString();
      if (value != null && value.isNotEmpty && value != 'null') {
        rawPoster = value;
        break;
      }
    }

    if (rawPoster.isEmpty) return '';

    return client.resolveUrl(rawPoster);
  }
}

class UrlNormalizer {
  /// Basic normalization for legacy components. Just strips player directives.
  static String normalize(String url, String? portalUrl) {
    return stripPlayerDirectives(url);
  }

  /// Stalker portals often return a `cmd` meant for their proprietary STB player.
  /// For instance: `ffmpeg http://live.domain.com/stream` or `ffrt3 http://...`
  /// This strips all those prefixes to yield a clean HTTP/RTSP URL.
  static String stripPlayerDirectives(String url) {
    url = url.trim();
    if (url.isEmpty) return url;

    // Requirement 5: Remove ffmpeg, ffrt3, auto, etc.
    const prefixes = ['ffmpeg ', 'ffrt3 ', 'ffrt ', 'auto ', '/ch/'];
    for (final p in prefixes) {
      if (url.toLowerCase().startsWith(p.toLowerCase())) {
        url = url.substring(p.length).trim();
        break; // Only strip one prefix
      }
    }

    // Attempt to strip anything before http:// if present and the prefix above didn't catch it
    final httpIdx = url.indexOf('http');
    if (httpIdx > 0 && !url.substring(0, httpIdx).contains('://')) {
      url = url.substring(httpIdx);
    }

    // Space-separated URLs: some portals send "http://... http://fallback..."
    // We take the first valid URL
    if (url.contains(' ')) {
      for (final part in url.split(' ')) {
        if (part.startsWith('http') || part.startsWith('rtsp') || part.startsWith('rtp')) {
          url = part;
          break;
        }
      }
    }

    return url.trim();
  }
}

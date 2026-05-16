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

import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/utils/response_parser.dart';

class StreamResolutionException implements Exception {
  final String message;
  StreamResolutionException(this.message);
  @override
  String toString() => message;
}

class StreamResolver {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;

  StreamResolver({
    required this.dio,
    required this.sessionManager,
    required this.deviceIdentity,
  });

  static const List<String> prefixesToStrip = [
    'ffmpeg ',
    'ffrt3 ',
    'ffrt ',
    'auto ',
    '/ch/'
  ];

  String _stripPrefixes(String cmd) {
    String cleaned = cmd;
    bool changed;
    do {
      changed = false;
      for (final prefix in prefixesToStrip) {
        if (cleaned.startsWith(prefix)) {
          cleaned = cleaned.substring(prefix.length).trim();
          changed = true;
        }
      }
    } while (changed);
    return cleaned;
  }

  String _extractHttpUrl(String mixedString) {
    int index = mixedString.indexOf('http');
    if (index != -1) {
      return mixedString.substring(index).trim();
    }
    return mixedString;
  }

  String _selectFirstValidUrl(String spaceSeparatedUrls) {
    final urls = spaceSeparatedUrls.split(' ');
    for (final url in urls) {
      if (url.startsWith('http') || url.startsWith('rtsp')) {
        return url;
      }
    }
    return urls.isNotEmpty ? urls.first : '';
  }

  String _replaceLocalhost(String url) {
    if (sessionManager.portalBaseUrl == null) return url;
    
    final uri = Uri.tryParse(sessionManager.portalBaseUrl!);
    if (uri == null) return url;

    return url
        .replaceAll('localhost', uri.host)
        .replaceAll('127.0.0.1', uri.host);
  }

  Future<String> resolveStreamUrl(String type, String cmd, {String? series}) async {
    // 1. Pre-process the command
    String processedCmd = _stripPrefixes(cmd);
    processedCmd = _extractHttpUrl(processedCmd);
    processedCmd = _selectFirstValidUrl(processedCmd);
    processedCmd = _replaceLocalhost(processedCmd);

    // 2. Direct HTTP bypass
    if (processedCmd.startsWith('http://') || processedCmd.startsWith('https://')) {
      if (!processedCmd.contains('localhost') && !processedCmd.contains('127.0.0.1')) {
        return processedCmd;
      }
    }

    if (processedCmd.startsWith('udp://') || processedCmd.startsWith('rtsp://')) {
      // Log warning for unsupported
      // Using generic print since logger is in Task 15
      print('Warning: Unsupported protocol scheme: $processedCmd');
    }

    // 3. Send create_link request
    if (sessionManager.portalBaseUrl == null || sessionManager.portalEndpoint == null) {
      throw StreamResolutionException('Portal endpoint not set');
    }

    final url = '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
    final queryParams = {
      'type': type,
      'action': 'create_link',
      'cmd': cmd, // Original cmd is usually sent
      'forced_storage': 'undefined',
      'disable_ad': '0',
      'JsHttpRequest': '1-xml',
    };
    if (series != null) {
      queryParams['series'] = series;
    }

    final headers = MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );

    try {
      final response = await dio.get(
        url,
        queryParameters: queryParams,
        options: Options(headers: headers),
      );

      final parsed = ResponseParser.parseResponse(response);
      final js = parsed['js'];
      final rawText = parsed['text']?.toString() ?? '';
      final isTimeout = rawText.contains('Connection timeout') || rawText.contains('Failed to connect');

      if (isTimeout) {
        throw StreamResolutionException(
          'The portal storage server is temporarily offline (Connection Timeout). Please try again later.'
        );
      }

      if (js == false || js == null) {
        throw StreamResolutionException('Failed to get link data from portal');
      }

      if (js is Map && js.containsKey('error')) {
        if (js['error'] == 'nothing_to_play') {
          throw StreamResolutionException('The portal is currently unable to play this item (nothing_to_play).');
        }
        throw StreamResolutionException('Portal error: ${js['error']}');
      }

      String finalUrl = '';
      if (js is Map) {
        if (js.containsKey('cmd')) {
          finalUrl = js['cmd'].toString();
        } else if (js.containsKey('url')) {
          finalUrl = js['url'].toString();
        }
      } else if (js is String) {
        finalUrl = js;
      }

      if (finalUrl.isEmpty) {
        throw StreamResolutionException('Empty stream URL returned');
      }

      // 4. Post-process the result
      finalUrl = _stripPrefixes(finalUrl);
      finalUrl = _extractHttpUrl(finalUrl);
      finalUrl = _selectFirstValidUrl(finalUrl);
      finalUrl = _replaceLocalhost(finalUrl);

      // 5. Dio automatically follows redirects up to a certain limit
      // If we need manual redirect following, we would do it here using dio.options.followRedirects = false
      // For now, we assume Dio handles the 5 redirects natively.

      return finalUrl;

    } on DioException catch (e) {
      throw StreamResolutionException('Network error resolving stream: ${e.message}');
    }
  }
}

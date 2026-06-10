import 'package:dio/dio.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';

class PortalDiscoveryService {
  final Dio dio;
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;

  PortalDiscoveryService({
    required this.dio,
    required this.sessionManager,
    required this.deviceIdentity,
  });

  static const List<String> candidatePaths = [
    '/server/load.php',
    '/stalker_portal/server/load.php',
    '/portal.php',
    '/load.php',
  ];

  static const String defaultPath = '/stalker_portal/server/load.php';

  String _normalizeUrl(String url) {
    String normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<String> discoverEndpoint(String inputUrl) async {
    final String baseUrl = _normalizeUrl(inputUrl);
    final headers = MagHeaders.buildHeaders(
      deviceIdentity: deviceIdentity,
      sessionManager: sessionManager,
    );

    for (final path in candidatePaths) {
      try {
        final url = '$baseUrl$path';
        final response = await dio.get(
          url,
          queryParameters: {
            'type': 'stb',
            'action': 'handshake',
          },
          options: Options(
            connectTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
            headers: headers,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          // Check if response contains 'js' field (could be parsed JSON or raw string)
          bool isValid = false;
          if (response.data is Map && response.data.containsKey('js')) {
            isValid = true;
          } else if (response.data is String && response.data.contains('"js"')) {
            isValid = true;
          }

          if (isValid) {
            sessionManager.setPortalInfo(baseUrl, path);
            return path;
          }
        }
      } catch (e) {
        // Ignore timeouts or network errors for candidates, try next
      }
    }

    // Default fallback
    sessionManager.setPortalInfo(baseUrl, defaultPath);
    return defaultPath;
  }
}

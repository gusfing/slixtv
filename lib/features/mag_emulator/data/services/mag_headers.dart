import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';

class MagHeaders {
  static const String defaultUserAgent =
      'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3';

  static Map<String, String> buildHeaders({
    required DeviceIdentity deviceIdentity,
    required SessionManager sessionManager,
  }) {
    final Map<String, String> headers = {
      'User-Agent': defaultUserAgent,
      'X-User-Agent': 'Model: MAG250; Link: WiFi',
      'Accept': '*/*',
      'Accept-Language': 'en_US',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
    };

    if (sessionManager.portalBaseUrl != null && sessionManager.portalEndpoint != null) {
      headers['Referer'] = '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
    } else if (sessionManager.portalBaseUrl != null) {
      headers['Referer'] = '${sessionManager.portalBaseUrl}/';
    }

    // Cookie header with MAC address and timezone
    headers['Cookie'] = 'mac=${Uri.encodeComponent(deviceIdentity.mac)}; timezone=Europe/Kyiv';

    final bearerToken = sessionManager.getBearerToken();
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
    }

    return headers;
  }
}

import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';

class PlayerHeadersService {
  final SessionManager sessionManager;
  final DeviceIdentity deviceIdentity;

  PlayerHeadersService({
    required this.sessionManager,
    required this.deviceIdentity,
  });

  Map<String, String> getPlayerHeaders() {
    final Map<String, String> headers = {
      'User-Agent': 'Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3',
      'X-User-Agent': 'Model: MAG250; Link: WiFi',
    };

    if (sessionManager.portalBaseUrl != null && sessionManager.portalEndpoint != null) {
      headers['Referer'] = '${sessionManager.portalBaseUrl}${sessionManager.portalEndpoint}';
    } else if (sessionManager.portalBaseUrl != null) {
      headers['Referer'] = '${sessionManager.portalBaseUrl}/';
    }

    final Map<String, String> cookies = {
      'mac': Uri.encodeComponent(deviceIdentity.mac),
      'stb_lang': 'en',
      'timezone': 'Europe/Kyiv',
    };
    if (deviceIdentity.serialNumber.isNotEmpty) {
      cookies['sn'] = Uri.encodeComponent(deviceIdentity.serialNumber);
    }

    final bearerToken = sessionManager.getBearerToken();
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
      cookies['token'] = bearerToken;
    }

    headers['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    // Generic print for now. Will be replaced by Logger later.
    print('Injecting Player Headers:');
    headers.forEach((key, value) {
      if (key == 'Authorization' && value.length > 16) {
        print('  $key: ${value.substring(0, 16)}...');
      } else {
        print('  $key: $value');
      }
    });

    return headers;
  }
}

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

    // Cookie header with MAC address, language, timezone, serial, and token
    final Map<String, String> cookies = {
      'mac': Uri.encodeComponent(deviceIdentity.mac),
      'stb_lang': 'en',
      'timezone': 'Europe/Kyiv',
    };
    if (deviceIdentity.serialNumber.isNotEmpty) {
      cookies['sn'] = Uri.encodeComponent(deviceIdentity.serialNumber);
    }
    if (deviceIdentity.deviceId.isNotEmpty) {
      cookies['device_id'] = deviceIdentity.deviceId;
      headers['device_id'] = deviceIdentity.deviceId;
    }
    if (deviceIdentity.deviceId2.isNotEmpty) {
      cookies['device_id2'] = deviceIdentity.deviceId2;
      headers['device_id2'] = deviceIdentity.deviceId2;
    }
    if (deviceIdentity.signature.isNotEmpty) {
      cookies['signature'] = deviceIdentity.signature;
      headers['signature'] = deviceIdentity.signature;
    }

    final bearerToken = sessionManager.getBearerToken();
    if (bearerToken != null && bearerToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $bearerToken';
      cookies['token'] = bearerToken;
    }

    headers['Cookie'] = cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

    return headers;
  }
}

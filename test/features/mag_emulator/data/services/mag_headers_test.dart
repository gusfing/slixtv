import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_headers.dart';

void main() {
  group('MagHeaders', () {
    late DeviceIdentity deviceIdentity;
    late SessionManager sessionManager;

    setUp(() {
      deviceIdentity = DeviceIdentity.generate();
      sessionManager = SessionManager();
      sessionManager.clearSession(); // Ensure clean state
    });

    test('should build default headers correctly', () {
      final headers = MagHeaders.buildHeaders(
        deviceIdentity: deviceIdentity,
        sessionManager: sessionManager,
      );

      expect(headers['User-Agent'], startsWith('Mozilla/5.0 (QtEmbedded;'));
      expect(headers['X-User-Agent'], 'Model: MAG250; Link: WiFi');
      expect(headers['Accept'], '*/*');
      expect(headers['Accept-Language'], 'en_US');
      expect(headers['Accept-Encoding'], 'gzip, deflate');
      expect(headers['Connection'], 'keep-alive');
      
      // Cookie should contain MAC address
      expect(headers['Cookie'], contains('mac=${Uri.encodeComponent(deviceIdentity.mac)}'));
      expect(headers['Cookie'], contains('timezone=Europe/Kyiv'));

      // No authorization token by default
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers.containsKey('Referer'), isFalse);
    });

    test('should include Authorization if token is present', () {
      sessionManager.setBearerToken('test_token');
      
      final headers = MagHeaders.buildHeaders(
        deviceIdentity: deviceIdentity,
        sessionManager: sessionManager,
      );

      expect(headers['Authorization'], 'Bearer test_token');
    });

    test('should include Referer if portal info is present', () {
      sessionManager.setPortalInfo('http://portal.com', '/load.php');
      
      final headers = MagHeaders.buildHeaders(
        deviceIdentity: deviceIdentity,
        sessionManager: sessionManager,
      );

      expect(headers['Referer'], 'http://portal.com/load.php');
    });
  });
}

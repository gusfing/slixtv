import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/player_headers_service.dart';

void main() {
  group('PlayerHeadersService', () {
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late PlayerHeadersService service;

    setUp(() {
      sessionManager = SessionManager();
      sessionManager.clearSession();
      deviceIdentity = DeviceIdentity.generate();
      
      service = PlayerHeadersService(
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );
    });

    test('should generate headers without token if not authenticated', () {
      final headers = service.getPlayerHeaders();
      
      expect(headers['User-Agent'], startsWith('Mozilla/5.0 (QtEmbedded;'));
      expect(headers['X-User-Agent'], 'Model: MAG250; Link: WiFi');
      expect(headers.containsKey('Authorization'), isFalse);
      expect(headers['Cookie'], contains(Uri.encodeComponent(deviceIdentity.mac)));
    });

    test('should include Authorization header if token exists', () {
      sessionManager.setBearerToken('my_test_token');
      final headers = service.getPlayerHeaders();
      
      expect(headers['Authorization'], 'Bearer my_test_token');
    });

    test('should include Referer if portal info exists', () {
      sessionManager.setPortalInfo('http://portal.com', '/load.php');
      final headers = service.getPlayerHeaders();
      
      expect(headers['Referer'], 'http://portal.com/load.php');
    });
  });
}

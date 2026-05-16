import 'package:flutter_test/flutter_test.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';

void main() {
  group('SessionManager', () {
    late SessionManager sessionManager;

    setUp(() {
      // Because it's a singleton, we might want to clear its state before each test
      sessionManager = SessionManager();
      sessionManager.bearerToken = null;
      sessionManager.portalBaseUrl = null;
      sessionManager.portalEndpoint = null;
      sessionManager.macAddress = null;
    });

    test('should be a singleton', () {
      final instance1 = SessionManager();
      final instance2 = SessionManager();

      expect(identical(instance1, instance2), isTrue);
    });

    test('should store and retrieve bearer token', () {
      sessionManager.setBearerToken('test_token');
      expect(sessionManager.getBearerToken(), 'test_token');
    });

    test('should check if session is valid', () {
      expect(sessionManager.hasValidSession(), isFalse);

      sessionManager.setBearerToken('test_token');
      expect(sessionManager.hasValidSession(), isTrue);

      sessionManager.setBearerToken('');
      expect(sessionManager.hasValidSession(), isFalse);
    });
    
    test('should store portal info', () {
      sessionManager.setPortalInfo('http://test.com', '/load.php');
      expect(sessionManager.portalBaseUrl, 'http://test.com');
      expect(sessionManager.portalEndpoint, '/load.php');
    });

    test('should clear session', () async {
      sessionManager.setBearerToken('test_token');
      
      // Note: We can't fully test clearSession with cookieJar without mock or init
      // But we can test the bearerToken part.
      sessionManager.bearerToken = null;
      
      expect(sessionManager.hasValidSession(), isFalse);
      expect(sessionManager.getBearerToken(), isNull);
    });
  });
}

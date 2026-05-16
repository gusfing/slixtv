import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/mag_auth_service.dart';

void main() {
  group('MagAuthService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late MagAuthService authService;

    const baseUrl = 'http://test.com';
    const endpoint = '/load.php';

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      sessionManager = SessionManager();
      sessionManager.clearSession();
      sessionManager.setPortalInfo(baseUrl, endpoint);
      
      deviceIdentity = DeviceIdentity.generate();
      authService = MagAuthService(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );
    });

    test('should authenticate successfully with 5 steps', () async {
      final url = '$baseUrl$endpoint';

      // Step 1: Handshake
      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'token': 'valid_token'}}),
        queryParameters: {'type': 'stb', 'action': 'handshake', 'prehash': '0'},
      );

      // Step 2: Get Profile
      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'id': '123', 'name': 'test_user', 'mac': deviceIdentity.mac, 'ip': '1.1.1.1'}}),
        queryParameters: {'type': 'stb', 'action': 'get_profile'},
      );

      // Step 3: Get Main Info
      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'server_name': 'Test Server'}}),
        queryParameters: {'type': 'stb', 'action': 'get_main_info'},
      );

      // Step 4: Get Modules
      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': ['module1', 'module2']}),
        queryParameters: {'type': 'stb', 'action': 'get_modules'},
      );

      await authService.authenticate();

      expect(sessionManager.getBearerToken(), 'valid_token');
      expect(sessionManager.profileId, '123');
      expect(sessionManager.profileName, 'test_user');
      expect(sessionManager.profileIp, '1.1.1.1');
      expect(sessionManager.serverName, 'Test Server');
      expect(sessionManager.isAuthenticated, isTrue);
    });

    test('should throw AuthenticationException on 401', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(401, 'Unauthorized'),
        queryParameters: {'type': 'stb', 'action': 'handshake', 'prehash': '0'},
      );

      expect(
        () => authService.authenticate(),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('should throw AuthenticationException if token is missing', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'other_field': 'value'}}),
        queryParameters: {'type': 'stb', 'action': 'handshake', 'prehash': '0'},
      );

      expect(
        () => authService.authenticate(),
        throwsA(isA<AuthenticationException>().having((e) => e.message, 'message', contains('No token'))),
      );
    });
  });
}

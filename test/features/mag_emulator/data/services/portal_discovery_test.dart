import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/portal_discovery.dart';

void main() {
  group('PortalDiscoveryService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late PortalDiscoveryService service;

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      sessionManager = SessionManager();
      sessionManager.clearSession();
      deviceIdentity = DeviceIdentity.generate();
      
      service = PortalDiscoveryService(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );
    });

    test('should discover correct endpoint when first candidate succeeds', () async {
      const baseUrl = 'http://test.com';
      dioAdapter.onGet(
        '$baseUrl/server/load.php',
        (server) => server.reply(200, {'js': {'token': 'test'}}),
        queryParameters: {'type': 'stb', 'action': 'handshake'},
      );

      final endpoint = await service.discoverEndpoint(baseUrl);

      expect(endpoint, '/server/load.php');
      expect(sessionManager.portalBaseUrl, baseUrl);
      expect(sessionManager.portalEndpoint, '/server/load.php');
    });

    test('should fallback to default when all candidates fail', () async {
      const baseUrl = 'http://test.com';
      
      // All paths fail
      for (final path in PortalDiscoveryService.candidatePaths) {
        dioAdapter.onGet(
          '$baseUrl$path',
          (server) => server.reply(404, 'Not found'),
          queryParameters: {'type': 'stb', 'action': 'handshake'},
        );
      }

      final endpoint = await service.discoverEndpoint(baseUrl);

      expect(endpoint, PortalDiscoveryService.defaultPath);
      expect(sessionManager.portalBaseUrl, baseUrl);
      expect(sessionManager.portalEndpoint, PortalDiscoveryService.defaultPath);
    });

    test('should normalize input URL correctly', () async {
      // Testing with missing http:// and trailing slash
      const inputUrl = 'test.com/';
      const normalizedBaseUrl = 'http://test.com';
      
      dioAdapter.onGet(
        '$normalizedBaseUrl/server/load.php',
        (server) => server.reply(200, {'js': {'token': 'test'}}),
        queryParameters: {'type': 'stb', 'action': 'handshake'},
      );

      final endpoint = await service.discoverEndpoint(inputUrl);

      expect(endpoint, '/server/load.php');
      expect(sessionManager.portalBaseUrl, normalizedBaseUrl);
    });
  });
}

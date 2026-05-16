import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/live_tv_service.dart';

void main() {
  group('LiveTvService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late StreamResolver streamResolver;
    late LiveTvService liveTvService;

    const baseUrl = 'http://portal.com';
    const endpoint = '/load.php';

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      sessionManager = SessionManager();
      sessionManager.clearSession();
      sessionManager.setPortalInfo(baseUrl, endpoint);
      deviceIdentity = DeviceIdentity.generate();
      
      streamResolver = StreamResolver(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );

      liveTvService = LiveTvService(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
        streamResolver: streamResolver,
      );
    });

    test('should fetch categories successfully', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
            {'id': '1', 'title': 'News'},
            {'id': '2', 'title': 'Sports'}
          ]
        }),
        queryParameters: {'type': 'itv', 'action': 'get_genres'},
      );

      final categories = await liveTvService.getCategories();
      
      expect(categories.length, 2);
      expect(categories[0].title, 'News');
      expect(categories[1].title, 'Sports');
    });

    test('should handle js as map with data array for categories', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': {
            'data': [
              {'id': '1', 'title': 'News'}
            ]
          }
        }),
        queryParameters: {'type': 'itv', 'action': 'get_genres'},
      );

      final categories = await liveTvService.getCategories();
      
      expect(categories.length, 1);
      expect(categories[0].title, 'News');
    });

    test('should fetch channels successfully', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
            {'id': '1', 'name': 'Channel 1', 'number': '1', 'logo': '/logo1.png', 'cmd': 'ch_1'}
          ]
        }),
        queryParameters: {'type': 'itv', 'action': 'get_all_channels'},
      );

      final channels = await liveTvService.getAllChannels();
      
      expect(channels.length, 1);
      expect(channels[0].name, 'Channel 1');
      expect(channels[0].logo, 'http://portal.com/logo1.png');
    });
  });
}

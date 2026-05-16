import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/series_service.dart';

void main() {
  group('SeriesService', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late StreamResolver streamResolver;
    late SeriesService seriesService;

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

      seriesService = SeriesService(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
        streamResolver: streamResolver,
      );
    });

    test('should fetch series categories', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
            {'id': '1', 'title': 'Drama'},
          ]
        }),
        queryParameters: {'type': 'series', 'action': 'get_categories'},
      );

      final categories = await seriesService.getCategories();
      
      expect(categories.length, 1);
      expect(categories[0].title, 'Drama');
    });

    test('should parse complex season data format 1', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
            {
              'season_number': '1',
              'series': [
                {'id': '101', 'title': 'Ep 1', 'cmd': 'cmd1'}
              ]
            }
          ]
        }),
        queryParameters: {'type': 'series', 'action': 'get_ordered_list', 'series_id': '1'},
      );

      final seasons = await seriesService.getSeasonData('1');
      
      expect(seasons.length, 1);
      expect(seasons[0].seasonNumber, '1');
      expect(seasons[0].episodes.length, 1);
      expect(seasons[0].episodes[0].name, 'Ep 1');
    });

    test('should parse complex season data format 2 (flat)', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {
          'js': [
             {'id': '101', 'title': 'Ep 1', 'season': '2', 'cmd': 'cmd1'}
          ]
        }),
        queryParameters: {'type': 'series', 'action': 'get_ordered_list', 'series_id': '1'},
      );

      final seasons = await seriesService.getSeasonData('1');
      
      expect(seasons.length, 1);
      expect(seasons[0].seasonNumber, '2');
      expect(seasons[0].episodes.length, 1);
      expect(seasons[0].episodes[0].season, '2');
    });

    test('should create playback link with series_id', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'cmd': 'http://backend.com/ep.ts'}}),
        queryParameters: {'type': 'series', 'action': 'create_link', 'cmd': 'cmd1', 'series': '123'},
      );

      final link = await seriesService.createPlaybackLink('cmd1', '123');
      expect(link, 'http://backend.com/ep.ts');
    });
  });
}

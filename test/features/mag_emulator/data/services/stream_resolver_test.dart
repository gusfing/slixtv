import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:slix_iptv/features/mag_emulator/data/models/device_identity.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/session_manager.dart';
import 'package:slix_iptv/features/mag_emulator/data/services/stream_resolver.dart';

void main() {
  group('StreamResolver', () {
    late Dio dio;
    late DioAdapter dioAdapter;
    late SessionManager sessionManager;
    late DeviceIdentity deviceIdentity;
    late StreamResolver resolver;

    const baseUrl = 'http://portal.com';
    const endpoint = '/load.php';

    setUp(() {
      dio = Dio();
      dioAdapter = DioAdapter(dio: dio);
      sessionManager = SessionManager();
      sessionManager.clearSession();
      sessionManager.setPortalInfo(baseUrl, endpoint);
      deviceIdentity = DeviceIdentity.generate();
      
      resolver = StreamResolver(
        dio: dio,
        sessionManager: sessionManager,
        deviceIdentity: deviceIdentity,
      );
    });

    test('should bypass create_link for direct HTTP URLs', () async {
      final result = await resolver.resolveStreamUrl('itv', 'http://direct.stream.com/video.m3u8');
      expect(result, 'http://direct.stream.com/video.m3u8');
    });

    test('should strip prefixes correctly', () async {
      // Internal method test via resolveStreamUrl for a URL that would normally trigger bypass
      final result = await resolver.resolveStreamUrl('itv', 'ffmpeg ffrt http://direct.stream.com/video.m3u8');
      expect(result, 'http://direct.stream.com/video.m3u8');
    });

    test('should replace localhost with portal host', () async {
      final result = await resolver.resolveStreamUrl('itv', 'http://localhost/video.m3u8');
      expect(result, 'http://portal.com/video.m3u8');
    });

    test('should extract HTTP url from mixed string', () async {
      final result = await resolver.resolveStreamUrl('itv', 'some junk here http://direct.stream.com/video.m3u8');
      expect(result, 'http://direct.stream.com/video.m3u8');
    });

    test('should call create_link and resolve result', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'cmd': 'ffmpeg http://backend.com/stream.ts'}}),
        queryParameters: {'type': 'itv', 'action': 'create_link', 'cmd': 'ch_123'},
      );

      final result = await resolver.resolveStreamUrl('itv', 'ch_123');
      expect(result, 'http://backend.com/stream.ts');
    });

    test('should throw specific exception for nothing_to_play', () async {
      final url = '$baseUrl$endpoint';

      dioAdapter.onGet(
        url,
        (server) => server.reply(200, {'js': {'error': 'nothing_to_play'}}),
        queryParameters: {'type': 'itv', 'action': 'create_link', 'cmd': 'ch_123'},
      );

      expect(
        () => resolver.resolveStreamUrl('itv', 'ch_123'),
        throwsA(isA<StreamResolutionException>().having((e) => e.message, 'message', contains('Nothing to play'))),
      );
    });
  });
}
